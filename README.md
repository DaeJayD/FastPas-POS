# FastPas POS

FastPas POS, formerly VaseNizz, is a Flutter-based mobile point-of-sale app evolving into a general retail system for sales, inventory, staff, multi-branch management, and reporting, with planned AI integration for sales insights and inventory assistance.

The name combines **fast** and **paspas**, a Cebuano word associated with speed.

## Project status

**Work in progress.** The default app now uses Supabase Auth, owner-created business workspaces, staff permissions, and hybrid cash selling. A fresh Supabase project still needs to be configured and tested. The Graphite Volt redesign covers the previous selling and management screens; those remain available through a separate legacy entry point while their features move to the new business-scoped contract. AI features remain planned. The application is not ready for live store use.

The legacy interface includes:

- Product browsing, cart, discounts, checkout, and receipts.
- Branch inventory, suppliers, and stock movement history.
- Employee management and GPS attendance.
- Sales dashboards and PDF/CSV reporting.

These workflows still require full end-to-end validation.

## Interface

**Graphite Volt** uses charcoal (`#202528`), electric lime (`#CEF54A`), and off-white (`#FAFAFA`). Home opens directly to products, with search, category filters, quantity controls, and a persistent checkout bar.

<img src="docs/screenshots/home-phone.jpg" alt="FastPas POS product homepage running with sample data" width="300">

*Flutter UI preview with sample data. No store transactions are saved. Products currently use category icons; barcode scanning is disabled and planned.*

More screenshots: [tablet](docs/screenshots/home-tablet.jpg), [order review](docs/screenshots/order-review-phone.jpg), [payment](docs/screenshots/payment-phone.jpg), and [receipt](docs/screenshots/receipt-phone.jpg).

Management previews: [staff](docs/screenshots/staff-phone.jpg), [suppliers](docs/screenshots/suppliers-phone.jpg), and [reports](docs/screenshots/reports-tablet.jpg).

## Local UI preview

```sh
flutter pub get
flutter run -d chrome -t lib/preview/main.dart
```

This entry point uses local sample data. Management requests use a read-only transport with no network fallback; no store changes or payments are saved. The normal app still requires the store configuration described in `config/supabase.example.json`.

## Refactor

Branch management and branch inventory use shared screens driven by saved branch identities. Session navigation, sign-in, calendar actions, stock adjustments, sale persistence, receipt reads, pricing, and report calculations now have shared modules. Unused parallel selling screens were removed.

See [architecture](docs/ARCHITECTURE.md), [database contracts](docs/DATABASE.md), and [business workspaces](docs/BUSINESSES.md).

## Backend setup

Follow [fresh Supabase setup](docs/SETUP.md) to create a development project, apply the four migrations in order, enable email confirmation, configure `fastpas://auth-callback`, and fill the ignored `config/supabase.local.json` file. No legacy export is needed for a new database.

```sh
flutter run --dart-define-from-file=config/supabase.local.json
```

The default app supports registration, verification resend, password recovery, owner-created businesses, staff invitations and access controls, and accessible branches. Branches open [hybrid cash selling](docs/HYBRID.md): downloaded catalog, local receipts and stock deductions, pending uploads, and automatic retry while open. SQLite persistence targets Android/iOS/macOS; this flow is not a web preview.

The explicit `lib/workspaces/main.dart` target launches the same app. `lib/legacy_main.dart` retains the historical single-store flow for migration development and requires its old schema. Workspace navigation does not open those legacy routes. Broader catalog, attendance, supplier, reporting, and selling UI integration remains planned.

## Validation

`flutter analyze` is clean. All 120 unit and widget tests pass, including local SQLite persistence, offline cash checkout, upload retries, account isolation, SDK account recovery, staff branch reassignment, and existing selling/management regressions. The four additive database migrations pass 95 embedded PostgreSQL checks with Auth identity stubbed. The earlier sample sale and branch navigation emulator check covers the Phase 2 sample flow, not this new backend. Build results and remaining acceptance checks are recorded in the roadmap.

The default workspace Android debug APK builds with placeholder backend configuration. Real Supabase Auth, email links, and multi-device acceptance remain unverified. Android callback declarations are packaged; iOS configuration is present but has not been built on macOS.

The [hosted acceptance runner](docs/HOSTED_ACCEPTANCE.md) is ready for use after a disposable Supabase development project is configured. Its local guard/transport tests run with `node --test supabase/tests/hosted_acceptance.test.mjs`. A real hosted acceptance run remains pending.

The Android build uses Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.21 and Java 17 bytecode. The development baseline is Flutter 3.47.4 / Dart 3.13. Release signing and physical-device validation remain planned.

## Roadmap

1. Interface redesign.
2. Technical baseline, codebase refactor, and database audit.
3. Database and authentication foundation.
4. Business settings and configurable branches.
5. General catalog and reliable inventory operations.
6. Atomic checkout and saved receipts.
7. Returns, refunds, and cashier shifts.
8. Reports and optional modules.
9. Offline synchronization.
10. Device pilot and release.

See the [product roadmap](docs/ROADMAP.md) for scope and current progress.

AI sales summaries and inventory insights are planned after the core retail workflows are reliable. No provider has been selected and no AI feature is implemented yet.

## Stack and scope

- Flutter / Dart.
- Supabase client integration.
- Android is the first intended release target; other platform folders do not establish platform support.
- Multi-business workspaces are in development; broader feature adaptation and deployed isolation checks remain. Optional old-record imports require a separate tenant migration.

The internal Dart package remains `vasenizzpos` while the application is being adapted to FastPas.
