import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class SwipeAction {
  const SwipeAction({required this.icon, required this.label, required this.color, required this.onTrigger, this.dismiss = false});
  final IconData icon;
  final String label;
  final Color color;

  /// Called when the swipe passes the threshold.
  final Future<void> Function() onTrigger;

  /// Whether the row animates out (e.g. delete) or snaps back (e.g. edit).
  final bool dismiss;
}

/// Row with swipe actions: [start] = swipe right, [end] = swipe left.
///
/// Once dismissed the row renders as empty space until the parent list
/// refreshes, so async data reloads can't rebuild a dismissed Dismissible.
class SwipeTile extends StatefulWidget {
  const SwipeTile({required super.key, required this.child, this.start, this.end, this.radius = Radii.lg});
  final Widget child;
  final SwipeAction? start;
  final SwipeAction? end;
  final double radius;

  @override
  State<SwipeTile> createState() => _SwipeTileState();
}

class _SwipeTileState extends State<SwipeTile> {
  bool _dismissed = false;

  Widget get child => widget.child;
  SwipeAction? get start => widget.start;
  SwipeAction? get end => widget.end;
  double get radius => widget.radius;

  Widget _bg(BuildContext context, SwipeAction a, Alignment align) => Container(
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
    decoration: BoxDecoration(color: a.color, borderRadius: BorderRadius.circular(radius)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(a.icon, color: Colors.white),
        const SizedBox(width: Gap.sm),
        Text(a.label, style: context.text.labelLarge!.copyWith(color: Colors.white)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (start == null && end == null) return child;
    return Dismissible(
      key: widget.key!,
      direction: start != null && end != null ? DismissDirection.horizontal : (start != null ? DismissDirection.startToEnd : DismissDirection.endToStart),
      background: start == null ? const SizedBox.shrink() : _bg(context, start!, Alignment.centerLeft),
      secondaryBackground: end == null ? null : _bg(context, end!, Alignment.centerRight),
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      confirmDismiss: (dir) async {
        final a = dir == DismissDirection.startToEnd ? start : end;
        if (a == null) return false;
        HapticFeedback.mediumImpact();
        if (a.dismiss) return true;
        await a.onTrigger();
        return false;
      },
      onDismissed: (dir) {
        setState(() => _dismissed = true);
        final a = dir == DismissDirection.startToEnd ? start : end;
        a?.onTrigger();
      },
      child: child,
    );
  }
}
