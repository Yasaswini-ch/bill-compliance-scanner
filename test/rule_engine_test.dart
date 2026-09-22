import 'package:flutter_test/flutter_test.dart';

import 'package:bill_compliance_scanner/models/bill.dart';
import 'package:bill_compliance_scanner/models/compliance_flag.dart';
import 'package:bill_compliance_scanner/services/bill_parser.dart';
import 'package:bill_compliance_scanner/services/demo_fixtures.dart';
import 'package:bill_compliance_scanner/services/explanation_service.dart';
import 'package:bill_compliance_scanner/services/gstin_validator.dart';
import 'package:bill_compliance_scanner/services/rule_engine.dart';

void main() {
  const engine = RuleEngine();
  const parser = BillParser();

  Set<String> idsOf(List<ComplianceFlag> flags) =>
      flags.map((f) => f.id).toSet();

  group('Fixture 1 — compliant bill', () {
    test('produces zero flags', () {
      final flags = engine.evaluate(DemoFixtures.compliantBill());
      expect(flags, isEmpty);
    });

    test('produces zero skipped-check notes', () {
      final report = engine.analyze(DemoFixtures.compliantBill());
      expect(report.notes, isEmpty);
      expect(report.isClean, isTrue);
      expect(report.isInconclusive, isFalse);
    });
  });

  group('Fixture 2 — non-compliant bill', () {
    late List<ComplianceFlag> flags;

    setUp(() {
      flags = engine.evaluate(DemoFixtures.nonCompliantBill());
    });

    test('raises the three required violations', () {
      expect(
        idsOf(flags),
        containsAll<String>([
          RuleIds.automaticServiceCharge,
          RuleIds.gstOnServiceCharge,
          RuleIds.gstSlabMismatch,
        ]),
      );
    });

    test('also catches the malformed GSTIN, for four flags total', () {
      expect(idsOf(flags), contains(RuleIds.gstinInvalid));
      expect(flags, hasLength(4));
    });

    test('quantifies the service charge and the tax overcharge', () {
      final sc = flags.firstWhere((f) => f.id == RuleIds.automaticServiceCharge);
      expect(sc.amountAffected, closeTo(120.00, 0.001));

      // 8% of 1320.00 = 105.60 charged, against 8% of 1200.00 = 96.00 lawful.
      final gst = flags.firstWhere((f) => f.id == RuleIds.gstOnServiceCharge);
      expect(gst.amountAffected, closeTo(9.60, 0.001));
    });

    test('marks the service-charge violations as high severity', () {
      final high = flags
          .where((f) => f.severity == FlagSeverity.high)
          .map((f) => f.id)
          .toSet();
      expect(high, contains(RuleIds.automaticServiceCharge));
      expect(high, contains(RuleIds.gstOnServiceCharge));
    });

    test('every flag carries a citation', () {
      for (final flag in flags) {
        expect(flag.citedRule, isNotEmpty, reason: '${flag.id} has no citation');
        expect(flag.explanation.length, greaterThan(40));
      }
    });
  });

  group('Missing data never becomes a violation', () {
    test('an unreadable bill produces notes, not flags', () {
      final report = engine.analyze(DemoFixtures.unreadableBill());
      expect(report.flags, isEmpty);
      expect(report.notes, isNotEmpty);
      expect(report.isInconclusive, isTrue);
    });

    test('a lone CGST line does not fake a 4% slab violation', () {
      // Only half the CGST/SGST pair was legible. Summing it alone would look
      // like an unlawful 4% rate; the engine must refuse to conclude.
      final bill = Bill(
        subtotal: const Detected.found(1000.00),
        serviceCharge: const Detected.absent(),
        cgst: const Detected.found(TaxComponent(amount: 40.0, percent: 4.0)),
        sgst: const Detected.unknown(),
        gstin: const Detected.found(DemoFixtures.validGstin),
        total: const Detected.found(1080.00),
        readQuality: ReadQuality.partial,
      );

      final report = engine.analyze(bill);
      expect(idsOf(report.flags), isNot(contains(RuleIds.gstSlabMismatch)));
      expect(report.notes.any((n) => n.ruleId == RuleIds.gstSlabMismatch),
          isTrue);
    });

    test('a poor scan does not claim the GSTIN is missing', () {
      final bill = Bill(
        subtotal: const Detected.found(500.00),
        gstin: const Detected.unknown(),
        readQuality: ReadQuality.poor,
      );
      final report = engine.analyze(bill);
      expect(idsOf(report.flags), isNot(contains(RuleIds.gstinInvalid)));
      expect(report.notes.any((n) => n.ruleId == RuleIds.gstinInvalid), isTrue);
    });

    test('a clean scan with genuinely no GSTIN does flag it', () {
      final bill = Bill(
        subtotal: const Detected.found(1000.00),
        serviceCharge: const Detected.absent(),
        cgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        sgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        gstin: const Detected.absent(),
        total: const Detected.found(1050.00),
        readQuality: ReadQuality.good,
      );
      expect(idsOf(engine.evaluate(bill)), contains(RuleIds.gstinInvalid));
    });

    test('an unreadable service-charge line is noted, not flagged', () {
      final bill = Bill(
        subtotal: const Detected.found(1000.00),
        serviceCharge: const Detected.unknown(),
        cgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        sgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        gstin: const Detected.found(DemoFixtures.validGstin),
        total: const Detected.found(1050.00),
        readQuality: ReadQuality.partial,
      );
      final report = engine.analyze(bill);
      expect(idsOf(report.flags),
          isNot(contains(RuleIds.automaticServiceCharge)));
      expect(
          report.notes
              .any((n) => n.ruleId == RuleIds.automaticServiceCharge),
          isTrue);
    });
  });

  group('Lawful bills stay unflagged', () {
    test('a voluntary, opted-out service charge is not a violation', () {
      final bill = Bill(
        subtotal: const Detected.found(1000.00),
        serviceCharge: const Detected.found(ServiceCharge(
          amount: 100.00,
          percentLabel: '10%',
          looksOptedOut: true,
        )),
        cgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        sgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        gstin: const Detected.found(DemoFixtures.validGstin),
        total: const Detected.found(1150.00),
        readQuality: ReadQuality.good,
      );
      expect(idsOf(engine.evaluate(bill)),
          isNot(contains(RuleIds.automaticServiceCharge)));
    });

    test('GST correctly levied on the subtotal alone is not flagged', () {
      // Service charge present (so rule 1 fires), but GST is 5% of the
      // subtotal only — rule 2 must stay silent.
      final bill = Bill(
        subtotal: const Detected.found(1000.00),
        serviceCharge: const Detected.found(
            ServiceCharge(amount: 100.00, percentLabel: '10%')),
        cgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        sgst: const Detected.found(TaxComponent(amount: 25.0, percent: 2.5)),
        gstin: const Detected.found(DemoFixtures.validGstin),
        total: const Detected.found(1150.00),
        readQuality: ReadQuality.good,
      );
      final ids = idsOf(engine.evaluate(bill));
      expect(ids, contains(RuleIds.automaticServiceCharge));
      expect(ids, isNot(contains(RuleIds.gstOnServiceCharge)));
      expect(ids, isNot(contains(RuleIds.gstSlabMismatch)));
    });

    test('the 18% hotel-restaurant slab is accepted', () {
      final bill = Bill(
        subtotal: const Detected.found(1000.00),
        serviceCharge: const Detected.absent(),
        cgst: const Detected.found(TaxComponent(amount: 90.0, percent: 9.0)),
        sgst: const Detected.found(TaxComponent(amount: 90.0, percent: 9.0)),
        gstin: const Detected.found(DemoFixtures.validGstin),
        total: const Detected.found(1180.00),
        readQuality: ReadQuality.good,
      );
      expect(engine.evaluate(bill), isEmpty);
    });
  });

  group('GSTIN validation', () {
    test('the fixture GSTIN passes format, state code and checksum', () {
      expect(GstinValidator.hasValidFormat(DemoFixtures.validGstin), isTrue);
      expect(GstinValidator.hasValidStateCode(DemoFixtures.validGstin), isTrue);
      expect(GstinValidator.hasValidChecksum(DemoFixtures.validGstin), isTrue);
    });

    test('the checksum character is computed correctly', () {
      expect(GstinValidator.computeCheckCharacter('29AABCU9603R1Z'), 'J');
      expect(GstinValidator.complete('29AABCU9603R1Z'),
          DemoFixtures.validGstin);
    });

    test('the malformed fixture GSTIN fails the format check', () {
      expect(GstinValidator.hasValidFormat(DemoFixtures.invalidGstin), isFalse);
    });

    test('a corrupted checksum is rejected', () {
      expect(GstinValidator.hasValidChecksum('29AABCU9603R1ZK'), isFalse);
    });

    test('an unissued state code is rejected', () {
      expect(GstinValidator.hasValidStateCode('49AABCU9603R1ZJ'), isFalse);
    });
  });

  group('Parser reaches the same verdict from printed receipt text', () {
    test('the compliant receipt parses and produces zero flags', () {
      final bill = parser.parse(DemoFixtures.compliantReceiptText);

      expect(bill.readQuality, ReadQuality.good);
      expect(bill.subtotal.value, closeTo(850.00, 0.001));
      expect(bill.total.value, closeTo(892.50, 0.001));
      expect(bill.cgst.value?.percent, closeTo(2.5, 0.001));
      expect(bill.sgst.value?.amount, closeTo(21.25, 0.001));
      expect(bill.gstin.value, DemoFixtures.validGstin);
      expect(bill.serviceCharge.isAbsent, isTrue,
          reason: 'no service charge line is printed on this receipt');
      expect(bill.items, isNotEmpty);

      expect(engine.evaluate(bill), isEmpty);
    });

    test('the non-compliant receipt parses and raises the same four flags', () {
      final bill = parser.parse(DemoFixtures.nonCompliantReceiptText);

      expect(bill.subtotal.value, closeTo(1200.00, 0.001));
      expect(bill.serviceCharge.value?.amount, closeTo(120.00, 0.001));
      expect(bill.serviceCharge.value?.percentLabel, '10%');
      expect(bill.serviceCharge.value?.looksOptedOut, isFalse);
      expect(bill.totalGstAmount, closeTo(105.60, 0.001));
      expect(bill.totalGstPercent, closeTo(8.0, 0.001));
      expect(bill.gstin.value, DemoFixtures.invalidGstin);
      expect(bill.total.value, closeTo(1425.60, 0.001));

      expect(
        idsOf(engine.evaluate(bill)),
        containsAll<String>([
          RuleIds.automaticServiceCharge,
          RuleIds.gstOnServiceCharge,
          RuleIds.gstSlabMismatch,
          RuleIds.gstinInvalid,
        ]),
      );
    });

    test('empty OCR output is reported as unreadable, not as a clean bill', () {
      final bill = parser.parse('');
      expect(bill.readQuality, ReadQuality.poor);
      final report = engine.analyze(bill);
      expect(report.flags, isEmpty);
      expect(report.isInconclusive, isTrue);
    });
  });

  group('Explanation service', () {
    const service = TemplateExplanationService();

    test('summarises a clean bill positively', () async {
      final bill = DemoFixtures.compliantBill();
      final text = await service.summarize(engine.analyze(bill), bill);
      expect(text.toLowerCase(), contains('clean'));
    });

    test('summarises violations with the amounts and a next step', () async {
      final bill = DemoFixtures.nonCompliantBill();
      final text = await service.summarize(engine.analyze(bill), bill);
      expect(text, contains('4 compliance issues'));
      expect(text, contains('service charge'));
      expect(text, contains('1915'));
    });

    test('does not call an unverifiable bill clean', () async {
      final bill = DemoFixtures.unreadableBill();
      final text = await service.summarize(engine.analyze(bill), bill);
      expect(text.toLowerCase(), contains('not verified'));
    });

    test('the local-LLM implementation falls back silently', () async {
      const llm = LocalLlmExplanationService();
      final bill = DemoFixtures.compliantBill();
      final text = await llm.summarize(engine.analyze(bill), bill);
      expect(text, isNotEmpty);
    });
  });
}
