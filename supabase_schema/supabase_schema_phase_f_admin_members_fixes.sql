-- ============================================================
-- SAGANA — Phase F: Admin-Members verification bugfixes
-- (Follow-up to the Phase A–E final verification pass)
--
-- Scope of this migration
--   1. link_sp3_registry(uuid) — a SECURITY DEFINER RPC that lets a
--      newly self-registered official member mark their own
--      sp3_member_registry row as registered. Fixes a pre-existing gap:
--      AuthService.register() previously tried to UPDATE
--      sp3_member_registry directly as the new farmer's own session,
--      but RLS ("sp3_registry: admin manages all") only grants write
--      access to admins — the update matched zero rows and was
--      silently dropped (no error, no crash), so self-registered
--      official members kept is_registered = false / registered_user_id
--      = NULL indefinitely even though their account was created
--      correctly. This RPC bypasses RLS the same way
--      create_farmer_account / approve_member already do, scoped to the
--      caller's own new account only.
--   2. approve_member — re-created to also insert the approved member's
--      member_capital_shares row (ON CONFLICT DO NOTHING), matching
--      create_farmer_account's behaviour, so every active farmer has a
--      capital-shares row from the moment they become active rather than
--      only after their first recorded contribution.
--
-- Nothing else changes: this file does not touch the status/role CHECK
-- constraints, RLS policies, or any other RPC from Phases A–D2.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. link_sp3_registry — self-registration registry linking
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.link_sp3_registry(p_registry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Only ever links the row to the CALLER's own account, and only when
  -- the row isn't already linked to someone else — never lets one
  -- session claim an arbitrary registry_id on another person's behalf.
  UPDATE sp3_member_registry
  SET is_registered = true,
      registered_user_id = auth.uid()
  WHERE id = p_registry_id
    AND (registered_user_id IS NULL OR registered_user_id = auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_sp3_registry(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.link_sp3_registry(uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 2. approve_member — also create the capital-shares row
-- ════════════════════════════════════════════════════════════
-- Full body reproduced from supabase_schema_phase_d2_officer_authorization
-- .sql; the ONLY addition is the member_capital_shares insert right after
-- farmer_profiles is updated.

CREATE OR REPLACE FUNCTION public.approve_member(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    TEXT;
  v_full_name TEXT;
  v_member_id TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be approved (current: %)', v_status;
  END IF;

  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = p_user_id;

  UPDATE user_roles
  SET status = 'active',
      pending_acknowledgement = true,
      rejection_reason = NULL,
      suspension_reason = NULL
  WHERE user_id = p_user_id;

  SELECT member_id INTO v_member_id FROM farmer_profiles WHERE user_id = p_user_id;
  IF v_member_id IS NULL OR trim(v_member_id) = '' THEN
    v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);
  END IF;

  UPDATE farmer_profiles
  SET member_id = v_member_id, is_verified = true
  WHERE user_id = p_user_id;

  -- Every approved member gets a capital-shares row immediately (parity
  -- with create_farmer_account) — starts at 0, loan-ineligible until a
  -- payment is recorded, but the row always exists.
  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (p_user_id, 2000.00, 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  IF EXISTS (SELECT 1 FROM sp3_member_registry WHERE registered_user_id = p_user_id) THEN
    UPDATE sp3_member_registry SET is_registered = true WHERE registered_user_id = p_user_id;
  ELSE
    INSERT INTO sp3_member_registry (full_name, is_registered, registered_user_id)
    VALUES (COALESCE(v_full_name, 'SP3 Member'), true, p_user_id)
    ON CONFLICT (registered_user_id) DO UPDATE SET is_registered = true;
  END IF;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'active', 'Application approved', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_approved', 'Membership Approved',
          'Your SP3 cooperative membership has been approved. Open SAGANA and tap '
          || 'Continue to activate your farmer access. Your Member ID is ' || v_member_id || '.',
          false);

  RETURN v_member_id;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) New RPC present:
--    SELECT proname FROM pg_proc WHERE proname = 'link_sp3_registry';  -- 1 row
--
-- 2) approve_member now creates capital shares — approve a pending
--    applicant in-app, then:
--    SELECT * FROM member_capital_shares WHERE farmer_id = '<that user_id>';
--    -- expect one row: total_shares=0, share_value_per_unit=2000.00,
--    -- total_contribution=0
--
-- 3) Self-registration registry link (going forward) — register a NEW
--    test account whose name matches an sp3_member_registry row, then:
--    SELECT is_registered, registered_user_id FROM sp3_member_registry
--    WHERE id = '<that registry row id>';
--    -- expect is_registered = true, registered_user_id = the new user's id
--
-- 4) The 3 existing accounts (sp3-0001/0002/0003) are NOT touched by this
--    migration — see the chat report for the investigated root cause and
--    an optional, reviewable one-time backfill query.
-- ============================================================

