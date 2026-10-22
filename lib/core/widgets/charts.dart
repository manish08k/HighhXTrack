import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import 'cards.dart';

typedef ValueFormat = String Function(double v);

String _defaultFormat(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Card with title/subtitle wrapping a chart.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, this.subtitle, required this.child, this.trailing, this.legend});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final List<(String, Color)>? legend;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall),
                    if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (legend != null && legend!.length > 1) ...[
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.md,
              children: [
                for (final (l, c) in legend!)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Dot(c, size: 8),
                      const SizedBox(width: 4),
                      Text(l, style: context.text.bodySmall),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: Gap.lg),
          child,
        ],
      ),
    );
  }
}

/// Single-series line chart over time with touch tooltip.
class TimeLineChart extends StatelessWidget {
  const TimeLineChart({super.key, required this.points, this.color, this.height = 180, this.format = _defaultFormat, this.unit = '', this.area = true});
  final List<(DateTime, double)> points;
  final Color? color;
  final double height;
  final ValueFormat format;
  final String unit;
  final bool area;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text('No data yet', style: context.text.bodySmall)),
      );
    }
    final t0 = points.first.$1;
    double x(DateTime d) => d.difference(t0).inHours / 24;
    final spots = [for (final p in points) FlSpot(x(p.$1), p.$2)];
    var minY = points.map((p) => p.$2).reduce(math.min);
    var maxY = points.map((p) => p.$2).reduce(math.max);
    final pad = (maxY - minY).abs() < 0.001 ? (maxY.abs() * 0.1 + 1) : (maxY - minY) * 0.15;
    minY = minY - pad;
    maxY = maxY + pad;
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;
    final grid = context.colors.outlineVariant.withValues(alpha: 0.5);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 3,
            getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: (maxY - minY) / 3,
                getTitlesWidget: (v, m) => v == m.max || v == m.min
                    ? const SizedBox.shrink()
                    : Text(format(v), style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: math.max(1, maxX / 3),
                getTitlesWidget: (v, m) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    D.dayMonth(t0.add(Duration(hours: (v * 24).round()))),
                    style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => context.colors.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${format(s.y)}$unit\n${D.dayMonthYear(t0.add(Duration(hours: (s.x * 24).round())))}',
                    context.text.labelMedium!.copyWith(color: context.colors.onInverseSurface),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: c,
              barWidth: 2,
              isCurved: true,
              preventCurveOverShooting: true,
              dotData: FlDotData(
                show: spots.length <= 20,
                getDotPainter: (s, a, b, i) => FlDotCirclePainter(radius: 3.5, color: c, strokeWidth: 2, strokeColor: context.colors.surfaceContainer),
              ),
              belowBarData: BarAreaData(
                show: area,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0)]),
              ),
            ),
          ],
        ),
        duration: Durations2.normal,
      ),
    );
  }
}

/// Vertical bars with labels; optional second series drawn side-by-side.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.second,
    this.color,
    this.secondColor,
    this.height = 180,
    this.format = _defaultFormat,
    this.highlightLast = false,
    this.target,
    this.seriesNames,
  });
  final List<double> values;
  final List<String> labels;
  final List<double>? second;
  final Color? color;
  final Color? secondColor;
  final double height;
  final ValueFormat format;
  final bool highlightLast;
  final double? target;
  final (String, String)? seriesNames;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    final c2 = secondColor ?? Palette.danger;
    final all = [...values, ...?second, ?target];
    final maxV = all.isEmpty ? 1.0 : math.max(1.0, all.reduce(math.max) * 1.15);
    final n = values.length;
    final barW = second == null ? (n > 20 ? 6.0 : (n > 10 ? 10.0 : 16.0)) : (n > 8 ? 6.0 : 10.0);
    final showEvery = n > 14 ? (n / 7).ceil() : 1;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxV,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxV / 3,
            getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          extraLinesData: target == null
              ? null
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(y: target!, color: context.colors.onSurfaceVariant.withValues(alpha: 0.6), strokeWidth: 1, dashArray: [4, 4]),
                  ],
                ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: maxV / 3,
                getTitlesWidget: (v, m) => v == m.max || v == 0
                    ? const SizedBox.shrink()
                    : Text(format(v), style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length || i % showEvery != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i], style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.colors.inverseSurface,
              getTooltipItem: (g, gi, rod, ri) {
                final name = seriesNames == null ? '' : '${ri == 0 ? seriesNames!.$1 : seriesNames!.$2}: ';
                return BarTooltipItem('${labels[g.x]}\n$name${format(rod.toY)}', context.text.labelMedium!.copyWith(color: context.colors.onInverseSurface));
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: barW,
                    color: highlightLast && i != n - 1 ? c.withValues(alpha: 0.45) : c,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  if (second != null)
                    BarChartRodData(
                      toY: second![i],
                      width: barW,
                      color: c2,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                ],
              ),
          ],
        ),
        duration: Durations2.normal,
      ),
    );
  }
}

