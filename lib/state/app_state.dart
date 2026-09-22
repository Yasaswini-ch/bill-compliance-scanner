import 'package:flutter/foundation.dart';

import '../models/bill.dart';
import '../models/compliance_flag.dart';
import '../services/bill_parser.dart';
import '../services/bill_scanner_service.dart';
import '../services/explanation_service.dart';
import '../services/history_store.dart';
import '../services/rule_engine.dart';

enum ScanStatus { idle, processing, success, unreadable, error }

/// Owns the scan → parse → evaluate → explain pipeline and the resulting UI
/// state. The heavy lifting lives in the pure services; this class only
/// sequences them and notifies listeners.
class AppState extends ChangeNotifier {
  final BillScannerService scanner;
  final BillParser parser;
  final RuleEngine ruleEngine;
  final ExplanationService explanationService;
  final HistoryStore historyStore;

  AppState({
    BillScannerService? scanner,
    this.parser = const BillParser(),
    this.ruleEngine = const RuleEngine(),
    this.explanationService = const TemplateExplanationService(),
    HistoryStore? historyStore,
  })  : scanner = scanner ?? BillScannerService(),
        historyStore = historyStore ?? HistoryStore();

  ScanStatus _status = ScanStatus.idle;
  ScanStatus get status => _status;

  Bill? _bill;
  Bill? get bill => _bill;

  ComplianceReport? _report;
  ComplianceReport? get report => _report;

  String _summary = '';
  String get summary => _summary;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<ScanRecord> _history = const [];
  List<ScanRecord> get history => _history;

  bool get isBusy => _status == ScanStatus.processing;

  /// Runs a captured image through the full pipeline.
  Future<void> processImage(String imagePath, {String source = 'camera'}) async {
    _status = ScanStatus.processing;
    _errorMessage = null;
    notifyListeners();

    final ocr = await scanner.recognizeFile(imagePath);

    if (!ocr.isUsable) {
      _status = ScanStatus.unreadable;
      _errorMessage = ocr.errorMessage ??
          "Couldn't read the bill clearly — retake the photo with the whole "
              'bill inside the frame and good light.';
      notifyListeners();
      return;
    }

    final parsed = parser.parse(ocr.text, source: source);
    await _evaluate(parsed);
  }

  /// Bypasses OCR entirely, for demo mode and printed-fixture testing.
  Future<void> loadBill(Bill bill) async {
    _status = ScanStatus.processing;
    _errorMessage = null;
    notifyListeners();
    await _evaluate(bill);
  }

  /// Runs the parser over raw text without a camera — used by demo mode to
  /// exercise the real parsing path from the printed fixture text.
  Future<void> processText(String rawText, {String source = 'demo'}) async {
    _status = ScanStatus.processing;
    _errorMessage = null;
    notifyListeners();
    await _evaluate(parser.parse(rawText, source: source));
  }

  Future<void> _evaluate(Bill bill) async {
    final report = ruleEngine.analyze(bill);
    String summary;
    try {
      summary = await explanationService.summarize(report, bill);
    } catch (e) {
      // An explanation failure must never hide the findings themselves.
      summary = '';
      debugPrint('Explanation failed: $e');
    }

    _bill = bill;
    _report = report;
    _summary = summary;
    _status = ScanStatus.success;
    notifyListeners();

    // History is a convenience; a storage failure must not break the scan.
    try {
      await historyStore.save(bill, report);
      await refreshHistory();
    } catch (e) {
      debugPrint('History save failed: $e');
    }
  }

  Future<void> refreshHistory() async {
    try {
      _history = await historyStore.loadAll();
      notifyListeners();
    } catch (e) {
      debugPrint('History load failed: $e');
    }
  }

  Future<void> clearHistory() async {
    try {
      await historyStore.clear();
      _history = const [];
      notifyListeners();
    } catch (e) {
      debugPrint('History clear failed: $e');
    }
  }

  void showRecord(ScanRecord record) {
    _bill = record.bill;
    _report = record.report;
    _summary = const TemplateExplanationService()
        .buildSummary(record.report, record.bill);
    _status = ScanStatus.success;
    notifyListeners();
  }

  void reset() {
    _status = ScanStatus.idle;
    _bill = null;
    _report = null;
    _summary = '';
    _errorMessage = null;
    notifyListeners();
  }

  void reportError(String message) {
    _status = ScanStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    scanner.dispose();
    historyStore.close();
    super.dispose();
  }
}
