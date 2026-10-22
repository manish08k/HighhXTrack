import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/todo.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/todo_repo.dart';
import '../../state/providers.dart';

final todoListProvider = FutureProvider.autoDispose.family<List<Todo>, TodoQuery>((ref, q) {
  ref.watchTopics([Chg.todo]);
  return ref.read(todoRepoProvider).query(q);
});

final todoCategoriesProvider = FutureProvider.autoDispose<List<TodoCategory>>((ref) {
  ref.watchTopics([Chg.todo]);
  return ref.read(todoRepoProvider).categories();
});

final todoCategoryCountsProvider = FutureProvider.autoDispose<Map<int, int>>((ref) {
  ref.watchTopics([Chg.todo]);
  return ref.read(todoRepoProvider).categoryCounts();
});

final todoTodayProgressProvider = FutureProvider.autoDispose<(int, int)>((ref) {
  ref.watchTopics([Chg.todo]);
  return ref.read(todoRepoProvider).todayProgress();
});

final todoByIdProvider = FutureProvider.autoDispose.family<Todo?, int>((ref, id) {
  ref.watchTopics([Chg.todo]);
  return ref.read(todoRepoProvider).get(id);
});

/// Current filter state of the Todo screen.
class TodoQueryNotifier extends Notifier<TodoQuery> {
  @override
  TodoQuery build() => const TodoQuery();
  void set(TodoQuery q) => state = q;
}

final todoQueryProvider = NotifierProvider<TodoQueryNotifier, TodoQuery>(TodoQueryNotifier.new);
