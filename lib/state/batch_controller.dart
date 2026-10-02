import 'package:flutter/foundation.dart';

import '../core/batch_parse.dart';
import '../core/fraud_advisories.dart';
import '../core/receipt_verify/models.dart';
import '../core/receipt_verify/extra_banks.dart';
import '../core/receipt_verify/verifier.dart';
import '../core/verify_history.dart';

/// Lifecycle of one row inside a batch run.
enum BatchRowStatus { pending, running, verified, failed, skipped }

/// One checkable row of a batch run — the runtime twin of [BatchLine]
/// with its live status and result.
class BatchRow {
  final String id;
  final String input;
  final String reference;

  /// Mutable only through [BatchController.applyBank] — the legitimate
  /// "pick a bank after pasting" path.
  String? bankId;
  final String? account;
  final String? scannedQr;
  final BatchSkipReason? skipReason;

  BatchRowStatus status;
  VerifyResult? result;

  /// Local anti-fraud advisory (stale receipt / duplicate of an earlier
  /// check) merged onto the row after a successful check.
  String? advisory;

  BatchRow({
    required this.id,
    required this.input,
    required this.reference,
    this.bankId,
    this.account,
    this.scannedQr,
    this.skipReason,
    BatchRowStatus? initialStatus,
  }) : status = initialStatus ??
            (skipReason != null ? BatchRowStatus.skipped : BatchRowStatus.pending);

  bool get isSkippedNow =>
      skipReason != null || status == BatchRowStatus.skipped;

  /// Bank name for display; falls back to the raw id.
  String get bankName =>
      bankId == null ? '' : (bankByIdAll(bankId!)?.name ?? bankId!);
}

/// Runs a batch of references through the same verifiers as the single
/// flow — sequentially, one attempt per row, strictly on-device.
///
/// Design points (mirroring the single flow's guarantees):
///   * attempts are charged right before each check, never for skipped
///     rows — [consumeAttempt] returning false (paywall declined / no
///     attempts left) stops the run without burning anything,
///   * [stop] aborts the remaining rows; the row in flight still lands
///     (its result is real and recorded),
///   * every completed row — verified OR failed — is recorded in the
///     local history, exactly like a single check,
///   * the anti-fraud advisories (duplicate of an earlier check, stale
///     receipt) run per verified row against the history BEFORE that row
///     is recorded, so a row can never flag itself.
class BatchController extends ChangeNotifier {
  BatchController({
    Future<VerifyResult> Function(VerifyInput)? verifyFn,
    Future<VerifyResult> Function(VerifyInput)? extraVerifyFn,
    DateTime Function()? now,
  })  : _verifyFn = verifyFn ?? ReceiptVerifier.I.verify,
        _extraVerifyFn = extraVerifyFn ?? verifyExtraBank,
        _now = now ?? (() => DateTime.now());

  final Future<VerifyResult> Function(VerifyInput input) _verifyFn;
  final Future<VerifyResult> Function(VerifyInput input) _extraVerifyFn;
  final DateTime Function() _now;

  List<BatchRow> _rows = const [];
  bool _running = false;
  bool _stopRequested = false;

  /// Generation counter — a stopped/finished run cannot be clobbered by
  /// a late in-flight row, and a new parse supersedes old results.
  int _run = 0;

  // ---------------------------------------------------------------- accessors

  /// Unmodifiable view of the current rows.
  List<BatchRow> get rows => List.unmodifiable(_rows);

  bool get isRunning => _running;

  bool get hasRows => _rows.isNotEmpty;

  int get total => _rows.length;

  int get chargeableCount =>
      _rows.where((r) => !r.isSkippedNow).length;

  int get pendingCount => _rows
      .where((r) => r.status == BatchRowStatus.pending)
      .length;

  int get verifiedCount =>
      _rows.where((r) => r.status == BatchRowStatus.verified).length;

  int get failedCount =>
      _rows.where((r) => r.status == BatchRowStatus.failed).length;

  int get skippedCount =>
      _rows.where((r) => r.status == BatchRowStatus.skipped).length;

  /// True when every chargeable row finished (verified or failed).
  bool get isComplete =>
      hasRows &&
      !_running &&
      _rows.every((r) =>
          r.isSkippedNow ||
          r.status == BatchRowStatus.verified ||
          r.status == BatchRowStatus.failed);

  /// True when a run was stopped with rows still pending.
  bool get isStoppedWithPending => !_running && _stopRequested && pendingCount > 0;

  // ---------------------------------------------------------------- mutation

