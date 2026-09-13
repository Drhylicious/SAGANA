# SAGANA — Marketplace Reservation Model: Canonical Reference

This file is documentation only — not a migration, never executed against
the database. It exists because `place_order`, `cancel_order`,
`complete_order`, `create_listing_with_reservation`, `reject_listing`,
`withdraw_listing`, and `resubmit_listing_with_reservation` are each
defined more than once across the SQL migration history, via
`CREATE OR REPLACE FUNCTION`. Whichever definition was applied *last*
against the live database is the one that actually runs — so re-running
an older file after a newer one silently reverts behavior, with no error
and no warning. This file records what the CANONICAL (intended, correct)
final state is, so that risk is at least documented instead of implicit.

## The two eras

**Batch-centric era** (`supabase_schema_buyer_orders.sql`,
`supabase_schema_order_management.sql`): a buyer's order moved stock
directly on `inventory_batches` — `available_kg` → `reserved_kg` at
placement, `reserved_kg` → `sold_kg` at completion, reversed on
cancellation. This conflicts with the *listing-creation*-time reservation
`_apply_batch_reservation` performs (see below) — by the time a buyer
could place an order, the batch's `available_kg` had usually already been
zeroed out by listing creation, making this era's `place_order` reject
orders that should have succeeded.

**Listing-centric era ("Option C")**
(`supabase_schema_marketplace_order_reservation_fix.sql`): resolves that
conflict by moving order-availability tracking off the batch entirely and
onto the listing's own `remaining_kg` column. This is the canonical model
— see below.

## Canonical model (current, intended-correct)

1. **Listing creation** (`create_listing_with_reservation`): reserves the
   full listed quantity against the *batch* immediately —
   `inventory_batches.available_kg` drops by the listed amount, via the
   shared `_apply_batch_reservation` helper. `remaining_kg` on the new
   listing starts equal to the listed quantity. The batch's `reserved_kg`
   column is NOT touched by this or anything else in this model — it is
   effectively unused in the canonical model.

2. **Buyer places an order** (`place_order`): decrements the *listing's*
   `remaining_kg` only. The batch is never touched at order-placement
   time — the full listed quantity was already committed to Marketplace
   disposal at step 1, regardless of how many individual orders end up
   splitting it.

3. **Order cancelled** (`cancel_order`): restores the *listing's*
   `remaining_kg` only (and revives the listing from `'sold'` back to
   `'approved'` if it had sold out). The batch is never touched — nothing
   was taken from it at order-placement time, so there's nothing to give
   back to it here.

4. **Order completed** (`complete_order`): increments the *batch's*
   `sold_kg` (the only point in this whole flow where the batch is
   touched again after listing creation). If this drives `remaining_kg`
   to zero, the listing's status flips to `'sold'`.

5. **Listing rejected / withdrawn / resubmitted** (`reject_listing`,
   `withdraw_listing`, `resubmit_listing_with_reservation`): releases
   (or reconciles, for resubmit) the batch-level reservation from step 1
   via `_release_batch_reservation`, and zeroes/re-syncs `remaining_kg`
   to match.

## Canonical file per function

| Function | Canonical file |
|---|---|
| `_apply_batch_reservation` | `supabase_schema_inventory_disposal_paths.sql` (never redefined elsewhere) |
| `_release_batch_reservation` | `supabase_schema_listing_rejection_release.sql` (never redefined elsewhere) |
| `create_listing_with_reservation` | `supabase_schema_create_listing_ginger_guard.sql` — **not** `create_listing_reservation_corrected.sql`; see warning below and "Post-reservation-model updates" |
| `place_order` | `supabase_schema_place_order_admin_notify.sql` — **not** the reservation_fix file; see "Post-reservation-model updates" below |
| `cancel_order` | `supabase_schema_cancel_order_pending_only_guard.sql` — **not** the reservation_fix file; see "Post-reservation-model updates" below |
| `complete_order` | `supabase_schema_complete_order_updated_at_fix.sql` — **not** `order_notifications.sql`; see below |
| `reject_listing` | `supabase_schema_reject_listing_guard.sql` — **not** the reservation_fix file; see "Post-Marketplace-review updates" below |
| `withdraw_listing` | `supabase_schema_marketplace_order_reservation_fix.sql` |
| `resubmit_listing_with_reservation` | `supabase_schema_rejected_listing_terminal.sql` — **not** the reservation_fix file; see "Post-Marketplace-review updates" below |
| `marketplace_listings.status` allowed values | `supabase_schema_marketplace_listings_status_fix.sql` (adds `'rejected'`/`'sold'`) |
| `delete_listing` | `supabase_schema_rejected_listing_terminal.sql` — **not** `delete_listing_order_guard.sql`; see "Post-Marketplace-review updates" below |

