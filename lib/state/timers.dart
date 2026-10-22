import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/knowledge.dart';
import '../services/notification_service.dart';
import 'providers.dart';

/// Loaded in main(); used to persist running timers across restarts.
final prefsProvider = Provider<SharedPreferences>((ref) => throw StateError('prefsProvider must be overridden in main()'));

/// One-second clock for countdown displays. Only alive while watched.
final clockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

// =================================================================== REST

class RestTimerState {
  const RestTimerState({this.endsAt, this.total = 0, this.pausedLeft, this.label = ''});
  final DateTime? endsAt;
  final int total;
  final int? pausedLeft;
  final String label;

  static const idle = RestTimerState();

  bool get active => endsAt != null || pausedLeft != null;
  bool get paused => pausedLeft != null;

  int remaining([DateTime? now]) {
    if (pausedLeft != null) return pausedLeft!;
    if (endsAt == null) return 0;
    final ms = endsAt!.difference(now ?? DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool finished([DateTime? now]) => endsAt != null && pausedLeft == null && remaining(now) == 0;

  Map<String, Object?> toJson() => {'e': endsAt?.millisecondsSinceEpoch, 't': total, 'p': pausedLeft, 'l': label};

  factory RestTimerState.fromJson(Map<String, Object?> j) => RestTimerState(
    endsAt: j['e'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['e'] as int),
    total: j['t'] as int? ?? 0,
    pausedLeft: j['p'] as int?,
    label: j['l'] as String? ?? '',
  );
}

/// Workout rest timer. Time is derived from an absolute end timestamp so it
/// stays correct across navigation, backgrounding and process death.
class RestTimerController extends Notifier<RestTimerState> {
  static const _key = 'rest_timer';
  Timer? _ticker;
  bool _alerted = false;

  @override
  RestTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    final raw = ref.read(prefsProvider).getString(_key);
    var s = RestTimerState.idle;
    if (raw != null) {
      try {
        s = RestTimerState.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    // Drop timers that finished long ago.
    if (s.endsAt != null && s.pausedLeft == null && DateTime.now().difference(s.endsAt!).inMinutes > 5) {
      s = RestTimerState.idle;
    }
    _alerted = s.finished();
    if (s.active && !s.paused) _startTicker();
    return s;
  }

  void _set(RestTimerState s) {
    state = s;
    final prefs = ref.read(prefsProvider);
    if (s.active) {
      prefs.setString(_key, jsonEncode(s.toJson()));
    } else {
      prefs.remove(_key);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!state.active || state.paused) return;
      if (state.finished() && !_alerted) {
        _alerted = true;
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        state = RestTimerState(endsAt: state.endsAt, total: state.total, label: state.label);
      }
    });
  }

  Future<void> _scheduleAlert() async {
    final n = NotificationService.instance;
    await n.cancel(NotificationService.restTimerId);
    if (state.endsAt != null && !state.paused) {
      await n.schedule(
        PlannedNotification(
          id: NotificationService.restTimerId,
          at: state.endsAt!,
          title: 'Rest complete',
          body: state.label.isEmpty ? 'Time for your next set' : 'Next: ${state.label}',
          channel: NotifChannel.timers,
          payload: 'gym:0:active',
        ),
      );
    }
  }

  void start(int seconds, {String label = ''}) {
    _alerted = false;
    _set(
      RestTimerState(
        endsAt: DateTime.now().add(Duration(seconds: seconds)),
        total: seconds,
        label: label,
      ),
    );
    _startTicker();
    _scheduleAlert();
  }

  void add(int seconds) {
    if (!state.active) return;
    if (state.paused) {
      _set(RestTimerState(pausedLeft: max(0, state.pausedLeft! + seconds), total: max(1, state.total + seconds), label: state.label));
      return;
    }
    final base = state.finished() ? DateTime.now() : state.endsAt!;
    final ends = base.add(Duration(seconds: seconds));
    if (!ends.isAfter(DateTime.now())) {
      stop();
      return;
    }
    _alerted = false;
    _set(RestTimerState(endsAt: ends, total: max(1, state.total + seconds), label: state.label));
    _scheduleAlert();
  }

  void pause() {
    if (!state.active || state.paused) return;
    _set(RestTimerState(pausedLeft: state.remaining(), total: state.total, label: state.label));
    NotificationService.instance.cancel(NotificationService.restTimerId);
  }

  void resume() {
    if (!state.paused) return;
    _set(
      RestTimerState(
        endsAt: DateTime.now().add(Duration(seconds: state.pausedLeft!)),
        total: state.total,
        label: state.label,
      ),
    );
    _alerted = false;
    _startTicker();
    _scheduleAlert();
  }

  void stop() {
    _ticker?.cancel();
    _set(RestTimerState.idle);
    NotificationService.instance.cancel(NotificationService.restTimerId);
  }
}

final restTimerProvider = NotifierProvider<RestTimerController, RestTimerState>(RestTimerController.new);

// =================================================================== STUDY

enum StudyMode { stopwatch, pomodoro }

enum PomoPhase { focus, rest }

class StudyTimerState {
  const StudyTimerState({
    this.active = false,
    this.mode = StudyMode.stopwatch,
    this.subjectId,
    this.topicId,
    this.subjectName = '',
    this.topicName,
    this.sessionStart,
    this.runningSince,
    this.accumulated = 0,
    this.focusMin = 25,
    this.breakMin = 5,
    this.phase = PomoPhase.focus,
    this.phaseEndsAt,
    this.phasePausedLeft,
    this.cycles = 0,
    this.focusLogged = 0,
  });

