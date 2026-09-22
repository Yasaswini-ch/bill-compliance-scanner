/// Structured representation of a scanned bill. Pure Dart — no Flutter
/// imports — so the parser and rule engine stay trivially unit testable.
library;

/// Whether a field was read off the bill, confirmed to be absent from it, or
/// simply could not be made out. The rule engine treats these very
/// differently: "confirmed absent" can justify a conclusion, "unknown" never
/// may, because a false accusation from unreadable text is worse than silence.
enum DetectionStatus {
  /// The value was located on the bill.
  found,

  /// The bill was read well enough to be confident this field is not on it.
  absent,

  /// The text was too poor to tell either way.
  unknown,
}

/// A value plus the story of how confidently it was obtained.
class Detected<T> {
  final T? value;
  final DetectionStatus status;

  /// The raw OCR line the value came from, kept for display and debugging.
  final String? source;

  const Detected._(this.value, this.status, this.source);

  const Detected.found(T value, {String? source})
      : this._(value, DetectionStatus.found, source);

  const Detected.absent() : this._(null, DetectionStatus.absent, null);

  const Detected.unknown() : this._(null, DetectionStatus.unknown, null);

  bool get isFound => status == DetectionStatus.found && value != null;
  bool get isAbsent => status == DetectionStatus.absent;
  bool get isUnknown => status == DetectionStatus.unknown;

  @override
  String toString() => 'Detected(${status.name}, $value)';
}

/// How much of the bill the OCR pass actually managed to read. Gates the
/// checks that reason from something being missing.
enum ReadQuality {
  /// Structure recognised: totals and tax lines line up.
  good,

  /// Some anchors found, but the read is patchy.
  partial,

  /// Little usable text — conclusions from absence are not safe.
  poor,
}

class LineItem {
  final String name;
  final double? price;
  final int quantity;

  const LineItem({required this.name, this.price, this.quantity = 1});

  Map<String, dynamic> toJson() =>
      {'name': name, 'price': price, 'quantity': quantity};

  factory LineItem.fromJson(Map<String, dynamic> json) => LineItem(
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );

  @override
  String toString() => '$name x$quantity: $price';
}

/// A service charge line as printed on the bill.
class ServiceCharge {
  final double? amount;

  /// The percentage as *labelled* on the bill, e.g. "10%" — kept as a string
  /// because bills print this inconsistently ("10%", "@10", "10 PCT").
  final String? percentLabel;

  /// True when the bill shows the charge was waived, zeroed, or explicitly
  /// described as voluntary/opt-out. Suppresses the automatic-charge flag.
  final bool looksOptedOut;

  const ServiceCharge({
    this.amount,
    this.percentLabel,
    this.looksOptedOut = false,
  });

  /// The numeric value behind [percentLabel], when one can be read out of it.
  double? get percent {
    if (percentLabel == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(percentLabel!);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'percentLabel': percentLabel,
        'looksOptedOut': looksOptedOut,
      };

  factory ServiceCharge.fromJson(Map<String, dynamic> json) => ServiceCharge(
        amount: (json['amount'] as num?)?.toDouble(),
        percentLabel: json['percentLabel'] as String?,
        looksOptedOut: json['looksOptedOut'] as bool? ?? false,
      );

  @override
  String toString() => 'ServiceCharge($amount, $percentLabel, optedOut=$looksOptedOut)';
}

/// One tax component (CGST, SGST, or a single combined GST line).
class TaxComponent {
  final double? amount;
  final double? percent;

  const TaxComponent({this.amount, this.percent});

  Map<String, dynamic> toJson() => {'amount': amount, 'percent': percent};

  factory TaxComponent.fromJson(Map<String, dynamic> json) => TaxComponent(
        amount: (json['amount'] as num?)?.toDouble(),
        percent: (json['percent'] as num?)?.toDouble(),
      );

  @override
  String toString() => 'Tax($amount @ $percent%)';
}

class Bill {
  final List<LineItem> items;
  final Detected<double> subtotal;
  final Detected<ServiceCharge> serviceCharge;
  final Detected<TaxComponent> cgst;
  final Detected<TaxComponent> sgst;

  /// Some bills print a single "GST 5%" line instead of splitting CGST/SGST.
  final Detected<TaxComponent> gstCombined;

  final Detected<String> gstin;
  final Detected<double> total;

  final ReadQuality readQuality;

  /// Raw OCR output, retained so the user can see what the scan actually read.
  final String rawText;

  /// Where this bill came from — a camera scan, the gallery, or demo mode.
  final String source;

  final DateTime scannedAt;