  /// Loads fresh rows from [lines], replacing everything (a new paste is
  /// a new batch). Any in-flight run is superseded by generation bump.
  void load(List<BatchLine> lines) {
    _run++;
    _running = false;
    _stopRequested = false;
    _rows = [
      for (var i = 0; i < lines.length; i++)
        BatchRow(
          id: 'b$i-${DateTime.now().microsecondsSinceEpoch}',
          input: lines[i].input,
          reference: lines[i].effectiveReference,
          bankId: lines[i].bankId,
          account: lines[i].account,
          scannedQr: lines[i].scannedQr,
          skipReason: lines[i].skipReason,
        ),
    ];
    notifyListeners();
  }

  /// Re-binds the batch bank to rows that had none (the user picked a
  /// bank after pasting). Skipped rows and rows carrying their own bank
  /// (links / QR payloads) are untouched.
  void applyBank(BankInfo? bank) {
    if (bank == null) return;
    var changed = false;
    for (final row in _rows) {
      if (row.isSkippedNow) continue;
      if (row.scannedQr != null) continue;
      if (row.bankId == null) {
        row.bankId = bank.id;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Asks the runner to stop after the row in flight. The finished row
  /// still records; everything still pending stays pending.
  void stop() {
    if (!_running) return;
    _stopRequested = true;
    notifyListeners();
  }

  /// Runs every pending row, in order, one at a time.
  ///
  /// [consumeAttempt] is awaited right before each check — return false
  /// to stop (no attempt used). [history] receives every completed row.
  /// The note builders keep this controller localization-free.
  Future<void> run({
    required VerifyHistory history,
    required Future<bool> Function() consumeAttempt,
    required String Function(String when) duplicateNote,
    required String Function(int days) staleNote,
  }) async {
    if (_running) return;
    if (pendingCount == 0) return;
    _running = true;
    _stopRequested = false;
    final gen = _run;
    notifyListeners();

    for (final row in _rows) {
      if (gen != _run) return; // superseded by a new load
      if (row.status != BatchRowStatus.pending) continue;

      if (_stopRequested) break;

      // Charge BEFORE the check — attempts are spent on attempts, not
      // successes. A refused charge stops the batch with nothing burned.
      bool charged;
      try {
        charged = await consumeAttempt();
      } catch (_) {
        charged = false;
      }
      if (gen != _run) return;
      if (!charged) break;

      final bankId = row.bankId ?? '';
      if (bankId.isEmpty && row.scannedQr == null) {
        // Should not happen (the screen gates on this) — fail safe.
        row.status = BatchRowStatus.skipped;
        notifyListeners();
        continue;
      }

      row.status = BatchRowStatus.running;
      notifyListeners();

      VerifyResult res;
      try {
        final fn = isExtraBank(bankId) ? _extraVerifyFn : _verifyFn;
        final acct = row.account?.trim();
        res = await fn(VerifyInput(
          bankId: bankId,
          reference: row.reference,
          account: (acct == null || acct.isEmpty) ? null : acct,
          qrData: row.scannedQr,
        ));
      } catch (_) {
        res = VerifyResult.failed(
          const VerifyFailure(
            VerifyErrorKind.unreadable,
            'Something went wrong while checking this receipt.',
          ),
          0,
        );
      }
      if (gen != _run) return; // stopped while in flight — discard

      row.result = res;
      row.status = res.ok ? BatchRowStatus.verified : BatchRowStatus.failed;

      // Anti-fraud advisories for verified rows — computed BEFORE the
      // row is recorded so it can never flag itself.
      if (res.ok) {
        try {
          final receipt = res.receipt!;
          final ref = receipt.reference.isNotEmpty
              ? receipt.reference
              : row.reference;
          row.advisory = duplicateAdvisory(
            entries: history.entries,
            bankId: bankId,
            reference: ref,
            now: _now(),
            note: duplicateNote,
          );
          row.advisory ??= freshnessAdvisory(
            receiptDate: receipt.date,
            now: _now(),
            note: staleNote,
          );
        } catch (_) {
          row.advisory = null; // advisories must never break a batch
        }
      }

      // Record in local history — verified AND failed, like the single
      // flow. History must never block a batch.
      try {
        await history.record(
          res,
          bankId: bankId,
          bankName: res.receipt?.bankName ?? row.bankName,
          referenceFallback: row.reference,
        );
      } catch (_) {}

      notifyListeners();
    }

    if (gen != _run) return;
    _running = false;
    notifyListeners();
  }

  /// Clears all results and rows (called when the screen closes or the
  /// user starts over).
  void reset() {
    _run++;
    _running = false;
    _stopRequested = false;
    _rows = const [];
    notifyListeners();
  }
}
