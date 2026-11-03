-- ============================================================
-- SAGANA — Officer permissions, script 2 of 6: ENFORCEMENT (the request gate)
--
-- Requires script 01. Safe to run on its own: nothing here takes effect until
-- script 06 registers the gate with PostgREST.
--
-- HOW ENFORCEMENT WORKS
--   Every write an Officer can make reaches the database through PostgREST,
--   either as a table write (POST / PATCH / DELETE /<table>) or as an RPC call
--   (POST /rpc/<function>). PostgREST runs one "pre-request" function in the
--   same transaction before it does anything. public.staff_permission_gate()
--   is that function. For an Officer it:
--     1. lets every read through (GET / HEAD) — View Only still sees the data;
--     2. looks the target (table or RPC) up in staff_permission_targets;
--     3. refuses (SQLSTATE 42501) unless the Officer holds 'manage' on that
--        target's module;
--     4. for a Members target, marks the transaction so is_platform_admin()
--        accepts the Officer (script 01, section 4).
--   Managers, Farmers, Buyers and anonymous callers are returned immediately.
--
-- WHY A GATE INSTEAD OF EDITING EVERY POLICY AND RPC
--   Authorization is currently spread over ~100 RPCs and ~70 policies, many
--   redefined several times across the migration history. Rewriting them from
--   the repository copies could silently revert newer live fixes. One mapping
--   table is auditable in one query (see the coverage check at the bottom) and
--   cannot drift from the live definitions.
--
-- WHAT IT DOES NOT COVER (be aware)
--   * Supabase Storage uploads (photos) and Edge Functions do not pass through
--     PostgREST. They are unaffected by the gate.
--   * An RPC or table that is not in staff_permission_targets is allowed for
--     Officers, exactly as today. Run the coverage check to list candidates.
--   * "Reports" has no database writes; its Manage level controls exports in
--     the app only.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Mapping: which module governs which table / RPC
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.staff_permission_targets (
  kind   TEXT NOT NULL CHECK (kind IN ('table', 'rpc')),
  name   TEXT NOT NULL,
  module TEXT NOT NULL
         CHECK (module IN ('dashboard', 'members', 'marketplace', 'loans', 'reports')),
  PRIMARY KEY (kind, name)
);

COMMENT ON TABLE public.staff_permission_targets IS
  'Maps each staff-write table / RPC to the permission module that governs it. '
  'Read by staff_permission_gate(). Changed by a database administrator only.';

ALTER TABLE public.staff_permission_targets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_permission_targets: staff reads" ON public.staff_permission_targets;
CREATE POLICY "staff_permission_targets: staff reads"
  ON public.staff_permission_targets FOR SELECT USING (public.is_staff());
REVOKE ALL ON public.staff_permission_targets FROM PUBLIC, anon;
GRANT SELECT ON public.staff_permission_targets TO authenticated;

-- Re-runnable: the mapping is replaced as a whole.
DELETE FROM public.staff_permission_targets;

INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  -- ── Dashboard: the management modules reached from the Dashboard ───────
  ('table', 'crop_master',                 'dashboard'),
  ('table', 'crop_categories',             'dashboard'),
  ('table', 'crop_requests',               'dashboard'),
  ('table', 'cooperative_inventory',       'dashboard'),
  ('table', 'inventory_categories',        'dashboard'),
  ('table', 'inventory_transactions',      'dashboard'),
  ('table', 'units',                       'dashboard'),
  ('table', 'cooperative_programs',        'dashboard'),
  ('table', 'program_activities',          'dashboard'),
  ('table', 'program_members',             'dashboard'),
  ('table', 'program_products',            'dashboard'),
  ('table', 'program_product_purchases',   'dashboard'),
  ('table', 'program_enrollment_requests', 'dashboard'),
  ('table', 'loan_items_master',           'dashboard'),
  ('table', 'price_records',               'dashboard'),
  ('table', 'broadcast_logs',              'dashboard'),
  ('rpc',   'adjust_cooperative_stock',    'dashboard'),
  ('rpc',   'adjust_inventory_stock',      'dashboard'),
  ('rpc',   'delete_inventory_item',       'dashboard'),
  ('rpc',   'approve_crop_request',        'dashboard'),
  ('rpc',   'reject_crop_request',         'dashboard'),
  ('rpc',   'send_broadcast',              'dashboard'),
  ('rpc',   'notify_price_update',         'dashboard'),
  ('rpc',   'confirm_program_purchase',    'dashboard'),
  ('rpc',   'cancel_program_purchase',     'dashboard'),
  ('rpc',   'confirm_program_return',      'dashboard'),
  ('rpc',   'convert_program_distribution_to_loan', 'dashboard'),
  ('rpc',   'distribute_program_benefit',  'dashboard'),
  ('rpc',   'record_program_thriving_outcome', 'dashboard'),
  ('rpc',   'respond_to_program_enrollment_request', 'dashboard'),

  -- ── Marketplace: listings, orders, offers, market linking ──────────────
  ('table', 'marketplace_listings',        'marketplace'),
  ('table', 'listing_edit_requests',       'marketplace'),
  ('table', 'orders',                      'marketplace'),
  ('table', 'cooperative_purchase_offers', 'marketplace'),
  ('table', 'cooperative_offer_events',    'marketplace'),
  ('table', 'member_sales_transactions',   'marketplace'),
  ('table', 'market_linking_programs',     'marketplace'),
  ('table', 'market_linking_sales',        'marketplace'),
  ('table', 'da_amad_enrollments',         'marketplace'),
  ('rpc',   'approve_listing',             'marketplace'),
  ('rpc',   'reject_listing',              'marketplace'),
  ('rpc',   'approve_listing_edit',        'marketplace'),
  ('rpc',   'reject_listing_edit',         'marketplace'),
  ('rpc',   'admin_update_listing_price',  'marketplace'),
  ('rpc',   'approve_order',               'marketplace'),
  ('rpc',   'mark_order_ready_for_pickup', 'marketplace'),
  ('rpc',   'mark_order_out_for_delivery', 'marketplace'),
  ('rpc',   'mark_order_delivered',        'marketplace'),
  ('rpc',   'complete_order',              'marketplace'),
  ('rpc',   'cancel_order',                'marketplace'),
  ('rpc',   'counter_cooperative_offer',   'marketplace'),
  ('rpc',   'accept_cooperative_offer',    'marketplace'),
  ('rpc',   'decline_cooperative_offer',   'marketplace'),
  ('rpc',   'confirm_cooperative_offer',   'marketplace'),
  ('rpc',   'confirm_cooperative_offer_receipt', 'marketplace'),
  ('rpc',   'cancel_cooperative_offer',    'marketplace'),
  ('rpc',   'record_market_linking_sale',  'marketplace'),
  ('rpc',   'complete_market_linking',     'marketplace'),
  ('rpc',   'respond_to_da_amad_enrollment', 'marketplace'),
  ('rpc',   'respond_to_market_linking_cancellation', 'marketplace'),
  ('rpc',   'respond_to_market_linking_request', 'marketplace'),
  ('rpc',   'save_market_linking_buyer_details', 'marketplace'),

  -- ── Loans ──────────────────────────────────────────────────────────────
  ('table', 'farmer_loans',                'loans'),
  ('table', 'farmer_loan_items',           'loans'),
  ('table', 'farmer_loan_payments',        'loans'),
  ('table', 'loan_requests',               'loans'),
  ('table', 'loan_request_items',          'loans'),
  ('table', 'loan_policy_settings',        'loans'),
  ('rpc',   'issue_loan',                  'loans'),
  ('rpc',   'record_loan_payment',         'loans'),
  ('rpc',   'review_loan_request',         'loans'),

  -- ── Members ────────────────────────────────────────────────────────────
  ('table', 'member_capital_shares',       'members'),
  ('table', 'capital_contribution_events', 'members'),
  ('table', 'member_status_events',        'members'),
  ('table', 'password_reset_requests',     'members'),
  ('rpc',   'approve_member',              'members'),
  ('rpc',   'reject_member',               'members'),
  ('rpc',   'suspend_member',              'members'),
  ('rpc',   'reactivate_member',           'members'),
  ('rpc',   'create_farmer_account',       'members'),
  ('rpc',   'create_officer_account',      'members'),
  ('rpc',   'admin_delete_rejected_applicant', 'members'),
  ('rpc',   'admin_reset_user_password',   'members'),
  ('rpc',   'resolve_password_reset_request', 'members'),
  ('rpc',   'set_officer_permissions',     'members');

