import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../services/notification_planner.dart';
import '../../services/notification_service.dart';
import '../../state/providers.dart';
import '../../state/services.dart';
import '../gym/rest_timer_bar.dart';
import '../lock/lock_screen.dart';
import '../shell/nav.dart';
import 'backup_screen.dart';

const kCurrencies = ['₹', '\$', '€', '£', '¥', '₩', 'A\$', 'C\$', 'AED', 'R'];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  bool _bioAvailable = false;
  bool? _notifEnabled;
  bool? _exact;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from system settings may have changed permissions.
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final n = NotificationService.instance;
    final bio = await ref.read(securityProvider).biometricAvailable();
    final en = n.supported ? await n.enabled : false;
    final ex = n.supported ? await n.exactAlarmsAllowed : false;
    final p = await n.pendingCount();
    if (mounted) {
      setState(() {
        _bioAvailable = bio;
        _notifEnabled = en;
        _exact = ex;
        _pending = p;
      });
    }
  }

  Future<void> _toggleLock(bool on) async {
    final sec = ref.read(securityProvider);
    if (on) {
      final ok = await push<bool>(context, const SetPinScreen());
      if (ok == true && mounted) showSnack(context, 'App lock enabled');
    } else {
      final ok = await push<bool>(context, const VerifyPinScreen());
      if (ok == true) {
        await sec.disableLock();
        if (mounted) showSnack(context, 'App lock disabled');
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final sec = ref.read(securityProvider);
    final sync = ref.read(notificationSyncProvider);

    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title, padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xl, 0, Gap.sm)),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(children: children),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxxl),
        children: [
          section('Appearance', [
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {s.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => ctrl.update((x) => x.copyWith(themeMode: v.first)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.currency_exchange_rounded),
              title: const Text('Currency symbol'),
              trailing: DropdownButton<String>(
                value: kCurrencies.contains(s.currency) ? s.currency : kCurrencies.first,
                underline: const SizedBox.shrink(),
                items: [for (final c in kCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) {
                  if (v != null) ctrl.update((x) => x.copyWith(currency: v));
                },
              ),
            ),
          ]),
          section('Security & privacy', [
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline_rounded),
              title: const Text('App lock'),
              subtitle: const Text('Require a PIN to open the app'),
              value: sec.lockEnabled,
              onChanged: _toggleLock,
            ),
            if (sec.lockEnabled) ...[
              if (_bioAvailable)
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint_rounded),
                  title: const Text('Unlock with biometrics'),
                  value: sec.biometricEnabled,
                  onChanged: (v) async {
                    if (v && !await sec.authenticateBiometric()) return;
                    await sec.setBiometric(v);
                    if (mounted) setState(() {});
                  },
                ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Change PIN'),
                onTap: () async {
                  final ok = await push<bool>(context, const VerifyPinScreen());
                  if (ok == true && context.mounted) {
                    final set = await push<bool>(context, const SetPinScreen());
                    if (set == true && context.mounted) showSnack(context, 'PIN changed');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Lock after'),
                trailing: DropdownButton<int>(
                  value: const [0, 30, 60, 300, 900].contains(s.lockTimeoutSec) ? s.lockTimeoutSec : 0,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Immediately')),
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60, child: Text('1 minute')),
                    DropdownMenuItem(value: 300, child: Text('5 minutes')),
                    DropdownMenuItem(value: 900, child: Text('15 minutes')),
                  ],
                  onChanged: (v) => ctrl.update((x) => x.copyWith(lockTimeoutSec: v)),
                ),
              ),
            ],
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide amounts on overview'),
              subtitle: const Text('Mask money values on Home and Insights'),
              value: s.hideAmounts,
              onChanged: (v) => ctrl.update((x) => x.copyWith(hideAmounts: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.screenshot_monitor_outlined),
              title: const Text('Secure screen'),
              subtitle: const Text('Block screenshots and hide content in recent apps'),
              value: s.secureScreen,
              onChanged: (v) async {
                await ctrl.update((x) => x.copyWith(secureScreen: v));
                await sec.setSecureScreen(v);
              },
            ),
          ]),
          section('Notifications', [
            ListTile(
              leading: Icon(
                _notifEnabled == true ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                color: _notifEnabled == false ? Palette.warning : null,
              ),
              title: Text(_notifEnabled == null ? 'Checking…' : (_notifEnabled! ? 'Notifications allowed' : 'Notifications are blocked')),
              subtitle: Text('$_pending scheduled'),
              trailing: _notifEnabled == false
                  ? TextButton(
                      onPressed: () async {
                        await NotificationService.instance.requestPermissions();
                        await sync.run();
                        await _refreshStatus();
                      },
                      child: const Text('Allow'),
                    )
                  : null,
            ),
            if (_exact == false)
              ListTile(
                leading: const Icon(Icons.alarm_rounded, color: Palette.warning),
                title: const Text('Allow exact alarms'),
                subtitle: const Text('Without this, reminders may arrive a few minutes late'),
                onTap: () async {
                  await NotificationService.instance.requestExactAlarms();
                  await sync.run();
                  await _refreshStatus();
                },
              ),
            for (final c in NotifChannel.values.where((c) => c != NotifChannel.timers))
              SwitchListTile(
                title: Text(c.label),
                value: s.notifyOn(c.id),
                onChanged: (v) async {
                  await ctrl.update((x) => x.copyWith(notify: {...x.notify, c.id: v}));
                  await sync.run();
                  await _refreshStatus();
                },
              ),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Send test notification'),
              onTap: () =>
                  NotificationService.instance.showNow(id: 9, title: 'HighhXTrack', body: 'Notifications are working 🎉', channel: NotifChannel.reminders),
            ),
          ]),
          section('Gym', [
            ListTile(
              leading: const Icon(Icons.scale_outlined),
              title: const Text('Weight unit'),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'kg', label: Text('kg')),
                  ButtonSegment(value: 'lb', label: Text('lb')),
                ],
                selected: {s.weightUnit},
                showSelectedIcon: false,
                onSelectionChanged: (v) => ctrl.update((x) => x.copyWith(weightUnit: v.first)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Default rest for new exercises'),
              trailing: DropdownButton<int>(
                value: kRestPresets.contains(s.defaultRestSec) ? s.defaultRestSec : 90,
                underline: const SizedBox.shrink(),
                items: [for (final r in kRestPresets) DropdownMenuItem(value: r, child: Text(restLabel(r)))],
                onChanged: (v) => ctrl.update((x) => x.copyWith(defaultRestSec: v)),
              ),
            ),
          ]),
          section('Study', [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Daily target'),
              trailing: NumberStepper(
                value: s.studyDailyTargetMin,
                min: 15,
                max: 960,
                step: 15,
                suffix: 'm',
                onChanged: (v) => ctrl.update((x) => x.copyWith(studyDailyTargetMin: v)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded),
              title: const Text('Weekly target'),
              trailing: NumberStepper(
                value: s.studyWeeklyTargetMin,
                min: 60,
                max: 6000,
                step: 60,
                suffix: 'm',
                onChanged: (v) => ctrl.update((x) => x.copyWith(studyWeeklyTargetMin: v)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none_rounded),
              title: const Text('Daily study reminder'),
              subtitle: Text(s.studyReminderMin == null ? 'Off' : D.minutesOfDayLabel(s.studyReminderMin!)),
              trailing: s.studyReminderMin == null
                  ? null
                  : IconButton(
                      tooltip: 'Turn off',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        await ctrl.update((x) => x.copyWith(clearStudyReminder: true));
                        await sync.run();
                      },
                    ),
              onTap: () async {
                final m = s.studyReminderMin;
                final t = await pickTime(
                  context,
                  initial: m == null ? const TimeOfDay(hour: 19, minute: 0) : TimeOfDay(hour: m ~/ 60, minute: m % 60),
                );
                if (t == null) return;
                await ctrl.update((x) => x.copyWith(studyReminderMin: t.hour * 60 + t.minute));
                await sync.run();
              },
            ),
          ]),
          section('Data', [
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup, restore & export'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => push(context, const BackupScreen()),
            ),
          ]),
          const SizedBox(height: Gap.xl),
          Center(child: Text('HighhXTrack · v1.0.0', style: context.text.bodySmall)),
          Center(child: Text('Offline-first. Your data never leaves your device.', style: context.text.bodySmall)),
        ],
      ),
    );
  }
}
