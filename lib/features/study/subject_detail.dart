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
import '../../data/models/knowledge.dart';
import '../../state/providers.dart';
import '../shared/linked_reminders.dart';
import '../shell/nav.dart';
import 'study_providers.dart';
import 'study_timer_screen.dart';
import 'study_widgets.dart';

class SubjectDetailScreen extends ConsumerStatefulWidget {
  const SubjectDetailScreen({super.key, required this.subjectId});
  final int subjectId;
  @override
  ConsumerState<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends ConsumerState<SubjectDetailScreen> {
  final _newTopic = TextEditingController();

  @override
  void dispose() {
    _newTopic.dispose();
    super.dispose();
  }

  Future<void> _addTopic() async {
    final t = _newTopic.text.trim();
    if (t.isEmpty) return;
    _newTopic.clear();
    await guard(context, () => ref.read(studyRepoProvider).saveTopic(subjectId: widget.subjectId, name: t));
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Subject?>(
      value: ref.watch(subjectProvider(widget.subjectId)),
      loading: const Scaffold(body: LoadingView()),
      builder: (s) {
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Subject not found'),
          );
        }
        final topics = ref.watch(topicsProvider(s.id!)).value ?? const <Topic>[];
        final sessions = ref.watch(sessionsProvider(s.id)).value ?? const <StudySession>[];
        final repo = ref.read(studyRepoProvider);
        return Scaffold(
          appBar: AppBar(
            title: Text(s.name),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => editSubject(context, existing: s),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'archive') {
                    await repo.saveSubject(
                      Subject(id: s.id, name: s.name, color: s.color, archived: !s.archived, position: s.position, createdAt: s.createdAt),
                    );
                    if (context.mounted) Navigator.pop(context);
                  } else if (v == 'delete' &&
                      await confirmDialog(context, title: 'Delete "${s.name}"?', message: 'All topics and study sessions for this subject will be deleted.')) {
                    await repo.deleteSubject(s.id!);
                    if (context.mounted) Navigator.pop(context);
                  } else if (v == 'log' && context.mounted) {
                    await logSession(context, subjectId: s.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'log', child: Text('Log time manually')),
                  PopupMenuItem(value: 'archive', child: Text(s.archived ? 'Unarchive' : 'Archive')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'subj-fab',
            backgroundColor: s.colorValue,
            foregroundColor: Colors.white,
            onPressed: () => push(context, StudyTimerScreen(subjectId: s.id)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Study now'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            children: [
              const ActiveStudyBanner(),
              AppCard(
                child: Row(
                  children: [
                    ProgressRing(
                      value: s.progress,
                      size: 64,
                      color: s.colorValue,
                      child: Text('${(s.progress * 100).round()}%', style: context.text.labelLarge),
                    ),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${s.topicsDone} of ${s.topicCount} topics done', style: context.text.titleSmall),
                          Text('${D.duration(Duration(seconds: s.totalSeconds))} studied in total', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Topics', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              if (topics.isEmpty) Text('Break the subject into topics and tick them off as you go.', style: context.text.bodyMedium),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (a, b) {
                  final ids = topics.map((t) => t.id!).toList();
                  ids.insert(b, ids.removeAt(a));
                  repo.reorderTopics(ids);
                },
                children: [
                  for (var k = 0; k < topics.length; k++)
                    Material(
                      key: ValueKey(topics[k].id),
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 0, right: 0),
                        leading: Checkbox(value: topics[k].done, activeColor: s.colorValue, onChanged: (v) => repo.setTopicDone(topics[k].id!, v ?? false)),
                        title: Text(
                          topics[k].name,
                          style: TextStyle(
                            decoration: topics[k].done ? TextDecoration.lineThrough : null,
                            color: topics[k].done ? context.colors.onSurfaceVariant : null,
                          ),
                        ),
                        subtitle: topics[k].seconds > 0 || topics[k].notes.isNotEmpty
                            ? Text(
                                [
                                  if (topics[k].seconds > 0) D.duration(Duration(seconds: topics[k].seconds)),
                                  if (topics[k].notes.isNotEmpty) topics[k].notes,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onTap: () => _topicMenu(topics[k]),
                        trailing: ReorderableDragStartListener(
                          index: k,
                          child: const Padding(padding: EdgeInsets.all(Gap.md), child: Icon(Icons.drag_handle_rounded)),
                        ),
                      ),
                    ),
                ],
              ),
              AppTextField(
                controller: _newTopic,
                hint: 'Add a topic',
                prefix: const Icon(Icons.add_rounded),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTopic(),
                suffix: IconButton(tooltip: 'Add topic', icon: const Icon(Icons.keyboard_return_rounded), onPressed: _addTopic),
              ),
              LinkedReminders(module: AppModule.study, itemId: s.id!, title: 'Study ${s.name}'),
              const SectionHeader('Sessions', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              if (sessions.isEmpty) Text('No sessions yet.', style: context.text.bodyMedium),
              for (final x in sessions.take(30))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(x.kind == 'pomodoro' ? Icons.av_timer_rounded : (x.kind == 'manual' ? Icons.edit_note_rounded : Icons.timer_outlined)),
                  title: Text(D.duration(x.duration)),
                  subtitle: Text([D.relativeDateTime(x.startedAt), ?x.topicName].join(' · ')),
                  trailing: IconButton(
                    tooltip: 'Delete session',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final m = ScaffoldMessenger.of(context);
                      final row = await repo.deleteSession(x.id!);
                      if (row != null) undoOn(m, 'Session deleted', () => repo.restoreSession(row));
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _topicMenu(Topic t) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.play_arrow_rounded), title: const Text('Study this topic'), onTap: () => Navigator.pop(ctx, 'study')),
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(leading: const Icon(Icons.notes_rounded), title: const Text('Notes'), onTap: () => Navigator.pop(ctx, 'notes')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final repo = ref.read(studyRepoProvider);
    switch (v) {
      case 'study':
        push(context, StudyTimerScreen(subjectId: t.subjectId, topicId: t.id));
      case 'rename':
        final n = await promptText(context, title: 'Rename topic', initial: t.name);
        if (n != null) await repo.saveTopic(id: t.id, subjectId: t.subjectId, name: n, notes: t.notes);
      case 'notes':
        final n = await promptText(context, title: 'Topic notes', initial: t.notes);
        if (n != null) await repo.saveTopic(id: t.id, subjectId: t.subjectId, name: t.name, notes: n);
      case 'delete':
        if (await confirmDialog(context, title: 'Delete topic?', message: t.name)) await repo.deleteTopic(t.id!);
    }
  }
}
