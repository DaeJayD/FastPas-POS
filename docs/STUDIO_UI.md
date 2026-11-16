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
