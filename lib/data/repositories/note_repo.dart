import '../../core/utils/dates.dart';
import '../models/knowledge.dart';
import 'base.dart';

class NoteQuery {
  const NoteQuery({this.folderId, this.tag, this.archived = false, this.search = ''});
  final int? folderId;
  final String? tag;
  final bool archived;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is NoteQuery && other.folderId == folderId && other.tag == tag && other.archived == archived && other.search == search;

  @override
  int get hashCode => Object.hash(folderId, tag, archived, search);
}

class NoteRepo extends Repo {
  NoteRepo(super.db, super.changed);

  Future<List<Note>> query(NoteQuery q) async {
    final where = <String>['archived=?'];
    final args = <Object?>[q.archived ? 1 : 0];
    if (q.folderId != null) {
      where.add('folder_id=?');
      args.add(q.folderId);
    }
    if (q.tag != null) {
      where.add("(',' || tags || ',') LIKE ? ESCAPE '\\'");
      args.add(Repo.like(',${q.tag},'));
    }
    if (q.search.trim().isNotEmpty) {
      final l = Repo.like(q.search.trim());
      where.add("(title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\' OR checklist LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\')");
      args.addAll([l, l, l, l]);
    }
    final rows = await db.query('notes', where: where.join(' AND '), whereArgs: args, orderBy: 'pinned DESC, updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Note?> get(int id) async {
    final rows = await db.query('notes', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  Future<List<String>> tags() async {
    final rows = await db.query('notes', columns: ['tags'], where: "archived=0 AND tags<>''");
    final set = <String>{};
    for (final r in rows) {
      set.addAll((r['tags'] as String).split(',').map((t) => t.trim()).where((t) => t.isNotEmpty));
    }
    return set.toList()..sort();
  }

  Future<int> save(Note n) async {
    final map = n.toMap()..['updated_at'] = D.ms(DateTime.now());
    final int id;
    if (n.id == null) {
      id = await db.insert('notes', map);
    } else {
      id = n.id!;
      await db.update('notes', map, where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.notes);
    return id;
  }

  Future<void> setFlags(int id, {bool? pinned, bool? archived}) async {
    await db.update(
      'notes',
      {'pinned': ?(pinned == null ? null : (pinned ? 1 : 0)), 'archived': ?(archived == null ? null : (archived ? 1 : 0))},
      where: 'id=?',
      whereArgs: [id],
    );
    changed(Chg.notes);
  }

  Future<Map<String, Object?>?> delete(int id) async {
    final rows = await db.query('notes', where: 'id=?', whereArgs: [id]);
    await db.delete('notes', where: 'id=?', whereArgs: [id]);
    changed(Chg.notes);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> restore(Map<String, Object?> row) async {
    await db.insert('notes', row);
    changed(Chg.notes);
  }

  // ------------------------------------------------------------ folders
  Future<List<NoteFolder>> folders() async {
    final rows = await db.rawQuery(
      'SELECT f.*, (SELECT COUNT(*) FROM notes n WHERE n.folder_id=f.id AND n.archived=0) cnt FROM note_folders f ORDER BY position, id',
    );
    return rows.map(NoteFolder.fromMap).toList();
  }

  Future<int> saveFolder(int? id, String name) async {
    final int out;
    if (id == null) {
      out = await db.insert('note_folders', {'name': name});
    } else {
      out = id;
      await db.update('note_folders', {'name': name}, where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.notes);
    return out;
  }

  Future<void> deleteFolder(int id) async {
    await db.delete('note_folders', where: 'id=?', whereArgs: [id]);
    changed(Chg.notes);
  }
}
