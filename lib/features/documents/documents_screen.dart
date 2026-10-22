import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/planner.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'document_detail.dart';
import 'document_editor.dart';
import 'document_providers.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});
  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  DocStatus? _status;
  String? _category;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final hide = ref.watch(settingsProvider.select((s) => s.hideAmounts));
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'doc-fab',
        tooltip: 'Add document',
        onPressed: () => push(context, const DocumentEditorScreen()),
        child: const Icon(Icons.add_rounded),
      ),
      body: AsyncBody<List<Doc>>(
        value: ref.watch(documentsProvider),
        onRetry: () => ref.invalidate(documentsProvider),
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.badge_outlined,
              color: AppModule.documents.color,
              title: 'No documents yet',
              message: 'Store passports, licences and insurance with expiry dates. You will be reminded before they expire.',
              actionLabel: 'Add document',
              onAction: () => push(context, const DocumentEditorScreen()),
            );
          }
          int count(DocStatus s) => all.where((d) => d.status == s).length;
          final q = _q.toLowerCase();
          final list = all.where((d) {
            if (_status != null && d.status != _status) return false;
            if (_category != null && d.category != _category) return false;
            if (q.isNotEmpty && !('${d.name} ${d.category} ${d.notes}'.toLowerCase().contains(q))) return false;
            return true;
          }).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            children: [
              Row(
                children: [
                  for (final s in [DocStatus.valid, DocStatus.expiring, DocStatus.expired]) ...[
                    Expanded(
                      child: AppCard(
                        padding: const EdgeInsets.all(Gap.md),
                        color: _status == s ? s.color.withValues(alpha: 0.14) : null,
                        borderColor: _status == s ? s.color : null,
                        onTap: () => setState(() => _status = _status == s ? null : s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${count(s)}', style: context.text.headlineSmall!.copyWith(color: s.color)),
                            Text(s.label, style: context.text.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    if (s != DocStatus.expired) const SizedBox(width: Gap.sm),
                  ],
                ],
              ),
              const SizedBox(height: Gap.md),
              AppTextField(hint: 'Search documents', prefix: const Icon(Icons.search_rounded), onChanged: (v) => setState(() => _q = v)),
              const SizedBox(height: Gap.sm),
              ChoiceChips<String?>(
                options: [null, ...kDocCategories],
                selected: _category,
                label: (c) => c ?? 'All',
                onSelected: (c) => setState(() => _category = c),
              ),
              const SizedBox(height: Gap.md),
              if (list.isEmpty) const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'No matching documents', compact: true),
              for (final d in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: AppCard(
                    onTap: () => push(context, DocumentDetailScreen(docId: d.id!)),
                    child: Row(
                      children: [
                        IconBadge(docIcon(d.category), AppModule.documents.color, size: 44),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(
                                [
                                  d.category,
                                  if (d.number.isNotEmpty) hide ? '••••' : '••${d.number.length > 4 ? d.number.substring(d.number.length - 4) : d.number}',
                                  if (d.attachmentCount > 0) '📎 ${d.attachmentCount}',
                                ].join(' · '),
                                style: context.text.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(docDaysLabel(d), style: context.text.labelMedium!.copyWith(color: d.status.color)),
                            ],
                          ),
                        ),
                        Pill(d.status.label, color: d.status.color),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
