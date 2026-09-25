# cheki mobile

**Free Ethiopian bank receipt verification — in your pocket. 100% native, no middleman server.**

[![Release](https://img.shields.io/github/v/release/L3von36/cheki-mobile?style=flat&logo=github&color=2ddb6a)](https://github.com/L3von36/cheki-mobile/releases)
[![Build APK](https://img.shields.io/github/actions/workflow/status/L3von36/cheki-mobile/release.yml?label=Release%20APK&style=flat&logo=github)](https://github.com/L3von36/cheki-mobile/actions/workflows/release.yml)
[![CI](https://img.shields.io/github/actions/workflow/status/L3von36/cheki-mobile/ci.yml?branch=main&label=CI&style=flat&logo=github)](https://github.com/L3von36/cheki-mobile/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-2ddb6a.svg)](LICENSE)

Verify CBE, Telebirr, BOA, M-Pesa, Dashen, Awash, Zemen, CBE Birr, Siinqee and
eBirr payment receipts in seconds. Point your phone at a receipt — cheki
fetches the official record **directly from the bank's public endpoint on your
device** and tells you if the payment is genuine.

No signup. No API key. No fees. No middleman server.

## Features

- **Native verification engine** — the app talks to each bank's public
  receipt endpoint straight from your phone. No hosted API in between, which
  means Telebirr and M-Pesa work on Ethiopian networks (a hosted
  non-Ethiopian server could never reach them).
- **Verify any receipt** — paste a reference or a share link from SMS
- **QR scan that works** — recognizes every receipt QR format we know:
  bank links, CBE `mbreciept` ids, **encrypted BOA receipt QR payloads
  (decrypted on-device)**, plain references — and generic reference codes
  with a bank picker fallback. Camera permission is requested up front with
  a clear recovery path if it was denied.
- **Auto-detect bank** — the app recognizes the bank from the reference
  format (CBE `FT…`, Telebirr `DET…`, Awash share segments, …)
- **Simple, focused UI** — one card: pick a bank, paste the reference,
  verify. No banners, no clutter. Light & dark themes.
- **Payment History** — every check is saved on-device; tap an entry for
  details, long-press to remove
- **Honest failures** — receipt not found or bank down? The result screen
  says exactly why and offers a one-tap "Open original receipt" fallback
- **Private** — history never leaves the device; nothing to sign up for

## How verification works

Each bank publishes receipts on a public endpoint; the app's native engine
(`lib/core/native/`) builds the URL, fetches it with retries, and parses the
response with its own parsers:

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
| Siinqee / eBirr | `receipt.ebirr.com/{tenant}/{token}` | HTML |

Notes:
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
1. Download `cheki-mobile-vX.Y.Z.apk`
2. Allow "Install unknown apps" if prompted
3. Install & verify your first receipt

## Building from source

```bash
flutter pub get
flutter analyze   # must be clean
flutter test      # 64 tests
flutter build apk --release
```

## Releases

Tag-push driven: bump `version` in `pubspec.yaml`, commit, tag `vX.Y.Z`,
push — GitHub Actions builds a signed APK and attaches it to the release.

## Credits

Architecture inspiration from the open-source
[cheki](https://github.com/1RB/cheki) project (studied, then re-implemented
from scratch in Dart for this app).

## License

MIT