## Post-reservation-model updates (Buyer module review, Phase 1–2)

This section documents layers applied *after* everything above — this file's
original scope stopped at the reservation model itself and never tracked
these, which was flagged as a documentation gap during the Buyer module
review. Each layer below is additive to the canonical model, not a
replacement of it — the reservation mechanics described above are
unaffected.

- **`place_order`**: `marketplace_order_reservation_fix.sql` (Option C,
  canonical reservation mechanics) → `place_order_buyer_status_guard.sql`
  (adds server-side rejection of suspended buyer accounts) →
  `place_order_admin_notify.sql` (adds admin notification on new order;
  **current canonical**).
- **`cancel_order`**: this file's original claim that `cancel_order` was
  "unaffected" was itself stale — two notification layers were added
  without ever being tracked here: `marketplace_order_reservation_fix.sql`
  (Option C, canonical reservation mechanics; originally allowed
  cancelling from `'pending'` **or** `'approved'`) → `order_notifications.sql`
  (adds buyer notification on cancellation) → `farmer_notification_gaps.sql`
  (adds a matching farmer notification) → `cancel_order_pending_only_guard.sql`
  (tightens the guard to `'pending'`-only — an approved order can no
  longer be cancelled, only completed, per the Admin Marketplace review;
  **current canonical**, all prior notification inserts preserved
  unchanged).
- **`complete_order`**: `marketplace_order_reservation_fix.sql` →
  `order_notifications.sql` (adds buyer notification on completion) →
  `supabase_schema_complete_order_updated_at_fix.sql` (removes a no-op
  `UPDATE...RETURNING` that was unnecessarily bumping the listing's
  `updated_at`; **current canonical** — no reservation-mechanics change).
- **`create_listing_with_reservation`**: same staleness this file already
  had for `cancel_order` — a later layer went untracked here too.
  `create_listing_reservation_corrected.sql` (fixes the wrong-column-name/
  invalid-status bug — canonical mechanics) → `farmer_notification_gaps.sql`
  (adds the admin fan-out notification on submission) →
  `create_listing_ginger_guard.sql` (blocks Ginger — it can only be sold
  through Market Linking, never the open Marketplace; **current
  canonical**, all prior lines including the notification preserved
  unchanged).
- **`delete_listing`**: `supabase_schema_delete_listing.sql` (original —
  status guard only) → `supabase_schema_delete_listing_order_guard.sql`
  (adds a block on deletion when any `orders` row references the listing,
  closing a cascade-delete data-loss gap; **current canonical**).
- **`orders` RLS** (not a function, but directly relevant to this file's
  trust model): `supabase_schema_orders_farmer_update_removal.sql` removed
  the `"Farmers update order status"` UPDATE policy, which had granted
  farmers unrestricted column-level write access to their own orders rows
  with no `WITH CHECK` — bypassing every guard described in this document.
  Confirmed via live-database query to have applied cleanly, with the
  three legitimate policies (`Farmers see own orders`,
  `Buyers see own orders`, `Buyers create orders`) undisturbed.

## ⚠️ One non-obvious trap in the canonical order

