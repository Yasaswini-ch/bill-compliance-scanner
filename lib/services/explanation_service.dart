/// Turns a [ComplianceReport] into one coherent piece of prose the user can
/// read out at the billing counter.
///
/// Pure Dart — no Flutter imports. Two implementations sit behind one
/// interface so a local-LLM version can be dropped in later without the UI
/// changing.
library;

import '../models/bill.dart';
import '../models/compliance_flag.dart';
import '../models/money.dart';

abstract interface class ExplanationService {
  /// A short, plain-language summary of the whole report.
  Future<String> summarize(ComplianceReport report, Bill bill);

  /// Human-readable name, shown in the UI so it is obvious which engine ran.
  String get name;
}

/// String-template implementation. Deterministic, instant, and always
/// available — this is the one the demo relies on.
class TemplateExplanationService implements ExplanationService {
  const TemplateExplanationService();

  @override
  String get name => 'Template';

  @override
  Future<String> summarize(ComplianceReport report, Bill bill) async {
    return buildSummary(report, bill);
  }

  /// Synchronous core, so tests do not need to await.
  String buildSummary(ComplianceReport report, Bill bill) {
    final buffer = StringBuffer();

    if (report.flags.isEmpty) {
      if (report.notes.isEmpty) {
        buffer.write(
          'This bill looks clean. The service charge, GST rate, tax base and '
          'GST registration number were all checked and none of them breach '
          'the rules that apply to restaurant bills in India.',
        );
      } else {
        buffer.write(
          'No violations were found, but this bill could not be checked in '
          'full. ',
        );
        buffer.write(_describeNotes(report.notes));
        buffer.write(
          ' Treat this as "not verified" rather than "clean" — a clearer photo '
          'of the bill would give a definite answer.',
        );
      }
      return buffer.toString();
    }

    // Opening line: how many problems, and what they are worth.
    final count = report.flags.length;
    final plural = count == 1 ? 'issue' : 'issues';
    buffer.write('This bill has $count compliance $plural');

    final money = report.totalAmountAffected;
    if (money > 0) {
      buffer.write(', affecting ${formatRupees(money)} of what you were asked '
          'to pay');
    }
    buffer.write('. ');

    // Body: each violation, in severity order, stitched into flowing prose.
    final ordered = [
      ...report.flags.where((f) => f.severity == FlagSeverity.high),
      ...report.flags.where((f) => f.severity == FlagSeverity.medium),
    ];

    for (var i = 0; i < ordered.length; i++) {
      buffer.write(_connector(i));
      buffer.write(ordered[i].explanation);
      buffer.write(' ');
    }

    // Closing line: what to actually do about it.
    buffer.write(_callToAction(report));

    if (report.notes.isNotEmpty) {
      buffer.write(' ');
      buffer.write(_describeNotes(report.notes));
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _connector(int index) {
    switch (index) {
      case 0:
        return '';
      case 1:
        return 'On top of that, ';
      case 2:
        return 'There is also a further problem. ';
      default:
        return 'Finally, ';
    }
  }

  String _callToAction(ComplianceReport report) {
    final hasServiceChargeFlag =
        report.flags.any((f) => f.id == RuleIds.automaticServiceCharge);

    if (hasServiceChargeFlag) {
      return 'You are entitled to ask for the service charge, and any tax '
          'charged on it, to be removed before you pay. If the restaurant '
          'refuses, you can complain to the National Consumer Helpline on '
          '1915 or file a case with the CCPA.';
    }
    return 'You can raise these points with the restaurant before paying, or '
        'complain to the National Consumer Helpline on 1915 if they are not '
        'corrected.';
  }

  String _describeNotes(List<DataNote> notes) {
    if (notes.isEmpty) return '';
    if (notes.length == 1) {
      return notes.first.message;
    }
    return 'Some checks were skipped: '
        '${notes.map((n) => _lowerFirst(n.message)).join(' ')}';
  }

  String _lowerFirst(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
}

/// Placeholder for an on-device LLM rewrite of the same report.
///
/// Intentionally not wired to a model: a working template summary is worth
/// more than a half-integrated local model. [isAvailable] returns false, and
/// the app falls back to [TemplateExplanationService] automatically, so this
/// class can be filled in later without touching any calling code.
class LocalLlmExplanationService implements ExplanationService {
  final ExplanationService fallback;

  const LocalLlmExplanationService({
    this.fallback = const TemplateExplanationService(),
  });

  @override
  String get name => 'On-device LLM (not loaded)';

  /// Flipped to true once a model is actually bundled and loaded.
  bool get isAvailable => false;

  @override
  Future<String> summarize(ComplianceReport report, Bill bill) async {
    if (!isAvailable) {
      return fallback.summarize(report, bill);
    }
    // A real implementation would prompt the local model here, passing the
    // structured report rather than the raw bill so the model rephrases
    // findings instead of deciding them. The rule engine stays the source of
    // truth either way.
    throw UnimplementedError('No on-device model bundled.');
  }
}
