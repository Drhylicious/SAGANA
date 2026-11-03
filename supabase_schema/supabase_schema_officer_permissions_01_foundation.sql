-- ============================================================
-- SAGANA — Officer permissions, script 1 of 6: FOUNDATION
--
-- Run order (see the header of each file):
--   buyer_suspension_removal (any time before the app release)
--   01 foundation -> 02 enforcement -> 03 broadcast_and_balik
--   -> 04 account_approval -> 05 accountability
--   -> [release the app build] -> 06 enable_gate -> _test
--
-- WHAT THIS DOES
--   1. officer_permissions     one row per (Officer, module): 'view' or 'manage'.
--                              Modules: dashboard, members, marketplace, loans,
--                              reports. Written ONLY by the RPCs below.
--   2. NO backfill             nothing is assigned automatically. Every new
--                              Officer gets all five rows when the account is
--                              created (script 04), Manage unless the Manager
--                              chose View Only for a module.
--   3. Helpers                 is_manager(), staff_module_list(),
--                              staff_access_level(module), staff_can_manage(module).
--   4. RPCs                    get_my_staff_permissions(), get_officer_permissions(),
--                              set_officer_permissions().
--   5. is_platform_admin()     now ALSO true for an Officer who holds Members =
--                              'manage' — but only while the request gate (script
--                              02/06) has marked the request as a Members request.
--                              Every existing Members RPC/policy therefore works
--                              for such an Officer with no change to its body.
--                              Manager-only features (Balik Tangkilik) stay
--                              Manager-only: they test "is_platform_admin AND NOT
--                              officer" or is_manager().
--   6. Rules kept              nobody edits their own access (set_officer_
--                              permissions) and nobody changes an account's role
--                              from the app (trigger on user_roles).
--   7. Staff read policies     Officers can read the Members tables the Members
--                              tab shows (additive; nothing is dropped). The
--                              approval history table, member_status_events, is
--                              NOT opened to Officers.
--
-- There is deliberately NO guard against an Officer managing another Officer or
-- the Manager (suspend, reset password, assign access): that is configured by
-- the Manager through the Members permission, not hard-wired.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor.
-- Until script 06 is run the request gate is off.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run each by itself) ──────────────────────────
-- A. Functions this file replaces — compare with the repo; a hotfix applied only
--    in the live database would be overwritten:
--    SELECT proname, pg_get_function_identity_arguments(oid)
--    FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('is_platform_admin','create_officer_account','create_farmer_account');
--    -- create_officer_account: expect the 12 arguments from registration_12.
-- B. Earlier scripts this depends on (each must return 1 row):
--    SELECT proname FROM pg_proc WHERE proname = 'normalize_name_part';
--    SELECT proname FROM pg_proc WHERE proname = 'issue_member_identifier';
--    SELECT proname FROM pg_proc WHERE proname = 'is_staff';
-- C. No existing officer_permissions table:
--    SELECT to_regclass('public.officer_permissions');   -- expect NULL
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Table
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.officer_permissions (
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  module       TEXT        NOT NULL
               CHECK (module IN ('dashboard', 'members', 'marketplace', 'loans', 'reports')),
  access_level TEXT        NOT NULL DEFAULT 'view'
               CHECK (access_level IN ('view', 'manage')),
  updated_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, module)
);

COMMENT ON TABLE public.officer_permissions IS
  'Per-Officer module access: view (read only) or manage (read + management actions). '
  'Managers are not listed here; they always manage everything. Written only by '
  'set_officer_permissions / create_officer_account.';

ALTER TABLE public.officer_permissions ENABLE ROW LEVEL SECURITY;

-- Read: an Officer reads their own rows; any staff member reads all (the Members
-- tab shows other Officers' access). No INSERT / UPDATE / DELETE policy exists on
-- purpose: only the SECURITY DEFINER functions below can write.
DROP POLICY IF EXISTS "officer_permissions: staff reads" ON public.officer_permissions;
CREATE POLICY "officer_permissions: staff reads"
  ON public.officer_permissions FOR SELECT
  USING (user_id = auth.uid() OR public.is_staff());

REVOKE ALL ON public.officer_permissions FROM PUBLIC, anon;
GRANT SELECT ON public.officer_permissions TO authenticated;

-- Realtime: lets the app pick up a permission change at once.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
         AND tablename = 'officer_permissions'
     )
  THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.officer_permissions;
  END IF;
