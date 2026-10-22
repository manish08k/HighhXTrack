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
import '../../core/widgets/swipe.dart';
import '../../data/models/knowledge.dart';
import '../../data/repositories/note_repo.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'note_editor.dart';
import 'note_providers.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});
  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  int? _folder;
  String? _tag;
  bool _archived = false;
  String _q = '';

  Future<void> _folderMenu(NoteFolder f) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename folder'), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete folder'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final repo = ref.read(noteRepoProvider);
    if (v == 'rename') {
      final n = await promptText(context, title: 'Rename folder', initial: f.name);
      if (n != null) await repo.saveFolder(f.id, n);
    } else if (v == 'delete') {
      if (await confirmDialog(context, title: 'Delete "${f.name}"?', message: 'Notes in this folder are kept and moved out of it.')) {
        await repo.deleteFolder(f.id!);
        if (_folder == f.id) setState(() => _folder = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = NoteQuery(folderId: _folder, tag: _tag, archived: _archived, search: _q);
    final folders = ref.watch(noteFoldersProvider).value ?? const <NoteFolder>[];
    final tags = ref.watch(noteTagsProvider).value ?? const <String>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(_archived ? 'Archived notes' : 'Notes'),
        actions: [
          IconButton(
            tooltip: _archived ? 'Show notes' : 'Show archive',
            icon: Icon(_archived ? Icons.notes_rounded : Icons.inventory_2_outlined),
            onPressed: () => setState(() => _archived = !_archived),
          ),
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () async {
              final n = await promptText(context, title: 'New folder', hint: 'Folder name', confirm: 'Create');
              if (n != null) await ref.read(noteRepoProvider).saveFolder(null, n);
            },
          ),
        ],
      ),
      floatingActionButton: _archived
          ? null
          : FloatingActionButton(
              heroTag: 'note-fab',
              tooltip: 'New note',
              onPressed: () => push(context, NoteEditorScreen(folderId: _folder)),
              child: const Icon(Icons.edit_rounded),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.sm),
            child: AppTextField(hint: 'Search notes', prefix: const Icon(Icons.search_rounded), onChanged: (v) => setState(() => _q = v)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: Gap.sm),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _folder == null && _tag == null,
                    onSelected: (_) => setState(() {
                      _folder = null;
                      _tag = null;
                    }),
                  ),
                ),
                for (final f in folders)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: GestureDetector(
                      onLongPress: () => _folderMenu(f),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.folder_outlined, size: 16),
                        label: Text('${f.name} ${f.count}'),
                        selected: _folder == f.id,
                        onSelected: (_) => setState(() => _folder = _folder == f.id ? null : f.id),
                      ),
                    ),
                  ),
                for (final t in tags)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: ChoiceChip(label: Text('#$t'), selected: _tag == t, onSelected: (_) => setState(() => _tag = _tag == t ? null : t)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
          Expanded(
            child: AsyncBody<List<Note>>(
              value: ref.watch(notesProvider(q)),
              builder: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: _q.isNotEmpty ? Icons.search_off_rounded : Icons.sticky_note_2_outlined,
                    color: AppModule.notes.color,
                    title: _q.isNotEmpty ? 'No matching notes' : (_archived ? 'Archive is empty' : 'No notes yet'),
                    message: _q.isEmpty && !_archived ? 'Capture ideas, lists and anything worth remembering.' : null,
                    actionLabel: _q.isEmpty && !_archived ? 'New note' : null,
                    onAction: () => push(context, NoteEditorScreen(folderId: _folder)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
                  itemBuilder: (context, i) => NoteCard(note: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class NoteCard extends ConsumerWidget {
  const NoteCard({super.key, required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = note;
    final repo = ref.read(noteRepoProvider);
    final card = AppCard(
      onTap: () => push(context, NoteEditorScreen(id: n.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(n.title.isEmpty ? 'Untitled' : n.title, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (n.pinned) Icon(Icons.push_pin_rounded, size: 16, color: AppModule.notes.color),
            ],
          ),
          if (n.preview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              n.preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(D.relativeDateTime(n.updatedAt), style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
              if (n.checklist.isNotEmpty) Pill('${n.checklist.where((c) => c.done).length}/${n.checklist.length}', icon: Icons.checklist_rounded, dense: true),
              for (final t in n.tags) Pill('#$t', dense: true, color: AppModule.notes.color),
            ],
          ),
        ],
      ),
    );
    return SwipeTile(
      key: ValueKey('note-${n.id}-${n.archived}'),
      start: SwipeAction(
        icon: n.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        label: n.pinned ? 'Unpin' : 'Pin',
        color: AppModule.notes.color,
        onTrigger: () => repo.setFlags(n.id!, pinned: !n.pinned),
      ),
      end: SwipeAction(
        icon: n.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
        label: n.archived ? 'Restore' : 'Archive',
        color: Palette.info,
        dismiss: true,
        onTrigger: () async {
          final m = ScaffoldMessenger.of(context);
          await repo.setFlags(n.id!, archived: !n.archived);
          undoOn(m, n.archived ? 'Note restored' : 'Note archived', () => repo.setFlags(n.id!, archived: n.archived));
        },
      ),
      child: card,
    );
  }
}
