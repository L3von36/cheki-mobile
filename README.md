# Mahtem ማህተም

**Free Ethiopian bank receipt verification — in your pocket. 100% native, no middleman server.**

*Mahtem* (ማህተም) is Amharic for **"stamp / seal"** — the moment a receipt is checked
and stamped as genuine. That's exactly what the app does.

<p align="center">
  <img src="assets/icon/mahtem_icon.png" width="128" alt="Mahtem launcher icon"/>
</p>

[![Release](https://img.shields.io/github/v/release/L3von36/cheki-mobile?style=flat&logo=github&color=2ddb6a)](https://github.com/L3von36/cheki-mobile/releases)
[![Build APK](https://img.shields.io/github/actions/workflow/status/L3von36/cheki-mobile/release.yml?label=Release%20APK&style=flat&logo=github)](https://github.com/L3von36/cheki-mobile/actions/workflows/release.yml)
[![CI](https://img.shields.io/github/actions/workflow/status/L3von36/cheki-mobile/ci.yml?branch=main&label=CI&style=flat&logo=github)](https://github.com/L3von36/cheki-mobile/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-2ddb6a.svg)](LICENSE)

Verify CBE, Telebirr, BOA, M-Pesa, Dashen, Awash, Wegagen, Amhara, Zemen,
CBE Birr, Siinqee, Coopay (Cooperative Bank of Oromia) and eBirr payment receipts in seconds. Point your phone at a receipt — Mahtem
fetches the official record **directly from the bank's public endpoint on your
device** and tells you if the payment is genuine.

No API key. No middleman server. Accounts live on your device (encrypted) —
your first 5 checks are free.

## Features

- **Device-local accounts** — create an account (Ethiopian phone number or
  email) and sign in; the session survives restarts. Passwords are
  PBKDF2-hashed and everything lives in Android-Keystore-encrypted secure
  storage — no server, nothing leaves the device. Forgot the password?
  Reset accounts from the sign-in screen (verification history and Pro
  plans are untouched). `lib/core/auth/` + `lib/state/auth_controller.dart`.

- **English / አማርኛ / Afaan Oromoo / ትግርኛ language switcher** — the whole
  core flow (verify form, auth screens, tabs, settings) is translated;
  switching is instant and persisted. Amharic and Tigrinya render with
  Noto Sans Ethiopic; Afaan Oromoo runs on the default Latin fonts.
  Catalogs live in `lib/core/localization/` — the abstract `AppStrings`
  base makes a missing translation a compile error, so the four languages
  can never drift.

- **Light / dark / system theme switcher** — pick a mode in the settings
  sheet (gear icon on the home screen); the choice persists across
  restarts. System mode follows the OS as before.

- **Settings sheet** — account header with sign-out, appearance switcher,
  language switcher, app version and the device code (tap to copy) for
  activation codes.

- **5 free checks, then Mahtem Pro** — every install verifies 5 receipts
  for free. After that an in-app subscription unlocks unlimited checks
  (10 ETB/month or 100 ETB/year): pay via Telebirr to the owner's
  account, paste the receipt number from the confirmation SMS, and the
  app verifies that receipt with its own engine — amount and recipient
  are checked against the plan — and unlocks instantly. Zero human in the
  loop. Anti-abuse: each receipt grants one plan on one device, used
  receipts are remembered, and stale receipts are refused. Owner-minted
  activation codes (Ed25519-signed, device-bound, offline verification)
  remain available as a fallback (`lib/core/licensing/`, code generator
  in `tool/make_license.dart`).

- **Proven stylepos verification engine** — the app talks to each bank's
  public receipt endpoint straight from your phone, using the same verifier
  code that runs in our stylepos shop app (`lib/core/receipt_verify/`). No
  hosted API in between, which means Telebirr and M-Pesa work on Ethiopian
  networks (a hosted non-Ethiopian server could never reach them).
- **Verify any receipt** — paste a reference or a share link from SMS
- **Scan the number off a paper receipt** — no QR on the slip? Point the
  camera at the printed transaction / reference number and Mahtem reads
  it with on-device ML Kit OCR: labeled numbers (`RRN:`, `Ref No:`,
  `FT#…`) and RRN-shaped numbers are accepted automatically once several
  consecutive frames agree; weaker candidates (bare numbers, telebirr-
  style tokens) show up as tappable chips so nothing is verified by
  accident. Account numbers, TINs and phone lines are filtered out, and
  Gallery photos are OCR'd too — with a "type instead" fallback a tap
  away
- **QR scan that works** — every receipt QR format the stylepos verifier
  knows: bank receipt links, CBE `mbreciept` ids, **encrypted BOA receipt
  QR payloads (decrypted fully offline on-device)**, the Telebirr SuperApp
  receipt QR (a base64→hex blob decoded to the invoice number on-device),
  plus generic reference codes with a bank picker fallback. Camera
  permission is requested up front with a clear recovery path if it was
  denied.
- **Self-stabilizing scanner** — camera readings must agree before they
  are trusted, so decoder noise (a Telebirr `…BEI` scanned as `…BEIc`)
  never reaches verification. Junk letters that land inside the decoded
  Telebirr blob (a trailing `c`/`e` glued onto the invoice number) are
  stripped too; if a removed letter was genuine, verification silently
  retries with the untouched scan.
- **Stoppable verification** — a red stop button appears next to VERIFY
  while a check is running; tapping it returns to the form immediately
  and discards the late result (no result screen, no history entry).
- **Auto-detect bank** — receipt links and QR scans pick the bank and
  extract the reference automatically; raw references pair with a manual
  bank pick
- **Simple, focused UI** — one card: pick a bank, paste the reference,
  verify. No banners, no clutter. Light & dark themes.
- **Payment History** — every check is saved on-device with a summary
  strip (checks / verified / total), Today / Yesterday / This week /
  Earlier date groups, search (covers your reason notes too), status
  filters, swipe-to-delete with undo (long-press works too),
  "Verify again" prefill, and a one-tap CSV share of the whole history
- **Reason notes** — once a receipt verifies, jot down why you checked it
  ("rent", "order #12"). The note shows on the history tile, the details
  sheet and the result screen, exports with the CSV, and rides the
  encrypted cloud vault like the rest of your history
- **Service announcements** — when the Mahtem team broadcasts a notice
  from the admin console (planned maintenance, a bank outage, a new bank
  going live), a dismissible banner shows it on the Verify tab
- **Honest failures** — receipt not found or bank down? The result screen
  says exactly why and lists what to do next
- **Crash reports (opt-in Sentry)** — release APKs built with a Sentry
  DSN report crashes anonymously (no receipt or account data, no
  screenshots, no PII) so bugs get fixed fast; builds without a DSN
  behave exactly as before — zero network, zero overhead. The settings
  sheet discloses this in all four languages
- **Private** — history never leaves the device; nothing to sign up for.
  The receipt-number OCR runs on-device too (ML Kit) — camera frames are
  never uploaded

## Mahtem Admin — owner console (`admin-app/`)

A separate, owner-only Android app lives in [`admin-app/`](admin-app/): every
account, every synced scan, bank popularity (which bank do people verify
most?) and a live scan feed — plus the full operations panel: **suspend /
delete any account** (typed confirmation, sessions wiped on sight), **post
announcements** that show up in every user's app, **allow/block new
sign-ups**, toggle **maintenance mode**, manage additional **admin
accounts**, and read the server-side **audit trail** of every action. All
with the same zero-knowledge guarantees (receipt contents stay encrypted;
the console sees banks, outcomes and counts only). Sign in once with the
owner email + password; it stays on the device. Releases are tagged
`admin-vX.Y.Z` and published by `.github/workflows/admin-release.yml`
(`mahtem-admin-<tag>-arm64/arm32/universal.apk`).

## How verification works

Each bank publishes receipts on a public endpoint; the app ships the
stylepos receipt verifier verbatim (`lib/core/receipt_verify/`) — it builds
the URL, fetches with retries, and parses the response:

| Bank | Endpoint | Response |
|------|----------|----------|
| CBE (new) | `Mb.cbe.com.et/api/v1/transactions/public/transaction-detail/{id}` | JSON |
| Telebirr | `transactioninfo.ethiotelecom.et/receipt/{ref}` | HTML |
| Bank of Abyssinia | `cs.bankofabyssinia.com/api/onlineSlip/getDetails/?id={ref}{last5}` | JSON |
| M-Pesa | `m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo={ref}` | JSON |
| Dashen | `receipt.dashensuperapp.com/receipt/{ref}` | PDF (text-extracted on device) |
| Awash | `awashpay.awashbank.com:8225/-{shareToken}` | HTML (self-signed TLS handled) |
| Zemen | `share.zemenbank.com/rt/{ref}/pdf` | PDF (text-extracted on device) |
| CBE Birr | `cbepay1.cbe.com.et/aureceipt?TID={ref}&PH={phone}` | HTML |
| Siinqee | `siinqeebank.com/receipt/{ref}` (moved off `receipt.ebirr.com/siinqee`, old links re-routed) | HTML |
| Coopay (Coop Bank of Oromia) | `receipt.ebirr.com/coopay/{token}` | HTML |
| eBirr family | `receipt.ebirr.com/{tenant}/{token}` (nib, wegagen, ahadu, kaafimf…) | HTML |
| Wegagen | `transinfo.wegagenbanksc.com.et:8011/sms_wega/txn/{shareId}` | JSON |
| Amhara | `transaction.amharabank.com.et/{trxRef}` | JSON |

Notes:
- **Sign in from anywhere — accounts follow you across devices**
  (`v1.14.4`): fixes the reported dead end where clearing app data (or
  using a second phone) made sign-in answer "No account found for this
  phone/email — create one first" even though the account existed.
  Sign-in now has a second tier: when the identifier is unknown to the
  device, the zero-knowledge cloud (provisioned automatically at
  sign-up) proves the phone/email + password remotely — the password
  itself never leaves the device, only a one-way derived key — and the
  account is rebuilt on the spot, display name included (it travels
  back inside the encrypted history vault). The rebuilt account is
  stored locally, so every later sign-in on that device works offline
  exactly as before. Wrong passwords, genuinely unknown accounts and
  offline states now each get their own truthful message instead of a
  blanket "no account found".
- **Much smaller downloads** (`v1.14.3`): the universal APK went from
  ~100 MB to ~35 MB, and the arm64 APK most phones install from under
  half its old size to ~22 MB. The old builds carried three complete
  copies of every native library (Flutter engine, ML Kit OCR pipeline,
  barcode engine, compiled Dart) — one per CPU architecture (32-bit
  ARM, 64-bit ARM, and x86_64 for emulators) — stored uncompressed
  inside the APK. Mahtem now ships ARM-only (100% of real phones),
  compresses the native libraries inside the APK (the installer
  extracts them once at install, so installed size is unchanged), and
  drops the unused x86_64 copies and icon font. Zero features changed.
- **Accounts survive restarts — resilient on-device account storage**
  (`v1.14.2`): fixes the reported bug where a freshly created account
  vanished after reopening the app ("No account found for this
  phone/email — create one first"). Accounts and the session now live in
  Keystore-encrypted secure storage WITH a second copy in the app's
  private storage; if the encrypted layer ever becomes unreadable
  (Keystore invalidation, device migration, plugin migration bugs), the
  next read self-heals from the mirror instead of losing the account.
  Sign-in also reports malformed phone/email input truthfully instead of
  claiming the account doesn't exist, and every storage failure is
  recorded in Settings → Report a problem. Android auto-backup is now
  disabled — nothing ever leaves the device via Google cloud backup.
- **Self-healing sign-up sync** (`v1.14.1`): the zero-step arming below is
  no longer one-shot — if a sign-up or sign-in lands while the network is
  down (flaky mobile data, DNS hiccup), the phone KEEPS TRYING with
  backoff for ~5 minutes and creates the hosted account the moment the
  connection returns. Nothing is stored for this: the password stays in
  memory only for that window and is dropped afterwards. Auth screens
  also never fail silently anymore — every failure shows a visible
  message.
- **Zero-step cloud sync** (`v1.14.0`): backup arms ITSELF — the moment
  you create your account (or sign in on a new device) the phone links to
  your hosted account and starts mirroring your verification history,
  encrypted end-to-end. No settings visit, no second password prompt, no
  button: signing in on a new phone restores your history automatically.
  An offline sign-up simply stays local (the Settings sheet remains the
  manual fallback), turning backup off still deletes the cloud copy, and
  the next sign-in arms it again.
- **Auto-backup — always-on sync** (`v1.13.1`): once Cloud backup is on,
  the phone talks to the cloud by itself — every verification is pushed
  automatically (debounced so a 50-row batch is one upload), app boots
  catch up anything that never made it, and a daily pull brings in
  changes made on another device. Failures retry with backoff and an
  expired session pauses syncing until re-enable (nothing is lost — the
  next push merge-uploads). An Auto-backup switch in the sheet pauses
  the automatic push for manual-only control.
- **Cloud backup — zero-knowledge history backup** (`v1.13.0`): Settings →
  Cloud backup links your device account to your own hosted account
  (Cloudflare Workers + KV) and merge-uploads the verification history as
  one AES-256-GCM blob. Everything is encrypted on the phone first: the
  server stores only an identifier hash, a password-derived auth key and
  ciphertext it can never open — the raw password and the vault key never
  leave the device. Restore on a new phone merges (never overwrites)
  local history; turning backup off deletes the cloud copy. The app
  stays fully local-first — the vault key never leaves the device.
- **Global error safety net + "Report a problem"** (`v1.12.1`): unexpected
  framework and async errors no longer vanish or show Flutter's grey
  developer box. Every build keeps a small, local-only diagnostics trail
  (last 30 problems, capped, never uploaded); release builds show a calm
  localized error card instead of a crash box. Settings → Report a problem
  opens the trail so a user who saw something break can read it and copy
  the details into a bug report.
- **Batch check — verify a whole day's receipts at once** (`v1.12.0`): the
  new checklist icon on the Verify tab opens a batch screen. Paste many
  receipt links or references — one per line — and Mahtem checks them
  sequentially on-device, one attempt per row, with a live progress bar,
  per-row results (amount or failure reason), a shareable results summary
  and the same local anti-fraud advisories as single checks. Duplicates
  collapse, CBE printed numbers are skipped with an explanation, unknown
  links are never charged, and a stopped batch offers a "check the
  remaining" resume.
- **Everything on a receipt auto-detects the bank — not just bare links.**
  The Wegagen receipt QR carries SMS-style prose with the link inside, and
  the Amhara web receipt's QR is a bare JSON payload
  (`{"transactionId":"FT…","creditAccountNo":"…"}`) — scanning either
  fills in the right bank and reference automatically.
- **The number scanner reads only what's inside the frame** (`v1.11.1`):
  OCR is now position-aware — a number counts only when its center sits
  inside the viewfinder rectangle, so the amount, account number or
  footer elsewhere on the receipt can never win the candidate list. Aim
  the frame at the transaction number and that number alone is read.
- **The QR screen is camera-only** (`v1.11.1`): the "Type number" button
  is gone — the QR scanner does exactly one thing (live scan, gallery
  decode, or the OCR number scanner). Typing stays where it belongs: the
  Verify tab and the number scanner's own fallback.
- **Pasted SMS / chat messages collapse to the receipt value** (`v1.11.0`):
  paste a whole Telebirr SMS or a chat message into the number sheet and the
  receipt link / reference is pulled out of the prose automatically — the SMS
  itself is never trusted, the extracted value still verifies against the bank.
- **OCR misread rescue** (`v1.11.0`): when the camera confuses easily-mixed
  characters (O↔0, I↔1, L↔1, B↔8, S↔5, Z↔2), the scanner offers the
  re-readings as extra candidate chips so one wrong glyph no longer turns a
  genuine receipt into "not found".
- **Local anti-fraud advisories** (`v1.11.0`): the result gains an advisory
  note when the verified receipt is more than a day old (the replayed-receipt
  scam) or when this exact bank + reference was already verified on this
  device before (a receipt being walked around). Both are computed on-device
  from the receipt's own date and the local history — nothing new leaves the
  phone.
- **Typed Telebirr numbers auto-select the bank** (`v1.11.0`): a bare
  reference with a Telebirr invoice prefix (CHQ…, DET…, ADQ…) pre-selects
  Telebirr instead of dead-ending in the manual picker.
- **Pasted share links work everywhere**: whether the sender shares a bare
  link or the whole SMS text, the app extracts the reference before calling
  the bank — pasting a full link into the reference field always verifies.
- **Awash tokens keep their leading dash** (`awashpay.awashbank.com:8225/-…`):
  the dash is part of the token and the bank answers 403 without it. A
  dash-less typed token is retried with the dash automatically.
- **CBE's receipt API intermittently answers HTTP 400** for a valid token
  and 200 on the next call (observed live) — the app retries those and only
  then reports the receipt as not found.
- Amhara Bank does not publish web receipts for some in-app (MB) transfers —
  the app explains that honestly instead of blaming the connection.
- CBE's **legacy `FT` + last-8-digits** PDF system was decommissioned by CBE —
  the app detects FT references and explains the new flow (scan the receipt QR
  or ask the sender for the `mbreciept.cbe.com.et` link).
- BOA still needs the last **5** digits of the receiving account when
  verifying by reference; scanning the BOA receipt QR skips that entirely —
  the QR carries the whole receipt, encrypted, and is decrypted locally.
- The PDF extractor (Dashen/Zemen) supports FlateDecode and
  ASCII85+Flate streams; if text cannot be recovered the app falls back to
  opening the original receipt in the browser.

## Install

Grab the latest APK from [Releases](https://github.com/L3von36/cheki-mobile/releases):
1. Download **`mahtem-vX.Y.Z-arm64.apk`** — for almost every phone sold since
   2016 (~22 MB, under half the old download)
2. Very old phone? Use `mahtem-vX.Y.Z-arm32.apk` (~20 MB). Not sure?
   `mahtem-vX.Y.Z-universal.apk` works on every Android phone (~35 MB)
3. Allow "Install unknown apps" if prompted
4. Install & stamp your first receipt as verified

> **Upgrading from v1.3.0 or earlier (installed as "Cheki")?** The app was
> fully rebranded in v1.4.0 — new name, new icon, new app id
> (`app.mahtem.mobile`) and a new signing key. Android treats it as a
> separate app: **uninstall the old Cheki app first**, then install Mahtem.
> Your old verification history does not carry over (it was on-device only).

## Building from source

```bash
flutter pub get
flutter analyze   # must be clean
flutter test      # unit + widget tests
flutter build apk --release
```

Launcher icons are regenerated from `assets/icon/` with:

```bash
dart run flutter_launcher_icons
```

## Crash reporting (Sentry, opt-in)

Mahtem uses [Sentry](https://sentry.io) for anonymous crash reporting
(`sentry_flutter`). Nothing is ever sent unless the APK was built with a
DSN baked in — the feature is inert by default.

To enable it for release builds:

1. Create a free project at [sentry.io](https://sentry.io) (platform:
   **Flutter**) and copy its **DSN**.
2. Add repo secrets (**Settings → Secrets and variables → Actions**):
   - **`SENTRY_DSN`** — turns reporting on. The release workflow passes
     it to `flutter build` via `--dart-define`; without this secret the
     app never touches Sentry at all.
   - **`SENTRY_AUTH_TOKEN`**, **`SENTRY_ORG`**, **`SENTRY_PROJECT`** —
     optional, used to upload the `--split-debug-info` symbols after the
     build so the `--obfuscate` Dart frames in crash reports become
     readable.
3. Push the next tag — crashes appear in the Sentry dashboard, grouped
   by release (`app.mahtem.mobile@X.Y.Z+NN`).

Privacy posture (pinned by tests in `test/crash_reporting_test.dart`):
`sendDefaultPii = false`, screenshots off, view hierarchy off, no
performance tracing — error events and release-health sessions only.
Every crash wrapper failure degrades to a plain boot, so reporting can
never keep the app from starting.

## Releases

Tag-push driven: bump `version` in `pubspec.yaml`, commit, tag `vX.Y.Z`,
push — GitHub Actions builds a signed APK and attaches it to the release.

## Credits

Architecture inspiration from the open-source
[cheki](https://github.com/1RB/cheki) project (studied, then re-implemented
from scratch in Dart for this app).

## License

MIT
