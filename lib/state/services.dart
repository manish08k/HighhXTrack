import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_service.dart';
import '../services/security_service.dart';
import 'providers.dart';

/// Loaded (secure storage read) in main() before the first frame.
final securityProvider = Provider<SecurityService>((ref) => throw StateError('securityProvider must be overridden in main()'));

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));

/// Whether the app is currently locked behind the PIN screen.
class LockNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(securityProvider).lockEnabled;
  void lock() {
    if (ref.read(securityProvider).lockEnabled) state = true;
  }

  void unlock() => state = false;
}

final lockedProvider = NotifierProvider<LockNotifier, bool>(LockNotifier.new);
