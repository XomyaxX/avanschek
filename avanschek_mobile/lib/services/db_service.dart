import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/check.dart';
import '../models/report_data.dart';

class DbService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'avanschek.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            organization TEXT,
            department TEXT,
            fio TEXT,
            position TEXT,
            tab_number TEXT,
            purpose TEXT,
            report_number TEXT,
            report_date TEXT,
            advance_received REAL,
            total_amount REAL,
            created_at TEXT,
            xls_path TEXT,
            pdf_path TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE checks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            report_id INTEGER,
            doc_date TEXT,
            doc_number TEXT,
            name TEXT,
            amount REAL,
            created_at TEXT,
            FOREIGN KEY (report_id) REFERENCES reports (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE drafts (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            report_json TEXT,
            checks_json TEXT,
            updated_at TEXT
          )
        ''');
      },
    );
  }

  // ─── Reports ───

  static Future<int> saveReport({
    required ReportData data,
    required List<Check> checks,
    required double totalAmount,
    String? xlsPath,
    String? pdfPath,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final reportId = await db.insert('reports', {
      'organization': data.organization,
      'department': data.department,
      'fio': data.fio,
      'position': data.position,
      'tab_number': data.tabNumber,
      'purpose': data.purpose,
      'report_number': data.reportNumber,
      'report_date': data.reportDate,
      'advance_received': data.advanceReceived,
      'total_amount': totalAmount,
      'created_at': now,
      'xls_path': xlsPath,
      'pdf_path': pdfPath,
    });

    for (final check in checks) {
      await db.insert('checks', {
        'report_id': reportId,
        'doc_date': check.docDate,
        'doc_number': check.docNumber,
        'name': check.name,
        'amount': check.amount,
        'created_at': now,
      });
    }

    return reportId;
  }

  static Future<List<Map<String, dynamic>>> getReports() async {
    final db = await database;
    final reports = await db.query('reports', orderBy: 'created_at DESC');
    return reports;
  }

  static Future<Map<String, dynamic>?> getReportById(int id) async {
    final db = await database;
    final results = await db.query('reports', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return results.first;
  }

  static Future<List<Map<String, dynamic>>> getChecksForReport(int reportId) async {
    final db = await database;
    return db.query('checks', where: 'report_id = ?', whereArgs: [reportId]);
  }

  static Future<void> deleteReport(int id) async {
    final db = await database;
    await db.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Drafts ───

  static Future<void> saveDraft(ReportData data, List<Check> checks) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final reportMap = {
      'organization': data.organization,
      'department': data.department,
      'fio': data.fio,
      'position': data.position,
      'tab_number': data.tabNumber,
      'purpose': data.purpose,
      'report_number': data.reportNumber,
      'report_date': data.reportDate,
      'advance_received': data.advanceReceived,
    };

    final checksList = checks.map((c) => {
      'doc_date': c.docDate,
      'doc_number': c.docNumber,
      'name': c.name,
      'amount': c.amount,
    }).toList();

    await db.insert(
      'drafts',
      {
        'id': 1,
        'report_json': jsonEncode(reportMap),
        'checks_json': jsonEncode(checksList),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getDraft() async {
    final db = await database;
    final results = await db.query('drafts', where: 'id = ?', whereArgs: [1]);
    if (results.isEmpty) return null;
    return results.first;
  }

  static Future<void> clearDraft() async {
    final db = await database;
    await db.delete('drafts', where: 'id = ?', whereArgs: [1]);
  }
}
