import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../core/utils/dates.dart';
import '../data/db/app_database.dart';
import '../data/repositories/document_repo.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RestoreResult {
  const RestoreResult(this.rows, this.files);
  final int rows;
  final int files;
}

/// Full JSON backup of every table plus attachment files, and CSV exports.
class BackupService {
  BackupService(this.database);
  final AppDatabase database;

  static const format = 'highhxtrack-backup';

  Database get _db => database.db;

  Future<Map<String, Object?>> buildBackup({bool includeFiles = true}) async {
    final tables = <String, Object?>{};
    for (final t in AppDatabase.tables) {
      tables[t] = await _db.query(t);
    }
    final files = <Map<String, String>>[];
    if (includeFiles) {
      final dir = await AttachmentStore.dir();
      for (final r in await _db.query('attachments')) {
        final f = File(p.join(dir.path, r['path'] as String));
        if (await f.exists()) {
          files.add({'path': r['path'] as String, 'data': base64Encode(await f.readAsBytes())});
        }
      }
    }
    return {'format': format, 'schema': AppDatabase.version, 'exported_at': DateTime.now().toIso8601String(), 'tables': tables, 'files': files};
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  Future<Uint8List> backupBytes() async => Uint8List.fromList(utf8.encode(jsonEncode(await buildBackup())));

  String backupFileName() => 'highhxtrack_backup_${_stamp()}.json';

  /// Lets the user pick a location and saves the backup there.
  /// Returns false if the user cancelled.
  Future<bool> saveBackupToDevice() async {
    final uri = await FilePicker.saveFile(fileName: backupFileName(), bytes: await backupBytes(), mimeType: 'application/json');
    return uri != null;
  }

  /// Opens the share sheet with the backup attached (Drive, email…).
  Future<void> shareBackup() async {
    final file = File(p.join((await getTemporaryDirectory()).path, backupFileName()));
    await file.writeAsBytes(await backupBytes(), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'HighhXTrack backup',
      ),
    );
  }

  /// Picks a backup file. Returns null if cancelled.
  Future<Map<String, Object?>?> pickBackup() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    return parse(bytes);
  }

  Map<String, Object?> parse(Uint8List bytes) {
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, Object?> || data['format'] != format || data['tables'] is! Map) {
        throw BackupException('This file is not a HighhXTrack backup.');
      }
      final schema = data['schema'];
      if (schema is! int || schema > AppDatabase.version) {
        throw BackupException('This backup was made by a newer version of the app.');
      }
      return data;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('The backup file is damaged or unreadable.');
    }
  }

  /// Replaces all data with [backup] atomically. A safety copy of the
  /// current data is written first so nothing is lost if the restore was a
  /// mistake.
  Future<RestoreResult> restore(Map<String, Object?> backup) async {
    final safety = File(p.join((await getApplicationDocumentsDirectory()).path, 'pre_restore_backup.json'));
    await safety.writeAsString(jsonEncode(await buildBackup(includeFiles: false)), flush: true);

    final tables = (backup['tables'] as Map).cast<String, Object?>();
    var rows = 0;
    await _db.transaction((tx) async {
      for (final t in AppDatabase.tables.reversed) {
        await tx.delete(t);
      }
      for (final t in AppDatabase.tables) {
        final list = tables[t];
        if (list is! List) continue;
        final cols = (await tx.rawQuery('PRAGMA table_info($t)')).map((r) => r['name'] as String).toSet();
        final batch = tx.batch();
        for (final row in list) {
          if (row is! Map) continue;
          final clean = <String, Object?>{
            for (final e in row.entries)
              if (cols.contains(e.key)) e.key as String: e.value,
          };
          batch.insert(t, clean, conflictAlgorithm: ConflictAlgorithm.replace);
          rows++;
        }
        await batch.commit(noResult: true);
      }
    });

    var files = 0;
    final dir = await AttachmentStore.dir();
    for (final f in (backup['files'] as List?) ?? const []) {
      if (f is! Map) continue;
      final name = p.basename(f['path'] as String? ?? '');
      final data = f['data'] as String?;
      if (name.isEmpty || data == null) continue;
      await File(p.join(dir.path, name)).writeAsBytes(base64Decode(data), flush: true);
      files++;
    }
    return RestoreResult(rows, files);
  }

  // ------------------------------------------------------------ CSV export
  static String _csv(List<List<Object?>> rows) => rows
      .map(
        (r) => r
            .map((v) {
              final s = v?.toString() ?? '';
              return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
            })
            .join(','),
      )
      .join('\n');

  Future<String> transactionsCsv() async {
    final rows = await _db.rawQuery('''
      SELECT t.date_at, t.kind, t.amount, c.name cname, t.payment_method, t.notes FROM transactions t
      LEFT JOIN money_categories c ON c.id=t.category_id ORDER BY t.date_at''');
    return _csv([
      ['Date', 'Type', 'Amount', 'Category', 'Payment method', 'Notes'],
      for (final r in rows)
        [
          D.fromMs(r['date_at'] as int).toIso8601String().substring(0, 10),
          r['kind'] == 1 ? 'Income' : 'Expense',
          ((r['amount'] as int) / 100).toStringAsFixed(2),
          r['cname'] ?? '',
          r['payment_method'],
          r['notes'],
        ],
    ]);
  }

  Future<String> todosCsv() async {
    final rows = await _db.rawQuery('SELECT t.*, c.name cname FROM todos t LEFT JOIN todo_categories c ON c.id=t.category_id ORDER BY t.created_at');
    return _csv([
      ['Title', 'Description', 'Priority', 'Category', 'Due', 'Completed', 'Completed at'],
      for (final r in rows)
        [
          r['title'],
          r['description'],
          const ['Low', 'Medium', 'High'][(r['priority'] as int).clamp(0, 2)],
          r['cname'] ?? '',
          r['due_at'] == null ? '' : D.fromMs(r['due_at'] as int).toIso8601String(),
          r['completed'] == 1 ? 'Yes' : 'No',
          r['completed_at'] == null ? '' : D.fromMs(r['completed_at'] as int).toIso8601String(),
        ],
    ]);
  }

  Future<String> workoutsCsv() async {
    final rows = await _db.rawQuery('''
      SELECT w.started_at, w.name wname, e.name ename, e.muscle, s.position, s.weight, s.reps FROM workout_sets s
      JOIN workout_exercises we ON we.id=s.workout_exercise_id JOIN workouts w ON w.id=we.workout_id
      JOIN exercises e ON e.id=we.exercise_id WHERE s.status=1 ORDER BY w.started_at, we.position, s.position''');
    return _csv([
      ['Date', 'Workout', 'Exercise', 'Muscle', 'Set', 'Weight', 'Reps'],
      for (final r in rows)
        [
          D.fromMs(r['started_at'] as int).toIso8601String().substring(0, 16),
          r['wname'],
          r['ename'],
          r['muscle'],
          (r['position'] as int) + 1,
          r['weight'],
          r['reps'],
        ],
    ]);
  }

  Future<void> shareCsv(String name, String csv) async {
    final file = File(p.join((await getTemporaryDirectory()).path, '${name}_${_stamp()}.csv'));
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'HighhXTrack $name export',
      ),
    );
  }
}
