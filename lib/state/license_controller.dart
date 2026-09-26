import 'dart:convert';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';

import '../core/licensing/license.dart';
import '../core/licensing/license_store.dart';
import '../core/licensing/paywall_config.dart';
import '../core/licensing/receipt_activation.dart';
import '../core/receipt_verify/models.dart';
import '../core/receipt_verify/verifier.dart';

/// Signature of the receipt engine the self-activation flow calls.
typedef ReceiptVerifyFn = Future<VerifyResult> Function(VerifyInput input);

/// Central licensing state: free-trial counter, activation status and the
/// device identity users quote when buying a code. Exposed app-wide via
/// `provider`.
///
/// Gating model ("Route B"):
///   * every install gets [kFreeTrialChecks] free verifications;
///   * an active plan lifts the limit — either an Ed25519-signed license
///     code (owner-minted, device-bound, see `core/licensing/license.dart`)
///     or a self-verified Telebirr payment receipt
///     (see `core/licensing/receipt_activation.dart`);
///   * both entitlements stack — a code month plus a receipt month simply
///     add up.
class LicenseController extends ChangeNotifier {
  LicenseController({
    LicenseKeyValue? store,
    Future<String?> Function()? deviceKeySource,
    DateTime Function()? now,
    String publicKeyHex = kLicensePublicKeyV1,
    ReceiptVerifyFn? receiptVerifier,
  })  : _store = store ?? SecureLicenseStore(),
        _deviceKeySource =
            deviceKeySource ?? (() => const AndroidId().getId()),
        _now = now ?? (() => DateTime.now().toUtc()),
        _publicKeyHex = publicKeyHex,
        _receiptVerifier = receiptVerifier ?? ReceiptVerifier.I.verify;

  final LicenseKeyValue _store;
  final Future<String?> Function() _deviceKeySource;
  final DateTime Function() _now;
  final String _publicKeyHex;
  final ReceiptVerifyFn _receiptVerifier;

  static const String _kTrialsKey = 'trial_checks';
  static const String _kTokenKey = 'license_token';
  static const String _kReceiptKey = 'receipt_license';
  static const String _kUsedReceiptsKey = 'used_receipts';
  static const String _kFallbackDeviceKey = 'fallback_device_key';

  bool _loaded = false;
  bool _loading = false;
  int _trialsUsed = 0;

  /// Expiry carried by the signed token, and by the locally stored
  /// self-verified receipt. Either grants entitlement; the later wins.
  DateTime? _tokenExpiry;
  DateTime? _receiptExpiry;

  /// Hash of the receipt that granted [_receiptExpiry] — lets the same
  /// receipt be re-submitted without double-charging the used list.
  String? _receiptRefHash;

  /// Every receipt ever used to activate on this device (hashes). A used
  /// receipt cannot grant a second month after its plan expires.
  Set<String> _usedReceipts = <String>{};

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

  /// True while a valid, unexpired plan is active on this device.
  bool get isEntitled {
    final expiry = effectiveExpiry;
    return expiry != null && !_now().isAfter(expiry);
  }

  /// The later of the token expiry and the receipt expiry — either one
  /// grants entitlement and they stack.
  DateTime? get effectiveExpiry {
    DateTime? best;
    for (final e in [_tokenExpiry, _receiptExpiry]) {
      if (e != null && (best == null || e.isAfter(best))) best = e;
    }
    return best;
  }

  /// Trial or license — may a verification run right now?
  bool get canVerifyNow => isEntitled || trialsLeft > 0;

  /// When the current plan expires (null on trial).
  DateTime? get expiresAt => effectiveExpiry;

  /// Days remaining on the plan (0 when on trial/expired).
  int get daysLeft {
    final expiry = effectiveExpiry;
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
    _tokenExpiry = null;
    _receiptExpiry = null;
    _receiptRefHash = null;
    _usedReceipts = <String>{};
    try {
      final token = await _store.read(_kTokenKey);
      _tokenExpiry = await _expiryOf(token);
    } catch (_) {
      _tokenExpiry = null;
    }
    try {
      final raw = await _store.read(_kReceiptKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final ms = (map['expiryMs'] as num?)?.toInt();
        final hash = map['refHash'] as String?;
        if (ms != null && ms > 0) {
          _receiptExpiry =
              DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
        }
        if (hash != null && hash.isNotEmpty) _receiptRefHash = hash;
      }
    } catch (_) {
      _receiptExpiry = null;
    }
    try {
      final raw = await _store.read(_kUsedReceiptsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _usedReceipts = list.whereType<String>().toSet();
      }
    } catch (_) {
      _usedReceipts = <String>{};
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
      _tokenExpiry = validation.expiryUtc;
      try {
        await _store.write(_kTokenKey, rawToken.trim());
      } catch (_) {
        // Storage failed — the license still works for this session.
      }
      notifyListeners();
    }
    return validation;
  }

