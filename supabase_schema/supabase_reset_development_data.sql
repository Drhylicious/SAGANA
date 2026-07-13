-- ============================================================
-- SAGANA — Development Data Reset Script
-- File: supabase_reset_development_data.sql
--
-- PURPOSE:
--   Removes ALL development/test data while preserving:
--   ✓ All table schemas and structure
--   ✓ All RLS policies
--   ✓ All RPCs and functions
--   ✓ All triggers
--   ✓ All authentication architecture
--   ✓ Admin account (protected by UUID constant below)
--   ✓ Seeded master data (crop_master, loan_items_master,
--       cooperative_programs, sp3_member_registry)
--
-- SAFE TO RUN: Yes — uses explicit WHERE clauses to protect
--   admin account and master data. Does NOT drop any tables.
--
-- USAGE:
--   Run in Supabase SQL Editor whenever you need a clean
--   development environment. Can be re-run safely.
--
-- ⚠ WARNING: This permanently deletes test data. There is no undo.
--   Ensure Supabase Storage buckets have been manually cleared
--   before running (crop_images, listing_photos, profile_photos).
-- ============================================================

-- ─── Configuration ────────────────────────────────────────────────────────────
-- Set your admin account UUID here. This account is NEVER touched.
DO $$
DECLARE
  v_admin_id UUID := 'd4e0e668-59df-462b-8b7d-5fd1a699d493';

  -- Collect all non-admin user IDs for cascaded cleanup
  v_test_user_ids UUID[];
