import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/services.dart';
import 'pin_pad.dart';

const kPinLength = 4;

/// Full-screen lock shown over the app when App Lock is enabled.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  bool _error = false;
  bool _checking = false;
  String? _message;
  Timer? _cooldownTicker;

  @override
  void initState() {
    super.initState();
    final sec = ref.read(securityProvider);
    if (sec.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    final ok = await ref.read(securityProvider).authenticateBiometric();
    if (ok && mounted) ref.read(lockedProvider.notifier).unlock();
  }

  Future<void> _digit(int d) async {
    if (_checking || _pin.length >= kPinLength) return;
    final sec = ref.read(securityProvider);
    if (sec.cooldown > Duration.zero) return;
    setState(() {
      _pin += '$d';
      _error = false;
      _message = null;
    });
    if (_pin.length < kPinLength) return;
    _checking = true;
    final ok = await sec.verifyPin(_pin);
    _checking = false;
    if (!mounted) return;
    if (ok) {
      ref.read(lockedProvider.notifier).unlock();
      return;
    }
    setState(() {
      _error = true;
      _pin = '';
      _message = 'Incorrect PIN';
    });
    if (sec.cooldown > Duration.zero) _startCooldown();
  }

  void _startCooldown() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = ref.read(securityProvider).cooldown;
      if (!mounted) return t.cancel();
      setState(() => _message = left == Duration.zero ? null : 'Too many attempts. Try again in ${left.inSeconds + 1}s');
      if (left == Duration.zero) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sec = ref.read(securityProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.page),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(Icons.lock_outline_rounded, size: 34, color: context.colors.primary),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text('HighhXTrack', style: context.text.headlineSmall),
                  const SizedBox(height: Gap.xs),
                  Text('Enter your PIN to unlock', style: context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                  SizedBox(
                    height: 28,
                    child: Center(
                      child: Text(_message ?? '', style: context.text.bodySmall!.copyWith(color: Palette.danger)),
                    ),
                  ),
                  PinPad(
                    length: _pin.length,
                    maxLength: kPinLength,
                    error: _error,
                    onDigit: _digit,
                    onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
                    extra: sec.biometricEnabled
                        ? IconButton(tooltip: 'Use biometrics', iconSize: 30, onPressed: _biometric, icon: const Icon(Icons.fingerprint_rounded))
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-step PIN creation. Returns true when a PIN was saved.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});
  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  bool _error = false;

  Future<void> _digit(int d) async {
    if (_pin.length >= kPinLength) return;
    setState(() {
      _pin += '$d';
      _error = false;
    });
    if (_pin.length < kPinLength) return;
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _error = true;
        _pin = '';
        _first = '';
        _confirming = false;
      });
      return;
    }
    await ref.read(securityProvider).setPin(_pin);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set PIN')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_confirming ? 'Confirm your PIN' : 'Choose a $kPinLength-digit PIN', style: context.text.titleLarge),
              SizedBox(
                height: 32,
                child: Center(
                  child: Text(_error ? "PINs didn't match. Try again." : '', style: context.text.bodySmall!.copyWith(color: Palette.danger)),
                ),
              ),
              PinPad(
                length: _pin.length,
                maxLength: kPinLength,
                error: _error,
                onDigit: _digit,
                onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the current PIN; returns true if correct.
class VerifyPinScreen extends ConsumerStatefulWidget {
  const VerifyPinScreen({super.key, this.title = 'Enter current PIN'});
  final String title;
  @override
  ConsumerState<VerifyPinScreen> createState() => _VerifyPinScreenState();
}

class _VerifyPinScreenState extends ConsumerState<VerifyPinScreen> {
  String _pin = '';
  bool _error = false;

  Future<void> _digit(int d) async {
    if (_pin.length >= kPinLength) return;
    setState(() {
      _pin += '$d';
      _error = false;
    });
    if (_pin.length < kPinLength) return;
    final ok = await ref.read(securityProvider).verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cooldown = ref.read(securityProvider).cooldown;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 32,
                child: Center(
                  child: Text(
                    cooldown > Duration.zero ? 'Too many attempts. Wait ${cooldown.inSeconds + 1}s' : (_error ? 'Incorrect PIN' : ''),
                    style: context.text.bodySmall!.copyWith(color: Palette.danger),
                  ),
                ),
              ),
              PinPad(
                length: _pin.length,
                maxLength: kPinLength,
                error: _error,
                onDigit: _digit,
                onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
