import 'package:flutter/material.dart';

/// Spacing scale (4pt grid).
abstract final class Gap {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal page gutter.
  static const double page = 20;
}

abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius field = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
}

abstract final class Durations2 {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}

/// Minimum accessible touch target.
const double kTouchTarget = 48;

/// Brand + semantic palette shared across modules.
abstract final class Palette {
  static const brand = Color(0xFF4F5BD5);

  static const success = Color(0xFF1FA971);
  static const warning = Color(0xFFE8A317);
  static const danger = Color(0xFFE5484D);
  static const info = Color(0xFF2D8CDB);

  // Neutral surfaces
  static const lightBg = Color(0xFFF5F6F8);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCardAlt = Color(0xFFEEF0F3);
  static const lightBorder = Color(0xFFE3E6EA);

  static const darkBg = Color(0xFF0D0E11);
  static const darkCard = Color(0xFF17181C);
  static const darkCardAlt = Color(0xFF202227);
  static const darkBorder = Color(0xFF2A2D33);

  /// Picker palette for user-defined colors (habits, subjects, categories…).
  static const swatches = <Color>[
    Color(0xFF4F5BD5),
    Color(0xFF2D8CDB),
    Color(0xFF14A3B8),
    Color(0xFF1FA971),
    Color(0xFF7CB342),
    Color(0xFFE8A317),
    Color(0xFFF2711C),
    Color(0xFFE5484D),
    Color(0xFFD6409F),
    Color(0xFF8E4EC6),
    Color(0xFF6E56CF),
    Color(0xFF607D8B),
  ];
}

/// Priority shared by todos and reminders.
enum Priority {
  low('Low', Color(0xFF8A94A6)),
  medium('Medium', Palette.warning),
  high('High', Palette.danger);

  const Priority(this.label, this.color);
  final String label;
  final Color color;

  static Priority fromIndex(int? i) => Priority.values[(i ?? 1).clamp(0, Priority.values.length - 1)];
}
