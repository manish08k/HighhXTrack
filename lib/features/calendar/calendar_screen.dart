import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/states.dart';
import '../shell/nav.dart';
import 'calendar_data.dart';
import 'event_editor.dart';

enum CalView { month, week, day }

const kCalendarModules = [AppModule.calendar, AppModule.todo, AppModule.gym, AppModule.reminders, AppModule.study];

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.standalone = false});
  final bool standalone;
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalView _view = CalView.month;
  DateTime _selected = D.today();
  DateTime _month = D.startOfMonth(DateTime.now());

  void _shift(int dir) => setState(() {
    switch (_view) {
      case CalView.month:
        _month = D.addMonths(_month, dir);
        _selected = D.sameDay(_month, D.startOfMonth(DateTime.now())) ? D.today() : _month;
      case CalView.week:
        _selected = D.addDays(_selected, 7 * dir);
        _month = D.startOfMonth(_selected);
      case CalView.day:
        _selected = D.addDays(_selected, dir);
        _month = D.startOfMonth(_selected);
    }
  });

  String get _title => switch (_view) {
    CalView.month => D.monthYear(_month),
    CalView.week => '${D.dayMonth(D.startOfWeek(_selected))} – ${D.dayMonth(D.addDays(D.startOfWeek(_selected), 6))}',
    CalView.day => D.relativeDay(_selected),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: const Text('Calendar'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _selected = D.today();
              _month = D.startOfMonth(_selected);
            }),
            child: const Text('Today'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'cal-fab',
        tooltip: 'New event',
        onPressed: () => push(context, EventEditorScreen(day: _selected)),
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: SegmentedButton<CalView>(
              segments: const [
                ButtonSegment(value: CalView.month, label: Text('Month')),
                ButtonSegment(value: CalView.week, label: Text('Week')),
                ButtonSegment(value: CalView.day, label: Text('Day')),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Row(
              children: [
                IconButton(tooltip: 'Previous', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Text(_title, textAlign: TextAlign.center, style: context.text.titleMedium),
                ),
                IconButton(tooltip: 'Next', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ),
          const _Legend(),
          Expanded(
            child: switch (_view) {
              CalView.month => _MonthView(
                month: _month,
                selected: _selected,
                onSelect: (d) => setState(() => _selected = d),
                onOpenDay: (d) => setState(() {
                  _selected = d;
                  _view = CalView.day;
                }),
              ),
              CalView.week => _WeekView(
                day: _selected,
                onOpenDay: (d) => setState(() {
                  _selected = d;
                  _view = CalView.day;
                }),
              ),
              CalView.day => _DayView(day: _selected),
            },
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.sm),
    child: Wrap(
      spacing: Gap.md,
      runSpacing: 4,
      children: [
        for (final m in kCalendarModules)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Dot(m.color),
              const SizedBox(width: 4),
              Text(m == AppModule.calendar ? 'Events' : m.label, style: context.text.bodySmall),
            ],
          ),
      ],
    ),
  );
}

class _MonthView extends ConsumerWidget {
  const _MonthView({required this.month, required this.selected, required this.onSelect, required this.onOpenDay});
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = monthGridRange(month);
    final async = ref.watch(calendarItemsProvider(range));
    final items = async.value ?? const <CalItem>[];
    final today = D.today();
    final dayItems = itemsOn(items, selected);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Column(
              children: [
                Row(
                  children: [
                    for (var k = 1; k <= 7; k++)
                      Expanded(
                        child: Center(
                          child: Text(D.weekdayName(k).substring(0, 2), style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var w = 0; w < 6; w++)
                  Row(
                    children: [
                      for (var k = 0; k < 7; k++)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final d = D.addDays(range.$1, w * 7 + k);
                              final inMonth = d.month == month.month;
                              final sel = D.sameDay(d, selected);
                              final isToday = D.sameDay(d, today);
                              final mods = itemsOn(items, d).map((i) => i.module).toSet();
                              return InkWell(
                                borderRadius: Radii.field,
                                onTap: () => onSelect(d),
                                onDoubleTap: () => onOpenDay(d),
                                child: Container(
                                  height: 48,
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: sel ? context.colors.primary : (isToday ? context.colors.primary.withValues(alpha: 0.12) : null),
                                    borderRadius: Radii.field,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${d.day}',
                                        style: context.text.labelLarge!.copyWith(
                                          color: sel ? context.colors.onPrimary : (inMonth ? null : context.colors.onSurfaceVariant.withValues(alpha: 0.5)),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      SizedBox(
                                        height: 5,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            for (final m in kCalendarModules.where(mods.contains))
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                                child: Dot(sel ? context.colors.onPrimary : m.color, size: 5),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(D.relativeDay(selected), action: 'Day view', onAction: () => onOpenDay(selected)),
        ),
        if (async.isLoading && async.value == null)
          const SliverToBoxAdapter(child: LoadingView(compact: true))
        else if (dayItems.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.event_available_outlined,
              color: AppModule.calendar.color,
              title: 'Nothing planned',
              compact: true,
              actionLabel: 'Add event',
              onAction: () => push(context, EventEditorScreen(day: selected)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, 96),
            sliver: SliverList.separated(
              itemCount: dayItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
              itemBuilder: (_, i) => CalItemTile(item: dayItems[i]),
            ),
          ),
      ],
    );
  }
}

class _WeekView extends ConsumerWidget {
  const _WeekView({required this.day, required this.onOpenDay});
  final DateTime day;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = weekRange(day);
    return AsyncBody<List<CalItem>>(
      value: ref.watch(calendarItemsProvider(range)),
      builder: (items) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, 96),
        itemCount: 7,
        itemBuilder: (context, k) {
          final d = D.addDays(range.$1, k);
          final list = itemsOn(items, d);
          final isToday = D.sameDay(d, DateTime.now());
          return Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => onOpenDay(d),
                  borderRadius: Radii.field,
                  child: SizedBox(
                    width: 52,
                    child: Column(
                      children: [
                        Text(
                          D.weekdayShort(d),
                          style: context.text.labelSmall!.copyWith(color: isToday ? context.colors.primary : context.colors.onSurfaceVariant),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? context.colors.primary : null),
                          child: Text('${d.day}', style: context.text.titleMedium!.copyWith(color: isToday ? context.colors.onPrimary : null)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: Gap.md),
                          child: Text('Free', style: context.text.bodySmall),
                        )
                      : Column(
                          children: [
                            for (final i in list)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: CalItemTile(item: i, dense: true),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.day});
  final DateTime day;

  static const _hour = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<CalItem>>(
      value: ref.watch(calendarItemsProvider(dayRange(day))),
      builder: (items) {
        final allDay = items.where((i) => i.allDay).toList();
        final timed = items.where((i) => !i.allDay).toList();
        final s = D.dateOnly(day);
        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.page, 96),
          children: [
            if (allDay.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: Gap.sm, bottom: Gap.sm),
                child: Text('All day', style: context.text.labelMedium),
              ),
              for (final i in allDay)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: Gap.sm),
                  child: CalItemTile(item: i, dense: true),
                ),
              const SizedBox(height: Gap.sm),
            ],
            if (items.isEmpty)
              EmptyState(
                icon: Icons.event_available_outlined,
                title: 'Nothing planned',
                compact: true,
                actionLabel: 'Add event',
                onAction: () => push(context, EventEditorScreen(day: day)),
              ),
            SizedBox(
              height: _hour * 24,
              child: LayoutBuilder(
                builder: (context, c) {
                  // Simple column layout: overlapping items share width.
                  final placed = <(CalItem, int, int)>[];
                  final columnsEnd = <DateTime>[];
                  for (final i in timed) {
                    final st = i.start.isBefore(s) ? s : i.start;
                    var col = columnsEnd.indexWhere((e) => !e.isAfter(st));
                    final end = (i.end ?? i.start.add(const Duration(minutes: 30)));
                    final effEnd = end.difference(st).inMinutes < 30 ? st.add(const Duration(minutes: 30)) : end;
                    if (col == -1) {
                      columnsEnd.add(effEnd);
                      col = columnsEnd.length - 1;
                    } else {
                      columnsEnd[col] = effEnd;
                    }
                    placed.add((i, col, 0));
                  }
                  final cols = columnsEnd.isEmpty ? 1 : columnsEnd.length;
                  final gridW = c.maxWidth - 48;
                  return Stack(
                    children: [
                      for (var h = 0; h < 24; h++)
                        Positioned(
                          top: h * _hour,
                          left: 0,
                          right: 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 44,
                                child: Text(
                                  D.minutesOfDayLabel(h * 60).replaceAll(':00', ''),
                                  style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant),
                                ),
                              ),
                              Expanded(child: Divider(color: context.colors.outlineVariant.withValues(alpha: 0.5))),
                            ],
                          ),
                        ),
                      for (final (i, col, _) in placed)
                        Builder(
                          builder: (context) {
                            final st = i.start.isBefore(s) ? s : i.start;
                            final end = i.end ?? i.start.add(const Duration(minutes: 30));
                            final top = st.difference(s).inMinutes / 60 * _hour;
                            final mins = end.difference(st).inMinutes.clamp(30, 24 * 60 - st.difference(s).inMinutes);
                            final w = gridW / cols;
                            return Positioned(
                              top: top + 6,
                              left: 48 + col * w,
                              width: w - 4,
                              height: (mins / 60 * _hour - 2).clamp(26, _hour * 24).toDouble(),
                              child: _Block(item: i),
                            );
                          },
                        ),
                      if (D.sameDay(day, now))
                        Positioned(
                          top: now.difference(s).inMinutes / 60 * _hour + 6,
                          left: 44,
                          right: 0,
                          child: Row(
                            children: [
                              const Dot(Palette.danger, size: 8),
                              Expanded(child: Container(height: 1.5, color: Palette.danger)),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Block extends ConsumerWidget {
  const _Block({required this.item});
  final CalItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: item.color.withValues(alpha: context.isDark ? 0.3 : 0.16),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => openItem(ref, item.module, item.id, kind: item.kind),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: item.color, width: 3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
        ),
      ),
    );
  }
}

/// Row for a calendar item; tapping opens it in its own module.
class CalItemTile extends ConsumerWidget {
  const CalItemTile({super.key, required this.item, this.dense = false});
  final CalItem item;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = item;
    return AppCard(
      padding: EdgeInsets.symmetric(horizontal: Gap.md, vertical: dense ? Gap.sm : Gap.md),
      onTap: () => openItem(ref, i.module, i.id, kind: i.kind),
      child: Row(
        children: [
          Container(
            width: 4,
            height: dense ? 30 : 38,
            decoration: BoxDecoration(color: i.color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: Gap.md),
          Icon(i.module.icon, size: 18, color: i.module.color),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: i.done && i.module == AppModule.todo ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (i.subtitle.isNotEmpty)
                  Text(
                    i.allDay && i.module == AppModule.calendar ? 'All day' : i.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
              ],
            ),
          ),
          if (!i.allDay && !dense) Text(D.time(i.start), style: context.text.labelMedium),
        ],
      ),
    );
  }
}
