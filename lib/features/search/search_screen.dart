import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/states.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/search_repo.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';

final globalSearchProvider = FutureProvider.autoDispose.family<Map<AppModule, List<SearchHit>>, String>((ref, q) {
  ref.watchTopics(Chg.all);
  return ref.read(searchRepoProvider).search(q);
});

/// One search across every module, grouped by module.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  AppModule? _only;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search tasks, notes, money, exercises…',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _q = '');
                    },
                  ),
          ),
        ),
      ),
      body: _q.isEmpty
          ? const EmptyState(
              icon: Icons.manage_search_rounded,
              title: 'Search everything',
              message: 'Todos, exercises, transactions, reminders, habits, events, documents, notes and study topics.',
            )
          : AsyncBody<Map<AppModule, List<SearchHit>>>(
              value: ref.watch(globalSearchProvider(_q)),
              builder: (res) {
                if (res.isEmpty) return EmptyState(icon: Icons.search_off_rounded, title: 'No results for "$_q"');
                final modules = res.keys.toList();
                final shown = _only == null ? modules : modules.where((m) => m == _only).toList();
                return ListView(
                  padding: const EdgeInsets.only(bottom: Gap.xxxl),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.sm),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: Gap.sm),
                            child: ChoiceChip(
                              label: Text('All ${res.values.fold<int>(0, (a, l) => a + l.length)}'),
                              selected: _only == null,
                              onSelected: (_) => setState(() => _only = null),
                            ),
                          ),
                          for (final m in modules)
                            Padding(
                              padding: const EdgeInsets.only(right: Gap.sm),
                              child: ChoiceChip(
                                avatar: Icon(m.icon, size: 16, color: m.color),
                                label: Text('${m.label} ${res[m]!.length}'),
                                selected: _only == m,
                                onSelected: (_) => setState(() => _only = _only == m ? null : m),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final m in shown) ...[
                      SectionHeader(m.label),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                          child: Column(
                            children: [
                              for (final h in res[m]!)
                                ListTile(
                                  leading: IconBadge(m.icon, m.color, size: 36),
                                  title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => openItem(ref, h.module, h.id, kind: h.kind, parentId: h.parentId),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Text('Showing up to 8 results per module', textAlign: TextAlign.center, style: context.text.bodySmall),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
