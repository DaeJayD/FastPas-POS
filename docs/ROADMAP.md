# FastPas POS roadmap

FastPas is being adapted from a store-specific application into a configurable mobile POS for small retail businesses. Android is the first release target. One platform serves multiple independent businesses. Owners create their businesses, configure branches, and invite staff. Accounts can belong to multiple businesses with separate permissions. The target storage model is offline-first with authorized cloud synchronization.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 1. Interface | Graphite Volt theme, product-first Home, responsive selling flow, and management layouts | Complete for this UI scope |
| 2. Technical baseline and refactor | Compatible Android build tools, shared navigation and data access, duplicated branch screen consolidation, and database inventory | Complete for this refactor scope |
| 3. Data and identity | Owner-created businesses, Supabase Auth, account recovery, memberships, invitations, tenant isolation, and branch access policies | Development schema deployed; hosted account/API checks passed; email/callback/device gates remain |
| 4. Business setup | Business details, receipts, settings, and configurable branches | Implemented; earlier phone checks reported complete; hosted account/API checks passed |
| 5. Catalog and inventory | Optional brands, categories, variants, receiving, adjustments, and stock transfers | Development schema deployed; hosted account/API checks passed; Phase 5 phone acceptance pending |
| 6. Sales | Atomic checkout, exact amounts, safe retries, payments, and saved receipts | Slices 6A–6D implemented locally; final acceptance and earlier phone/email/callback gates remain |
| 7. Returns and shifts | Partial returns, refund records, cash movements, and shift reconciliation | Development schema deployed. Hosted concurrent workflows passed. Device acceptance remains open. |
| 8. Reports | Reconciled reports, exports, and optional attendance | Branch reports and CSV implemented. Hosted report access checks passed. Device acceptance remains open. |
| 9. Offline synchronization | Local database, durable upload queue, device registration, retries, conflicts, and cross-device isolation | Development schema deployed. Hosted registration and desktop SQLite recovery checks passed. Physical two-device acceptance remains open. |
| 10. Release | Android device validation, migration rehearsal, backup restoration, tenant isolation, and two-device outage pilot | Migration history aligned and application-data restore rehearsed. Android release preparation in progress. Device and production gates remain. |

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

Twelve unreachable legacy modules and three unused dependencies were removed. The adaptive-controls icon font remains an asset dependency. The supported toolchain is recorded in [architecture notes](ARCHITECTURE.md). Static analysis is clean across the application and tests. [The database inventory](DATABASE.md) records the source contract and migration boundary; it is not a verified production schema export. No remote migration was run during Phase 2.

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

A development Supabase project is now configured with all four migrations. [Fresh setup](SETUP.md) remains the guide for new installations and explains the migration-history boundary for the existing manually provisioned project. A legacy schema export is needed only if old records are imported later. Authenticated Supabase isolation, email, callback routing, and two-device acceptance remain outstanding, so Phase 3 is not marked complete.

Phase 3 also includes Owner-managed staff branch assignments in a fourth migration. Branch access can be changed or cleared without removing membership or sales. Changes cancel that employee's unused invitations for the business and record previous/new assignments privately. The server rejects cross-business branches and Owner edits; other memberships remain unaffected. The editor closes on account switches, and old backend versions cannot submit assignments. Automated reconnect tests retain pending receipts on branch revocation and upload the same receipts after access is restored.

Validation on 24 October 2026: all 120 Flutter tests pass serially, full static analysis reports no issues, and all four migrations pass 95 embedded PostgreSQL checks with Auth identity stubbed. Actual Supabase Auth, PostgREST, email, and device acceptance remain pending.

The default Android debug APK rebuilt successfully with the branch editor and placeholder backend configuration. Android and iOS XML parse; iOS compilation is unverified. Native callbacks and offline synchronization still require device acceptance against Supabase.

