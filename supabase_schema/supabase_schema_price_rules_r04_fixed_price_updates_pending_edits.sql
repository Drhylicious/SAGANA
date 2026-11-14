-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Price rules r04 · A Fixed Price change also updates pending edits
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER r03 (supabase_schema_price_rules_r03_required_reference_and_changes.sql).
-- Safe to run more than once.
--
-- The case:
--   1. Tomato has a Fixed Price of ₱50/kg.
--   2. A Farmer sends an edit request (for example a new quantity). The request
--      stores the price as it was: ₱50.
--   3. While it waits, the Fixed Price becomes ₱60. r03 moves the listing to ₱60.
--   4. The waiting request still said ₱50, so approving it was refused.
--
-- Now: when a Fixed Price is saved, the price inside every PENDING edit request
-- of the listings it applies to is set to the new Fixed Price as well. The
-- Farmer's other requested changes (quantity, description, photo, shelf life)
-- are kept, and the request is approved the usual way.
--
-- Reference Price RANGE: nothing here changes. A range never changes a price
-- automatically (r03).
--
-- Adds only: one function and one trigger on price_records. r03's own function
-- and trigger are left exactly as they are.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._listing_price_rule(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_price_rules_r03_required_reference_and_changes.sql first.';
  END IF;
  IF to_regclass('public.listing_edit_requests') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_listing_edit_approval.sql first (listing_edit_requests is missing).';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._price_record_apply_to_edit_requests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  q RECORD;
  r RECORD;
BEGIN
  IF NEW.crop_id IS NULL THEN
    RETURN NULL;
  END IF;

  FOR q IN
    SELECT req.id, req.farmer_id, req.proposed_price, req.original_price,
           ml.crop_name, ml.unit, ml.inventory_batch_id,
           (x.discount_applied_on IS NOT NULL) AS discounted
    FROM listing_edit_requests req
    JOIN marketplace_listings ml ON ml.id = req.listing_id
    JOIN inventory_batches b     ON b.id = ml.inventory_batch_id
    JOIN farmer_crops fc         ON fc.id = b.crop_id
    JOIN crop_master cm          ON cm.id = fc.crop_master_id
    LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE req.status = 'pending'
      AND cm.id = NEW.crop_id
      AND COALESCE(b.crop_type, cm.crop_type) = NEW.price_type
      AND lower(btrim(COALESCE(b.unit, 'kg'))) = lower(btrim(NEW.unit))
    FOR UPDATE OF req
  LOOP
    -- The rule now in force (a backdated record may not be the latest one).
    SELECT * INTO r FROM public._listing_price_rule(q.inventory_batch_id);
    CONTINUE WHEN NOT FOUND;
    CONTINUE WHEN r.mode <> 'fixed';              -- a range changes nothing
    CONTINUE WHEN q.proposed_price = r.price_min; -- already at the Fixed Price

    UPDATE listing_edit_requests
       SET proposed_price = r.price_min,
           -- "Before" follows the listing, which r03 has just moved to the new
           -- Fixed Price. A listing carrying the shelf-life discount keeps its
           -- discounted price, so its "before" is left alone.
           original_price = CASE WHEN q.discounted THEN original_price ELSE r.price_min END
     WHERE id = q.id;

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      q.farmer_id, 'listing', 'Edit Request Price Updated',
      'The cooperative changed the fixed price of ' || q.crop_name || ' to ₱' ||
        to_char(r.price_min, 'FM999999990.00') || ' per ' || q.unit ||
        '. The price in your pending edit request was updated to match. Your other requested changes are kept.',
      FALSE, NOW(), '/farmer/marketplace');
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._price_record_apply_to_edit_requests() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_price_records_apply_to_edit_requests ON public.price_records;
CREATE TRIGGER trg_price_records_apply_to_edit_requests
  AFTER INSERT ON public.price_records
  FOR EACH ROW EXECUTE FUNCTION public._price_record_apply_to_edit_requests();

-- ═══ Existing data: requests already left behind by an earlier change ═════
-- Pending requests on Fixed Price listings whose price no longer matches.
UPDATE listing_edit_requests req
   SET proposed_price = rule.price_min,
       original_price = CASE WHEN x.discount_applied_on IS NOT NULL
                             THEN req.original_price ELSE rule.price_min END
  FROM marketplace_listings ml
  LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
  CROSS JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) rule
 WHERE ml.id = req.listing_id
   AND req.status = 'pending'
   AND ml.inventory_batch_id IS NOT NULL
   AND rule.mode = 'fixed'
   AND req.proposed_price <> rule.price_min;

COMMIT;

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. The trigger exists (expect 1 row):
--      SELECT tgname FROM pg_trigger WHERE tgname = 'trg_price_records_apply_to_edit_requests';
--
-- 2. No pending request on a Fixed Price listing is out of step (expect 0 rows):
--      SELECT req.id, req.proposed_price, rule.price_min
--      FROM listing_edit_requests req
--      JOIN marketplace_listings ml ON ml.id = req.listing_id
--      CROSS JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) rule
--      WHERE req.status = 'pending' AND rule.mode = 'fixed'
--        AND req.proposed_price <> rule.price_min;
