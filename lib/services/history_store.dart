import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/bill.dart';
import '../models/compliance_flag.dart';

/// One past scan, as stored on the device.
class ScanRecord {
  final int? id;
  final Bill bill;
  final ComplianceReport report;
  final DateTime scannedAt;

  const ScanRecord({
    this.id,
    required this.bill,
    required this.report,
    required this.scannedAt,
  });
}

/// Local scan history. Stores each scan as a pair of JSON blobs, which keeps
/// the schema stable as the models evolve — worth more than column purity on
/// a prototype.
class HistoryStore {
  static const String _table = 'scans';
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'bill_scans.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scanned_at TEXT NOT NULL,
            source TEXT NOT NULL,
            flag_count INTEGER NOT NULL,
            bill_json TEXT NOT NULL,
            report_json TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<int> save(Bill bill, ComplianceReport report) async {
    final db = await _open();
    return db.insert(_table, {
      'scanned_at': bill.scannedAt.toIso8601String(),
      'source': bill.source,
      'flag_count': report.flags.length,
      'bill_json': jsonEncode(bill.toJson()),
      'report_json': jsonEncode(report.toJson()),
    });
  }

  Future<List<ScanRecord>> loadAll({int limit = 50}) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      orderBy: 'id DESC',
      limit: limit,
    );

    final records = <ScanRecord>[];
    for (final row in rows) {
      try {
        records.add(ScanRecord(
          id: row['id'] as int?,
          bill: Bill.fromJson(
              jsonDecode(row['bill_json'] as String) as Map<String, dynamic>),
          report: ComplianceReport.fromJson(
              jsonDecode(row['report_json'] as String) as Map<String, dynamic>),
          scannedAt: DateTime.tryParse(row['scanned_at'] as String? ?? '') ??
              DateTime.now(),
        ));
      } catch (_) {
        // A single corrupt row must not take the whole history down.
        continue;
      }
    }
    return records;
  }

  Future<void> delete(int id) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete(_table);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
