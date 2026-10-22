import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';

/// Numeric keypad with dot indicators for PIN entry.
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.length, required this.maxLength, required this.onDigit, required this.onBackspace, this.extra, this.error = false});
  final int length;
  final int maxLength;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  /// Bottom-left key (e.g. biometrics).
  final Widget? extra;
  final bool error;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap, {String? label}) => Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 76,
        height: 76,
        child: onTap == null
            ? Center(child: child)
            : InkResponse(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                radius: 40,
                child: Center(child: child),
              ),
      ),
    );
    final digitStyle = context.text.headlineMedium!.copyWith(fontWeight: FontWeight.w500);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < maxLength; i++)
              AnimatedContainer(
                duration: Durations2.fast,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: error ? Palette.danger : (i < length ? context.colors.primary : Colors.transparent),
                  border: Border.all(color: error ? Palette.danger : context.colors.outline, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.xxl),
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) key(Text('$d', style: digitStyle), () => onDigit(d), label: '$d')],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            key(extra ?? const SizedBox.shrink(), null),
            key(Text('0', style: digitStyle), () => onDigit(0), label: '0'),
            key(const Icon(Icons.backspace_outlined), onBackspace, label: 'Delete'),
          ],
        ),
      ],
    );
  }
}
