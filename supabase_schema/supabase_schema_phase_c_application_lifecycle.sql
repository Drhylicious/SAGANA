-- ============================================================
-- SAGANA — Phase C: Application lifecycle & 5-status model
-- (Admin Members tab enhancement — Issue 5)
--
-- Sections
--   1. user_roles.status CHECK -> add 'draft' and 'rejected'
--      (active | pending | suspended | draft | rejected).
--      'inactive' is NOT a stored value — it is DERIVED in the app
--      from user_information.last_active_at (Decision D11).
--   2. user_roles extra columns:
--        pending_acknowledgement  BOOLEAN  (Decision D7 — approval must be
--                                  acknowledged before farmer features unlock)
--        application_attempts     SMALLINT (Decision D6 — 3 total tries)
--        rejection_reason         TEXT
--        suspension_reason        TEXT
--   3. user_information.last_active_at TIMESTAMPTZ (Decision D8 — 30-day
--      derived "Inactive"; never blocks login; never-logged-in stays Active).
--   4. notifications_type_check -> add 'member_approved', 'member_rejected'
--      (Decision D25). Full value list reproduced from
--      supabase_schema_notification_type_fixes.sql.
--   5. member_status_events audit table (Decision D13).
--   6. RPCs (all SECURITY DEFINER):
--        touch_last_active()        - caller stamps their own last_active_at
--        submit_application()       - applicant: draft|rejected -> pending,
--                                     +1 attempt, cap 3, audit row
--        acknowledge_membership()   - member: clears pending_acknowledgement
--        approve_member(uuid)       - admin: pending -> active, ack gate on,
--                                     is_verified, Member ID, registry,
--                                     'member_approved' notice, audit row
--        reject_member(uuid,text)   - admin: pending -> rejected (reason
--                                     required), 'member_rejected' notice,
--                                     audit row. No farmer access granted.
--        suspend_member(uuid,text)  - admin: -> suspended (reason recorded),
--                                     'member_updated' notice, audit row
--        reactivate_member(uuid)    - admin: suspended -> active, clears
--                                     suspension_reason, audit row
--
-- The application is NOT sent when the account is created: an outsider
-- self-registration now lands in 'draft' (see AuthService.register) and
-- stays hidden from the Admin Members list until submit_application().
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. user_roles.status — widen the CHECK
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.user_roles DROP CONSTRAINT IF EXISTS user_roles_status_check;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_status_check
  CHECK (status IN ('active', 'pending', 'suspended', 'draft', 'rejected'));

-- ════════════════════════════════════════════════════════════
-- 2. user_roles — lifecycle columns
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS pending_acknowledgement BOOLEAN  NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS application_attempts    SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rejection_reason        TEXT,
  ADD COLUMN IF NOT EXISTS suspension_reason       TEXT;

COMMENT ON COLUMN public.user_roles.pending_acknowledgement IS
  'TRUE after approve_member until the member taps "Continue" on the '
  'Pending Applicant screen (acknowledge_membership). Farmer features '
  'stay gated while TRUE.';
COMMENT ON COLUMN public.user_roles.application_attempts IS
  'Number of times submit_application has been called. Capped at 3 '
  '(Decision D6).';

-- ════════════════════════════════════════════════════════════
-- 3. user_information.last_active_at
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;

COMMENT ON COLUMN public.user_information.last_active_at IS
  'Stamped on every login (touch_last_active). NULL = never logged in '
  '(still counts as Active). "Inactive" is derived in-app: status=active '
  'AND now() - last_active_at > 30 days. Never blocks login.';

-- ════════════════════════════════════════════════════════════
-- 4. notifications_type_check — add member_approved / member_rejected
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'order', 'listing', 'loan', 'price', 'sync', 'system',
    'listing_submitted', 'loan_overdue', 'member_pending',
    'member_registered', 'member_updated',
    'member_approved', 'member_rejected',
    'low_stock', 'stock_depleted',
    'crop_request', 'cooperative_offer', 'program'
  ));

