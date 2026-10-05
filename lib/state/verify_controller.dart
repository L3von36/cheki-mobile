import 'package:flutter/foundation.dart';

import '../core/receipt_verify/models.dart';
import '../core/receipt_verify/parsers.dart';
import '../core/receipt_verify/extra_banks.dart';
import '../core/receipt_verify/geo_relay.dart';
import '../core/receipt_verify/reference_shape.dart';
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

  /// Input detection across the verbatim stylepos catalog AND the app-side
  /// extra banks (Wegagen, Amhara, Awash) — extra patterns first, hosts
  /// never overlap. Works on bare links, links embedded in SMS-style prose
  /// (the Wegagen receipt QR) and the Amhara QR's bare JSON payload.
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

  /// Banks whose receipts plausibly carry the current bare reference's
  /// shape (see `bankCandidatesForReference`), most likely first. Empty
  /// when the reference came from a link/QR (those identify their bank
  /// outright). The verify controller walks this list after a definitive
  /// not-found so a wrong bank pick self-heals instead of dead-ending.
  List<String> shapeCandidates = const [];

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
    // Detect on ANY text: a bare link, a link embedded in SMS prose, or the
    // Amhara QR's bare JSON payload. Not gated on looksLikeUrl — the
    // Wegagen receipt QR carries prose, and missing its embedded link used
    // to leave the bank undetected with a paragraph in the field.
    final detected = _detect(value);
    final info = detected == null ? null : bankByIdAll(detected.bank);
    detectedBank = info;
    if (detected != null && info != null) {
      // Store the extracted token (like applyScan does) so the verifier
      // gets a clean reference — the field keeps showing the pasted text
      // until the next sync, but the verification itself uses the token.
      // Regression guard: handing the FULL URL to the extra-bank
      // verifier used to make every pasted Wegagen/Amhara/Awash link
      // fail against the bank API.
      reference = detected.reference;
      if (detected.account != null) {
        accountNumber = detected.account!;
      }
    }
    // Editing inputs clears a finished (failed) attempt.
    if (status == VerifyStatus.done && result != null && !result!.ok) {
      status = VerifyStatus.idle;
      result = null;
    }
    // Shape candidates only exist for BARE references — a link or QR
    // identified its bank outright, so nothing is left to guess there.
    shapeCandidates = (detected != null || looksLikeUrl(reference))
        ? const []
        : bankCandidatesForReference(reference);
    _autoDetectFromShape(reference);
    notifyListeners();
  }

  /// Pre-selects the bank for a bare reference whose shape belongs to
  /// exactly one supported bank (Telebirr invoice, Zemen ETTB…, Dashen
  /// digits, a CBE receipt code…). Ambiguous shapes (FT… could be
  /// Amhara's, BOA's or CBE Birr's) stay unselected — the picker decides
  /// and the wrong-bank retry net in [verify] covers a wrong guess.
  void _autoDetectFromShape(String value) {
    if (manualBank != null || detectedBank != null) return;
    final v = value.trim();
    if (v.isEmpty || v.contains('/') || looksLikeUrl(v)) return;
    final id = autoDetectBankForReference(v);
    if (id != null) detectedBank = bankByIdAll(id);
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
      // Back to auto: re-detect from the current input — any text shape the
      // detectors understand, not just links.
      final detected = _detect(reference);
      final info = detected == null ? null : bankByIdAll(detected.bank);
      detectedBank = info;
      if (detected != null && info != null) reference = detected.reference;
      shapeCandidates = (detected != null || looksLikeUrl(reference))
          ? const []
          : bankCandidatesForReference(reference);
      _autoDetectFromShape(reference);
    }
    notifyListeners();
  }

  /// Applies a scanned QR payload (or any raw scanned text).
  ///
  /// Resolution mirrors the stylepos verifier's own input rules, extended
  /// with the extra banks' text shapes:
  ///   * receipt links — bare, or embedded in SMS-style prose (the Wegagen
  ///     receipt QR) — auto-detect the bank and extract the reference,
  ///   * the Amhara web receipt's QR is a BARE JSON payload
  ///     (`{"transactionId":"FT…",…}`) and detects the same way,
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
    // Cleared here; the plain-reference path below re-arms it. Link / QR
    // payloads identify their bank outright — nothing left to guess.
    shapeCandidates = const [];

    // Receipt markers auto-detect the bank — on any text shape, not just
    // inputs that start with http://.
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
    if (looksLikeUrl(raw)) {
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

    // Plain reference — the user pairs it with a bank (unless its shape
    // belongs to exactly one bank, which pre-selects it).
    reference = raw;
    detectedBank = null;
    shapeCandidates = bankCandidatesForReference(raw);
    _autoDetectFromShape(raw);
    notifyListeners();
  }

  /// Merges a local anti-fraud advisory (stale receipt / duplicate check)
  /// into the current successful result's note before the result screen
  /// shows. No-op when the latest result is not a successful receipt.
  void applyAdvisoryNote(String advisory) {
    final res = result;
    final receipt = res?.receipt;
    if (res == null || !res.ok || receipt == null) return;
    final existing = receipt.note;
    final merged = existing == null || existing.isEmpty
        ? advisory
        : '$existing · $advisory';
    result = VerifyResult.receipt(
      ReceiptData(
        verified: receipt.verified,
        bankCode: receipt.bankCode,
        bankName: receipt.bankName,
        reference: receipt.reference,
        senderName: receipt.senderName,
        senderAccount: receipt.senderAccount,
        receiverName: receipt.receiverName,
        receiverAccount: receipt.receiverAccount,
        amount: receipt.amount,
        currency: receipt.currency,
        date: receipt.date,
        branch: receipt.branch,
        reason: receipt.reason,
        transactionType: receipt.transactionType,
        transactionStatus: receipt.transactionStatus,
        invoiceNumber: receipt.invoiceNumber,
        bankAccountNumber: receipt.bankAccountNumber,
        bankAccountName: receipt.bankAccountName,
        note: merged,
        fromQr: receipt.fromQr,
      ),
      res.durationMs,
    );
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
    shapeCandidates = const [];
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

  /// Runs ONE verification through the right channel: geo-blocked banks
  /// (Telebirr / M-Pesa) try the Worker relay first when the device looks
  /// abroad (or on web, where the browser blocks the direct call), and
  /// whenever the relay has no definitive answer fall back to the regular
  /// path — extra banks to their verifier, everything else to the verbatim
  /// stylepos verifier.
  Future<VerifyResult> _invoke(VerifyInput input) async {
    if (shouldUseGeoRelay(input.bankId)) {
      final relayed = await verifyViaGeoRelay(input);
      if (relayed != null) return relayed;
    }
    return (isExtraBank(input.bankId) ? _extraVerifyFn : _verifyFn)(input);
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
      res = await _invoke(VerifyInput(
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
        final retry = await _invoke(VerifyInput(
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

    // Wrong-bank net: a bare reference only HINTS at its bank (an FT
    // number may be Amhara's, BOA's or CBE Birr's, a mixed-case token
    // CBE's). When the chosen bank answers a definitive not-found,
    // silently ask the other banks whose receipts carry this shape — one
    // of them may own it. Only a not-found triggers the net: network
    // errors and anti-bot gates keep their original message, and a
    // failed alternative NEVER replaces the primary answer — only a
    // verified receipt does.
    if (!res.ok &&
        res.failure?.kind == VerifyErrorKind.notFound &&
        shapeCandidates.isNotEmpty) {
      for (final altId in shapeCandidates) {
        if (altId == bankId) continue;
        final alt = bankByIdAll(altId);
        if (alt == null) continue;
        // Candidates the form could not fill in are skipped — BOA needs
        // the receiver's last-5, CBE Birr the payer phone.
        if (alt.accountDigits > 0 && accountNumber.trim().isEmpty) continue;
        if (alt.requiresPhone && phoneNumber.trim().isEmpty) continue;
        VerifyResult altRes;
        try {
          altRes = await _invoke(VerifyInput(
            bankId: altId,
            reference: reference.trim(),
            account:
                accountNumber.trim().isEmpty ? null : accountNumber.trim(),
            phone: phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
          ));
        } catch (_) {
          continue; // a broken alternative must not mask the answer
        }
        if (run != _verifyRun) return null; // stopped while in flight
        if (altRes.ok) {
          res = altRes;
          // The form must show the bank that actually verified.
          final altBank = bankByIdAll(altId);
          if (altBank != null) {
            if (manualBank != null) {
              manualBank = altBank;
            } else {
              detectedBank = altBank;
            }
          }
          break;
        }
      }
    }

    // Shape-aware escape hatch: candidates skipped for missing account /
    // phone fields are the user's next move — name them instead of
    // dead-ending on a bare "not found".
    if (!res.ok &&
        res.failure?.kind == VerifyErrorKind.notFound &&
        shapeCandidates.isNotEmpty &&
        scannedQr == null) {
      final skipped = <String>[];
      for (final altId in shapeCandidates) {
        if (altId == bankId) continue;
        final alt = bankByIdAll(altId);
        if (alt == null) continue;
        if ((alt.accountDigits > 0 && accountNumber.trim().isEmpty) ||
            (alt.requiresPhone && phoneNumber.trim().isEmpty)) {
          skipped.add(alt.name);
        }
      }
      if (skipped.isNotEmpty) {
        final f = res.failure!;
        res = VerifyResult.failed(
          VerifyFailure(
            f.kind,
            f.message,
            tips: [
              ...f.tips,
              'If this receipt is actually from ${skipped.join(' or ')}, '
                  'pick that bank — it needs a detail you can enter there.',
            ],
          ),
          res.durationMs,
        );
      }
    }

    result = res;
    status = VerifyStatus.done;
    notifyListeners();
    return res;
  }
}
