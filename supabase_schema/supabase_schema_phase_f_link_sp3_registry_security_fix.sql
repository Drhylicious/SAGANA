-- ============================================================
-- SAGANA — Security fix: link_sp3_registry() ownership check
-- (Addendum to supabase_schema_phase_f_admin_members_fixes.sql —
-- run this standalone; it does not touch anything else from that file
-- and is safe even though phase_f has already been applied.)
--
-- Vulnerability
--   link_sp3_registry(p_registry_id) previously only checked that the
--   caller was authenticated and that the target row was unclaimed
--   (registered_user_id IS NULL) or already theirs. It never verified
--   that the registry row actually belongs to the caller. Because the
--   function is GRANT EXECUTE'd to `authenticated` (not just used
--   internally during registration), ANY signed-in user — an existing
--   Farmer, Buyer, or Officer, not only someone mid-registration —
--   could call it directly via the client SDK with an arbitrary
--   p_registry_id and hijack another person's unclaimed SP3 registry
--   row (setting registered_user_id to their own uid), permanently
--   blocking the real match from ever linking it.
--
-- Fix
--   Require the target row's normalized_name to equal the caller's own
--   full name, normalized the exact same way check_sp3_registry()
--   already does it (lower(trim(...)) via the generated
--   normalized_name column) — restoring the "name-verified self link"
--   guarantee the app's UI flow always assumed but the RPC never
--   enforced. Legitimate self-registration is unaffected: AuthService
--   .register() only ever calls this right after checkSp3Registry(name)
--   found a name match, so the caller's own name always matches the
--   row they're linking.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.link_sp3_registry(p_registry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT full_name INTO v_caller_name
  FROM user_information
  WHERE user_id = auth.uid();

  IF v_caller_name IS NULL THEN
    RAISE EXCEPTION 'Account has no name on record';
  END IF;

  -- Only links the row to the CALLER's own account, only when the row
  -- isn't already linked to someone else, AND only when the row's own
  -- registered name matches the caller's own name (same normalization
  -- check_sp3_registry uses) — closes the arbitrary-claim hole above.
  UPDATE sp3_member_registry
  SET is_registered = true,
      registered_user_id = auth.uid()
  WHERE id = p_registry_id
    AND (registered_user_id IS NULL OR registered_user_id = auth.uid())
    AND normalized_name = lower(trim(v_caller_name));
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_sp3_registry(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.link_sp3_registry(uuid) FROM anon;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Confirm the fix is live:
--    SELECT prosrc FROM pg_proc WHERE proname = 'link_sp3_registry';
--    -- body should now reference "normalized_name = lower(trim(v_caller_name))"
--
-- 2) Negative test (should now fail silently — 0 rows updated, no
--    exception, matching the original "not my row" no-op behavior):
--    as any authenticated non-matching user, call
--      select link_sp3_registry('<some other person's unclaimed registry id>');
--    then confirm that row is still is_registered = false.
--
-- 3) Positive test — unaffected: a NEW registration whose full name
--    matches an unclaimed registry row should still link normally
--    (see the "Self-registration registry link" test in
--    supabase_schema_phase_f_admin_members_fixes.sql).
--
-- This patch does not affect the sp3-0001/0002/0003 backfill — that
-- backfill is a direct admin-run UPDATE on sp3_member_registry, not a
-- call to this RPC, so it is unaffected either way. Once this patch is
-- applied, you may proceed with the backfill UPDATE you already
-- previewed.
-- ============================================================
