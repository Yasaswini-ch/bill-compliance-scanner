# Bill Compliance Scanner

**Point your camera at a restaurant bill. Find out, in two seconds, whether you are being charged illegally — and exactly what to say about it.**

![Platform](https://img.shields.io/badge/platform-Android-3DDC84)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B)
![Tests](https://img.shields.io/badge/tests-27%20passing-2A9D8F)
![Processing](https://img.shields.io/badge/processing-100%25%20on--device-1B3A5C)

---

## The problem

In July 2022, the Central Consumer Protection Authority **banned restaurants from adding a service charge automatically**. Restaurants challenged it. In **March 2025, the Delhi High Court upheld the ban** and dismissed the petitions.

Three and a half years later, it is still on the bill almost everywhere.

The charge itself is only part of it. The more expensive habit is quieter: restaurants add a 10% service charge, then calculate **GST on the inflated total**, taxing a charge that is not a taxable supply in the first place. Every one of those bills carries two violations, and the second one is invisible unless you do arithmetic at the counter while a queue forms behind you.

Individually it's ₹10. Across the roughly **8 million** food-service outlets in India, it is a systematic transfer that persists because verifying it takes information and arithmetic that nobody has while paying.

**That is a solvable problem.** The rules are public, deterministic, and arithmetic. They just need to be applied at the moment the bill arrives.

---

## What it does

Photograph the bill. Everything below happens on the phone, in about two seconds, with no network call.

| # | Check | Severity | Legal basis |
|---|---|---|---|
| 1 | **Automatic service charge** | High | CCPA Guidelines, July 2022 — upheld by the Delhi High Court, March 2025 |
| 2 | **GST charged on top of the service charge** | High | GST applies to the taxable supply of food and service, not to a discretionary charge |
| 3 | **GST rate outside the 5% / 18% restaurant slabs** | Medium | GST Council notified rates for restaurant services |
| 4 | **Missing or malformed GSTIN** | Medium | GST registration requirement, CGST Act |

The result screen gives you the verdict, the rupee amount at stake, the rule that was broken — and a plain-language paragraph you can read out at the counter, ending with the National Consumer Helpline number.

---

## A worked example

This is the bundled demo bill. The violations compound, and the audience can follow every line:

```
Sub Total                       1200.00
Service Charge 10%               120.00   ← cannot be automatic (violation 1)
                                --------
GST base actually used          1320.00   ← should have been 1200.00 (violation 2)
CGST 4%  +  SGST 4%              105.60   ← 8% is not a valid slab (violation 3)
                                --------
Grand Total                     1425.60

Lawful GST = 8% of 1200.00  =      96.00
Actually charged            =     105.60
                                --------
Tax overcharged on a charge that was itself illegal    9.60
```

Add a malformed GSTIN and this bill trips **all four rules**. The app reports ₹120.00 of illegal service charge plus ₹9.60 of tax that should never have existed — an overcharge no diner would catch unaided.

---

## The hard part: never accuse anyone falsely

A naive version of this app is easy and **actively dangerous**. Point OCR at a creased thermal receipt, miss the SGST line, sum what's left, and you confidently tell a user that an honest restaurant is committing tax fraud at 2.5%.

An app that cries wolf is worse than no app. Its entire value is that a stranger trusts its verdict enough to challenge a bill in public.

So the core design rule is:

> **A check that cannot be evaluated is skipped and reported, never guessed.**

Every extracted field carries one of three states, not two:

| State | Meaning | Can support a verdict? |
|---|---|---|
| `found` | Read off the bill | Yes |
| `absent` | The bill read cleanly and genuinely lacks this | Yes |
| `unknown` | Could not be made out | **Never** |

Concrete consequences, each covered by a regression test:

- **A lone CGST line reports the rate as unknown, not as half.** If the SGST line is smudged, summing what's visible yields 2.5% — which looks exactly like an illegal slab. The engine refuses to conclude.
- **"No GSTIN on this bill" is only ever claimed when the rest of the bill read cleanly.** On a poor scan it degrades to "could not verify".
- **A waived or opt-out service charge is lawful** and is not flagged.
- **GST correctly levied on the subtotal alone never trips rule 2**, even when a service charge is present.

The UI carries the distinction through: **"No compliance issues detected"** and **"Not enough was readable to decide"** are different screens, in different colours. The second never masquerades as the first.

---

## Verified, not just written

```
$ flutter analyze
No issues found!

$ flutter test
00:00 +27: All tests passed!
```

The two acceptance criteria hold:

| Fixture | Expected | Actual |
|---|---|---|
| Compliant bill | 0 flags | **0 flags**, 0 skipped checks |
| Non-compliant bill | Service charge + GST-on-SC + bad slab | **All 4 rules fire**, ₹9.60 overcharge computed |

Both printable receipts in [`demo/`](demo/) are asserted to parse through the **real** `BillParser` to the same verdicts as the in-memory fixtures — the printed-bill path is genuinely the same code, not a second hardcoded route.

---

## Try it in 60 seconds

```bash
flutter pub get
flutter test      # 27 tests, no device needed
flutter run       # Android device or emulator
```

No device handy? `flutter test` exercises the entire rule engine, parser and GSTIN validator — the whole decision layer runs without Flutter.

**In the app**, tap the flask icon for **Demo Mode**: a compliant bill, a non-compliant bill, and an unreadable scan. Demo fixtures run through the real parser, so demo mode exercises the same path a camera scan does.

**For a live demo**, print [`demo/non_compliant_bill.txt`](demo/non_compliant_bill.txt) in a monospaced font and scan the paper. Three independent capture paths — live camera, gallery import, demo mode — because a camera is the most fragile part of any live demo.

---

## Architecture

```
lib/
  models/      Bill, LineItem, ServiceCharge, TaxComponent, ComplianceFlag
  services/    BillParser · RuleEngine · GstinValidator · ExplanationService
               BillScannerService (camera + ML Kit) · HistoryStore (sqflite)
  screens/     ScanScreen · ResultScreen · HistoryScreen
  widgets/     FlagCard · VerdictHeader · BillSummaryCard · NotesCard
  theme/       app_theme.dart
```

`BillParser`, `RuleEngine`, `GstinValidator` and `TemplateExplanationService` are **pure Dart with zero Flutter imports** — data in, data out. They are unit-tested directly and survive a UI rewrite untouched. `AppState` (provider) only sequences the pipeline: OCR → parse → evaluate → explain → persist.

**Parsing is label-driven and position-independent.** A photographed receipt returns reordered, split and misspelled lines, so nothing depends on line numbers. Labels match against a letters-only form, collapsing `S.CHARGE`, `S CHARGE` and `SCHARGE`; specific labels are tested before general ones so `CGST` is never swallowed by `GST`. Digit repair (`O→0`, `I→1`) applies only inside runs that are already majority-digit, leaving words alone.

**GSTIN validation is real**, not a length check: 15-character structure, state code against the issued list, and the official **mod-36 checksum**. A checksum failure is reported at medium severity with an explicit note that a single misread character can cause it.

---

## On the LLM question

`ExplanationService` has two implementations behind one interface. `TemplateExplanationService` composes the findings into a single counter-ready paragraph — deterministic, instant, always available. `LocalLlmExplanationService` is wired to the same interface and currently delegates to it.

**No on-device model is bundled, and that is deliberate.** A language model must never decide whether a bill is unlawful — that is the rule engine's job, and it has to be auditable, deterministic and defensible in front of a restaurant manager. An LLM's only legitimate role here is rephrasing findings the engine already made. That is a genuine improvement in tone, and a poor use of the last hours before a deadline. The interface is ready when the improvement is worth it.

---

## Status and roadmap

**Working today:** all four rules, camera and gallery capture, on-device OCR, parser, result screen, local scan history, demo mode, printable fixtures, 27 tests.

**Next, in priority order:**

1. **OCR accuracy on real thermal receipts** — the one thing standing between a working prototype and a usable product. Needs a corpus of real bills, not synthetic ones.
2. **One-tap complaint filing** — pre-fill a National Consumer Helpline (1915) complaint from the flags, which is where detection turns into consequence.
3. **Aggregate reporting** — with consent, anonymised flags reveal which chains do this systematically. Individually ₹10; in aggregate, evidence.
4. **More rules** — MRP violations on packaged water and beverages, duplicate taxes, incorrect rounding.
5. **Regional language bills** and the 18% hotel-restaurant slab via room-tariff detection.

---

## Limitations

Stated plainly, because a compliance tool that overstates itself has missed its own point:

- **OCR on creased, glossy or dimly-lit thermal receipts is the real constraint.** The parser compensates with label-driven matching, but a bill it cannot read is reported as unread rather than guessed at.
- **Line-item extraction is best-effort.** The compliance checks depend on the summary block, not the items.
- **The 18% slab is legitimate** for restaurants in hotels with room tariffs above ₹7,500/night. A bill alone cannot always establish which applies, so both 5% and 18% are accepted and only rates outside them are flagged.
- **Informational, not legal advice.** Always check the printed bill before raising a complaint.

---

## References

- Central Consumer Protection Authority, *Guidelines for Prevention of Unfair Trade Practices and Violation of Consumer Rights levying Service Charge in Hotels and Restaurants*, 4 July 2022
- Delhi High Court, judgment upholding the CCPA guidelines, March 2025
- GST Council notified rates for restaurant services (5% without ITC; 18% for specified hotel restaurants)
- Central Goods and Services Tax Act, 2017 — GST registration and invoice requirements
