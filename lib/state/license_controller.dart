import 'dart:math';
import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';

import '../core/licensing/license.dart';
import '../core/licensing/license_store.dart';
import '../core/licensing/paywall_config.dart';

/// Central licensing state: free-trial counter, activation status and the
/// device identity users quote when buying a code. Exposed app-wide via
/// `provider`.
///
/// Gating model ("Route B"):
///   * every install gets [kFreeTrialChecks] free verifications;
///   * a valid, unexpired license code lifts the limit;
///   * codes are Ed25519-signed, bound to THIS device and carry their own
///     expiry — see `core/licensing/license.dart`.
class LicenseController extends ChangeNotifier {
  LicenseController({
    LicenseKeyValue? store,
    Future<String?> Function()? deviceKeySource,
    DateTime Function()? now,
    String publicKeyHex = kLicensePublicKeyV1,
  })  : _store = store ?? SecureLicenseStore(),
        _deviceKeySource =
            deviceKeySource ?? (() => const AndroidId().getId()),
        _now = now ?? (() => DateTime.now().toUtc()),
        _publicKeyHex = publicKeyHex;

  final LicenseKeyValue _store;
  final Future<String?> Function() _deviceKeySource;
  final DateTime Function() _now;
  final String _publicKeyHex;

  static const String _kTrialsKey = 'trial_checks';
  static const String _kTokenKey = 'license_token';
  static const String _kFallbackDeviceKey = 'fallback_device_key';

  bool _loaded = false;
  bool _loading = false;
  int _trialsUsed = 0;
  DateTime? _expiryUtc;

  /// Stable device key (Android SSAID; falls back to a random UUID kept in
  /// secure storage). Not the pretty code — see [deviceCode].
  Uint8List? _deviceHash;

  /// Human-facing device code (`MAH-XXXXXXX`) the user sends with their
  /// payment. Empty until [ensureLoaded] finished.
  String deviceCode = '';

  // ---------------------------------------------------------------- accessors

  bool get isLoaded => _loaded;

  int get trialsLeft =>
      (kFreeTrialChecks - _trialsUsed).clamp(0, kFreeTrialChecks);

  /// True while a valid, unexpired license is active on this device.
  bool get isEntitled {
    final expiry = _expiryUtc;
    return expiry != null && !_now().isAfter(expiry);
  }

  /// Trial or license — may a verification run right now?
  bool get canVerifyNow => isEntitled || trialsLeft > 0;

  /// When the current license expires (null on trial).
  DateTime? get expiresAt => _expiryUtc;

  /// Days remaining on the license (0 when on trial/expired).
  int get daysLeft {
    final expiry = _expiryUtc;
    if (expiry == null) return 0;
    return expiry.difference(_now()).inDays.clamp(0, 9999);
  }

  // ---------------------------------------------------------------- lifecycle

  /// Loads persisted state and the device identity. Idempotent and
  /// concurrency-safe; the gating flow awaits this before deciding.
  ///
  /// The device identity loads FIRST — license validation needs the
  /// device hash, so the persisted token is checked only after it.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      await _loadDevice();
      await Future.wait([
        _loadTrials(),
        _loadLicense(),
      ]);
      _loaded = true;
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadTrials() async {
    try {
      final raw = await _store.read(_kTrialsKey);
      _trialsUsed = int.tryParse(raw ?? '') ?? 0;
      if (_trialsUsed < 0) _trialsUsed = 0;
    } catch (_) {
      _trialsUsed = 0;
    }
  }

  Future<void> _loadLicense() async {
    try {
      final token = await _store.read(_kTokenKey);
      _expiryUtc = await _expiryOf(token);
    } catch (_) {
      _expiryUtc = null;
    }
  }

  Future<void> _loadDevice() async {
    String? key;
    try {
      key = await _deviceKeySource();
    } catch (_) {
      key = null;
    }
    if (key == null || key.trim().isEmpty) {
      // SSAID unavailable (weird ROM / platform) — fall back to a random
      // key persisted in secure storage. Less reset-proof, still binding.
      try {
        key = await _store.read(_kFallbackDeviceKey);
        if (key == null || key.isEmpty) {
          key = _randomKey();
          await _store.write(_kFallbackDeviceKey, key);
        }
      } catch (_) {
        key = 'mahtem-anon-device';
      }
    }
    _deviceHash = deviceHashFor(key);
    deviceCode = deviceCodeFor(_deviceHash!);
  }

  // ---------------------------------------------------------------- mutation

  /// Counts one verification against the trial — no-op while entitled.
  Future<void> consumeAttempt() async {
    if (isEntitled) return;
    _trialsUsed += 1;
    try {
      await _store.write(_kTrialsKey, '$_trialsUsed');
    } catch (_) {
      // Storage failed — keep the in-memory count for this session.
    }
    notifyListeners();
  }

  /// Validates and stores an activation code. Returns the result so the
  /// paywall can show exactly why a code was refused.
  Future<LicenseValidation> activate(String rawToken) async {
    if (_deviceHash == null) await _loadDevice();
    final validation = await validateLicenseToken(
      rawToken,
      deviceHash: _deviceHash!,
      now: _now(),
      publicKeyHex: _publicKeyHex,
    );
    if (validation is LicenseValid) {
      _expiryUtc = validation.expiryUtc;
      try {
        await _store.write(_kTokenKey, rawToken.trim());
      } catch (_) {
        // Storage failed — the license still works for this session.
      }
      notifyListeners();
    }
    return validation;
  }

  // ---------------------------------------------------------------- internals

  Future<DateTime?> _expiryOf(String? token) async {
    if (token == null || token.trim().isEmpty) return null;
    if (_deviceHash == null) return null;
    final validation = await validateLicenseToken(
      token,
      deviceHash: _deviceHash!,
      now: _now(),
      publicKeyHex: _publicKeyHex,
    );
    if (validation is! LicenseValid) return null;
    return validation.expiryUtc;
  }

  String _randomKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
