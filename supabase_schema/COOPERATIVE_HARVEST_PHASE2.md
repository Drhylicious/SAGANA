# Cooperative Harvest Inventory — Phase 2

Implemented in source; **the migration has not been applied to Supabase**. Run the SQL manually as required by `CLAUDE.md`. Existing uncommitted project work was retained.

## Behavior

- Manager/Officer physical receipt completes the offer, settles its existing sale, reconciles Farmer stock, and transfers cooperative stock in the same database transaction. Approval/delivery alone does not transfer ownership. A retry returns the original sale.
- Cooperative items use **Farmer ID + Crop Master ID + unit**, including archived items. Three JD–Tomato receipts of 50, 30, and 20 kg produce one 100 kg item and three immutable receipt batches. Another Farmer's 60 kg produces another item; the crop summary totals 160 kg. Sacks and kg remain separate; no conversion is invented.
- Each receipt snapshots its quantity, harvest date, original storage location, Farmer identity/name, source batch number/ID, offer ID, sale ID, receiver, receipt time, and inventory transaction ID. Farmer `inventory_batches` are never repurposed as cooperative stock.
- **Manual Stock Addition.** Adjust Stock → Restock creates its own batch with no offer and **no source Farmer** (the stock was not delivered by the Farmer; the item still belongs to its Farmer–Crop identity). History and the Batches tab label it **Manual Stock Addition** and show the responsible user, quantity, harvest date, storage location, notes and transaction ID. A zero quantity is rejected in the app with its own message and by the RPC.
- **Farmer name.** The Inventory card shows **Source Farmer: <name>**, and search matches it. The Program Distribution picker, the Add Product picker and the distributed line show **Crop — Farmer name** for Farmer harvest items, so same-crop items from different Farmers can be told apart. Supplies keep their plain name.
- Manual additions create another cooperative harvest batch. Adjustments and existing loan/program/sales movements remain signed inventory transactions; they do not overwrite original receipt quantities. **On hand = original receipts/additions + subsequent signed movements**, not the sum of original receipt quantities alone after stock has been used.
- History includes quantity transactions, item/reorder/photo edits, loan/product catalog publish/unpublish events, archive and restoration. Actor/Source Farmer snapshots and references survive subsequent changes. Older recorded transactions are imported; historical edits/publications that were never recorded cannot be reconstructed.
- Stock requests use a unique request ID bound to the actor, item and payload. The dialog keeps the same ID and freezes submitted values when retrying an uncertain result. Separate, intentional additions use new IDs.
- The existing delete action now archives an **empty, unreserved** item and unpublishes catalog links without deleting them. Remaining stock must first be used or explicitly adjusted with a reason. Archived history remains accessible through the inactive/archived switch. A later completed offer restores the same Farmer–Crop item; it does not republish catalogs automatically.

## SQL execution order

Use a maintenance window for the database migration and matching app rollout; Phase 2 revokes the old adjustment RPC from API clients. Do not deploy this Flutter build against the old schema.

1. Back up the database and run `supabase_schema_cooperative_harvest_phase2_preflight.sql` (read-only). Review current RPC definitions, policies, triggers, receipt evidence, source identity, ledger consistency, and pooled stock. Query 2a lists the legacy offers that will be skipped (expect the four reported above); queries 2b, 3, 4 and 5 must return zero rows.
2. Run **`supabase_schema_cooperative_harvest_phase2.sql`** in one execution. It is transactional and rerunnable. It locks receipt/inventory tables during conversion, backfills verified completed offers, preserves existing receipt transaction IDs, and archives emptied legacy pools. Re-running does not transfer again.
3. Run `supabase_schema_cooperative_harvest_phase2_verify.sql` (read-only). Anomaly queries must return zero rows; privilege checks must be false. The final crop summary is informational.
4. On staging, run `supabase_schema_cooperative_harvest_phase2_test.sql`. It exercises the real offer → accept → deliver → receive RPCs as Farmers, Manager and Officer, and rolls back its fixtures. Missing role fixtures cause an explicit failure. If the SQL editor stops after a failure, run `ROLLBACK;` before continuing.
5. Deploy the matching app, then perform the role/UI checks below. Also run the updated `supabase_schema_farmer_stock_management_test.sql` and the existing market-linking/order workflow SQL tests against staging; these have **not** been executed against your Supabase instance here.

