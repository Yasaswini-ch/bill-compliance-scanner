/// Hard-coded bills for demoing without a camera, plus the matching printed
/// receipt text so the same bills can be printed and physically scanned.
///
/// Pure Dart — no Flutter imports.
library;

import '../models/bill.dart';

class DemoFixture {
  final String key;
  final String label;
  final String description;
  final Bill bill;

  /// The same bill as it would appear on thermal receipt paper. Printing this
  /// and scanning it exercises the real OCR path end to end.
  final String receiptText;

  const DemoFixture({
    required this.key,
    required this.label,
    required this.description,
    required this.bill,
    required this.receiptText,
  });
}

abstract final class DemoFixtures {
  /// A checksum-valid GSTIN (Karnataka, state code 29).
  static const String validGstin = '29AABCU9603R1ZJ';

  /// Malformed: positions 7-10 must be digits, but this has a letter.
  static const String invalidGstin = '27AAQCS12E4M1ZP';

  // -------------------------------------------------------------------
  // Fixture 1 — fully compliant. Expected result: zero flags.
  // -------------------------------------------------------------------
  static Bill compliantBill() => Bill(
        items: const [
          LineItem(name: 'Masala Dosa', price: 260.00, quantity: 2),
          LineItem(name: 'Filter Coffee', price: 120.00, quantity: 2),
          LineItem(name: 'Paneer Butter Masala', price: 320.00, quantity: 1),
          LineItem(name: 'Butter Naan', price: 150.00, quantity: 2),
        ],
        subtotal: const Detected.found(850.00),
        // Confirmed absent, not merely unread: this bill has no such line.
        serviceCharge: const Detected.absent(),
        cgst: const Detected.found(TaxComponent(amount: 21.25, percent: 2.5)),
        sgst: const Detected.found(TaxComponent(amount: 21.25, percent: 2.5)),
        gstCombined: const Detected.absent(),
        gstin: const Detected.found(validGstin),
        total: const Detected.found(892.50),
        readQuality: ReadQuality.good,
        source: 'demo',
        rawText: compliantReceiptText,
      );

  static const String compliantReceiptText = '''
UDUPI SRI KRISHNA BHAVAN
45 Jayanagar 4th Block, Bengaluru 560041
GSTIN: 29AABCU9603R1ZJ
Bill No: 1183        Table: 4
Date: 22/09/2026     Time: 13:20
----------------------------------------
Item                   Qty       Amount
----------------------------------------
Masala Dosa             2        260.00
Filter Coffee           2        120.00
Paneer Butter Masala    1        320.00
Butter Naan             2        150.00
----------------------------------------
Sub Total                        850.00
CGST 2.5%                         21.25
SGST 2.5%                         21.25
----------------------------------------
Grand Total                      892.50
----------------------------------------
Thank you! Visit again
''';

  // -------------------------------------------------------------------
  // Fixture 2 — multiple violations. Expected: 4 flags.
  //
  //   subtotal        1200.00
  //   service charge   120.00  (10%, automatic)
  //   GST @ 8% on     1320.00  ->  105.60   (should be 8% of 1200 = 96.00)
  //   grand total     1425.60
  //
  // 8% is not a lawful restaurant slab, the GST base includes the service
  // charge, the service charge itself is automatic, and the GSTIN is
  // malformed — one violation for each of the four rules.
  // -------------------------------------------------------------------
  static Bill nonCompliantBill() => Bill(
        items: const [
          LineItem(name: 'Chicken Biryani', price: 560.00, quantity: 2),
          LineItem(name: 'Mutton Rogan Josh', price: 420.00, quantity: 1),
          LineItem(name: 'Garlic Naan', price: 180.00, quantity: 3),
          LineItem(name: 'Gulab Jamun', price: 40.00, quantity: 2),
        ],
        subtotal: const Detected.found(1200.00),
        serviceCharge: const Detected.found(
          ServiceCharge(amount: 120.00, percentLabel: '10%', looksOptedOut: false),
        ),
        cgst: const Detected.found(TaxComponent(amount: 52.80, percent: 4.0)),
        sgst: const Detected.found(TaxComponent(amount: 52.80, percent: 4.0)),
        gstCombined: const Detected.absent(),
        gstin: const Detected.found(invalidGstin),
        total: const Detected.found(1425.60),
        readQuality: ReadQuality.good,
        source: 'demo',
        rawText: nonCompliantReceiptText,
      );

  static const String nonCompliantReceiptText = '''
SPICE GARDEN RESTAURANT
12 MG Road, Bengaluru 560001
GSTIN: 27AAQCS12E4M1ZP
Bill No: 4472        Table: 7
Date: 22/09/2026     Time: 20:45
----------------------------------------
Item                   Qty       Amount
----------------------------------------
Chicken Biryani         2        560.00
Mutton Rogan Josh       1        420.00
Garlic Naan             3        180.00
Gulab Jamun             2         40.00
----------------------------------------
Sub Total                       1200.00
Service Charge 10%               120.00
CGST 4%                           52.80
SGST 4%                           52.80
----------------------------------------
Grand Total                     1425.60
----------------------------------------
Thank you! Visit again
''';

  // -------------------------------------------------------------------
  // Fixture 3 — a deliberately unreadable scan, to demonstrate that missing
  // data produces notes rather than accusations.
  // -------------------------------------------------------------------
  static Bill unreadableBill() => Bill(
        subtotal: const Detected.unknown(),
        serviceCharge: const Detected.unknown(),
        cgst: const Detected.unknown(),
        sgst: const Detected.unknown(),
        gstCombined: const Detected.unknown(),
        gstin: const Detected.unknown(),
        total: const Detected.unknown(),
        readQuality: ReadQuality.poor,
        source: 'demo',
        rawText: 'SP CE G RD N\n.... 14 5.6',
      );

  static List<DemoFixture> all() => [
        DemoFixture(
          key: 'compliant',
          label: 'Compliant bill',
          description:
              'Udupi Sri Krishna Bhavan — 5% GST on subtotal, no service '
              'charge, valid GSTIN. Should report no issues.',
          bill: compliantBill(),
          receiptText: compliantReceiptText,
        ),
        DemoFixture(
          key: 'non_compliant',
          label: 'Non-compliant bill',
          description:
              'Spice Garden — automatic 10% service charge, GST charged on '
              'top of it at an invalid 8% slab, malformed GSTIN.',
          bill: nonCompliantBill(),
          receiptText: nonCompliantReceiptText,
        ),
        DemoFixture(
          key: 'unreadable',
          label: 'Unreadable scan',
          description:
              'A bill too blurred to parse. Shows that the app reports what it '
              'could not check instead of inventing violations.',
          bill: unreadableBill(),
          receiptText: '',
        ),
      ];
}