  /// Self-activation: verifies the user's Telebirr payment receipt with
  /// the app's own engine and, when it is a genuine plan payment to the
  /// owner, unlocks the app — no code, no server, no human in the loop.
  ///
  /// [rawInput] is the receipt number from the confirmation SMS (or the
  /// full transactioninfo.ethiotelecom.et link — the engine resolves it).
  Future<ReceiptActivation> activateWithReceipt(String rawInput) async {
    await ensureLoaded();
    final input = rawInput.trim();
    if (input.isEmpty) {
      return const ReceiptActivationRejected(
          'Paste the receipt number from the Telebirr confirmation SMS.');
    }

    final VerifyResult result;
    try {
      result = await _receiptVerifier(
          VerifyInput(bankId: 'telebirr', reference: input));
    } catch (_) {
      return const ReceiptActivationError(VerifyFailure(
        VerifyErrorKind.network,
        'Could not check the receipt right now — check your internet and '
        'try again.',
        tips: ['Make sure mobile data or Wi-Fi is on.'],
      ));
    }
    if (result.failure != null) return ReceiptActivationError(result.failure!);
    final receipt = result.receipt!;

    // Which payment is this? Prefer the invoice number Telebirr returned.
    final refKey = normalizeReceiptReference(
      (receipt.invoiceNumber?.trim().isNotEmpty ?? false)
          ? receipt.invoiceNumber!
          : (receipt.reference.trim().isNotEmpty
              ? receipt.reference
              : input),
    );
    final refHash = receiptHashFor(refKey);

    // Same receipt submitted again while its plan still runs — nothing to
    // grant, just confirm the current expiry.
    if (refHash == _receiptRefHash &&
        _receiptExpiry != null &&
        !_now().isAfter(_receiptExpiry!)) {
      return ReceiptActivationSuccess(
        expiryUtc: _receiptExpiry!,
        amountEtb: receipt.amount ?? 0,
        planDays: planDaysForAmount(receipt.amount) ?? 0,
        alreadyActive: true,
      );
    }
    if (_usedReceipts.contains(refHash)) {
      return const ReceiptActivationRejected(
        'This receipt has already been used to activate on this device. '
        'When your plan expires, pay again and paste the new receipt.',
      );
    }

    final check = evaluateActivationReceipt(receipt, now: _now());
    if (check is! ReceiptActivationAccepted) return check;
    final accepted = check;

    // Stack on top of the current entitlement (a code month plus a receipt
    // month simply add up; renewing early never loses paid days).
    final nowUtc = _now();
    final currentEnd = effectiveExpiry;
    final base = (currentEnd != null && currentEnd.isAfter(nowUtc))
        ? currentEnd
        : nowUtc;
    final newExpiry = base.add(Duration(days: accepted.planDays));

    _receiptExpiry = newExpiry;
    _receiptRefHash = refHash;
    _usedReceipts.add(refHash);
    try {
      await _store.write(
        _kReceiptKey,
        jsonEncode({
          'expiryMs': newExpiry.millisecondsSinceEpoch,
          'refHash': refHash,
          'amountEtb': accepted.amountEtb,
        }),
      );
      final used = _usedReceipts.toList();
      if (used.length > 200) used.removeRange(0, used.length - 200);
      _usedReceipts = used.toSet();
      await _store.write(_kUsedReceiptsKey, jsonEncode(used));
    } catch (_) {
      // Storage failed — the entitlement still holds for this session.
    }
    notifyListeners();
    return ReceiptActivationSuccess(
      expiryUtc: newExpiry,
      amountEtb: accepted.amountEtb,
      planDays: accepted.planDays,
      alreadyActive: false,
    );
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