Required existing foundations are the **current** Phase 1 receipt workflow (`supabase_schema_farmer_stock_management.sql`), crop identity, unit/batch numbering, inventory source/images, role-based staff access, loan inventory link and product sales schema. These are prerequisites, **not instructions to rerun their old scripts**. Preflight should confirm their actual deployed definitions. Do not apply Phase 1 or older receipt/delete/adjustment scripts after Phase 2; they would replace the new behavior.

### Preflight stop conditions

**Rollout history (2026-10-29).** The first migration attempt aborted because four completed offers had `received_by IS NULL`; Phase 2 was not installed (the missing-table errors in verify/test were a consequence of that rollback, and Farmer-stock test B13 still saw the Phase 1 duplicate-receipt rule). The read-only `supabase_schema_cooperative_harvest_phase2_receipt_diagnostic.sql` showed all four (offers `8b3bc79c…`, `f8deda1f…`, `22cba6b1…`, `32c23551…`) were accepted and settled by the Manager at acceptance: no `delivered_at`, no delivery photo, no `delivered`/`received` event, no receipt transaction, no cooperative stock. Their `received_at` equals `confirmed_at` to the microsecond, which is Phase 1's relabeling of old `confirmed` offers, not a receipt.

**Decision (2026-10-29): legacy offers are skipped, never stamped.**

- *Legacy* = `completed`, `received_by` NULL, `delivered_at` NULL, no delivery photo, no `delivered`/`received` event, and no `harvest_received` transaction. The migration does not transfer or touch them: their sale rows, `confirmed_*` fields and `received_at` stay exactly as they are. No `received_by`, delivery evidence or receipt time is invented.
- Every other completed offer is *modern* and is transferred automatically. A modern offer missing `received_at`/`received_by`/sale (for example, delivery evidence but no receiver) is inconsistent data: the migration still **aborts and rolls back**.
- The migration also aborts if the receipt ledger and completed offers disagree, if a source harvest/crop/Farmer identity is missing, or if a pooled legacy stock row has movements, reservations or catalog links.
- The preflight lists the skipped legacy offers (2a, informational) and the inconsistent ones (2b, must be zero); the verify script lists the skipped offers (1b, informational) and requires every modern completed offer to have exactly one batch.
- Legacy offers are completed and terminal, so no later status change can transfer them by accident.

A legacy pooled item is automatically split only when its balance equals its recorded receipts, it has no reservations, other movements, or loan/product/distribution links. **If preflight reports a consumed/adjusted/linked pool, stop:** its remaining stock and dependent references need an explicit Farmer allocation based on actual records. Do not delete those movements, replenish the pool artificially, or distribute the balance proportionally. The current data cannot establish that allocation automatically. A data-specific reconciliation script is required for such rows; none has been fabricated without seeing the affected data.

## Database changes

