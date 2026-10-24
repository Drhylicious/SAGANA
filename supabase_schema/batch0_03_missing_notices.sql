-- ─────────────────────────────────────────────────────────────────────────────
-- batch0_03_missing_notices.sql
-- Batch 0 (0E–0I + 0L) of the approved implementation plan.
--
-- Adds the notices that were missing (review findings) and removes the
-- self-notice to an applicant (approved decision 5).
--
--   0E  DA-AMAD enrollment submitted      → Admin/Officer notified
--   0F  Farmer withdraws a listing         → Admin/Officer notified
--   0G  Listing sold out                   → Farmer notified
--   0H  Overdue loan                       → Admin/Officer notified (in addition
--                                            to the farmer's existing reminder)
--   0I  Payout decision confirmed/rejected → Farmer notified
--   0L  submit_application                 → applicant's own notice removed
--
-- Not included here, on purpose:
--   * The BOD-near notice (0H): the plan does not define when it fires, so it
--     waits for a decision.
--   * cancel_program_purchase (0L): the live definition already notifies the
--     farmer only when Admin cancels, so nothing changes.
--   * convert_program_distribution_to_loan: issue_loan already notifies the
--     farmer with the loan and its items, so no extra notice is added.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── 0E. DA-AMAD enrollment submitted → Admin/Officer ────────────────────────
-- Source: live definition in supabase_schema_da_amad_enrollment.sql.
-- The only change is the staff notice after the insert.
CREATE OR REPLACE FUNCTION submit_da_amad_enrollment()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_has_ginger BOOLEAN;
  v_new_id UUID;
  v_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM da_amad_enrollments
    WHERE farmer_id = v_farmer_id AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'You already have a pending or approved enrollment';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM farmer_crops fc
    JOIN crop_master cm ON cm.id = fc.crop_master_id
    WHERE fc.farmer_id = v_farmer_id AND cm.crop_type = 'da_amad_market'
  ) INTO v_has_ginger;

  IF NOT v_has_ginger THEN
    RAISE EXCEPTION 'A Ginger crop in your Crop Roster is required to enroll';
  END IF;

  INSERT INTO da_amad_enrollments (farmer_id, status, submitted_at)
  VALUES (v_farmer_id, 'pending', NOW())
  RETURNING id INTO v_new_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_farmer_id;

  PERFORM public.notify_staff(
    'system',
    'New Market Linking Enrollment',
    COALESCE(v_name, 'A farmer') || ' submitted a Market Linking enrollment for Ginger and needs review.'
  );

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_da_amad_enrollment() TO authenticated;

-- ─── 0F. Listing withdrawn → Admin/Officer ───────────────────────────────────
-- Source: live definition in supabase_schema_withdraw_listing_pending_only_guard.sql.
-- The only change is the staff notice after the status update.
-- NOTE: the live database copy could not be read from the dump. Confirm this
-- source matches the deployed function before running this file.
CREATE OR REPLACE FUNCTION withdraw_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
  v_name TEXT;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_listing.status != 'pending_review' THEN
    RAISE EXCEPTION 'This listing cannot be withdrawn (status: %)', v_listing.status;
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_listing.remaining_kg > 0 THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.remaining_kg);
  END IF;

  UPDATE marketplace_listings SET status = 'withdrawn', remaining_kg = 0 WHERE id = p_listing_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();

  PERFORM public.notify_staff(
    'listing',
    'Listing Withdrawn',
    COALESCE(v_name, 'A farmer') || ' withdrew their ' || COALESCE(v_listing.crop_name, 'produce') || ' listing.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION withdraw_listing TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ─── 0G. Listing sold out → Farmer ───────────────────────────────────────────
-- Fires when a listing's status changes to 'sold' (set by the order flow).
CREATE OR REPLACE FUNCTION public.fn_notify_listing_sold()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold' THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      NEW.farmer_id,
      'listing',
      'Listing Sold Out',
      'Your ' || COALESCE(NEW.crop_name, 'produce') || ' listing has been sold out.',
      FALSE,
      NOW(),
      '/farmer/marketplace'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_listing_sold ON public.marketplace_listings;
CREATE TRIGGER trg_notify_listing_sold
  AFTER UPDATE OF status ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_listing_sold();

-- ─── 0H. Overdue loans → Admin/Officer (added to the existing reminder loop) ─
-- Source: live definition of notify_overdue_farmers. The only change is the
-- staff notice inside the loop, after the farmer's reminder.
CREATE OR REPLACE FUNCTION public.notify_overdue_farmers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mode           TEXT;
  v_delay_days     INT;
  v_notified_count INT := 0;
  v_loan           RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  SELECT notification_timing_mode, notification_delay_days
  INTO v_mode, v_delay_days
  FROM loan_policy_settings WHERE id = 1;

  FOR v_loan IN
    SELECT id, farmer_id, reference_no, total_value, amount_paid, next_payment_date
    FROM farmer_loans
    WHERE status = 'overdue'
      AND notified_overdue_at IS NULL
      AND (
        v_mode = 'on_transition'
        OR (v_mode = 'delayed' AND next_payment_date <= CURRENT_DATE - v_delay_days)
        OR (v_mode = 'next_bod_meeting' AND CURRENT_DATE >= next_bod_saturday_after(next_payment_date))
      )
  LOOP
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_loan.farmer_id,
      'loan',
      'Payment Reminder',
      'Your loan ' || v_loan.reference_no || ' has a missed payment. Outstanding balance: ₱' ||
      to_char(v_loan.total_value - v_loan.amount_paid, 'FM999,999,990.00') ||
      '. Please settle at the next BOD meeting or visit the cooperative office.',
      FALSE,
      NOW(),
      '/farmer/profile/loans'
    );

    PERFORM public.notify_staff(
      'loan',
      'Overdue Loan',
      'Loan ' || v_loan.reference_no || ' is overdue. Outstanding balance: ₱' ||
      to_char(v_loan.total_value - v_loan.amount_paid, 'FM999,999,990.00') || '.'
    );

    UPDATE farmer_loans SET notified_overdue_at = NOW() WHERE id = v_loan.id;
    v_notified_count := v_notified_count + 1;
  END LOOP;

  RETURN v_notified_count;
