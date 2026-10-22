import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/utils/recurrence.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/money.dart';
import '../../state/providers.dart';
import 'money_providers.dart';

/// Salary, rent, subscriptions, bills and other recurring transactions.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = {for (final c in ref.watch(moneyCategoriesProvider).value ?? const <MoneyCategory>[]) c.id: c};
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'rec-fab',
        tooltip: 'New recurring transaction',
        onPressed: () => editRecurring(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: AsyncBody<List<RecurringTxn>>(
        value: ref.watch(recurringProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.autorenew_rounded,
              color: AppModule.money.color,
              title: 'No recurring transactions',
              message: 'Add salary, rent, subscriptions and bills. They are recorded automatically and you get reminded.',
              actionLabel: 'Add recurring',
              onAction: () => editRecurring(context),
            );
          }
          final monthlyOut = list.where((r) => r.active && r.kind == TxKind.expense).fold<double>(0, (a, r) => a + _monthlyEquivalent(r));
          final monthlyIn = list.where((r) => r.active && r.kind == TxKind.income).fold<double>(0, (a, r) => a + _monthlyEquivalent(r));
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            children: [
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(label: 'Monthly income', value: Money.format(monthlyIn.round()), color: Palette.success, icon: Icons.south_west_rounded),
                  StatTile(label: 'Monthly bills', value: Money.format(monthlyOut.round()), icon: Icons.north_east_rounded),
                ],
              ),
              const SizedBox(height: Gap.lg),
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: Opacity(
                    opacity: r.active ? 1 : 0.55,
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
                      onTap: () => editRecurring(context, existing: r),
                      child: Row(
                        children: [
                          IconBadge(
                            cats[r.categoryId] == null ? Icons.autorenew_rounded : iconAt(cats[r.categoryId]!.icon),
                            cats[r.categoryId]?.colorValue ?? AppModule.money.color,
                          ),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.title, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  r.active ? '${r.recurrence.label} · next ${D.relativeDay(r.next)}${r.autoAdd ? '' : ' · manual'}' : 'Paused',
                                  style: context.text.bodySmall!.copyWith(color: r.active && D.diffDays(D.today(), r.next) <= 2 ? Palette.warning : null),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${r.kind == TxKind.income ? '+' : ''}${Money.format(r.amount)}',
                            style: context.text.titleSmall!.copyWith(color: r.kind == TxKind.income ? Palette.success : null),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              final repo = ref.read(moneyRepoProvider);
                              switch (v) {
                                case 'pay':
                                  await repo.payRecurringNow(r);
                                  if (context.mounted) {
                                    showSnack(
                                      context,
                                      'Recorded ${Money.format(r.amount)} · next ${D.relativeDay(r.recurrence.nextAfter(r.anchor, r.next) ?? r.next)}',
                                    );
                                  }
                                case 'toggle':
                                  await repo.saveRecurring(
                                    RecurringTxn(
                                      id: r.id,
                                      title: r.title,
                                      kind: r.kind,
                                      amount: r.amount,
                                      categoryId: r.categoryId,
                                      paymentMethod: r.paymentMethod,
                                      recurrence: r.recurrence,
                                      anchor: r.anchor,
                                      next: _rollForward(r),
                                      autoAdd: r.autoAdd,
                                      remind: r.remind,
                                      active: !r.active,
                                    ),
                                  );
                                case 'delete':
                                  if (context.mounted && await confirmDialog(context, title: 'Delete "${r.title}"?', message: 'Past transactions are kept.')) {
                                    await repo.deleteRecurring(r.id!);
                                  }
                              }
                            },
                            itemBuilder: (_) => [
                              if (r.active) PopupMenuItem(value: 'pay', child: Text(r.kind == TxKind.income ? 'Record now' : 'Mark paid now')),
                              PopupMenuItem(value: 'toggle', child: Text(r.active ? 'Pause' : 'Resume')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// On resume, skip past occurrences so nothing is back-filled.
  static DateTime _rollForward(RecurringTxn r) {
    if (r.active) return r.next;
    var next = r.next;
    final today = D.today();
    var guard = 0;
    while (next.isBefore(today) && guard++ < 1000) {
      next = r.recurrence.nextAfter(r.anchor, next) ?? today;
    }
    return next;
  }

  static double _monthlyEquivalent(RecurringTxn r) {
    final i = r.recurrence.interval;
    return switch (r.recurrence.freq) {
      RepeatFreq.daily => r.amount * 30.4 / i,
      RepeatFreq.weekly => r.amount * 4.35 * (r.recurrence.weekdays.isEmpty ? 1 : r.recurrence.weekdays.length) / i,
      RepeatFreq.monthly => r.amount / i,
      RepeatFreq.yearly => r.amount / (12 * i),
      RepeatFreq.none => 0,
    };
  }
}

Future<void> editRecurring(BuildContext context, {RecurringTxn? existing}) => showAppSheet<void>(context, builder: (_) => _RecurringSheet(existing: existing));

class _RecurringSheet extends ConsumerStatefulWidget {
  const _RecurringSheet({this.existing});
  final RecurringTxn? existing;
  @override
  ConsumerState<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends ConsumerState<_RecurringSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount = TextEditingController(text: widget.existing == null ? '' : Money.inputValue(widget.existing!.amount));
  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late int? _categoryId = widget.existing?.categoryId;
  late Recurrence _rec = widget.existing?.recurrence ?? Recurrence.monthly;
  late DateTime _next = widget.existing?.next ?? D.today();
  late bool _autoAdd = widget.existing?.autoAdd ?? true;
  late bool _remind = widget.existing?.remind ?? true;
  late String _method = widget.existing?.paymentMethod ?? '';

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Money.parse(_amount.text);
    if (_title.text.trim().isEmpty || amount == null || amount <= 0) {
      showSnack(context, 'Enter a name and amount');
      return;
    }
    final e = widget.existing;
    final scheduleChanged = e == null || e.recurrence != _rec || !D.sameDay(e.next, _next);
    final r = RecurringTxn(
      id: e?.id,
      title: _title.text.trim(),
      kind: _kind,
      amount: amount,
      categoryId: _categoryId,
      paymentMethod: _method,
      recurrence: _rec,
      anchor: scheduleChanged ? _next : e.anchor,
      next: _next,
      autoAdd: _autoAdd,
      remind: _remind,
      active: e?.active ?? true,
    );
    final ok = await guard(context, () => ref.read(moneyRepoProvider).saveRecurring(r));
    if (ok == null || !mounted) return;
    // Record anything already due (e.g. a start date of today).
    await ref.read(moneyRepoProvider).processDue();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cats = (ref.watch(moneyCategoriesProvider).value ?? const <MoneyCategory>[]).where((c) => c.kind == _kind).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'New recurring' : 'Edit recurring', style: context.text.titleLarge),
          const SizedBox(height: Gap.md),
          SegmentedButton<TxKind>(
            segments: const [
              ButtonSegment(value: TxKind.expense, label: Text('Expense / bill')),
              ButtonSegment(value: TxKind.income, label: Text('Income')),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _categoryId = null;
            }),
          ),
          AppTextField(controller: _title, label: 'Name', hint: _kind == TxKind.income ? 'e.g. Salary' : 'e.g. Rent, Netflix, Electricity'),
          AppTextField(
            controller: _amount,
            label: 'Amount',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalFormatter],
            prefix: Padding(padding: const EdgeInsets.all(14), child: Text(Money.symbol)),
          ),
          const FieldLabel('Category'),
          ChoiceChips<int?>(
            options: [null, ...cats.map((c) => c.id)],
            selected: _categoryId,
            wrap: true,
            label: (id) => id == null ? 'None' : cats.firstWhere((c) => c.id == id).name,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const FieldLabel('Schedule'),
          PickerTile(
            icon: Icons.event_outlined,
            label: 'Next date',
            value: 'Next: ${D.relativeDay(_next)}',
            onTap: () async {
              final d = await pickDate(context, initial: _next);
              if (d != null) setState(() => _next = d);
            },
          ),
          const SizedBox(height: Gap.sm),
          PickerTile(
            icon: Icons.repeat_rounded,
            label: 'Repeat',
            value: _rec.label,
            onTap: () async {
              final r = await pickRecurrence(context, _rec, anchor: _next);
              if (r != null && r.repeats) setState(() => _rec = r);
            },
          ),
          const FieldLabel('Payment method'),
          ChoiceChips<String>(
            options: kPaymentMethods,
            selected: _method,
            wrap: true,
            label: (m) => m,
            onSelected: (m) => setState(() => _method = _method == m ? '' : m),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add automatically'),
            subtitle: const Text('Record the transaction on each due date'),
            value: _autoAdd,
            onChanged: (v) => setState(() => _autoAdd = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me'),
            subtitle: const Text('Notification at 9:00 AM on the due date'),
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
          ),
          const SizedBox(height: Gap.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
