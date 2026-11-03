# Catalog and inventory

Phase 5 development adds **Catalog & inventory** to the selected business's Owner controls. It uses the workspace data, not legacy inventory tables. The sixth migration is local only; the development project still has the first five migrations applied. Do not rerun those files.

## Catalog

Owners can create/edit products and archive/restore them. Brand and category grouping is optional. Optional product families group SKU variants: each variant has its own SKU, price, and branch stock. The displayed/saved sale name includes the variant, so a receipt distinguishes sizes/colors. The combined name must fit the existing 120-character cash-sale contract. Existing ungrouped products remain usable.

Classifications can be renamed or archived without deleting product references. Existing archived classifications remain readable; new assignments require active classifications. Product edits carry a version, and writes retain a stable request ID for retrying a lost response. Repricing/archiving can make older pending sales require review under the existing server rules; recorded receipts are preserved.

Catalog and movement pages load 50 rows at a time. Product search is debounced and searches name/SKU. Management changes require internet. Downloaded products and variant names remain sellable through the established offline cash flow; stock-management writes are not queued offline.

## Stock

- **Receive stock** adds a positive whole quantity to one SKU/branch.
- **Set physical count** records the counted nonnegative quantity with a required reason.
- **Transfer stock** moves a positive quantity between branches of the same business. Source stock must cover the transfer. Both changes commit together.
- **Low-stock alert** stores a branch/SKU threshold; zero disables the alert.

Stock writes use the versions shown when the form opened. Another sale or adjustment invalidates a stale count/transfer instead of overwriting it. Retrying the same request ID and payload returns the original result without applying the change twice. After an error indicating stale/changed request details, cancel and refresh before starting another operation.

Only Owners manage catalog/inventory in this phase. Cashiers retain their assigned-branch selling rights. The server enforces business ownership, branch/product relationships, read-only client table grants, and private request/audit storage.

## Movement history and compatibility

Stock quantity changes and their immutable movement records share one database transaction. The ledger records item/SKU/branch names, before/after quantities, reason, actor, and command/receipt identity. Existing stock receives a clearly labeled migration-time snapshot, not invented receiving history. New sales use the existing cash validation/idempotency implementation through a wrapper that supplies ledger context. Duplicate sales do not create another deduction or movement.

Negative stock from cross-device offline overselling is still retained for explicit review. A transfer cannot oversell its source; a physical count can reconcile a shortage. Receiving can reduce an existing negative balance without hiding the remaining deficit.

The migration uses [PostgreSQL trigger functions](https://www.postgresql.org/docs/current/plpgsql-trigger.html) and preserves the established cash function in the private schema using [ALTER FUNCTION](https://www.postgresql.org/docs/current/sql-alterfunction.html). Private execution grants are revoked; the public cash RPC keeps its existing identity and permissions. No local SQLite reset is required.

## Validation and deployment boundary

The initial ten Phase 5 PostgreSQL scenarios pass locally, including permissions, variants, stale edits, transfer conservation/retry/rollback, low-stock thresholds, and sale-ledger rollback. The existing 148 database checks pass, and all 85 acceptance-runner checks plus 16 result assertions pass after applying the sixth migration in the embedded test database. Auth/HTTP are stubbed there; hosted/device acceptance remains separate.

Flutter analysis reports no issues. All 151 Flutter tests pass, including five catalog checks covering phone/tablet layouts at larger text, a lost transfer response retaining its original request and destination version, unavailable backend functions, and account changes closing an active stock editor. These use mocked HTTP responses, not a deployed backend.

Hosted deployment, fresh APK verification, and installed-device Phase 5 acceptance are still pending. Phase 3/4's real three-account hosted run also remains pending. Do not mark Phase 5 complete from local tests.
