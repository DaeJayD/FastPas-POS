# Catalog and inventory

Phase 5 development adds **Catalog & inventory** to the selected business's Owner controls. It uses the workspace data, not legacy inventory tables. The sixth migration was applied once to the development project on 4 November 2026. A seventh corrective migration was also applied on that date; all seven are installed there, and none should be rerun.

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

On 4 November 2026, all 14 Phase 5 PostgreSQL scenarios pass locally, including permissions, variants, stale edits, transfer conservation/retry/rollback, low-stock thresholds, sale-ledger rollback, archived classification assignments, and negative-stock reconciliation. An upgrade rehearsal starts with an existing sale and stock, preserves the saved receipt and quantity, creates a migration snapshot, and retries the old receipt without another deduction. Nine read-only deployment checks also pass locally.

The existing 148 database checks pass. The expanded three-account acceptance runner passes 123 checks plus 23 report/failure assertions against the seven migrations in the embedded database. It now covers every catalog/inventory RPC, classification and variant retries, receiving, stale counts, concurrent transfer retries, conservation, direct-write restrictions, archive/restore, and movement history. Attempted inventory IDs are recorded before writes, and missing catalog RPCs fail the run. Auth, HTTP status mapping and concurrency are stubbed/serialized in those local results; the separate hosted result is recorded below.

Flutter analysis reports no issues. All 158 Flutter tests pass, including 12 catalog checks for phone/tablet layouts at larger text, product creation in the selected branch, exact variant prices, archived classifications, paginated reads, out-of-order search replies, stale count forms, lost transfer responses, unavailable backend functions, and account changes closing/disabling management. The account-switch test first reproduced an enabled Add product button; the screen now clears its readiness state on identity changes. These tests use mocked HTTP responses. Widget-rendered forms and history were inspected; they do not establish physical-device behavior or frame timings.

The configured profile APK rebuilt successfully on 4 November 2026 with build dependency validation enabled (approximately 94.1 MB). Existing Android tooling emits upcoming support warnings; it does not block this build. The APK has not been installed or accepted on the phone.

## Deployment procedure

The current project has already completed deployment. For another development project with only the first five migrations installed:

1. In the intended project's SQL Editor, run [the read-only preflight](../supabase/catalog_inventory_preflight.sql) and record the counts. Require `phase_4_installed = true` and `phase_5_installed = false`. If Phase 5 is already installed, stop and inspect its deployed definition; do not rerun or overwrite the migration blindly.
2. Apply only [the sixth migration](../supabase/migrations/202611030001_catalog_inventory.sql), once. This step assumes the first five migrations are already installed in that target project. Keep the pending receipts and app data. The file wraps its changes in one transaction.
3. Apply [the seventh conflict-response migration](../supabase/migrations/202611040001_conflict_responses.sql) once, then run [its five-function verification](../supabase/verify_conflict_responses.sql). All five rows must pass.
4. Run [the read-only verification](../supabase/verify_catalog_inventory.sql). All nine rows must pass. Compare the recorded business/branch/product/stock/receipt counts and total stock while no sales or inventory changes are occurring. Schema checks do not prove signed-in authorization.
5. Prepare the three verified test accounts locally, then run [hosted acceptance](HOSTED_ACCEPTANCE.md). The runner requires all seven migrations, explicit fixture-write opt-in, and retains its test data. Keep credentials out of Git and chat.
6. Install the new profile APK as an update preserving data, and complete [Phase 5 device acceptance](DEVICE_ACCEPTANCE.md#phase-5-catalog-and-inventory). Real-account tests and physical-device acceptance remain separate from schema deployment. Phase 3/4's separate release gates remain open. Do not mark Phase 5 complete from local tests.

## Deployed development verification

On 4 November 2026, the hosted preflight found Phase 4 installed and Phase 5 absent. The exact local sixth-migration text was read back from the editor before execution. SQL Editor returned `Success. No rows returned.` All nine read-only schema/grant checks passed afterward. Before/after counts matched: one business, two branches, one product, four receipts, one stock row and fourteen total units. These counts precede acceptance-runner fixtures. The first five migrations were not rerun. The ignored local deployment report records the migration hash and individual results; manual SQL execution still does not populate CLI migration history.

## Hosted acceptance and conflict correction

On 4 November 2026, the first hosted run reproduced a stale business edit that failed to return within 15 seconds; an isolated probe still timed out after 45 seconds. The functions used application-level SQLSTATE `40001`, which affected PostgREST versions retry as serialization failures. The seventh additive migration replaces those explicit domain errors in five functions with `PT409`, preserving their ownership checks, signatures, grants and data. The same hosted probe subsequently returned HTTP 409/code PT409 in 177 ms. Readback found five corrected functions and no active matching conflict probes. The client handles PT409 and retains compatibility with earlier 40001 responses.

After the correction, all 123 hosted Auth/PostgREST checks passed with three distinct dedicated admin-confirmed accounts. Real concurrent sale/branch/transfer retries, tenant and role restrictions, revocation/restoration, immutable receipt branding, stock conservation and archive/restore checks passed. The report confirms all three test sessions were closed locally. Admin confirmation bypassed delivery for these test identities; SMTP/email verification links and native callbacks remain separate acceptance steps. The first failed run retained partial fixtures, and the successful run retained its documented fixtures. Both manifests and the generated credentials remain in ignored local configuration files.

Final local verification after the conflict correction: all 158 Flutter tests pass, full analysis reports no issues, all 30 backend test cases pass, and the configured profile APK builds. The final read-only hosted query passes all fourteen catalog/conflict checks and confirms that the original business, branch, product, receipt and stock counts are unchanged after excluding retained acceptance fixtures. No Android device was attached over ADB, so installation, native callbacks, physical-device timing and Phase 5 phone acceptance remain pending.
