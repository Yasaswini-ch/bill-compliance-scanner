/// The compliance rule engine.
///
/// Pure Dart with zero Flutter dependencies: data in, data out. Every check
/// follows one overriding principle — **a check that cannot be evaluated is
/// skipped and recorded as a note, never guessed into a violation.** A false
/// accusation against a restaurant is a far worse failure than a missed one.
library;

import 'dart:math' as math;

import '../models/bill.dart';
import '../models/compliance_flag.dart';
import '../models/money.dart';
import 'gstin_validator.dart';

class RuleEngine {
  /// GST rates that are lawful for restaurant services.
  ///   5%  — standalone restaurants (no input tax credit).
  ///   18% — restaurants inside hotels with declared room tariff > ₹7,500.
  /// Absent a room-tariff signal on the bill, both are accepted as plausible.
  static const List<double> validRestaurantSlabs = [5.0, 18.0];

  /// Tolerance in *percentage points* when matching a printed rate to a slab.
  final double slabTolerance;

  /// Absolute rupee tolerance when matching a tax amount to a computed one.
  final double amountTolerance;

  const RuleEngine({
    this.slabTolerance = 0.5,
    this.amountTolerance = 1.0,
  });

  /// The signature requested by the spec: flags only.
  List<ComplianceFlag> evaluate(Bill bill) => analyze(bill).flags;

  /// The fuller result: flags plus the checks that had to be skipped.
  ComplianceReport analyze(Bill bill) {
    final flags = <ComplianceFlag>[];
    final notes = <DataNote>[];

    _checkAutomaticServiceCharge(bill, flags, notes);
    _checkGstOnServiceCharge(bill, flags, notes);
    _checkGstSlab(bill, flags, notes);
    _checkGstin(bill, flags, notes);

    return ComplianceReport(flags: flags, notes: notes);
  }

  // -------------------------------------------------------------------
  // Rule 1 — automatic service charge
  // -------------------------------------------------------------------
  void _checkAutomaticServiceCharge(
      Bill bill, List<ComplianceFlag> flags, List<DataNote> notes) {
    final sc = bill.serviceCharge;

    if (sc.isUnknown) {
      notes.add(const DataNote(
        ruleId: RuleIds.automaticServiceCharge,
        message:
            'Could not read a service charge line clearly, so this bill was '
            'not checked for an automatic service charge.',
      ));
      return;
    }

    // Confirmed absent, or present but zero/waived: nothing unlawful here.
    if (sc.isAbsent) return;
    final charge = sc.value;
    if (charge == null) return;

    final amount = charge.amount;
    if (amount == null) {
      notes.add(const DataNote(
        ruleId: RuleIds.automaticServiceCharge,
        message:
            'A service charge line was found but its amount could not be read.',
      ));
      return;
    }
    if (amount <= 0) return;
    if (charge.looksOptedOut) return;

    final percentText =
        charge.percentLabel != null ? ' (${charge.percentLabel})' : '';

    flags.add(ComplianceFlag(
      id: RuleIds.automaticServiceCharge,
      severity: FlagSeverity.high,
      title: 'Illegal automatic service charge',
      explanation:
          'A service charge of ${formatRupees(amount)}$percentText was added to '
          'this bill. Under CCPA Guidelines (July 2022), upheld by the Delhi '
          'High Court, restaurants cannot add a service charge by default — it '
          'must be entirely voluntary. You can ask for this to be removed.',
      citedRule: 'CCPA Guidelines, July 2022 (Delhi HC upheld, March 2025)',
      amountAffected: amount,
    ));
  }

