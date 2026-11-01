# Business workspaces

## Ownership

One FastPas platform hosts independent businesses. A signed-in, verified account can create a business; the server creates its Owner membership and first branch in the same transaction. An account can own several businesses. Staff join an existing business using an owner-issued invitation. Permissions belong to each membership, not to a global user role.

Business creation accepts a caller-generated UUID as an idempotency key. Repeating the same request returns the same business; it cannot claim an existing business or change its owner. The client must retain that UUID across retries.

## Foundation

`supabase/migrations/202610210001_business_workspaces.sql` adds prefixed workspace tables without changing legacy relations. It provides owner-only staff invitations and invitation acceptance bound to the verified account email. Invite codes expire, are single-use, and grant only manager, cashier, or employee roles. No invitation can grant ownership. Owners can read all their branches; staff can read only assigned branches.

`202610210003_staff_access.sql` adds owner-only staff listing, role changes, removal, and unused invitation cancellation. The workspace screen exposes these through Manage staff access. Removing a member also removes branch assignments and invalidates their unused invitations, while preserving historical sales. These operations cannot remove, demote, or promote an Owner. Changes write to a private audit table; client roles cannot read or modify it directly. Ownership transfer remains a separate release gate.

The default app uses Supabase Auth email/password and lists only accessible businesses and branches. It includes registration, verification resend, and password recovery via the `fastpas://auth-callback` PKCE callback. Initial and running-app links are handled by one account controller. Workspace navigation does not open legacy retail routes; the old entry point is retained as `lib/legacy_main.dart`.

`202610240001_staff_branch_access.sql` adds explicit staff branch assignment. Owners can select branches in their own business or clear the list while retaining membership. The server rejects other businesses' branches and Owner membership changes, replaces assignments atomically, cancels that staff email's unused invitations for this business, and records previous/new branch IDs in the private audit. Other business memberships and historical sales are preserved. The editor closes on account changes; installations missing this migration cannot submit an empty list accidentally.

## Delivery gates

1. Follow [fresh setup](SETUP.md). Validate the five migrations and allow/deny tests against a development Supabase project with real Auth and email. Embedded PostgreSQL checks already pass; hosted acceptance remains outstanding.
2. A fresh database needs no old-record export. Only if importing legacy records later, export the actual schema, constraints, policies, views, and storage configuration. Back up and rehearse against a copy. Resolve employee identities without carrying plaintext passwords forward.
3. Extend the business-scoped catalog and cash-sale contract to attendance, suppliers, events, files, and broader retail operations. Composite foreign keys must prohibit cross-business relationships. Enforce server permissions, including reporting views. Explicitly map ownership for any optional imported records.
4. Connect the Graphite Volt selling and management UI to verified workspace context. Register cashier devices to one business/branch. Test two unrelated businesses and a user with different roles in each.
5. Extend the implemented SQLite cash-sale slice to the remaining retail features. Each operation retains its original business, branch, account, device context, and stable request ID across switches and retries. Complete secure device enrollment, membership-change recovery, and queue resolution. Never silently move or discard queued sales.
6. Pilot two devices through outages. Test duplicate uploads, stock shortages, stale permissions, cancelled invitations, restore, and branch reassignment. Show pending/failed synchronization in the UI. Digital payment confirmation remains provider-controlled.

## Offline rules

Business creation, invitation acceptance, and initial catalog enrollment require connectivity. The new [hybrid cash-sale slice](HYBRID.md) provides a 24-hour offline access window, SQLite persistence, and queued uploads. Device enrollment and offline staff switching still need implementation. Offline devices cannot guarantee global stock availability; the staged cash-sale server retains negative stock for reconciliation. Synchronization does not replace independent backups.

## Current limits

Foundation files are not proof of production tenant isolation. All five migrations are now deployed to a development Supabase project. Live schema/grant readback and anonymous API-denial checks pass, while the three-account hosted acceptance run remains pending. The default workspace app has hybrid cash selling; wider retail feature integration remains incomplete. Old-record migration is conditional on a future import.

## Validation

The five migrations pass 148 checks in disposable embedded PostgreSQL (PGlite), with a minimal Auth identity stub. Coverage includes unrelated businesses, multiple businesses per owner, role escalation, branch restrictions, invitations, cross-business references, idempotent cash sales, rollback, stock shortages, Owner protection, staff revocation, cancelled invitations, audit privacy, branch reassignment/clearing, duplicate branch IDs, stale invitation denial, and preservation of other memberships. This does not exercise real Supabase Auth, email delivery, PostgREST, or a deployed project's grants.

To reproduce without adding JavaScript dependencies to the Flutter project, install `@electric-sql/pglite` in a temporary directory and pass its absolute `dist/index.js` path to:

```sh
node supabase/tests/workspaces.test.mjs /absolute/path/to/pglite/dist/index.js
```

Local Supabase integration and full hosted acceptance remain unverified. The development contract is provisioned; follow [hosted acceptance](HOSTED_ACCEPTANCE.md) with three verified test accounts to exercise authenticated allow/deny behavior. Real email delivery and device callbacks remain separate checks.

The onboarding form passes phone/tablet widget checks at 360 and 1024 logical pixels with 130% text. Static analysis of the new client is clean. These checks do not validate real account registration, email verification, or a running backend.

The latest full Flutter suite passes 139 tests, including staff-management layouts, cancelled removal, branch reassignment and clearing, account switching while a dialog is open, denied saves, RPC request scope, branch-only revocation with pending receipts, SDK PKCE exchanges, duplicate/invalid/expired links, recovery startup, and responsive password forms above a keyboard. Full static analysis is clean. Real Supabase acceptance remains outstanding.

The default workspace Android debug APK rebuilt on 24 October with placeholder project values, including branch assignments, staff controls, and account recovery. This establishes compilation, not a working backend or device email-link acceptance. Both platform XML files parse; iOS compilation remains unverified.

For an optional future legacy import, run `supabase/inspect_legacy_schema.sql` in that old project's SQL Editor and save the `schema_inventory` result. This read-only query exports table definitions, relationships, policies, grants, views, indexes, and trigger metadata without reading customer records. A schema-only dump is also needed for function bodies and a complete rehearsal. This is not required for the fresh setup.
