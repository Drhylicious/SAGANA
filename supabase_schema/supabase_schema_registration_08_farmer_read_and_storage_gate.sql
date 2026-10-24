-- ============================================================
-- SAGANA — Registration refactor, step 8: what a Pending or Disapproved Farmer
-- can READ, and what they can UPLOAD
--
-- Step 5 stopped farmers who are not approved from WRITING to the farmer
-- modules. This closes the other two doors the same way: reading, and Supabase
-- Storage.
--
-- WHO IS AFFECTED. Only a signed-in user whose role is 'farmer' and whose
-- status is draft, pending or rejected (Disapproved). Approved farmers,
-- Managers, Officers, Buyers and system jobs are not affected. (A Suspended
-- farmer is not covered here; suspension signs the person out.)
--
-- 1. READS. A "restrictive" read policy is added to each table below. It is
--    ANDed with the policies already there, so it only ever removes access: an
--    applicant gets zero rows. Covered, because they are approved-member
--    features or cooperative-internal data:
--      programs and their products, activities, members, enrollment requests,
--      purchases and cooperative inventory; loans, loan items, payments, loan
--      policy and the loan-item catalogue; capital shares, contributions and
--      sales; harvest records, inventory batches, expenses, crops and crop
--      requests; informal sales; market-linking records and cooperative
--      purchase offers; the cooperative's annual totals; farmer dashboard
--      settings and activity logs; orders.
--    NOT covered, on purpose (so an applicant can still use the app):
--      * their own account, profile, address, notifications and application
--        history (user_roles, user_information, farmer_profiles,
--        buyer_addresses, notifications, member_status_events);
--      * information that is public to every signed-in user: market prices,
--        the crop / category / ownership lookup lists, approved marketplace
--        listings.
--
-- 2. STORAGE. Uploading, replacing or deleting files in the crop, listing and
--    cooperative-inventory photo buckets is refused for an applicant. The
--    profile-photo bucket stays open (a permitted personal detail).
--    All four buckets are PUBLIC: anyone with a photo's link can open it
--    without signing in, and no database rule can change that. Product photos
--    are public by design (buyers see them). The policy below is therefore
--    about WRITING, not viewing.
--
-- NOT COVERED BY THIS FILE: views and SECURITY DEFINER functions that read
-- these tables run with their owner's rights and are not filtered by these
-- policies. Those that return the caller's own rows return nothing for an
-- applicant, who has none.
--
-- Not applied automatically. Run the PRE-FLIGHT block, this file, then verify.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Every read policy that is NOT limited to the caller's own rows or to
--    staff — these are the ones an applicant can use today (review the list
--    against the tables below):
--    SELECT tablename, policyname, cmd, roles, qual FROM pg_policies
--    WHERE schemaname = 'public' AND cmd IN ('SELECT', 'ALL')
--      AND qual NOT ILIKE '%is_staff%' AND qual NOT ILIKE '%is_platform_admin%'
--      AND qual NOT ILIKE '%staff_profiles%' AND qual NOT ILIKE '%admin_profiles%'
--      AND qual NOT ILIKE '%officer_profiles%'
--      AND qual NOT ILIKE '%auth.uid() = %'      -- own-rows policies
--    ORDER BY tablename, policyname;
--
-- B. Storage buckets and who may write to them today:
--    SELECT id, public FROM storage.buckets;
--    SELECT policyname, cmd, qual, with_check FROM pg_policies
--    WHERE schemaname = 'storage' AND tablename = 'objects' ORDER BY policyname;
--
-- C. Tables below that do not exist in your database (the loop skips them):
--    SELECT t.name FROM (VALUES ('cooperative_annual_totals'),('cooperative_programs'),
--      ('program_activities'),('program_members'),('program_products'),
--      ('program_product_purchases'),('program_enrollment_requests'),('cooperative_inventory'),
--      ('inventory_transactions'),('loan_items_master'),('loan_policy_settings'),('farmer_loans'),
--      ('farmer_loan_items'),('farmer_loan_payments'),('member_capital_shares'),
--      ('capital_contribution_events'),('member_contributions'),('member_sales_transactions'),
--      ('harvest_records'),('inventory_batches'),('farmer_expenses'),('farmer_crops'),
--      ('crop_requests'),('informal_sales'),('market_linking_programs'),
--      ('cooperative_purchase_offers'),('farmer_dashboard_settings'),('farmer_crop_activity'),
--      ('farmer_home_activity'),('orders')) AS t(name)
--    WHERE to_regclass('public.' || t.name) IS NULL;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- Who counts as an applicant. Callable by signed-in users only.
CREATE OR REPLACE FUNCTION public.is_unapproved_applicant(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_uid AND role = 'farmer' AND status IN ('draft', 'pending', 'rejected')
  );