  // -------------------------------------------------------------------
  // Rule 2 — GST levied on top of the service charge
  // -------------------------------------------------------------------
  void _checkGstOnServiceCharge(
      Bill bill, List<ComplianceFlag> flags, List<DataNote> notes) {
    // Only meaningful when a real service charge exists.
    if (bill.serviceCharge.isUnknown) return; // already noted by rule 1
    if (!bill.hasServiceCharge) return;

    final serviceChargeAmount = bill.serviceCharge.value!.amount!;

    if (!bill.subtotal.isFound) {
      notes.add(const DataNote(
        ruleId: RuleIds.gstOnServiceCharge,
        message:
            'The subtotal could not be read, so it was not possible to check '
            'whether GST was charged on top of the service charge.',
      ));
      return;
    }

    final gstAmount = bill.totalGstAmount;
    if (gstAmount == null || gstAmount <= 0) {
      notes.add(const DataNote(
        ruleId: RuleIds.gstOnServiceCharge,
        message:
            'The GST amounts could not be read in full, so it was not possible '
            'to check whether GST was charged on top of the service charge.',
      ));
      return;
    }

    final subtotal = bill.subtotal.value!;
    if (subtotal <= 0) return;
    final gross = subtotal + serviceChargeAmount;

    bool matchesGross = false;
    bool matchesSubtotal = false;
    double? rate;

    final printedRate = bill.totalGstPercent;

    if (printedRate != null && printedRate > 0) {
      // Strongest evidence: use the rate the bill itself claims, and see
      // which base it was actually applied to.
      rate = printedRate;
      matchesGross = _amountsMatch(gstAmount, gross * printedRate / 100);
      matchesSubtotal = _amountsMatch(gstAmount, subtotal * printedRate / 100);
    } else {
      // Fallback: no printed rate, so infer which base yields a lawful slab.
      final rateOnGross = gstAmount / gross * 100;
      final rateOnSubtotal = gstAmount / subtotal * 100;
      for (final slab in validRestaurantSlabs) {
        if ((rateOnGross - slab).abs() <= slabTolerance) {
          matchesGross = true;
          rate = slab;
        }
        if ((rateOnSubtotal - slab).abs() <= slabTolerance) {
          matchesSubtotal = true;
        }
      }
    }

    // Flag only when the evidence points one way and not the other.
    if (!matchesGross || matchesSubtotal || rate == null) return;

    final lawful = roundPaise(subtotal * rate / 100);
    final difference = roundPaise(gstAmount - lawful);
    if (difference <= 0) return; // no overcharge in practice

    flags.add(ComplianceFlag(
      id: RuleIds.gstOnServiceCharge,
      severity: FlagSeverity.high,
      title: 'GST illegally charged on service charge',
      explanation:
          'GST of ${formatRupees(gstAmount)} was charged at ${formatPercent(rate)} '
          'on ${formatRupees(gross)} — the food subtotal plus the service '
          'charge. Calculated correctly on the ${formatRupees(subtotal)} '
          'subtotal alone, GST would be ${formatRupees(lawful)}. You were '
          'charged ${formatRupees(difference)} in extra tax on a charge that is '
          'itself voluntary.',
      citedRule:
          'GST cannot apply to a discretionary service charge — it is not part '
          'of the taxable supply of food/service',
      amountAffected: difference,
    ));
  }

  // -------------------------------------------------------------------
  // Rule 3 — GST slab validity
  // -------------------------------------------------------------------
  void _checkGstSlab(
      Bill bill, List<ComplianceFlag> flags, List<DataNote> notes) {
    // totalGstPercent deliberately returns null when only half a CGST/SGST
    // pair was read — half a pair would look like an invalid 2.5% slab and
    // produce exactly the false positive this engine must never produce.
    final rate = bill.totalGstPercent;

    if (rate == null) {
      notes.add(const DataNote(
        ruleId: RuleIds.gstSlabMismatch,
        message:
            'The GST rate was not printed or could not be fully read, so the '
            'tax slab was not checked.',
      ));
      return;
    }
    if (rate <= 0) return;

    final matches = validRestaurantSlabs
        .any((slab) => (rate - slab).abs() <= slabTolerance);
    if (matches) return;

    final breakdown = _describeRateBreakdown(bill);

    flags.add(ComplianceFlag(
      id: RuleIds.gstSlabMismatch,
      severity: FlagSeverity.medium,
      title: 'GST rate does not match any valid slab',
      explanation:
          'This bill applies a combined GST rate of ${formatPercent(rate)}$breakdown. '
          'Restaurant services are taxed at either 5% for a standalone '
          'restaurant, or 18% for a restaurant in a hotel with room tariffs '
          'above ₹7,500 a night. ${formatPercent(rate)} does not match either '
          'rate, so the tax on this bill should be questioned.',
      citedRule: 'GST Council notified rates for restaurant services',
      amountAffected: bill.totalGstAmount,
    ));
  }

