# Hybrid operation

## Development scope

Run the staged `lib/workspaces/main.dart` entry point after validating all three additive migrations in a disposable Supabase project. Branch selection opens the new cash-selling flow. The normal legacy app is unchanged; its existing sales, inventory, attendance, and management data still require migration.

Owners add products, exact prices in centavos, and opening stock while online. Previously downloaded products can be sold for cash offline. SQLite commits the receipt, stock deductions, and pending upload in one transaction. Receipts remain available after restart. Currency is PHP; taxes, discounts, returns, shifts, providers, printers, and configured production receipt numbering are outside this development slice.

## Isolation and access

Each account/business/branch gets a separate SQLite file. Immutable upload payloads retain their original business, branch, and device-context UUID. Signing out preserves pending records; another account cannot discover or upload them through this flow. Business and branch discovery labels are cached per account, with a 24-hour expiry. Permission failures invalidate discovery instead of falling back to stale labels.

First sign-in, business creation, invitations, and catalog enrollment require internet. Existing signed-in accounts can sell for up to 24 hours after successful membership, branch, and catalog verification. Known revocation disables local selling. Revocation cannot be detected while disconnected. Device clock and sandbox protection are not tamper-proof. PIN staff switching and secure device enrollment remain planned.

## Sync and conflicts

Sync runs on opening the branch, app resume, every 30 seconds while open, and Sync now. It does not block cash checkout and is not a guaranteed OS background job after closing the app. Requests have bounded timeouts. Lost responses retry the same receipt UUID and payload; the server atomically saves each sale and deducts stock once.

The server rechecks business membership, role, branch access, catalog prices, and product ownership. Network failures remain pending. Validation failures retain the receipt and display a review reason. A resolution/reversal workflow is still required before pilot use. Catalog refresh preserves pending and blocked stock deductions without deducting acknowledged sales twice. Reads paginate the catalog.

Local stock checks cannot prevent two disconnected devices selling the same remaining units. The staged server accepts completed cash sales and retains negative stock for explicit shortage reconciliation. Stock allocations and configurable online-only items remain planned. Database sync never verifies a card or wallet payment.

## Remaining release gates

Attendance, reports across devices, suppliers, files, and calendar synchronization remain planned. Local Supabase, real email authentication, two-device airplane-mode/restart acceptance, server deployment, existing-data migration, and independent backup restoration have not run. Local database encryption is not implemented. Do not clear app data with pending receipts.

Tests use real SQLite files, mocked HTTP transport, and embedded PostgreSQL with Auth identity stubbed. These are separate from device and deployed-backend acceptance.

The staged Android debug APK builds with the new storage plugins. The sample preview's earlier emulator checks do not validate this new hybrid backend or its offline authentication on a device. The SQL migrations remain unapplied remotely.

Verification on 21 October 2026: full static analysis is clean, all 92 Flutter tests pass, and 46 embedded PostgreSQL checks pass. The final Flutter suite ran serially after low disk space interrupted an earlier rerun; only generated compiler caches and a duplicate build output were removed. Source and the completed APK were preserved.
