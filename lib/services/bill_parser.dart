/// Converts raw OCR text into a structured [Bill].
///
/// Pure Dart with no Flutter dependencies. The parser assumes nothing about
/// line order or spacing — real receipts, photographed at an angle under
/// restaurant lighting, produce text that is reordered, split, and riddled
/// with character confusions. Everything here is label-driven and
/// position-independent.
library;

import '../models/bill.dart';
import 'gstin_validator.dart';

/// What a given line of the receipt turned out to be.
enum _LineKind { subtotal, serviceCharge, cgst, sgst, gstCombined, total, other }

class BillParser {
  const BillParser();

  // Label aliases, matched against a line with all non-letter characters
  // stripped, so "S.CHARGE", "S CHARGE" and "SCHARGE" all collapse together.
  // Order within each list does not matter; order *between* kinds does, and
  // is enforced in [_classify].
  static const List<String> _subtotalLabels = [
    'SUBTOTAL', 'SUBTOTL', 'NETAMOUNT', 'NETAMT', 'FOODTOTAL', 'ITEMTOTAL',
    'GROSSAMOUNT', 'TOTALBEFORETAX', 'AMOUNTBEFORETAX', 'TAXABLEVALUE',
    'TAXABLEAMOUNT', 'BASICAMOUNT',
  ];

  static const List<String> _serviceChargeLabels = [
    'SERVICECHARGE', 'SERVICECHARGES', 'SERVICECHRG', 'SERVICECHG', 'SVCCHARGE',
    'SRVCHARGE', 'SERVCHARGE', 'SCHARGE', 'SERVICE', 'SERVCHRG',
  ];

  static const List<String> _cgstLabels = ['CGST', 'CENTRALGST', 'CGSTTAX'];
  static const List<String> _sgstLabels = [
    'SGST', 'STATEGST', 'SGSTTAX', 'UTGST', 'UGST',
  ];
  static const List<String> _combinedGstLabels = ['GST', 'IGST', 'TAX', 'GSTTOTAL'];

  static const List<String> _totalLabels = [
    'GRANDTOTAL', 'TOTAL', 'NETPAYABLE', 'AMOUNTPAYABLE', 'BILLTOTAL',
    'TOTALAMOUNT', 'PAYABLE', 'ROUNDEDTOTAL',
  ];

  /// Words that indicate a service charge was waived or is genuinely optional.
  static const List<String> _optOutMarkers = [
    'VOLUNTARY', 'OPTIONAL', 'OPTEDOUT', 'OPTOUT', 'WAIVED', 'WAIVER',
    'REMOVED', 'NOTAPPLICABLE', 'DISCRETIONARY', 'ATYOURDISCRETION',
    'NOSERVICECHARGE', 'NIL',
  ];

  /// Lines that are receipt furniture rather than purchased items.
  static const List<String> _noiseMarkers = [
    'GSTIN', 'GSTNO', 'INVOICE', 'BILLNO', 'DATE', 'TIME', 'TABLE', 'PHONE',
    'TEL', 'MOB', 'CASHIER', 'STEWARD', 'THANKYOU', 'VISITAGAIN', 'FSSAI',
    'ADDRESS', 'ORDERNO', 'TOKEN', 'COVERS', 'PAX', 'CARD', 'CASH', 'UPI',
    'CHANGE', 'TENDERED', 'ROUNDOFF', 'ROUNDING', 'QTY', 'ITEM', 'RATE',
    'AMOUNT', 'DESCRIPTION', 'PARTICULARS', 'WWW', 'HTTP',
  ];