  String _describeRateBreakdown(Bill bill) {
    final c = bill.cgst.value?.percent;
    final s = bill.sgst.value?.percent;
    if (c != null && s != null) {
      return ' (CGST ${formatPercent(c)} + SGST ${formatPercent(s)})';
    }
    return '';
  }

  // -------------------------------------------------------------------
  // Rule 4 — GSTIN presence and validity
  // -------------------------------------------------------------------
  void _checkGstin(
      Bill bill, List<ComplianceFlag> flags, List<DataNote> notes) {
    final gstin = bill.gstin;

    if (!gstin.isFound) {
      // Concluding "no GSTIN printed" from a bad scan would be a false
      // positive, so absence only counts when the bill read cleanly.
      if (bill.readQuality == ReadQuality.poor || gstin.isUnknown) {
        notes.add(const DataNote(
          ruleId: RuleIds.gstinInvalid,
          message:
              'No GSTIN was found, but the bill did not read clearly enough to '
              'be sure it is genuinely missing. Check the printed bill.',
        ));
        return;
      }

      flags.add(const ComplianceFlag(
        id: RuleIds.gstinInvalid,
        severity: FlagSeverity.medium,
        title: 'No GSTIN found on bill — cannot verify tax registration',
        explanation:
            'This bill does not show a GSTIN. A business collecting GST must '
            'print its GST registration number on the bill. Without it, there '
            'is no way to verify that the tax collected from you is being '
            'remitted to the government.',
        citedRule: 'GST registration requirement under CGST Act',
      ));
      return;
    }

    final value = GstinValidator.normalize(gstin.value!);

    if (!GstinValidator.hasValidFormat(value)) {
      flags.add(ComplianceFlag(
        id: RuleIds.gstinInvalid,
        severity: FlagSeverity.medium,
        title: 'GSTIN format appears invalid',
        explanation:
            'The GSTIN printed on this bill ($value) does not match the '
            'required 15-character format of a state code, a 10-character PAN, '
            'an entity digit, the letter Z, and a checksum character. An '
            'invalid GSTIN may mean the tax registration cannot be verified.',
        citedRule: 'GST registration requirement under CGST Act',
      ));
      return;
    }

    if (!GstinValidator.hasValidStateCode(value)) {
      flags.add(ComplianceFlag(
        id: RuleIds.gstinInvalid,
        severity: FlagSeverity.medium,
        title: 'GSTIN state code is not valid',
        explanation:
            'The GSTIN on this bill ($value) begins with a state code that is '
            'not issued to any Indian state or union territory. This suggests '
            'the number is not a genuine GST registration.',
        citedRule: 'GST registration requirement under CGST Act',
      ));
      return;
    }

    if (!GstinValidator.hasValidChecksum(value)) {
      // Checksum failures are reported more cautiously: a single character
      // misread by OCR breaks the checksum on an otherwise genuine number.
      flags.add(ComplianceFlag(
        id: RuleIds.gstinInvalid,
        severity: FlagSeverity.medium,
        title: 'GSTIN checksum does not validate',
        explanation:
            'The GSTIN on this bill ($value) has the right shape but fails its '
            'built-in checksum, so it is not a valid registration number. Note '
            'that a single character misread from the printed bill can also '
            'cause this — check the number against the bill before relying on '
            'it.',
        citedRule: 'GST registration requirement under CGST Act',
      ));
    }
  }

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------

  /// Compares two rupee amounts allowing for the rounding a printed bill
  /// does: a flat tolerance, or 0.5% of the expected value, whichever is
  /// larger.
  bool _amountsMatch(double actual, double expected) {
    final tolerance = math.max(amountTolerance, expected.abs() * 0.005);
    return (actual - expected).abs() <= tolerance;
  }
}