END
$$;

-- ════════════════════════════════════════════════════════════
-- 2. Helpers
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.staff_module_list()
RETURNS text[]
LANGUAGE sql IMMUTABLE
AS $$ SELECT ARRAY['dashboard', 'members', 'marketplace', 'loans', 'reports']::text[]; $$;

-- The strict Manager check (user_roles.role = 'admin'), never widened.
CREATE OR REPLACE FUNCTION public.is_manager(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id = p_uid AND role = 'admin');
$$;

-- 'manage' for a Manager; the stored level for an Officer (default 'view');
-- NULL for anyone who is not staff.
CREATE OR REPLACE FUNCTION public.staff_access_level(p_module text, p_uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE r.role
           WHEN 'admin'   THEN 'manage'
           WHEN 'officer' THEN COALESCE(
             (SELECT op.access_level FROM officer_permissions op
              WHERE op.user_id = p_uid AND op.module = p_module),
             'view')
           ELSE NULL
         END
  FROM user_roles r
  WHERE r.user_id = p_uid;
$$;

CREATE OR REPLACE FUNCTION public.staff_can_manage(p_module text, p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$ SELECT COALESCE(public.staff_access_level(p_module, p_uid) = 'manage', false); $$;

GRANT EXECUTE ON FUNCTION public.staff_module_list()                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_manager(uuid)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_access_level(text, uuid)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_can_manage(text, uuid)        TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. is_platform_admin(): Manager, or an Officer with Members = manage
--    during a request the gate marked as a Members request.
-- ════════════════════════════════════════════════════════════
-- Same name, arguments and return type as before, so every existing caller
-- (RLS policies and RPCs) keeps working. The extra branch is true only when
--   (a) the caller is acting as themselves, AND
--   (b) the request gate set sagana.members_manage = 'on' for THIS transaction
--       (it does so only for requests that target a Members table / RPC), AND
--   (c) the caller really holds Members = manage.
-- Policies written as "is_platform_admin() AND NOT <is an Officer>" are
-- unaffected: those remain Manager-only.
CREATE OR REPLACE FUNCTION public.is_platform_admin(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id = p_uid AND role = 'admin')
      OR (
        p_uid IS NOT DISTINCT FROM auth.uid()
        AND COALESCE(current_setting('sagana.members_manage', true), '') = 'on'
        AND public.staff_access_level('members', p_uid) = 'manage'
      );
$$;
GRANT EXECUTE ON FUNCTION public.is_platform_admin(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Reading permissions
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_my_staff_permissions()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT jsonb_object_agg(m, public.staff_access_level(m))
     FROM unnest(public.staff_module_list()) AS m
     WHERE public.is_staff()),
    '{}'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.get_officer_permissions(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  RETURN COALESCE(
    (SELECT jsonb_object_agg(m, public.staff_access_level(m, p_user_id))
     FROM unnest(public.staff_module_list()) AS m),
    '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_staff_permissions()        TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_officer_permissions(uuid)     TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Writing permissions
-- ════════════════════════════════════════════════════════════
-- Applies a (possibly partial) permission map to one Officer. A key that is
-- missing keeps the Officer's current level; an Officer with no row yet starts at
-- p_new_default (create_officer_account passes 'manage'). No ceiling is applied
-- to who may grant what: Members = manage is the permission to assign access.
CREATE OR REPLACE FUNCTION public._apply_officer_permissions(
  p_user_id uuid, p_perms jsonb, p_new_default text DEFAULT 'view'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key   text;
  v_mod   text;
  v_new   text;
  v_cur   text;
BEGIN
  IF p_new_default NOT IN ('view', 'manage') THEN
    RAISE EXCEPTION 'Invalid default access level.';
  END IF;
  IF p_perms IS NULL THEN
    p_perms := '{}'::jsonb;
  END IF;
  IF jsonb_typeof(p_perms) <> 'object' THEN
    RAISE EXCEPTION 'Permissions must be an object of module: level pairs.';
  END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_perms) LOOP
    IF NOT (v_key = ANY (public.staff_module_list())) THEN
      RAISE EXCEPTION 'Unknown module: %', v_key;
    END IF;
    IF (p_perms ->> v_key) NOT IN ('view', 'manage') THEN
      RAISE EXCEPTION 'Access for % must be view or manage.', v_key;
    END IF;
  END LOOP;

  FOREACH v_mod IN ARRAY public.staff_module_list() LOOP
    v_cur := COALESCE(
      (SELECT access_level FROM officer_permissions
       WHERE user_id = p_user_id AND module = v_mod), p_new_default);
    v_new := COALESCE(p_perms ->> v_mod, v_cur);


    INSERT INTO officer_permissions (user_id, module, access_level, updated_by, updated_at)
    VALUES (p_user_id, v_mod, v_new, auth.uid(), NOW())
    ON CONFLICT (user_id, module) DO UPDATE
      SET access_level = EXCLUDED.access_level,
          updated_by   = EXCLUDED.updated_by,
          updated_at   = EXCLUDED.updated_at
      WHERE officer_permissions.access_level IS DISTINCT FROM EXCLUDED.access_level;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public._apply_officer_permissions(uuid, jsonb, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_officer_permissions(p_user_id uuid, p_permissions jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  -- A Manager, or an Officer who manages Members. (The request gate enforces
  -- the same rule first; this keeps the function safe if called any other way.)
  IF NOT public.is_manager() AND public.staff_access_level('members') IS DISTINCT FROM 'manage' THEN
    RAISE EXCEPTION 'Your Officer account has view-only access to Members.';
  END IF;
  IF p_user_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM user_roles WHERE user_id = p_user_id AND role = 'officer') THEN
    RAISE EXCEPTION 'Permissions can only be set for an Officer account.';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot change your own access.';
  END IF;

  PERFORM public._apply_officer_permissions(p_user_id, p_permissions);

  RETURN public.get_officer_permissions(p_user_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.set_officer_permissions(uuid, jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_officer_permissions(uuid, jsonb) FROM anon;


-- ════════════════════════════════════════════════════════════
-- 7. Role changes: not through the app, for anyone
-- ════════════════════════════════════════════════════════════
-- No screen changes an account's role, and no one signed in (Manager or
-- Officer) may. A change made from the SQL editor or with the service key (no
-- signed-in user) is still allowed. This is the ONLY restriction placed on what
-- an Officer can do to other accounts; suspending, resetting passwords and
-- assigning access are not restricted here.
CREATE OR REPLACE FUNCTION public.user_roles_no_role_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'An account''s role cannot be changed from the app.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_roles_staff_guard ON public.user_roles;      -- earlier draft, if present
DROP FUNCTION IF EXISTS public.user_roles_staff_guard();
DROP TRIGGER IF EXISTS trg_user_roles_no_role_change ON public.user_roles;
CREATE TRIGGER trg_user_roles_no_role_change
  BEFORE UPDATE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.user_roles_no_role_change();


-- ════════════════════════════════════════════════════════════
-- 10. Read access for the Members tab (additive; nothing dropped)
-- ════════════════════════════════════════════════════════════
-- user_roles, user_information, farmer_profiles, buyer_profiles, buyer_addresses,
-- password_reset_requests and member_contributions are already readable by
-- staff. These are the remaining tables the Members screens read.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'member_capital_shares', 'capital_contribution_events',
    'member_identifiers', 'member_identifier_history', 'officer_profiles'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': staff reads', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT USING (public.is_staff())',
        t || ': staff reads', t);
    END IF;
  END LOOP;
END
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run each by itself)
-- ============================================================
-- 1) The table exists and is empty (no backfill):
--    SELECT count(*) FROM officer_permissions;                       -- 0
-- 2) is_platform_admin knows about the Members marker:
--    SELECT prosrc LIKE '%sagana.members_manage%' FROM pg_proc
--    WHERE proname = 'is_platform_admin';                            -- true
-- 3) No write policy on officer_permissions:
--    SELECT policyname, cmd FROM pg_policies WHERE tablename = 'officer_permissions';  -- SELECT only
-- 4) The role-change rule:
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_user_roles_no_role_change';     -- 1 row
-- 5) Members history is still Manager-only (this must NOT list a staff policy):
--    SELECT policyname FROM pg_policies WHERE tablename = 'member_status_events';
-- ============================================================
