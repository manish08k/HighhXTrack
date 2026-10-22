import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/todo.dart';
import '../../data/repositories/todo_repo.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'todo_categories.dart';
import 'todo_editor.dart';
import 'todo_providers.dart';
import 'todo_tile.dart';

class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key, this.standalone = false});

  /// True when pushed as a page (shows back button) instead of a tab.
  final bool standalone;

  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends ConsumerState<TodoScreen> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(TodoQuery q) => ref.read(todoQueryProvider.notifier).set(q);

  Future<void> _showFilters(TodoQuery q, List<TodoCategory> cats) async {
    await showAppSheet<void>(
      context,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final q = ref.watch(todoQueryProvider);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter & sort', style: ctx.text.titleLarge),
                  const FieldLabel('Sort by'),
                  ChoiceChips<TodoSort>(
                    options: TodoSort.values,
                    selected: q.sort,
                    label: (s) => s.label,
                    wrap: true,
                    onSelected: (s) => _setQuery(q.copyWith(sort: s)),
                  ),
                  const FieldLabel('Priority'),
                  ChoiceChips<int?>(
                    options: const [null, 2, 1, 0],
                    selected: q.priority,
                    wrap: true,
                    label: (p) => p == null ? 'Any' : Priority.values[p].label,
                    color: (p) => p == null ? ctx.colors.primary : Priority.values[p].color,
                    onSelected: (p) => _setQuery(p == null ? q.copyWith(clearPriority: true) : q.copyWith(priority: p)),
                  ),
                  const FieldLabel('Category'),
                  ChoiceChips<int?>(
                    options: [null, ...cats.map((c) => c.id)],
                    selected: q.categoryId,
                    wrap: true,
                    label: (id) => id == null ? 'All' : cats.firstWhere((c) => c.id == id).name,
                    color: (id) => id == null ? ctx.colors.primary : cats.firstWhere((c) => c.id == id).colorValue,
                    onSelected: (id) => _setQuery(id == null ? q.copyWith(clearCategory: true) : q.copyWith(categoryId: id)),
                  ),
                  const SizedBox(height: Gap.xl),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _setQuery(TodoQuery(view: q.view)),
                      child: const Text('Reset filters'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _menu(String v) async {
    final q = ref.read(todoQueryProvider);
    switch (v) {
      case 'archived':
        _setQuery(q.copyWith(view: TodoView.archived));
      case 'archive_done':
        final ok = await confirmDialog(
          context,
          title: 'Archive completed tasks?',
          message: 'Completed tasks move to the archive. You can restore them anytime.',
          confirm: 'Archive',
          destructive: false,
        );
        if (!ok || !mounted) return;
        final n = await guard(context, () => ref.read(todoRepoProvider).archiveCompleted());
        if (mounted && n != null) showSnack(context, n == 0 ? 'Nothing to archive' : 'Archived ${plural(n)}');
      case 'categories':
        push(context, const TodoCategoriesScreen());
    }
  }

  static String plural(int n) => '$n ${n == 1 ? 'task' : 'tasks'}';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(todoQueryProvider);
    final cats = ref.watch(todoCategoriesProvider).value ?? const <TodoCategory>[];
    final catMap = {for (final c in cats) c.id!: c};
    final list = ref.watch(todoListProvider(q));
    final progress = ref.watch(todoTodayProgressProvider).value ?? (0, 0);
    final filtered = q.categoryId != null || q.priority != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search tasks',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (s) => _setQuery(q.copyWith(search: s)),
              )
            : const Text('Todo'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                _setQuery(q.copyWith(search: ''));
              }
            },
          ),
          IconButton(
            tooltip: 'Filter & sort',
            onPressed: () => _showFilters(q, cats),
            icon: Badge(isLabelVisible: filtered, smallSize: 8, child: const Icon(Icons.tune_rounded)),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'categories', child: Text('Manage categories')),
              PopupMenuItem(value: 'archive_done', child: Text('Archive completed')),
              PopupMenuItem(value: 'archived', child: Text('View archive')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'todo-fab',
        tooltip: 'New task',
        onPressed: () => push(context, TodoEditorScreen(initialDue: q.view == TodoView.today ? D.today() : null, initialCategory: q.categoryId)),
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ProgressHeader(done: progress.$1, total: progress.$2),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
              child: ChoiceChips<TodoView?>(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                options: const [TodoView.today, TodoView.upcoming, TodoView.all, TodoView.completed, null, TodoView.archived],
                selected: q.view == TodoView.archived ? TodoView.archived : q.view,
                label: (v) => switch (v) {
                  TodoView.today => 'Today',
                  TodoView.upcoming => 'Upcoming',
                  TodoView.all => 'All',
                  TodoView.completed => 'Completed',
                  TodoView.archived => 'Archive',
                  null => 'Categories',
                },
                onSelected: (v) {
                  if (v == null) {
                    push(context, const TodoCategoriesScreen());
                  } else {
                    _setQuery(q.copyWith(view: v));
                  }
                },
              ),
            ),
          ),
          if (q.categoryId != null && catMap[q.categoryId] != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(catMap[q.categoryId]!.name),
                    avatar: Dot(catMap[q.categoryId]!.colorValue),
                    onDeleted: () => _setQuery(q.copyWith(clearCategory: true)),
                  ),
                ),
              ),
            ),
          AsyncSliver<List<Todo>>(
            value: list,
            onRetry: () => ref.invalidate(todoListProvider(q)),
            builder: (todos) {
              if (todos.isEmpty) {
                return SliverFillRemaining(hasScrollBody: false, child: _empty(q));
              }
              final rows = _group(q, todos);
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, 96),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    if (r is String) {
                      return Padding(
                        padding: EdgeInsets.only(top: i == 0 ? Gap.xs : Gap.lg, bottom: Gap.sm, left: Gap.xs),
                        child: Text(r, style: context.text.labelLarge!.copyWith(color: r == 'Overdue' ? Palette.danger : context.colors.onSurfaceVariant)),
                      );
                    }
                    final t = r as Todo;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: q.view == TodoView.archived
                          ? _ArchivedTile(todo: t, category: catMap[t.categoryId])
                          : TodoTile(key: ValueKey(t.id), todo: t, category: catMap[t.categoryId]),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _empty(TodoQuery q) {
    if (q.search.isNotEmpty) return const EmptyState(icon: Icons.search_off_rounded, title: 'No matching tasks');
    return switch (q.view) {
      TodoView.today => EmptyState(
        icon: Icons.wb_sunny_outlined,
        color: AppModule.todo.color,
        title: 'Nothing due today',
        message: 'Enjoy the calm, or plan something new.',
        actionLabel: 'Add task',
        onAction: () => push(context, TodoEditorScreen(initialDue: D.today())),
      ),
      TodoView.upcoming => const EmptyState(
        icon: Icons.event_available_outlined,
        title: 'No upcoming tasks',
        message: 'Tasks with future due dates appear here.',
      ),
      TodoView.completed => const EmptyState(icon: Icons.task_alt_rounded, title: 'No completed tasks yet'),
      TodoView.archived => const EmptyState(icon: Icons.inventory_2_outlined, title: 'Archive is empty'),
      TodoView.all => EmptyState(
        icon: Icons.checklist_rounded,
        color: AppModule.todo.color,
        title: 'No open tasks',
        message: 'Tap + to add your first task.',
        actionLabel: 'Add task',
        onAction: () => push(context, const TodoEditorScreen()),
      ),
    };
  }

  /// Inserts section headers (String) between todos.
  List<Object> _group(TodoQuery q, List<Todo> todos) {
    if (q.sort != TodoSort.due) return todos;
    final out = <Object>[];
    String? last;
    for (final t in todos) {
      final String h;
      switch (q.view) {
        case TodoView.today:
          h = t.isOverdue && !t.isDueToday ? 'Overdue' : (t.completed ? 'Done today' : 'Today');
        case TodoView.upcoming:
          h = D.relativeDay(t.dueAt!);
        case TodoView.completed:
          h = t.completedAt == null ? 'Earlier' : D.relativeDay(t.completedAt!);
        case TodoView.all:
          h = t.dueAt == null ? 'No date' : (t.isOverdue && !t.isDueToday ? 'Overdue' : D.relativeDay(t.dueAt!));
        case TodoView.archived:
          h = 'Archived';
      }
      if (h != last) {
        out.add(h);
        last = h;
      }
      out.add(t);
    }
    return out;
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 0),
      child: AppCard(
        child: Row(
          children: [
            ProgressRing(
              value: p,
              size: 60,
              color: AppModule.todo.color,
              child: Text('${(p * 100).round()}%', style: context.text.labelLarge),
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today', style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(total == 0 ? 'No tasks due' : '$done of $total completed', style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(D.longDate(DateTime.now()), style: context.text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedTile extends ConsumerWidget {
  const _ArchivedTile({required this.todo, this.category});
  final Todo todo;
  final TodoCategory? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(todo.title, style: context.text.bodyLarge!.copyWith(decoration: todo.completed ? TextDecoration.lineThrough : null)),
                Text(todo.completedAt != null ? 'Completed ${D.relativeDay(todo.completedAt!)}' : 'Not completed', style: context.text.bodySmall),
              ],
            ),
          ),
          IconButton(tooltip: 'Restore', icon: const Icon(Icons.unarchive_outlined), onPressed: () => ref.read(todoRepoProvider).setArchived(todo.id!, false)),
          IconButton(
            tooltip: 'Delete permanently',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (await confirmDialog(context, title: 'Delete permanently?', message: todo.title)) {
                await ref.read(todoRepoProvider).delete(todo.id!);
              }
            },
          ),
        ],
      ),
    );
  }
}
