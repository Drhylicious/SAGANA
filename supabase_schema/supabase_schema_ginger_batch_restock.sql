-- ============================================================
-- SAGANA — One-batch restock: BATCH-GING-20260730-7083
--
-- Pre-flight query B (supabase_schema_selling_channels_integrity.sql) found one
-- batch whose Sold figure no sale supports:
--     id 24e4eab0-45de-4272-bf3a-03dfd127db1a   Ginger
--     quantity 20.00 | available 10.00 | sold 10.00 | real sales 0.00
-- No order, informal sale, cooperative offer or DA-AMAD program backs the 10 kg,
-- so it is stock that was taken out of Available and counted as Sold with no
-- record behind it (a leftover of an older version of a sale function).
--
-- This puts those 10 kg back: sold_kg = what the records show (0.00), available
-- = quantity - sold - anything still reserved (0.00), status from the same
-- thresholds the app uses. Nothing else is touched: no sale, order, offer,
-- listing, program, price or notification is created, changed or deleted, and
-- the batch's number and unit are not written (the identity guard stays quiet).
--
-- SAFE BY CONSTRUCTION. In one transaction it re-checks everything and stops
-- with a message, changing NOTHING, unless ALL of these hold:
--   1. the batch exists and its figures are still 20 / 10 / 10 (so it is not run
--      twice, or on a batch that has moved since);
--   2. available + sold = quantity (no other reservation hides in the gap);
--   3. no order, informal sale, cooperative offer or DA-AMAD program references
--      the batch, and no listing of it is still pending, approved or sold.
-- If a check fails, read the message: it means the 10 kg may be real, and it
-- should be settled by hand rather than restocked.
--
-- Run it once in the Supabase SQL editor. Not applied automatically.
-- If the farmer really did sell those 10 kg outside the app, do NOT run this:
-- record it as an Informal Sale instead, and the batch corrects itself.
-- ============================================================

BEGIN;

DO $$
DECLARE
  c_batch CONSTANT UUID := '24e4eab0-45de-4272-bf3a-03dfd127db1a';
  b       inventory_batches%ROWTYPE;
  v_refs  INT;
  v_new_status TEXT;
BEGIN
  SELECT * INTO b FROM inventory_batches WHERE id = c_batch FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nothing changed: the batch % was not found.', c_batch;
  END IF;

  IF b.status = 'withdrawn' THEN
    RAISE EXCEPTION 'Nothing changed: the batch is withdrawn.';
  END IF;
  IF NOT (b.quantity_kg = 20 AND b.available_kg = 10 AND b.sold_kg = 10) THEN
    RAISE EXCEPTION 'Nothing changed: the batch is no longer 20 / 10 / 10 (quantity / available / sold); it is % / % / %.',
      b.quantity_kg, b.available_kg, b.sold_kg;
  END IF;
  IF b.available_kg + b.sold_kg <> b.quantity_kg THEN
    RAISE EXCEPTION 'Nothing changed: available + sold does not equal quantity, so another reservation is involved.';
  END IF;

  SELECT
      (SELECT count(*) FROM informal_sales i WHERE i.inventory_batch_id = c_batch)
    + (SELECT count(*) FROM cooperative_purchase_offers c WHERE c.inventory_batch_id = c_batch)
    + (SELECT count(*) FROM market_linking_programs m WHERE m.inventory_batch_id = c_batch)
    + (SELECT count(*) FROM orders o JOIN marketplace_listings l ON l.id = o.listing_id
        WHERE l.inventory_batch_id = c_batch)
    + (SELECT count(*) FROM marketplace_listings l
        WHERE l.inventory_batch_id = c_batch
          AND l.status IN ('pending_review', 'changes_required', 'approved', 'sold'))
  INTO v_refs;
  IF v_refs > 0 THEN
    RAISE EXCEPTION 'Nothing changed: % record(s) (sale, offer, program, order or live listing) still reference this batch, so the 10 kg may be real.', v_refs;
  END IF;

  -- Everything checks out: nothing is sold, nothing is reserved. All 20 kg are available.
  v_new_status := 'available'; -- 20 of 20 is above the 15 % low-stock line

  UPDATE inventory_batches
     SET sold_kg = 0, available_kg = quantity_kg, status = v_new_status
   WHERE id = c_batch;
END;
$$;

COMMIT;

-- Result (expect quantity 20 | available 20 | sold 0 | status available):
SELECT id, batch_number, quantity_kg, available_kg, sold_kg, status
FROM inventory_batches WHERE id = '24e4eab0-45de-4272-bf3a-03dfd127db1a';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- Pre-flight query B from supabase_schema_selling_channels_integrity.sql should
-- now return 0 rows.
-- ───────────────────────────────────────────────────────────────────────────
