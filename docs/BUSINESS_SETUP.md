# Business setup

Phase 4 adds Owner-managed business details, receipt branding, and branch creation/editing to the workspace app. Development began at the user's request while Phase 3 hosted/device acceptance remains open. This phase does not establish production readiness.

## Owner controls

Select a business, then open **Business settings**. The server verifies Owner membership for every settings read and write.

- Edit the business name, address, contact phone/email, and receipt footer. Empty optional contact fields are supported.
- Add branches with a name and address, or edit an existing branch. Branch IDs and historical transactions are preserved.
- Preview sample receipt branding for each branch. Creating a branch does not assign staff; use **Manage staff access** for that step.
- Currency remains PHP to match the existing exact-centavo cash-sale contract. Taxes, discounts, production receipt sequences, printer integration, and other payment methods belong to later phases.

Settings changes require internet. A failed save keeps the form and its values open. Retrying branch creation reuses the same request UUID, so a lost reply cannot create a second branch. Reusing that ID with changed details is rejected; cancel and refresh before submitting a different request.

Business and branch edits carry the version read when the form opened. A stale save is rejected rather than overwriting another device's update. Cancel and refresh to review the current version. Account changes close open settings dialogs and discard the previous account's visible settings.

## Receipts and offline operation

Verified catalog synchronization caches business/branch names, addresses, contact details, and footer in the branch's existing SQLite metadata. Each new cash sale copies those details into its immutable upload payload within the same local transaction as its stock deduction and outbox entry. Later settings edits and branch renames do not rewrite saved or pending receipts.

Offline receipts use the last downloaded details. A device receives newer branding on its next successful catalog synchronization. Older installations without cached branding can record the names supplied by their workspace context; historical receipts without branding remain readable and retain their recorded amounts. Branding is not retroactively inferred for those receipts.

This uses the existing SQLite schema and preserves app data. There is no local schema reset. The server retains the exact receipt payload, including its branding, and rejects a changed payload retried under an existing sale UUID.

## Migration and validation boundary

The fifth additive migration is [business settings](../supabase/migrations/202610310001_business_settings.sql). It adds bounded text fields and version columns to existing business/branch rows and four authenticated RPCs. Existing RLS and direct-write restrictions remain in effect. Settings mutations append private audit events. Functions use an empty search path and explicit execution grants, following [PostgreSQL security-definer guidance](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY).

The development project has all five migrations applied. The fifth was applied once on 31 October 2026 after local validation; do not rerun any applied files. New projects need all five in order. See [setup](SETUP.md) for the SQL Editor/CLI migration-history boundary.

The client displays unavailable settings when the new RPC is absent. Existing cash selling continues to support the earlier four-migration backend. The fifth migration returned success in the hosted SQL Editor. On 1 November 2026, all ten read-only deployment checks passed: seven settings columns, four security-definer RPCs with an empty search path, authenticated execution, anonymous/public execution denial, unchanged RLS and direct-write restrictions, initialized versions, and the original counts of one business, one branch, and one sale. Authenticated device acceptance remains pending.

All five migrations pass 148 disposable embedded PostgreSQL checks with Auth stubbed. These include Owner-only settings, anonymous and cross-business denial, read-only client table grants, optimistic version conflicts, branch creation retries, preservation of existing sales, private audits, and unchanged receipt payloads after settings edits. Hosted Auth/PostgREST and physical-device acceptance remain separate checks.

All 139 Flutter tests pass and static analysis is clean. Settings, receipt previews, and the keyboard-constrained business editor also pass phone/tablet geometry checks at 130% text, with rendered previews inspected. Phase 4 acceptance still requires Owner settings edits/branch retries on the installed app and offline receipt checks. Phase 3 real-account and two-device gates remain open.
