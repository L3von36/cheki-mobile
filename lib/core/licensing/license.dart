/// Mahtem licensing: device-bound, expiry-bound activation codes.
///
/// A license is an Ed25519-signed token — the app holds ONLY the public
/// key, the signing seed lives with the app owner (`tool/license_secret.key`,
/// used by `tool/make_license.dart`). Offline verification, no server.
///
/// Token layout (71 bytes → Crockford Base32 → `MAH-…` grouped string):
///
///   payload (7 bytes)
///     [0]     version (0x01)
///     [1..3)  expiry, uint16 big-endian, days since 2026-01-01 UTC
///     [3..7)  device hash — first 4 bytes of SHA-256(deviceKey)
///   signature (64 bytes) — Ed25519 over the payload
///
/// Binding the device hash into the signed payload means a code cannot be
/// re-used on another device (the signature covers it), and the expiry
/// cannot be extended (same). Upgrade path: when a Firebase backend lands,
/// the same codes can be validated server-side and revoked.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha256.dart';

/// Ed25519 public key matching `tool/license_secret.key`.
const String kLicensePublicKeyV1 =
    '155b09e08a8da9e44b9ac00d9f2abb67b7da4e55d70f0ce6c581b333b7e6eb98';

/// Expiry field epoch: expiry = epoch + days (uint16 → valid to year 2205).
final DateTime kLicenseExpiryEpoch = DateTime.utc(2026, 1, 1);

const int _kVersion = 1;
const int _kPayloadLen = 7;
const int _kTokenLen = _kPayloadLen + 64;

// ─────────────────────────────────────────────────────────────────────────────
// Device identity
// ─────────────────────────────────────────────────────────────────────────────

/// First 4 bytes of SHA-256 over the device key (SSAID). These exact bytes
/// are what the user's device code shows and what a license embeds.
Uint8List deviceHashFor(String deviceKey) {
  final digest =
      SHA256Digest().process(utf8.encode('mahtem-device-v1:$deviceKey'));
  return Uint8List.sublistView(digest, 0, 4);
}

/// Human-facing device code — the value the user sends the app owner
/// together with their Telebirr payment receipt.
String deviceCodeFor(Uint8List deviceHash) => 'MAH-${_base32Encode(deviceHash)}';

/// Inverse of [deviceCodeFor] — used by `tool/make_license.dart` to turn
/// the user's device code (`MAH-XXXXXXX`) back into the 4-byte hash a
/// license embeds. Null when the text is not a valid device code.
Uint8List? deviceHashFromCode(String raw) {
  var text = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
  if (text.startsWith('MAH')) text = text.substring(3);
  final decoded = _base32Decode(text);
  if (decoded == null || decoded.length != 4) return null;
  return decoded;
}

// ─────────────────────────────────────────────────────────────────────────────
// Token minting (owner side: tool/make_license.dart)
// ─────────────────────────────────────────────────────────────────────────────

