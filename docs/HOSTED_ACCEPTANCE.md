# Hosted backend acceptance

This checks the Phase 3 workspace/cash-sale, Phase 4 business-settings, and Phase 5 catalog/inventory contracts through real Supabase Auth and PostgREST. It is separate from the embedded PostgreSQL suite, which stubs Auth. A passing hosted run still does not verify email delivery, native callback routing, SQLite persistence, or two-device offline operation.

The runner has been prepared locally. The hosted run passed all 123 checks on 4 November 2026 after correcting stale-edit responses. Its three identities were created and confirmed through the development project's admin tools; the run verifies real password sign-in and authenticated API behavior, not email delivery.

## Prepare a disposable development project

Follow [fresh setup](SETUP.md) first: apply all seven migrations, configure email/password accounts, and keep `fastpas_private` out of exposed API schemas. All seven are installed in the current development project; do not rerun them. Do not run this against a store's database. The runner cannot determine whether a project contains production data.

Use Node.js 20 or later. No additional JavaScript packages are required for this runner. From the repository root, copy the configuration:

```powershell
Copy-Item config/acceptance.example.json config/acceptance.local.json
```

Edit the ignored local copy:

- Set `projectUrl` to the development project's HTTPS URL, and `expectedProjectRef` to its exact project reference. The runner supports the standard `https://PROJECT_REF.supabase.co` address.
- Set `publicKey` to that project's publishable key. Legacy `anon` keys are also accepted. Secret and service-role keys are rejected because privileged access would invalidate the isolation checks. Supabase distinguishes [client keys from keys that bypass row-level security](https://supabase.com/docs/guides/getting-started/api-keys).
- Supply three distinct, existing, email-verified test accounts under `ownerA`, `ownerB`, and `staff`. Register and verify them through the app, or provision dedicated admin-confirmed accounts in the development project for API acceptance. Admin confirmation must not be reported as email-delivery or native-callback acceptance. These labels describe their roles in newly created fixtures; the script does not create Auth accounts or grant access to existing businesses.
- Set `allowTestWrites` to `true` only after confirming this is the disposable development project. Keep the example file unchanged.

The runner uses password sign-in and checks each identity through Auth's user endpoint. It does not implement MFA or CAPTCHA challenges. If those prevent sign-in, the run fails before business fixtures are created; it does not bypass them.

## Run the checks

First verify the runner's local safeguards without making network requests:

```powershell
node --test supabase/tests/hosted_acceptance.test.mjs
```

For all local checks, including disposable PostgreSQL, install the locked test dependency and run the test package:

```powershell
npm.cmd --prefix supabase/tests ci --ignore-scripts
npm.cmd --prefix supabase/tests test
```

Dependency installation downloads the pinned package from npm. The tests then run locally without project credentials or hosted writes. `node_modules` is ignored; keep `package.json` and `package-lock.json` together so fresh checkouts use the same PostgreSQL runtime.

After the backend and local credentials are ready, explicitly allow fixture creation:

```powershell
node supabase/tests/hosted_acceptance.mjs config/acceptance.local.json --write-fixtures
```

Both `allowTestWrites: true` and `--write-fixtures` are required. Starting the script without them does not sign in or create fixtures. There is no automatic migration, credential provisioning, or retry of the whole run.

## What the run exercises

| Area | Expected behavior |
|---|---|
| Identity | Three different verified accounts; anonymous business creation denied; private schema not exposed |
| Businesses | One owner creates two businesses, another creates a third; creation retries retain one branch; unrelated owners cannot take over or read the other business |
| Catalog | Owner creates an item and opening stock; unrelated catalog access and cross-business stock relationships are denied |
| Catalog management | All six new RPCs enforce their intended roles; classifications and variants retry once; exact prices, scoped reads, archived classification references, product archive/restore and versions persist |
| Inventory | Receiving/count/transfer/threshold writes retain versions; concurrent transfer retries move stock once; cross-business transfers and changed retry payloads are denied; immutable movement history reconciles both branches; direct REST edits are denied |
| Staff | Invitation bound to verified email, invitation replay denied, different roles in two businesses, no self-promotion or direct membership edits, Owner membership protected |
| Business settings | Owner details round-trip; anonymous users, unrelated owners, and cashiers denied for all four settings RPCs; invalid inputs and stale versions rejected; direct REST writes denied |
| Branch settings | Concurrent creation retries return one branch; changed retry details and cross-business edits denied; edits preserve identity/version; new branches do not silently assign staff |
| Receipt branding | Business/branch/contact/footer snapshots remain unchanged after settings edits; old branded payloads still retry once; newer receipts store refreshed details |
| Cash sales | Concurrent identical uploads save one receipt and deduct once; changed receipt payload and stale price are rejected without changing stock |
| Revocation | Clearing branch access blocks uploads and branch reads; restoring it permits the original unsynced payload; unused invitations cannot undo the change |
| Removal | Removing one membership preserves historical receipts and the account's other membership and role |