  final bool active;
  final StudyMode mode;
  final int? subjectId;
  final int? topicId;
  final String subjectName;
  final String? topicName;
  final DateTime? sessionStart;

  // Stopwatch
  final DateTime? runningSince;
  final int accumulated;

  // Pomodoro
  final int focusMin;
  final int breakMin;
  final PomoPhase phase;
  final DateTime? phaseEndsAt;
  final int? phasePausedLeft;
  final int cycles;

  /// Focus seconds already saved as sessions during this run.
  final int focusLogged;

  static const idle = StudyTimerState();

  bool get paused => mode == StudyMode.stopwatch ? runningSince == null : phasePausedLeft != null;

  int phaseLength() => (phase == PomoPhase.focus ? focusMin : breakMin) * 60;

  int elapsed([DateTime? now]) {
    now ??= DateTime.now();
    if (mode == StudyMode.stopwatch) {
      return accumulated + (runningSince == null ? 0 : now.difference(runningSince!).inSeconds);
    }
    return phaseLength() - phaseRemaining(now);
  }

  int phaseRemaining([DateTime? now]) {
    if (phasePausedLeft != null) return phasePausedLeft!;
    if (phaseEndsAt == null) return phaseLength();
    final ms = phaseEndsAt!.difference(now ?? DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  StudyTimerState copyWith({
    DateTime? runningSince,
    bool clearRunning = false,
    int? accumulated,
    PomoPhase? phase,
    DateTime? phaseEndsAt,
    bool clearPhaseEnd = false,
    int? phasePausedLeft,
    bool clearPaused = false,
    int? cycles,
    int? focusLogged,
  }) => StudyTimerState(
    active: active,
    mode: mode,
    subjectId: subjectId,
    topicId: topicId,
    subjectName: subjectName,
    topicName: topicName,
    sessionStart: sessionStart,
    runningSince: clearRunning ? null : (runningSince ?? this.runningSince),
    accumulated: accumulated ?? this.accumulated,
    focusMin: focusMin,
    breakMin: breakMin,
    phase: phase ?? this.phase,
    phaseEndsAt: clearPhaseEnd ? null : (phaseEndsAt ?? this.phaseEndsAt),
    phasePausedLeft: clearPaused ? null : (phasePausedLeft ?? this.phasePausedLeft),
    cycles: cycles ?? this.cycles,
    focusLogged: focusLogged ?? this.focusLogged,
  );

  Map<String, Object?> toJson() => {
    'a': active,
    'm': mode.index,
    'sid': subjectId,
    'tid': topicId,
    'sn': subjectName,
    'tn': topicName,
    'ss': sessionStart?.millisecondsSinceEpoch,
    'rs': runningSince?.millisecondsSinceEpoch,
    'acc': accumulated,
    'fm': focusMin,
    'bm': breakMin,
    'ph': phase.index,
    'pe': phaseEndsAt?.millisecondsSinceEpoch,
    'pp': phasePausedLeft,
    'c': cycles,
    'fl': focusLogged,
  };

  factory StudyTimerState.fromJson(Map<String, Object?> j) {
    DateTime? t(String k) => j[k] == null ? null : DateTime.fromMillisecondsSinceEpoch(j[k] as int);
    return StudyTimerState(
      active: j['a'] == true,
      mode: StudyMode.values[(j['m'] as int? ?? 0).clamp(0, 1)],
      subjectId: j['sid'] as int?,
      topicId: j['tid'] as int?,
      subjectName: j['sn'] as String? ?? '',
      topicName: j['tn'] as String?,
      sessionStart: t('ss'),
      runningSince: t('rs'),
      accumulated: j['acc'] as int? ?? 0,
      focusMin: j['fm'] as int? ?? 25,
      breakMin: j['bm'] as int? ?? 5,
      phase: PomoPhase.values[(j['ph'] as int? ?? 0).clamp(0, 1)],
      phaseEndsAt: t('pe'),
      phasePausedLeft: j['pp'] as int?,
      cycles: j['c'] as int? ?? 0,
      focusLogged: j['fl'] as int? ?? 0,
    );
  }
}

/// Study stopwatch and Pomodoro. Completed focus blocks are saved as study
/// sessions immediately, so progress survives the app being killed.
class StudyTimerController extends Notifier<StudyTimerState> {
  static const _key = 'study_timer';
  Timer? _ticker;

  @override
  StudyTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    final raw = ref.read(prefsProvider).getString(_key);
    var s = StudyTimerState.idle;
    if (raw != null) {
      try {
        s = StudyTimerState.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    if (s.active) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _advance());
      Future.microtask(_advance);
    }
    return s;
  }

  void _set(StudyTimerState s) {
    state = s;
    final prefs = ref.read(prefsProvider);
    if (s.active) {
      prefs.setString(_key, jsonEncode(s.toJson()));
    } else {
      prefs.remove(_key);
    }
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _advance());
  }

