-- ============================================================
-- SAGANA — Officer permissions, script 20: ONLY THE MANAGER CHANGES AN OFFICER'S ACCESS
--
-- DECISION (yours): only the Manager may change the module access (View Only /
-- Manage) assigned to an Officer account. That belongs to the future Cooperative
-- ID Card and is not offered anywhere in the app for now.
--
-- WHAT WAS WRONG
--   set_officer_permissions() (script 01) also accepted an Officer whose Members
--   access is Manage, with no limit on what they could grant. The app screen that
--   offered it has been removed, but the database would still have accepted the
--   call.
--
-- WHAT THIS DOES
--   Replaces that one function. It is the same as before except that the caller
--   must be the Manager. Everything else is unchanged: only for an Officer account,
--   never for yourself, validated and applied by the same helper, and the change is
--   still written to the accountability log by the existing trigger.
--   Creating an Officer account (Manager only, script 08) is not touched.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo, run the CREATE OR REPLACE of set_officer_permissions from script 01.
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.set_officer_permissions(uuid,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'set_officer_permissions(uuid, jsonb) is missing.';
  END IF;
  IF to_regprocedure('public._apply_officer_permissions(uuid,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION '_apply_officer_permissions(uuid, jsonb, text) is missing.';
  END IF;
  IF to_regprocedure('public.get_officer_permissions(uuid)') IS NULL THEN
    RAISE EXCEPTION 'get_officer_permissions(uuid) is missing.';
  END IF;
  IF to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_manager(uuid) is missing.';
  END IF;
END $$;

BEGIN;

CREATE OR REPLACE FUNCTION public.set_officer_permissions(p_user_id uuid, p_permissions jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Only the Manager can change an Officer''s access.';
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

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT prosrc LIKE '%Only the Manager can change an Officer%' AS manager_only
--   FROM pg_proc WHERE proname = 'set_officer_permissions';          -- true
-- ─────────────────────────────────────────────────────────────────────────
