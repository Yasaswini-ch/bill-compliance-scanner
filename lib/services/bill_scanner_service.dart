import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Result of an on-device OCR pass over a bill photo.
class OcrResult {
  final String text;

  /// False when the image produced too little text to be worth parsing —
  /// the caller shows "retake photo" instead of parsing noise.
  final bool isUsable;

  final String? errorMessage;

  const OcrResult({
    required this.text,
    required this.isUsable,
    this.errorMessage,
  });

  const OcrResult.failure(String message)
      : text = '',
        isUsable = false,
        errorMessage = message;
}

/// Wraps ML Kit's on-device text recognition. Everything runs locally: no
/// bill image or its contents ever leaves the phone.
class BillScannerService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// A bill that scanned properly yields far more than this; below it, the
  /// photo is blurred, mis-framed, or of something that is not a bill.
  static const int _minUsableCharacters = 40;
  static const int _minUsableLines = 4;

  Future<OcrResult> recognizeFile(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return const OcrResult.failure('The captured image could not be found.');
      }

      final input = InputImage.fromFilePath(imagePath);
      final recognized = await _recognizer.processImage(input);

      // Rebuild the text block by block. ML Kit's own `text` property is
      // usually fine, but assembling from blocks keeps related lines together
      // when a receipt is photographed at an angle.
      final buffer = StringBuffer();
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          buffer.writeln(line.text);
        }
      }
      final text = buffer.toString().trim().isEmpty
          ? recognized.text
          : buffer.toString();

      return OcrResult(
        text: text,
        isUsable: _isUsable(text),
      );
    } catch (e) {
      return OcrResult.failure('Could not read the image: $e');
    }
  }

  bool _isUsable(String text) {
    final trimmed = text.trim();
    if (trimmed.length < _minUsableCharacters) return false;
    final lines = trimmed
        .split(RegExp(r'[\r\n]+'))
        .where((l) => l.trim().isNotEmpty)
        .length;
    if (lines < _minUsableLines) return false;
    // A bill always carries numbers; a page of prose is not a bill.
    return RegExp(r'\d').hasMatch(trimmed);
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}
