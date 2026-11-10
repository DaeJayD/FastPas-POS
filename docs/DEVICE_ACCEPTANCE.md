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

### Guided Android checks on 3 November 2026

The tester reports that the Phase 4 APK is installed and **Business settings** displays business details and branches. This confirms the initial settings screen check on the phone. Android version and installed build identity have not been independently inspected. The tester also changed the receipt footer to `FastPas test A`, saved, reopened the editor, and confirmed the value persisted. The tester created `Phase 4 check` at `Test address`, refreshed settings, and confirmed exactly one branch was listed. The tester renamed the new branch to `Phase 4 checked`, changed its address to `Updated test address`, and confirmed the receipt preview displays that name/address and `FastPas test A`. In the original stocked branch, the tester synced online, disabled Wi-Fi and mobile data, and recorded one exact-cash sale. The receipt retained `FastPas test A`, stock decreased by one, and pending receipts increased by one. After removing FastPas from Recent apps and reopening while still offline, the tester confirmed the saved receipt/footer, pending count, and single stock deduction survived. Reconnect behavior, immutable branding across settings changes, and the other checklist items remain pending until their results are recorded.

## Hosted isolation run

After three distinct test accounts are verified, fill their credentials into the ignored `config/acceptance.local.json`. Keep `allowTestWrites` disabled until the project and fixtures are ready. Then follow [hosted acceptance](HOSTED_ACCEPTANCE.md). The runner retains its test businesses and writes a local report; do not substitute manual screen checks for its database assertions.

Record failed steps and resolve them before marking Phase 3 complete. iOS build and callback acceptance remain pending until a macOS build and an iOS device are available.

During the reconnect/settings step on 3 November 2026, a settings read initially displayed the generic connection/Owner-access message. Refreshing with internet enabled loaded the details. This records successful retry recovery; the original request failure was not independently diagnosed from the generic message. After recovery, the tester saved `FastPas test B` successfully while outside the selling branch. Original-receipt synchronization/branding and new-receipt footer checks remain pending.

The tester subsequently confirmed all remaining guided Phase 4 phone tests completed on 3 November 2026. This is tester-reported acceptance of the installed Phase 4 build; no independent device trace or automated hosted report was obtained. The new settings-recovery message/Retry settings build passes 146 local Flutter tests, clean full analysis, and a fresh profile APK build; that updated build has not yet been installed on the test phone. The real three-account runner and other Phase 3 release gates remain separate.

## Phase 5 catalog and inventory

