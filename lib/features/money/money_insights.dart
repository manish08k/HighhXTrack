import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/states.dart';
import '../../data/models/money.dart';
import 'money_providers.dart';
import 'money_widgets.dart';

String _compact(double minorUnits) {
  final v = minorUnits / 100;
  if (v.abs() >= 100000) return '${trimNum(v / 100000)}L';
  if (v.abs() >= 1000) return '${trimNum(v / 1000)}k';
  return trimNum(v, digits: 0);
}

class MoneyInsightsScreen extends ConsumerWidget {
  const MoneyInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(moneyMonthProvider);
    final summary = ref.watch(monthSummaryProvider(month));
    final prevSummary = ref.watch(monthSummaryProvider(D.addMonths(month, -1))).value;
    final daily = ref.watch(dailySpendingProvider(month)).value ?? const <int>[];
    final monthly = ref.watch(monthlyTotalsProvider).value ?? const [];
    final cats = {for (final c in ref.watch(moneyCategoriesProvider).value ?? const <MoneyCategory>[]) c.id: c};
    final expColor = AppModule.money.color;

    return Scaffold(
      appBar: AppBar(title: const Text('Money insights')),
      body: AsyncBody<MonthSummary>(
        value: summary,
        builder: (s) {
          final diff = prevSummary == null ? null : s.expense - prevSummary.expense;
          final cum = <(DateTime, double)>[];
          var savings = 0;
          for (final m in monthly) {
            savings += m.$2 - m.$3;
            cum.add((m.$1, savings / 100));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxxl),
            children: [
              Center(
                child: MonthSwitcher(month: month, onShift: ref.read(moneyMonthProvider.notifier).shift),
              ),
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(label: 'Spent', value: Money.format(s.expense), icon: Icons.north_east_rounded),
                  StatTile(label: 'Income', value: Money.format(s.income), color: Palette.success, icon: Icons.south_west_rounded),
                  StatTile(
                    label: 'Saved',
                    value: Money.format(s.savings),
                    color: s.savings >= 0 ? Palette.success : Palette.danger,
                    icon: Icons.savings_outlined,
                    caption: s.income == 0 ? null : '${pct((s.savings / s.income).clamp(-9, 1))} of income',
                  ),
                  StatTile(
                    label: 'vs last month',
                    icon: Icons.compare_arrows_rounded,
                    value: diff == null
                        ? '—'
                        : '${diff > 0
                              ? '+'
                              : diff < 0
                              ? '−'
                              : ''}${Money.format(diff.abs())}',
                    color: diff == null ? null : (diff > 0 ? Palette.danger : Palette.success),
                    caption: diff == null ? null : (diff > 0 ? 'more spent' : 'less spent'),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Daily spending',
                subtitle: D.monthYear(month),
                child: SimpleBarChart(
                  values: [for (final d in daily) d.toDouble()],
                  labels: [for (var k = 0; k < daily.length; k++) '${k + 1}'],
                  color: expColor,
                  format: _compact,
                  target: s.budget == null || daily.isEmpty ? null : s.budget! / daily.length,
                ),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Category breakdown',
                subtitle: 'Expenses in ${D.monthYear(month)}',
                child: RankedBars(
                  format: (v) => Money.format(v.round()),
                  items: [
                    for (final e in s.byCategory.entries)
                      (
                        cats[e.key]?.name ?? 'Uncategorized',
                        e.value.toDouble(),
                        cats[e.key]?.colorValue ?? context.colors.onSurfaceVariant,
                        cats[e.key] == null ? Icons.category_rounded : iconAt(cats[e.key]!.icon),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Income vs expenses',
                subtitle: 'Last 6 months',
                legend: [('Income', Palette.success), ('Expenses', expColor)],
                child: SimpleBarChart(
                  values: [for (final m in monthly) m.$2.toDouble()],
                  second: [for (final m in monthly) m.$3.toDouble()],
                  labels: [for (final m in monthly) D.shortMonth(m.$1)],
                  color: Palette.success,
                  secondColor: expColor,
                  seriesNames: ('Income', 'Expenses'),
                  format: _compact,
                ),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Monthly spending',
                subtitle: 'Last 6 months',
                child: SimpleBarChart(
                  values: [for (final m in monthly) m.$3.toDouble()],
                  labels: [for (final m in monthly) D.shortMonth(m.$1)],
                  color: expColor,
                  highlightLast: true,
                  format: _compact,
                ),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Savings trend',
                subtitle: 'Cumulative income − expenses, last 6 months',
                child: TimeLineChart(points: cum, color: Palette.success, format: (v) => _compact(v * 100)),
              ),
            ],
          );
        },
      ),
    );
  }
}
