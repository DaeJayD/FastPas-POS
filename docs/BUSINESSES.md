# Business workspaces

## Ownership

One FastPas platform hosts independent businesses. A signed-in, verified account can create a business; the server creates its Owner membership and first branch in the same transaction. An account can own several businesses. Staff join an existing business using an owner-issued invitation. Permissions belong to each membership, not to a global user role.

Business creation accepts a caller-generated UUID as an idempotency key. Repeating the same request returns the same business; it cannot claim an existing business or change its owner. The client must retain that UUID across retries.

## Foundation

`supabase/migrations/202610210001_business_workspaces.sql` adds prefixed workspace tables without changing legacy relations. It provides owner-only staff invitations and invitation acceptance bound to the verified account email. Invite codes expire, are single-use, and grant only manager, cashier, or employee roles. No invitation can grant ownership. Owners can read all their branches; staff can read only assigned branches.

`202610210003_staff_access.sql` adds owner-only staff listing, role changes, removal, and unused invitation cancellation. The workspace screen exposes these through Manage staff access. Removing a member also removes branch assignments and invalidates their unused invitations, while preserving historical sales. These operations cannot remove, demote, or promote an Owner. Changes write to a private audit table; client roles cannot read or modify it directly. Ownership transfer remains a separate release gate.

The initial workspace client uses Supabase Auth email/password and lists only accessible businesses and branches. It is a separate entry point while retail migration is unfinished. It deliberately does not open legacy retail routes.

## Delivery gates

1. Validate the foundation migration and allow/deny tests against disposable PostgreSQL and then local Supabase. Configure email confirmation and recovery links.
2. Export the actual legacy schema, constraints, policies, views, and storage configuration. Back up and rehearse migration against a copy. Resolve legacy employee identities without carrying plaintext passwords forward.
3. Add business ownership to catalog, stock, sales, sale lines, attendance, suppliers, events, and files. Composite foreign keys must prohibit cross-business relationships. Enforce server permissions, including reporting views and checkout operations. Migrate one existing business explicitly; never infer ownership from user input.
4. Connect the Graphite Volt selling and management UI to verified workspace context. Register cashier devices to one business/branch. Test two unrelated businesses and a user with different roles in each.
5. Extend the implemented SQLite cash-sale slice to the remaining retail features. Each operation retains its original business, branch, account, device context, and stable request ID across switches and retries. Complete secure device enrollment, membership-change recovery, and queue resolution. Never silently move or discard queued sales.
6. Pilot two devices through outages. Test duplicate uploads, stock shortages, stale permissions, cancelled invitations, restore, and branch reassignment. Show pending/failed synchronization in the UI. Digital payment confirmation remains provider-controlled.

## Offline rules

Business creation, invitation acceptance, and initial catalog enrollment require connectivity. The new [hybrid cash-sale slice](HYBRID.md) provides a 24-hour offline access window, SQLite persistence, and queued uploads. Device enrollment and offline staff switching still need implementation. Offline devices cannot guarantee global stock availability; the staged cash-sale server retains negative stock for reconciliation. Synchronization does not replace independent backups.

## Current limits

Foundation files are not proof of production tenant isolation. The normal legacy app remains a single-business development flow. No remote migration has run. The staged workspace has new hybrid cash selling; wider retail features and legacy data migration remain incomplete until the gates above pass.

## Validation

The three migrations pass 62 checks in disposable embedded PostgreSQL (PGlite), with a minimal Auth identity stub. Coverage includes unrelated businesses, multiple businesses per owner, role escalation, branch restrictions, invitations, cross-business references, idempotent cash sales, rollback, stock shortages, Owner protection, staff revocation, cancelled invitations, and audit privacy. This does not exercise real Supabase Auth, email delivery, PostgREST, or a deployed project's grants.

To reproduce without adding JavaScript dependencies to the Flutter project, install `@electric-sql/pglite` in a temporary directory and pass its absolute `dist/index.js` path to:

```sh
node supabase/tests/workspaces.test.mjs /absolute/path/to/pglite/dist/index.js
```

Docker was unavailable during this implementation, so local Supabase integration and remote acceptance have not run. The migration has not been applied to the configured store project. The workspace UI can be exercised only after the new contract is available in a disposable Supabase project.

The onboarding form passes phone/tablet widget checks at 360 and 1024 logical pixels with 130% text. Static analysis of the new client is clean. These checks do not validate real account registration, email verification, or a running backend.

The latest full Flutter suite passes 94 tests, including phone staff-management layout, cancelled removal, and clearing staff identities on account switching. Full static analysis is clean. The earlier Android debug APK predates these staff-management controls; a fresh native build and real Supabase acceptance remain to be run for this addition.

To unblock legacy migration, run `supabase/inspect_legacy_schema.sql` in the existing project's SQL Editor and save the `schema_inventory` result. This read-only query exports table definitions, relationships, policies, grants, views, indexes, and trigger metadata without reading customer records. A schema-only dump is still needed for function bodies and a complete rehearsal.
