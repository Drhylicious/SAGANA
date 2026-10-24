-- ─────────────────────────────────────────────────────────────────────────────
-- batch10_01_bod_and_failed_outcome.sql
-- Two decisions from the notification review:
--   A. Failed program outcome: the farmer gets "Program Outcome: Failed".
--      convert_program_distribution_to_loan is copied from
--      supabase_schema_role_based_staff_access.sql; only the notice is added.
--   B. BOD meeting notice, 3 days before the meeting, daily at 08:00 Manila.
--      Recipients: active farmers, admins and officers.
--      The meeting date is a PLACEHOLDER rule: the first Saturday of the month
--      (lib/core/utils/bod_schedule_utils.dart). Change the date function when
--      the real schedule is confirmed.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── A. Failed program outcome notice ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.convert_program_distribution_to_loan(p_program_member_id uuid, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(loan_id uuid, reference_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member       RECORD;
  v_item         RECORD;
  v_line_total   NUMERIC;
  v_items        JSONB;
  v_result       RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can convert a distribution to a loan';
  END IF;

  SELECT pm.*, cp.program_name INTO v_member
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  WHERE pm.id = p_program_member_id
  FOR UPDATE OF pm;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program member not found';
  END IF;

  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'This member has not been distributed a benefit yet';
  END IF;

  IF v_member.converted_loan_id IS NOT NULL THEN
    RAISE EXCEPTION 'This distribution has already been converted to a loan';
  END IF;

  IF v_member.inventory_item_id IS NULL OR v_member.quantity_given IS NULL THEN
    RAISE EXCEPTION 'This distribution has no recorded item/quantity to convert';
  END IF;

  SELECT item_name, unit, COALESCE(unit_cost, 0) AS unit_cost
  INTO v_item
  FROM cooperative_inventory
  WHERE id = v_member.inventory_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The distributed inventory item no longer exists';
  END IF;

  v_line_total := v_member.quantity_given * v_item.unit_cost;

  v_items := jsonb_build_array(jsonb_build_object(
    'itemName',  v_item.item_name,
    'quantity',  v_member.quantity_given,
    'unit',      v_item.unit,
    'unitPrice', v_item.unit_cost,
    'lineTotal', v_line_total
  ));

  SELECT * INTO v_result FROM issue_loan(
    v_member.farmer_id,
    v_items,
    CURRENT_DATE,
    p_monthly_payment,
    p_next_payment_date,
    COALESCE(p_notes, 'From Program Distribution: ' || v_member.program_name),
    auth.uid(),
    NULL
  );

  UPDATE farmer_loans
  SET source_program_id = v_member.program_id
  WHERE id = v_result.loan_id;

  UPDATE program_members
  SET distribution_outcome = 'failed',
      outcome_recorded_at = NOW(),
      converted_loan_id = v_result.loan_id
  WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_member.farmer_id, 'program', 'Program Outcome: Failed',
    'Your distribution from ' || COALESCE(v_member.program_name, 'the program') ||
      ' was recorded as failed and converted to loan ' || v_result.reference_no || '.',
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_result.loan_id, v_result.reference_no;
END;
$function$;

-- ─── B. BOD meeting notice (3 days before) ───────────────────────────────────
-- First Saturday of the month for a given date (PLACEHOLDER rule).
CREATE OR REPLACE FUNCTION public.bod_first_saturday(p_month_of date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (date_trunc('month', p_month_of)::date
          + ((6 - EXTRACT(DOW FROM date_trunc('month', p_month_of))::int + 7) % 7));
$$;

-- The next BOD meeting on or after p_today (PLACEHOLDER rule).
CREATE OR REPLACE FUNCTION public.bod_next_meeting(p_today date DEFAULT CURRENT_DATE)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_this date := public.bod_first_saturday(p_today);
BEGIN
  IF v_this >= p_today THEN
    RETURN v_this;
  END IF;
  RETURN public.bod_first_saturday((date_trunc('month', p_today) + interval '1 month')::date);
END;
$$;

-- Sends the notice exactly 3 days before the next meeting. Run once a day by
-- the cron job below, so each meeting is announced once.
CREATE OR REPLACE FUNCTION public.notify_bod_meeting_upcoming(p_today date DEFAULT CURRENT_DATE)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meeting date := public.bod_next_meeting(p_today);
  v_count   integer := 0;
  v_body    text;
BEGIN
  IF v_meeting - p_today <> 3 THEN
    RETURN 0;
  END IF;

  v_body := 'The BOD meeting is on ' || to_char(v_meeting, 'FMMonth DD, YYYY') || ' (in 3 days).';

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'loan', 'BOD Meeting in 3 Days', v_body, FALSE, NOW(), '/farmer/profile/loans'
  FROM user_roles ur
  WHERE ur.role = 'farmer' AND ur.status = 'active';
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'system', 'BOD Meeting in 3 Days', v_body, FALSE, NOW(), '/admin/loans'
  FROM user_roles ur
  WHERE ur.role IN ('admin', 'officer');

  RETURN v_count;
END;
$$;

-- Daily at 08:00 Manila (00:00 UTC). Unschedule first so re-runs stay single.
DO $$
BEGIN
  PERFORM cron.unschedule('bod-meeting-upcoming');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'bod-meeting-upcoming',
  '0 0 * * *',
  $$ SELECT public.notify_bod_meeting_upcoming(); $$
);

-- ─── Verification (run after applying) ───────────────────────────────────────
--   select public.bod_next_meeting(date 2026-10-07);   -- 2026-11-07 (first Saturday of November 2026)
--   select jobname, schedule from cron.job where jobname = bod-meeting-upcoming;   -- 1 row
