# cheki mobile

**Free Ethiopian bank receipt verification — in your pocket. Flutter client for [cheki](https://github.com/1RB/cheki).**

[![Release](https://img.shields.io/github/v/release/L3von36/cheki-mobile?style=flat&logo=github&color=2ddb6a)](https://github.com/L3von36/cheki-mobile/releases)
[![Build APK](https://img.shields.io/github/actions/workflow/status/L3von36/cheki-mobile/release.yml?label=Release%20APK&style=flat&logo=github)](https://github.com/L3von36/cheki-mobile/actions/workflows/release.yml)
[![CI](https://img.shields.io/github/actions/workflow/status/L3von36/cheki-mobile/ci.yml?branch=main&label=CI&style=flat&logo=github)](https://github.com/L3von36/cheki-mobile/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-2ddb6a.svg)](LICENSE)

Verify CBE, Telebirr, BOA, M-Pesa, Dashen, Awash, Zemen, CBE Birr, Siinqee and
eBirr payment receipts in seconds. Point your phone at a receipt — cheki
fetches the official record from the bank's public endpoint and tells you if
the payment is genuine.

No signup. No API key. No fees. Ever.

## Features

- **Verify any receipt** — paste a reference or a share link from SMS
- **QR scan** — scan receipt QR codes (including the new CBE
  `mbreciept.cbe.com.et` receipts) and verify instantly
- **Auto-detect bank** — the app recognizes the bank from the reference
  format (CBE `FT…`, Telebirr `DET…`, Awash share segments, …)
- **Official receipt card** — amount, sender, receiver, date and fees
  rendered on a thermal-paper receipt with a VERIFIED stamp
- **Geo-blocked banks handled** — Telebirr and M-Pesa verify through the
  cheki servers, so the app works worldwide
- **Receipt aesthetic** — punched paper, dashed perforations, monospace
  references, dark & light themes
- **Private** — receipts are never stored; nothing to sign up for

## Install

Grab the latest APK from [Releases](https://github.com/L3von36/cheki-mobile/releases):
1. Download `cheki-mobile-vX.Y.Z.apk`
2. Allow "Install unknown apps" if prompted
3. Install & verify your first receipt

Minimum Android 7.0 (API 24). Camera permission is used only for QR scanning.

## How it works

```
App ──POST /api/verify──► cheki API (chekiapp.vercel.app)
                              │
                              ├─► CBE          apps.cbe.com.et (PDF)
                              ├─► Telebirr     transactioninfo.ethiotelecom.et
                              ├─► BOA          cs.bankofabyssinia.com (JSON)
                              ├─► M-Pesa       m-pesabusiness.safaricom.et (JSON)
                              ├─► Dashen / Awash / Zemen / CBE Birr / Siinqee / eBirr
                              ▼
                       Structured receipt JSON
```

The app talks to the free hosted cheki API — the same one powering
[chekiapp.vercel.app](https://chekiapp.vercel.app). It is open source
([1RB/cheki](https://github.com/1RB/cheki)) and can be self-hosted.

## Building

```bash
flutter pub get
flutter test
flutter build apk --release
```

### Release signing (maintainers)

The `Release APK` workflow builds a signed APK on every `v*` tag push and
attaches it to a GitHub Release. It reads four repository secrets:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 keystore.jks` of the release keystore |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | signing key alias |
| `KEY_PASSWORD` | key password |

If the secrets are absent the workflow still ships a debug-signed APK, so
CI never blocks on signing setup.

## Project structure

```
lib/
  core/
    cheki_client.dart     # API client: verify, batch, banks, health + retry
    banks_registry.dart   # 10 banks, reference & URL/QR detection
    models.dart           # VerifyResult, ChekiBank, ChekiException
  state/
    verify_controller.dart  # form + verification state machine
    theme_controller.dart
  theme/cheki_theme.dart  # receipt design tokens (from the web app)
  ui/
    screens/              # home, result, scan, banks
    widgets/              # receipt paper, stamp, ticker, verify button…
  util/format.dart
```

## Contributing

Found a bank that doesn't verify? An endpoint change? Open an issue on the
[main repo](https://github.com/1RB/cheki/issues) with the bank name and a
reference number — parser fixes land on the API side and every client
benefits immediately.

## License

MIT — same as the cheki API.

## Disclaimer

cheki mobile is not affiliated with any Ethiopian bank or Ethio Telecom. It
reads publicly accessible receipt endpoints and displays the data the banks
themselves publish.
