import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: Palette.brand, brightness: b);
    final scheme = base.copyWith(
      primary: dark ? const Color(0xFF8C95F2) : Palette.brand,
      onPrimary: dark ? const Color(0xFF10132E) : Colors.white,
      surface: dark ? Palette.darkBg : Palette.lightBg,
      surfaceContainerLowest: dark ? Palette.darkBg : Colors.white,
      surfaceContainerLow: dark ? Palette.darkCard : Palette.lightCard,
      surfaceContainer: dark ? Palette.darkCard : Palette.lightCard,
      surfaceContainerHigh: dark ? Palette.darkCardAlt : Palette.lightCardAlt,
      surfaceContainerHighest: dark ? const Color(0xFF292B31) : const Color(0xFFE6E8EC),
      outlineVariant: dark ? Palette.darkBorder : Palette.lightBorder,
      onSurface: dark ? const Color(0xFFECEDEF) : const Color(0xFF14161A),
      onSurfaceVariant: dark ? const Color(0xFF9A9FA8) : const Color(0xFF646B76),
      error: Palette.danger,
    );

    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder(), TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder()},
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.6 : 0.8)),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        height: 68,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall!.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, kTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, kTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 14),
        border: const OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.field,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: Radii.field,
          borderSide: BorderSide(color: Palette.danger, width: 1.2),
        ),
        hintStyle: text.bodyLarge!.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
        labelStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.chip),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        labelStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
        showCheckmark: false,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        minVerticalPadding: Gap.md,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge!.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.xl))),
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFECEDEF) : const Color(0xFF1C1E23),
        contentTextStyle: text.bodyMedium!.copyWith(color: dark ? Colors.black : Colors.white),
        actionTextColor: dark ? Palette.brand : const Color(0xFFA9B0FF),
        shape: const RoundedRectangleBorder(borderRadius: Radii.field),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.14),
          selectedForegroundColor: scheme.primary,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.labelLarge,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 3),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.onSurfaceVariant, width: 1.6),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme s) {
    final base = Typography.material2021(platform: TargetPlatform.android).black.apply(bodyColor: s.onSurface, displayColor: s.onSurface);
    return base.copyWith(
      displaySmall: base.displaySmall!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
      headlineMedium: base.headlineMedium!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineSmall: base.headlineSmall!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: base.titleLarge!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: base.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall!.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge!.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall!.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.3),
      bodySmall: base.bodySmall!.copyWith(color: s.onSurfaceVariant),
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
