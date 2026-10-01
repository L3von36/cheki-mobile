/// Account model for Mahtem's device-local accounts.
///
/// An account is identified by a phone number (Ethiopian formats) or an
/// email address. Only the display name and the PBKDF2-encoded password
/// hash are persisted — never the raw password. Accounts live in
/// Android-Keystore-encrypted secure storage and never leave the device.
library;

/// A single device-local account.
class AccountRecord {
  /// Normalized identifier (see [validateAccountIdentifier]) — the
  /// lookup key for sign-in, always lowercase/digits.
  final String id;

  /// What the user typed originally (display purposes in settings).
  final String identifier;

  final String displayName;

  /// [PasswordHash.encode] output — PBKDF2 parameters travel inside.
  final String passwordHash;

  final DateTime createdAtUtc;

  const AccountRecord({
    required this.id,
    required this.identifier,
    required this.displayName,
    required this.passwordHash,
    required this.createdAtUtc,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'identifier': identifier,
    'displayName': displayName,
    'passwordHash': passwordHash,
    'createdAtMs': createdAtUtc.millisecondsSinceEpoch,
  };

  static AccountRecord? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final identifier = json['identifier'];
    final displayName = json['displayName'];
    final passwordHash = json['passwordHash'];
    final createdAtMs = (json['createdAtMs'] as num?)?.toInt();
    if (id is! String ||
        id.isEmpty ||
        identifier is! String ||
        displayName is! String ||
        passwordHash is! String ||
        passwordHash.isEmpty ||
        createdAtMs == null) {
      return null;
    }
    return AccountRecord(
      id: id,
      identifier: identifier,
      displayName: displayName,
      passwordHash: passwordHash,
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
        createdAtMs,
        isUtc: true,
      ),
    );
  }

  /// Initials for the avatar circle in settings ("AB"), from the first
  /// two words' first letters (rune-safe, works for Amharic names).
  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'M';
    String first(String s) => String.fromCharCode(s.runes.first);
    if (parts.length == 1) {
      final name = parts.first;
      return (first(name) +
              (name.runes.length > 1 ? first(name.substring(1)) : ''))
          .toUpperCase();
    }
    return (first(parts.first) + first(parts[1])).toUpperCase();
  }
}

/// Why an identifier was rejected by [validateAccountIdentifier].
enum AccountIdIssue { empty, invalidPhone, invalidEmail }

/// Outcome of validating a raw identifier typed by the user.
sealed class AccountIdValidation {
  const AccountIdValidation();
}

class AccountIdValid extends AccountIdValidation {
  const AccountIdValid(this.normalized);
  final String normalized;
}

class AccountIdInvalid extends AccountIdValidation {
  const AccountIdInvalid(this.issue);
  final AccountIdIssue issue;
}

/// Validates and normalizes a phone number or email.
///
/// Accepted Ethiopian phone shapes (spaces/dashes ignored):
///   * `09xxxxxxxx`  (local mobile)
///   * `+2519xxxxxxxx` / `2519xxxxxxxx` (international mobile)
///   * `07xxxxxxxx` / `2517xxxxxxxx` (Safaricom Ethiopia)
/// Emails use a pragmatic `local@domain.tld` check.
AccountIdValidation validateAccountIdentifier(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const AccountIdInvalid(AccountIdIssue.empty);
  }
  if (trimmed.contains('@')) {
    return _isValidEmail(trimmed)
        ? AccountIdValid(trimmed.toLowerCase())
        : const AccountIdInvalid(AccountIdIssue.invalidEmail);
  }
  final digits = trimmed.replaceAll(RegExp(r'[\s\-()]'), '');
  final plus = digits.startsWith('+');
  final clean = plus ? digits.substring(1) : digits;
  if (clean.contains(RegExp(r'\D'))) {
    return const AccountIdInvalid(AccountIdIssue.invalidPhone);
  }
  String intl;
  if (clean.startsWith('0') && clean.length == 10) {
    intl = '251${clean.substring(1)}';
  } else if (clean.startsWith('251') && clean.length == 12) {
    intl = clean;
  } else if ((clean.startsWith('9') || clean.startsWith('7')) &&
      clean.length == 9) {
    intl = '251$clean';
  } else {
    return const AccountIdInvalid(AccountIdIssue.invalidPhone);
  }
  return AccountIdValid(intl);
}

/// Pretty form for display: `+251911223344` / lowercase email.
String displayIdentifierFor(String raw) {
  final validation = validateAccountIdentifier(raw);
  return switch (validation) {
    AccountIdValid(:final normalized) =>
      normalized.contains('@') ? normalized : '+$normalized',
    AccountIdInvalid() => raw.trim(),
  };
}

bool _isValidEmail(String value) {
  final email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  return email.hasMatch(value);
}
