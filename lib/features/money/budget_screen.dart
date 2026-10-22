import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/money.dart';
import '../../state/providers.dart';
import 'money_providers.dart';
import 'money_widgets.dart';

Color budgetColor(double used) => used >= 1 ? Palette.danger : (used >= 0.8 ? Palette.warning : Palette.success);

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  Future<void> _editAmount(BuildContext context, {required String title, int? current, required Future<void> Function(int?) onSave}) async {
    final v = await promptText(
      context,
      title: title,
      initial: current == null ? '' : Money.inputValue(current),
      hint: 'Amount (leave empty to remove)',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
    if (v == null) {
      // Empty input → ask whether to clear an existing budget.
      if (current != null && context.mounted && await confirmDialog(context, title: 'Remove budget?', confirm: 'Remove')) await onSave(null);
      return;
    }
    final m = Money.parse(v);
    if (m == null || m <= 0) {
      if (context.mounted) showSnack(context, 'Enter a valid amount');
      return;
    }
    await onSave(m);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(moneyMonthProvider);
    final summary = ref.watch(monthSummaryProvider(month));
    final cats = (ref.watch(moneyCategoriesProvider).value ?? const <MoneyCategory>[]).where((c) => c.kind == TxKind.expense).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      body: AsyncBody<MonthSummary>(
        value: summary,
        builder: (s) {
          final used = s.budgetUsed;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxxl),
            children: [
              Center(
                child: MonthSwitcher(month: month, onShift: ref.read(moneyMonthProvider.notifier).shift),
              ),
              AppCard(
                onTap: () => _editAmount(
                  context,
                  title: 'Monthly budget',
                  current: s.budget,
                  onSave: (v) => ref.read(settingsProvider.notifier).update((x) => v == null ? x.copyWith(clearBudget: true) : x.copyWith(monthlyBudget: v)),
                ),
                child: s.budget == null
                    ? Row(
                        children: [
                          IconBadge(Icons.savings_outlined, AppModule.money.color),
                          const SizedBox(width: Gap.md),
                          Expanded(child: Text('Set a monthly budget to track how much you have left.', style: context.text.bodyMedium)),
                          const Icon(Icons.edit_outlined),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Monthly budget', style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                              ),
                              const Icon(Icons.edit_outlined, size: 18),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(Money.format(s.budget!), style: context.text.headlineSmall),
                          const SizedBox(height: Gap.md),
                          AppProgressBar(value: used, color: budgetColor(used), height: 10),
                          const SizedBox(height: Gap.sm),
                          Row(
                            children: [
                              Expanded(child: Text('Spent ${Money.format(s.expense)} · ${pct(used)}', style: context.text.bodySmall)),
                              Text(
                                s.remaining! >= 0 ? '${Money.format(s.remaining!)} left' : '${Money.format(-s.remaining!)} over',
                                style: context.text.labelLarge!.copyWith(color: budgetColor(used)),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SectionHeader('Category budgets', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: Builder(
                    builder: (context) {
                      final spent = s.byCategory[c.id] ?? 0;
                      final u = c.budget == null || c.budget == 0 ? 0.0 : spent / c.budget!;
                      return AppCard(
                        onTap: () => _editAmount(
                          context,
                          title: '${c.name} budget',
                          current: c.budget,
                          onSave: (v) => ref.read(moneyRepoProvider).setCategoryBudget(c.id!, v),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconBadge(iconAt(c.icon), c.colorValue, size: 34),
                                const SizedBox(width: Gap.md),
                                Expanded(child: Text(c.name, style: context.text.titleSmall)),
                                Text(
                                  c.budget == null ? Money.format(spent) : '${Money.format(spent)} / ${Money.format(c.budget!)}',
                                  style: context.text.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            if (c.budget != null) ...[
                              const SizedBox(height: Gap.sm),
                              AppProgressBar(value: u, color: budgetColor(u), height: 6),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  spent <= c.budget!
                                      ? '${Money.format(c.budget! - spent)} remaining · ${pct(u)}'
                                      : '${Money.format(spent - c.budget!)} over budget',
                                  style: context.text.bodySmall!.copyWith(color: budgetColor(u)),
                                ),
                              ),
                            ] else
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text('Tap to set a budget', style: context.text.bodySmall),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