Hosted acceptance tooling is prepared for Phase 3. The opt-in runner checks real Auth and PostgREST isolation, staff permissions, branch revocation, and cash-sale retry behavior when a disposable development project is configured. It preserves attempted fixture IDs in ignored local reports, waits for concurrent uploads before session cleanup, and fails on missing RPCs or transport errors. See [hosted acceptance](HOSTED_ACCEPTANCE.md) for configuration, retained fixtures, and the remaining device checks. Preparing and locally testing this runner does not complete hosted acceptance or Phase 3.

Local verification on 30 October 2026: all 15 acceptance-tooling tests and all 95 embedded PostgreSQL checks pass. Runner syntax and whitespace checks pass; local credentials, reports, and pending report files are ignored by Git. These results do not exercise a real Supabase API or device callback.

Development backend setup on 30-31 October 2026: all four migrations were applied once through the Supabase SQL Editor. Seven deployed-schema checks passed: seven public RLS tables, read-only authenticated table grants with anonymous access denied, seven read policies, nine authenticated-only workspace functions, private-table client access denied, branch-audit UUID array columns, and branch assignments in the staff listing. The Data API exposes `public` and `graphql_public`, with `fastpas_private` excluded.

Email sign-up and confirmation are enabled, the minimum password length is eight, and the exact `fastpas://auth-callback` redirect is saved. The ignored app-local configuration targets the development project with a public client key; the earlier configuration is backed up locally. Three anonymous HTTP checks passed: Auth settings are reachable and require email confirmation, business-record reads are denied, and the private schema is absent from PostgREST exposure. These checks do not establish real-account sign-in, cross-business authenticated isolation, email delivery, or device acceptance. The three-account hosted runner has not run, and Phase 3 remains open.

On 31 October 2026, the default Android debug APK rebuilt successfully with the development project's local configuration. Build dependency validation remained enabled. This is a development build; registration, verification links, and hybrid operation still need acceptance on an installed device.

Device preparation on 31 October 2026: APK inspection confirms the app label, callback intent filter, minimum API 24, target API 36, and ARM32/ARM64/x86_64 libraries. All 15 hosted-runner safeguard tests pass again. The [device acceptance checklist](DEVICE_ACCEPTANCE.md) defines exact checkout/reconnect quantities and account/access checks. An isolated API 36.1 emulator failed during OS boot with the SurfaceFlinger `hasReadColorBufferDma` assertion; installation was rejected while booting, so this provides no app-runtime acceptance. A physical device or working emulator and verified test accounts remain required.

UI and responsiveness revision on 31 October 2026: the workspace uses a light gray background (`#EDF0F2`), clearer card edges, compact dialogs, separated floating labels, and short quantity/selection animations that respect reduced-motion settings. Product and cash forms validate in place and own their controllers through route disposal. The cash form shows the total due and uses a decimal keyboard; stock uses a whole-number keyboard. Account and recovery fields have matching spacing.

Background synchronization no longer blocks Android Back. Each branch visit owns its SQLite connection, so a previous visit finishing an upload cannot close a newly opened store. Independent business and access reads run concurrently, with account and revocation checks retained before/after catalog refresh. Catalog rows are constructed on demand, cart totals use only cart entries, uploads read pending receipts, and checkout retrieves its saved receipt directly. A product form from an earlier account cannot submit after an identity change.

All 127 Flutter tests pass, including regressions first observed failing for label spacing, blocked Back, shared connection closure, sequential business reads, and stale-account form submission. Full static analysis is clean. Widget-rendered selling/product/payment previews were inspected; the 1,000-product test reaches the final item with a bounded visible card count. Physical-device startup and frame timings have not been measured. User screenshots show a running connected test branch and product, but they do not complete the hosted isolation, recovery-link, or two-device acceptance gates. At this checkpoint Phase 3 remained open and Phase 4 had not started.

Both the debug and optimized profile Android APKs rebuilt successfully with the development configuration. The profile APK is approximately 76.4 MB; package identity and signing certificate match the debug build, supporting an update that retains app data. Use profile mode for physical-device performance checks, as described in the device checklist. Build dependency validation remained enabled; release signing and store distribution remain planned.

## Phase 4 development

