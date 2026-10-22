import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/money.dart';
import '../../state/providers.dart';
import 'money_providers.dart';

class MoneyCategoriesScreen extends ConsumerWidget {
  const MoneyCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        body: AsyncBody<List<MoneyCategory>>(
          value: ref.watch(moneyCategoriesProvider),
          builder: (all) => TabBarView(
            children: [
              for (final kind in TxKind.values)
                Builder(
                  builder: (context) {
                    final list = all.where((c) => c.kind == kind).toList();
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
                      children: [
                        for (final c in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gap.sm),
                            child: AppCard(
                              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
                              onTap: () => editMoneyCategory(context, existing: c),
                              child: Row(
                                children: [
                                  IconBadge(iconAt(c.icon), c.colorValue, size: 38),
                                  const SizedBox(width: Gap.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.name, style: context.text.titleSmall),
                                        if (c.budget != null) Text('Budget ${Money.format(c.budget!)} / month', style: context.text.bodySmall),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    onPressed: () async {
                                      if (await confirmDialog(
                                        context,
                                        title: 'Delete "${c.name}"?',
                                        message: 'Existing transactions are kept as Uncategorized.',
                                      )) {
                                        await ref.read(moneyRepoProvider).deleteCategory(c.id!);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => editMoneyCategory(context, kind: kind),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add category'),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<int?> editMoneyCategory(BuildContext context, {MoneyCategory? existing, TxKind kind = TxKind.expense}) {
  return showAppSheet<int>(
    context,
    builder: (_) => _CategorySheet(existing: existing, kind: existing?.kind ?? kind),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing, required this.kind});
  final MoneyCategory? existing;
  final TxKind kind;
  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _budget = TextEditingController(text: widget.existing?.budget == null ? '' : Money.inputValue(widget.existing!.budget!));
  late int _icon = widget.existing?.icon ?? 8;
  late int _color = widget.existing?.color ?? Palette.swatches[3].toARGB32();

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final e = widget.existing;
    final budget = widget.kind == TxKind.expense ? Money.parse(_budget.text) : null;
    final id = await guard(
      context,
      () => ref
          .read(moneyRepoProvider)
          .saveCategory(
            MoneyCategory(
              id: e?.id,
              name: _name.text.trim(),
              kind: widget.kind,
              icon: _icon,
              color: _color,
              budget: (budget ?? 0) > 0 ? budget : null,
              isDefault: e?.isDefault ?? false,
              position: e?.position ?? 0,
            ),
          ),
    );
    if (id != null && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final c = Color(_color);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'New ${widget.kind.label.toLowerCase()} category' : 'Edit category', style: context.text.titleLarge),
          AppTextField(controller: _name, label: 'Name', autofocus: widget.existing == null),
          if (widget.kind == TxKind.expense)
            AppTextField(
              controller: _budget,
              label: 'Monthly budget (optional)',
              hint: '0',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [decimalFormatter],
              prefix: Padding(padding: const EdgeInsets.all(14), child: Text(Money.symbol)),
            ),
          const FieldLabel('Color'),
          ColorChoice(value: _color, onChanged: (v) => setState(() => _color = v)),
          const FieldLabel('Icon'),
          IconChoice(value: _icon, color: c, onChanged: (v) => setState(() => _icon = v)),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
