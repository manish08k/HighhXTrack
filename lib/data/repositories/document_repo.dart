import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/dates.dart';
import '../models/common.dart';
import '../models/planner.dart';
import 'base.dart';

class DocumentRepo extends Repo {
  DocumentRepo(super.db, super.changed);

  Future<List<Doc>> all({String? category, String search = ''}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (category != null) {
      where.add('category=?');
      args.add(category);
    }
    if (search.isNotEmpty) {
      final l = Repo.like(search);
      where.add("(name LIKE ? ESCAPE '\\' OR number LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\')");
      args.addAll([l, l, l]);
    }
    final rows = await db.rawQuery('''
      SELECT d.*, (SELECT COUNT(*) FROM attachments a WHERE a.owner_type='document' AND a.owner_id=d.id) att
      FROM documents d ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY d.expiry_at IS NULL, d.expiry_at ASC, d.name''', args);
    return rows.map((r) => Doc.fromMap(r, attachments: r['att'] as int? ?? 0)).toList();
  }

  Future<Doc?> get(int id) async {
    final rows = await db.query('documents', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Doc.fromMap(rows.first);
  }

  Future<int> save(Doc d) async {
    final int id;
    if (d.id == null) {
      id = await db.insert('documents', d.toMap());
    } else {
      id = d.id!;
      await db.update('documents', d.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.documents);
    return id;
  }

  Future<void> delete(int id) async {
    await AttachmentStore(this).deleteAllFor('document', id);
    await db.delete('documents', where: 'id=?', whereArgs: [id]);
    changed(Chg.documents);
  }
}

/// Stores attachment files under app documents/attachments and their rows.
class AttachmentStore {
  AttachmentStore(this.repo);
  final Repo repo;

  static Future<Directory> dir() async {
    final d = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'attachments'));
    await d.create(recursive: true);
    return d;
  }

  Future<List<Attachment>> list(String ownerType, int ownerId) async {
    final rows = await repo.db.query('attachments', where: 'owner_type=? AND owner_id=?', whereArgs: [ownerType, ownerId], orderBy: 'created_at');
    return rows.map(Attachment.fromMap).toList();
  }

  /// Writes [bytes] into app storage and records it.
  Future<Attachment> add(String ownerType, int ownerId, Uint8List bytes, String name) async {
    final d = await dir();
    final ext = p.extension(name);
    final target = File(p.join(d.path, '${ownerType}_${ownerId}_${DateTime.now().microsecondsSinceEpoch}$ext'));
    await target.writeAsBytes(bytes, flush: true);
    final a = Attachment(
      ownerType: ownerType,
      ownerId: ownerId,
      name: name,
      path: p.basename(target.path),
      size: await target.length(),
      createdAt: DateTime.now(),
    );
    final id = await repo.db.insert('attachments', a.toMap());
    repo.changed(ownerType == 'todo' ? Chg.todo : Chg.documents);
    return Attachment(id: id, ownerType: ownerType, ownerId: ownerId, name: name, path: a.path, size: a.size, createdAt: a.createdAt);
  }

  /// Absolute path for a stored attachment (rows store a relative file name).
  static Future<String> resolve(Attachment a) async => p.join((await dir()).path, a.path);

  Future<void> remove(Attachment a) async {
    await repo.db.delete('attachments', where: 'id=?', whereArgs: [a.id]);
    try {
      await File(await resolve(a)).delete();
    } catch (_) {}
    repo.changed(a.ownerType == 'todo' ? Chg.todo : Chg.documents);
  }

  Future<void> deleteAllFor(String ownerType, int ownerId) async {
    for (final a in await list(ownerType, ownerId)) {
      await remove(a);
    }
  }

  /// Removes attachment rows/files whose owner no longer exists.
  Future<void> cleanupOrphans() async {
    final rows = await repo.db.rawQuery('''
      SELECT * FROM attachments a WHERE
        (a.owner_type='todo' AND NOT EXISTS (SELECT 1 FROM todos t WHERE t.id=a.owner_id)) OR
        (a.owner_type='document' AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.id=a.owner_id))''');
    for (final r in rows) {
      await remove(Attachment.fromMap(r));
    }
  }
}

extension DocDates on Doc {
  /// When the renewal reminder should fire.
  DateTime? get remindAt => expiryAt == null ? null : D.addDays(D.dateOnly(expiryAt!), -remindDays).add(const Duration(hours: 9));
}
