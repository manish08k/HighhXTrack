import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/todo.dart';
import '../../data/repositories/todo_repo.dart';
import '../../state/providers.dart';
import 'todo_providers.dart';

class TodoCategoriesScreen extends ConsumerWidget {
  const TodoCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(todoCategoriesProvider);
    final counts = ref.watch(todoCategoryCountsProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'todo-cat-fab',
        tooltip: 'New category',
        onPressed: () => editTodoCategory(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: AsyncBody<List<TodoCategory>>(
        value: cats,
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.label_outline_rounded,
              color: AppModule.todo.color,
              title: 'No categories',
              message: 'Group tasks into Work, Personal and more.',
              actionLabel: 'Add category',
              onAction: () => editTodoCategory(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
            itemBuilder: (context, i) {
              final c = list[i];
              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
                onTap: () {
                  ref.read(todoQueryProvider.notifier).set(TodoQuery(view: TodoView.all, categoryId: c.id));
                  Navigator.pop(context);
                },
                child: Row(
                  children: [
                    IconBadge(Icons.label_rounded, c.colorValue, size: 36),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: context.text.titleSmall),
                          Text('${counts[c.id] ?? 0} open', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => editTodoCategory(context, ref, c)),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        if (await confirmDialog(context, title: 'Delete "${c.name}"?', message: 'Tasks in this category are kept and become uncategorized.')) {
                          await ref.read(todoRepoProvider).deleteCategory(c.id!);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Create/edit a todo category. Returns the saved id.
Future<int?> editTodoCategory(BuildContext context, WidgetRef ref, [TodoCategory? existing]) =>
    showAppSheet<int>(context, builder: (_) => _CategorySheet(existing: existing));

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing});
  final TodoCategory? existing;
  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.color ?? Palette.swatches.first.toARGB32();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final e = widget.existing;
    final id = await guard(
      context,
      () => ref.read(todoRepoProvider).saveCategory(TodoCategory(id: e?.id, name: _name.text.trim(), color: _color, position: e?.position ?? 99)),
    );
    if (mounted && id != null) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'New category' : 'Edit category', style: context.text.titleLarge),
          AppTextField(controller: _name, label: 'Name', autofocus: true, hint: 'e.g. Work', onSubmitted: (_) => _save()),
          const FieldLabel('Color'),
          ColorChoice(value: _color, onChanged: (c) => setState(() => _color = c)),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
