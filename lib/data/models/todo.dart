import 'dart:ui';

import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import 'common.dart';

class TodoCategory {
  const TodoCategory({this.id, required this.name, required this.color, this.position = 0});
  final int? id;
  final String name;
  final int color;
  final int position;

  Color get colorValue => Color(color);

  factory TodoCategory.fromMap(Map<String, Object?> m) =>
      TodoCategory(id: m['id'] as int, name: m['name'] as String, color: m['color'] as int, position: m['position'] as int? ?? 0);

  Map<String, Object?> toMap() => {if (id != null) 'id': id, 'name': name, 'color': color, 'position': position};
}

class Subtask {
  const Subtask({this.id, this.todoId, required this.title, this.done = false, this.position = 0});
  final int? id;
  final int? todoId;
  final String title;
  final bool done;
  final int position;

  Subtask copyWith({String? title, bool? done, int? position}) =>
      Subtask(id: id, todoId: todoId, title: title ?? this.title, done: done ?? this.done, position: position ?? this.position);

  factory Subtask.fromMap(Map<String, Object?> m) =>
      Subtask(id: m['id'] as int, todoId: m['todo_id'] as int, title: m['title'] as String, done: b(m['done']), position: m['position'] as int? ?? 0);
}

class Todo {
  const Todo({
    this.id,
    required this.title,
    this.description = '',
    this.notes = '',
    this.priority = Priority.medium,
    this.categoryId,
    this.dueAt,
    this.hasTime = false,
    this.recurrence = Recurrence.none,
    this.remind = true,
    this.completed = false,
    this.completedAt,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
    this.subtasks = const [],
    this.attachmentCount = 0,
  });

  final int? id;
  final String title;
  final String description;
  final String notes;
  final Priority priority;
  final int? categoryId;
  final DateTime? dueAt;
  final bool hasTime;
  final Recurrence recurrence;
  final bool remind;
  final bool completed;
  final DateTime? completedAt;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Populated by repository queries.
  final List<Subtask> subtasks;
  final int attachmentCount;

  bool get isOverdue {
    if (completed || dueAt == null) return false;
    final now = DateTime.now();
    return hasTime ? dueAt!.isBefore(now) : D.dateOnly(dueAt!).isBefore(D.today());
  }

  bool get isDueToday => dueAt != null && D.sameDay(dueAt!, DateTime.now());

  int get subtasksDone => subtasks.where((s) => s.done).length;

  Todo copyWith({
    String? title,
    bool? completed,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? archived,
    DateTime? dueAt,
    List<Subtask>? subtasks,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    description: description,
    notes: notes,
    priority: priority,
    categoryId: categoryId,
    dueAt: dueAt ?? this.dueAt,
    hasTime: hasTime,
    recurrence: recurrence,
    remind: remind,
    completed: completed ?? this.completed,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    subtasks: subtasks ?? this.subtasks,
    attachmentCount: attachmentCount,
  );

  factory Todo.fromMap(Map<String, Object?> m, {List<Subtask> subtasks = const [], int attachments = 0}) => Todo(
    id: m['id'] as int,
    title: m['title'] as String,
    description: m['description'] as String? ?? '',
    notes: m['notes'] as String? ?? '',
    priority: Priority.fromIndex(m['priority'] as int?),
    categoryId: m['category_id'] as int?,
    dueAt: D.fromMsN(m['due_at'] as int?),
    hasTime: b(m['has_time']),
    recurrence: Recurrence.decode(m['recurrence'] as String?),
    remind: b(m['remind']),
    completed: b(m['completed']),
    completedAt: D.fromMsN(m['completed_at'] as int?),
    archived: b(m['archived']),
    createdAt: D.fromMs(m['created_at'] as int),
    updatedAt: D.fromMs(m['updated_at'] as int),
    subtasks: subtasks,
    attachmentCount: attachments,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'description': description,
    'notes': notes,
    'priority': priority.index,
    'category_id': categoryId,
    'due_at': dueAt == null ? null : D.ms(dueAt!),
    'has_time': i(hasTime),
    'recurrence': recurrence.encode(),
    'remind': i(remind),
    'completed': i(completed),
    'completed_at': completedAt == null ? null : D.ms(completedAt!),
    'archived': i(archived),
    'created_at': D.ms(createdAt),
    'updated_at': D.ms(updatedAt),
  };
}
