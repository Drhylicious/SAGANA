-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Officer permissions 22 · Register the newer staff actions
-- ═══════════════════════════════════════════════════════════════════════════
-- Run after the scripts that create these functions (r01, s04, s05, c01 and the
-- program rework p25, p33, p36). One transaction. Safe to run more than once.
--
-- WHY
--   An action that is not listed in staff_permission_targets is allowed for any
--   staff member. The app already stops a View Only Officer on these screens,
--   but the database did not: the functions below only checked "is staff". This
--   lists them under Dashboard, so the Officer gate refuses a View Only Officer
--   in the database as well, exactly like the other Dashboard actions.
--
-- WHAT IS REGISTERED (all under Dashboard)
--   Inventory Management   confirm_coop_lot_still_good, report_coop_lot_rotten
--   Crop Requests          set_crop_request_shelf_life, set_crop_request_storage_life
--   Price Management       notify_reference_price_range
--   Crop Management        shelf_life_settings (the expiry-day discount)
--   Program Management     approve_program_redistribution, redistribute_program_member,
--                          set_member_return_arrangement
--
-- NOT CHANGED: no function, table or policy. The Manager and an Officer with
-- Manage on Dashboard are unaffected.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.staff_permission_targets') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_officer_permissions_02_enforcement.sql first.';
  END IF;
END;
$$;

INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc',   'confirm_coop_lot_still_good',    'dashboard'),
  ('rpc',   'report_coop_lot_rotten',         'dashboard'),
  ('rpc',   'set_crop_request_shelf_life',    'dashboard'),
  ('rpc',   'set_crop_request_storage_life',  'dashboard'),
  ('rpc',   'notify_reference_price_range',   'dashboard'),
  ('table', 'shelf_life_settings',            'dashboard'),
  ('rpc',   'approve_program_redistribution', 'dashboard'),
  ('rpc',   'redistribute_program_member',    'dashboard'),
  ('rpc',   'set_member_return_arrangement',  'dashboard')
ON CONFLICT (kind, name) DO NOTHING;

COMMIT;

-- ═══ Check (run after the script; expect 9 rows) ══════════════════════════
--   SELECT kind, name, module FROM staff_permission_targets
--   WHERE name IN ('confirm_coop_lot_still_good', 'report_coop_lot_rotten',
--                  'set_crop_request_shelf_life', 'set_crop_request_storage_life',
--                  'notify_reference_price_range', 'shelf_life_settings',
--                  'approve_program_redistribution', 'redistribute_program_member',
--                  'set_member_return_arrangement')
--   ORDER BY kind, name;
