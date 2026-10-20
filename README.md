# FastPas POS

FastPas POS, formerly VaseNizz, is a Flutter-based mobile point-of-sale app evolving into a general retail system for sales, inventory, staff, multi-branch management, and reporting, with planned AI integration for sales insights and inventory assistance.

The name combines **fast** and **paspas**, a Cebuano word associated with speed.

## Project status

**Work in progress.** The Graphite Volt redesign includes sign-in, product-first Home, order review, payment, and receipt screens. Management screens now share the same theme, compact headers, responsive forms, and navigation back to Home. The FastPas speed mark is used for launcher icons. The backend migration and AI features remain planned. The application is not ready for live store use.

Existing functionality includes:

- Product browsing, cart, discounts, checkout, and receipts.
- Branch inventory, suppliers, and stock movement history.
- Employee management and GPS attendance.
- Sales dashboards and PDF/CSV reporting.

These workflows still require full end-to-end validation.

## Interface

**Graphite Volt** uses charcoal (`#202528`), electric lime (`#CEF54A`), and off-white (`#FAFAFA`). Home opens directly to products, with search, category filters, quantity controls, and a persistent checkout bar.

<img src="docs/screenshots/home-phone.png" alt="FastPas POS product homepage running with sample data" width="300">

*Flutter UI preview with sample data. No store transactions are saved. Products currently use category icons; barcode scanning is disabled and planned.*

More screenshots: [tablet](docs/screenshots/home-tablet.png), [order review](docs/screenshots/order-review-phone.png), [payment](docs/screenshots/payment-phone.png), and [receipt](docs/screenshots/receipt-phone.png).

Management previews: [staff](docs/screenshots/staff-phone.png), [suppliers](docs/screenshots/suppliers-phone.png), and [reports](docs/screenshots/reports-tablet.png).

## Local UI preview

```sh
flutter pub get
flutter run -d chrome -t lib/preview/main.dart
```

This entry point uses local sample data. Management requests use a read-only transport with no network fallback; no store changes or payments are saved. The normal app still requires the store configuration described in `config/supabase.example.json`.

## Refactor

Branch management and branch inventory use shared screens driven by saved branch identities. Session navigation, sign-in, calendar actions, stock adjustments, sale persistence, receipt reads, pricing, and report calculations now have shared modules. Unused parallel selling screens were removed.

See [architecture](docs/ARCHITECTURE.md) and the [database contract inventory](docs/DATABASE.md). The new [business workspace foundation](docs/BUSINESSES.md) has an additive migration and a separate Supabase Auth entry point. Legacy retail authentication and data migration remain unfinished.

To develop owner-created business workspaces after validating and applying the foundation migration to a disposable Supabase project:

```sh
flutter run -t lib/workspaces/main.dart --dart-define-from-file=config/supabase.local.json
```

This staged entry point supports registration, sign-in, owner-created businesses, staff invitations, and accessible branches. With all three additive migrations available in a disposable project, branches open [hybrid cash selling](docs/HYBRID.md): downloaded catalog, local receipts and stock deductions, pending uploads, and automatic retry while open. It does not open legacy retail screens. Configure email confirmation before testing owner creation. The normal entry point still uses the legacy single-business backend; do not deploy it as a multi-business service. SQLite persistence targets Android/iOS/macOS; this staged flow is not a web preview.

To run the normal store app, create `config/supabase.local.json` from the example configuration and supply your own project values:

```sh
flutter run --dart-define-from-file=config/supabase.local.json
```

## Validation

`flutter analyze` is clean. All 94 unit and widget tests pass, including local SQLite persistence, offline cash checkout, upload retries, account isolation, and existing selling/management regressions. The three additive database migrations pass 62 embedded PostgreSQL checks with Auth identity stubbed. The staged hybrid Android debug APK builds. The earlier sample sale and branch navigation emulator check covers the Phase 2 sample flow, not this new backend. Build results and remaining acceptance checks are recorded in the roadmap.

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
9. Device pilot and release.

See the [product roadmap](docs/ROADMAP.md) for scope and current progress.

AI sales summaries and inventory insights are planned after the core retail workflows are reliable. No provider has been selected and no AI feature is implemented yet.

## Stack and scope

- Flutter / Dart.
- Supabase client integration.
- Android is the first intended release target; other platform folders do not establish platform support.
- Multi-business workspaces are in development; legacy retail tables still require ownership migration and isolation checks.

The internal Dart package remains `vasenizzpos` while the application is being adapted to FastPas.
