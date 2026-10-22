import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// App lock: salted PIN hash in secure storage, optional biometrics,
/// and FLAG_SECURE control on Android.
class SecurityService {
  SecurityService({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _auth = LocalAuthentication();
  static const _channel = MethodChannel('highhxtrack/secure');

  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';
  static const _kBio = 'bio_enabled';

  bool _lockEnabled = false;
  bool _bioEnabled = false;
  int _failures = 0;
  DateTime? _lockedUntil;

  bool get lockEnabled => _lockEnabled;
  bool get biometricEnabled => _bioEnabled;

  /// Remaining cooldown after repeated wrong PINs.
  Duration get cooldown {
    final u = _lockedUntil;
    if (u == null) return Duration.zero;
    final d = u.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> load() async {
    try {
      _lockEnabled = (await _storage.read(key: _kHash)) != null;
      _bioEnabled = (await _storage.read(key: _kBio)) == '1';
    } catch (e) {
      // Keystore can be reset (e.g. after restoring a device backup).
      debugPrint('Secure storage read failed: $e');
      _lockEnabled = false;
      _bioEnabled = false;
    }
  }

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin:highhxtrack')).toString();

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _storage.write(key: _kSalt, value: salt);
    await _storage.write(key: _kHash, value: _hash(pin, salt));
    _lockEnabled = true;
  }

  Future<bool> verifyPin(String pin) async {
    if (cooldown > Duration.zero) return false;
    final salt = await _storage.read(key: _kSalt);
    final hash = await _storage.read(key: _kHash);
    if (salt == null || hash == null) return true;
    final ok = _hash(pin, salt) == hash;
    if (ok) {
      _failures = 0;
      _lockedUntil = null;
    } else {
      _failures++;
      if (_failures >= 5) {
        _lockedUntil = DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
      }
    }
    return ok;
  }

  Future<void> disableLock() async {
    await _storage.delete(key: _kHash);
    await _storage.delete(key: _kSalt);
    await _storage.delete(key: _kBio);
    _lockEnabled = false;
    _bioEnabled = false;
  }

  Future<void> setBiometric(bool on) async {
    await _storage.write(key: _kBio, value: on ? '1' : '0');
    _bioEnabled = on;
  }

  Future<bool> biometricAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(localizedReason: 'Unlock HighhXTrack', biometricOnly: true, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('Biometric auth failed: $e');
      return false;
    }
  }

  /// Hides app content from screenshots and the recent-apps switcher.
  Future<void> setSecureScreen(bool on) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', on);
    } catch (e) {
      debugPrint('setSecure failed: $e');
    }
  }
}