-- ════════════════════════════════════════════════════════════
-- 2. The gate
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.staff_permission_gate()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid;
  v_method text;
  v_path   text;
  v_kind   text;
  v_name   text;
  v_module text;
  v_role   text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN;                                   -- anonymous / service role
  END IF;

  -- Only Officers are gated. One indexed lookup for everyone else.
  SELECT role INTO v_role FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'officer' THEN
    RETURN;
  END IF;

  v_method := upper(COALESCE(current_setting('request.method', true), ''));
  IF v_method IN ('GET', 'HEAD', 'OPTIONS') THEN
    RETURN;                                   -- View Only still reads everything
  END IF;

  v_path := COALESCE(current_setting('request.path', true), '');
  IF v_path ~ '/rpc/[A-Za-z0-9_]+' THEN
    v_kind := 'rpc';
    v_name := substring(v_path FROM '/rpc/([A-Za-z0-9_]+)');
  ELSE
    v_kind := 'table';
    v_name := substring(v_path FROM '([A-Za-z0-9_]+)/?$');
  END IF;

  SELECT t.module INTO v_module
  FROM staff_permission_targets t
  WHERE t.kind = v_kind AND t.name = v_name;

  IF v_module IS NULL THEN
    RETURN;                                   -- not a governed target
  END IF;

  IF public.staff_access_level(v_module, v_uid) = 'manage' THEN
    IF v_module = 'members' THEN
      -- Lets is_platform_admin() accept this Officer for THIS transaction only.
      PERFORM set_config('sagana.members_manage', 'on', true);
    END IF;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Your Officer account has view-only access to the % module. Ask the Manager to give you Manage access.', v_module
    USING ERRCODE = '42501';
END;
$$;

REVOKE ALL ON FUNCTION public.staff_permission_gate() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.staff_permission_gate()
  TO anon, authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- COVERAGE CHECK — staff-guarded functions that are NOT governed yet.
-- Read the list; anything an Officer should not run while view-only belongs in
-- the INSERT above (then re-run this script). Run by itself:
--
--   SELECT p.proname
--   FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace
--     AND p.prokind = 'f'
--     AND (p.prosrc ILIKE '%is_staff()%' OR p.prosrc ILIKE '%is_platform_admin%'
--          OR p.prosrc ILIKE '%officer_profiles%')
--     AND p.proname NOT LIKE '\_%'
--     AND NOT EXISTS (SELECT 1 FROM staff_permission_targets t
--                     WHERE t.kind = 'rpc' AND t.name = p.proname)
--   ORDER BY 1;
--
-- Tables with a staff write policy that are not governed yet:
--
--   SELECT DISTINCT tablename FROM pg_policies
--   WHERE schemaname = 'public' AND cmd IN ('ALL','INSERT','UPDATE','DELETE')
--     AND (qual ILIKE '%is_staff()%' OR with_check ILIKE '%is_staff()%'
--          OR qual ILIKE '%is_platform_admin%')
--     AND tablename NOT IN (SELECT name FROM staff_permission_targets WHERE kind = 'table')
--   ORDER BY 1;
-- ============================================================
