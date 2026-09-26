import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/licensing/paywall_config.dart';
import 'package:mahtem/core/licensing/receipt_activation.dart';
import 'package:mahtem/core/receipt_verify/models.dart';

ReceiptData _receipt({
  String bankCode = 'telebirr',
  double? amount = 10,
  String? receiverAccount = '989680816',
  String? receiverName = 'NOVEL WOLDE MICHAEL',
  String? date = '20-09-2026 12:00:00',
  String? status = 'Successful',
}) {
  return ReceiptData(
    verified: true,
    bankCode: bankCode,
    bankName: 'Telebirr',
    reference: 'CHQ261Z4AB2C',
    senderName: 'Customer',
    senderAccount: '0911223344',
    receiverName: receiverName,
    receiverAccount: receiverAccount,
    amount: amount,
    date: date,
    transactionStatus: status,
    invoiceNumber: 'CHQ261Z4AB2C',
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 26, 12);

  group('parseTelebirrReceiptDate', () {
    test('reads the dd-MM-yyyy HH:mm:ss stamp as Ethiopia time → UTC', () {
      final utc = parseTelebirrReceiptDate('20-09-2026 12:00:00');
      expect(utc, DateTime.utc(2026, 9, 20, 9)); // wall 12:00 − 3h
    });

    test('accepts the stamp embedded in longer text', () {
      final utc = parseTelebirrReceiptDate('Payment date 01-01-2027 00:30:00 x');
      expect(utc, DateTime.utc(2026, 12, 31, 21, 30));
    });

    test('returns null for missing or unparseable dates', () {
      expect(parseTelebirrReceiptDate(null), isNull);
      expect(parseTelebirrReceiptDate(''), isNull);
      expect(parseTelebirrReceiptDate('yesterday morning'), isNull);
    });
  });

  group('planDaysForAmount', () {
    test('exact plan prices unlock their plan', () {
      expect(planDaysForAmount(10), kMonthlyPlanDays);
      expect(planDaysForAmount(100), kYearlyPlanDays);
    });

    test('anything else unlocks nothing', () {
      expect(planDaysForAmount(10.5), isNull);
      expect(planDaysForAmount(99), isNull);
      expect(planDaysForAmount(null), isNull);
    });
  });

  group('receiver matching', () {
    test('credited account matches in every dialing format', () {
      expect(accountEndsWithOwnerDigits('989680816'), isTrue);
      expect(accountEndsWithOwnerDigits('+251989680816'), isTrue);
      expect(accountEndsWithOwnerDigits('251989680816'), isTrue);
      expect(accountEndsWithOwnerDigits('0989680816'), isTrue);
      expect(accountEndsWithOwnerDigits('+251 98 968 0816'), isTrue);
    });

    test('other accounts never match', () {
      expect(accountEndsWithOwnerDigits('0911223344'), isFalse);
      expect(accountEndsWithOwnerDigits('89680816'), isFalse);
      expect(accountEndsWithOwnerDigits(null), isFalse);
      expect(accountEndsWithOwnerDigits(''), isFalse);
    });

    test('credited name matches leniently', () {
      expect(receiverNameMatchesOwner('NOVEL WOLDE MICHAEL'), isTrue);
      expect(receiverNameMatchesOwner('Novel Wolde Michael'), isTrue);
      expect(receiverNameMatchesOwner('novel  wolde   michael'), isTrue);
      expect(receiverNameMatchesOwner('NOVEL WOLDE MICHAEL TRADING'), isTrue);
      expect(receiverNameMatchesOwner('Wolde Michael Novel'), isFalse);
      expect(receiverNameMatchesOwner('Someone Else'), isFalse);
      expect(receiverNameMatchesOwner(null), isFalse);
    });
  });

  group('evaluateActivationReceipt', () {
    test('a genuine monthly payment is accepted', () {
      final out = evaluateActivationReceipt(_receipt(), now: now);
      expect(out, isA<ReceiptActivationAccepted>());
      final ok = out as ReceiptActivationAccepted;
      expect(ok.amountEtb, 10);
      expect(ok.planDays, kMonthlyPlanDays);
    });

    test('a yearly payment is accepted for the yearly plan', () {
      final out = evaluateActivationReceipt(
          _receipt(amount: 100), now: now);
      expect(out, isA<ReceiptActivationAccepted>());
      expect((out as ReceiptActivationAccepted).planDays, kYearlyPlanDays);
    });

    test('only Telebirr receipts count', () {
      final out = evaluateActivationReceipt(
          _receipt(bankCode: 'cbe'), now: now);
      expect(out, isA<ReceiptActivationRejected>());
    });

    test('a wrong amount is rejected with the expected price', () {
      final out = evaluateActivationReceipt(_receipt(amount: 50), now: now);
      expect(out, isA<ReceiptActivationRejected>());
      expect((out as ReceiptActivationRejected).message,
          contains('exactly 10 ETB'));
    });

    test('a missing amount is rejected', () {
      final out = evaluateActivationReceipt(_receipt(amount: null), now: now);
      expect(out, isA<ReceiptActivationRejected>());
    });

    test('money sent to someone else is rejected', () {
      final out = evaluateActivationReceipt(
        _receipt(receiverAccount: '0911223344', receiverName: 'Someone Else'),
        now: now,
      );
      expect(out, isA<ReceiptActivationRejected>());
      expect((out as ReceiptActivationRejected).message,
          contains(kPayTelebirrNumber));
    });

    test('matching on EITHER account or name is enough', () {
      final byName = evaluateActivationReceipt(
        _receipt(receiverAccount: '0911223344'),
        now: now,
      );
      expect(byName, isA<ReceiptActivationAccepted>());

      final byAccount = evaluateActivationReceipt(
        _receipt(receiverName: 'N. W. M. Enterprises'),
        now: now,
      );
      expect(byAccount, isA<ReceiptActivationAccepted>());
    });

    test('a failed transaction is rejected', () {
      final out = evaluateActivationReceipt(
          _receipt(status: 'Transaction Failed'), now: now);
      expect(out, isA<ReceiptActivationRejected>());
    });

    test('an unknown status does not reject a good payment', () {
      final out = evaluateActivationReceipt(_receipt(status: null), now: now);
      expect(out, isA<ReceiptActivationAccepted>());
    });

    test('a stale receipt is rejected', () {
      final out = evaluateActivationReceipt(
        _receipt(date: '01-09-2026 12:00:00'), // 25 days old
        now: now,
      );
      expect(out, isA<ReceiptActivationRejected>());
      expect((out as ReceiptActivationRejected).message, contains('old'));
    });

    test('a fresh receipt inside the window is accepted', () {
      final out = evaluateActivationReceipt(
        _receipt(date: '23-09-2026 08:00:00'), // ~3 days old
        now: now,
      );
      expect(out, isA<ReceiptActivationAccepted>());
    });

    test('an unparseable date never rejects a paying user', () {
      final out = evaluateActivationReceipt(_receipt(date: 'n/a'), now: now);
      expect(out, isA<ReceiptActivationAccepted>());
    });
  });

  group('receiptHashFor', () {
    test('is stable and input-sensitive', () {
      expect(receiptHashFor('CHQ261Z4AB2C'), receiptHashFor('CHQ261Z4AB2C'));
      expect(receiptHashFor('CHQ261Z4AB2C'),
          isNot(receiptHashFor('CHQ261Z4AB2D')));
      expect(receiptHashFor('CHQ261Z4AB2C').length, 64);
    });

    test('normalizeReceiptReference canonicalises paste noise', () {
      expect(
        normalizeReceiptReference('  chq 261z4ab2c '),
        'CHQ261Z4AB2C',
      );
    });
  });
}