Phase 4 began on 31 October 2026 at the user's explicit request, with Phase 3's hosted and device acceptance still open. See [business setup](BUSINESS_SETUP.md). The implementation adds Owner business/contact/receipt settings, branch creation/editing, version conflict protection, and immutable receipt branding cached for offline checkout. The fifth additive migration passes the combined 148 embedded PostgreSQL checks. All 139 Flutter tests pass and full static analysis is clean. The fifth migration was applied once through the hosted SQL Editor and returned success; preflight found no Phase 4 version columns and one existing business, branch, and sale. All ten post-deployment schema/grant/data-count checks passed on 1 November 2026. Phone acceptance and Phase 3 hosted/device gates remain pending. The current optimized Android profile APK rebuilt successfully on 1 November 2026 with build dependency validation enabled (approximately 93.4 MB).

Local acceptance preparation on 1 November 2026: the opt-in hosted runner now checks all four Phase 4 RPCs, direct-write restrictions, concurrent branch retries, stale-version rejection, staff isolation, and saved/pending/new receipt branding across settings changes. All 85 runner checks pass against the five migrations through a disposable embedded Auth/HTTP adapter, along with 148 direct database checks, 16 report/failure assertions, and 15 runner safeguard tests. The adapter serializes requests and cannot establish real hosted Auth/PostgREST or network-concurrency acceptance. No device is attached and the three-account local config remains unconfigured. Phase 3 and Phase 4 acceptance remain open.

Validation on 3 November 2026: all 140 Flutter tests pass serially, including a late-save/account-switch navigation check. The phone-layout test now centers its edit control before tapping so it works with default test-font metrics as well as captured-font previews; no app layout change was required. The changed Dart test analyzes cleanly. Backend checks pass with locked PGlite 0.5.14: 148 direct database checks, 85 complete runner checks with Auth/HTTP stubbed, 16 runner-result assertions, and 15 safeguard tests. A clean test dependency install succeeds. Guided phone testing has confirmed the settings screen, receipt-footer save/reopen, and single branch creation after refresh; remaining results are tracked in the device checklist.

Reconnect error handling on 3 November 2026: the phone tester recovered a generic settings-load error by refreshing. Connection failures, timeouts, expired sign-in, and explicit Owner denials now have distinct messages; failed reads offer Retry settings. A simulated connection failure reproduced the old misleading message before the change. All 146 Flutter tests pass afterward, including safe read retries and session-error classification, and full static analysis is clean. The original phone request error type remains unconfirmed. The optimized profile APK rebuilt successfully with build dependency validation enabled. The tester subsequently confirmed all remaining guided Phase 4 phone tests completed. These reports concern the previously installed APK; the new recovery-message build is locally validated and not yet device-verified. Automated three-account hosted acceptance remains pending.

## Phase 5 local validation

The next sales work is outlined in [the Phase 6 plan](SALES_PLAN.md). Preparing that plan does not advance Phase 5 acceptance or start a hosted rollout.

On 4 November 2026, Owner catalog and inventory controls pass local review: optional brands/categories/families, SKU variants, archive/restore, receiving, physical counts, transfers, thresholds, and immutable movement history. A regression first reproduced an enabled Add product button after an account switch; the screen now clears readiness when its identity changes. Classification eligibility is locked until a product edit commits. All 158 Flutter tests pass, analysis is clean, and the configured profile APK builds. The 14 catalog database scenarios include an upgrade with existing stock/receipts; all nine deployment checks pass locally. The full acceptance runner passes 123 embedded checks and 23 report/failure assertions; those local results do not establish real Auth/HTTP or network concurrency; the hosted result is recorded below.

The sixth migration was initially held locally at the user's request, then applied on 4 November 2026 after sign-in and explicit continuation. [Catalog deployment and acceptance](CATALOG_INVENTORY.md) records the preflight, one-time migration, post-deployment checks, and phone checklist. At that checkpoint, Phase 5 still required hosted and installed-device acceptance and Phase 6 had not started. Subsequent work is recorded below.

## Hosted acceptance and conflict correction

