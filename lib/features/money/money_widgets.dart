import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/swipe.dart';
import '../../data/models/money.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'txn_editor.dart';

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onShift});
  final DateTime month;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final isCurrent = D.sameDay(month, D.startOfMonth(DateTime.now()));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Previous month', onPressed: () => onShift(-1), icon: const Icon(Icons.chevron_left_rounded)),
        Text(D.monthYear(month), style: context.text.titleSmall),
        IconButton(tooltip: 'Next month', onPressed: isCurrent ? null : () => onShift(1), icon: const Icon(Icons.chevron_right_rounded)),
      ],
    );
  }
}

abstract final class TxnActions {
  static Future<void> delete(BuildContext context, WidgetRef ref, Txn t) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(moneyRepoProvider);
    final row = await guard(context, () => repo.delete(t.id!));
    if (row == null) return;
    undoOn(m, 'Transaction deleted', () => repo.restore(row));
  }
}

class TxnTile extends ConsumerWidget {
  const TxnTile({super.key, required this.txn, this.category, this.swipe = true});
  final Txn txn;
  final MoneyCategory? category;
  final bool swipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = txn;
    final c = category?.colorValue ?? context.colors.onSurfaceVariant;
    final income = t.kind == TxKind.income;
    final title = t.notes.isNotEmpty ? t.notes : (category?.name ?? (income ? 'Income' : 'Expense'));
    final tile = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
      onTap: () => push(context, TxnEditorScreen(id: t.id)),
      child: Row(
        children: [
          IconBadge(category == null ? Icons.category_rounded : iconAt(category!.icon), c, size: 42),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [category?.name ?? 'Uncategorized', if (t.paymentMethod.isNotEmpty) t.paymentMethod, if (t.recurringId != null) 'Recurring'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          Text(
            '${income ? '+' : '−'}${Money.format(t.amount)}',
            style: context.text.titleSmall!.copyWith(
              color: income ? Palette.success : context.colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    if (!swipe) return tile;
    return SwipeTile(
      key: ValueKey('tx-${t.id}'),
      start: SwipeAction(
        icon: Icons.edit_outlined,
        label: 'Edit',
        color: Palette.info,
        onTrigger: () async => push(context, TxnEditorScreen(id: t.id)),
      ),
      end: SwipeAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        color: Palette.danger,
        dismiss: true,
        onTrigger: () => TxnActions.delete(context, ref, t),
      ),
      child: tile,
    );
  }
}