All reads and mutations use the public client key and the applicable account's access token. Permission checks require the expected database error code and HTTP status. Missing RPCs, invalid authentication, server failures, and network errors fail the run; they do not count as permission denials. The deliberate stale-version checks require exactly SQLSTATE `PT409` with HTTP `409`. The seventh migration installs this domain-conflict response. Custom `40001` errors can cause [unbounded transaction retries on affected Supabase/PostgREST versions](https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions); [PostgREST's PT status codes](https://docs.postgrest.org/en/stable/references/errors.html#raise-errors-with-http-status-codes) avoid that retry path. Generic timeouts, HTTP `500` errors or other SQLSTATE codes do not pass.

The concurrent-upload and branch-creation checks wait for both requests to settle before reporting failure or closing sessions. On normal completion or failure, the runner attempts to sign out only its own sessions using [Supabase's local sign-out scope](https://supabase.com/docs/guides/auth/signout). It does not request global sign-out on the test accounts.

## Local runner validation

On 1 November 2026, the 15 safeguard/transport unit tests passed. The embedded PostgreSQL suite also runs all 85 acceptance checks against the actual five migrations through a test-only Auth/HTTP adapter, alongside the existing 148 database checks and 16 runner-result assertions. The failure scenario confirms that a failed branch request waits for its concurrent partner, preserves the attempted branch ID, reports failure, and closes test sessions even when the other request committed.

The test package pins PGlite 0.5.14. On 3 November 2026, all local checks passed with that locked runtime, including the 85 complete runner checks, 148 database checks, and 16 runner-result assertions. The previous temporary dependency directory had been removed; the package and lockfile make the setup reproducible.

After installing dependencies, run only the database suite with:

```powershell
node supabase/tests/workspaces.test.mjs
```

An explicit installed PGlite module path remains supported as an optional argument.

These are local results. The adapter serializes requests on one embedded connection and stubs Auth, HTTP status mapping, and schema exposure. It does not verify hosted authentication, real PostgREST routing, network concurrency, or two-device behavior.

On 4 November 2026, the expanded runner passes 123 checks through the seven-migration embedded database, alongside 148 original database checks, 14 catalog/inventory scenarios, nine deployment-schema checks, 23 runner-result assertions, and the 15 safeguard tests. Inventory IDs are journaled before requests. A missing catalog RPC fails acceptance and preserves the attempted fixture manifest; it does not count as an authorization denial. This remains local validation.

## Results and retained fixtures

A successful run exits with code `0` and prints `Hosted acceptance passed`. Any failed check, request, or session cleanup exits with code `1`. Treat a run without a final successful result as incomplete.

The script prints the path of its saved report on success or failure:

```text
config/acceptance-RUN_UUID.local.json
```

The report contains the project URL, run ID, passed-check labels, attempted business/branch/sale/inventory IDs, final status, and session-cleanup outcome. Passwords, access/refresh tokens, account emails, and invitation codes are not included. Business, branch, product, classification and inventory request IDs are recorded before their creation requests, because a timeout can lose the response after the server commits.

Updates are written to an ignored `acceptance-RUN_UUID.pending.local.json` file and renamed over the report after a complete write. An interruption can leave a pending file; the previous complete report remains available. A hard interruption can also prevent session cleanup. Inspect the report and the development project before rerunning. Each new invocation creates a new run ID and new fixtures, rather than resuming an earlier run.

The successful run retains three new businesses, one additional branch in the first business, and three cash-sale receipts. Stock for the original cash-sale test item ends at seven from an opening quantity of ten. The inventory fixture adds one variant SKU, three classifications and movement/request records. Its source stock ends at nine, destination stock at three, and source threshold at four. The product is restored active; its brand remains archived to verify retained references. Failed runs can retain fewer records; use their manifests. Business names begin with `Acceptance` and include the run UUID. It intentionally does not bulk-delete records or Auth accounts. Use the manifest to review retained data; discard the dedicated test project when it is no longer needed.

Local credentials, reports, and pending reports match the existing `/config/*.local.json` Git ignore rule. Check the exclusions before publishing changes:

```powershell
git check-ignore config/acceptance.local.json config/acceptance-RUN_UUID.local.json config/acceptance-RUN_UUID.pending.local.json
```

## Phase 3–5 completion boundary

Keep hosted acceptance pending until the actual project run succeeds and its report is reviewed. Then perform the Android email-verification and password-recovery callback checks and the two-device outage/reconnect and installed-app settings/receipt/inventory checks in the [device acceptance checklist](DEVICE_ACCEPTANCE.md). Embedded tests, runner unit tests, a browser sample, or an APK build do not replace these checks. Do not mark these phases complete solely because the acceptance tooling exists.

## Hosted acceptance and conflict correction

On 4 November 2026, the first hosted run reproduced a stale business edit that failed to return within 15 seconds; an isolated probe still timed out after 45 seconds. The functions used application-level SQLSTATE `40001`, which affected PostgREST versions retry as serialization failures. The seventh additive migration replaces those explicit domain errors in five functions with `PT409`, preserving their ownership checks, signatures, grants and data. The same hosted probe subsequently returned HTTP 409/code PT409 in 177 ms. Readback found five corrected functions and no active matching conflict probes. The client handles PT409 and retains compatibility with earlier 40001 responses.

After the correction, all 123 hosted Auth/PostgREST checks passed with three distinct dedicated admin-confirmed accounts. Real concurrent sale/branch/transfer retries, tenant and role restrictions, revocation/restoration, immutable receipt branding, stock conservation and archive/restore checks passed. The report confirms all three test sessions were closed locally. Admin confirmation bypassed delivery for these test identities; SMTP/email verification links and native callbacks remain separate acceptance steps. The first failed run retained partial fixtures, and the successful run retained its documented fixtures. Both manifests and the generated credentials remain in ignored local configuration files.