`marketplace_order_reservation_fix.sql`'s own version of
`create_listing_with_reservation` has the bug
`create_listing_reservation_corrected.sql` fixes (wrong column name,
invalid status). **If you ever need to re-run
`marketplace_order_reservation_fix.sql`** (e.g. rebuilding a fresh
database from these files in order), **`create_listing_reservation_corrected.sql`
must be re-applied AFTER it**, every time — otherwise `create_listing_with_reservation`
silently reverts to the broken version even though the other six
functions in that same file are fine. `create_listing_reservation_corrected.sql`
only touches `create_listing_with_reservation`, so applying it last
doesn't affect anything else.

**Recommended full replay order for a fresh database:**
`inventory_disposal_paths.sql` → `listing_rejection_release.sql` →
`listing_withdraw_reservation.sql` → `listing_resubmit_reservation.sql` →
`buyer_orders.sql` → `order_management.sql` →
`marketplace_order_reservation_fix.sql` →
`create_listing_reservation_corrected.sql` →
`marketplace_listings_status_fix.sql` → `delete_listing.sql` →
`place_order_buyer_status_guard.sql` → `place_order_admin_notify.sql` →
`order_notifications.sql` → `supabase_schema_complete_order_updated_at_fix.sql` →
`supabase_schema_delete_listing_order_guard.sql` →
`supabase_schema_orders_farmer_update_removal.sql` →
`supabase_schema_farmer_notification_gaps.sql` →
`supabase_schema_cancel_order_pending_only_guard.sql` →
`supabase_schema_create_listing_ginger_guard.sql`.

## Superseded files (kept for history, not canonical for the functions below)

- `supabase_schema_buyer_orders.sql` — its `place_order` is superseded (batch-centric era)
- `supabase_schema_order_management.sql` — its `complete_order`/`cancel_order` are superseded (batch-centric era)
- `supabase_schema_listing_rejection_release.sql` — its `reject_listing` is superseded (the `_release_batch_reservation` helper it defines is still canonical)
- `supabase_schema_listing_withdraw_reservation.sql` — its `withdraw_listing` is superseded
- `supabase_schema_listing_resubmit_reservation.sql` — its `resubmit_listing_with_reservation` is superseded
- `supabase_schema_fix_listing_reservation.sql` — its `create_listing_with_reservation` is superseded (earlier fix attempt, itself superseded by `create_listing_reservation_corrected.sql`)
- `supabase_schema_create_listing_reservation_corrected.sql` — its `create_listing_with_reservation` is superseded by `supabase_schema_farmer_notification_gaps.sql`, itself now superseded by `supabase_schema_create_listing_ginger_guard.sql`
- `supabase_schema_farmer_notification_gaps.sql` — its `create_listing_with_reservation` is superseded by `supabase_schema_create_listing_ginger_guard.sql` (the admin notification INSERT it added is preserved unchanged in the new canonical version); its `cancel_order` is superseded by `supabase_schema_cancel_order_pending_only_guard.sql`
- `supabase_schema_marketplace_order_reservation_fix.sql` — its `place_order`/`complete_order` are now superseded by the "Post-reservation-model updates" layers above; its `reject_listing`/`resubmit_listing_with_reservation` are now superseded by the "Post-Marketplace-review updates" layers below; its `cancel_order` is now superseded by `supabase_schema_cancel_order_pending_only_guard.sql` (see above — was wrongly tracked as canonical/unaffected until this correction); its `withdraw_listing` remains canonical, unaffected
- `supabase_schema_order_notifications.sql` — its `complete_order` is superseded by `supabase_schema_complete_order_updated_at_fix.sql`; its `cancel_order` is superseded by `supabase_schema_cancel_order_pending_only_guard.sql`
- `supabase_schema_farmer_notification_gaps.sql` — its `cancel_order` is superseded by `supabase_schema_cancel_order_pending_only_guard.sql` (the farmer-notification INSERT it added is preserved unchanged in the new canonical version)
- `supabase_schema_delete_listing.sql` — its `delete_listing` is superseded (first by `supabase_schema_delete_listing_order_guard.sql`, now by `supabase_schema_rejected_listing_terminal.sql`)
- `supabase_schema_delete_listing_order_guard.sql` — its `delete_listing` is itself now superseded by `supabase_schema_rejected_listing_terminal.sql`