# Workspace device acceptance

Phase 3 stays open until hosted account isolation and the device checks below pass. Use the development project and test transactions. Record the device, Android version, app build, date, and observed result for each check. An APK build or a unit test is separate evidence.

## Preparation verified on 31 October 2026

- The development debug APK has the FastPas label, the `fastpas://auth-callback` intent filter, and ARM32, ARM64, and x86_64 libraries. Its minimum Android API is 24; target API is 36.
- All 15 local hosted-runner safeguard tests pass. Three verified accounts are still needed for the actual hosted run.
- A new isolated Android API 36.1 emulator failed during OS boot: SurfaceFlinger aborted with `hasReadColorBufferDma`, including with SwiftShader and Vulkan disabled. APK installation was rejected because the device was still booting. No app startup or native callback result was obtained. Use a physical Android device or a working emulator for the checks below.

## Install and create the first account

1. Build the default app with your ignored development configuration:

   ```powershell
   flutter build apk --debug --no-pub --dart-define-from-file=config/supabase.local.json
   ```

2. Transfer `build/app/outputs/flutter-apk/app-debug.apk` to the Android test phone and install it. Keep existing app data if there are pending receipts. For a connected USB test device, select its serial explicitly:

   ```powershell
   adb devices -l
   adb -s YOUR_DEVICE_SERIAL install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

   For startup and navigation performance checks, build with `--profile` in place of `--debug`, then install `build/app/outputs/flutter-apk/app-profile.apk` as an update. Flutter recommends [profile mode on a physical device](https://docs.flutter.dev/testing/build-modes) for performance analysis; debug-mode timings include development overhead. Keep the same development configuration and signing key so existing app data is preserved.

3. Open FastPas POS, choose **Create an account**, and enter your own email and a password of at least eight characters. Enter credentials directly on the device; do not put them in issues, screenshots, or reports.
4. Open the latest verification email on that same device and installation. Return to FastPas, sign in if needed, and create a test business and its Main branch.
5. Add one item priced at PHP 25.00 with opening stock of 10. Keep this fixture separate from hosted-runner fixtures.

Registration and confirmation require connectivity. If email delivery is restricted by Supabase's default service, configure custom SMTP before adding external testers; keep email confirmation enabled. See [account setup](SETUP.md#2-configure-accounts-and-email).

## Required checks

All checks in this table are pending until performed on installed devices.

For the UI revision, also check Add product and Cash payment with the keyboard open and larger system text. Field labels should remain separated, invalid amounts should stay editable in the dialog, and Android Back should return from a branch while background sync is running. Reopen that branch immediately and confirm its catalog and pending receipts remain usable. Measure cold startup and branch navigation with the profile build; widget tests alone do not establish phone performance.

| Check | Action | Pass condition |
|---|---|---|
| Online checkout | Sell one unit for exact cash | Receipt is acknowledged; stock becomes 9 |
| Offline restart | Disconnect, sell one unit, fully close and reopen FastPas | Receipt survives as pending; local stock is 8 |
| Reconnect and retry | Reconnect, sync, then sync again | Same receipt is acknowledged once; server stock is 8 |
| Second device | Sign in and open the same branch online on device B | Refreshed stock is 8; device A retains both acknowledged receipts; no duplicate deduction |
| Business isolation | Create a second test business and switch between them | Each shows only its own catalog, stock, and receipts |
| Unrelated owner | Use a different verified account on device B | First owner's businesses and receipts are inaccessible |
| Staff restrictions | Owner invites a verified test account as cashier to one branch; staff accepts | Assigned branch opens; Owner controls and unassigned branches are denied |
| Branch revocation | On device A, clear staff branch access while device B has a pending offline receipt; reconnect B | Branch access is denied and the pending receipt is retained |
| Access restoration | Restore that branch and reconnect B | Original pending receipt uploads once with its original identity |
| Membership removal | Remove staff from one business while it belongs to another | Removed business becomes inaccessible; other membership and historical sales remain |
| Verification callbacks | Request separate fresh links with the app running and fully closed | Each latest link opens FastPas and completes verification without duplicate exchanges |
| Password recovery | Test fresh reset links with the app running and fully closed | New-password form opens; mismatches are rejected; replacement password signs in |
| Invalid recovery | Test an expired or already-used link, then cancel a valid recovery | No unauthorized session; useful retry message; cancel returns to signed-out state |
| Offline access expiry | Leave an enrolled device disconnected beyond the 24-hour authorization period | New sales are blocked; saved pending receipts remain |

Do not clear app data, uninstall, or change device time to shortcut a persistence or expiry check. Do not use real customer data or payments. A disconnected device cannot receive an access revocation until it reconnects; assess offline operation within the documented authorization window.

Saved receipts currently belong to the local account/branch database on the device that recorded them. Synchronization uploads receipts and refreshes catalog/stock; it does not download other devices' receipt history into this screen. Shared reporting remains a later phase.

## Phase 4 business settings checks

The Phase 4 profile APK rebuilt on 1 November 2026. Install the current `app-profile.apk` as an update with existing app data retained. The fifth migration is already applied to the development project; do not rerun it. All ten deployed-schema/grant/data-count checks passed. The following installed-app checks remain pending:

| Check | Action | Pass condition |
|---|---|---|
| Owner details | Open **Business settings**, change test business/contact/footer values, save and reopen | Saved values return; invalid email/name stays editable; PHP currency remains fixed |
| New branch | Add a test branch, refresh, then edit its name/address | One branch is created; its ID stays the same after editing; it is available in branch selection |
| Staff assignment | Assign a test cashier to the new branch using staff access | Cashier sees only its assigned branches and cannot open Owner settings |
| Concurrent edits | Open the same details on two devices; save one, then save the stale form | Stale save is rejected and retains edits; cancel/refresh shows the accepted version |
| Offline branding | Sync branch A with footer A; disconnect and sell one test item; restart the app | Receipt remains pending with the business/branch/contact/footer recorded at checkout |
| Rename while pending | On device B, rename the business/branch and set footer B; reconnect device A and sync twice | Original receipt keeps footer A and original names; it uploads once; a subsequent sale uses refreshed footer B |
| Tenant and account isolation | Switch businesses/accounts with settings or a receipt open | Previous account's editor closes; no other business's details appear in the selected branch or new receipt |
| Keyboard and navigation | Use larger system text, open/edit all fields with the keyboard visible, then return to businesses | Every field can be reached; Save/Cancel stay usable; returning refreshes business and branch names |

For a lost branch-creation response, refresh the branch list before starting a different request. Retrying within the same open form uses the same request identity. Do not create network failures by changing backend permissions or deleting existing data.

## Hosted isolation run

After three distinct test accounts are verified, fill their credentials into the ignored `config/acceptance.local.json`. Keep `allowTestWrites` disabled until the project and fixtures are ready. Then follow [hosted acceptance](HOSTED_ACCEPTANCE.md). The runner retains its test businesses and writes a local report; do not substitute manual screen checks for its database assertions.

Record failed steps and resolve them before marking Phase 3 complete. iOS build and callback acceptance remain pending until a macOS build and an iOS device are available.