All checks below remain pending. The sixth migration is deployed and its nine schema checks passed on 4 November 2026; do not rerun it. For other projects, follow [the deployment procedure](CATALOG_INVENTORY.md#deployment-procedure). Install the new profile APK as an update without clearing app data. A locally built APK or widget screenshot does not establish a phone result.

Use a dedicated test business with Main and Second branches. Keep these fixtures separate from existing receipts and the automated hosted-runner fixtures.

| Check | Action | Pass condition |
|---|---|---|
| Product and classifications | As Owner, open Catalog & inventory. Add a brand/category/family, then a product with a family variant, a unique SKU, price PHP 19.99 and opening stock 10 in Main | Saved product name includes its variant; price, classifications and stock return after refresh/reopen; another business cannot see it |
| Receive and count | Receive 5 units with a reason, then set a physical count of 12 | Main changes from 10 to 15 to 12; history shows opening +10, receive +5 and count -3 with the supplied reasons |
| Transfer | Transfer exactly 3 units to Second and refresh both branches | Main has 9 and Second has 3; total remains 12; each branch has one corresponding transfer movement |
| Threshold | Set Main's alert threshold to 10, then refresh | Main still has 9, a low-stock alert appears, and no quantity movement is invented |
| Offline sale and restart | Open/sync Main's selling screen, disconnect, sell one unit for exact cash, fully close and reopen the app offline | One saved pending receipt survives; Main remains at 8 locally; catalog-management writes require connectivity and preserve entered values on failure |
| Reconnect | Restore internet and sync the same branch twice, then refresh management history | Pending clears; Main is 8 and Second is 3; one sale movement is recorded, with no duplicate deduction or receipt |
| Archive and restore | Archive the assigned brand, then edit/archive/restore the existing product; refresh | Its archived brand remains readable, a new product cannot choose that brand, stock remains unchanged, and saved receipts/history retain their recorded names |
| Stale count on two devices | Open a count on device A; receive stock on device B; submit A's stale count | A gets a changed-record message and retains its typed count; cancel/refresh shows B's stock without overwriting it |
| Account/role isolation | Switch accounts while a management form is open; try a cashier and an unrelated Owner | Previous form closes; Add product is disabled for the stale screen; cashier has no inventory management controls; unrelated businesses remain isolated |
| Layout and responsiveness | Use larger system text and the keyboard in product/classification/stock forms; search, change branch, load another page, open history and go Back | Fields remain reachable, Save/Cancel work, names/prices remain readable, current search results win, and navigation preserves app data |

Measure cold startup/navigation on the physical phone in profile mode. Report device model, Android version, installed build identity and observed failures separately from local test results. If an operation loses its response, retry the unchanged open form; after canceling, refresh before creating a different request. Do not change backend permissions or erase app data to simulate failures.

### Current build and hosted status, 4 November 2026

The development project now has all seven migrations installed. All fourteen deployed catalog/conflict checks pass, and the real three-account Auth/API runner passes 123 checks with admin-confirmed test identities. This does not prove email delivery or mobile callbacks. The profile APK includes the PT409 stale-edit correction; older versions can display a generic error for those new conflict responses. All 158 Flutter tests pass and analysis is clean.

Phase 5 `app-profile.apk` at that checkpoint: 98,720,450 bytes; SHA-256 `f428c23135cb1ffbc0c9fa1fc4aec461fe842fe6ed6de939d70087074f35473d`. No physical Android device was attached over ADB during this validation. The Phase 5 table remains pending until performed on the installed phone.

## Phase 6 installed-device checks

All checks below remain pending. Use the new Phase 6 APK as an update, preserving app data. The prior build identity above describes Phase 5. SQLite version 2 upgrades version 1 automatically; do not downgrade to an older version-1 build or clear data containing pending receipts. Keep the Phase 5 and email/native callback gates open until separately accepted.

Phase 6 profile APK built on 5 November 2026: 99,064,514 bytes; SHA-256 `43eaa288d49b0aa0f93559bfd21c5bab58198465f07985dfe943b01ff0e457bd`. All 187 Flutter tests and static analysis pass. The APK's v2 signature verifies with the development Android Debug certificate; required ARM32, ARM64 and x64 app libraries are packaged. This is a local development artifact, not a store release or confirmed installation. ADB reports no attached devices.

| Check | Action | Pass condition |
|---|---|---|
| Existing-data upgrade | Before updating, note a pending test receipt, product stock, receipt branding and saved history. Install the update and open the same branch offline | Original receipts/payloads/statuses, stock deductions and branding are still present; no extra receipt or deduction appears |
| Product browsing | Online, sync a test business with categorized products. Search a mixed-case name and SKU, clear search, then filter a category. Repeat offline | Correct local results, explicit no-match/out-of-stock states, readable prices and unchanged cart selections |
| Persistent cart | Select products from two categories; hide a selected product with search/filter and scroll the list | Cart count and total remain correct; Clear cart removes selections without changing stock or creating a receipt |
| Cash review | Select two units, open Cash checkout, check names/SKUs/quantities/unit prices/total; enter insufficient and excess cash. Cancel with Android Back and reopen | Exact due/change, insufficient cash rejected, no receipt before confirmation, cart retained after cancel |
| One confirmation | Tap checkout and confirmation rapidly using a dedicated test sale | One payment flow, one saved receipt and one stock deduction |
| Changed quote | On another authorized device, change the product price or stock while payment is open. Allow the selling device's periodic sync to download the change, then confirm | The form requests cancelling/reviewing; typed cash remains, and no new receipt or partial stock write occurs |
| Offline commit/restart | Disconnect Wi-Fi/data, complete one exact-cash sale, close/reopen the app, then open Saved receipts | Original pending receipt survives with original names, prices, change and branding; stock remains reduced once |
| Receipt history/reconnect | Open each status filter, detail and older pages where available. Restore internet and tap Sync now twice | Same receipt ID becomes synced once; quantities are not deducted twice; blocked receipts keep their original payload and review reason |
| Account switch | Switch accounts with a payment or receipt detail open and while sync is finishing | Old detail/payment closes; old cart, search and receipt rows clear; access warning remains and stale controls cannot submit |
| Layout/performance | Test larger system text and the keyboard on phone; open Home/history, change filters and navigate Back | Controls remain reachable and responsive. Record device/build, cold-start and navigation timings; local widget results are not phone timing measurements |

## Phase 7 installed-device checks

After applying migrations eight and nine to the development project, use a test branch and dedicated accounts. These checks are pending.

| Check | Action | Pass condition |
|---|---|---|
| Partial return | As an owner or assigned manager, return a unit from a synced receipt after a price change. Repeat with and without restocking on separate units. | Refunds use the receipt price. Stock increases only for the restocked units. The original receipt remains intact. |
| Drawer reconciliation | Open with ₱100, make a ₱75 sale with ₱100 tender, record a ₱25 refund, add ₱10 and remove ₱5. Close with ₱154.50 counted. | Expected cash is ₱155.00. The displayed variance is −₱0.50, and the reasons appear in recent movements. |
| Offline sale and close | Open a shift online, go offline, take a sale, reopen the app and reconnect. Attempt close before and after syncing. | The receipt keeps its shift ID, close waits for upload, and the sale counts once. |
| Lost shift reply and role scope | Interrupt an opening, movement or close response and retry from the same account after reopening. Switch accounts and try a different branch/device. | The original request resolves once. Other accounts and devices cannot read or post to that drawer. |

## Phase 8 installed-device checks

After applying migration ten to the development project, run **Cash reports** on a test branch as an owner or assigned manager. Check a period that contains a sale, a refund recorded on a later local day and a closed drawer with a variance. Verify the amounts and dates on screen, then save and open the CSV on the phone. Each daily row should match the screen and the receipt or closing records. Check a different branch and time zone, then switch accounts during a refresh and verify the old report clears. These checks remain pending.
