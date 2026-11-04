# Workspace sales

Phase 6A–6D implement the local selling flow. This is the authenticated business/branch route, separate from the sample preview. Installed-device acceptance and the earlier email/callback gates remain open.

## Product Home

Home reads the selected account/business/branch SQLite snapshot. Name and SKU search is case insensitive and trims outer whitespace. Categories are downloaded with the existing scoped stock query and retained for offline filtering. Filtering never removes cart selections. Phones use a product list; wider screens use a grid sized for the current text scale. Rows are built on demand. The cart count and exact total stay at the bottom, with Clear cart and Cash checkout.

Out-of-stock and negative local quantities cannot be incremented. Offline selling still requires a valid cached role/access window. A gray sync indicator does not imply lost data; the status text and pending/review counts describe the latest attempt. This is foreground synchronization, not an OS background-service guarantee.

## Review and cash

Opening payment creates one immutable `CheckoutQuote`: account, business, branch, names, SKUs, quantities, unit centavos and available stock. The dialog displays those lines, total due, editable cash and exact change before Complete sale. Cash is PHP; quantities are whole units. Cancel and Android Back preserve an unconfirmed cart.

The SQLite transaction verifies the quote against its current local snapshot. Changed names, SKUs, prices or stock require cancelling and reviewing the cart. This does not promise a fresh server price while disconnected. A later server validation failure retains the original receipt for review rather than rewriting it.

One local attempt ID records the receipt, stock deduction and pending upload atomically. Reconfirming an unchanged committed quote returns that receipt; changed cash is rejected. The quote stays in memory while the form is open. After process restart, committed receipts are recovered through Saved receipts; unfinished payment forms are not restored. Success clears the cart only after durable commit. Account changes close payment/details, clear browsing state and keep the account-change warning even if an earlier sync finishes later.

## Receipt history and performance

The receipt icon opens this device's branch history. All, Pending, Synced and Needs review filters read local status. Pages fetch at most 30 summaries, ordered by a stable row cursor; detail opens one saved payload. New receipts arriving between pages do not shift the cursor. Refresh returns to the newest page. Sync now retries the existing pending queue; blocked receipts remain for a future explicit resolution workflow.

Home reads grouped receipt counts instead of every saved JSON payload on each refresh. Receipt status has an index. These changes bound history reads and visible widgets; physical-phone startup, navigation and frame timings still require measurement. History does not download another device's receipts, edit an old sale, refund a payment or resolve a blocked transaction.

## Local upgrade and deployment

SQLite version 2 adds `category_id`/`category_name` with empty defaults and a receipt-status index. Existing device identity, access metadata, branding, sales, statuses and pending deductions are preserved. Empty category fields remain usable until the next successful sync. All existing cash-upload payloads remain compatible. No Supabase migration, reset or credential change is required.

Install the new APK as an update without clearing app data. Do not downgrade to a build whose database version is 1 after upgrading; it cannot open a version-2 file. Keep pending receipts intact and use the [device checklist](DEVICE_ACCEPTANCE.md) for acceptance. Production release signing and store distribution remain separate work.

## Validation, 5 November 2026

All 187 Flutter tests pass, including real SQLite upgrade/cursor/retry checks and phone/tablet layouts at 130% text. Static analysis is clean. The configured profile APK builds with dependency validation enabled and passes APK signature/runtime-entry checks. Widget-rendered Home and payment previews were inspected; these are not installed-phone results. No Android device was attached over ADB.

A read-only hosted check returned populated category labels through the new scoped stock query for an Owner. The staff account's accessible fixture businesses had no categorized stock rows, so the corresponding populated staff read remains unverified. Both test sign-in sessions were closed; no business data, memberships or server permissions were changed. The earlier 123 hosted checks establish their recorded Phase 5 scope, not the new phone workflow. Email delivery, native callbacks and the Phase 5/6 installed-device tables remain open.
