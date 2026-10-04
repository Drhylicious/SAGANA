-- ============================================================
-- SAGANA — Phase H: Cooperative membership management
--
-- Closes three gaps found while investigating "how are Member ID /
-- Share Value / Initial Contribution applied to a Farmer-Member":
--
--   1. Self-registered official SP3 members (the registry-match path
--      in AuthService.register()) called generate_member_id() as a
--      SEPARATE RPC round-trip, then did a SEPARATE farmer_profiles
--      insert. The advisory lock inside generate_member_id() is
--      released the instant that RPC returns, so it does not actually
--      cover the later insert — unlike create_farmer_account()/
--      approve_member(), which do both inside one transaction. Low
--      probability, but a real race (guarded only by the member_id
--      UNIQUE constraint failing the whole registration, not silently
--      duplicating).
--
--   2. That same self-registration path never created a
--      member_capital_shares row at all — nothing in register() ever
--      inserted one, and no DB trigger does either. create_farmer_
--      account() and approve_member() both eagerly create this row at
--      ₱0; self-registration silently skipped it. Doesn't crash
--      anything today (fetchCapitalSummary() defaults to a synthetic
--      ₱0 row when missing; issue_loan() COALESCEs to 0), but the real
--      row was never actually initialized.
--
--   3. No Admin-side way exists to fix either of the above after the
--      fact, and some existing farmer_profiles.member_id values predate
--      generate_member_id() entirely (an older, username-shaped
--      numbering scheme, e.g. "SP3-0001" instead of "SP3-2026-001") —
--      no backfill was ever run when that generator shipped.
--
-- Patronage safety: every patronage/contribution table this touches
-- (member_capital_shares, capital_contribution_events) is only ever
-- written through an INSERT into the capital_contribution_events
-- ledger (recompute_member_capital() trigger derives the running
-- total from there) — nothing here does a direct UPDATE of
-- total_contribution, and farmer_id/user_id (not the text member_id)
-- remains the only join key anywhere in patronage code. See the
-- investigation notes in this session's plan for the full trace.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. finalize_official_membership — atomic self-registration finish
-- ════════════════════════════════════════════════════════════
-- Called once by AuthService.register(), immediately after the caller's
-- own farmer_profiles row has been inserted WITHOUT a member_id (NULL).
-- Self-scoped via auth.uid(), exactly like link_sp3_registry() — a
-- session can only ever finalize its own account, never another's.