  Bill({
    this.items = const [],
    this.subtotal = const Detected.unknown(),
    this.serviceCharge = const Detected.unknown(),
    this.cgst = const Detected.unknown(),
    this.sgst = const Detected.unknown(),
    this.gstCombined = const Detected.unknown(),
    this.gstin = const Detected.unknown(),
    this.total = const Detected.unknown(),
    this.readQuality = ReadQuality.poor,
    this.rawText = '',
    this.source = 'scan',
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  /// Combined GST amount, but only when it can be established without
  /// guessing. Returns null if only half of a CGST/SGST pair was read —
  /// half a pair would understate the tax and manufacture a false violation.
  double? get totalGstAmount {
    final c = cgst.value?.amount;
    final s = sgst.value?.amount;
    if (c != null && s != null) return c + s;
    if (c == null && s == null) return gstCombined.value?.amount;
    // Exactly one half of the pair was readable: refuse to guess, unless the
    // other half is confirmed genuinely absent from the bill.
    if (c != null && sgst.isAbsent) return c;
    if (s != null && cgst.isAbsent) return s;
    return null;
  }

  /// Combined GST percentage, subject to the same "never guess" rule.
  double? get totalGstPercent {
    final c = cgst.value?.percent;
    final s = sgst.value?.percent;
    if (c != null && s != null) return c + s;
    if (c == null && s == null) return gstCombined.value?.percent;
    if (c != null && sgst.isAbsent) return c;
    if (s != null && cgst.isAbsent) return s;
    return null;
  }

  /// True when there is a service charge with a real, non-zero amount.
  bool get hasServiceCharge =>
      serviceCharge.isFound && (serviceCharge.value?.amount ?? 0) > 0;

  Bill copyWith({
    List<LineItem>? items,
    Detected<double>? subtotal,
    Detected<ServiceCharge>? serviceCharge,
    Detected<TaxComponent>? cgst,
    Detected<TaxComponent>? sgst,
    Detected<TaxComponent>? gstCombined,
    Detected<String>? gstin,
    Detected<double>? total,
    ReadQuality? readQuality,
    String? rawText,
    String? source,
    DateTime? scannedAt,
  }) {
    return Bill(
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      cgst: cgst ?? this.cgst,
      sgst: sgst ?? this.sgst,
      gstCombined: gstCombined ?? this.gstCombined,
      gstin: gstin ?? this.gstin,
      total: total ?? this.total,
      readQuality: readQuality ?? this.readQuality,
      rawText: rawText ?? this.rawText,
      source: source ?? this.source,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  // ---------------------------------------------------------------------
  // Serialisation, used by the local history store.
  // ---------------------------------------------------------------------

  static Map<String, dynamic> _detectedToJson<T>(
      Detected<T> d, Object? Function(T) encode) {
    return {
      'status': d.status.name,
      'value': d.value == null ? null : encode(d.value as T),
      'source': d.source,
    };
  }

  static Detected<T> _detectedFromJson<T>(
      Map<String, dynamic>? json, T Function(Object) decode) {
    if (json == null) return Detected<T>.unknown();
    final status = DetectionStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => DetectionStatus.unknown,
    );
    final raw = json['value'];
    if (status == DetectionStatus.found && raw != null) {
      return Detected<T>.found(decode(raw), source: json['source'] as String?);
    }
    if (status == DetectionStatus.absent) return Detected<T>.absent();
    return Detected<T>.unknown();
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'subtotal': _detectedToJson<double>(subtotal, (v) => v),
        'serviceCharge': _detectedToJson<ServiceCharge>(serviceCharge, (v) => v.toJson()),
        'cgst': _detectedToJson<TaxComponent>(cgst, (v) => v.toJson()),
        'sgst': _detectedToJson<TaxComponent>(sgst, (v) => v.toJson()),
        'gstCombined': _detectedToJson<TaxComponent>(gstCombined, (v) => v.toJson()),
        'gstin': _detectedToJson<String>(gstin, (v) => v),
        'total': _detectedToJson<double>(total, (v) => v),
        'readQuality': readQuality.name,
        'rawText': rawText,
        'source': source,
        'scannedAt': scannedAt.toIso8601String(),
      };

  factory Bill.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? sub(String key) =>
        json[key] as Map<String, dynamic>?;

    return Bill(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => LineItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotal: _detectedFromJson<double>(
          sub('subtotal'), (v) => (v as num).toDouble()),
      serviceCharge: _detectedFromJson<ServiceCharge>(sub('serviceCharge'),
          (v) => ServiceCharge.fromJson(v as Map<String, dynamic>)),
      cgst: _detectedFromJson<TaxComponent>(
          sub('cgst'), (v) => TaxComponent.fromJson(v as Map<String, dynamic>)),
      sgst: _detectedFromJson<TaxComponent>(
          sub('sgst'), (v) => TaxComponent.fromJson(v as Map<String, dynamic>)),
      gstCombined: _detectedFromJson<TaxComponent>(sub('gstCombined'),
          (v) => TaxComponent.fromJson(v as Map<String, dynamic>)),
      gstin: _detectedFromJson<String>(sub('gstin'), (v) => v as String),
      total: _detectedFromJson<double>(
          sub('total'), (v) => (v as num).toDouble()),
      readQuality: ReadQuality.values.firstWhere(
        (q) => q.name == json['readQuality'],
        orElse: () => ReadQuality.poor,
      ),
      rawText: json['rawText'] as String? ?? '',
      source: json['source'] as String? ?? 'scan',
      scannedAt:
          DateTime.tryParse(json['scannedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'Bill(subtotal=$subtotal, sc=$serviceCharge, cgst=$cgst, sgst=$sgst, '
      'gstin=$gstin, total=$total, quality=${readQuality.name})';
}
