import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../../state/providers.dart';
import 'gym_providers.dart';

/// Body weight & measurements with full history per measurement.
class BodyScreen extends ConsumerStatefulWidget {
  const BodyScreen({super.key, this.initialKind = BodyKind.weight});
  final String initialKind;
  @override
  ConsumerState<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends ConsumerState<BodyScreen> {
  late String _kind = widget.initialKind;

  String _unit(String kind) => kind == BodyKind.weight ? ref.read(settingsProvider).weightUnit : 'cm';

  @override
  Widget build(BuildContext context) {
    final kinds = ref.watch(bodyKindsProvider).value ?? BodyKind.builtIn;
    final latest = ref.watch(latestBodyProvider).value ?? const {};
    final list = ref.watch(bodyMetricsProvider(_kind));
    final unit = _unit(_kind);
    return Scaffold(
      appBar: AppBar(title: const Text('Body')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'body-fab',
        onPressed: () => addBodyEntry(context, ref, kind: _kind),
        icon: const Icon(Icons.add_rounded),
        label: Text('Log $_kind'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.sm),
              itemCount: kinds.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
              itemBuilder: (context, i) {
                if (i == kinds.length) {
                  return AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                    onTap: () async {
                      final name = await promptText(context, title: 'Custom measurement', hint: 'e.g. Neck, Body fat %');
                      if (name != null && mounted) {
                        setState(() => _kind = name);
                        if (context.mounted) await addBodyEntry(context, ref, kind: name);
                      }
                    },
                    child: const Center(child: Row(children: [Icon(Icons.add_rounded), SizedBox(width: 4), Text('Custom')])),
                  );
                }
                final k = kinds[i];
                final sel = k == _kind;
                final l = latest[k];
                return SizedBox(
                  width: 112,
                  child: AppCard(
                    padding: const EdgeInsets.all(Gap.md),
                    color: sel ? AppModule.gym.color.withValues(alpha: 0.14) : null,
                    borderColor: sel ? AppModule.gym.color : null,
                    onTap: () => setState(() => _kind = k),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(k, style: context.text.labelMedium, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(l == null ? '—' : '${trimNum(l.value)} ${_unit(k)}', style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          AsyncBody<List<BodyMetric>>(
            value: list,
            compact: true,
            builder: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  color: AppModule.gym.color,
                  title: 'No $_kind entries',
                  message: 'Log your first measurement to start tracking progress.',
                  compact: true,
                );
              }
              final first = items.first.value;
              final last = items.last.value;
              final diff = last - first;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Gap.sm),
                    ChartCard(
                      title: '$_kind over time',
                      subtitle: '${diff >= 0 ? '+' : ''}${trimNum(diff)} $unit since ${D.dayMonthYear(items.first.measuredAt)}',
                      child: TimeLineChart(points: [for (final m in items) (m.measuredAt, m.value)], color: AppModule.gym.color, unit: ' $unit'),
                    ),
                    const SectionHeader('History', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
                    for (final m in items.reversed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${trimNum(m.value)} $unit', style: context.text.titleSmall),
                        subtitle: Text(D.dayMonthYear(m.measuredAt)),
                        trailing: IconButton(
                          tooltip: 'Delete entry',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final repo = ref.read(gymRepoProvider);
                            final row = await repo.deleteBodyMetric(m.id!);
                            if (row != null) undoOn(messenger, 'Entry deleted', () => repo.restoreRow('body_metrics', row));
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> addBodyEntry(BuildContext context, WidgetRef ref, {required String kind}) {
  return showAppSheet<void>(context, builder: (_) => _BodyEntrySheet(kind: kind));
}

class _BodyEntrySheet extends ConsumerStatefulWidget {
  const _BodyEntrySheet({required this.kind});
  final String kind;
  @override
  ConsumerState<_BodyEntrySheet> createState() => _BodyEntrySheetState();
}

class _BodyEntrySheetState extends ConsumerState<_BodyEntrySheet> {
  final _value = TextEditingController();
  DateTime _date = D.today();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_value.text.replaceAll(',', '.'));
    if (v == null || v <= 0) {
      showSnack(context, 'Enter a valid number');
      return;
    }
    final now = DateTime.now();
    final at = D.sameDay(_date, now) ? now : DateTime(_date.year, _date.month, _date.day, 12);
    await guard(context, () => ref.read(gymRepoProvider).addBodyMetric(widget.kind, v, at));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.kind == BodyKind.weight ? ref.read(settingsProvider).weightUnit : 'cm';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Log ${widget.kind}', style: context.text.titleLarge),
          AppTextField(
            controller: _value,
            label: 'Value ($unit)',
            autofocus: true,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalFormatter],
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Gap.sm),
          PickerTile(
            icon: Icons.event_outlined,
            label: 'Date',
            value: D.relativeDay(_date),
            onTap: () async {
              final d = await pickDate(context, initial: _date, last: DateTime.now());
              if (d != null) setState(() => _date = d);
            },
          ),
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