CREATE OR REPLACE FUNCTION public.finalize_official_membership(p_registry_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller      UUID := auth.uid();
  v_caller_name TEXT;
  v_member_id   TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT full_name INTO v_caller_name FROM user_information WHERE user_id = v_caller;
  IF v_caller_name IS NULL THEN
    RAISE EXCEPTION 'Account has no name on record';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM farmer_profiles WHERE user_id = v_caller) THEN
    RAISE EXCEPTION 'Farmer profile not found for caller';
  END IF;

  -- Member ID: generated and assigned inside this same transaction, so
  -- the advisory lock generate_member_id() takes is held until this
  -- function commits — closes the race the two-round-trip version had.
  v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);

  UPDATE farmer_profiles
  SET member_id = v_member_id
  WHERE user_id = v_caller;

  -- Capital-shares row, eager creation — parity with create_farmer_
  -- account()/approve_member(). Starts at ₱0; loan-ineligible until a
  -- payment is recorded, but the row now always exists.
  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (v_caller, 2000.00, 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  -- Registry link — identical ownership/name-matched guard as
  -- link_sp3_registry() (supabase_schema_phase_f_link_sp3_registry_
  -- security_fix.sql): only links the caller's own account, only when
  -- the row isn't already claimed by someone else, only when the row's
  -- registered name matches the caller's own name.
  UPDATE sp3_member_registry
  SET is_registered = true,
      registered_user_id = v_caller
  WHERE id = p_registry_id
    AND (registered_user_id IS NULL OR registered_user_id = v_caller)
    AND normalized_name = lower(trim(v_caller_name));

  RETURN v_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_official_membership(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finalize_official_membership(uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 2. admin_assign_member_id — the only way to (re)assign a Member ID
--    from the Admin side; always system-generated, never free text.
-- ════════════════════════════════════════════════════════════
-- No-ops (returns the current value unchanged) if it already matches
-- the proper SP3-<year>-<seq> shape, so re-clicking "Fix Member ID" on
-- an already-correct record can never waste a sequence number.

CREATE OR REPLACE FUNCTION public.admin_assign_member_id(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current TEXT;
  v_new     TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT member_id INTO v_current
  FROM farmer_profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Farmer profile not found';
  END IF;

  IF v_current IS NOT NULL AND v_current ~ '^SP3-\d{4}-\d{3}$' THEN
    RETURN v_current;
  END IF;

  v_new := generate_member_id(EXTRACT(YEAR FROM now())::INT);

  UPDATE farmer_profiles
  SET member_id = v_new
  WHERE user_id = p_user_id;

  RETURN v_new;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_assign_member_id(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_assign_member_id(uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 3. One-time backfill — existing records only, safe to run once
-- ════════════════════════════════════════════════════════════

-- 3a. Every ACTIVE farmer missing a member_capital_shares row gets one
--     at ₱0 — identical pattern to the Phase B backfill. No monetary
--     value changes for anyone who already has a row.
INSERT INTO public.member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
SELECT fp.user_id, 2000.00, 0
FROM public.farmer_profiles fp
JOIN public.user_roles ur ON ur.user_id = fp.user_id AND ur.status = 'active'
LEFT JOIN public.member_capital_shares mcs ON mcs.farmer_id = fp.user_id
WHERE mcs.id IS NULL;

-- 3b. Every active + verified farmer whose member_id is NULL or predates
--     the SP3-<year>-<seq> scheme gets reassigned one now, oldest join
--     date first so numbering stays chronologically meaningful, using
--     each farmer's OWN join year (not a blanket current-year stamp).
DO $$
DECLARE
  r RECORD;
  v_new TEXT;
BEGIN
  FOR r IN
    SELECT fp.user_id, EXTRACT(YEAR FROM ur.created_at)::INT AS join_year
    FROM public.farmer_profiles fp
    JOIN public.user_roles ur ON ur.user_id = fp.user_id
      AND ur.status = 'active'
    WHERE fp.is_verified = true
      AND (fp.member_id IS NULL OR fp.member_id !~ '^SP3-\d{4}-\d{3}$')
    ORDER BY ur.created_at ASC
  LOOP
    v_new := generate_member_id(r.join_year);
    UPDATE public.farmer_profiles
    SET member_id = v_new
    WHERE user_id = r.user_id;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run manually)
-- ============================================================
-- 1) No more legacy-format or missing Member IDs among active,
--    verified farmers:
--    SELECT user_id, member_id FROM farmer_profiles fp
--    JOIN user_roles ur ON ur.user_id = fp.user_id AND ur.status = 'active'
--    WHERE fp.is_verified = true
--      AND (fp.member_id IS NULL OR fp.member_id !~ '^SP3-\d{4}-\d{3}$');
--    -- expect: zero rows
--
-- 2) Every active farmer now has a capital-shares row:
--    SELECT COUNT(*) FROM farmer_profiles fp
--    JOIN user_roles ur ON ur.user_id = fp.user_id AND ur.status = 'active'
--    LEFT JOIN member_capital_shares mcs ON mcs.farmer_id = fp.user_id
--    WHERE mcs.id IS NULL;
--    -- expect: 0
--
-- 3) No existing total_contribution values changed for farmers who
--    already had a row (spot-check a known member before/after):
--    SELECT farmer_id, total_contribution FROM member_capital_shares
--    WHERE farmer_id = '<a known farmer with prior contributions>';
--    -- expect: identical to before this migration
--
-- 4) admin_assign_member_id is idempotent on an already-correct record:
--    SELECT admin_assign_member_id('<a farmer_id that already has a
--      proper SP3-<year>-<seq> id>');
--    -- expect: returns the SAME id, no new sequence number consumed
--
-- 5) finalize_official_membership is self-scoped (should fail for
--    anyone other than the account itself — cannot be tested directly
--    via SQL editor since auth.uid() there is null/service-role; verify
--    via a real self-registration matching an unclaimed registry row
--    and confirm member_id + a ₱0 member_capital_shares row both now
--    exist immediately, with no separate manual step).
-- ============================================================
