# Phase 6 sales plan

Status: Phase 6A implemented locally following the user's continuation. Phase 5's catalog/conflict migrations are deployed and its 123 hosted Auth/API checks pass; installed-phone acceptance, email delivery and native callbacks remain pending. Local Phase 6 work does not complete those earlier gates or establish release readiness.

## Starting point

The workspace selling route is `lib/hybrid/hybrid_pos_screen.dart`. It already supports cart quantities, exact PHP cash input, local receipts and sync status. `LocalStore.checkout` commits the receipt, stock deduction and pending upload together. `SyncService` retries the saved receipt ID and payload, rechecks access and keeps blocked sales for review. The existing cash RPC and inventory ledger must continue to work with older queued receipts.

The richer product-first interface under the legacy/sample routes is not the workspace selling screen. Its appearance can guide this phase, but its legacy data queries must not be connected to workspace businesses.

## Delivery order

| Slice | Deliverable | Required evidence |
|---|---|---|
| 6A. Stable cart and checkout | Typed cart/quote boundary scoped to account, business and branch; quantity editing, remove/clear, exact totals and one active payment flow | Real SQLite tests for changed price/stock, repeated confirmation, transaction failure, expired access and account changes; no partial receipt or stock write |
| 6B. Product-first selling Home | Graphite Volt product list/grid, local name/SKU search, category filter where cached, clear stock state and persistent cart summary | Phone/tablet and larger-text checks, keyboard forms, bounded visible widgets with a large catalog, empty/error/offline states |
| 6C. Review and cash payment | Review item quantities/prices/total, cash received and change before confirmation; saved receipt opens after durable local commit | Exact-cent boundary cases, insufficient cash, no silent repricing during payment, double-tap prevention, safe cancel/back behavior |
| 6D. Receipt history and review status | Separate paginated local receipt history with detail, pending/synced/needs-review filters and explicit sync retry | Restart preservation, immutable names/branding/amounts, stable retry IDs, no receipt mutation or duplicate upload |
| 6E. Acceptance and handoff | Full regressions, migration rehearsal if local storage changes, configured profile APK, hosted checks and physical-phone script | Earlier phase gates remain visible; real backend/device results are recorded separately from mocks and embedded tests |

## Checkout contract

1. A quote contains product IDs, recorded names/SKUs, selected quantities and integer centavo prices, plus the immutable account/business/branch context. Money is calculated with integers.
2. Entering payment freezes the reviewed quote. If a sync changes its price, product availability or usable stock, checkout requests review rather than silently using a different total. Verify the quote against the local database inside the transaction that records the sale.
3. Only one payment/confirmation operation can run for a cart. A repeated tap or a retry after a local commit must resolve the same checkout attempt, not create a second receipt. Preserve the committed receipt identity if reading or showing it fails afterward.
4. Persist the receipt, its branding snapshot, stock deduction and upload identity atomically before showing success. Network synchronization must not hold the local confirmation or navigation open.
5. Canceling an unconfirmed payment preserves the cart. A successful local commit clears that cart exactly once. Account changes close the old flow; they must not submit or display another account's records.
6. Pending and blocked receipts retain their original payloads. Retry never edits prices, receipt branding or quantities to make an old receipt pass current validation. Resolution/reversal belongs to an explicit later workflow.

The price-change and repeated-entry regressions were reproduced before correction. `CheckoutQuote` freezes displayed lines and scope before payment. SQLite checks them within the sale transaction and requests review if names, SKUs, prices or available stock changed. The open form keeps entered cash on failure. Its stable attempt ID returns the original receipt for an unchanged retry, including after reopening the database; changed cash on a committed attempt is rejected. A quote is held in memory, so a full process restart recovers committed receipts through Saved receipts rather than restoring an unfinished payment form.

One active payment flow locks quantity/product changes until it closes. Clear cart removes selections without recording a sale. Account changes close payment and receipt dialogs. Receipt, stock and pending upload still commit atomically with the existing payload and version-1 schema. Tests cover concurrent confirmation, caller mutation, transaction rollback, expired access and account/business/branch boundaries. Product-first Home, the expanded review flow and separate receipt history remain subsequent slices.

## Storage and interfaces

- Keep `LocalStore` as the SQLite transaction boundary and `SyncService` as the upload/access boundary. Give the screen a typed sales interface instead of placing new arithmetic and persistence inside widget callbacks.
- The local database is currently version 1. Offline category filters require cached classification metadata that the current products table does not contain. Add a versioned, additive upgrade if this metadata is included; preserve all existing products, device identity, receipt payloads, statuses and pending deductions. Test upgrading a populated version-1 file.
- Keep sales history local to the selected account/business/branch in this phase. Downloading other devices' receipts needs a separate scoped pagination/sync contract; do not imply shared history from local results.
- Retain existing cash-upload compatibility. Any future server change must be additive and keep old unbranded/branded receipt retries valid. Inventory history must still get one movement per accepted sale.
- Use the shared theme and form controls. A search or category filter must not discard cart selections. Retain lazy rendering; measure cold startup and navigation on the physical phone in profile mode before claiming performance gains.

## Scope limits

The first slice remains cash in PHP and whole SKU units. Provider-verified wallet/card payments, tax configuration, discount authorization, split tenders, printer/scanner hardware, production receipt numbering and payment refunds need their own agreed contracts and tests. Do not present a manually recorded tender as a verified payment. Returns and cash-shift reconciliation remain Phase 7.

## Completion gate

The phase is complete only after the scoped selling flow works online/offline, stored receipts survive restart, retries do not double-deduct, quote changes cannot bypass review, tenant/account restrictions hold, and the hosted plus installed-device checks pass. Static analysis, unit/widget/SQLite/embedded tests and an APK build are necessary local evidence; they do not substitute for those acceptance results.