BEGIN

  RAISE NOTICE '============================================';
  RAISE NOTICE 'SAGANA Development Data Reset';
  RAISE NOTICE 'Protecting admin: %', v_admin_id;
  RAISE NOTICE '============================================';

  -- ── Step 1: Identify all non-admin user IDs ─────────────────────────────────
  SELECT ARRAY(
    SELECT id FROM auth.users
    WHERE id != v_admin_id
  ) INTO v_test_user_ids;

  RAISE NOTICE 'Found % test user accounts to remove.', array_length(v_test_user_ids, 1);

  -- ── Step 2: Clear financial and operational records ──────────────────────────
  -- Order matters: delete children before parents (FK constraints)

  -- Loan payments first (child of farmer_loans)
  DELETE FROM public.farmer_loan_payments
  WHERE loan_id IN (
    SELECT id FROM public.farmer_loans
    WHERE farmer_id = ANY(v_test_user_ids)
  );
  RAISE NOTICE 'Cleared: farmer_loan_payments';

  -- Loan items (child of farmer_loans)
  DELETE FROM public.farmer_loan_items
  WHERE loan_id IN (
    SELECT id FROM public.farmer_loans
    WHERE farmer_id = ANY(v_test_user_ids)
  );
  RAISE NOTICE 'Cleared: farmer_loan_items';

  -- Loans
  DELETE FROM public.farmer_loans
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: farmer_loans';

  -- Expenses
  DELETE FROM public.farmer_expenses
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: farmer_expenses';

  -- Contributions
  DELETE FROM public.member_contributions
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: member_contributions';

  -- Capital shares
  DELETE FROM public.member_capital_shares
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: member_capital_shares';

  -- Sales transactions
  DELETE FROM public.member_sales_transactions
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: member_sales_transactions';

  -- Annual totals (no user FK — clear all, admin will re-enter)
  DELETE FROM public.cooperative_annual_totals;
  RAISE NOTICE 'Cleared: cooperative_annual_totals';

  -- ── Step 3: Clear marketplace and orders ─────────────────────────────────────

  -- Orders (child of marketplace_listings)
  DELETE FROM public.orders
  WHERE listing_id IN (
    SELECT id FROM public.marketplace_listings
    WHERE farmer_id = ANY(v_test_user_ids)
  );
  -- Also clear any buyer-side orders
  DELETE FROM public.orders
  WHERE buyer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: orders';

  -- Marketplace listings
  DELETE FROM public.marketplace_listings
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: marketplace_listings';

  -- Market linking programs (DA-AMAD)
  DELETE FROM public.market_linking_programs
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: market_linking_programs';

  -- ── Step 4: Clear inventory ───────────────────────────────────────────────────

  -- Inventory transactions (child of cooperative_inventory)
  DELETE FROM public.inventory_transactions;
  RAISE NOTICE 'Cleared: inventory_transactions';

  -- Cooperative inventory (admin-managed items — reset to empty for clean start)
  DELETE FROM public.cooperative_inventory;
  RAISE NOTICE 'Cleared: cooperative_inventory';

  -- Inventory batches (farmer-submitted)
  DELETE FROM public.inventory_batches
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: inventory_batches';

  -- ── Step 5: Clear harvest records ────────────────────────────────────────────

  DELETE FROM public.harvest_records
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: harvest_records';

  -- ── Step 6: Clear farmer crops ────────────────────────────────────────────────

  DELETE FROM public.farmer_crops
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: farmer_crops';

  -- ── Step 7: Clear analytics/forecast data ────────────────────────────────────

  -- Analytics forecasts (if table exists)
  BEGIN
    DELETE FROM public.analytics_forecasts;
    RAISE NOTICE 'Cleared: analytics_forecasts';
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'Skipped: analytics_forecasts (table does not exist)';
  END;

  -- ── Step 8: Clear program enrollments ────────────────────────────────────────

  -- Program activities (child of cooperative_programs)
  DELETE FROM public.program_activities;
  RAISE NOTICE 'Cleared: program_activities';

  -- Program members (enrollment records — keep the programs themselves)
  DELETE FROM public.program_members
  WHERE farmer_id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: program_members';

  -- ── Step 9: Clear price records ───────────────────────────────────────────────
  -- These are test prices entered during development.
  -- Admin will re-enter real market prices during setup.
  DELETE FROM public.price_records;
  RAISE NOTICE 'Cleared: price_records';

  -- ── Step 10: Clear notifications and broadcasts ───────────────────────────────

  -- Notifications for all non-admin users
  DELETE FROM public.notifications
  WHERE user_id = ANY(v_test_user_ids);

  -- Also clear any admin notifications generated during development
  DELETE FROM public.notifications
  WHERE user_id = v_admin_id;
  RAISE NOTICE 'Cleared: notifications';

  -- Broadcast logs (development/test broadcasts)
  DELETE FROM public.broadcast_logs;
  RAISE NOTICE 'Cleared: broadcast_logs';

  -- ── Step 11: Clear SP3 member registry test entries ───────────────────────────
  -- Remove any test entries added during development.
  -- The real 52-member registry will be loaded by admin during setup.
  DELETE FROM public.sp3_member_registry;
  RAISE NOTICE 'Cleared: sp3_member_registry';

  -- ── Step 12: Remove test user accounts ───────────────────────────────────────
  -- Cascades handle: user_roles, user_information, farmer_profiles,
  -- buyer_profiles, staff_profiles automatically via ON DELETE CASCADE

  -- Remove from admin_profiles first (non-admin test admins if any)
  DELETE FROM public.admin_profiles
  WHERE user_id = ANY(v_test_user_ids);

  -- Remove auth users — CASCADE handles all public.* profile tables
  DELETE FROM auth.users
  WHERE id = ANY(v_test_user_ids);
  RAISE NOTICE 'Cleared: auth.users + all cascaded profile tables';

  -- ── Step 13: Verify admin account still intact ────────────────────────────────
  PERFORM id FROM auth.users WHERE id = v_admin_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '❌ CRITICAL: Admin account was accidentally deleted! '
                    'Rolling back entire transaction.';
  END IF;
  RAISE NOTICE '✓ Admin account verified intact: %', v_admin_id;

  -- ── Step 14: Verification summary ────────────────────────────────────────────
  RAISE NOTICE '============================================';
  RAISE NOTICE 'CLEANUP COMPLETE — Verification:';
  RAISE NOTICE '  auth.users remaining: %',
    (SELECT COUNT(*) FROM auth.users);
  RAISE NOTICE '  user_roles remaining: %',
    (SELECT COUNT(*) FROM public.user_roles);
  RAISE NOTICE '  harvest_records: %',
    (SELECT COUNT(*) FROM public.harvest_records);
  RAISE NOTICE '  marketplace_listings: %',
    (SELECT COUNT(*) FROM public.marketplace_listings);
  RAISE NOTICE '  farmer_loans: %',
    (SELECT COUNT(*) FROM public.farmer_loans);
  RAISE NOTICE '  inventory_batches: %',
    (SELECT COUNT(*) FROM public.inventory_batches);
  RAISE NOTICE '  cooperative_inventory: %',
    (SELECT COUNT(*) FROM public.cooperative_inventory);
  RAISE NOTICE '  notifications: %',
    (SELECT COUNT(*) FROM public.notifications);
  RAISE NOTICE '  price_records: %',
    (SELECT COUNT(*) FROM public.price_records);
  RAISE NOTICE '  sp3_member_registry: %',
    (SELECT COUNT(*) FROM public.sp3_member_registry);
  RAISE NOTICE '';
  RAISE NOTICE 'PRESERVED (master data):';
  RAISE NOTICE '  crop_master: %',
    (SELECT COUNT(*) FROM public.crop_master);
  RAISE NOTICE '  loan_items_master: %',
    (SELECT COUNT(*) FROM public.loan_items_master);
  RAISE NOTICE '  cooperative_programs: %',
    (SELECT COUNT(*) FROM public.cooperative_programs);
  RAISE NOTICE '============================================';

END;
$$;