/// Ranked horizontal bars (category breakdowns). Easier to compare than a pie.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.items, this.format = _defaultFormat, this.max, this.onTap});
  final List<(String, double, Color, IconData?)> items;
  final ValueFormat format;
  final double? max;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Center(child: Text('No data yet', style: context.text.bodySmall)),
      );
    }
    final total = items.fold<double>(0, (a, b) => a + b.$2);
    final top = max ?? items.map((e) => e.$2).reduce(math.max);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            borderRadius: Radii.field,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              child: Row(
                children: [
                  if (items[i].$4 != null) ...[IconBadge(items[i].$4!, items[i].$3, size: 32), const SizedBox(width: Gap.md)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                items[i].$1,
                                style: context.text.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(format(items[i].$2), style: context.text.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
                            SizedBox(
                              width: 44,
                              child: Text(
                                total == 0 ? '' : '${(items[i].$2 / total * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: context.text.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        AppProgressBar(value: top == 0 ? 0 : items[i].$2 / top, color: items[i].$3, height: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// GitHub-style contribution heatmap: columns are weeks, rows Mon–Sun.
class HeatmapCalendar extends StatelessWidget {
  const HeatmapCalendar({super.key, required this.values, this.weeks = 18, this.color, this.maxValue, this.cell = 14, this.onTapDay, this.label});
  final Map<int, num> values;
  final int weeks;
  final Color? color;
  final num? maxValue;
  final double cell;
  final void Function(DateTime day)? onTapDay;
  final String Function(DateTime day, num value)? label;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    final today = D.today();
    final start = D.addDays(D.startOfWeek(today), -7 * (weeks - 1));
    final maxV = maxValue ?? (values.isEmpty ? 1 : values.values.reduce((a, b) => a > b ? a : b));
    final empty = context.colors.surfaceContainerHighest;
    const gap = 3.0;
    return LayoutBuilder(
      builder: (context, cons) {
        final fitWeeks = ((cons.maxWidth - 18) / (cell + gap)).floor().clamp(4, weeks);
        final from = D.addDays(start, 7 * (weeks - fitWeeks));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                for (var r = 0; r < 7; r++)
                  SizedBox(
                    height: cell + gap,
                    width: 16,
                    child: r % 2 == 0
                        ? Text(D.weekdayLetter(r + 1), style: context.text.labelSmall!.copyWith(fontSize: 9, color: context.colors.onSurfaceVariant))
                        : null,
                  ),
              ],
            ),
            for (var w = 0; w < fitWeeks; w++)
              Padding(
                padding: const EdgeInsets.only(right: gap),
                child: Column(
                  children: [
                    for (var r = 0; r < 7; r++)
                      Builder(
                        builder: (context) {
                          final day = D.addDays(from, w * 7 + r);
                          if (day.isAfter(today)) return SizedBox(width: cell, height: cell + gap);
                          final v = values[D.dayKey(day)] ?? 0;
                          final t = maxV == 0 ? 0.0 : (v / maxV).clamp(0, 1).toDouble();
                          final fill = v == 0 ? empty : Color.lerp(c.withValues(alpha: 0.3), c, t)!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: Tooltip(
                              message: label?.call(day, v) ?? '${D.dayMonth(day)}: ${_defaultFormat(v.toDouble())}',
                              child: GestureDetector(
                                onTap: onTapDay == null ? null : () => onTapDay!(day),
                                child: Container(
                                  width: cell,
                                  height: cell,
                                  decoration: BoxDecoration(
                                    color: fill,
                                    borderRadius: BorderRadius.circular(3),
                                    border: D.sameDay(day, today) ? Border.all(color: context.colors.onSurface.withValues(alpha: 0.5), width: 1) : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
