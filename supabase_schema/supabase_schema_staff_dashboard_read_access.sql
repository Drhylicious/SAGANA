-- ============================================================
-- SAGANA — Staff read-only Dashboard access
-- Staff sessions currently receive RLS-empty results across most
-- of the Admin Dashboard because every existing admin-gate policy
-- checks admin_profiles membership or user_roles.role='admin',
-- neither of which a Staff account (role='staff', staff_profiles
-- row only) satisfies. This grants Staff SELECT-only visibility
-- on the same nine tables, via new additive policies. No existing
-- policy (including the ALL-command admin policies that also
-- cover INSERT/UPDATE/DELETE on several of these tables) is
-- modified — Staff gains visibility only, no write access.
-- ============================================================

CREATE POLICY "cooperative_inventory: staff reads all"
  ON public.cooperative_inventory FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "harvest_records: staff reads all"
  ON public.harvest_records FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "marketplace_listings: staff reads all"
  ON public.marketplace_listings FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "farmer_loans: staff reads all"
  ON public.farmer_loans FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "crop_requests: staff reads all"
  ON public.crop_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "broadcast_logs: staff reads all"
  ON public.broadcast_logs FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "user_roles: staff reads all"
  ON public.user_roles FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "user_information: staff reads all"
  ON public.user_information FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "farmer_profiles: staff reads all"
  ON public.farmer_profiles FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

NOTIFY pgrst, 'reload schema';
