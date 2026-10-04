-- ============================================================
-- SAGANA — Phase 6: Balik-Tangkilik / capital workflow notifications
-- ============================================================
-- Scoped per explicit user decision (all 3 recommended sub-events):
--   1. recordDistribution (Dart, admin bulk-finalizes a year's payout)
--      → notify every affected farmer with their own amount. Handled
--      in balik_tangkilik_repository.dart, not here (no RPC exists for
--      this — it's a plain bulk upsert).
--   2. reinvest_patronage_capital (farmer self-service RPC) → notify
--      all admins, mirroring Phase 3's submit_application fix.
--   3. recordContribution (Dart, admin records a capital payment/dues
--      for a farmer) → notify that farmer. Handled in
--      capital_contribution_repository.dart, not here (plain insert).
--
-- New type: no existing notifications.type value fits a
-- capital/patronage event (closest existing ones are 'loan'/'price',
-- neither accurate). Adds 'capital', with a matching
-- NotificationType/NotificationFilter case added on the Dart side (a
-- new "Capital" filter chip on farmer's Notifications screen, same
-- pattern as the existing Loans/Programs/Prices chips).
-- ============================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'order', 'listing', 'loan', 'price', 'sync', 'system',
    'listing_submitted', 'loan_overdue', 'member_pending',
    'member_registered', 'member_updated', 'member_approved', 'member_rejected',
    'low_stock', 'stock_depleted',
    'crop_request', 'cooperative_offer', 'program', 'capital'
  ));

-- ─── reinvest_patronage_capital → notify all admins ─────────────────────────

CREATE OR REPLACE FUNCTION public.reinvest_patronage_capital(p_year integer, p_amount numeric, p_note text DEFAULT NULL::text)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_farmer UUID := auth.uid();
  v_row RECORD;
  v_total_payout NUMERIC;
  v_available NUMERIC;
  v_farmer_name TEXT;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = v_farmer AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', v_farmer, p_year;
  END IF;
  IF v_row.status != 'paid' THEN
    RAISE EXCEPTION 'This year''s Balik-Tangkilik has not been finalized yet (status: %)', v_row.status;
  END IF;

  -- Widened: now includes actual_purchase_patronage (Product Sales
  -- Program Patronage) alongside the original two Offer to Cooperative
  -- components, matching the combined total the farmer sees on-screen.
  v_total_payout := COALESCE(v_row.actual_balik_tangkilik, 0)
                   + COALESCE(v_row.actual_interest_on_capital, 0)
                   + COALESCE(v_row.actual_purchase_patronage, 0);
  v_available := v_total_payout - v_row.reinvested_amount;

  IF p_amount > v_available THEN
    RAISE EXCEPTION 'Amount (%) exceeds what remains available to reinvest (%)', p_amount, v_available;
  END IF;

  INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
  VALUES (
    v_farmer,
    p_amount,
    'patronage_capital',
    COALESCE(p_note, 'Reinvested from ' || p_year || ' Balik-Tangkilik payout'),
    v_farmer
  );

  UPDATE member_contributions
  SET reinvested_amount = reinvested_amount + p_amount
  WHERE farmer_id = v_farmer AND year = p_year;

  SELECT full_name INTO v_farmer_name FROM user_information WHERE user_id = v_farmer;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'capital',
    'Patronage Capital Reinvested',
    COALESCE(v_farmer_name, 'A farmer') || ' reinvested ₱' || to_char(p_amount, 'FM999,999,990.00') ||
      ' of their ' || p_year || ' Balik-Tangkilik payout into their capital share.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN v_available - p_amount;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conname = 'notifications_type_check';  -- expect 'capital' included
--
-- SELECT prosrc ILIKE '%admin_profiles%' FROM pg_proc
-- WHERE proname = 'reinvest_patronage_capital';  -- expect TRUE
--
-- In-app: as a farmer, reinvest part of a finalized year's payout and
-- confirm admins get notified. Record a year's distribution and a
-- capital contribution from the admin side (see Dart-side changes) and
-- confirm farmers see the new "Capital" filter chip and notification.
-- ============================================================
