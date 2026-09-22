/// Pure Dart money helpers. No Flutter imports — safe to unit test.
library;

/// Formats a rupee amount using the Indian digit grouping convention
/// (last three digits, then groups of two): 1234567.5 -> "₹12,34,567.50".
String formatRupees(num? amount, {bool symbol = true}) {
  if (amount == null) return '—';
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final fraction = parts[1];

  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final lastThree = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final buffer = <String>[];
    while (rest.length > 2) {
      buffer.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) buffer.insert(0, rest);
    grouped = '${buffer.join(',')},$lastThree';
  }

  final body = '$grouped.$fraction';
  final prefix = symbol ? '₹' : '';
  return negative ? '-$prefix$body' : '$prefix$body';
}

/// Formats a percentage without trailing zeros where they add nothing:
/// 5.0 -> "5%", 2.5 -> "2.5%".
String formatPercent(num? value) {
  if (value == null) return '—';
  final asDouble = value.toDouble();
  final text = asDouble == asDouble.roundToDouble()
      ? asDouble.toStringAsFixed(0)
      : asDouble.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$text%';
}

/// Rounds to 2 decimals, which is the precision printed bills actually use.
double roundPaise(double value) => (value * 100).roundToDouble() / 100;
