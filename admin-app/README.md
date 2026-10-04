# Mahtem Admin (admin-app)

Owner-only analytics console for the Mahtem receipt verification network —
a separate Android app (independent of the main Mahtem app) that shows:

- Registered accounts & cloud-synced vaults (live)
- Total scans, verification success rate, scans today / last 7 days
- 14-day scan-activity bar chart
- **Most-used banks** ranking — which bank do people verify most?
- Recent scan-activity feed (verified / not verified, per device)
- Per-account overview

Read-only. Zero-knowledge preserved: vaults are end-to-end encrypted, so the
console can never see receipt contents, references or amounts — only bank
names, verification outcomes and counts, which v1.15.0+ clients report with
each sync.

## Sign-in

Paste the **ADMIN_KEY** (the `ADMIN_KEY` secret on the
`mahtem-api` Cloudflare Worker). It is stored only on the device
(SharedPreferences, app-private) and sent solely as a Bearer token to
`GET /v1/admin/overview` on `https://mahtem-api.mahtem.workers.dev`.
"Lock & sign out" removes it from the device.

## Builds

Releases are built by `.github/workflows/admin-release.yml`:

- push to `main` touching `admin-app/**` → analyze + test
- push tag `admin-vX.Y.Z` → signed APK release (`arm64` / `arm32` / `universal`)

Locally: `flutter pub get && flutter analyze && flutter test`.

## Structure

```
lib/
  main.dart                  app entry + login/dashboard shell
  admin_api.dart             typed Worker admin API client + models
  admin_controller.dart      session state: unlock, refresh, live timer, sign-out
  format.dart                time/date/percentage helpers
  ui/
    theme.dart               dark zinc + emerald theme tokens
    login_screen.dart        ADMIN_KEY unlock screen
    dashboard_screen.dart    KPIs, chart, banks, feed, accounts, privacy note
```

The Android host (`android/`) is adapted from the main app — same AGP/Kotlin/
Gradle versions, same keystore secrets, `applicationId app.mahtem.admin`.
