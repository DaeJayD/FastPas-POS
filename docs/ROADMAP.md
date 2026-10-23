# FastPas POS roadmap

FastPas is being adapted from a store-specific application into a configurable mobile POS for small retail businesses. Android is the first release target. One platform serves multiple independent businesses. Owners create their businesses, configure branches, and invite staff. Accounts can belong to multiple businesses with separate permissions. The target storage model is offline-first with authorized cloud synchronization.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 1. Interface | Graphite Volt theme, product-first Home, responsive selling flow, and management layouts | Complete for this UI scope |
| 2. Technical baseline and refactor | Compatible Android build tools, shared navigation and data access, duplicated branch screen consolidation, and database inventory | Complete for this refactor scope |
| 3. Data and identity | Owner-created businesses, Supabase Auth, account recovery, memberships, invitations, tenant isolation, and branch access policies | Implemented development foundation; fresh backend and hosted acceptance pending |
| 4. Business setup | Business details, receipts, settings, and configurable branches | Planned |
| 5. Catalog and inventory | Optional brands, categories, variants, receiving, adjustments, and stock transfers | Planned |
| 6. Sales | Atomic checkout, exact amounts, safe retries, payments, and saved receipts | Planned |
| 7. Returns and shifts | Partial returns, refund records, cash movements, and shift reconciliation | Planned |
| 8. Reports | Reconciled reports, exports, and optional attendance | Planned |
| 9. Offline synchronization | Local database, durable upload queue, device registration, retries, conflicts, and cross-device isolation | Cash-sale development slice implemented; wider sync and device acceptance planned |
| 10. Release | Android device validation, migration rehearsal, backup restoration, tenant isolation, and two-device outage pilot | Planned |

## Current interface

The Phase 1 UI scope is implemented: sign-in, product Home, checkout, payment, receipts, staff, suppliers, profiles and attendance, sales history, dashboards, reports, branch inventory, stock forms, and calendar forms share the Graphite Volt theme. Management pages opened from Home use back navigation. Phone layouts stack crowded cards and fields; dense stock tables scroll horizontally. The FastPas speed mark replaces the previous launcher branding.

Home includes product/SKU search, category filters, branch selection, stock counts, quantity controls, and a persistent cart. Products currently use category icons. Barcode scanning is planned and its control is disabled.

The separate UI preview uses sample catalog data and an isolated local transport for management views. It does not initialize a live store connection. The transport rejects mutations and has no network fallback. A persistent sample banner identifies this mode; attendance and photo actions are blocked. Preview payments produce sample receipts without recording transactions. Preview behavior does not establish production authentication, stock consistency, or payment verification.

## Phase 1 verification and limits

At the end of Phase 1, the Flutter widget suite passed 56 tests, including selling interactions, saved receipt line items, management layouts at 360 and 1024 logical pixels with 130% text, and supplier form validation with a phone keyboard. The web preview built and the management screens were inspected in a browser. Static analysis had no compilation errors; legacy warnings and lint findings were carried into Phase 2.

Android validation was blocked at that point because the Gradle 8.12 wrapper was below the installed Flutter toolchain requirement of 8.14. The Phase 2 toolchain update resolves that build blocker. Browser, widget, and emulator evidence do not replace a physical Android device check.

## Phase 2 order and completion criteria

1. Align Android Gradle, plugin, Kotlin, and Java versions with the installed Flutter toolchain; build the app and run a device smoke check when a device is available.
2. Consolidate repeated branch screens into shared views driven by branch identity, while preserving the existing store behavior.
3. Centralize session and navigation handling so every flow returns to the product Home consistently.
4. Extract database queries and checkout, inventory, and report calculations from widgets into typed, testable modules. Replace loosely typed maps at those boundaries incrementally.
5. Remove obsolete screens, dead code, and redundant dependencies; resolve analyzer findings in the affected modules.
6. Inventory the existing schema and document the migration boundary for Phase 3. Preserve current data; schema and authentication changes belong to their planned phase.

Phase 2 is complete when Android builds, the affected modules analyze cleanly, regression tests pass, and selling and management flows retain the approved Phase 1 UI. Refactor in small steps with behavior checks; avoid a wholesale rewrite.

## Phase 2 implementation

