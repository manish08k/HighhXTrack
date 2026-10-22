import '../../core/utils/dates.dart';
import '../models/todo.dart';
import 'base.dart';

enum TodoView { today, upcoming, all, completed, archived }

enum TodoSort {
  due('Due date'),
  priority('Priority'),
  created('Recently added'),
  title('Title');

  const TodoSort(this.label);
  final String label;
}

class TodoQuery {
  const TodoQuery({this.view = TodoView.today, this.categoryId, this.priority, this.search = '', this.sort = TodoSort.due});
  final TodoView view;
  final int? categoryId;
  final int? priority;
  final String search;
  final TodoSort sort;

  TodoQuery copyWith({
    TodoView? view,
    int? categoryId,
    bool clearCategory = false,
    int? priority,
    bool clearPriority = false,
    String? search,
    TodoSort? sort,
  }) => TodoQuery(
    view: view ?? this.view,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    priority: clearPriority ? null : (priority ?? this.priority),
    search: search ?? this.search,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is TodoQuery && other.view == view && other.categoryId == categoryId && other.priority == priority && other.search == search && other.sort == sort;

  @override
  int get hashCode => Object.hash(view, categoryId, priority, search, sort);
}

class TodoSnapshot {
  TodoSnapshot(this.row, this.subtasks);
  final Map<String, Object?> row;
  final List<Map<String, Object?>> subtasks;
}

class TodoRepo extends Repo {
  TodoRepo(super.db, super.changed);

  // ---------------------------------------------------------- categories
  Future<List<TodoCategory>> categories() async => (await db.query('todo_categories', orderBy: 'position, id')).map(TodoCategory.fromMap).toList();

  Future<int> saveCategory(TodoCategory c) async {
    final id = c.id == null
        ? await db.insert('todo_categories', c.toMap())
        : (await db.update('todo_categories', c.toMap(), where: 'id=?', whereArgs: [c.id]), c.id!).$2;
    changed(Chg.todo);
    return id;
  }

  Future<void> deleteCategory(int id) async {
    await db.delete('todo_categories', where: 'id=?', whereArgs: [id]);
    changed(Chg.todo);
  }

  /// id → (open count)
  Future<Map<int, int>> categoryCounts() async {
    final rows = await db.rawQuery(
      'SELECT category_id, COUNT(*) c FROM todos WHERE completed=0 AND archived=0 AND category_id IS NOT NULL GROUP BY category_id',
    );
    return {for (final r in rows) r['category_id'] as int: r['c'] as int};
  }

  // ---------------------------------------------------------- queries
  Future<List<Todo>> query(TodoQuery q) async {
    final where = <String>[];
    final args = <Object?>[];
    final endToday = D.ms(D.endOfDay(DateTime.now()));
    switch (q.view) {
      case TodoView.today:
        // Due today or overdue, plus anything completed today (so progress is visible).
        where.add(
          'archived=0 AND ((completed=0 AND due_at IS NOT NULL AND due_at<=?) OR (completed=1 AND completed_at>=? AND due_at IS NOT NULL AND due_at<=?))',
        );
        args.addAll([endToday, D.ms(D.today()), endToday]);
      case TodoView.upcoming:
        where.add('archived=0 AND completed=0 AND due_at>?');
        args.add(endToday);
      case TodoView.all:
        where.add('archived=0 AND completed=0');
      case TodoView.completed:
        where.add('archived=0 AND completed=1');
      case TodoView.archived:
        where.add('archived=1');
    }
    if (q.categoryId != null) {
      where.add('category_id=?');
      args.add(q.categoryId);
    }
    if (q.priority != null) {
      where.add('priority=?');
      args.add(q.priority);
    }
    if (q.search.trim().isNotEmpty) {
      where.add("(title LIKE ? ESCAPE '\\' OR description LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\')");
      final l = Repo.like(q.search.trim());
      args.addAll([l, l, l]);
    }
    final order = switch (q.view) {
      TodoView.completed => 'completed_at DESC',
      _ => switch (q.sort) {
        TodoSort.due => 'completed ASC, due_at IS NULL, due_at ASC, priority DESC',
        TodoSort.priority => 'completed ASC, priority DESC, due_at IS NULL, due_at ASC',
        TodoSort.created => 'created_at DESC',
        TodoSort.title => 'title COLLATE NOCASE ASC',
      },
    };
    final rows = await db.query('todos', where: where.join(' AND '), whereArgs: args, orderBy: order, limit: q.view == TodoView.completed ? 500 : null);
    return _hydrate(rows);
  }

