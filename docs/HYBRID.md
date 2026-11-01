# Hybrid operation

## Development scope

The default `lib/main.dart` launches business workspaces after [fresh Supabase setup](SETUP.md). Branch selection opens the new cash-selling flow. The historical single-store app is retained as `lib/legacy_main.dart`; its attendance and management features need adaptation before joining the workspace flow. Old-record migration is needed only if records are imported later.

Owners add products, exact prices in centavos, and opening stock while online. Previously downloaded products can be sold for cash offline. SQLite commits the receipt, stock deductions, and pending upload in one transaction. Receipts remain available after restart. Currency is PHP; taxes, discounts, returns, shifts, providers, printers, and configured production receipt numbering are outside this development slice.

## Isolation and access

Each account/business/branch gets a separate SQLite file. Immutable upload payloads retain their original business, branch, and device-context UUID. Signing out preserves pending records; another account cannot discover or upload them through this flow. Business and branch discovery labels are cached per account, with a 24-hour expiry. Permission failures invalidate discovery instead of falling back to stale labels.

First sign-in, business creation, invitations, and catalog enrollment require internet. Existing signed-in accounts can sell for up to 24 hours after successful membership, branch, and catalog verification. Known revocation disables local selling. Revocation cannot be detected while disconnected. Device clock and sandbox protection are not tamper-proof. PIN staff switching and secure device enrollment remain planned.

## Sync and conflicts

Owners can now change an employee's branch assignments while retaining membership. Branch revocation disables local selling on the next successful access check and retains pending receipts in their original branch database. Restoring access allows those same receipts to sync. Disconnected devices still operate within their previously verified access window until they reconnect or that window expires.

Sync runs on opening the branch, app resume, every 30 seconds while open, and Sync now. It does not block cash checkout and is not a guaranteed OS background job after closing the app. Requests have bounded timeouts. Lost responses retry the same receipt UUID and payload; the server atomically saves each sale and deducts stock once.

The current Saved receipts list reads the local account/branch database. It does not download receipt history from other devices. Other enrolled devices refresh catalog and stock from the server; shared receipt reporting remains planned.

The server rechecks business membership, role, branch access, catalog prices, and product ownership. Network failures remain pending. Validation failures retain the receipt and display a review reason. A resolution/reversal workflow is still required before pilot use. Catalog refresh preserves pending and blocked stock deductions without deducting acknowledged sales twice. Reads paginate the catalog.

Local stock checks cannot prevent two disconnected devices selling the same remaining units. The staged server accepts completed cash sales and retains negative stock for explicit shortage reconciliation. Stock allocations and configurable online-only items remain planned. Database sync never verifies a card or wallet payment.

## Remaining release gates

Attendance, reports across devices, suppliers, files, and calendar synchronization remain planned. Local Supabase, real email authentication, two-device airplane-mode/restart acceptance, production deployment, and independent backup restoration have not run. The development schema is deployed, with schema/grant readback and anonymous endpoint checks completed. Any future old-record import requires migration rehearsal. Local database encryption is not implemented. Do not clear app data with pending receipts.

Tests use real SQLite files, mocked HTTP transport, and embedded PostgreSQL with Auth identity stubbed. These are separate from device and deployed-backend acceptance.

The default workspace Android debug APK builds with storage plugins, staff controls, and account recovery. Its ignored local configuration now targets the development backend. The sample preview's earlier emulator checks do not validate this new hybrid backend or its offline authentication on a device. All four SQL migrations are applied remotely to the development project; the authenticated and two-device acceptance checks remain pending.

Verification on 24 October 2026: all 120 Flutter tests pass serially, static analysis is clean, and all 95 embedded PostgreSQL checks pass. Branch-only revocation, receipt preservation, and uploading the original receipt after access restoration are now covered. The default Android debug APK rebuilt with placeholder backend values and the branch editor. Hosted backend and device acceptance remain separate outstanding checks.

Phase 4 adds receipt branding snapshots from the last verified business/branch settings download. Names, addresses, contact details, and footer are copied into each new sale transaction and remain unchanged across later settings edits and retries. Older unbranded receipts remain readable. See [business setup](BUSINESS_SETUP.md).
