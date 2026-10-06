# Mahtem Admin (admin-app)

Owner console for the Mahtem receipt verification network —
a separate Android app (independent of the main Mahtem app).

It runs the whole network side:

- **Home** — live KPIs (accounts, encrypted cloud vaults, scans, verification
  success rate), a 7/14/30-day activity chart, top banks and the latest
  scan feed.
- **Accounts** — every cloud-synced account, searchable and sortable, with a
  per-account drill-down (KPIs, 30-day series, banks, event timeline) and CSV
  export.
- **Activity** — the full scan feed, filtered by outcome and bank, grouped by
  day, with CSV export.
- **Banks** — popularity ranking with per-bank verification success.
- **Manage** — the operations hub:
  - **Service controls** — toggle new sign-ups and maintenance mode
    (owner-only; enforced by the Worker on the next request),
  - **Announcements** — broadcast a banner into every user's app at their
    next launch (info / warn / critical, max 5 stored at once),
  - **Console access** — invite additional admins, reset their passwords,
    remove them (owner-only; every admin sees the list),
  - **Audit trail** — who did what, newest first, kept at 150 entries.
- **Account controls** (on the account drill-down) — suspend / re-enable an
  account (kills its sessions instantly; blocks sign-in and vault sync), and
  delete it permanently (typed confirmation required; vault, sessions and
  refresh tokens wiped, tombstone blocks zombie writes).

Zero-knowledge preserved: vaults are end-to-end encrypted, so the console can
never see receipt contents, references or amounts — only bank names,
verification outcomes and counts, which v1.15.0+ clients report with each sync.

Sign-in is a real owner **email + password** session (30-day token, PBKDF2
hash server-side). Admin sign-ins have a narrower, role-scoped reach — the
server enforces every action, the UI only mirrors it.

## Builds

Releases are built by `.github/workflows/admin-release.yml`:

- push to `main` touching `admin-app/**` → analyze + test
- push tag `admin-vX.Y.Z` → signed APK release (`arm64` / `arm32` / `universal`)

Locally: `flutter pub get && flutter analyze && flutter test`.
Application version is `1.3.0+4` (pubspec.yaml); API surface tracked is v1.19.

## Structure

```
lib/
  main.dart                  app entry + login/dashboard shell
  admin_api.dart             typed Worker admin API client + all models
  admin_controller.dart      session + management state (ChangeNotifier)
  format.dart                time/date/percentage/thousands helpers
  ui/
    theme.dart               dark zinc + emerald theme tokens
    login_screen.dart        owner sign-in / first-run setup
    dashboard_screen.dart    6-tab shell (IndexedStack + NavigationBar)
    admin_widgets.dart       shared cards, custom bar chart painter,
                             bank rows, event tiles, copy-CSV helper
    account_detail_page.dart per-account drill-down + suspend/delete
    tabs/
      home_tab.dart          KPIs + 7/14/30-day chart + top banks + feed
      accounts_tab.dart      search/sort + suspended chip + CSV export
      activity_tab.dart      feed with outcome/bank filters + CSV export
      banks_tab.dart         full bank ranking
      manage_tab.dart        service controls, announcements, admin users,
                             audit trail
      settings_tab.dart      owner card, security, live updates, privacy
```

The Android host (`android/`) is adapted from the main app — same AGP/Kotlin/
Gradle versions, same keystore secrets, `applicationId app.mahtem.admin`.
