import 'package:flutter/foundation.dart';

import '../core/receipt_verify/models.dart';
import '../core/receipt_verify/parsers.dart';
import '../core/receipt_verify/extra_banks.dart';
import '../core/receipt_verify/verifier.dart';
import '../core/scan_input.dart';

/// Lifecycle of a verification attempt.
enum VerifyStatus { idle, verifying, done, error }

/// Central app state: selected bank, inputs, scan/URL resolution,
/// verification calls and the latest result. Exposed app-wide via `provider`.
///
/// All verification logic lives in the stylepos receipt verifier
/// (`core/receipt_verify`) — this controller only builds a [VerifyInput],
/// runs it and holds the [VerifyResult].
class VerifyController extends ChangeNotifier {
  VerifyController({
    Future<VerifyResult> Function(VerifyInput)? verifyFn,
    Future<VerifyResult> Function(VerifyInput)? extraVerifyFn,
  })  : _verifyFn = verifyFn ?? ReceiptVerifier.I.verify,
        _extraVerifyFn = extraVerifyFn ?? verifyExtraBank;

  final Future<VerifyResult> Function(VerifyInput input) _verifyFn;
  final Future<VerifyResult> Function(VerifyInput input) _extraVerifyFn;

  /// Link detection across the verbatim stylepos catalog AND the app-side
  /// extra banks (Wegagen, Amhara) — extra patterns first, hosts never
  /// overlap.
  UrlDetection? _detect(String input) =>
      detectExtraBankFromUrl(input) ?? detectBankFromUrl(input);

  // ------------------------------------------------------------------ state
  VerifyStatus status = VerifyStatus.idle;

  /// Bank chosen manually via the picker (null = auto from scan/link).
  BankInfo? manualBank;

  /// Bank auto-detected from the scanned QR or pasted receipt link.
  BankInfo? detectedBank;

  String reference = '';
  String accountNumber = '';
  String phoneNumber = '';

  /// Raw QR payload from the last scan when it must be passed to the
  /// verifier untouched (BOA encrypted slip QR — decrypted offline inside
  /// the verifier). Null when the reference alone carries the input.
  String? scannedQr;

  /// Bank id passed through to the verifier verbatim, bypassing the
  /// catalog — used for the retired `cbe-legacy` links so the verifier can
  /// show its dedicated guidance instead of a generic not-found.
  String? forcedBankId;

  /// Untouched Telebirr invoice from the last scan, kept when the shown
  /// reference had decoder junk stripped (`stripTrailingCeJunk`). When the
  /// cleaned reference comes back not-found, [verify] retries once with
  /// this raw value — in the rare case the removed letter was genuine,
  /// the raw invoice still verifies instead of dead-ending the user.
  /// Cleared as soon as the user edits the reference.
  String? rawScannedReference;

  VerifyResult? result;

  /// Generation counter for verification runs. Stopping (or restarting)
  /// a verification bumps it, so an in-flight [verify] recognizes it was
  /// abandoned and discards its result instead of clobbering state.
  int _verifyRun = 0;

  // -------------------------------------------------------------- accessors
  /// The bank whose fields/styling currently apply.
  BankInfo? get effectiveBank => manualBank ?? detectedBank;

  bool get isVerifying => status == VerifyStatus.verifying;

