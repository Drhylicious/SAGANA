-- ============================================================
-- SAGANA — Offer to Cooperative: Accept Any Crop (Scoped Fix)
-- (Admin Marketplace review, Crop Management phase)
--
-- Offer to Cooperative was hard-restricted to Palay/Peanut because
-- confirm_cooperative_offer() always settled into member_sales_transactions,
-- whose crop_type is DB-constrained to those two crops (Balik-Tangkilik
-- patronage-refund eligibility). Per the reviewed decision, any crop
-- should be offerable to the cooperative — but the settlement path
-- differs by crop:
--   - Palay/Peanut: unchanged — still creates a member_sales_transactions
--     row, still counts toward Balik-Tangkilik.
--   - Any other crop: confirmed directly on the cooperative_purchase_offers
--     row itself (confirmed_quantity_kg / confirmed_amount, both already
--     existing columns) — no transaction row, so it does NOT appear in
--     Sales Report, Analytics, or farmer Total Earnings, and does NOT
--     affect Balik-Tangkilik math.
--
-- Deliberately deferred, NOT implemented here: "Full financial parity" —
-- widening member_sales_transactions.crop_type to accept any crop and
-- adding explicit `crop_type IN ('palay','peanut')` filters to the ~6
-- files that currently rely on the DB constraint alone (
-- member_sales_aggregation.dart, contribution_repository.dart,
-- admin_reports_repository.dart's Sales Report + Member Contribution
-- Report, analytics_repository.dart, dashboard_repository.dart's farmer
-- earnings total). Flagged as a future requirement for the Reports tab.
--
-- Every existing line for the Palay/Peanut path is preserved exactly —
-- only the hard rejection of other crops is replaced with the
-- offer-only settlement branch. Base body is
-- supabase_schema_notification_type_fixes.sql's version, the current
-- canonical one (adds the 'cooperative_offer'-typed notification).
-- ============================================================

CREATE OR REPLACE FUNCTION confirm_cooperative_offer(
  p_offer_id UUID,
  p_confirmed_quantity_kg DECIMAL,
  p_confirmed_amount DECIMAL,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_transaction_id UUID;
  v_crop_type TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  IF p_confirmed_quantity_kg <= 0 OR p_confirmed_quantity_kg > v_offer.offered_quantity_kg THEN
    RAISE EXCEPTION 'Confirmed quantity must be between 0 and the offered quantity (%).', v_offer.offered_quantity_kg;
  END IF;

  v_crop_type := lower(v_offer.crop_name);

  -- Only Palay/Peanut settle through member_sales_transactions
  -- (Balik-Tangkilik eligible). Any other crop confirms directly on the
  -- offer row, with no transaction record — Scoped Fix decision, Admin
  -- Marketplace review. v_transaction_id stays NULL in that case, which
  -- member_sales_transaction_id (nullable) and the RETURN below both
  -- already handle correctly.
  IF v_crop_type IN ('palay', 'peanut') THEN
    INSERT INTO member_sales_transactions (
      farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
    ) VALUES (
      v_offer.farmer_id, v_offer.crop_name, v_crop_type,
      p_confirmed_quantity_kg, p_confirmed_amount, CURRENT_DATE, auth.uid()
    ) RETURNING id INTO v_transaction_id;
  END IF;

  UPDATE cooperative_purchase_offers
  SET status = 'confirmed',
      confirmed_quantity_kg = p_confirmed_quantity_kg,
      confirmed_amount = p_confirmed_amount,
      member_sales_transaction_id = v_transaction_id,
      admin_notes = p_admin_notes,
      confirmed_by = auth.uid(),
      confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Confirmed',
    'Your offer of ' || p_confirmed_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was confirmed by SP3 for ₱' || p_confirmed_amount || '.',
    FALSE,
    NOW()
  );

  RETURN v_transaction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_cooperative_offer TO authenticated;
