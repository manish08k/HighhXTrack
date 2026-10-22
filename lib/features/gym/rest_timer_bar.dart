import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../state/timers.dart';

const kRestPresets = [30, 60, 90, 120, 180];

String restLabel(int s) => s < 60 ? '${s}s' : (s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}');

/// Live rest countdown shown in the workout session and as a global banner.
/// Time comes from an absolute end timestamp, so it survives navigation.
class RestTimerBar extends ConsumerWidget {
  const RestTimerBar({super.key, this.compact = false, this.onTap});
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(restTimerProvider);
    if (!s.active) return const SizedBox.shrink();
    ref.watch(clockProvider);
    final ctrl = ref.read(restTimerProvider.notifier);
    final left = s.remaining();
    final done = s.finished();
    final c = done ? Palette.success : AppModule.gym.color;
    return Material(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
          child: Row(
            children: [
              ProgressRing(
                value: s.total == 0 ? 0 : (done ? 1 : left / s.total),
                size: 44,
                stroke: 4,
                color: c,
                child: Icon(done ? Icons.check_rounded : Icons.timer_outlined, size: 18, color: c),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      done ? 'Rest complete' : (s.paused ? 'Rest paused' : 'Resting'),
                      style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    Text(
                      done ? 'Go!' : D.clock(Duration(seconds: left)),
                      style: context.text.titleLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: done ? Palette.success : null),
                    ),
                  ],
                ),
              ),
              if (!done && !compact) TextButton(onPressed: () => ctrl.add(-15), child: const Text('−15')),
              if (!done) TextButton(onPressed: () => ctrl.add(15), child: const Text('+15')),
              if (!done)
                IconButton(
                  tooltip: s.paused ? 'Resume' : 'Pause',
                  onPressed: s.paused ? ctrl.resume : ctrl.pause,
                  icon: Icon(s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                ),
              IconButton(tooltip: done ? 'Dismiss' : 'Skip rest', onPressed: ctrl.stop, icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to start a rest timer with presets.
Future<void> showRestPicker(BuildContext context, WidgetRef ref, {int? suggested, String label = ''}) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rest timer', style: ctx.text.titleLarge),
            const SizedBox(height: Gap.lg),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final p in {...kRestPresets, ?suggested}.toList()..sort())
                  ActionChip(
                    label: Text(restLabel(p)),
                    avatar: p == suggested ? const Icon(Icons.star_rounded, size: 16) : null,
                    onPressed: () {
                      ref.read(restTimerProvider.notifier).start(p, label: label);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
