# FastPas POS roadmap

FastPas is being adapted from a store-specific application into a configurable mobile POS for small retail businesses. Android is the first release target. Each deployment serves one business with multiple branches.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 1. Interface | Graphite Volt theme, product-first Home, responsive selling flow, and management layouts | In progress |
| 2. Technical baseline | Compatible Android build tools, legacy code cleanup, and database inventory | Planned |
| 3. Data and identity | Versioned schema, authentication, roles, and branch access policies | Planned |
| 4. Business setup | Business details, receipts, settings, and configurable branches | Planned |
| 5. Catalog and inventory | Optional brands, categories, variants, receiving, adjustments, and stock transfers | Planned |
| 6. Sales | Atomic checkout, exact amounts, safe retries, payments, and saved receipts | Planned |
| 7. Returns and shifts | Partial returns, refund records, cash movements, and shift reconciliation | Planned |
| 8. Reports | Reconciled reports, exports, and optional attendance | Planned |
| 9. Release | Android device validation, migration rehearsal, backup restoration, and pilot testing | Planned |

## Current interface

Sign-in, product Home, order review, payment, and receipt screens use the new design. Inventory, Reports, and More have new navigation hubs; their deeper management pages still need layout updates.

Home includes product/SKU search, category filters, branch selection, stock counts, quantity controls, and a persistent cart. Products currently use category icons. Barcode scanning is planned and its control is disabled.

The separate UI preview runs on sample data without initializing the database. Its payment flow produces sample receipts without recording transactions. Preview behavior does not establish production authentication, stock consistency, or payment verification.

## Planned AI features

Sales summaries and inventory insights may be added after the core retail workflows are reliable. Providers, costs, data handling, and evaluation criteria are undecided. No AI feature is implemented yet.

## Later scope

Offline selling and synchronization, integrated payment processing, restaurant workflows, weighted products, unit conversions, and hosting unrelated businesses are outside the initial release. Printer and scanner support require testing with specific hardware.
