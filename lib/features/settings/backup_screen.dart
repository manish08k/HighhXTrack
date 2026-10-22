import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../services/backup_service.dart';
import '../../services/notification_planner.dart';
import '../../state/providers.dart';
import '../../state/services.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      debugPrint('backup: $e');
      if (mounted) showSnack(context, 'Something went wrong: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() => _run(() async {
    final svc = ref.read(backupServiceProvider);
    final data = await svc.pickBackup();
    if (data == null || !mounted) return;
    final tables = (data['tables'] as Map).cast<String, Object?>();
    final count = tables.values.fold<int>(0, (a, l) => a + (l is List ? l.length : 0));
    final ok = await confirmDialog(
      context,
      title: 'Restore backup?',
      message:
          'This replaces ALL current data with the backup from ${data['exported_at'].toString().split('T').first} ($count records). A safety copy of your current data is saved first.',
      confirm: 'Restore',
    );
    if (!ok) return;
    final res = await svc.restore(data);
    await ref.read(settingsProvider.notifier).reload();
    ref.read(changesProvider.notifier).bumpAll();
    await ref.read(notificationSyncProvider).run();
    if (mounted) showSnack(context, 'Restored ${res.rows} records and ${res.files} files');
  });

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(backupServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & export')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: Gap.md),
                child: LinearProgressIndicator(),
              ),
            AppCard(
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: context.colors.primary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      'All data is stored only on this device. Make regular backups so nothing is lost if you change or reset your phone.',
                      style: context.text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader('Backup', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.save_alt_rounded),
                    title: const Text('Save backup to device'),
                    subtitle: const Text('Full backup including attachments (.json)'),
                    onTap: () => _run(() async {
                      final saved = await svc.saveBackupToDevice();
                      if (saved && context.mounted) showSnack(context, 'Backup saved');
                    }),
                  ),
                  ListTile(
                    leading: const Icon(Icons.ios_share_rounded),
                    title: const Text('Share backup'),
                    subtitle: const Text('Send to Drive, email or another app'),
                    onTap: () => _run(svc.shareBackup),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore_rounded),
                    title: const Text('Restore from backup'),
                    subtitle: const Text('Replaces current data'),
                    onTap: _restore,
                  ),
                ],
              ),
            ),
            const SectionHeader('Export (CSV)', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Transactions'),
                    onTap: () => _run(() async => svc.shareCsv('transactions', await svc.transactionsCsv())),
                  ),
                  ListTile(
                    leading: const Icon(Icons.checklist_rounded),
                    title: const Text('Tasks'),
                    onTap: () => _run(() async => svc.shareCsv('tasks', await svc.todosCsv())),
                  ),
                  ListTile(
                    leading: const Icon(Icons.fitness_center_rounded),
                    title: const Text('Workout sets'),
                    onTap: () => _run(() async => svc.shareCsv('workouts', await svc.workoutsCsv())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
