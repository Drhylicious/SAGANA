-- Officers: Admin-only writes outside their modules, and Balik Tangkilik payouts.
--
-- Officers keep their assigned modules. These tables and actions are Admin-only:
--   member contributions, farmer dashboard settings, expense categories, farm ownership
--   types, cooperative annual totals, broadcast logs, sending notifications, and the
--   Balik Tangkilik payout (confirm and reject).
-- Officers may read these tables where their screens need it. Admin is unchanged.
--
-- Also: an Officer may update their own date of birth and gender (Edit Profile).
-- A trigger stops Officers changing any other field on their officer profile.
--
-- Not applied automatically. Run in the Supabase SQL editor.

BEGIN;

-- 1. Write policies: Officers may read (as before) but not write.
DROP POLICY IF EXISTS "Admin full access to broadcast_logs" ON public.broadcast_logs;
CREATE POLICY "Admin full access to broadcast_logs (read)" ON public.broadcast_logs FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));
CREATE POLICY "Admin full access to broadcast_logs (insert)" ON public.broadcast_logs FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "Admin full access to broadcast_logs (update)" ON public.broadcast_logs FOR UPDATE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "Admin full access to broadcast_logs (delete)" ON public.broadcast_logs FOR DELETE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

DROP POLICY IF EXISTS "cooperative_annual_totals: admin manages all" ON public.cooperative_annual_totals;
CREATE POLICY "cooperative_annual_totals: admin manages all (read)" ON public.cooperative_annual_totals FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));
CREATE POLICY "cooperative_annual_totals: admin manages all (insert)" ON public.cooperative_annual_totals FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "cooperative_annual_totals: admin manages all (update)" ON public.cooperative_annual_totals FOR UPDATE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "cooperative_annual_totals: admin manages all (delete)" ON public.cooperative_annual_totals FOR DELETE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

DROP POLICY IF EXISTS "expense_categories: admin manages all" ON public.expense_categories;
CREATE POLICY "expense_categories: admin manages all (read)" ON public.expense_categories FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));
CREATE POLICY "expense_categories: admin manages all (insert)" ON public.expense_categories FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "expense_categories: admin manages all (update)" ON public.expense_categories FOR UPDATE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "expense_categories: admin manages all (delete)" ON public.expense_categories FOR DELETE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

DROP POLICY IF EXISTS "farm_ownership_types: admin manages all" ON public.farm_ownership_types;
CREATE POLICY "farm_ownership_types: admin manages all (read)" ON public.farm_ownership_types FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));
CREATE POLICY "farm_ownership_types: admin manages all (insert)" ON public.farm_ownership_types FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "farm_ownership_types: admin manages all (update)" ON public.farm_ownership_types FOR UPDATE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "farm_ownership_types: admin manages all (delete)" ON public.farm_ownership_types FOR DELETE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

DROP POLICY IF EXISTS "farmer_dashboard_settings: admin update" ON public.farmer_dashboard_settings;
CREATE POLICY "farmer_dashboard_settings: admin update" ON public.farmer_dashboard_settings FOR UPDATE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

DROP POLICY IF EXISTS "member_contributions: admin manages all" ON public.member_contributions;
CREATE POLICY "member_contributions: admin manages all (read)" ON public.member_contributions FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));
CREATE POLICY "member_contributions: admin manages all (insert)" ON public.member_contributions FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "member_contributions: admin manages all (update)" ON public.member_contributions FOR UPDATE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "member_contributions: admin manages all (delete)" ON public.member_contributions FOR DELETE TO public USING (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admin insert notifications" ON public.notifications;
CREATE POLICY "Admin insert notifications" ON public.notifications FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid())))) AND NOT EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

-- 2. Balik Tangkilik payout: Admin only.
-- confirm_payout_decision
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
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin) OR EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = v_admin) THEN
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
END;
$function$;

-- reject_payout_decision
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
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin) OR EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = v_admin) THEN
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
END;
$function$;

-- 3. Officer Edit Profile: date of birth and gender only.
DROP POLICY IF EXISTS "officer updates own dob and gender" ON public.officer_profiles;
CREATE POLICY "officer updates own dob and gender" ON public.officer_profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE OR REPLACE FUNCTION public.officer_profiles_self_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.is_platform_admin() THEN
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['date_of_birth', 'gender']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['date_of_birth', 'gender']) THEN
    RAISE EXCEPTION 'Officers can change only their date of birth and gender';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS officer_profiles_self_guard ON public.officer_profiles;
CREATE TRIGGER officer_profiles_self_guard BEFORE UPDATE ON public.officer_profiles FOR EACH ROW EXECUTE FUNCTION public.officer_profiles_self_guard();

COMMIT;

NOTIFY pgrst, 'reload schema';
