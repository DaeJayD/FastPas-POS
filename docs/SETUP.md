# Fresh Supabase setup

FastPas currently starts with a new database. No legacy schema export or old store records are needed for this path. Use a development project and test accounts first; live store acceptance remains outstanding.

## 1. Create the backend

Create a Supabase project in your own account. Save its database password privately. In its SQL Editor, run these files once, in order, checking that each succeeds before continuing:

1. [Business workspaces](../supabase/migrations/202610210001_business_workspaces.sql)
2. [Hybrid cash sales](../supabase/migrations/202610210002_hybrid_cash_sales.sql)
3. [Staff access](../supabase/migrations/202610210003_staff_access.sql)
4. [Staff branch assignments](../supabase/migrations/202610240001_staff_branch_access.sql)

Each file has its own transaction. They create the new `pos_*` tables and functions; they are not scripts to rerun after successful installation. Record which files were applied. Do not create the old `employees`, `products`, or `sales` tables to make the legacy screens work.

If the first three migrations are already installed, apply only the fourth. It adds branch reassignment and extends the Owner's staff listing; it preserves memberships and sales.

The current development project already has all four migrations applied through the SQL Editor. Do not rerun them there. Manual SQL execution does not populate the CLI migration history; before switching that project to CLI deployment, compare its history and mark the verified versions as applied using [migration repair](https://supabase.com/docs/reference/cli/supabase-migration-repair). Repairing history records versions without re-executing the schema changes. New projects still follow the four-file sequence above.

Keep `public` exposed through the Data API. Keep `fastpas_private` out of exposed schemas. Leave row-level security and the grants installed by the migrations in place. Business ownership is created through the app, using the authenticated account.

## 2. Configure accounts and email

In Supabase Authentication settings:

- Enable email/password registration and email confirmation.
- Set the minimum password length to at least eight characters. The client enforces eight; stricter server rules may reject a password and display the server's message.
- Add exactly `fastpas://auth-callback` to the allowed redirect URLs. Android and iOS register this scheme in this repository.
- Keep the confirmation and reset email templates using Supabase's confirmation URL. Configure custom SMTP before inviting external test users; the default service restricts recipients and rate limits.

The app uses PKCE. Request a confirmation or password reset on the installed app, then open the latest email link on that same device and installation. A later request can replace the saved verifier for an earlier email. Clearing app data or switching devices can invalidate the exchange. Request a fresh email if the link fails. Verification resend and password reset use the same callback.

The recovery screen requires a matching new password before returning to businesses. Cancel recovery signs the account out locally. These operations require connectivity; they do not modify sales or business ownership.

Reference: [mobile callbacks](https://supabase.com/docs/guides/auth/native-mobile-deep-linking), [SMTP configuration](https://supabase.com/docs/guides/auth/auth-smtp), and [client API keys](https://supabase.com/docs/guides/getting-started/api-keys).

## 3. Configure the app

From the repository directory in PowerShell:

```powershell
Copy-Item config/supabase.example.json config/supabase.local.json
```

Edit the local file with the project URL and public client API key from your project's Connect dialog. The existing configuration field is named `SUPABASE_ANON_KEY`; it is passed to the SDK's `anonKey` parameter. Use a client key, never a secret key, service-role key, database password, or SMTP password. The local file is ignored by Git. Project keys are not user accounts; the app signs users in separately.

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.local.json
```

The default `lib/main.dart` launches business workspaces and hybrid cash selling. `lib/workspaces/main.dart` remains an equivalent explicit target. SQLite selling targets mobile; use `lib/preview/main.dart` for the browser sample.

`lib/legacy_main.dart` retains the historical single-store interface for migration development. It requires its old database contract and is not connected to the new project. Attendance, suppliers, advanced inventory, reports, and the complete previous selling UI will move into the workspace flow in later phases.

## 4. Automated hosted acceptance

After setting up the development project, follow [hosted backend acceptance](HOSTED_ACCEPTANCE.md) to check real Auth, PostgREST isolation, staff permissions, and cash-sale retries. The opt-in runner uses three verified test accounts and creates retained fixtures in a disposable project. Credentials and results stay in ignored local configuration files. This run has not yet been performed; it does not replace the device checks below.

## 5. First business and acceptance checks

Use the [device acceptance checklist](DEVICE_ACCEPTANCE.md) for installation, repeatable stock quantities, account checks, and recording results.

1. Install on Android, register an Owner account, and verify its email on the same device. Create a business and its first branch. The server creates Owner membership automatically.
2. Open the branch online. Add a product, a price in PHP, and opening stock. Make a cash sale; confirm the saved receipt and acknowledged sync status.
3. Disconnect, sell another item, close and reopen the app, and check that the receipt remains pending. Reconnect and sync. Confirm that the cloud receives it once and stock changes once.
4. Create a second business and confirm that catalog and receipts stay separate. Test another unrelated account as well as one with different roles in two businesses.
5. Invite a verified staff email to a branch. Share the generated code yourself; invitation email delivery is not implemented. Accept from that staff account. Confirm its branch restrictions and that it cannot use Owner controls. Revoke access and reconnect that device to verify denial.
6. Sign out, test Forgot password, and verify the new-password form opens with the app both running and closed. Test resend, expired links, mismatched passwords, cancel, and signing in with the replacement password. Repeat on iOS when a macOS build is available.
7. Before a real store pilot, complete a two-device outage test, blocked-sale resolution, secure device enrollment, independent backup/restore, and release signing. Offline authorization expires after 24 hours from successful verification; removal cannot reach a disconnected device immediately.

These are acceptance steps to perform against the new project, not completed results. Automated tests use mocked HTTP and embedded PostgreSQL; they do not establish hosted Auth, email delivery, device callback routing, or production readiness.

Under Manage staff access, choose Edit branch access to change an employee's assigned branches. An empty selection preserves membership but prevents opening any branch. Saving cancels that employee's unused invitations for this business. Test removal of a branch, denial on that device's next reconnect, preservation of pending receipts, and uploading those same receipts after access is explicitly restored. Owner access is not editable here. A change in one business must not affect the same employee's other memberships.

## Optional legacy import

Only if old records are introduced later, export that database's schema first using [the inspection query](../supabase/inspect_legacy_schema.sql), obtain a schema-only dump, and rehearse an explicit tenant migration against a copy. Do not import old employee passwords. See [the legacy contract inventory](DATABASE.md).
