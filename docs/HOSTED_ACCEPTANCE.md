# Hosted backend acceptance

This checks the Phase 3 workspace/cash-sale and Phase 4 business-settings contracts through real Supabase Auth and PostgREST. It is separate from the embedded PostgreSQL suite, which stubs Auth. A passing hosted run still does not verify email delivery, native callback routing, SQLite persistence, or two-device offline operation.

The runner has been prepared locally. No hosted run has been completed for this project yet.

## Prepare a disposable development project

Follow [fresh setup](SETUP.md) first: apply the five migrations, configure email/password accounts, and keep `fastpas_private` out of exposed API schemas. Do not run this against a store's database. The runner cannot determine whether a project contains production data.

Use Node.js 20 or later. No additional JavaScript packages are required for this runner. From the repository root, copy the configuration:

```powershell
Copy-Item config/acceptance.example.json config/acceptance.local.json
```

Edit the ignored local copy:

- Set `projectUrl` to the development project's HTTPS URL, and `expectedProjectRef` to its exact project reference. The runner supports the standard `https://PROJECT_REF.supabase.co` address.
- Set `publicKey` to that project's publishable key. Legacy `anon` keys are also accepted. Secret and service-role keys are rejected because privileged access would invalidate the isolation checks. Supabase distinguishes [client keys from keys that bypass row-level security](https://supabase.com/docs/guides/getting-started/api-keys).
- Supply three distinct, existing, email-verified test accounts under `ownerA`, `ownerB`, and `staff`. Register and verify them through the app first. These labels describe their roles in newly created fixtures; the script does not create Auth accounts or grant access to existing businesses.
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
| Staff | Invitation bound to verified email, invitation replay denied, different roles in two businesses, no self-promotion or direct membership edits, Owner membership protected |
| Business settings | Owner details round-trip; anonymous users, unrelated owners, and cashiers denied for all four settings RPCs; invalid inputs and stale versions rejected; direct REST writes denied |
| Branch settings | Concurrent creation retries return one branch; changed retry details and cross-business edits denied; edits preserve identity/version; new branches do not silently assign staff |
| Receipt branding | Business/branch/contact/footer snapshots remain unchanged after settings edits; old branded payloads still retry once; newer receipts store refreshed details |
| Cash sales | Concurrent identical uploads save one receipt and deduct once; changed receipt payload and stale price are rejected without changing stock |
| Revocation | Clearing branch access blocks uploads and branch reads; restoring it permits the original unsynced payload; unused invitations cannot undo the change |
| Removal | Removing one membership preserves historical receipts and the account's other membership and role |

All reads and mutations use the public client key and the applicable account's access token. Permission checks require the expected database error code and HTTP status. Missing RPCs, invalid authentication, server failures, and network errors fail the run; they do not count as permission denials. The deliberate stale-version checks require exactly SQLSTATE `40001` with HTTP `500`, matching [PostgREST's class-40 mapping](https://docs.postgrest.org/en/v13/references/errors.html#http-status-codes). Other HTTP `500` responses do not pass these checks.

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

## Results and retained fixtures

A successful run exits with code `0` and prints `Hosted acceptance passed`. Any failed check, request, or session cleanup exits with code `1`. Treat a run without a final successful result as incomplete.

The script prints the path of its saved report on success or failure:

```text
config/acceptance-RUN_UUID.local.json
```

The report contains the project URL, run ID, passed-check labels, attempted business/branch/sale IDs, final status, and session-cleanup outcome. Passwords, access/refresh tokens, account emails, and invitation codes are not included. Business and branch IDs are recorded before their creation requests, because a timeout can lose the response after the server commits.

Updates are written to an ignored `acceptance-RUN_UUID.pending.local.json` file and renamed over the report after a complete write. An interruption can leave a pending file; the previous complete report remains available. A hard interruption can also prevent session cleanup. Inspect the report and the development project before rerunning. Each new invocation creates a new run ID and new fixtures, rather than resuming an earlier run.

The successful run retains three new businesses, one additional branch in the first business, and three cash-sale receipts. Stock for the first business's test item ends at seven from an opening quantity of ten. Failed runs can retain fewer records; use their manifests. Business names begin with `Acceptance` and include the run UUID. It intentionally does not bulk-delete records or Auth accounts. Use the manifest to review retained data; discard the dedicated test project when it is no longer needed.

Local credentials, reports, and pending reports match the existing `/config/*.local.json` Git ignore rule. Check the exclusions before publishing changes:

```powershell
git check-ignore config/acceptance.local.json config/acceptance-RUN_UUID.local.json config/acceptance-RUN_UUID.pending.local.json
```

## Phase 3 and Phase 4 completion boundary

Keep hosted acceptance pending until the actual project run succeeds and its report is reviewed. Then perform the Android email-verification and password-recovery callback checks and the two-device outage/reconnect and installed-app settings/receipt checks in the [device acceptance checklist](DEVICE_ACCEPTANCE.md). Embedded tests, runner unit tests, a browser sample, or an APK build do not replace these checks. Do not mark either phase complete solely because the acceptance tooling exists.
