import '../../core/modules.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import 'base.dart';

class SearchHit {
  const SearchHit(this.module, this.id, this.title, this.subtitle, {this.parentId, this.kind});
  final AppModule module;
  final int id;
  final String title;
  final String subtitle;

  /// e.g. subject id for a topic hit.
  final int? parentId;

  /// Sub-type within a module ('exercise', 'topic', 'subject', ...).
  final String? kind;
}

/// One query across every module, grouped by module.
class SearchRepo extends Repo {
  SearchRepo(super.db, super.changed);

  Future<Map<AppModule, List<SearchHit>>> search(String query, {int perModule = 8}) async {
    final q = query.trim();
    final out = <AppModule, List<SearchHit>>{};
    if (q.isEmpty) return out;
    final l = Repo.like(q);
    const esc = "ESCAPE '\\'";
    final lim = perModule;

    void put(AppModule m, List<SearchHit> hits) {
      if (hits.isNotEmpty) out[m] = hits;
    }

    final todos = await db.query(
      'todos',
      where: 'title LIKE ? $esc OR description LIKE ? $esc OR notes LIKE ? $esc',
      whereArgs: [l, l, l],
      orderBy: 'completed, due_at IS NULL, due_at',
      limit: lim,
    );
    put(AppModule.todo, [
      for (final r in todos)
        SearchHit(
          AppModule.todo,
          r['id'] as int,
          r['title'] as String,
          [if (r['completed'] == 1) 'Completed', if (r['due_at'] != null) 'Due ${D.relativeDay(D.fromMs(r['due_at'] as int))}'].join(' · '),
        ),
    ]);

    final ex = await db.query('exercises', where: 'archived=0 AND (name LIKE ? $esc OR notes LIKE ? $esc)', whereArgs: [l, l], limit: lim);
    final workouts = await db.query('workouts', where: 'name LIKE ? $esc OR notes LIKE ? $esc', whereArgs: [l, l], orderBy: 'started_at DESC', limit: 4);
    put(AppModule.gym, [
      for (final r in ex) SearchHit(AppModule.gym, r['id'] as int, r['name'] as String, 'Exercise · ${_cap(r['muscle'] as String)}', kind: 'exercise'),
      for (final r in workouts)
        SearchHit(AppModule.gym, r['id'] as int, r['name'] as String, 'Workout · ${D.dayMonthYear(D.fromMs(r['started_at'] as int))}', kind: 'workout'),
    ]);

    final tx = await db.rawQuery(
      '''
      SELECT t.*, c.name cname FROM transactions t LEFT JOIN money_categories c ON c.id=t.category_id
      WHERE t.notes LIKE ? $esc OR c.name LIKE ? $esc OR t.payment_method LIKE ? $esc
      ORDER BY t.date_at DESC LIMIT $lim''',
      [l, l, l],
    );
    put(AppModule.money, [
      for (final r in tx)
        SearchHit(
          AppModule.money,
          r['id'] as int,
          (r['notes'] as String).isEmpty ? (r['cname'] as String? ?? 'Transaction') : r['notes'] as String,
          '${r['kind'] == 1 ? '+' : '-'}${Money.format(r['amount'] as int)} · ${r['cname'] ?? 'Uncategorized'} · ${D.dayMonth(D.fromMs(r['date_at'] as int))}',
        ),
    ]);

    final rem = await db.query('reminders', where: 'title LIKE ? $esc OR notes LIKE ? $esc', whereArgs: [l, l], orderBy: 'completed, due_at', limit: lim);
    put(AppModule.reminders, [
      for (final r in rem)
        SearchHit(
          AppModule.reminders,
          r['id'] as int,
          r['title'] as String,
          r['completed'] == 1 ? 'Completed' : D.relativeDateTime(D.fromMs(r['due_at'] as int)),
        ),
    ]);

    final hab = await db.query('habits', where: 'name LIKE ? $esc', whereArgs: [l], limit: lim);
    put(AppModule.habits, [
      for (final r in hab) SearchHit(AppModule.habits, r['id'] as int, r['name'] as String, r['archived'] == 1 ? 'Archived habit' : 'Habit'),
    ]);

    final ev = await db.query(
      'events',
      where: 'title LIKE ? $esc OR notes LIKE ? $esc OR location LIKE ? $esc',
      whereArgs: [l, l, l],
      orderBy: 'start_at DESC',
      limit: lim,
    );
    put(AppModule.calendar, [
      for (final r in ev)
        SearchHit(AppModule.calendar, r['id'] as int, r['title'] as String, D.relativeDateTime(D.fromMs(r['start_at'] as int), hasTime: r['all_day'] != 1)),
    ]);

    final docs = await db.query(
      'documents',
      where: 'name LIKE ? $esc OR number LIKE ? $esc OR notes LIKE ? $esc OR category LIKE ? $esc',
      whereArgs: [l, l, l, l],
      limit: lim,
    );
    put(AppModule.documents, [
      for (final r in docs)
        SearchHit(
          AppModule.documents,
          r['id'] as int,
          r['name'] as String,
          '${r['category']}${r['expiry_at'] == null ? '' : ' · Expires ${D.dayMonthYear(D.fromMs(r['expiry_at'] as int))}'}',
        ),
    ]);

    final notes = await db.query(
      'notes',
      where: 'title LIKE ? $esc OR body LIKE ? $esc OR checklist LIKE ? $esc OR tags LIKE ? $esc',
      whereArgs: [l, l, l, l],
      orderBy: 'updated_at DESC',
      limit: lim,
    );
    put(AppModule.notes, [
      for (final r in notes)
        SearchHit(
          AppModule.notes,
          r['id'] as int,
          (r['title'] as String).isEmpty ? _firstLine(r['body'] as String) : r['title'] as String,
          '${r['archived'] == 1 ? 'Archived · ' : ''}Edited ${D.relativeDay(D.fromMs(r['updated_at'] as int))}',
        ),
    ]);

    final subj = await db.query('subjects', where: 'name LIKE ? $esc', whereArgs: [l], limit: lim);
    final topics = await db.rawQuery(
      'SELECT t.*, s.name sname FROM topics t JOIN subjects s ON s.id=t.subject_id WHERE t.name LIKE ? $esc OR t.notes LIKE ? $esc LIMIT $lim',
      [l, l],
    );
    put(AppModule.study, [
      for (final r in subj) SearchHit(AppModule.study, r['id'] as int, r['name'] as String, 'Subject', kind: 'subject'),
      for (final r in topics)
        SearchHit(
          AppModule.study,
          r['id'] as int,
          r['name'] as String,
          'Topic in ${r['sname']}${r['done'] == 1 ? ' · Done' : ''}',
          parentId: r['subject_id'] as int,
          kind: 'topic',
        ),
    ]);

    return out;
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  static String _firstLine(String s) {
    final t = s.trim().split('\n').first;
    return t.isEmpty ? 'Untitled note' : t;
  }
}
