/// GSTIN format + checksum validation. Pure Dart, no Flutter imports.
///
/// A GSTIN is 15 characters:
///   [0-1]   state code (2 digits)
///   [2-11]  PAN (5 letters, 4 digits, 1 letter)
///   [12]    entity code for that PAN (1-9 or A-Z)
///   [13]    literal 'Z'
///   [14]    checksum character (0-9 or A-Z)
library;

class GstinValidator {
  /// Strict structural pattern for a well-formed GSTIN.
  static final RegExp strictPattern =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  /// Loose pattern used to *find* a GSTIN-shaped token inside noisy OCR text.
  /// Deliberately permissive so a misread character still gets extracted and
  /// can then be reported as malformed rather than silently missed.
  static final RegExp searchPattern = RegExp(r'\b[0-9O]{2}[A-Z0-9]{13}\b');

  /// Valid Indian state/UT codes (01-38, plus 97 for other territory and
  /// 99 for centre jurisdiction).
  static const Set<String> _stateCodes = {
    '01', '02', '03', '04', '05', '06', '07', '08', '09', '10',
    '11', '12', '13', '14', '15', '16', '17', '18', '19', '20',
    '21', '22', '23', '24', '25', '26', '27', '28', '29', '30',
    '31', '32', '33', '34', '35', '36', '37', '38', '97', '99',
  };

  static const String _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// True when [value] matches the 15-character GSTIN structure.
  static bool hasValidFormat(String? value) {
    if (value == null) return false;
    final v = normalize(value);
    return v.length == 15 && strictPattern.hasMatch(v);
  }

  /// True when the state-code prefix is one that actually exists.
  static bool hasValidStateCode(String? value) {
    if (value == null) return false;
    final v = normalize(value);
    if (v.length < 2) return false;
    return _stateCodes.contains(v.substring(0, 2));
  }

  /// Validates the 15th character using the official mod-36 checksum.
  static bool hasValidChecksum(String? value) {
    if (value == null) return false;
    final v = normalize(value);
    if (v.length != 15) return false;
    final expected = computeCheckCharacter(v.substring(0, 14));
    if (expected == null) return false;
    return expected == v[14];
  }

  /// Computes the checksum character for the first 14 characters of a GSTIN.
  /// Returns null if the input contains characters outside 0-9/A-Z.
  static String? computeCheckCharacter(String first14) {
    final v = normalize(first14);
    if (v.length != 14) return null;
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      final code = _alphabet.indexOf(v[i]);
      if (code < 0) return null;
      final factor = i.isEven ? 1 : 2;
      final product = code * factor;
      sum += (product ~/ 36) + (product % 36);
    }
    final checkCode = (36 - (sum % 36)) % 36;
    return _alphabet[checkCode];
  }

  /// Uppercases and strips spaces/punctuation that OCR tends to sprinkle in.
  static String normalize(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

  /// Builds a complete, checksum-valid GSTIN from a 14-character stem.
  /// Used by the demo fixtures so the "compliant" bill really does validate.
  static String? complete(String first14) {
    final check = computeCheckCharacter(first14);
    if (check == null) return null;
    return normalize(first14) + check;
  }
}
