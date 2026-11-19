# Studio release UI

Implemented on `dev-release` from the local Studio mockup on 17 November 2026. The mockup toolbar, sample products, CSS illustrations and simulated payment flow are not part of the Flutter application.

## Behavior

- Shared semantic colors define Forest dark and Porcelain light across the workspace, checkout, inventory, Overview and related dialogs. Appearance is a device preference above navigation; switching preserves route and cart state. A failed preference write is exposed in the switch tooltip.
- Checkout uses a compact product list on phones, a cart summary/payment bar and an expandable cart. On wider screens products and cart share the screen. Quantity buttons retain large touch targets; payment stays anchored when space permits and remains scrollable for short screens or large text.
- Product search and category filters operate on the downloaded branch catalog. Cards show name, SKU, price and stock. Checkout highlights five or fewer units as a visual warning; inventory and Overview use saved branch thresholds. No stock/pricing rule changed. The scoped catalog currently has no image field; it uses a consistent inventory-icon fallback. The thumbnail component accepts a supplied HTTP(S) image without reaching into legacy store data.
- Inventory retains Owner access, existing mutations and paging. Stock filters apply to loaded products, with a visible loaded count and Load more action; they do not claim to search unloaded pages.
- Overview stays within the existing Owner/assigned-manager Cash reports route. Net cash sales and daily reconciliation retain the existing date/timezone report. Items sold and top sellers explicitly cover the latest 200 synced branch receipts before returns. Stock attention covers active products in the current branch, paged in batches of 500. These supplementary reads enforce account and branch scope; failures keep cash totals visible and offer retry. No proposed weekly chart or growth percentage was invented.
- Authentication, business/branch permissions, frozen checkout review, cash calculations, shifts, receipts, offline writes, retries and recovery remain in their existing modules. Pending uploads and blocked sales link to saved receipts; selling-access and connection warnings remain visible.
- Product selection and theme transitions are subtle and respect reduced motion. Layouts accommodate keyboard insets, landscape and larger text without replacing operational messages with decoration.

## Validation

On 17 November 2026:

- `flutter analyze --no-pub`: no issues.
- `flutter test --reporter expanded`: 243 passed; the opt-in hosted-write test was skipped. Checkout price/stock revalidation, tenant/account changes, offline persistence and recovery regressions remain covered.
- 74 focused UI/repository tests passed. The visual pass rendered 21 scenarios with real Flutter widgets and inspected checkout, inventory, Overview and cash-dialog screenshots in both themes. Sizes include 320/360px phones, 1024px tablets and 1440px wide layouts, with larger text; cart tests also cover short landscape and reduced motion. Screenshot data uses isolated test fixtures, never production sample rows.
- Three read-only requests against the development project verified the authorized cash-report scope, the bounded receipt payload and the branch-stock relationship/threshold query. No hosted business-data writes were performed for this UI validation.

Automated and widget-render evidence does not establish physical-device or production readiness. Android packaging results:

- `flutter build appbundle --release --dart-define-from-file=config/supabase.local.json` completed using the documented signing-property override, `com.fastpas.acceptance` and a temporary test key. Retained bundle: `build/acceptance/fastpas-studio-ui-acceptance.aab` (55,405,258 bytes), SHA-256 `a19387cfed686ed8057225026d5c99332ca05d15634f979ddb23f3d34ffa383f`. The manifest identifies the acceptance package and contains ARM32, ARM64 and x64 native libraries. `jarsigner` reported `jar verified`; it also reported self-signed/short-lived certificate, absent timestamp and JarInputStream manifest-order warnings. This is packaging/signature evidence, not Play acceptance. Temporary private key/properties were deleted after verification.
- `flutter build apk --profile --dart-define-from-file=config/supabase.local.json` completed. Phone artifact: `build/app/outputs/flutter-apk/app-profile.apk` (110,123,714 bytes), SHA-256 `71b6a03ae4daaeb712ff2bed0f4cce0d4ab0716873e5a71561d458966474f77c`. `apksigner` verified its v2 signature with the existing Android Debug certificate. Its package remains `com.example.vasenizzpos`; ARM32, ARM64 and x64 libraries are present. This is the normal development-profile handoff, not a store-signed APK.
- Existing Gradle, Android Gradle Plugin and Kotlin deprecation warnings remain. No dependency or schema migration was introduced for the UI.

The rebuilt profile APK was installed with `adb install -r` on the dedicated API 36.1 x86_64 emulator without clearing app data. The signed-out entry rendered in both appearances, the visible switch changed the theme, and Porcelain persisted after force-stop/relaunch. The native keyboard opened with readable fields and an accessible sign-in action. This smoke test did not sign into a business or repeat the earlier authenticated checkout/shift/reconnect acceptance. The emulator showed an unrelated Bluetooth system-service crash during startup; closing that system dialog and disabling Bluetooth in this dedicated emulator allowed the check to continue. No physical-phone performance result is claimed.

## Remaining release acceptance

