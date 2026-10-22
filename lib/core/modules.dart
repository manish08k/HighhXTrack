import 'package:flutter/material.dart';

/// The nine core modules. Used for colors, icons, links and navigation.
enum AppModule {
  todo('Todo', Icons.check_circle_outline_rounded, Color(0xFF4F5BD5)),
  gym('Gym', Icons.fitness_center_rounded, Color(0xFFF2711C)),
  money('Money', Icons.account_balance_wallet_outlined, Color(0xFF1FA971)),
  reminders('Reminders', Icons.notifications_none_rounded, Color(0xFFE8A317)),
  habits('Habits', Icons.local_fire_department_outlined, Color(0xFFD6409F)),
  calendar('Calendar', Icons.calendar_month_outlined, Color(0xFF2D8CDB)),
  documents('Documents', Icons.badge_outlined, Color(0xFF8E4EC6)),
  notes('Notes', Icons.sticky_note_2_outlined, Color(0xFFB7791F)),
  study('Study', Icons.menu_book_rounded, Color(0xFF14A3B8));

  const AppModule(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static AppModule? byName(String? name) {
    if (name == null) return null;
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}
