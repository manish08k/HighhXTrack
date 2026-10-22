import 'package:sqflite/sqflite.dart';

import '../models/gym.dart';

/// Default content inserted on first launch.
abstract final class Seed {
  static const exercises = <Muscle, List<String>>{
    Muscle.chest: ['Bench Press', 'Incline Bench Press', 'Dumbbell Press', 'Incline Dumbbell Press', 'Cable Fly', 'Pec Deck', 'Push-up', 'Chest Dip'],
    Muscle.back: ['Deadlift', 'Pull-up', 'Lat Pulldown', 'Barbell Row', 'Seated Cable Row', 'Single-arm Dumbbell Row', 'T-Bar Row', 'Face Pull'],
    Muscle.shoulders: ['Overhead Press', 'Dumbbell Shoulder Press', 'Lateral Raise', 'Front Raise', 'Rear Delt Fly', 'Arnold Press', 'Upright Row'],
    Muscle.biceps: ['Barbell Curl', 'Dumbbell Curl', 'Hammer Curl', 'Preacher Curl', 'Incline Dumbbell Curl', 'Cable Curl'],
    Muscle.triceps: ['Tricep Pushdown', 'Overhead Tricep Extension', 'Skull Crusher', 'Close-grip Bench Press', 'Tricep Dip', 'Rope Pushdown'],
    Muscle.legs: [
      'Back Squat',
      'Front Squat',
      'Leg Press',
      'Romanian Deadlift',
      'Walking Lunge',
      'Leg Extension',
      'Leg Curl',
      'Bulgarian Split Squat',
      'Hip Thrust',
    ],
    Muscle.abs: ['Crunch', 'Hanging Leg Raise', 'Plank', 'Cable Crunch', 'Russian Twist', 'Ab Wheel Rollout'],
    Muscle.forearms: ['Wrist Curl', 'Reverse Wrist Curl', 'Farmer\'s Walk', 'Reverse Curl', 'Dead Hang'],
    Muscle.calves: ['Standing Calf Raise', 'Seated Calf Raise', 'Leg Press Calf Raise', 'Single-leg Calf Raise'],
  };

  /// (name, kind 0=expense 1=income, iconIndex, color)
  static const moneyCategories = <(String, int, int, int)>[
    ('Food', 0, 0, 0xFFF2711C),
    ('Transport', 0, 1, 0xFF2D8CDB),
    ('Shopping', 0, 2, 0xFFD6409F),
    ('Bills', 0, 3, 0xFFE5484D),
    ('Entertainment', 0, 4, 0xFF8E4EC6),
    ('Health', 0, 5, 0xFF1FA971),
    ('Education', 0, 6, 0xFF14A3B8),
    ('Gym', 0, 7, 0xFFE8A317),
    ('Other', 0, 8, 0xFF607D8B),
    ('Salary', 1, 9, 0xFF1FA971),
    ('Freelance', 1, 10, 0xFF4F5BD5),
    ('Gifts', 1, 11, 0xFFD6409F),
    ('Investments', 1, 12, 0xFF14A3B8),
    ('Other income', 1, 8, 0xFF607D8B),
  ];

  static Future<void> run(DatabaseExecutor db) async {
    final b = db.batch();
    for (final entry in exercises.entries) {
      for (final name in entry.value) {
        b.insert('exercises', {'name': name, 'muscle': entry.key.name, 'rest_seconds': entry.key == Muscle.abs || entry.key == Muscle.calves ? 60 : 90});
      }
    }
    var pos = 0;
    for (final c in moneyCategories) {
      b.insert('money_categories', {'name': c.$1, 'kind': c.$2, 'icon': c.$3, 'color': c.$4, 'is_default': 1, 'position': pos++});
    }
    b.insert('todo_categories', {'name': 'Personal', 'color': 0xFF4F5BD5, 'position': 0});
    b.insert('todo_categories', {'name': 'Work', 'color': 0xFF14A3B8, 'position': 1});
    b.insert('todo_categories', {'name': 'Errands', 'color': 0xFFF2711C, 'position': 2});
    b.insert('note_folders', {'name': 'Personal', 'position': 0});
    await b.commit(noResult: true);
  }
}