Complete the outstanding physical two-phone outage/restart/reconnect checks, real email callbacks and production setup in [release preparation](RELEASE.md). A temporary-key acceptance bundle is not a store publication artifact. The owner must supply the permanent application ID and backed-up upload key before store release. No deployment, publication or completion of outstanding device acceptance is implied by this UI work.


For the installed-phone UI check, update the existing development install without clearing data. In both appearances, search/filter products and inventory, add/remove cart quantities, open/cancel cash payment with the keyboard visible, and verify the authoritative report totals. Repeat with larger system text and landscape. With a dedicated pending test receipt, check that the upload/review state remains reachable after switching appearance and restarting. Measure cold loading/navigation separately on the physical target phone; this work does not claim a measured speed improvement.


## Authenticated Android validation on 19 November 2026

The 17 November profile artifact (`59cec6b`, SHA-256 above) was exercised on the dedicated API 36.1 x86_64 emulator with the existing verified development Owner and isolated emulator fixture. No app data was cleared. Initial fixture stock was ten, its price was ₱30, and it had one earlier synced receipt.

| Check | Observed result |
|---|---|
| Actual branch catalog and SKU search | The intended branch downloaded; `EMU` matched its product at ₱30 with ten units. |
| Cart and appearance | Quantities changed 1 → 2 → 1 with totals ₱30 → ₱60 → ₱30. Switching Forest/Porcelain kept the cart. |
| Cash and keyboard | With Wi-Fi and mobile data disabled, ₱1 tender was rejected without leaving the form. Labels, error, remaining amount and confirmation remained readable above the actual numeric keyboard. Exact ₱30 tender saved one pending receipt. |
| Native persistence | Local stock became nine while hosted stock remained ten. After force-stop/relaunch offline, the same receipt ID, timestamp, cash, product/price and branding remained pending, stock stayed nine, and Forest remained selected. The pending-upload action stayed visible. |
| Reconnect and repeat sync | Original receipt became synced, history showed zero pending/two synced, and hosted readback showed exactly one matching new ID with nine stock. Two later manual syncs preserved these figures. |
| Inventory | The current branch showed ₱30 and nine stock in both themes. Out of stock and a no-match search showed the empty state; In stock restored the product. The product dialog remained reachable with the native keyboard and was canceled without creating a product. |
| Overview | Both themes showed actual summaries: net cash ₱30, two units before returns, zero stock alerts and the intended top seller. Gross ₱55 minus the previous ₱25 refund reconciled to net ₱30. A separate verified Owner API report matched the branch, dates, receipt count and amounts. |

One new test receipt was retained in the development fixture. No product price, manual stock adjustment, role, migration or production setting was changed. Private receipt IDs, raw UI evidence and the run manifest remain in ignored `config/studio-native-20261119.local.json` and `build/studio-authenticated/`.

### Landscape follow-up

The native run exposed a cramped short-screen layout: the two-row checkout footer left only 81 logical pixels for products with Android system insets. A regression reproduced it in both themes. On short, sufficiently wide screens at ordinary text scale, cart summary and payment now share one row; upload/review and access warnings retain their existing controls. Narrow phones and larger-text layouts keep the stacked presentation. The regression verifies available product space, reachable quantity controls, payment placement and opening the selected cart. Fresh `flutter analyze --no-pub` completed with no issues. All 245 ordinary Flutter tests passed, with the opt-in hosted-write test skipped; both new landscape regressions also passed the Flutter screenshot run. Updated packaging and installed-artifact results follow below.


### Updated artifacts on 19 November 2026

Both artifacts were rebuilt after the landscape refinement and passed signature verification. They replace the earlier files at the same ignored paths; the 17 November hashes above remain historical evidence.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `build/app/outputs/flutter-apk/app-profile.apk` | 110,123,714 | `83437f3699ba4a49a3d2151e67a67bdbef25ec3305af6e8190979386f9c4b24c` |
| `build/acceptance/fastpas-studio-ui-acceptance.aab` | 55,407,367 | `1605990cb1b74da3d641c401d764f1ab8455557e49a38a743e068d5480e5742a` |

The APK retains `com.example.vasenizzpos` and the existing Android Debug v2 signature. The bundle retains `com.fastpas.acceptance` and a temporary test certificate; `jarsigner` reported `jar verified` with the same test-certificate/manifest-order warnings described above. Temporary signing properties and the private test key were removed. Existing toolchain deprecation warnings remain. These files are development/acceptance artifacts, not owner-signed publication artifacts.


The rebuilt APK was installed as an update without clearing data. Its installed `base.apk` SHA-256 matched the new profile artifact above. The signed-in workspace and nine-unit stock survived the update. In actual landscape, the compact footer, quantity control, cart opening and frozen cash review were exercised in both themes. Canceling payment kept the cart; clearing the cart created no additional sale. The account was signed out after the zero-pending state was verified. This validates the new installed footer path; the earlier offline/reconnect sequence used the 17 November APK as identified above. Physical two-phone, email callback and production acceptance remain open.