-- ============================================================
-- TEST HELPER — 30-day Inactive-status test (run manually; NOT part of
-- the migration above, NOT wrapped in a transaction, NOT auto-applied).
-- ============================================================
-- MemberStatus.derive() treats a member as "Inactive" purely from
-- user_information.last_active_at > 30 days ago — it is never stored as
-- a status value and never blocks login. To test the Members list /
-- Member Detail screens rendering "Inactive" correctly, backdate a real
-- test member's last_active_at, then undo it when finished.
--
-- Step 1 — identify the test member (replace the name/username filter):
--   SELECT user_id, full_name, username, last_active_at
--   FROM user_information
--   WHERE full_name ILIKE '%your test member name%';
--
-- Step 2 — push last_active_at back 35 days (safely past the 30-day
-- threshold) for that one user_id:
--   UPDATE user_information
--   SET last_active_at = now() - interval '35 days'
--   WHERE user_id = '<paste the user_id from Step 1>';
--
--   Reload the Members list / that member's Detail screen — the badge
--   should now read "Inactive" even though user_roles.status is still
--   'active' underneath, and the Members-list toggle should read "Set
--   Suspended" (Inactive is treated the same as Active for the toggle).
--
-- Step 3 — restore the member afterwards so the test doesn't leave a
-- stale timestamp behind (either value works — this sets it back to now,
-- as if they just logged in):
--   UPDATE user_information
--   SET last_active_at = now()
--   WHERE user_id = '<same user_id>';
-- ============================================================

-- ============================================================
-- OPTIONAL — sp3_member_registry backfill for the 3 pre-existing
-- accounts (sp3-0001, sp3-0002, sp3-0003). NOT part of the migration
-- above, NOT auto-applied, and NOT run by this session. Root cause: the
-- old client-side AuthService.register() UPDATE was always silently
-- blocked by RLS before this fix (see link_sp3_registry above) — these
-- 3 rows were never marked registered even though the matching accounts
-- are real and active. Review the preview SELECT below yourself before
-- deciding whether to run the UPDATE; do not run it blindly.
-- ============================================================
--
-- Preview — confirm these are genuinely the same 3 people before
-- touching anything (compare full_name / phone / email by eye):
--   SELECT r.id AS registry_id, r.full_name AS registry_name,
--          r.is_registered, r.registered_user_id,
--          u.user_id AS candidate_user_id, ui.full_name AS account_name,
--          ui.username
--   FROM sp3_member_registry r
--   JOIN user_information ui ON ui.full_name = r.full_name
--   JOIN user_roles u ON u.user_id = ui.user_id
--   WHERE r.is_registered = false
--     AND r.id IN (
--       SELECT id FROM sp3_member_registry
--       WHERE full_name IN (
--         'Jhon Drhy M. Salangsang',
--         'John Harold Revilloza',
--         'Marc Louie M. Yañez'
--       )
--     );
--
-- Only after confirming the preview looks correct — link each row to its
-- matching account (run one at a time, or all three together):
--   UPDATE sp3_member_registry r
--   SET is_registered = true,
--       registered_user_id = ui.user_id
--   FROM user_information ui
--   WHERE ui.full_name = r.full_name
--     AND r.is_registered = false
--     AND r.full_name IN (
--       'Jhon Drhy M. Salangsang',
--       'John Harold Revilloza',
--       'Marc Louie M. Yañez'
--     );
--
-- Verify afterwards:
--   SELECT full_name, is_registered, registered_user_id
--   FROM sp3_member_registry
--   WHERE full_name IN (
--     'Jhon Drhy M. Salangsang', 'John Harold Revilloza', 'Marc Louie M. Yañez'
--   );
-- ============================================================