-- ════════════════════════════════════════════════════════════
-- 5. member_status_events — audit trail (Decision D13)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.member_status_events (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  member_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status   TEXT        NOT NULL,
  reason      TEXT,
  actor_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mse_member_created
  ON public.member_status_events (member_id, created_at DESC);

ALTER TABLE public.member_status_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mse: member reads own" ON public.member_status_events;
CREATE POLICY "mse: member reads own"
  ON public.member_status_events FOR SELECT
  USING (auth.uid() = member_id);

DROP POLICY IF EXISTS "mse: admin manages all" ON public.member_status_events;
CREATE POLICY "mse: admin manages all"
  ON public.member_status_events FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- ════════════════════════════════════════════════════════════
-- 6. RPCs
-- ════════════════════════════════════════════════════════════

-- ─── touch_last_active ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.touch_last_active()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_information
  SET last_active_at = NOW()
  WHERE user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION public.touch_last_active() TO authenticated;

-- ─── submit_application ────────────────────────────────────────────────────
-- Applicant sends their own application. draft|rejected -> pending.
-- Returns the number of attempts USED after this call (1..3).
CREATE OR REPLACE FUNCTION public.submit_application()
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_status   TEXT;
  v_attempts SMALLINT;
BEGIN
  SELECT status, application_attempts INTO v_status, v_attempts
  FROM user_roles WHERE user_id = v_uid
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'No membership record found';
  END IF;

  IF v_status NOT IN ('draft', 'rejected') THEN
    RAISE EXCEPTION 'Application cannot be submitted from status %', v_status;
  END IF;

  IF v_attempts >= 3 THEN
    RAISE EXCEPTION 'You have used all 3 application attempts. Please visit the SP3 office.';
  END IF;

  UPDATE user_roles
  SET status = 'pending',
      application_attempts = v_attempts + 1,
      rejection_reason = NULL,
      pending_acknowledgement = false
  WHERE user_id = v_uid;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (v_uid, v_status, 'pending',
          'Application submitted (attempt ' || (v_attempts + 1) || ' of 3)', v_uid);

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (v_uid, 'member_pending', 'Application Submitted',
          'Your membership application has been sent to the SP3 Cooperative for review.',
          false);

  RETURN (v_attempts + 1)::SMALLINT;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_application() TO authenticated;

-- ─── acknowledge_membership ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.acknowledge_membership()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_roles
  SET pending_acknowledgement = false
  WHERE user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION public.acknowledge_membership() TO authenticated;

-- ─── approve_member ───────────────────────────────────────────────────────
-- Admin approves a pending applicant. Consolidates what was previously
-- several sequential client writes into one atomic function so the
-- status flip, Member ID, registry link, notification and audit row
-- either all happen or none do.
CREATE OR REPLACE FUNCTION public.approve_member(p_user_id UUID)
RETURNS TEXT                      -- the (possibly newly assigned) member_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    TEXT;
  v_full_name TEXT;
  v_member_id TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
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

  -- Member ID: keep an existing one, otherwise mint via the shared generator.
  SELECT member_id INTO v_member_id FROM farmer_profiles WHERE user_id = p_user_id;
  IF v_member_id IS NULL OR trim(v_member_id) = '' THEN
    v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);
  END IF;

  UPDATE farmer_profiles
  SET member_id = v_member_id, is_verified = true
  WHERE user_id = p_user_id;

  -- Registry link (upsert on registered_user_id).
  IF EXISTS (SELECT 1 FROM sp3_member_registry WHERE registered_user_id = p_user_id) THEN
    UPDATE sp3_member_registry
    SET is_registered = true
    WHERE registered_user_id = p_user_id;
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
GRANT EXECUTE ON FUNCTION public.approve_member(UUID) TO authenticated;

-- ─── reject_member ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_member(p_user_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A rejection reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be rejected (current: %)', v_status;
  END IF;

  -- Rejected: account stays listed, farmer access NOT granted, is_verified
  -- left untouched (it is only ever set true by approve_member).
  UPDATE user_roles
  SET status = 'rejected',
      rejection_reason = trim(p_reason),
      pending_acknowledgement = false
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'rejected', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_rejected', 'Application Not Approved',
          'Your SP3 membership application was not approved. Reason: ' || trim(p_reason)
          || ' You may review your details and resubmit.',
          false);
END;
$$;
GRANT EXECUTE ON FUNCTION public.reject_member(UUID, TEXT) TO authenticated;

-- ─── suspend_member ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.suspend_member(p_user_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A suspension reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'suspended', suspension_reason = trim(p_reason)
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'suspended', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_updated', 'Account Suspended',
          'Your SP3 account has been suspended. Reason: ' || trim(p_reason)
          || ' Please contact the SP3 Cooperative.',
          false);
END;
$$;
GRANT EXECUTE ON FUNCTION public.suspend_member(UUID, TEXT) TO authenticated;

-- ─── reactivate_member ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'active', suspension_reason = NULL
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by admin', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false);
END;
$$;
GRANT EXECUTE ON FUNCTION public.reactivate_member(UUID) TO authenticated;

-- ─── Data touch-up ────────────────────────────────────────────────────────
-- Existing self-registered outsiders currently sit in 'pending' with a
-- submitted application — leave them. There is no legacy 'draft' data to
-- migrate (the status did not exist before). No backfill needed for
-- last_active_at (NULL = Active until first login under the new build).

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Status CHECK accepts the new values:
--    SELECT conname, pg_get_constraintdef(oid)
--    FROM pg_constraint WHERE conname = 'user_roles_status_check';
--    -- IN ('active','pending','suspended','draft','rejected')
--
-- 2) New columns present:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='user_roles'
--      AND column_name IN ('pending_acknowledgement','application_attempts',
--                          'rejection_reason','suspension_reason');           -- 4 rows
--    SELECT 1 FROM information_schema.columns
--    WHERE table_name='user_information' AND column_name='last_active_at';     -- 1 row
--
-- 3) Notification types:
--    SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conname='notifications_type_check';   -- contains member_approved / member_rejected
--
-- 4) Audit table + RPCs:
--    SELECT to_regclass('public.member_status_events');   -- not null
--    SELECT proname FROM pg_proc WHERE proname IN
--      ('submit_application','approve_member','reject_member','suspend_member',
--       'reactivate_member','acknowledge_membership','touch_last_active')
--    ORDER BY proname;    -- 7 rows
--
-- 5) End-to-end (in app): register an outsider -> they land on the
--    Applicant screen in 'draft' and are ABSENT from Admin > Members.
--    Tap Submit Application -> status 'pending', now visible in Members.
--    Admin Reject with a reason -> status 'rejected', reason shows on the
--    applicant's Home + a 'member_rejected' notification in Updates; the
--    applicant is NOT a farmer. Resubmit -> 'pending' (attempt 2 of 3).
--    Admin Approve -> 'member_approved' notice; applicant sees an
--    "Approved — Continue" card; tapping it clears pending_acknowledgement
--    and opens the farmer dashboard.
-- ============================================================