  Future<List<Todo>> _hydrate(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final subs = <int, List<Subtask>>{};
    final att = <int, int>{};
    // Chunk to stay under SQLite's variable limit.
    for (var s = 0; s < ids.length; s += 500) {
      final chunk = ids.sublist(s, s + 500 > ids.length ? ids.length : s + 500);
      final ph = Repo.placeholders(chunk.length);
      for (final r in await db.query('subtasks', where: 'todo_id IN ($ph)', whereArgs: chunk, orderBy: 'position, id')) {
        final st = Subtask.fromMap(r);
        (subs[st.todoId!] ??= []).add(st);
      }
      for (final r in await db.rawQuery(
        "SELECT owner_id, COUNT(*) c FROM attachments WHERE owner_type='todo' AND owner_id IN ($ph) GROUP BY owner_id",
        chunk,
      )) {
        att[r['owner_id'] as int] = r['c'] as int;
      }
    }
    return rows.map((r) => Todo.fromMap(r, subtasks: subs[r['id']] ?? const [], attachments: att[r['id']] ?? 0)).toList();
  }

  Future<Todo?> get(int id) async {
    final rows = await db.query('todos', where: 'id=?', whereArgs: [id]);
    final list = await _hydrate(rows);
    return list.isEmpty ? null : list.first;
  }

  Future<List<Todo>> dueBetween(DateTime from, DateTime to) async {
    final rows = await db.query('todos', where: 'archived=0 AND due_at>=? AND due_at<=?', whereArgs: [D.ms(from), D.ms(to)], orderBy: 'due_at');
    return rows.map((r) => Todo.fromMap(r)).toList();
  }

  /// (completed, total) for today's list.
  Future<(int, int)> todayProgress() async {
    final endToday = D.ms(D.endOfDay(DateTime.now()));
    final r = await db.rawQuery(
      'SELECT SUM(CASE WHEN completed=1 THEN 1 ELSE 0 END) d, COUNT(*) t FROM todos WHERE archived=0 AND due_at IS NOT NULL AND due_at<=? AND (completed=0 OR completed_at>=?)',
      [endToday, D.ms(D.today())],
    );
    return ((r.first['d'] as int?) ?? 0, (r.first['t'] as int?) ?? 0);
  }

  /// Completed per day for the last [days] days (oldest first).
  Future<List<int>> completionsPerDay(int days) async {
    final start = D.addDays(D.today(), -(days - 1));
    final rows = await db.query('todos', columns: ['completed_at'], where: 'completed=1 AND completed_at>=?', whereArgs: [D.ms(start)]);
    final out = List<int>.filled(days, 0);
    for (final r in rows) {
      final idx = D.diffDays(start, D.fromMs(r['completed_at'] as int));
      if (idx >= 0 && idx < days) out[idx]++;
    }
    return out;
  }

  Future<(int, int)> overallCounts() async {
    final r = await db.rawQuery('SELECT SUM(completed) d, COUNT(*) t FROM todos WHERE archived=0');
    return ((r.first['d'] as int?) ?? 0, (r.first['t'] as int?) ?? 0);
  }