  bool get canVerify {
    if (isVerifying) return false;
    final bank = effectiveBank;
    if (bank == null && forcedBankId == null) return false;
    if (reference.trim().isEmpty && scannedQr == null) return false;
    if (scannedQr == null) {
      // BOA QR scans verify offline — no account suffix needed.
      if (bank != null && bank.accountDigits > 0 && accountNumber.trim().isEmpty) {
        return false;
      }
    }
    if (bank != null && bank.requiresPhone && phoneNumber.trim().isEmpty) {
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- mutation
  void setReference(String value) {
    reference = value;
    // The user took over the input — a previous scan no longer applies.
    scannedQr = null;
    forcedBankId = null;
    rawScannedReference = null;
    if (looksLikeUrl(value)) {
      final detected = _detect(value);
      final info = detected == null ? null : bankByIdAll(detected.bank);
      detectedBank = info;
      if (detected != null && info != null) {
        // Store the extracted token (like applyScan does) so the verifier
        // gets a clean reference — the field keeps showing the pasted link
        // until the next sync, but the verification itself uses the token.
        // Regression guard: handing the FULL URL to the extra-bank
        // verifier used to make every pasted Wegagen/Amhara/Awash link
        // fail against the bank API.
        reference = detected.reference;
        if (detected.account != null) {
          accountNumber = detected.account!;
        }
      }
    } else {
      detectedBank = null;
    }
    // Editing inputs clears a finished (failed) attempt.
    if (status == VerifyStatus.done && result != null && !result!.ok) {
      status = VerifyStatus.idle;
      result = null;
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

  void selectBank(BankInfo? bank) {
    manualBank = bank;
    if (bank == null) {
      // Back to auto: re-detect from the current input.
      final detected = looksLikeUrl(reference) ? _detect(reference) : null;
      final info = detected == null ? null : bankByIdAll(detected.bank);
      detectedBank = info;
      if (detected != null && info != null) reference = detected.reference;
    }
    notifyListeners();
  }

  /// Applies a scanned QR payload (or any raw scanned text).
  ///
  /// Resolution mirrors the stylepos verifier's own input rules:
  ///   * receipt links auto-detect the bank and extract the reference,
  ///   * BOA slip QRs are flagged for offline decryption by the verifier,
  ///   * Telebirr SuperApp QRs are decoded to the invoice number here,
  ///   * anything else is kept as a plain reference for the user to pair
  ///     with a bank pick — scanning never dead-ends.
  void applyScan(String payload) {
    final raw = payload.trim();
    status = VerifyStatus.idle;
    result = null;
    manualBank = null;
    scannedQr = null;
    forcedBankId = null;
    rawScannedReference = null;

    if (looksLikeUrl(raw)) {
      final detected = _detect(raw);
      if (detected != null) {
        if (detected.bank == 'cbe-legacy') {
          // Keep the verifier's dedicated retired-endpoint guidance.
          forcedBankId = detected.bank;
          reference = detected.reference;
          accountNumber = detected.account ?? '';
          detectedBank = null;
          notifyListeners();
          return;
        }
        detectedBank = bankByIdAll(detected.bank);
        reference = detected.reference;
        accountNumber = detected.account ?? '';
        notifyListeners();
        return;
      }
      // Unknown link — the verifier explains it after a bank pick.
      reference = raw;
      detectedBank = null;
      notifyListeners();
      return;
    }

    // BOA encrypted slip QR — the verifier decrypts it offline.
    final boa = decryptBoaQr(raw);
    if (boa != null && (boa.reference?.isNotEmpty ?? false)) {
      detectedBank = bankById('boa');
      reference = '';
      accountNumber = '';
      scannedQr = raw;
      notifyListeners();
      return;
    }

    // Telebirr SuperApp QR — base64 → hex → invoice number. Decoder junk
    // ('c'/'e' read while the QR leaves the frame) lands INSIDE the decoded
    // blob right after the invoice and gets swallowed by the invoice run,
    // so the extracted reference ends with a bogus 'C' — strip it, and
    // keep the untouched invoice for the raw-scan retry net in [verify].
    final invoice = extractTelebirrInvoiceFromQr(raw);
    if (invoice != null) {
      detectedBank = bankById('telebirr');
      final cleaned = stripTrailingCeJunk(invoice);
      rawScannedReference = cleaned == invoice ? null : invoice;
      reference = cleaned;
      accountNumber = '';
      notifyListeners();
      return;
    }

    // Plain reference — the user pairs it with a bank.
    reference = raw;
    detectedBank = null;
    notifyListeners();
  }

  void reset() {
    status = VerifyStatus.idle;
    result = null;
    notifyListeners();
  }

  /// Full form reset ("Verify another receipt").
  void resetAll() {
    status = VerifyStatus.idle;
    result = null;
    reference = '';
    accountNumber = '';
    phoneNumber = '';
    manualBank = null;
    detectedBank = null;
    scannedQr = null;
    forcedBankId = null;
    rawScannedReference = null;
    notifyListeners();
  }

  // -------------------------------------------------------------- verification
  /// Aborts an in-flight verification and returns the form to idle.
  ///
  /// The HTTP request itself cannot be interrupted, but the late result is
  /// discarded: when the abandoned [verify] call finally lands it sees its
  /// generation was superseded and exits without touching any state — so
  /// no result screen, no history entry, no spinner.
  void stopVerify() {
    if (status != VerifyStatus.verifying) return;
    _verifyRun++;
    status = VerifyStatus.idle;
    notifyListeners();
  }

  /// Runs the verification through the stylepos verifier.
  ///
  /// Returns the [VerifyResult] (receipt OR failure — failures carry
  /// user-ready messages and tips), or null when the attempt was abandoned
  /// via [stopVerify] (or superseded by a newer one).
  Future<VerifyResult?> verify() async {
    final bank = effectiveBank;
    final bankId = forcedBankId ?? bank?.id;
    if (bankId == null || !canVerify) return null;

    final run = ++_verifyRun;
    status = VerifyStatus.verifying;
    notifyListeners();

    VerifyResult res;
    try {
      // App-side extra banks (Wegagen, Amhara) route to their own verifier;
      // everything else goes through the verbatim stylepos verifier.
      final fn = isExtraBank(bankId) ? _extraVerifyFn : _verifyFn;
      res = await fn(VerifyInput(
        bankId: bankId,
        reference: reference.trim(),
        account: accountNumber.trim().isEmpty ? null : accountNumber.trim(),
        phone: phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
        qrData: scannedQr?.trim(),
      ));
    } catch (_) {
      res = VerifyResult.failed(
        const VerifyFailure(
          VerifyErrorKind.unreadable,
          'Something went wrong while checking this receipt.',
          tips: ['Try again — the bank may be busy.'],
        ),
        0,
      );
    }
    if (run != _verifyRun) return null; // stopped while in flight

    // Retry net for sanitized Telebirr scans: the shown reference had
    // decoder junk stripped (`stripTrailingCeJunk`). When the bank answers
    // a definitive not-found for it, retry once with the untouched invoice
    // — if the removed letter was genuine, the raw value still verifies
    // instead of dead-ending the user.
    final rawInvoice = rawScannedReference;
    if (!res.ok &&
        res.failure?.kind == VerifyErrorKind.notFound &&
        rawInvoice != null &&
        rawInvoice.isNotEmpty &&
        rawInvoice != reference.trim()) {
      try {
        final retry = await (isExtraBank(bankId) ? _extraVerifyFn : _verifyFn)(
          VerifyInput(
            bankId: bankId,
            reference: rawInvoice,
          account: accountNumber.trim().isEmpty ? null : accountNumber.trim(),
          phone: phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
        ));
        if (run != _verifyRun) return null; // stopped during the retry
        if (retry.ok) {
          res = retry;
          reference = rawInvoice; // show the value that actually verified
          rawScannedReference = null;
        }
      } catch (_) {
        // The retry is best-effort; keep the first result.
      }
    }

    result = res;
    status = VerifyStatus.done;
    notifyListeners();
    return res;
  }
}