  Future<void> _save(int seconds, String kind, DateTime start) async {
    if (seconds < 60) return;
    await ref
        .read(studyRepoProvider)
        .addSession(StudySession(subjectId: state.subjectId, topicId: state.topicId, startedAt: start, durationSec: seconds, kind: kind));
  }

  /// Processes phase boundaries that passed (possibly while the app was closed).
  Future<void> _advance() async {
    final s = state;
    if (!s.active || s.mode != StudyMode.pomodoro || s.paused || s.phaseEndsAt == null) return;
    final now = DateTime.now();
    if (now.isBefore(s.phaseEndsAt!)) return;
    if (s.phase == PomoPhase.focus) {
      final len = s.focusMin * 60;
      // Mark before the async save so a concurrent tick can't double-log.
      _set(
        s.copyWith(
          phase: PomoPhase.rest,
          phaseEndsAt: s.phaseEndsAt!.add(Duration(minutes: s.breakMin)),
          cycles: s.cycles + 1,
          focusLogged: s.focusLogged + len,
        ),
      );
      HapticFeedback.heavyImpact();
      await _save(len, 'pomodoro', s.phaseEndsAt!.subtract(Duration(seconds: len)));
      await _scheduleAlert();
      // The break may also have elapsed while away.
      await _advance();
    } else {
      // Break over: wait for the user to start the next focus block.
      _set(s.copyWith(phase: PomoPhase.focus, clearPhaseEnd: true, phasePausedLeft: s.focusMin * 60));
      HapticFeedback.heavyImpact();
      await NotificationService.instance.cancel(NotificationService.pomodoroId);
    }
  }

  Future<void> _scheduleAlert() async {
    final n = NotificationService.instance;
    await n.cancel(NotificationService.pomodoroId);
    final s = state;
    if (!s.active || s.mode != StudyMode.pomodoro || s.paused || s.phaseEndsAt == null) return;
    await n.schedule(
      PlannedNotification(
        id: NotificationService.pomodoroId,
        at: s.phaseEndsAt!,
        title: s.phase == PomoPhase.focus ? 'Focus block complete' : 'Break is over',
        body: s.phase == PomoPhase.focus ? 'Take a ${s.breakMin}-minute break.' : 'Ready for the next ${s.focusMin}-minute focus?',
        channel: NotifChannel.timers,
        payload: 'study:0:timer',
      ),
    );
  }