  // ---------------------------------------------------------- writes
  Future<int> save(Todo t, List<Subtask> subtasks) async {
    late int id;
    await db.transaction((tx) async {
      final map = t.toMap()..['updated_at'] = D.ms(DateTime.now());
      if (t.id == null) {
        id = await tx.insert('todos', map);
      } else {
        id = t.id!;
        await tx.update('todos', map, where: 'id=?', whereArgs: [id]);
        await tx.delete('subtasks', where: 'todo_id=?', whereArgs: [id]);
      }
      var pos = 0;
      for (final s in subtasks) {
        if (s.title.trim().isEmpty) continue;
        await tx.insert('subtasks', {'todo_id': id, 'title': s.title.trim(), 'done': s.done ? 1 : 0, 'position': pos++});
      }
    });
    changed(Chg.todo);
    return id;
  }

  /// Toggles completion. For a recurring todo being completed, the next
  /// occurrence is created. Returns the id of the spawned todo (if any).
  Future<int?> setCompleted(Todo t, bool done) async {
    int? spawned;
    await db.transaction((tx) async {
      await tx.update(
        'todos',
        {'completed': done ? 1 : 0, 'completed_at': done ? D.ms(DateTime.now()) : null, 'updated_at': D.ms(DateTime.now())},
        where: 'id=?',
        whereArgs: [t.id],
      );
      if (done && t.recurrence.repeats && t.dueAt != null) {
        var next = t.recurrence.nextAfter(t.dueAt!, t.dueAt!);
        // Skip past occurrences so the next one is in the future.
        final today = D.today();
        while (next != null && D.dateOnly(next).isBefore(today)) {
          next = t.recurrence.nextAfter(t.dueAt!, next);
        }
        if (next != null) {
          final now = D.ms(DateTime.now());
          final map = t.toMap()
            ..remove('id')
            ..['due_at'] = D.ms(next)
            ..['completed'] = 0
            ..['completed_at'] = null
            ..['created_at'] = now
            ..['updated_at'] = now;
          spawned = await tx.insert('todos', map);
          var pos = 0;
          for (final s in t.subtasks) {
            await tx.insert('subtasks', {'todo_id': spawned, 'title': s.title, 'done': 0, 'position': pos++});
          }
          // The completed instance no longer repeats; the new one carries the rule.
          await tx.update('todos', {'recurrence': ''}, where: 'id=?', whereArgs: [t.id]);
        }
      }
    });
    changed(Chg.todo);
    return spawned;
  }

  /// Reverts [setCompleted] including removal of a spawned occurrence.
  Future<void> undoComplete(Todo original, int? spawnedId) async {
    await db.transaction((tx) async {
      if (spawnedId != null) await tx.delete('todos', where: 'id=?', whereArgs: [spawnedId]);
      await tx.update('todos', {'completed': 0, 'completed_at': null, 'recurrence': original.recurrence.encode()}, where: 'id=?', whereArgs: [original.id]);
    });
    changed(Chg.todo);
  }

  Future<void> setSubtaskDone(int subtaskId, bool done) async {
    await db.update('subtasks', {'done': done ? 1 : 0}, where: 'id=?', whereArgs: [subtaskId]);
    changed(Chg.todo);
  }

  Future<void> setArchived(int id, bool archived) async {
    await db.update('todos', {'archived': archived ? 1 : 0, 'updated_at': D.ms(DateTime.now())}, where: 'id=?', whereArgs: [id]);
    changed(Chg.todo);
  }

  /// Archives all completed todos. Returns count.
  Future<int> archiveCompleted() async {
    final n = await db.update('todos', {'archived': 1}, where: 'completed=1 AND archived=0');
    changed(Chg.todo);
    return n;
  }

  Future<TodoSnapshot?> delete(int id) async {
    final rows = await db.query('todos', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final subs = await db.query('subtasks', where: 'todo_id=?', whereArgs: [id]);
    await db.delete('todos', where: 'id=?', whereArgs: [id]);
    changed(Chg.todo);
    return TodoSnapshot(rows.first, subs);
  }

  Future<void> restore(TodoSnapshot s) async {
    await db.transaction((tx) async {
      await tx.insert('todos', s.row);
      for (final r in s.subtasks) {
        await tx.insert('subtasks', r);
      }
    });
    changed(Chg.todo);
  }
}