On 4 November 2026, the first hosted run reproduced a stale business edit that failed to return within 15 seconds; an isolated probe still timed out after 45 seconds. The functions used application-level SQLSTATE `40001`, which affected PostgREST versions retry as serialization failures. The seventh additive migration replaces those explicit domain errors in five functions with `PT409`, preserving their ownership checks, signatures, grants and data. The same hosted probe subsequently returned HTTP 409/code PT409 in 177 ms. Readback found five corrected functions and no active matching conflict probes. The client handles PT409 and retains compatibility with earlier 40001 responses.

After the correction, all 123 hosted Auth/PostgREST checks passed with three distinct dedicated admin-confirmed accounts. Real concurrent sale/branch/transfer retries, tenant and role restrictions, revocation/restoration, immutable receipt branding, stock conservation and archive/restore checks passed. The report confirms all three test sessions were closed locally. Admin confirmation bypassed delivery for these test identities; SMTP/email verification links and native callbacks remain separate acceptance steps. The first failed run retained partial fixtures, and the successful run retained its documented fixtures. Both manifests and the generated credentials remain in ignored local configuration files.

## Phase 6 local sales

Phase 6A was published with frozen checkout quotes, stable local attempt IDs, atomic retries, cart clearing and account-change dialog protection. Its full suite passed 175 Flutter tests, analysis was clean and the configured profile APK built. That build was not installed or physically accepted.

On 5 November 2026, slices 6B–6D add the [workspace product Home, cash review and receipt history](SALES.md). Name/SKU search and cached category filters preserve the cart. Phone lists and wider grids build products lazily; the cart stays visible. Cash review displays the frozen lines and exact change before Complete sale. History uses cursor pages and status filters, reads a payload only for detail, and offers sync of the existing pending queue. Home refresh reads counts instead of loading all receipt JSON. A late sync can no longer replace an account-change warning.

The additive SQLite version-2 upgrade preserves a populated version-1 file, including pending receipts, stock deductions, device identity, access and branding. It adds cached category fields and a receipt-status index; no new Supabase migration is required. A read-only authenticated Owner category-query check succeeded against the existing development schema. The staff fixture had no categorized stock to verify that populated read. No business data or server permissions were changed. All 187 Flutter tests pass, static analysis is clean and the configured profile APK builds and verifies. No physical Android device was attached. Installed-phone acceptance and the earlier release gates remain open.

## Phase 7A cash returns

Owners and assigned managers can open **Cash return** from a synced receipt on their device. The dialog shows the remaining units, the original unit prices and the refund total. Staff choose which units to put back in stock and enter a reason. The cashier handles the cash handoff.

The eighth migration records each return separately from the original sale. Refund amounts use recorded sale prices. The database caps cumulative quantities per receipt line and commits the return, its lines and any stock movements together. The app saves the request on the device before sending it, so a lost reply can be retried after reopening the app with the same account and receipt.

Local validation passed 189 Flutter tests and 34 backend test groups for this slice. The new tests cover returns at the original price, optional restocking, branch permissions, rollback, and recovery after reopening SQLite. Development deployment and hosted concurrent return checks completed on 12 November 2026. Installed-device checks are pending.

## Phase 7B cashier shifts

Open **Cash shift** in the branch selling screen, enter the opening float and record cash added to or taken from the drawer with a reason. The shift belongs to the signed-in cashier, branch and device. Checkout attaches the active shift to receipts, including cash sales taken offline. Returns recorded from this drawer use its shift for the refund debit.

The close shows expected cash, counted cash and variance. Expected cash is opening float plus synced sale totals and cash in, less recorded refunds and cash out. The app requires resolution of linked pending or blocked receipts and saved return requests before closing. A saved shift request survives a lost reply and holds new checkout until it is resolved. Closing freezes the ledger totals and a late new receipt for that drawer goes to review. Older receipts without an assigned shift can still sync.