  void startStopwatch({int? subjectId, String subjectName = '', int? topicId, String? topicName}) {
    final now = DateTime.now();
    _set(
      StudyTimerState(
        active: true,
        mode: StudyMode.stopwatch,
        subjectId: subjectId,
        subjectName: subjectName,
        topicId: topicId,
        topicName: topicName,
        sessionStart: now,
        runningSince: now,
      ),
    );
    _ensureTicker();
  }

  void startPomodoro({int? subjectId, String subjectName = '', int? topicId, String? topicName, required int focusMin, required int breakMin}) {
    final now = DateTime.now();
    _set(
      StudyTimerState(
        active: true,
        mode: StudyMode.pomodoro,
        subjectId: subjectId,
        subjectName: subjectName,
        topicId: topicId,
        topicName: topicName,
        sessionStart: now,
        focusMin: focusMin.clamp(1, 240),
        breakMin: breakMin.clamp(1, 120),
        phase: PomoPhase.focus,
        phaseEndsAt: now.add(Duration(minutes: focusMin.clamp(1, 240))),
      ),
    );
    _ensureTicker();
    _scheduleAlert();
  }

  void pause() {
    final s = state;
    if (!s.active || s.paused) return;
    if (s.mode == StudyMode.stopwatch) {
      _set(s.copyWith(accumulated: s.elapsed(), clearRunning: true));
    } else {
      _set(s.copyWith(phasePausedLeft: s.phaseRemaining(), clearPhaseEnd: true));
      NotificationService.instance.cancel(NotificationService.pomodoroId);
    }
  }

  void resume() {
    final s = state;
    if (!s.active || !s.paused) return;
    if (s.mode == StudyMode.stopwatch) {
      _set(s.copyWith(runningSince: DateTime.now()));
    } else {
      _set(s.copyWith(phaseEndsAt: DateTime.now().add(Duration(seconds: s.phasePausedLeft!)), clearPaused: true));
      _scheduleAlert();
    }
  }

  /// Skips the current Pomodoro phase (saving partial focus time).
  Future<void> skipPhase() async {
    final s = state;
    if (!s.active || s.mode != StudyMode.pomodoro) return;
    if (s.phase == PomoPhase.focus) {
      final done = s.elapsed();
      _set(
        s.copyWith(
          phase: PomoPhase.rest,
          phaseEndsAt: DateTime.now().add(Duration(minutes: s.breakMin)),
          clearPaused: true,
          cycles: done >= 60 ? s.cycles + 1 : s.cycles,
          focusLogged: s.focusLogged + done,
        ),
      );
      await _save(done, 'pomodoro', DateTime.now().subtract(Duration(seconds: done)));
    } else {
      _set(
        s.copyWith(
          phase: PomoPhase.focus,
          phaseEndsAt: DateTime.now().add(Duration(minutes: s.focusMin)),
          clearPaused: true,
        ),
      );
    }
    await _scheduleAlert();
  }

  /// Stops and saves. Returns seconds saved by this call.
  Future<int> stop({bool save = true}) async {
    final s = state;
    if (!s.active) return 0;
    _ticker?.cancel();
    _ticker = null;
    _set(StudyTimerState.idle);
    await NotificationService.instance.cancel(NotificationService.pomodoroId);
    if (!save) return 0;
    if (s.mode == StudyMode.stopwatch) {
      final secs = s.elapsed();
      if (secs >= 60) {
        await ref
            .read(studyRepoProvider)
            .addSession(
              StudySession(subjectId: s.subjectId, topicId: s.topicId, startedAt: s.sessionStart ?? DateTime.now(), durationSec: secs, kind: 'timer'),
            );
        return secs;
      }
      return 0;
    }
    if (s.phase == PomoPhase.focus) {
      final secs = s.elapsed();
      if (secs >= 60) {
        await ref
            .read(studyRepoProvider)
            .addSession(
              StudySession(
                subjectId: s.subjectId,
                topicId: s.topicId,
                startedAt: DateTime.now().subtract(Duration(seconds: secs)),
                durationSec: secs,
                kind: 'pomodoro',
              ),
            );
        return secs;
      }
    }
    return 0;
  }
}

final studyTimerProvider = NotifierProvider<StudyTimerController, StudyTimerState>(StudyTimerController.new);
