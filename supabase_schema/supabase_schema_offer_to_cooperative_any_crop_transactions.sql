-- ============================================================
-- SAGANA — Offer to Cooperative: Any-Crop Transaction Parity
-- (Admin-Report tab review — Phase 9)
--
-- supabase_schema_confirm_cooperative_offer_any_crop.sql widened Offer to
-- Cooperative to accept any crop, but only Palay/Peanut settled into
-- member_sales_transactions — its own header comment explicitly named
-- "Full financial parity" (widening member_sales_transactions.crop_type
-- to accept any crop) as deferred future work. This migration is that
-- follow-through, per the organization's explicit confirmation: "Any
-- crop can be offered to the Cooperative... regardless of its Market
-- Type," and "Once the cooperative actually buys the farmer-member's
-- harvested crop, that transaction becomes connected to Balik-Tangkilik."
--
-- Ginger is not separately guarded here — it's already structurally
-- excluded upstream, at offer-creation time, via crop_master.
-- is_cooperative_eligible (crop_type <> 'da_amad_market'), so a Ginger
-- offer should never reach 'confirmed' status in the first place.
-- ============================================================

BEGIN;

-- ─── Widen the crop_type constraint ─────────────────────────────────────────
-- crop_type here is just lower(crop_name) (see confirm_cooperative_offer()
-- below) — a normalized crop identifier, not a fixed business enum beyond
-- the historical Palay/Peanut-only restriction. Dropped rather than
-- replaced with an enumerated list, since crop_master's catalog is
-- open-ended (admin/farmer-driven, not a fixed set this migration should
-- hardcode).
ALTER TABLE public.member_sales_transactions
  DROP CONSTRAINT IF EXISTS member_sales_transactions_crop_type_check;

COMMENT ON COLUMN public.member_sales_transactions.crop_type IS
  'Normalized crop identifier (lower(crop_name) at confirmation time). '
  'No longer restricted to palay/peanut as of this migration — any '
  'confirmed Offer to Cooperative transaction, for any crop, settles '
  'here. Palay/Peanut remain the two crops with dedicated breakdown '
  'columns/UI elsewhere (Sales Report, Member Patronage Report); every '
  'other crop is included in totals but not broken out by name in those '
  'two specific UI elements.';

-- ─── confirm_cooperative_offer(): always settle into member_sales_transactions ──
-- Full function body re-supplied (CREATE OR REPLACE requires the whole
-- thing) — identical to supabase_schema_confirm_cooperative_offer_any_
-- crop.sql's version except the IF v_crop_type IN ('palay','peanut') THEN
-- branch is removed; every confirmed offer, any crop, now inserts a
-- member_sales_transactions row and v_transaction_id is never left NULL
-- for a real confirmation.
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

  -- Every confirmed offer, any crop, settles through
  -- member_sales_transactions as of this migration (Phase 9 / "Full
  -- financial parity") — this is the single change from the prior
  -- version, which only did this for palay/peanut.
  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, v_crop_type,
    p_confirmed_quantity_kg, p_confirmed_amount, CURRENT_DATE, auth.uid()
  ) RETURNING id INTO v_transaction_id;

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

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- Confirm the constraint is gone:
--   SELECT conname FROM pg_constraint
--   WHERE conrelid = 'member_sales_transactions'::regclass
--     AND conname LIKE '%crop_type%';
--   -- expect 0 rows
--
-- Confirm existing Palay/Peanut data is unaffected:
--   SELECT crop_type, count(*), sum(amount) FROM member_sales_transactions
--   GROUP BY crop_type;
--   -- expect the same palay/peanut rows/totals as before this migration