$$;

REVOKE ALL ON FUNCTION public.is_unapproved_applicant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_unapproved_applicant(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 1. Reads
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'cooperative_annual_totals',
    'cooperative_programs', 'program_activities', 'program_members', 'program_products',
    'program_product_purchases', 'program_enrollment_requests',
    'cooperative_inventory', 'inventory_transactions',
    'loan_items_master', 'loan_policy_settings',
    'farmer_loans', 'farmer_loan_items', 'farmer_loan_payments',
    'member_capital_shares', 'capital_contribution_events',
    'member_contributions', 'member_sales_transactions',
    'harvest_records', 'inventory_batches', 'farmer_expenses', 'farmer_crops',
    'crop_requests', 'informal_sales',
    'market_linking_programs', 'cooperative_purchase_offers',
    'farmer_dashboard_settings', 'farmer_crop_activity', 'farmer_home_activity',
    'orders'
  ]
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (read)', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated '
        'USING (NOT public.is_unapproved_applicant())',
        t || ': approved farmers only (read)', t);
    END IF;
  END LOOP;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. Storage uploads
--    (If your SQL editor role may not create policies on storage.objects, the
--    block prints a notice instead of failing; the same three policies can
--    then be added under Dashboard > Storage > Policies.)
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  DROP POLICY IF EXISTS "approved farmers only: product photo uploads (insert)" ON storage.objects;
  DROP POLICY IF EXISTS "approved farmers only: product photo uploads (update)" ON storage.objects;
  DROP POLICY IF EXISTS "approved farmers only: product photo uploads (delete)" ON storage.objects;

  CREATE POLICY "approved farmers only: product photo uploads (insert)"
    ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    );

  CREATE POLICY "approved farmers only: product photo uploads (update)"
    ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    )
    WITH CHECK (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    );

  CREATE POLICY "approved farmers only: product photo uploads (delete)"
    ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
    USING (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    );
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Not allowed to create policies on storage.objects from this role. Add the three restrictive policies in Dashboard > Storage > Policies instead (see the header of this file).';
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Read policies in place (expect one row per existing table above):
--    SELECT tablename FROM pg_policies
--    WHERE policyname LIKE '%: approved farmers only (read)' ORDER BY 1;
--
-- 2. Storage policies in place (expect 3 rows):
--    SELECT policyname FROM pg_policies
--    WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'approved farmers only:%';
--
-- 3. Simulate a PENDING farmer reading (rolled back). Replace the uuid with a
--    pending farmer's user_id. Expect 0 rows from the first three; the last
--    (their own profile) must still return 1 row:
--    BEGIN;
--      SET LOCAL ROLE authenticated;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<pending farmer uuid>','role','authenticated')::text, true);
--      SELECT count(*) FROM public.cooperative_programs;
--      SELECT count(*) FROM public.cooperative_annual_totals;
--      SELECT count(*) FROM public.loan_items_master;
--      SELECT count(*) FROM public.user_information WHERE user_id = '<pending farmer uuid>';  -- 1
--    ROLLBACK;
--
-- 4. The same three counts for an APPROVED farmer, a Manager and an Officer
--    must be what they were before this file ran (not zero unless the table is
--    empty).
-- ============================================================