END;
$function$;


-- ─── 0I. Payout decision confirmed → Farmer ─────────────────────────────────
-- Source: live definition in supabase_schema_role_based_staff_access.sql.
-- The only change is the farmer notice before the function ends.
CREATE OR REPLACE FUNCTION public.confirm_payout_decision(p_farmer_id uuid, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID := auth.uid();
  v_row RECORD;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) OR EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = v_admin) THEN
    RAISE EXCEPTION 'Only an admin can confirm a payout decision.';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = p_farmer_id AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', p_farmer_id, p_year;
  END IF;
  IF v_row.payout_decision NOT IN ('pending_cash', 'pending_capital') THEN
    RAISE EXCEPTION 'No pending payout decision to confirm (current: %)', v_row.payout_decision;
  END IF;

  IF v_row.payout_decision = 'pending_capital' THEN
    INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
    VALUES (
      p_farmer_id,
      v_row.payout_decision_amount,
      'patronage_capital',
      'Reinvested from ' || p_year || ' Balik-Tangkilik payout (admin-confirmed)',
      v_admin
    );

    UPDATE member_contributions
    SET reinvested_amount = COALESCE(reinvested_amount, 0) + v_row.payout_decision_amount,
        payout_decision = 'capital_confirmed',
        payout_decision_confirmed_at = NOW(),
        payout_decision_confirmed_by = v_admin
    WHERE farmer_id = p_farmer_id AND year = p_year;
  ELSE
    UPDATE member_contributions
    SET payout_decision = 'cash_confirmed',
        payout_decision_confirmed_at = NOW(),
        payout_decision_confirmed_by = v_admin
    WHERE farmer_id = p_farmer_id AND year = p_year;
  END IF;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    p_farmer_id, 'capital', 'Payout Decision Confirmed',
    'Your Balik-Tangkilik payout decision for ' || p_year || ' has been confirmed by the cooperative.',
    FALSE, NOW(), '/farmer/profile/contribution'
  );

END;
$function$;

-- ─── 0I. Payout decision rejected → Farmer ──────────────────────────────────
-- Source: as above.
CREATE OR REPLACE FUNCTION public.reject_payout_decision(p_farmer_id uuid, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID := auth.uid();
  v_row RECORD;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) OR EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = v_admin) THEN
    RAISE EXCEPTION 'Only an admin can reject a payout decision.';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = p_farmer_id AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', p_farmer_id, p_year;
  END IF;
  IF v_row.payout_decision NOT IN ('pending_cash', 'pending_capital') THEN
    RAISE EXCEPTION 'Only a pending decision can be rejected (current: %)', v_row.payout_decision;
  END IF;

  UPDATE member_contributions
  SET payout_decision = NULL,
      payout_decision_amount = NULL,
      payout_decision_requested_at = NULL
  WHERE farmer_id = p_farmer_id AND year = p_year;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    p_farmer_id, 'capital', 'Payout Decision Not Approved',
    'Your Balik-Tangkilik payout decision for ' || p_year || ' was not approved. You may submit a new decision.',
    FALSE, NOW(), '/farmer/profile/contribution'
  );

END;
$function$;

-- ─── 0L. submit_application: applicant's own notice removed ────────────────
-- Source: live definition. The staff notice is kept; the self-notice is removed.
-- Dropping the 'Application Submitted' self-notice is approved decision 5.
CREATE OR REPLACE FUNCTION public.submit_application()
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       UUID := auth.uid();
  v_status    TEXT;
  v_attempts  SMALLINT;
  v_full_name TEXT;
BEGIN
  SELECT status, application_attempts INTO v_status, v_attempts
  FROM user_roles WHERE user_id = v_uid
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'No membership record found';
  END IF;

  IF v_status NOT IN ('draft', 'rejected') THEN
    RAISE EXCEPTION 'Application cannot be submitted from status %', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'pending',
      application_attempts = COALESCE(v_attempts, 0) + 1,
      rejection_reason = NULL,
      pending_acknowledgement = false
  WHERE user_id = v_uid;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (v_uid, v_status, 'pending',
          'Application submitted (attempt ' || (COALESCE(v_attempts, 0) + 1) || ')', v_uid);


  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = v_uid;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'member_pending',
    'New Membership Application',
    COALESCE(v_full_name, 'A farmer') || ' submitted a membership application and needs review.',
    FALSE,
    NOW(),
    '/admin/farmers'
  FROM public.user_roles ap WHERE ap.role IN ('admin');

  RETURN (COALESCE(v_attempts, 0) + 1)::SMALLINT;
END;
$function$;