/// Builds and signs a license token for [deviceHash] valid until [expiryUtc].
Future<String> makeLicenseToken({
  required Uint8List seed,
  required DateTime expiryUtc,
  required Uint8List deviceHash,
}) async {
  final payload = _payload(expiryUtc, deviceHash);
  final signature = await _sign(seed, payload);
  return _formatToken(Uint8List.fromList([...payload, ...signature]));
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation (app side)
// ─────────────────────────────────────────────────────────────────────────────

sealed class LicenseValidation {
  const LicenseValidation();
}

class LicenseValid extends LicenseValidation {
  final DateTime expiryUtc;
  const LicenseValid(this.expiryUtc);
}

/// Not a Mahtem token (undecodable / wrong length / wrong version).
class LicenseBadFormat extends LicenseValidation {
  const LicenseBadFormat();
}

/// Signature does not verify — forged or corrupted token.
class LicenseBadSignature extends LicenseValidation {
  const LicenseBadSignature();
}

/// Valid signature, but minted for a different device.
class LicenseWrongDevice extends LicenseValidation {
  const LicenseWrongDevice();
}

/// Valid signature for this device, but the expiry has passed.
class LicenseExpired extends LicenseValidation {
  final DateTime expiryUtc;
  const LicenseExpired(this.expiryUtc);
}

/// Checks a pasted token against this device. [publicKeyHex] is injectable
/// for tests; production uses [kLicensePublicKeyV1].
Future<LicenseValidation> validateLicenseToken(
  String rawToken, {
  required Uint8List deviceHash,
  DateTime? now,
  String publicKeyHex = kLicensePublicKeyV1,
}) async {
  final token = _decodeToken(rawToken);
  if (token == null || token.length != _kTokenLen) {
    return const LicenseBadFormat();
  }
  final payload = Uint8List.sublistView(token, 0, _kPayloadLen);
  final signature = Uint8List.sublistView(token, _kPayloadLen);
  if (payload[0] != _kVersion) return const LicenseBadFormat();

  final verified = await _verify(
    signature: signature,
    message: payload,
    publicKeyHex: publicKeyHex,
  );
  if (!verified) return const LicenseBadSignature();

  if (!_bytesEqual(Uint8List.sublistView(payload, 3, 7), deviceHash)) {
    return const LicenseWrongDevice();
  }

  final expiry = kLicenseExpiryEpoch.add(
    Duration(days: (payload[1] << 8) | payload[2]),
  );
  if ((now ?? DateTime.now().toUtc()).isAfter(expiry)) {
    return LicenseExpired(expiry);
  }
  return LicenseValid(expiry);
}

// ─────────────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _payload(DateTime expiryUtc, Uint8List deviceHash) {
  final days = expiryUtc
      .toUtc()
      .difference(kLicenseExpiryEpoch)
      .inDays
      .clamp(0, 0xFFFF);
  return Uint8List.fromList([
    _kVersion,
    (days >> 8) & 0xFF,
    days & 0xFF,
    deviceHash[0],
    deviceHash[1],
    deviceHash[2],
    deviceHash[3],
  ]);
}

final Ed25519 _ed25519 = Ed25519();

Future<Uint8List> _sign(Uint8List seed, Uint8List message) async {
  final pair = await _ed25519.newKeyPairFromSeed(seed);
  final signature = await _ed25519.sign(message, keyPair: pair);
  return Uint8List.fromList(signature.bytes);
}

Future<bool> _verify({
  required Uint8List signature,
  required Uint8List message,
  required String publicKeyHex,
}) async {
  try {
    final publicKey = SimplePublicKey(
      _bytes(publicKeyHex),
      type: KeyPairType.ed25519,
    );
    return await _ed25519.verify(
      message,
      signature: Signature(signature, publicKey: publicKey),
    );
  } catch (_) {
    return false;
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── token formatting ─────────────────────────────────────────────────────────

String _formatToken(Uint8List bytes) {
  final encoded = _base32Encode(bytes);
  final groups = <String>[];
  for (var i = 0; i < encoded.length; i += 6) {
    groups.add(
        encoded.substring(i, i + 6 > encoded.length ? encoded.length : i + 6));
  }
  return 'MAH-${groups.join('-')}';
}

/// Accepts anything the user reasonably pastes: mixed case, spaces and
/// hyphens anywhere, optional MAH/MAHTEM prefixes, Crockford lookalikes
/// (O→0, I→1, L→1). Returns the 71-byte token, or null if undecodable.
Uint8List? _decodeToken(String raw) {
  var text = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
  // Users may paste the code with its display prefix (or several) — token
  // DATA never starts with 'M' (the version byte's first character is
  // always '0'), so stripping any run of prefixes is unambiguous.
  while (true) {
    if (text.startsWith('MAHTEM')) {
      text = text.substring(6);
      continue;
    }
    if (text.startsWith('MAH')) {
      text = text.substring(3);
      continue;
    }
    break;
  }
  if (text.isEmpty) return null;
  return _base32Decode(text);
}

// ── Crockford Base32 ─────────────────────────────────────────────────────────

const String _kAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String _base32Encode(List<int> bytes) {
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final byte in bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_kAlphabet[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_kAlphabet[(value << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List? _base32Decode(String text) {
  final normalized = text
      .toUpperCase()
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');
  var bits = 0;
  var value = 0;
  final out = BytesBuilder();
  for (var i = 0; i < normalized.length; i++) {
    final index = _kAlphabet.indexOf(normalized[i]);
    if (index < 0) return null; // 'U' or any foreign character → bad token
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.addByte((value >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  // Trailing bits (< 8) are the encoder's zero padding — ignored.
  return out.toBytes();
}

Uint8List _bytes(String hex) => Uint8List.fromList(List.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
