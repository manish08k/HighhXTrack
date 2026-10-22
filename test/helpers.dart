import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:newone/data/db/app_database.dart';
import 'package:newone/data/repositories/settings_repo.dart';
import 'package:newone/services/security_service.dart';
import 'package:newone/state/providers.dart';
import 'package:newone/state/services.dart';
import 'package:newone/state/timers.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// path_provider backed by a temp directory.
class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
  @override
  Future<String?> getTemporaryPath() async => root.path;
  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

/// Opens a fresh in-memory database (schema + seed) without isolates so it
/// works inside fake-async widget tests.
Future<AppDatabase> openTestDb() async {
  sqfliteFfiInit();
  return AppDatabase.open(overridePath: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
}

Future<ProviderContainer> makeContainer(AppDatabase db, {AppSettings settings = const AppSettings()}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final security = SecurityService();
  await security.load();
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      prefsProvider.overrideWithValue(prefs),
      initialSettingsProvider.overrideWithValue(settings),
      securityProvider.overrideWithValue(security),
    ],
  );
}

void setUpTempPaths() {
  final dir = Directory.systemTemp.createTempSync('hxt_test');
  PathProviderPlatform.instance = FakePathProvider(dir);
}
