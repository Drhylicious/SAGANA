-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_marketplace_filter_counts_realtime.sql
--
-- Lets the Manager's Marketplace filter counts move on their own.
--
-- Every Marketplace screen (All Listings, Listing Approvals, Order Management,
-- Market Linking, Market Linking Enrollments, Offer to Cooperative) counts its
-- filter chips from the records it loaded, and reloads quietly when one of its
-- tables changes. For that, the tables must be in the Supabase realtime
-- publication. marketplace_listings and orders already are
-- (supabase_schema_stock_integrity.sql, STEP 3b). This adds the other three.
--
-- Nothing else changes: no table, column, policy or function is touched, and
-- no data is read or written. Without this script the screens still work; the
-- counts then refresh on pull-down, on returning to the app and after each
-- action, as before.
--
-- NOT applied automatically. Run it yourself in the Supabase SQL editor.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_table TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'No supabase_realtime publication in this database; nothing to do.';
    RETURN;
  END IF;

  FOREACH v_table IN ARRAY ARRAY['da_amad_enrollments', 'market_linking_programs', 'cooperative_purchase_offers']
  LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE NOTICE 'public.% does not exist, skipped', v_table;
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = v_table
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
    END IF;
  END LOOP;
END $$;

-- ─── Verify: expect all five rows ────────────────────────────────────────────
--   SELECT tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
--     AND tablename IN ('marketplace_listings', 'orders', 'da_amad_enrollments',
--                       'market_linking_programs', 'cooperative_purchase_offers')
--   ORDER BY tablename;
