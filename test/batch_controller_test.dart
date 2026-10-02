import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/batch_parse.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/batch_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.12.0 batch runner: sequential on-device checks, one attempt per
/// row charged right before its check, stop leaves rows pending, every
/// completed row lands in local history.

VerifyResult _ok(String reference, {double amount = 250}) =>
    VerifyResult.receipt(
      ReceiptData(
        verified: true,
        bankCode: 'telebirr',
        bankName: 'Telebirr',
        reference: reference,
        senderName: 'ABEBE',
        receiverName: 'MAHTEM SHOP',
        amount: amount,
        currency: 'ETB',
        date: '2026-10-02 10:00:00',
      ),
      12,
    );

VerifyResult _fail(String reference) => VerifyResult.failed(
      VerifyFailure(VerifyErrorKind.notFound, 'Receipt not found'),
      8,
    );

BatchController _controller({
  required Future<VerifyResult> Function(VerifyInput) verifyFn,
}) {
  return BatchController(
    verifyFn: verifyFn,
    extraVerifyFn: verifyFn,
  );
}

Future<VerifyHistory> _history() async {
  SharedPreferences.setMockInitialValues({});
  return VerifyHistory();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('runs rows sequentially, charges per row, records everything',
      () async {
    final calls = <String>[];
    final controller = _controller(
      verifyFn: (input) async {
        calls.add(input.reference);
        return input.reference.contains('BAD')
            ? _fail(input.reference)
            : _ok(input.reference);
      },
    );

    controller.load(parseBatchLines(
      'CHQ261Z4AB2C\nCHQ261Z4AB3D\nCHQ261Z4AB4E\n',
      bank: null,
    ));
    // telebirr-prefix bare numbers auto-detect their bank.
    expect(controller.chargeableCount, 3);

    var consumed = 0;
    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async {
        consumed++;
        return true;
      },
      duplicateNote: (_) => 'dup',
      staleNote: (_) => 'stale',
    );

    expect(calls, ['CHQ261Z4AB2C', 'CHQ261Z4AB3D', 'CHQ261Z4AB4E']);
    expect(consumed, 3);
    expect(controller.verifiedCount, 3);
    expect(controller.failedCount, 0);
    expect(controller.isComplete, isTrue);
    expect(history.length, 3); // verified AND failed both recorded
  });

  test('a failed row keeps the batch going', () async {
    final controller = _controller(
      verifyFn: (input) async => _fail(input.reference),
    );
    controller.load(parseBatchLines('CHQ261Z4AB2C\nCHQ261Z4AB3D'));
    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async => true,
      duplicateNote: (_) => 'dup',
      staleNote: (_) => 'stale',
    );
    expect(controller.failedCount, 2);
    expect(controller.verifiedCount, 0);
    expect(controller.isComplete, isTrue);
  });

  test('stop() mid-run leaves the remaining rows pending and lets the '
      'row in flight finish', () async {
    final calls = <String>[];
    late final BatchController controller;
    controller = BatchController(
      verifyFn: (input) async {
        calls.add(input.reference);
        if (input.reference == 'CHQ261Z4AB3D') {
          controller.stop(); // stop while row 2 is in flight
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return _ok(input.reference);
      },
      extraVerifyFn: (input) async => _fail(input.reference),
    );
    controller.load(parseBatchLines(
      'CHQ261Z4AB2C\nCHQ261Z4AB3D\nCHQ261Z4AB4E',
    ));

    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async => true,
      duplicateNote: (_) => 'dup',
      staleNote: (_) => 'stale',
    );

    expect(calls, ['CHQ261Z4AB2C', 'CHQ261Z4AB3D']); // row 3 never ran
    expect(controller.verifiedCount, 2);
    expect(controller.pendingCount, 1);
    expect(controller.isStoppedWithPending, isTrue);
    expect(controller.isComplete, isFalse);
  });

  test('a refused charge stops the batch before the check — nothing '
      'beyond the refusal is burned', () async {
    var calls = 0;
    final controller = _controller(
      verifyFn: (input) async {
        calls++;
        return _ok(input.reference);
      },
    );
    controller.load(parseBatchLines('CHQ261Z4AB2C\nCHQ261Z4AB3D'));

    var charges = 0;
    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async {
        charges++;
        return charges <= 1; // second row: refused
      },
      duplicateNote: (_) => 'dup',
      staleNote: (_) => 'stale',
    );

    expect(calls, 1);
    expect(controller.verifiedCount, 1);
    expect(controller.pendingCount, 1);
  });

  test('duplicate advisory attaches for a reference verified here '
      'before, computed before the row is recorded', () async {
    final controller = _controller(
      verifyFn: (input) async => _ok(input.reference),
    );
    controller.load(parseBatchLines('CHQ261Z4AB2C'));

    final history = await _history();
    // Pre-existing verified entry from 10 minutes ago.
    final now = DateTime.now();
    await history.add(HistoryEntry(
      id: 'old',
      bankId: 'telebirr',
      bankName: 'Telebirr',
      reference: 'CHQ261Z4AB2C',
      verifiedAt: now.subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      status: 'verified',
    ));

    await controller.run(
      history: history,
      consumeAttempt: () async => true,
      duplicateNote: (when) => 'DUP:$when',
      staleNote: (days) => 'STALE:$days',
    );

    expect(controller.rows.single.advisory, startsWith('DUP:'));
  });

  test('stale-receipt advisory attaches for an old receipt date',
      () async {
    final controller = BatchController(
      verifyFn: (input) async => VerifyResult.receipt(
        ReceiptData(
          verified: true,
          bankCode: 'telebirr',
          bankName: 'Telebirr',
          reference: input.reference,
          amount: 100,
          currency: 'ETB',
          // 5 days old — freshnessAdvisory fires.
          date: DateTime.now()
              .subtract(const Duration(days: 5))
              .toIso8601String(),
        ),
        5,
      ),
      extraVerifyFn: (input) async => _fail(input.reference),
      now: () => DateTime.now(),
    );
    controller.load(parseBatchLines('CHQ261Z4AB2C'));

    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async => true,
      duplicateNote: (when) => 'DUP',
      staleNote: (days) => 'STALE:$days',
    );

    expect(controller.rows.single.advisory, 'STALE:5');
  });

  test('applyBank re-binds pending plain rows but never touches link '
      'rows or skipped rows', () {
    final controller = _controller(
      verifyFn: (input) async => _ok(input.reference),
    );
    controller.load(parseBatchLines(
      'FT26140P01YB\n' // plain — needs bank
      'https://mbreciept.cbe.com.et/AB12CD34\n' // link — has bank
      'CHQ261Z4AB2C\n' // telebirr auto-detect
      'CHQ261Z4AB2C', // duplicate — skipped
    ));

    controller.applyBank(bankById('dashen'));

    final rows = controller.rows;
    expect(rows[0].bankId, 'dashen');
    expect(rows[1].bankId, 'cbe'); // untouched
    expect(rows[2].bankId, 'telebirr'); // untouched
    expect(rows[3].isSkippedNow, isTrue); // untouched
    expect(controller.pendingCount, 3);
  });

  test('load() replaces the previous batch and clears the run state',
      () async {
    final controller = _controller(
      verifyFn: (input) async => _ok(input.reference),
    );
    controller.load(parseBatchLines('CHQ261Z4AB2C'));
    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async => true,
      duplicateNote: (_) => 'dup',
      staleNote: (_) => 'stale',
    );
    expect(controller.isComplete, isTrue);

    controller.load(parseBatchLines('DET261Z4AB2D\nDET261Z4AB2E'));
    expect(controller.total, 2);
    expect(controller.verifiedCount, 0);
    expect(controller.isComplete, isFalse);
  });

  test('skipped rows never charge and never call the verifier', () async {
    var calls = 0;
    final controller = _controller(
      verifyFn: (input) async {
        calls++;
        return _ok(input.reference);
      },
    );
    controller.load(parseBatchLines(
      'CHQ261Z4AB2C\n'
      'CHQ261Z4AB2C\n' // duplicate
      'https://example.com/x', // unknown link
    ));
    expect(controller.chargeableCount, 1);

    var consumed = 0;
    final history = await _history();
    await controller.run(
      history: history,
      consumeAttempt: () async {
        consumed++;
        return true;
      },
      duplicateNote: (_) => 'dup',
      staleNote: (_) => 'stale',
    );

    expect(calls, 1);
    expect(consumed, 1);
    expect(controller.skippedCount, 2);
    expect(history.length, 1);
  });
}
