import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/format.dart';
import '../data/db/app_database.dart';
import '../data/repositories/base.dart';
import '../data/repositories/document_repo.dart';
import '../data/repositories/event_repo.dart';
import '../data/repositories/gym_repo.dart';
import '../data/repositories/habit_repo.dart';
import '../data/repositories/money_repo.dart';
import '../data/repositories/note_repo.dart';
import '../data/repositories/reminder_repo.dart';
import '../data/repositories/search_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../data/repositories/study_repo.dart';
import '../data/repositories/todo_repo.dart';

/// Opened in main() and injected via ProviderScope overrides.
final databaseProvider = Provider<AppDatabase>((ref) => throw StateError('databaseProvider must be overridden in main()'));

/// Settings loaded before the first frame (avoids a theme flash).
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

/// Revision counter per data topic. Repositories bump a topic after every
/// write; read providers watch only the topics they depend on.
class ChangeTracker extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void bump(String topic) => state = {...state, topic: (state[topic] ?? 0) + 1};

  void bumpAll() => state = {for (final t in Chg.all) t: (state[t] ?? 0) + 1};
}

final changesProvider = NotifierProvider<ChangeTracker, Map<String, int>>(ChangeTracker.new);

extension RefTopics on Ref {
  /// Rebuild this provider whenever any of [topics] changes.
  void watchTopics(List<String> topics) {
    for (final t in topics) {
      watch(changesProvider.select((m) => m[t] ?? 0));
    }
  }
}

ChangeSink _sink(Ref ref) =>
    (topic) => ref.read(changesProvider.notifier).bump(topic);

final todoRepoProvider = Provider((ref) => TodoRepo(ref.watch(databaseProvider).db, _sink(ref)));
final gymRepoProvider = Provider((ref) => GymRepo(ref.watch(databaseProvider).db, _sink(ref)));
final moneyRepoProvider = Provider((ref) => MoneyRepo(ref.watch(databaseProvider).db, _sink(ref)));
final reminderRepoProvider = Provider((ref) => ReminderRepo(ref.watch(databaseProvider).db, _sink(ref)));
final habitRepoProvider = Provider((ref) => HabitRepo(ref.watch(databaseProvider).db, _sink(ref)));
final eventRepoProvider = Provider((ref) => EventRepo(ref.watch(databaseProvider).db, _sink(ref)));
final documentRepoProvider = Provider((ref) => DocumentRepo(ref.watch(databaseProvider).db, _sink(ref)));
final noteRepoProvider = Provider((ref) => NoteRepo(ref.watch(databaseProvider).db, _sink(ref)));
final studyRepoProvider = Provider((ref) => StudyRepo(ref.watch(databaseProvider).db, _sink(ref)));
final settingsRepoProvider = Provider((ref) => SettingsRepo(ref.watch(databaseProvider).db, _sink(ref)));
final searchRepoProvider = Provider((ref) => SearchRepo(ref.watch(databaseProvider).db, _sink(ref)));

final attachmentStoreProvider = Provider((ref) => AttachmentStore(ref.watch(documentRepoProvider)));

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = ref.read(initialSettingsProvider);
    Money.symbol = s.currency;
    return s;
  }

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    final next = change(state);
    Money.symbol = next.currency;
    state = next;
    await ref.read(settingsRepoProvider).save(next);
  }

  /// Re-reads settings from the database (after a restore).
  Future<void> reload() async {
    final s = await ref.read(settingsRepoProvider).load();
    Money.symbol = s.currency;
    state = s;
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Selected bottom-navigation tab.
class NavTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void select(int i) => state = i;
}

final tabProvider = NotifierProvider<NavTabNotifier, int>(NavTabNotifier.new);
