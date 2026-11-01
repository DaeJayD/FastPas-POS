# Database contracts

New installations use the five migrations under `supabase/migrations`, starting with business workspaces, then hybrid cash sales, staff access, staff branch assignments, and business settings. Follow [fresh setup](SETUP.md). The current development database was provisioned with these five migrations without importing legacy records. A legacy export is needed only if old records are imported later.

## Legacy source inventory

This inventory is inferred from legacy application queries. The additive workspace migration under `supabase/migrations` defines the new business foundation, not the legacy schema. Legacy database types, constraints, indexes, triggers, grants, row policies, and production contents have not been verified. No legacy data migration has run; the five new workspace migrations are deployed to the development project.

| Relation | Fields referenced by the app | Current purpose |
|---|---|---|
| `branches` | `id`, `name`, `location` | Branch identity and location labels |
| `employees` | `id`, `user_id`, `name`, `username`, `password`, `phone`, `dob`, `branch`, `role`, status/profile fields | Legacy sign-in, staff profiles and attendance identity |
| `brands` | `id`, `name`, `description`, `created_at` | Optional catalog grouping |
| `branch_brands` | `branch_id`, `brand_id` | Assign brands to branches |
| `categories` | `id`, `brand_id`, `name`, `description` | Product grouping |
| `products` | `id`, `name`, `sku`, `price`, `brand_id`, `category_id`, `supplier_id` | Retail catalog and supplier assignment |
| `branch_stock` | `id`, `branch_id`, `product_id`, `current_stock`, `low_stock_threshold`, `last_updated` | Stock per product and branch |
| `inventory_movements` | `product_id`, `branch_id`, `movement_type`, `quantity`, `previous_stock`, `new_stock`, `user_id`, `username`, `reason`, `created_at` | Stock history |
| `suppliers` | `id`, `name`, `contact_person`, `phone`, `email`, `created_at` | Supplier contacts |
| `sales` | `id`, `created_at`, `subtotal_amount`, `tax_amount`, `discount_amount`, `total_amount`, `payment_method`, `cash_given`, `change`, `status`, `cashier_name`, `cashier_role`, `branch_location` | Sale snapshots |
| `sale_items` | `sale_id`, `product_id`, `quantity`, `unit_price`, `total_price`, `created_at` | Saved sale lines and product relationships |
| `attendance` | `id`, `user_id`, `date`, `time_in`, `time_out` | Staff attendance |
| `calendar_events` | `id`, `branch_id`, `event_date`, `event_type`, `description`, `created_by`, `created_at` | Branch calendar |
| `product_inventory_summary` | Columns consumed by inventory export | Assumed reporting view; its definition is absent |

## Migration boundary

For an optional legacy import, first obtain a schema-only export and review access policies from that database. Identify which employee identifier is referenced by each foreign key. Record all constraints and view definitions before writing import migrations. Rehearse against a copy with representative data and test backups before any production migration. The fresh setup does not require this step.

The employee-table username/password lookup remains a legacy contract. Replace it with Supabase Auth, verified role membership, and branch policies. UI role checks and `PosSession` are presentation state and do not enforce server authorization. Do not carry plaintext or default employee passwords into the new identity design.

Keep branch IDs through new schema boundaries; current employee and sales records also identify branches by text. Resolve aliases and duplicates during migration. Add business ownership and the appropriate unique and foreign-key constraints after existing data has been checked.

## Deferred integrity work

- Sales, line items, and stock updates are still sequential. Branch stock updates are now scoped to the resolved branch, and failures produce a receipt warning. A failure after sale insertion can still leave partial data. Phase 6 must use a server transaction, exact monetary amounts, idempotency keys, and concurrency checks.
- Stock changes and movement entries are separate writes. Phase 5 must make them atomic and reject stale quantities. Confirm nonnegative stock and one stock row per branch/product.
- Movement writers use `in`/`out`, while some reporting filters expect `stock_in`/`stock_out`. Standardize vocabulary and backfill explicitly before relying on those reports.
- Low-stock rules differ between older dashboard summaries and per-product thresholds. Reconcile them during inventory work.
- Historical line names are joined from the current product catalog. Preserve product/SKU/name snapshots in the sale schema so later edits or deletions cannot alter receipts.
- Supplier assignment is currently a product field. Confirm whether one or multiple suppliers per product are needed before introducing a join table.
- Reporting totals and exports need reconciliation against transaction status, returns, and the store timezone. No financial reconciliation is claimed by the interface or refactor phases.
