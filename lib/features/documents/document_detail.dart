import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/document_repo.dart';
import '../../state/providers.dart';
import '../shared/attachments_section.dart';
import '../shared/linked_reminders.dart';
import '../shell/nav.dart';
import 'document_editor.dart';
import 'document_providers.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.docId});
  final int docId;
  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  /// Document numbers are masked until revealed.
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Doc?>(
      value: ref.watch(documentProvider(widget.docId)),
      loading: const Scaffold(body: LoadingView()),
      builder: (d) {
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Document not found'),
          );
        }
        final s = d.status;
        return Scaffold(
          appBar: AppBar(
            title: Text(d.name),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => push(context, DocumentEditorScreen(id: d.id)),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await confirmDialog(context, title: 'Delete document?', message: '"${d.name}" and its attachments will be permanently deleted.')) {
                    await ref.read(documentRepoProvider).delete(d.id!);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
            children: [
              AppCard(
                color: s.color.withValues(alpha: 0.1),
                borderColor: s.color.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    IconBadge(docIcon(d.category), AppModule.documents.color, size: 48),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.category, style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                          Text(docDaysLabel(d), style: context.text.titleMedium!.copyWith(color: s.color)),
                        ],
                      ),
                    ),
                    Pill(s.label, color: s.color),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Column(
                  children: [
                    if (d.number.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.numbers_rounded),
                        title: Text(_reveal ? d.number : '•' * d.number.length.clamp(4, 16)),
                        subtitle: const Text('Document number'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _reveal ? 'Hide' : 'Show',
                              icon: Icon(_reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _reveal = !_reveal),
                            ),
                            IconButton(
                              tooltip: 'Copy',
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: d.number));
                                showSnack(context, 'Number copied');
                              },
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.event_available_outlined),
                      title: Text(d.issueAt == null ? '—' : D.dayMonthYear(d.issueAt!)),
                      subtitle: const Text('Issue date'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.event_busy_outlined),
                      title: Text(d.expiryAt == null ? '—' : D.dayMonthYear(d.expiryAt!)),
                      subtitle: const Text('Expiry date'),
                    ),
                    if (d.expiryAt != null)
                      ListTile(
                        leading: const Icon(Icons.notifications_none_rounded),
                        title: Text('${d.remindDays} days before (${D.dayMonthYear(d.remindAt!)})'),
                        subtitle: const Text('Renewal reminder'),
                      ),
                  ],
                ),
              ),
              if (d.notes.isNotEmpty) ...[const SizedBox(height: Gap.md), AppCard(child: Text(d.notes))],
              AttachmentsSection(ownerType: 'document', ownerId: d.id, label: 'Scans & photos'),
              LinkedReminders(module: AppModule.documents, itemId: d.id!, title: 'Renew ${d.name}', suggestedTime: d.remindAt),
            ],
          ),
        );
      },
    );
  }
}
