import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Small caption shown above form controls.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm, top: Gap.lg),
    child: Text(text, style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant)),
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.maxLines = 1,
    this.minLines,
    this.keyboard,
    this.autofocus = false,
    this.validator,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.textStyle,
    this.capitalization = TextCapitalization.sentences,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboard;
  final bool autofocus;
  final FormFieldValidator<String>? validator;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextStyle? textStyle;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboard,
      autofocus: autofocus,
      validator: validator,
      onChanged: onChanged,
      style: textStyle,
      textCapitalization: capitalization,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(hintText: hint, prefixIcon: prefix, suffixIcon: suffix),
    );
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FieldLabel(label!), field]);
  }
}

/// Decimal number input (amounts, weights).
final decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'));

/// Tappable row that shows a value and opens a picker (date, time, repeat…).
class PickerTile extends StatelessWidget {
  const PickerTile({super.key, required this.icon, required this.label, this.value, required this.onTap, this.onClear, this.color});
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    return Material(
      color: context.colors.surfaceContainerHigh,
      borderRadius: Radii.field,
      child: InkWell(
        borderRadius: Radii.field,
        onTap: () {
          // Don't let a text field regain focus (and the keyboard) after the picker closes.
          FocusManager.instance.primaryFocus?.unfocus();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.only(left: Gap.lg, right: Gap.xs),
            child: Row(
              children: [
                Icon(icon, size: 20, color: has ? (color ?? context.colors.primary) : context.colors.onSurfaceVariant),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    value ?? label,
                    style: context.text.bodyLarge!.copyWith(color: has ? context.colors.onSurface : context.colors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (has && onClear != null)
                  IconButton(tooltip: 'Clear', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18))
                else
                  const SizedBox(width: kTouchTarget),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling single-select chips.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.color,
    this.padding = EdgeInsets.zero,
    this.wrap = false,
  });
  final List<T> options;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final Color Function(T)? color;
  final EdgeInsetsGeometry padding;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final o in options)
        ChoiceChip(
          label: Text(label(o)),
          selected: o == selected,
          selectedColor: (color?.call(o) ?? context.colors.primary).withValues(alpha: 0.18),
          side: BorderSide(color: o == selected ? (color?.call(o) ?? context.colors.primary) : context.colors.outlineVariant),
          labelStyle: context.text.labelLarge!.copyWith(color: o == selected ? (color?.call(o) ?? context.colors.primary) : context.colors.onSurface),
          onSelected: (_) => onSelected(o),
        ),
    ];
    if (wrap) {
      return Padding(
        padding: padding,
        child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: chips),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: c,
            ),
        ],
      ),
    );
  }
}

/// Bottom-of-form primary action bar that sits above the keyboard.
class FormActionBar extends StatelessWidget {
  const FormActionBar({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : onPressed,
            child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
          ),
        ),
      ),
    );
  }
}

/// Numeric stepper used for sets/reps/targets.
class NumberStepper extends StatelessWidget {
  const NumberStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 999, this.step = 1, this.suffix = ''});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_rounded),
          tooltip: 'Decrease',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Text('$value$suffix', textAlign: TextAlign.center, style: context.text.titleMedium),
        ),
        IconButton.filledTonal(onPressed: value + step <= max ? () => onChanged(value + step) : null, icon: const Icon(Icons.add_rounded), tooltip: 'Increase'),
      ],
    );
  }
}