The cash returns and cash shifts migrations are installed on the development project. The [cash-workflow acceptance run](HOSTED_ACCEPTANCE.md#returns-and-cash-shifts) passed 19 hosted checks including concurrent partial returns, repeated movement requests, concurrent closing, late-sale rejection and report reconciliation. Continue the [device checks](DEVICE_ACCEPTANCE.md#phase-7-installed-device-checks).

## Phase 8 branch cash reports

Owners and assigned managers can open **Cash reports**, select a branch, choose a date range of up to 93 days and save the displayed daily figures to CSV. The initial report covers the last seven days in `Asia/Manila`. Enter a different IANA time zone to report in the branch's local calendar.

The report assigns synced sales to their occurrence date, refunds to the date recorded and drawer reconciliation to the date the shift closed. Gross sales less refunds gives net cash sales. Drawer expected cash, counted cash and variance are reported separately. Older sales can appear after their devices sync. The report does not yet include optional attendance.

Local validation passed 193 Flutter tests, 39 backend test groups and static analysis. Coverage includes exact CSV amounts, the workspace report route, late replies after account changes, branch permissions and daylight-saving boundaries. The reporting migration was deployed on 12 November 2026 after the returns and shifts migrations. Hosted Owner reads and anonymous/cross-business denials passed. Installed-device CSV checks remain pending.

## Phase 9A offline cash-sale recovery

The cash-sale queue uploads in bounded batches and persists retry timing in SQLite version 3. Lost or mismatched acknowledgments retain the original payload and device ID. Sync now can retry early. One sync operation per local store keeps a second branch visit from uploading into an older visit's stock refresh. Catalog paging follows product IDs, and the previous snapshot stays in place while an upload remains unconfirmed. Local upgrades from versions 1 and 2 preserve pending receipts and stock deductions.

Broader offline operations and independent two-device acceptance remain open. Follow the [Phase 9 device checks](DEVICE_ACCEPTANCE.md#phase-9-installed-device-checks) for the cash-sale queue.

## Phase 9B selling device registration

After an online branch sync refreshes the catalog, FastPas checks in using the same device ID stored on local cash receipts. Owners can open **Business settings**, choose **Selling devices** on a branch and match its device codes to the selling screens. Each registration belongs to the signed-in account and branch, with a server-recorded last-seen time. Registering again preserves the original registration and pending receipts.

Migration eleven adds the registry and was deployed on 12 November 2026. Hosted checks confirmed Owner access to the branch list and denied anonymous, staff and unrelated Owner access. Registration writes passed in the Phase 9C run below. The [physical two-device checks](DEVICE_ACCEPTANCE.md#phase-9-installed-device-checks) remain open. Branch access remains managed through staff assignments.

Deployment readback matched all eleven affected public function bodies to their repository source and confirmed the execution grants. Twenty-five hosted Auth/API checks passed across three distinct verified accounts. The original seven receipts and 43 stock units matched the pre-deployment counts. [Setup](SETUP.md#1-create-the-backend) records the hosted migration versions and the remaining workflow checks.

## Phase 9C hosted recovery acceptance

The opt-in [hosted SQLite test](DEVICE_ACCEPTANCE.md#phase-9-installed-device-checks) passed 19 checks on 12 November 2026. It runs the app's `LocalStore` and `SyncService` against the development backend using two independent register directories and three verified accounts. It confirmed registration writes, database reopening, recovery from a lost sale acknowledgment, concurrent reconnects, exact receipt retries, stock convergence, registry restrictions and pending-sale recovery after staff access was restored.

The successful run retained three synced receipts and two registrations in its dedicated fixture. Earlier attempts stopped at a test-manifest type error and retained their separate fixtures. Their manifests and local databases remain available for inspection. The original data outside those fixtures matched its earlier counts. Physical phone timing, airplane mode, app process restart and the two-phone test remain open.

## Phase 10 release preparation

On 13 November 2026, the live application's 20 tables and 42 functions matched a clean replay of all eleven repository migrations. Migration history was aligned with the local filenames after retaining the previous records. An independent in-memory PostgreSQL restore of 164 application rows passed 100 checks, including per-table row digests, a receipt retry, stock preservation and tenant isolation. The rehearsal seeds Auth identity references for foreign keys. Full Supabase Auth recovery and managed backup restoration remain separate release work.

The Android build now supports local release signing and a configurable application ID. [Release preparation](RELEASE.md) records the build commands, backup scope and outstanding production/device checks.