| Object | Change |
| --- | --- |
| `cooperative_inventory` | Farmer/crop snapshot IDs, `archived_at`, unique Farmer/crop/unit index; identity/duplicate/direct-stock-write/delete guards; metadata audit trigger |
| `cooperative_harvest_batches` | New immutable receipt/addition snapshots; unique offer and inventory transaction; restricted FK to retained inventory/transactions |
| `cooperative_inventory_history` | New immutable event ledger; indexed pagination; unique stock transaction reference; actor/Farmer snapshots and edit before/after data |
| `cooperative_stock_requests` | Private idempotency request ledger |
| `inventory_transactions` | Existing authoritative stock ledger retained; insert audit trigger, update/delete guard; API writes revoked |
| `cooperative_purchase_offers` | Completion/insert triggers transfer stock; API direct writes revoked; existing RPC workflow retained |
| `loan_items_master`, `program_products` | Audit publish/unpublish changes; refuse publishing archived items or swapping a catalog link's inventory identity |
| `confirm_cooperative_offer_receipt`, `_coop_receive_harvest` | Atomic receipt/transfer with retry safety and Farmer grouping |
| `adjust_cooperative_stock` | New authorized, row-locked, idempotent adjustment RPC; rejects negative balances, reserved-stock consumption and invalid decimals |
| `adjust_inventory_stock` | Old signature retained but API execution revoked to prevent bypassing request IDs |
| `delete_inventory_item` | Authorized empty-item archival, catalog unpublishing, no history destruction |
| Internal functions | `_coop_person_name`, `_coop_immutable_record`, `_coop_inventory_guard`, `_coop_inventory_audit`, `_coop_transaction_audit`, `_coop_catalog_audit`, `_coop_completed_transfer`, `_coop_preserve_transaction` |
| RLS/grants | New batch/history SELECT restricted to `is_staff()`; no client writes; request ledger private; internal transfer/name lookup execution revoked |
| Realtime | Cooperative inventory added to existing Supabase publication when present |

No changes to Farmer ownership, selling-channel eligibility, prices, buyer checkout, or loan/program accounting rules are introduced. Their existing signed stock transactions feed the history automatically.

## Verification performed

- `flutter gen-l10n`: succeeded for English and Tagalog.
- Targeted `flutter analyze`: **no issues found**. Whitespace checks pass for the modified Phase 2 files; the wider working tree has unrelated pre-existing whitespace findings.
- Follow-up round (2026-10-29): `flutter gen-l10n` re-run; the five Phase 2-related Flutter test files pass (**51 tests**, two new: Manual Stock Addition labeling and Farmer-aware program pickers). Analysis of the changed files shows no errors; `program_management_screen.dart` still reports its pre-existing style hints (missing braces, one unnecessary import), none on changed lines.
- Isolated PostgreSQL (PGlite) re-run against the updated migration, three modes: normal (adds a legacy offer that must be skipped and untouched, and a manual restock whose batch has no offer/Farmer), `--ambiguous` (consumed legacy pool aborts and rolls back) and `--inconsistent` (delivery evidence without a receiver aborts and rolls back). All three pass.
- Targeted Flutter tests: **49 passed**, including six new model/widget cases, error/retry loading, pagination beyond 50 entries, decimal/unit grouping and a 360 px Tagalog layout; existing Farmer-stock, inventory-source, offer-RPC and negotiation suites passed.
- Isolated PostgreSQL (PGlite) tests execute the migration and real Phase 2 PL/pgSQL against a minimal fixture: clean legacy backfill, reruns, 100 + 60 grouping, receipt/stock retries, exact decimals, immutable provenance, audit events, archive/restore and role/direct-write guards. This fixture stubs unrelated Phase 1 services; it does **not** prove compatibility with every live Supabase trigger or policy.
- A second isolated test confirmed an ambiguous consumed legacy pool is rejected and the complete migration rolls back without changing the original stock or schema.
- Live Supabase migration, full-schema SQL integration test, two-session concurrency, and device-to-device realtime remain manual checks.

Reproduce Flutter checks from the repository root:

```powershell
flutter gen-l10n
flutter analyze lib/presentation/screens/admin/admin_inventory_screen.dart lib/data/models/cooperative_inventory_item.dart lib/data/models/cooperative_inventory_history.dart lib/data/repositories/cooperative_inventory_history_repository.dart lib/presentation/widgets/cooperative_inventory_history.dart test/cooperative_harvest_phase2_test.dart
flutter test test/cooperative_harvest_phase2_test.dart test/farmer_stock_management_test.dart test/inventory_source_and_order_wording_test.dart test/coop_offer_rpc_contract_test.dart test/coop_offer_negotiation_test.dart
```

Optional isolated SQL reproduction (adds a disposable local dependency folder, not an app dependency):

