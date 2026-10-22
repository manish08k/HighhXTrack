import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/utils/recurrence.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/money.dart';
import '../../state/providers.dart';
import 'categories_screen.dart';
import 'money_providers.dart';
import 'money_widgets.dart';

class TxnEditorScreen extends ConsumerStatefulWidget {
  const TxnEditorScreen({super.key, this.id, this.kind = TxKind.expense});
  final int? id;
  final TxKind kind;

  @override
  ConsumerState<TxnEditorScreen> createState() => _TxnEditorScreenState();
}

class _TxnEditorScreenState extends ConsumerState<TxnEditorScreen> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  Txn? _original;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  late TxKind _kind = widget.kind;
  int? _categoryId;
  DateTime _date = DateTime.now();
  String _method = '';
  Recurrence _repeat = Recurrence.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.id != null) {
      final t = await ref.read(moneyRepoProvider).get(widget.id!);
      if (!mounted) return;
      if (t == null) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      _original = t;
      _kind = t.kind;
      _amount.text = Money.inputValue(t.amount);
      _notes.text = t.notes;
      _categoryId = t.categoryId;
      _date = t.date;
      _method = t.paymentMethod;
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Money.parse(_amount.text);
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter an amount');
      return;
    }
    setState(() => _saving = true);
    final o = _original;
    final t = Txn(
      id: o?.id,
      kind: _kind,
      amount: amount,
      categoryId: _categoryId,
      date: _date,
      paymentMethod: _method,
      notes: _notes.text.trim(),
      recurringId: o?.recurringId,
      createdAt: o?.createdAt ?? DateTime.now(),
    );
    final repo = ref.read(moneyRepoProvider);
    final ok = await guard(context, () async {
      if (o == null && _repeat.repeats) {
        final next = _repeat.nextAfter(_date, _date) ?? _date;
        final rid = await repo.saveRecurring(
          RecurringTxn(
            title: t.notes.isEmpty ? (_kind == TxKind.income ? 'Recurring income' : 'Recurring expense') : t.notes,
            kind: _kind,
            amount: amount,
            categoryId: _categoryId,
            paymentMethod: _method,
            recurrence: _repeat,
            anchor: _date,
            next: next,
          ),
        );
        return repo.save(
          Txn(
            kind: t.kind,
            amount: t.amount,
            categoryId: t.categoryId,
            date: t.date,
            paymentMethod: t.paymentMethod,
            notes: t.notes,
            recurringId: rid,
            createdAt: t.createdAt,
          ),
        );
      }
      return repo.save(t);
    }, error: 'Could not save the transaction.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off_rounded, title: 'Transaction not found'),
      );
    }
    final o = _original;
    final cats = (ref.watch(moneyCategoriesProvider).value ?? const <MoneyCategory>[]).where((c) => c.kind == _kind).toList();
    final accent = _kind == TxKind.income ? Palette.success : AppModule.money.color;
    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'New transaction' : 'Edit transaction'),
        actions: [
          if (o != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDialog(context, title: 'Delete transaction?')) {
                  if (!context.mounted) return;
                  await TxnActions.delete(context, ref, o);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(label: o == null ? 'Add ${_kind.label.toLowerCase()}' : 'Save changes', onPressed: _save, busy: _saving),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
        children: [
          SegmentedButton<TxKind>(
            segments: const [
              ButtonSegment(value: TxKind.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward_rounded)),
              ButtonSegment(value: TxKind.income, label: Text('Income'), icon: Icon(Icons.arrow_downward_rounded)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: Gap.lg),
          TextField(
            controller: _amount,
            autofocus: o == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalFormatter],
            textAlign: TextAlign.center,
            style: context.text.displaySmall!.copyWith(color: accent),
            decoration: InputDecoration(
              hintText: '0',
              prefixText: '${Money.symbol} ',
              prefixStyle: context.text.headlineSmall!.copyWith(color: accent),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          const FieldLabel('Category'),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final c in cats)
                ChoiceChip(
                  avatar: Icon(iconAt(c.icon), size: 18, color: c.colorValue),
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  selectedColor: c.colorValue.withValues(alpha: 0.18),
                  onSelected: (_) => setState(() => _categoryId = c.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New'),
                onPressed: () async {
                  final id = await editMoneyCategory(context, kind: _kind);
                  if (id != null && mounted) setState(() => _categoryId = id);
                },
              ),
            ],
          ),
          const FieldLabel('Date'),
          PickerTile(
            icon: Icons.event_outlined,
            label: 'Date',
            value: D.relativeDay(_date),
            onTap: () async {
              final d = await pickDate(context, initial: _date);
              if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
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
          const FieldLabel('Note'),
          AppTextField(controller: _notes, hint: 'e.g. Lunch with team', maxLines: 3, minLines: 1),
          if (o == null) ...[
            const FieldLabel('Repeat'),
            PickerTile(
              icon: Icons.repeat_rounded,
              label: 'One-time',
              value: _repeat.repeats ? _repeat.label : null,
              onTap: () async {
                final r = await pickRecurrence(context, _repeat, anchor: _date);
                if (r != null) setState(() => _repeat = r);
              },
              onClear: () => setState(() => _repeat = Recurrence.none),
            ),
            if (_repeat.repeats)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm, left: Gap.xs),
                child: Text('Future occurrences are added automatically and you get a reminder on each due date.', style: context.text.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
