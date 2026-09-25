import 'package:flutter/foundation.dart';

import '../core/banks_registry.dart';
import '../core/models.dart';
import '../core/native/verifier.dart';

/// Lifecycle of a verification attempt.
enum VerifyStatus { idle, verifying, done, error }

/// Central app state: selected bank, inputs, auto-detection, verification
/// calls and the latest result. Exposed app-wide via `provider`.
class VerifyController extends ChangeNotifier {
  VerifyController({VerifyEngine? engine})
      : _engine = engine ?? NativeVerifier();

  final VerifyEngine _engine;

  // ------------------------------------------------------------------ state
  VerifyStatus status = VerifyStatus.idle;

  /// Bank chosen manually via the picker (null = auto from reference).
  ChekiBank? manualBank;

  /// Bank auto-detected from the typed reference / scanned QR.
  ChekiBank? detectedBank;

  /// True when the user is on the "cbe-new" QR receipt flow.
  bool usingCbeNew = false;

  String reference = '';
  String accountNumber = '';
  String phoneNumber = '';

  VerifyResult? result;
  String? errorMessage;

  double? lastDurationMs;

  // -------------------------------------------------------------- accessors
  /// The bank whose fields/styling currently apply.
  ChekiBank? get effectiveBank => manualBank ?? detectedBank;

  bool get isVerifying => status == VerifyStatus.verifying;

  bool get canVerify {
    if (isVerifying) return false;
    if (reference.trim().isEmpty) return false;
    final bank = effectiveBank;
    if (bank == null) return false;
    // CBE-new QR receipts verify with the receipt ID alone.
    if (!usingCbeNew &&
        bank.requiresAccount &&
        bank.accountDigits != null &&
        accountNumber.trim().length < bank.accountDigits!) {
      return false;
    }
    if (bank.requiresPhone && phoneNumber.trim().isEmpty) return false;
    return true;
  }

  // ---------------------------------------------------------------- mutation
  void setReference(String value) {
    reference = value;
    // Reset manual selection whenever the user edits the reference so that
    // auto-detect gets a chance (matches the web behavior).
    if (manualBank != null && value.trim().isEmpty) {
      manualBank = null;
    }
    detectedBank = _detectBank(value);
    usingCbeNew = detectedBank != null &&
        RegExp(r'^[0-9a-f]{12}$', caseSensitive: false)
            .hasMatch(reference.trim());
    // Editing inputs clears a finished (failed) attempt.
    if (status == VerifyStatus.done && result != null && !result!.isVerified) {
      status = VerifyStatus.idle;
      result = null;
      errorMessage = null;
    }
    notifyListeners();
  }

  void setAccount(String value) {
    accountNumber = value;
    notifyListeners();
  }

  void setPhone(String value) {
    phoneNumber = value;
    notifyListeners();
  }

  void selectBank(ChekiBank? bank) {
    manualBank = bank;
    usingCbeNew = false;
    if (bank == null) {
      detectedBank = _detectBank(reference);
      usingCbeNew = detectedBank != null &&
          RegExp(r'^[0-9a-f]{12}$', caseSensitive: false)
              .hasMatch(reference.trim());
    }
    notifyListeners();
  }

  /// Applies a scanned/typed detection (from QR scan or paste).
  ///
  /// [detection.bank] is null for generic payloads — we keep the reference
  /// and let the caller open the bank picker.
  void applyDetection(BankDetection detection) {
    reference = detection.reference;
    accountNumber = detection.accountNumber ?? '';
    manualBank = null;
    usingCbeNew = detection.bank == kCbeNewId;
    detectedBank = detection.bank == null
        ? null
        : bankById(detection.bank == kCbeNewId ? 'cbe' : detection.bank!);
    status = VerifyStatus.idle;
    errorMessage = null;
    notifyListeners();
  }

  void reset() {
    status = VerifyStatus.idle;
    result = null;
    errorMessage = null;
    notifyListeners();
  }

  /// Full form reset ("Verify another receipt").
  void resetAll() {
    status = VerifyStatus.idle;
    result = null;
    errorMessage = null;
    reference = '';
    accountNumber = '';
    phoneNumber = '';
    manualBank = null;
    detectedBank = null;
    usingCbeNew = false;
    notifyListeners();
  }

  // -------------------------------------------------------------- verification
  /// Runs the verification natively on the device.
  ///
  /// ALWAYS resolves to a [VerifyResult]: genuine failures (receipt not
  /// found, bank unreachable) become a failed result so the result screen
  /// can show them — no silent failures.
  Future<VerifyResult?> verify() async {
    final bank = effectiveBank;
    if (bank == null || !canVerify) return null;

    final engineBank = usingCbeNew ? kCbeNewId : bank.id;
    status = VerifyStatus.verifying;
    errorMessage = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    VerifyResult res;
    try {
      res = await _engine.verify(
        bank: engineBank,
        reference: reference.trim(),
        accountNumber: usingCbeNew ? null : accountNumber.trim(),
        phoneNumber: phoneNumber.trim(),
      );
    } catch (e) {
      stopwatch.stop();
      lastDurationMs = stopwatch.elapsedMilliseconds.toDouble();
      res = VerifyResult(
        success: false,
        verified: false,
        bank: engineBank,
        reference: reference.trim(),
        error: 'Something went wrong. Check your connection and retry.',
      );
      errorMessage = res.error;
    }
    result = res;
    status = VerifyStatus.done;
    lastDurationMs = res.durationMs?.toDouble();
    notifyListeners();
    return res;
  }

  ChekiBank? _detectBank(String value) {
    final detection = detectBankFromUrl(value) ?? _detectPlain(value);
    if (detection == null || detection.bank == null) return null;
    return bankById(detection.bank == kCbeNewId ? 'cbe' : detection.bank!);
  }

  BankDetection? _detectPlain(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    // CBE new QR receipts encode a bare receipt ID (12 hex chars).
    if (RegExp(r'^[0-9a-f]{12}$', caseSensitive: false).hasMatch(trimmed)) {
      return BankDetection(bank: kCbeNewId, reference: trimmed);
    }
    final byRef = detectBankFromReference(trimmed);
    if (byRef != null) {
      return BankDetection(bank: byRef.bank.id, reference: byRef.reference);
    }
    return null;
  }

  @override
  void dispose() {
    final engine = _engine;
    if (engine is NativeVerifier) engine.dispose();
    super.dispose();
  }
}
