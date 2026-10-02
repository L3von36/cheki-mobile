import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/cloud/cloud_vault.dart';
import 'package:mahtem/core/verify_history.dart';

HistoryEntry _entry({
  required String id,
  String bankId = 'cbe',
  String reference = 'FT123',
  int verifiedAt = 1000,
  String status = 'verified',
}) =>
    HistoryEntry(
      id: id,
      bankId: bankId,
      bankName: 'CBE',
      reference: reference,
      verifiedAt: verifiedAt,
      status: status,
    );

void main() {
  group('encode/decode', () {
    test('round-trips entries', () {
      final entries = [
        _entry(id: 'a', verifiedAt: 3000),
        _entry(id: 'b', verifiedAt: 2000, status: 'failed'),
      ];
      final decoded = decodeVaultPayload(encodeVaultPayload(entries));

      expect(decoded, hasLength(2));
      expect(decoded[0].id, 'a'); // newest first
      expect(decoded[1].id, 'b');
      expect(decoded[1].status, 'failed');
    });

    test('caps at 100 entries on encode', () {
      final entries = List.generate(150, (i) => _entry(id: 'e$i', verifiedAt: i));
      final decoded = decodeVaultPayload(encodeVaultPayload(entries));
      expect(decoded, hasLength(kVaultMaxEntries));
    });

    test('rejects unknown versions', () {
      expect(
        () => decodeVaultPayload('{"v":99,"entries":[]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-object payloads', () {
      expect(
        () => decodeVaultPayload('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('mergeHistoryEntries', () {
    test('unions local and remote, newest first', () {
      final merged = mergeHistoryEntries(
        [_entry(id: 'local1', verifiedAt: 5000)],
        [_entry(id: 'remote1', verifiedAt: 7000)],
      );
      expect(merged.map((e) => e.id).toList(), ['remote1', 'local1']);
    });

    test('same id appears once — local wins', () {
      final merged = mergeHistoryEntries(
        [_entry(id: 'x', verifiedAt: 5000, reference: 'LOCAL')],
        [_entry(id: 'x', verifiedAt: 5000, reference: 'REMOTE')],
      );
      expect(merged, hasLength(1));
      expect(merged.single.reference, 'LOCAL');
    });

    test('same natural signature (no id) appears once', () {
      final merged = mergeHistoryEntries(
        [_entry(id: 'deviceA-1', verifiedAt: 5000)],
        [_entry(id: 'deviceB-9', verifiedAt: 5000)],
      );
      expect(merged, hasLength(1));
    });

    test('distinct references at the same time both survive', () {
      final merged = mergeHistoryEntries(
        [_entry(id: 'l1', reference: 'FT1', verifiedAt: 5000)],
        [_entry(id: 'r1', reference: 'FT2', verifiedAt: 5000)],
      );
      expect(merged, hasLength(2));
    });

    test('result is capped at 100', () {
      final local = List.generate(60, (i) => _entry(id: 'l$i', verifiedAt: i));
      final remote = List.generate(60, (i) => _entry(id: 'r$i', verifiedAt: 1000 + i));
      final merged = mergeHistoryEntries(local, remote);
      expect(merged, hasLength(kVaultMaxEntries));
    });
  });
}