  Bill parse(String rawText, {String source = 'scan'}) {
    final lines = _splitLines(rawText);

    Detected<double> subtotal = const Detected.unknown();
    Detected<ServiceCharge> serviceCharge = const Detected.unknown();
    Detected<TaxComponent> cgst = const Detected.unknown();
    Detected<TaxComponent> sgst = const Detected.unknown();
    Detected<TaxComponent> gstCombined = const Detected.unknown();
    Detected<double> total = const Detected.unknown();

    final items = <LineItem>[];
    var firstSummaryIndex = lines.length;

    // Pass 1 — classify each line and pull out the summary figures.
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final kind = _classify(line);
      if (kind == _LineKind.other) continue;

      if (i < firstSummaryIndex) firstSummaryIndex = i;

      final percent = _percentIn(line);
      final amount = _primaryAmountIn(line);

      switch (kind) {
        case _LineKind.subtotal:
          if (amount != null && !subtotal.isFound) {
            subtotal = Detected.found(amount, source: line);
          }
        case _LineKind.serviceCharge:
          if (!serviceCharge.isFound) {
            final optedOut = _looksOptedOut(line, amount);
            serviceCharge = Detected.found(
              ServiceCharge(
                amount: amount,
                percentLabel: percent != null ? _formatPercentLabel(percent) : null,
                looksOptedOut: optedOut,
              ),
              source: line,
            );
          }
        case _LineKind.cgst:
          if (!cgst.isFound) {
            cgst = Detected.found(
              TaxComponent(amount: amount, percent: percent),
              source: line,
            );
          }
        case _LineKind.sgst:
          if (!sgst.isFound) {
            sgst = Detected.found(
              TaxComponent(amount: amount, percent: percent),
              source: line,
            );
          }
        case _LineKind.gstCombined:
          if (!gstCombined.isFound) {
            gstCombined = Detected.found(
              TaxComponent(amount: amount, percent: percent),
              source: line,
            );
          }
        case _LineKind.total:
          // Prefer a "grand total" over an earlier generic "total" line.
          final isGrand = _stripped(line).contains('GRANDTOTAL') ||
              _stripped(line).contains('NETPAYABLE');
          if (amount != null && (!total.isFound || isGrand)) {
            total = Detected.found(amount, source: line);
          }
        case _LineKind.other:
          break;
      }
    }

    // Pass 2 — line items are the amount-bearing lines above the summary
    // block that are not receipt furniture.
    for (var i = 0; i < firstSummaryIndex && i < lines.length; i++) {
      final item = _asLineItem(lines[i]);
      if (item != null) items.add(item);
    }

    final gstin = _findGstin(rawText);

    final quality = _assessQuality(
      rawText: rawText,
      lines: lines,
      subtotal: subtotal,
      total: total,
      cgst: cgst,
      sgst: sgst,
      gstCombined: gstCombined,
      gstin: gstin,
      itemCount: items.length,
    );

    // Pass 3 — promote "not found" to "confirmed absent" only where the read
    // was good enough for absence to mean something.
    final good = quality == ReadQuality.good;

    if (!subtotal.isFound && good) subtotal = const Detected.absent();
    if (!total.isFound && good) total = const Detected.absent();
    if (!serviceCharge.isFound && good) serviceCharge = const Detected.absent();

    // A *lone* half of a CGST/SGST pair is far more likely an OCR miss than a
    // real bill, so the missing half stays "unknown". Calling it absent would
    // halve the apparent GST rate and manufacture a slab violation.
    final sawEitherHalf = cgst.isFound || sgst.isFound;
    if (good && !sawEitherHalf) {
      cgst = const Detected.absent();
      sgst = const Detected.absent();
    }
    if (!gstCombined.isFound && (sawEitherHalf || good)) {
      gstCombined = const Detected.absent();
    }

