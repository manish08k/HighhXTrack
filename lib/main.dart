import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'data/db/app_database.dart';
import 'data/repositories/base.dart';
import 'data/repositories/document_repo.dart';
import 'data/repositories/money_repo.dart';
import 'data/repositories/settings_repo.dart';
import 'services/notification_planner.dart';
import 'services/notification_service.dart';
import 'services/security_service.dart';
import 'state/providers.dart';
import 'state/services.dart';
import 'state/timers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await bootstrap();
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(error: e));
  }
}

Future<void> bootstrap() async {
  await initializeDateFormatting();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Critical, fast-path initialization (all local).
  final results = await Future.wait([AppDatabase.open(), SharedPreferences.getInstance()]);
  final database = results[0] as AppDatabase;
  final prefs = results[1] as SharedPreferences;
  void noop(String _) {}
  final settings = await SettingsRepo(database.db, noop).load();
  final security = SecurityService();
  await security.load();
  await NotificationService.instance.init();

  // Housekeeping: record recurring transactions that came due.
  await MoneyRepo(database.db, noop).processDue();

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      prefsProvider.overrideWithValue(prefs),
      initialSettingsProvider.overrideWithValue(settings),
      securityProvider.overrideWithValue(security),
    ],
  );

  // Re-plan notifications whenever data changes (debounced inside).
  container.listen<Map<String, int>>(changesProvider, (_, _) => container.read(notificationSyncProvider).schedule());
  // Keep timers alive for the app's lifetime (they restore from prefs).
  container.read(restTimerProvider);
  container.read(studyTimerProvider);

  if (settings.secureScreen) await security.setSecureScreen(true);

  runApp(UncontrolledProviderScope(container: container, child: const HighhXTrackApp()));

  // Non-critical work after the first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await database.snapshot();
    await AttachmentStore(DocumentRepo(database.db, (t) => container.read(changesProvider.notifier).bump(t))).cleanupOrphans();
    container.read(changesProvider.notifier).bump(Chg.settings);
  });
}

/// Shown only if the database can't be opened, so the user sees a clear
/// message instead of a blank screen.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Palette.danger),
                const SizedBox(height: Gap.lg),
                const Text('HighhXTrack could not start', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: Gap.sm),
                Text('Your data has not been changed. Please restart the app.\n\n$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
