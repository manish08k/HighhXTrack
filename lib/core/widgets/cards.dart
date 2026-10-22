import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Base surface used everywhere.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.color,
    this.borderColor,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Material(
      color: color ?? c.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: borderColor ?? c.outlineVariant.withValues(alpha: context.isDark ? 0.6 : 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(Gap.page, Gap.xl, Gap.sm, Gap.sm)});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w700),
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Rounded tinted icon square used for modules and categories.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, this.color, {super.key, this.size = 40, this.iconSize});
  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: iconSize ?? size * 0.52),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon, this.dense = false});
  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: context.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 11 : 13, color: c), const SizedBox(width: 3)],
          Text(
            label,
            style: context.text.labelSmall!.copyWith(color: c, fontSize: dense ? 10.5 : 11.5),
          ),
        ],
      ),
    );
  }
}

class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: Durations2.slow,
        curve: Curves.easeOutCubic,
        builder: (context, a, _) => LinearProgressIndicator(
          value: a,
          minHeight: height,
          color: color ?? context.colors.primary,
          backgroundColor: context.colors.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// Animated circular progress with centered child.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 56, this.stroke = 6, this.color, this.child});
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: Durations2.slow,
        curve: Curves.easeOutCubic,
        builder: (context, a, child) => CustomPaint(
          painter: _RingPainter(a, stroke, color ?? context.colors.primary, context.colors.surfaceContainerHighest),
          child: Center(child: child),
        ),
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.color, this.track);
  final double v;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = track);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Label + big value + optional caption.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption, this.color, this.icon, this.onTap});
  final String label;
  final String value;
  final String? caption;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gap.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: color ?? context.colors.onSurfaceVariant), const SizedBox(width: 6)],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: context.text.titleLarge!.copyWith(color: color)),
          ),
          if (caption != null) ...[const SizedBox(height: 2), Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall)],
        ],
      ),
    );
  }
}

/// Two-up responsive grid of [StatTile]s.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: Gap.page)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 600 ? 4 : 2;
          final w = (c.maxWidth - Gap.md * (cols - 1)) / cols;
          return Wrap(
            spacing: Gap.md,
            runSpacing: Gap.md,
            children: [for (final ch in children) SizedBox(width: w, child: ch)],
          );
        },
      ),
    );
  }
}

/// Small colored dot.
class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Masks sensitive values (money/doc numbers) when privacy mode is on.
class Sensitive extends StatelessWidget {
  const Sensitive({super.key, required this.hidden, required this.child, this.placeholder = '•••••'});
  final bool hidden;
  final Widget child;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    if (!hidden) return child;
    final style = child is Text ? (child as Text).style : null;
    return Text(placeholder, style: style);
  }
}
