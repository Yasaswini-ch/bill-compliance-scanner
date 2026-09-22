/// Output types for the rule engine. Pure Dart — no Flutter imports.
library;

enum FlagSeverity { high, medium }

/// Stable identifiers for the four checks. Used by tests and the UI.
abstract final class RuleIds {
  static const String automaticServiceCharge = 'AUTOMATIC_SERVICE_CHARGE';
  static const String gstOnServiceCharge = 'GST_ON_SERVICE_CHARGE';
  static const String gstSlabMismatch = 'GST_SLAB_MISMATCH';
  static const String gstinInvalid = 'GSTIN_INVALID';
}

/// A single detected compliance violation.
class ComplianceFlag {
  final String id;
  final FlagSeverity severity;
  final String title;

  /// Plain-language explanation, 2-3 sentences, written to be read aloud to
  /// a restaurant manager.
  final String explanation;

  final String citedRule;

  /// The rupee amount this violation puts at stake, where one applies.
  final double? amountAffected;

  const ComplianceFlag({
    required this.id,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.citedRule,
    this.amountAffected,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'title': title,
        'explanation': explanation,
        'citedRule': citedRule,
        'amountAffected': amountAffected,
      };

  factory ComplianceFlag.fromJson(Map<String, dynamic> json) => ComplianceFlag(
        id: json['id'] as String,
        severity: FlagSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => FlagSeverity.medium,
        ),
        title: json['title'] as String,
        explanation: json['explanation'] as String,
        citedRule: json['citedRule'] as String,
        amountAffected: (json['amountAffected'] as num?)?.toDouble(),
      );

  @override
  String toString() => 'ComplianceFlag($id, ${severity.name})';
}

/// Raised when a check had to be skipped because the data it needs was not
/// readable. Deliberately *not* a violation — an unreadable bill is not an
/// illegal one, and conflating the two would make the app untrustworthy.
class DataNote {
  /// The rule that could not be evaluated.
  final String ruleId;
  final String message;

  const DataNote({required this.ruleId, required this.message});

  Map<String, dynamic> toJson() => {'ruleId': ruleId, 'message': message};

  factory DataNote.fromJson(Map<String, dynamic> json) => DataNote(
        ruleId: json['ruleId'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );

  @override
  String toString() => 'DataNote($ruleId: $message)';
}

/// The full result of evaluating a bill: what was wrong, and what could not
/// be checked.
class ComplianceReport {
  final List<ComplianceFlag> flags;
  final List<DataNote> notes;

  const ComplianceReport({this.flags = const [], this.notes = const []});

  bool get isClean => flags.isEmpty;
  bool get hasNotes => notes.isNotEmpty;

  /// True when nothing was flagged but checks were skipped — the bill is
  /// "not proven clean" rather than "clean", and the UI says so.
  bool get isInconclusive => flags.isEmpty && notes.isNotEmpty;

  int get highSeverityCount =>
      flags.where((f) => f.severity == FlagSeverity.high).length;

  /// Total rupees implicated across all flags that carry an amount.
  double get totalAmountAffected => flags.fold<double>(
        0,
        (sum, f) => sum + (f.amountAffected ?? 0),
      );

  Map<String, dynamic> toJson() => {
        'flags': flags.map((f) => f.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  factory ComplianceReport.fromJson(Map<String, dynamic> json) =>
      ComplianceReport(
        flags: (json['flags'] as List<dynamic>? ?? [])
            .map((e) => ComplianceFlag.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (json['notes'] as List<dynamic>? ?? [])
            .map((e) => DataNote.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  String toString() =>
      'ComplianceReport(${flags.length} flags, ${notes.length} notes)';
}
