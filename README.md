# Bill Compliance Scanner

An Android app that photographs a printed restaurant or hotel bill, reads it
entirely on-device, and flags overcharges that are unlawful under Indian
consumer-protection and GST rules.

No image and no bill data ever leaves the phone.

## What it checks

| # | Check | Severity | Basis |
|---|-------|----------|-------|
| 1 | Automatic service charge | High | CCPA Guidelines, July 2022 (upheld by the Delhi High Court, March 2025) |
| 2 | GST charged on top of the service charge | High | GST applies to the taxable supply of food and service, not to a discretionary charge |
| 3 | GST rate outside the 5% / 18% restaurant slabs | Medium | GST Council notified rates for restaurant services |
| 4 | Missing or malformed GSTIN | Medium | GST registration requirement under the CGST Act |

### The rule that matters most

**A check that cannot be evaluated is skipped and reported as a note — never
guessed into a violation.**

A photo of a bill is a lossy, unreliable input. Accusing a restaurant of an
offence because the OCR missed a line would make the app worse than useless,
so every rule distinguishes three states for each field: *found*, *confirmed
absent*, and *unreadable*. Only the first two can support a conclusion. The
result screen separates "no issues found" from "not enough was readable to
decide", and never lets the second masquerade as the first.

Two concrete guards worth knowing about:

- If only one half of a CGST/SGST pair is legible, the combined rate is
  reported as unknown rather than halved — otherwise a missed SGST line would
  look like an unlawful 2.5% slab.
- "No GSTIN on this bill" is only ever claimed when the rest of the bill read
  cleanly. On a poor scan it becomes "could not verify".

## Architecture

```
lib/
  models/      Bill, LineItem, ServiceCharge, TaxComponent, ComplianceFlag
  services/    BillParser, RuleEngine, GstinValidator, ExplanationService,
               BillScannerService (camera + ML Kit), HistoryStore
  screens/     ScanScreen, ResultScreen, HistoryScreen
  widgets/     FlagCard, VerdictHeader, BillSummaryCard, NotesCard, ScanButton
  theme/       app_theme.dart
```

`BillParser`, `RuleEngine`, `GstinValidator` and `TemplateExplanationService`
are **pure Dart with no Flutter imports** — data in, data out. They are unit
tested directly and can be reused unchanged behind a different UI.

State management is `provider`; `AppState` only sequences the pipeline
(OCR → parse → evaluate → explain → persist) and holds the result.

## Running it

```bash
flutter pub get
flutter run                 # Android device or emulator
flutter test                # rule engine + parser + validator tests
```

Requires an Android device or emulator. iOS is not configured.

## Demo mode

The camera is the weakest link in a live demo, so there are two fallbacks,
reachable from the flask icon in the app bar or the **Demo** button:

1. **Compliant bill** — expects **0 flags**.
2. **Non-compliant bill** — expects **4 flags** (automatic service charge,
   GST on the service charge, an invalid 8% slab, and a malformed GSTIN).
3. **Unreadable scan** — demonstrates notes instead of accusations.

Demo fixtures with receipt text run through the *real* parser, not a
pre-built object, so demo mode exercises the same code path a camera scan
would.

### Printable bills

`demo/compliant_bill.txt` and `demo/non_compliant_bill.txt` are the same two
bills formatted as printed receipts. Print them in a monospaced font and scan
them with the camera for a live end-to-end demo that does not depend on
finding a real restaurant bill. They are asserted in the test suite to parse
to the same verdicts as the in-memory fixtures.

### The worked example

The non-compliant bill is arithmetic the audience can follow:

```
Subtotal                        1200.00
Service charge (10%)             120.00   <- cannot be automatic
                                --------
GST base actually used          1320.00   <- should have been 1200.00
GST @ 8%                         105.60   <- 8% is not a valid slab
                                --------
Grand total                     1425.60

Lawful GST on the subtotal alone: 8% of 1200.00 = 96.00
Tax overcharged:                                    9.60
```

## Explanation layer

`ExplanationService` has two implementations behind one interface.
`TemplateExplanationService` stitches the flags into a single paragraph the
user can read out at the billing counter, including the National Consumer
Helpline number. It is deterministic and always available.

`LocalLlmExplanationService` is a wired-up placeholder that currently
delegates to the template version. An on-device model is deliberately *not*
bundled: a working template summary is worth more in a demo than a
half-integrated LLM, and the rule engine — not a language model — must stay
the source of truth for whether a bill is unlawful.

## Limitations

- OCR accuracy on creased, glossy, or dimly-lit thermal receipts is the main
  practical constraint. The parser is label-driven and position-independent to
  compensate, but a bill it cannot read is reported as unread.
- Line-item extraction is best-effort; the compliance checks depend on the
  summary block, not the items.
- The 18% slab legitimately applies to restaurants in hotels with room tariffs
  above ₹7,500/night. The app cannot tell from a bill alone which applies, so
  it accepts both 5% and 18% as valid and only flags rates outside them.
- Informational, not legal advice.
