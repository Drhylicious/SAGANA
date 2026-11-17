-- ============================================================================
-- Notification audit 03: the Farmer is told when staff change something that
-- affects them.
--
-- Found in the audit: three staff actions change a Farmer's own record and tell
-- them nothing (live definitions checked):
--   * adjust_program_return    the quantity the Farmer must return was changed
--   * close_program_return     the Farmer's harvest return was closed short
--   * set_monthly_contribution_waiver  a monthly contribution was waived/restored
--
-- Each function is re-created EXACTLY as it is live today with one addition: a
-- notification to the Farmer. Run once, in the Supabase SQL editor, after audit
-- 02 (that script's trigger also applies to these notifications).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.adjust_program_return(
  p_return_id uuid, p_new_quantity numeric, p_reason text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ret    program_returns%ROWTYPE;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can adjust a harvest return.';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'RETURN_REASON: A reason is required to change the quantity.';
  END IF;
  SELECT * INTO v_ret FROM program_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RETURN_CLOSED: Harvest return not found.';
  END IF;
  IF v_ret.status IN ('received', 'closed_short') THEN
    RAISE EXCEPTION 'RETURN_CLOSED: This harvest return is already closed.';
  END IF;
  IF p_new_quantity IS NULL OR p_new_quantity <= 0 OR p_new_quantity <> round(p_new_quantity, 2) THEN
    RAISE EXCEPTION 'RETURN_REASON: Enter a quantity greater than zero.';
  END IF;
  IF p_new_quantity < v_ret.received_quantity THEN
    RAISE EXCEPTION 'RETURN_OVER_RECEIPT: The quantity due cannot be lower than what was already received.';
  END IF;
  IF p_new_quantity = v_ret.due_quantity THEN
    RETURN;
  END IF;

  UPDATE program_returns
     SET due_quantity = p_new_quantity,
         status = CASE WHEN received_quantity >= p_new_quantity THEN 'received'
                       WHEN received_quantity > 0 THEN 'partial' ELSE 'pending' END
   WHERE id = p_return_id;

  INSERT INTO program_return_events
    (return_id, event_type, quantity_before, quantity_after, reason, actor_id, actor_name, actor_role)
  SELECT p_return_id, 'adjusted', v_ret.due_quantity, p_new_quantity, v_reason, auth.uid(), a_name, a_role
    FROM public._outcome_actor();

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_ret.farmer_id, 'program', 'Return Quantity Changed',
          'The quantity of ' || v_ret.crop_name || ' you are to return was changed from ' ||
            v_ret.due_quantity || ' to ' || p_new_quantity || ' ' || v_ret.unit || '. Reason: ' || v_reason,
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
END;
$function$;

CREATE OR REPLACE FUNCTION public.close_program_return(p_return_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ret    program_returns%ROWTYPE;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
  v_name   TEXT;
  v_role   TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can close a harvest return.';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'RETURN_REASON: A reason is required to close a return with less than was due.';
  END IF;
  SELECT * INTO v_ret FROM program_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RETURN_CLOSED: Harvest return not found.';
  END IF;
  IF v_ret.status IN ('received', 'closed_short') THEN
    RAISE EXCEPTION 'RETURN_CLOSED: This harvest return is already closed.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  UPDATE program_returns
     SET status = 'closed_short', closed_reason = v_reason,
         closed_by = auth.uid(), closed_by_name = v_name, closed_at = NOW()
   WHERE id = p_return_id;

  INSERT INTO program_return_events
    (return_id, event_type, quantity_before, quantity_after, reason, actor_id, actor_name, actor_role)
  VALUES (p_return_id, 'closed', v_ret.due_quantity, v_ret.received_quantity, v_reason, auth.uid(), v_name, v_role);

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_ret.farmer_id, 'program', 'Harvest Return Closed',
          'The cooperative closed your return of ' || v_ret.crop_name || ' with ' || v_ret.received_quantity ||
            ' of ' || v_ret.due_quantity || ' ' || v_ret.unit || ' received. Reason: ' || v_reason,
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_monthly_contribution_waiver(
  p_farmer_id uuid, p_month date, p_waive boolean, p_reason text DEFAULT NULL::text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_month  date := date_trunc('month', p_month)::date;
  v_reason text := btrim(COALESCE(p_reason, ''));
  v_row    public.member_monthly_contributions%ROWTYPE;
  v_paid   numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only the Manager or an Officer who manages Members can waive a month.';
  END IF;

  SELECT * INTO v_row
  FROM public.member_monthly_contributions
  WHERE farmer_id = p_farmer_id AND contribution_month = v_month
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This Farmer has no monthly contribution recorded for that month.';
  END IF;

  IF p_waive THEN
    IF length(v_reason) < 3 THEN
      RAISE EXCEPTION 'Enter the reason for the waiver (at least 3 characters).';
    END IF;
    IF length(v_reason) > 500 THEN
      RAISE EXCEPTION 'The reason is too long (500 characters at most).';
    END IF;
    IF v_row.waived_at IS NOT NULL THEN
      RAISE EXCEPTION 'This month is already waived.';
    END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM public.capital_contribution_events
    WHERE farmer_id = p_farmer_id AND contribution_month = v_month AND source = 'member_payment';
    IF v_paid > 0 THEN
      RAISE EXCEPTION 'A payment is already recorded for this month. Cancel it before waiving the month.';
    END IF;
    UPDATE public.member_monthly_contributions
    SET waived_at = now(), waived_by = auth.uid(), waive_reason = v_reason
    WHERE id = v_row.id;
  ELSE
    IF v_row.waived_at IS NULL THEN
      RAISE EXCEPTION 'This month is not waived.';
    END IF;
    UPDATE public.member_monthly_contributions
    SET waived_at = NULL, waived_by = NULL, waive_reason = NULL
    WHERE id = v_row.id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    p_farmer_id, 'capital',
    CASE WHEN p_waive THEN 'Monthly Contribution Waived' ELSE 'Monthly Contribution Waiver Removed' END,
    CASE WHEN p_waive
         THEN 'Your ' || to_char(v_month, 'FMMonth YYYY') || ' monthly contribution was waived. Reason: ' || v_reason
         ELSE 'The waiver of your ' || to_char(v_month, 'FMMonth YYYY') || ' monthly contribution was removed. It is due again.'
    END,
    FALSE, NOW(), '/farmer/profile/contribution'
  );
END;
$function$;