```powershell
npm.cmd install --prefix .phase2_validation --no-save --package-lock=false @electric-sql/pglite
node test/support/cooperative_harvest_phase2_check.cjs
node test/support/cooperative_harvest_phase2_check.cjs --ambiguous
node test/support/cooperative_harvest_phase2_check.cjs --inconsistent
```

## Exact acceptance checks

1. As Farmer JD, harvest Tomato in kg, with a date and storage location, then submit offers of **50, 30 and 20**. Accept as Manager/Officer. Before delivery/receipt, confirm cooperative stock remains unchanged and Farmer stock is reserved.
2. Mark each offer delivered with the existing photo workflow. Confirm physical receipt as Manager/Officer. Expect **one JD–Tomato item, 100 kg**, actual source name, and **three batches** with 50/30/20 and matching harvest metadata/offer/sale references. Farmer sold stock increases only once.
3. Complete another Farmer's **60 kg** Tomato offer. Expect a second Farmer row and **160 kg** in the Tomato/kg summary. Search by each Farmer name; both rows must remain accessible. Test a non-kg unit separately; it must never enter the kg total.
4. Retry the same receipt RPC or submit it from two staff sessions simultaneously. Expect one sale, one batch, one receipt transaction and one transfer per offer. Submit different offers for the same Farmer/crop simultaneously: expect one item with the exact combined quantity. Run the verification SQL afterward.
5. Add **5.25 kg** using Adjust Stock → Restock, supplying harvest date/location. Expect one new batch labeled **Manual Stock Addition** (no offer, no source Farmer) and +5.25 history showing the responsible user; the zero-quantity attempt shows "Quantity cannot be zero". Retry the identical request UUID/payload: no second addition. Reuse that UUID with another quantity: expect rejection. Try 0, negative restock, overprecision, and an excessive deduction: expect rejection without any stock change.
6. Deduct **10 kg**, edit cost/reorder/photo, publish in Loan Catalog, and archive/unarchive the catalog entry. History must show time to seconds, action, responsible staff, Farmer, quantity changes and references. Original offer batches remain unchanged; on-hand reflects the signed adjustment. Test a Program Product publish/unpublish and loan/program stock deduction too.
7. Attempt inventory archival with stock/reservations: expect refusal. After stock reaches zero through legitimate movements, archive. Expect disappearance from active pickers, catalog unpublishing, and full history/batches under **Show archived / inactive items**. A later receipt from that Farmer/crop must restore the same item ID.
8. As Farmer and Buyer, verify cooperative batches/history cannot be read or changed. Farmer-owned harvest and personal stock history must retain the original records. Confirm Marketplace/order receipt and DA-AMAD flows still obey their existing ownership/reservation rules.
9. Open history with more than 50 events; Load more must reach older records. Test failed requests and Retry, English/Tagalog, a narrow mobile viewport, offline mutation restrictions, and realtime refresh while another staff account confirms a receipt.

## Complete file list for this change

Modified:

- `lib/presentation/screens/admin/admin_inventory_screen.dart`: real item rows, Farmer search, crop/unit summary, realtime/error states, history/batches integration, request IDs, protected receipt identity and archival.
- `lib/core/l10n/app_en.arb`, `app_tl.arb`: new Phase 2 text.
- `lib/core/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_tl.dart`: regenerated localization output.
- `supabase_schema/supabase_schema_farmer_stock_management_test.sql`: receipt retry expectation updated from refusal to idempotent success.
- Follow-up round: `lib/data/models/program_model.dart` (`DistributionItem` carries `source`/`sourceFarmerId` and a Farmer-aware `displayName`), `lib/data/repositories/program_repository.dart` (both inventory pickers select them), `lib/presentation/screens/admin/program_management_screen.dart` (Add Product, Distribute and the distributed line use `displayName`), `lib/presentation/screens/admin/admin_inventory_screen.dart` (Source Farmer line, zero-quantity message), `lib/data/models/cooperative_inventory_history.dart` and `lib/presentation/widgets/cooperative_inventory_history.dart` (Manual Stock Addition), the two `.arb` files plus regenerated localizations (`coopInvQuantityZero`, `coopInvManualAddition`), and the migration/preflight/verify SQL described above (legacy skip; manual batches carry no source Farmer).

