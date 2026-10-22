import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction, this.color, this.compact = false});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Gap.xxxl, vertical: compact ? Gap.xl : Gap.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 26 : 34, color: c),
            ),
            const SizedBox(height: Gap.lg),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
            if (message != null) ...[
              const SizedBox(height: Gap.xs + 2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Gap.lg),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(compact ? Gap.lg : Gap.xxxl),
      child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline_rounded,
    color: Palette.danger,
    title: 'Something went wrong',
    message: friendlyError(error),
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
    compact: compact,
  );
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('DatabaseException')) return 'Could not read your data. Please try again.';
  return s.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
}

/// Renders an [AsyncValue] with consistent loading/error UI. Previous data
/// stays visible while refreshing, so lists don't flicker.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry, this.compact = false, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool compact;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => loading ?? LoadingView(compact: compact),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry, compact: compact),
    );
  }
}

/// Sliver variant of [AsyncBody].
class AsyncSliver<T> extends StatelessWidget {
  const AsyncSliver({super.key, required this.value, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorView(error: e, onRetry: onRetry),
      ),
    );
  }
}
