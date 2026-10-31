# Hosted backend acceptance

This checks the Phase 3 workspace and cash-sale contract through real Supabase Auth and PostgREST. It is separate from the embedded PostgreSQL suite, which stubs Auth. A passing hosted run still does not verify email delivery, native callback routing, SQLite persistence, or two-device offline operation.

The runner has been prepared locally. No hosted run has been completed for this project yet.

## Prepare a disposable development project

Follow [fresh setup](SETUP.md) first: apply the four migrations, configure email/password accounts, and keep `fastpas_private` out of exposed API schemas. Do not run this against a store's database. The runner cannot determine whether a project contains production data.

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
| Cash sales | Concurrent identical uploads save one receipt and deduct once; changed receipt payload and stale price are rejected without changing stock |
| Revocation | Clearing branch access blocks uploads and branch reads; restoring it permits the original unsynced payload; unused invitations cannot undo the change |
| Removal | Removing one membership preserves historical receipts and the account's other membership and role |

All reads and mutations use the public client key and the applicable account's access token. Permission checks require the expected database error code and HTTP status. Missing RPCs, invalid authentication, server failures, and network errors fail the run; they do not count as permission denials.

The concurrent-upload check waits for both requests to settle before reporting failure or closing sessions. On normal completion or failure, the runner attempts to sign out only its own sessions using [Supabase's local sign-out scope](https://supabase.com/docs/guides/auth/signout). It does not request global sign-out on the test accounts.

## Results and retained fixtures

A successful run exits with code `0` and prints `Hosted acceptance passed`. Any failed check, request, or session cleanup exits with code `1`. Treat a run without a final successful result as incomplete.

The script prints the path of its saved report on success or failure:

```text
config/acceptance-RUN_UUID.local.json
```

The report contains the project URL, run ID, passed-check labels, attempted business and sale IDs, final status, and session-cleanup outcome. Passwords, access/refresh tokens, account emails, and invitation codes are not included. Business IDs are recorded before their creation requests, because a timeout can lose the response after the server commits.

Updates are written to an ignored `acceptance-RUN_UUID.pending.local.json` file and renamed over the report after a complete write. An interruption can leave a pending file; the previous complete report remains available. A hard interruption can also prevent session cleanup. Inspect the report and the development project before rerunning. Each new invocation creates a new run ID and new fixtures, rather than resuming an earlier run.

The run retains three new businesses and their test records for inspection. Business names begin with `Acceptance` and include the run UUID. It intentionally does not bulk-delete records or Auth accounts. Use the manifest to review retained data; discard the dedicated test project when it is no longer needed.

Local credentials, reports, and pending reports match the existing `/config/*.local.json` Git ignore rule. Check the exclusions before publishing changes:

```powershell
git check-ignore config/acceptance.local.json config/acceptance-RUN_UUID.local.json config/acceptance-RUN_UUID.pending.local.json
```

## Phase 3 completion boundary

Keep hosted acceptance pending until the actual project run succeeds and its report is reviewed. Then perform the Android email-verification and password-recovery callback checks and the two-device outage/reconnect checks in the [device acceptance checklist](DEVICE_ACCEPTANCE.md). Embedded tests, runner unit tests, a browser sample, or an APK build do not replace these checks. Do not mark Phase 3 complete solely because the acceptance tooling exists.
