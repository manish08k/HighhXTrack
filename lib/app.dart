import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/lock/lock_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/shell/nav.dart';
import 'services/notification_planner.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';
import 'state/services.dart';

class HighhXTrackApp extends ConsumerStatefulWidget {
  const HighhXTrackApp({super.key});
  @override
  ConsumerState<HighhXTrackApp> createState() => _HighhXTrackAppState();
}

class _HighhXTrackAppState extends ConsumerState<HighhXTrackApp> with WidgetsBindingObserver {
  StreamSubscription<String>? _taps;
  DateTime? _backgroundedAt;
  String? _pendingPayload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final n = NotificationService.instance;
    _taps = n.taps.stream.listen(_handlePayload);
    if (n.launchPayload != null) {
      _pendingPayload = n.launchPayload;
      n.launchPayload = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await n.requestPermissions();
      await ref.read(notificationSyncProvider).run();
      _flushPayload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    super.dispose();
  }

  void _handlePayload(String payload) {
    _pendingPayload = payload;
    _flushPayload();
  }

  /// Opens a tapped notification's target once the app is unlocked.
  void _flushPayload() {
    final p = _pendingPayload;
    if (p == null || ref.read(lockedProvider) || rootNavigatorKey.currentState == null) return;
    _pendingPayload = null;
    openPayload(ref, p);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final away = _backgroundedAt == null ? Duration.zero : DateTime.now().difference(_backgroundedAt!);
        _backgroundedAt = null;
        if (away > Duration(seconds: ref.read(settingsProvider).lockTimeoutSec)) {
          ref.read(lockedProvider.notifier).lock();
        }
        // Catch up on recurring transactions and day rollover, then re-plan.
        ref.read(moneyRepoProvider).processDue().then((_) {
          ref.read(changesProvider.notifier).bumpAll();
          return ref.read(notificationSyncProvider).run();
        });
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final locked = ref.watch(lockedProvider);
    ref.listen<bool>(lockedProvider, (_, isLocked) {
      if (!isLocked) WidgetsBinding.instance.addPostFrameCallback((_) => _flushPayload());
    });
    return MaterialApp(
      title: 'HighhXTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      navigatorKey: rootNavigatorKey,
      home: const HomeShell(),
      builder: (context, child) {
        // Respect user font scaling but cap it so layouts stay usable.
        final mq = MediaQuery.of(context);
        final scaled = MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.4)),
          child: child!,
        );
        return Stack(
          children: [
            scaled,
            if (locked) const Positioned.fill(child: _LockOverlay()),
          ],
        );
      },
    );
  }
}

class _LockOverlay extends StatelessWidget {
  const _LockOverlay();
  @override
  Widget build(BuildContext context) {
    // Own Navigator so dialogs/biometric prompts work above the app.
    return Theme(
      data: Theme.of(context),
      child: Material(
        color: context.colors.surface,
        child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const LockScreen())),
      ),
    );
  }
}