    return Bill(
      items: items,
      subtotal: subtotal,
      serviceCharge: serviceCharge,
      cgst: cgst,
      sgst: sgst,
      gstCombined: gstCombined,
      gstin: gstin,
      total: total,
      readQuality: quality,
      rawText: rawText,
      source: source,
    );
  }

  // -------------------------------------------------------------------
  // Line handling
  // -------------------------------------------------------------------

  List<String> _splitLines(String raw) => raw
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  /// Uppercase, letters and digits only — the form labels are matched in.
  String _stripped(String line) =>
      line.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Letters only, for label matching that must ignore embedded amounts.
  String _letters(String line) =>
      line.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

  _LineKind _classify(String line) {
    final letters = _letters(line);
    if (letters.isEmpty) return _LineKind.other;

    // Most specific first: CGST/SGST contain "GST", subtotal contains "TOTAL".
    if (_containsAny(letters, _cgstLabels)) return _LineKind.cgst;
    if (_containsAny(letters, _sgstLabels)) return _LineKind.sgst;
    if (_containsAny(letters, _subtotalLabels)) return _LineKind.subtotal;
    if (_containsAny(letters, _serviceChargeLabels)) return _LineKind.serviceCharge;

    // "GST" only counts as a combined line once CGST/SGST have been ruled out,
    // and never when it is part of "GSTIN"/"GST NO" (a registration number).
    if (letters.contains('GSTIN') || letters.contains('GSTNO')) {
      return _LineKind.other;
    }
    if (_containsAny(letters, _combinedGstLabels)) return _LineKind.gstCombined;

    if (_containsAny(letters, _totalLabels)) return _LineKind.total;

    return _LineKind.other;
  }

  bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      // Compare on letters only, since the needles are letter-only forms.
      final needle = n.replaceAll(RegExp(r'[^A-Z]'), '');
      if (needle.isNotEmpty && haystack.contains(needle)) return true;
    }
    return false;
  }

  /// Extracts a percentage: "5%", "@ 10", "2.5 %".
  double? _percentIn(String line) {
    final explicit = RegExp(r'(\d{1,2}(?:\.\d{1,2})?)\s*%').firstMatch(line);
    if (explicit != null) return double.tryParse(explicit.group(1)!);

    final at = RegExp(r'@\s*(\d{1,2}(?:\.\d{1,2})?)').firstMatch(line);
    if (at != null) return double.tryParse(at.group(1)!);

    return null;
  }

  String _formatPercentLabel(double percent) {
    final text = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toString();
    return '$text%';
  }

  /// The rupee figure on a line — the last number once percentages have been
  /// removed, since receipts put the amount in the rightmost column.
  double? _primaryAmountIn(String line) {
    final amounts = _amountsIn(line);
    return amounts.isEmpty ? null : amounts.last;
  }

  List<double> _amountsIn(String line) {
    // Drop percentages and "@10" rate markers so they are not mistaken for
    // amounts, and drop anything that looks like a quantity multiplier.
    var cleaned = line
        .replaceAll(RegExp(r'\d+(?:\.\d+)?\s*%'), ' ')
        .replaceAll(RegExp(r'@\s*\d+(?:\.\d+)?'), ' ');

    // Repair the digit/letter confusions OCR makes inside numeric runs.
    cleaned = _repairDigits(cleaned);

    final matches = RegExp(r'\d[\d,]*(?:\.\d{1,2})?').allMatches(cleaned);
    final result = <double>[];
    for (final m in matches) {
      final token = m.group(0)!.replaceAll(',', '');
      final value = double.tryParse(token);
      if (value != null) result.add(value);
    }
    return result;
  }

  /// Fixes O/o -> 0, l/I -> 1, S -> 5 and B -> 8, but only inside runs that
  /// are already mostly digits. Applying these blindly would mangle words.
  String _repairDigits(String input) {
    return input.replaceAllMapped(
      RegExp(r'[0-9OoIlSB][0-9OoIlSB.,]{1,}'),
      (match) {
        final token = match.group(0)!;
        final digitCount = RegExp(r'[0-9]').allMatches(token).length;
        // Require the run to be majority-digit before "repairing" it.
        if (digitCount * 2 < token.length) return token;
        return token
            .replaceAll(RegExp(r'[Oo]'), '0')
            .replaceAll(RegExp(r'[Il]'), '1')
            .replaceAll('S', '5')
            .replaceAll('B', '8');
      },
    );
  }

  bool _looksOptedOut(String line, double? amount) {
    if (amount != null && amount == 0) return true;
    final letters = _letters(line);
    return _containsAny(letters, _optOutMarkers);
  }

  LineItem? _asLineItem(String line) {
    final letters = _letters(line);
    if (letters.length < 3) return null;
    if (_containsAny(letters, _noiseMarkers)) return null;
    if (_classify(line) != _LineKind.other) return null;

    final amounts = _amountsIn(line);
    if (amounts.isEmpty) return null;

    final price = amounts.last;
    // A plausible menu price, not a phone number or a date fragment.
    if (price <= 0 || price > 100000) return null;

    // Leading integer is usually a quantity: "2  Paneer Tikka   450.00".
    var quantity = 1;
    final qtyMatch = RegExp(r'^\s*(\d{1,2})\s+[A-Za-z]').firstMatch(line);
    if (qtyMatch != null) {
      quantity = int.tryParse(qtyMatch.group(1)!) ?? 1;
    }

    // The name is the line with numbers and currency marks stripped out.
    final name = line
        .replaceAll(RegExp(r'[₹]|(?:Rs\.?)|(?:INR)', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\d[\d,]*(?:\.\d{1,2})?'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.length < 2) return null;

    return LineItem(name: name, price: price, quantity: quantity);
  }

  Detected<String> _findGstin(String rawText) {
    final upper = rawText.toUpperCase();

    // Prefer a token sitting next to an explicit GSTIN label.
    final labelled = RegExp(
      r'GST(?:IN|\s*NO\.?|\s*NUMBER)?\s*[:\-#]?\s*([0-9OoIl][0-9A-Zoil]{14})',
      caseSensitive: false,
    ).firstMatch(upper);
    if (labelled != null) {
      final candidate = GstinValidator.normalize(
          _repairStateDigits(labelled.group(1)!));
      if (candidate.length == 15) {
        return Detected.found(candidate, source: labelled.group(0));
      }
    }

    // Otherwise look for any GSTIN-shaped 15-character token.
    for (final match in GstinValidator.searchPattern.allMatches(upper)) {
      final candidate =
          GstinValidator.normalize(_repairStateDigits(match.group(0)!));
      if (candidate.length != 15) continue;
      if (GstinValidator.strictPattern.hasMatch(candidate)) {
        return Detected.found(candidate, source: match.group(0));
      }
    }

    // A malformed-but-labelled number is still worth reporting, so the
    // "invalid format" rule can speak to it rather than staying silent.
    final loose = RegExp(r'GST(?:IN|\s*NO\.?)\s*[:\-#]?\s*([0-9A-Z]{10,20})',
            caseSensitive: false)
        .firstMatch(upper);
    if (loose != null) {
      return Detected.found(GstinValidator.normalize(loose.group(1)!),
          source: loose.group(0));
    }

    return const Detected.unknown();
  }

  /// The first two characters of a GSTIN are always digits, so O/I/l there
  /// are unambiguous OCR errors.
  String _repairStateDigits(String token) {
    if (token.length < 2) return token;
    final head = token
        .substring(0, 2)
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[Il]'), '1');
    return head + token.substring(2);
  }

  ReadQuality _assessQuality({
    required String rawText,
    required List<String> lines,
    required Detected<double> subtotal,
    required Detected<double> total,
    required Detected<TaxComponent> cgst,
    required Detected<TaxComponent> sgst,
    required Detected<TaxComponent> gstCombined,
    required Detected<String> gstin,
    required int itemCount,
  }) {
    if (rawText.trim().length < 40 || lines.length < 4) return ReadQuality.poor;

    var anchors = 0;
    if (subtotal.isFound) anchors++;
    if (total.isFound) anchors++;
    if (cgst.isFound || sgst.isFound || gstCombined.isFound) anchors++;
    if (gstin.isFound) anchors++;
    if (itemCount > 0) anchors++;

    if (anchors >= 3) return ReadQuality.good;
    if (anchors >= 1) return ReadQuality.partial;
    return ReadQuality.poor;
  }
}