The three branch routes and three branch inventory routes now share two screens backed by a branch repository. The selector reads saved branches. `PosSession` and shared navigation carry the signed-in identity through selling and new-sale flows. Sign-in, calendar, stock adjustment, receipt reads, and sale writes have explicit repository boundaries. Pricing and reporting calculations use typed models and have direct tests; reports load paginated data.

Twelve unreachable legacy modules and three unused dependencies were removed. The adaptive-controls icon font remains an asset dependency. The supported toolchain is recorded in [architecture notes](ARCHITECTURE.md). Static analysis is clean across the application and tests. [The database inventory](DATABASE.md) records the source contract and migration boundary; it is not a verified production schema export. No remote migration has run.

The regression suite passes 73 unit and widget tests. The preview banner has phone and tablet geometry checks, including a simulated status bar. An Android API 36 emulator smoke test passes the sample sale, exact-cash payment, receipt, new sale, and shared branch inventory navigation. Sample requests stay local throughout this test.

Verification on 20 October 2026: full static analysis reports no issues, all 73 unit and widget tests pass, the sample web preview builds, and the normal Android app builds as a universal debug APK with ARM and x64 support. The Android smoke test passes on the API 36 emulator. Both icon fonts are packaged; no build dependency checks were bypassed.

Fresh browser inspection could not run because the browser control tool was unavailable. The existing screenshots document Phase 1; Phase 2 layout evidence comes from widget tests and the Android sample flow. Physical-device and live-backend acceptance remain separate release checks. The debug APK is for development; release signing is still planned.

## Planned AI features

Sales summaries and inventory insights may be added after the core retail workflows are reliable. Providers, costs, data handling, and evaluation criteria are undecided. No AI feature is implemented yet.

## Later scope

Integrated payment processing, restaurant workflows, weighted products, and unit conversions are outside the initial release. Printer and scanner support require testing with specific hardware.

## Multi-business implementation boundary

See [business workspaces](BUSINESSES.md) for the accepted ownership model and rollout gates. The new foundation does not migrate or secure legacy retail tables. Do not connect a selected workspace to legacy selling or management routes until those tables, storage objects, queries, and server operations enforce business ownership. Offline synchronization is a separate delivery gate; sample preview data does not provide offline persistence.

The staged workspace branch route now has a separate cash-sale contract with SQLite persistence and queued cloud uploads. See [hybrid operation](HYBRID.md). Attendance, suppliers, shared reports, files, and calendar sync still require their tenant migrations. This cash-sale slice does not complete the full offline phase or establish release readiness.

Phase 3 now includes Owner-only staff access controls: member listing, role changes, access removal, pending invitation cancellation, and private audit records. Owner memberships are protected from these operations. Offline devices receive changes on reconnect; previously recorded sales remain.

The default app now opens business workspaces with registration, verification resend, and password recovery. Android and iOS callback declarations use `fastpas://auth-callback`; PKCE exchanges are serialized and duplicate links are ignored after successful exchange. Recovery state is established before the first screen subscribes. The historical single-store flow is retained under `lib/legacy_main.dart`.

There is no existing Supabase project for this setup. Follow [fresh setup](SETUP.md) to apply all four migrations and configure Auth and email. A legacy schema export is needed only if old records are imported later. Real Supabase isolation, email, callback routing, and two-device acceptance remain outstanding, so Phase 3 is not marked complete.

Phase 3 also includes Owner-managed staff branch assignments in a fourth migration. Branch access can be changed or cleared without removing membership or sales. Changes cancel that employee's unused invitations for the business and record previous/new assignments privately. The server rejects cross-business branches and Owner edits; other memberships remain unaffected. The editor closes on account switches, and old backend versions cannot submit assignments. Automated reconnect tests retain pending receipts on branch revocation and upload the same receipts after access is restored.

Validation on 24 October 2026: all 120 Flutter tests pass serially, full static analysis reports no issues, and all four migrations pass 95 embedded PostgreSQL checks with Auth identity stubbed. Actual Supabase Auth, PostgREST, email, and device acceptance remain pending.

The default Android debug APK rebuilt successfully with the branch editor and placeholder backend configuration. Android and iOS XML parse; iOS compilation is unverified. Native callbacks and offline synchronization still require device acceptance against Supabase.
