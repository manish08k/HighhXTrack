import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/money.dart';
import '../../data/repositories/money_repo.dart';
import '../shell/nav.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';
import 'money_insights.dart';
import 'money_providers.dart';
import 'money_widgets.dart';
import 'recurring_screen.dart';
import 'txn_editor.dart';

class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key, this.standalone = false});
  final bool standalone;
  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  TxKind? _kind;
  int? _categoryId;
  String _search = '';
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(moneyMonthProvider);
    final summary = ref.watch(monthSummaryProvider(month)).value;
    final cats = ref.watch(moneyCategoriesProvider).value ?? const <MoneyCategory>[];
    final catMap = {for (final c in cats) c.id: c};
    final txns = ref.watch(transactionsProvider(TxQuery(month: month, kind: _kind, categoryId: _categoryId, search: _search)));
    final bills = ref.watch(upcomingBillsProvider).value ?? const <RecurringTxn>[];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes, categories…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _search = v),
              )
            : const Text('Money'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search = '';
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'budget' => push(context, const BudgetScreen()),
              'recurring' => push(context, const RecurringScreen()),
              'insights' => push(context, const MoneyInsightsScreen()),
              _ => push(context, const MoneyCategoriesScreen()),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'budget', child: Text('Budget')),
              PopupMenuItem(value: 'recurring', child: Text('Recurring')),
              PopupMenuItem(value: 'insights', child: Text('Insights')),
              PopupMenuItem(value: 'categories', child: Text('Categories')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'money-fab',
        tooltip: 'Add transaction',
        onPressed: () => push(context, const TxnEditorScreen()),
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: MonthSwitcher(month: month, onShift: ref.read(moneyMonthProvider.notifier).shift),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              child: _SummaryCard(s: summary),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickLink(icon: Icons.pie_chart_outline_rounded, label: 'Budget', onTap: () => push(context, const BudgetScreen())),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _QuickLink(icon: Icons.autorenew_rounded, label: 'Recurring', onTap: () => push(context, const RecurringScreen())),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _QuickLink(icon: Icons.insights_rounded, label: 'Insights', onTap: () => push(context, const MoneyInsightsScreen())),
                  ),
                ],
              ),
            ),
          ),
          if (bills.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Upcoming bills')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                  itemCount: bills.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
                  itemBuilder: (context, i) {
                    final b = bills[i];
                    final days = D.diffDays(D.today(), b.next);
                    return SizedBox(
                      width: 170,
                      child: AppCard(
                        padding: const EdgeInsets.all(Gap.md),
                        onTap: () => push(context, const RecurringScreen()),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                            Text(
                              '${Money.format(b.amount)} · ${days <= 0 ? 'today' : D.relativeDay(b.next)}',
                              style: context.text.bodySmall!.copyWith(color: days <= 1 ? Palette.warning : null),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SectionHeader('Transactions')),
          SliverToBoxAdapter(
            child: ChoiceChips<Object?>(
              padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.sm),
              options: [null, TxKind.expense, TxKind.income, ...cats.where((c) => _kind == null || c.kind == _kind).map((c) => c.id)],
              selected: _categoryId ?? _kind,
              label: (o) => o == null ? 'All' : (o is TxKind ? o.label : catMap[o]?.name ?? ''),
              onSelected: (o) => setState(() {
                if (o == null) {
                  _kind = null;
                  _categoryId = null;
                } else if (o is TxKind) {
                  _kind = o;
                  _categoryId = null;
                } else {
                  _categoryId = o as int;
                }
              }),
            ),
          ),
          AsyncSliver<List<Txn>>(
            value: txns,
            builder: (list) {
              if (list.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    color: AppModule.money.color,
                    title: _search.isEmpty ? 'No transactions in ${D.monthYear(month)}' : 'No matches',
                    message: _search.isEmpty ? 'Track an expense or income with the + button.' : null,
                    compact: true,
                  ),
                );
              }
              final rows = <Object>[];
              DateTime? last;
              for (final t in list) {
                if (last == null || !D.sameDay(last, t.date)) {
                  final dayTotal = list.where((x) => D.sameDay(x.date, t.date) && x.kind == TxKind.expense).fold<int>(0, (a, x) => a + x.amount);
                  rows.add((D.relativeDay(t.date), dayTotal));
                  last = t.date;
                }
                rows.add(t);
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, 96),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    if (r is (String, int)) {
                      return Padding(
                        padding: EdgeInsets.only(top: i == 0 ? Gap.xs : Gap.lg, bottom: Gap.sm, left: Gap.xs, right: Gap.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(r.$1, style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant)),
                            ),
                            if (r.$2 > 0) Text('−${Money.format(r.$2)}', style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }
                    final t = r as Txn;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: TxnTile(txn: t, category: catMap[t.categoryId]),
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
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.s});
  final MonthSummary? s;

  @override
  Widget build(BuildContext context) {
    final s = this.s;
    if (s == null) return const AppCard(child: SizedBox(height: 120, child: LoadingView(compact: true)));
    final used = s.budgetUsed;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spent this month', style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(Money.format(s.expense), style: context.text.headlineMedium),
          if (s.budget != null) ...[
            const SizedBox(height: Gap.md),
            AppProgressBar(value: used, color: budgetColor(used)),
            const SizedBox(height: 6),
            Text(
              s.remaining! >= 0
                  ? '${Money.format(s.remaining!)} of ${Money.format(s.budget!)} budget left'
                  : '${Money.format(-s.remaining!)} over your ${Money.format(s.budget!)} budget',
              style: context.text.bodySmall!.copyWith(color: budgetColor(used)),
            ),
          ],
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              Expanded(
                child: _Mini(label: 'Income', value: Money.format(s.income), color: Palette.success),
              ),
              Expanded(
                child: _Mini(label: 'Savings', value: Money.format(s.savings), color: s.savings >= 0 ? Palette.success : Palette.danger),
              ),
              Expanded(
                child: _Mini(label: 'Today', value: Money.format(s.spentToday)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value, style: context.text.titleSmall!.copyWith(color: color)),
      ),
    ],
  );
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: Gap.md),
    onTap: onTap,
    child: Column(
      children: [
        Icon(icon, color: AppModule.money.color),
        const SizedBox(height: 4),
        Text(label, style: context.text.labelMedium),
      ],
    ),
  );
}
