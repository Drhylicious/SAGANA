-- ============================================================
-- SAGANA — Staff notifications go to ACTIVE Manager and Officer accounts only
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it once in the Supabase SQL editor (after m01-m07), then
-- the CHECKS at the bottom. One transaction, safe to re-run.
--
-- THE GAP THIS CLOSES
--   Two of the new order functions told "every admin and officer row" about an order, without
--   looking at the account status, so a suspended or pending staff account would have received
--   the notice too. The older generic helper (notify_staff) already filters on active accounts;
--   these two did not.
--     1. _pp_notify_staff()          new Cooperative order, cancelled, completed notices (m04)
--     2. _order_after_completion()   the "Order Completed" notice for Marketplace orders (m05)
--
-- HOW (so nothing newer is overwritten)
--   1. is replaced by a small wrapper that calls notify_staff() (active accounts only).
--   2. is patched IN PLACE from its LIVE definition: only the staff recipient line gets
--      "AND ur.status = 'active'". If that line is not found the script stops and changes
--      nothing, unless the function already filters on status.
--
-- NOT CHANGED: tables, columns, policies, grants, what any notice says, who gets the
-- consumer's own notices.
-- ============================================================

BEGIN;

-- 1. Cooperative order notices to staff: active accounts only (through the existing helper).
CREATE OR REPLACE FUNCTION public._pp_notify_staff(p_title text, p_body text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.notify_staff('order', p_title, p_body, '/admin/marketplace/orders');
$$;
REVOKE ALL ON FUNCTION public._pp_notify_staff(text, text) FROM PUBLIC, anon, authenticated;

-- 2. Marketplace "Order Completed" notice: patch the staff recipient line in place.
DO $patch$
DECLARE
  v_oid  oid;
  v_def  text;
  v_new  text;
  c_find CONSTANT text := $p$FROM user_roles ur WHERE ur.role IN ('admin', 'officer');$p$;
  c_repl CONSTANT text := $r$FROM user_roles ur WHERE ur.role IN ('admin', 'officer') AND ur.status = 'active';$r$;
BEGIN
  SELECT p.oid INTO v_oid
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace AND p.proname = '_order_after_completion'
   LIMIT 1;
  IF v_oid IS NULL THEN
    RAISE EXCEPTION '_order_after_completion() does not exist. Run m05 first.';
  END IF;
  v_def := pg_get_functiondef(v_oid);
  IF v_def ~* 'ur\.status\s*=\s*''active''' THEN
    RAISE NOTICE '_order_after_completion() already limits staff notices to active accounts.';
    RETURN;
  END IF;
  v_new := replace(v_def, c_find, c_repl);
  IF v_new = v_def THEN
    RAISE EXCEPTION '_order_after_completion(): the staff recipient line was not found, so nothing was changed. Send me the live definition (CHECKS C1).';
  END IF;
  EXECUTE v_new;
END
$patch$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only; run after the script)
-- ============================================================
-- C1  Both functions now limit staff notices to active accounts (expect true, true):
--     SELECT
--       pg_get_functiondef('public._pp_notify_staff(text,text)'::regprocedure) ILIKE '%notify_staff(%' AS pp_uses_active_helper,
--       pg_get_functiondef(p.oid) ~* 'ur\.status\s*=\s*''active''' AS completion_active_only
--     FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = '_order_after_completion';
--
-- C2  The helper still filters on active accounts:
--     SELECT pg_get_functiondef('public.notify_staff(text,text,text,text)'::regprocedure) ILIKE '%status = ''active''%' AS helper_filters_active;
--
-- C3  The Cooperative order notice still reaches an active Manager: place a Cooperative order
--     as a Farmer, then
--     SELECT user_id, title, route_on_tap FROM notifications
--      WHERE title = 'New Cooperative Order' ORDER BY created_at DESC LIMIT 5;   -- route /admin/marketplace/orders