Created:
- `supabase_schema/supabase_schema_phase2_offer_reservation_diagnostic.sql`: read-only investigation of the 25 kg reserved on offer `22cba6b1` (findings below).

- `lib/data/models/cooperative_inventory_item.dart`: extracted existing item model, source IDs/archive date and crop/unit totals.
- `lib/data/models/cooperative_inventory_history.dart`: immutable receipt/event parsing.
- `lib/data/repositories/cooperative_inventory_history_repository.dart`: paginated history/batch reads with propagated errors.
- `lib/presentation/widgets/cooperative_inventory_history.dart`: localized history and batch tabs, source/reference details, loading/error/retry/pagination.
- `test/cooperative_harvest_phase2_test.dart`: model/widget regression tests.
- `test/support/cooperative_harvest_phase2_check.cjs`: isolated PostgreSQL migration/behavior tests.
- `supabase_schema/supabase_schema_cooperative_harvest_phase2_preflight.sql`: read-only deployment checks.
- `supabase_schema/supabase_schema_cooperative_harvest_phase2_receipt_diagnostic.sql`: one read-only result set for the four reported legacy receipt blockers; runs on Phase 1.
- `supabase_schema/supabase_schema_cooperative_harvest_phase2.sql`: transactional migration and backfill.
- `supabase_schema/supabase_schema_cooperative_harvest_phase2_verify.sql`: exact post-deployment anomaly/privilege queries.
- `supabase_schema/supabase_schema_cooperative_harvest_phase2_test.sql`: full-schema rollback integration test.
- `supabase_schema/COOPERATIVE_HARVEST_PHASE2.md`: this execution/testing report.

## Reservation finding: 25 kg on offer `22cba6b1` (investigation only, no stock changed)

Evidence from the diagnostic row: offer for **60 kg**, accepted at **35 kg**; batch `BATCH-PEAN-20260816-2066` has quantity 60, available 0, sold 35, **reserved 25**.

- `inventory_batches.reserved_kg` is not an independent counter. `_inventory_batch_stock_guard()` recomputes it on every write as `quantity − available − sold − adjusted` (`supabase_schema_farmer_stock_management.sql:168`). Here that is 60 − 0 − 35 − 0 = **25**.
- The offer reserved the full 60 kg when it was made (`available_kg` → 0). The old `confirm_cooperative_offer(p_confirmed_quantity_kg …)` (`supabase_schema_cooperative_offer_confirmation.sql:44-68`) allowed confirming **less than offered** and never returned the unconfirmed remainder to `available_kg`. The current accept flow cannot do this (it always accepts the offered quantity), so the 25 kg is a leftover of the old flow.
- **Result of the diagnostic (run by the operator, 2026-10-29): the 25 kg is NOT orphaned. My first hypothesis was wrong.** It is held by a live Marketplace listing on the same batch: listing `e89365de…` (approved, 25 kg, `remaining_kg` 0) has active orders of 10 kg (pending), 5 kg (pending) and 10 kg (approved) = **25 kg**; its other five orders are cancelled. So the batch adds up: 60 kg = 35 kg sold to the cooperative + 25 kg committed to the listing's orders, available 0, status `reserved`. Nothing needs repair, and **no stock was modified**.
- The listing was created after the offer, so the unconfirmed remainder had already been returned to available stock by then; how the old flow did that does not matter for the current balances.
- The same query showed the live `reconcile_batch_sold()` counts cooperative offers with status `completed` (`counts_completed_offers: true`, `counts_confirmed_offers: false`), so Sold is not understated. The older `supabase_schema_market_linking_partial_sales.sql` (which counts `confirmed`) was not re-applied; keep it that way.

No product files deleted. No approval needed for further code work. Database execution and any reconciliation identified by preflight remain with the operator; live data has not been inspected or changed.
