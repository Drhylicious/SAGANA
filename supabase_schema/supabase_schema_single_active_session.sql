-- ============================================================================
-- SAGANA — Single Active Device Session (All Roles)
--
-- Implements Item 3 across Manager (admin), Officer, Farmer, and Buyer:
--   1. public.user_active_sessions stores the single active Supabase Auth
--      session_id + human-readable device_name per user, with Realtime enabled.
--   2. claim_active_session(p_device_name, p_silent) claims the caller's JWT
--      session_id as the sole active session. When replacing a different active
--      session (and not p_silent), logs the sign-in with device name & time
--      into the role's Recent Activity table:
--        - farmer       -> farmer_profile_activity
--        - buyer        -> buyer_profile_activity
--        - admin/officer -> admin_activity_log (source='app', module='profile')
--   3. get_active_session_status() checks whether the caller's JWT session_id
--      is still the active session (and returns the new device name if not).
--   4. release_active_session() removes the row ONLY if it still belongs to
--      the caller's own session_id (used on voluntary logout).
--   5. Chains session enforcement into public.staff_permission_gate()
--      (pgrst.db_pre_request) BEFORE the Officer-only check, so a replaced
--      session on Device A is immediately rejected server-side across ALL 4
--      roles (even before the 1-hour JWT expires), while failing open when no
--      session row exists and keeping all Officer permission gating intact.
--
-- NOTE: user_active_sessions intentionally has NO audit_staff_change trigger
-- (it is per-user session state, not cooperative staff accountability).
--
-- NOT APPLIED AUTOMATICALLY. Run manually in the Supabase SQL Editor.
-- Safe to re-run (transactional, idempotent).
-- ============================================================================

BEGIN;

-- ─── 1. Active session registry table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_active_sessions (
  user_id      UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id   UUID        NOT NULL,
  device_name  TEXT        NOT NULL DEFAULT 'Another device',
  signed_in_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_active_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_active_sessions: owner reads own" ON public.user_active_sessions;
CREATE POLICY "user_active_sessions: owner reads own"
  ON public.user_active_sessions
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON public.user_active_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.user_active_sessions TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'user_active_sessions'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_active_sessions;
  END IF;
END;
$$;

-- ─── 2. Claim active session & record cross-device activity ────────────────
CREATE OR REPLACE FUNCTION public.claim_active_session(
  p_device_name TEXT    DEFAULT NULL,
  p_silent      BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        UUID := auth.uid();
  v_sid_text   TEXT := NULLIF(btrim(COALESCE(auth.jwt()->>'session_id', '')), '');
  v_sid        UUID;
  v_device     TEXT;
  v_prev       public.user_active_sessions%ROWTYPE;
  v_replaced   BOOLEAN := FALSE;
  v_role       TEXT;
  v_desc       TEXT;
BEGIN
  IF v_uid IS NULL OR v_sid_text IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_sid := v_sid_text::uuid;
  v_device := COALESCE(NULLIF(left(btrim(COALESCE(p_device_name, '')), 120), ''), 'Another device');

  SELECT * INTO v_prev
  FROM public.user_active_sessions
  WHERE user_id = v_uid
  FOR UPDATE;

  v_replaced := FOUND AND v_prev.session_id IS DISTINCT FROM v_sid;

  INSERT INTO public.user_active_sessions (user_id, session_id, device_name, signed_in_at, updated_at)
  VALUES (v_uid, v_sid, v_device, NOW(), NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET session_id   = EXCLUDED.session_id,
        device_name  = EXCLUDED.device_name,
        signed_in_at = CASE
                         WHEN public.user_active_sessions.session_id IS DISTINCT FROM EXCLUDED.session_id
                         THEN NOW()
                         ELSE public.user_active_sessions.signed_in_at
                       END,
        updated_at   = NOW();

  IF v_replaced AND NOT COALESCE(p_silent, FALSE) THEN
    SELECT role INTO v_role FROM public.user_roles WHERE user_id = v_uid LIMIT 1;
    v_desc := 'Signed in on ' || v_device || ' (previous device signed out)';

    IF v_role = 'farmer' THEN
      INSERT INTO public.farmer_profile_activity
        (farmer_id, description, created_at)
      VALUES
        (v_uid, v_desc, NOW());
    ELSIF v_role = 'buyer' THEN
      INSERT INTO public.buyer_profile_activity
        (buyer_id, description, created_at)
      VALUES
        (v_uid, v_desc, NOW());
    ELSIF v_role IN ('admin', 'officer') THEN
      INSERT INTO public.admin_activity_log
        (admin_id, module, action_type, description, source, created_at)
      VALUES
        (v_uid, 'profile', 'device_login', v_desc, 'app', NOW());
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'session_id', v_sid,
    'replaced', v_replaced,
    'previous_device', v_prev.device_name
  );
END;
$$;
REVOKE ALL ON FUNCTION public.claim_active_session(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_active_session(TEXT, BOOLEAN) TO authenticated;

-- ─── 3. Active session status check ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_active_session_status()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_sid_text TEXT := NULLIF(btrim(COALESCE(auth.jwt()->>'session_id', '')), '');
  v_sid      UUID;
  v_row      public.user_active_sessions%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR v_sid_text IS NULL THEN
    RETURN jsonb_build_object('active', TRUE);
  END IF;

  v_sid := v_sid_text::uuid;
  SELECT * INTO v_row FROM public.user_active_sessions WHERE user_id = v_uid;

  IF NOT FOUND OR v_row.session_id = v_sid THEN
    RETURN jsonb_build_object(
      'active', TRUE,
      'device_name', v_row.device_name,
      'signed_in_at', v_row.signed_in_at
    );
  END IF;

  RETURN jsonb_build_object(
    'active', FALSE,
    'device_name', v_row.device_name,
    'signed_in_at', v_row.signed_in_at
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_active_session_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_session_status() TO authenticated;

-- ─── 4. Release own session on voluntary sign-out ──────────────────────────
CREATE OR REPLACE FUNCTION public.release_active_session()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_sid_text TEXT := NULLIF(btrim(COALESCE(auth.jwt()->>'session_id', '')), '');
BEGIN
  IF v_uid IS NULL OR v_sid_text IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM public.user_active_sessions
   WHERE user_id = v_uid
     AND session_id = v_sid_text::uuid;
END;
$$;
REVOKE ALL ON FUNCTION public.release_active_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_active_session() TO authenticated;

-- ─── 5. Chain single-session gate into pgrst.db_pre_request ────────────────
-- Preserves all Officer permission enforcement from officer_permissions_02.
CREATE OR REPLACE FUNCTION public.staff_permission_gate()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        UUID;
  v_method     TEXT;
  v_path       TEXT;
  v_kind       TEXT;
  v_name       TEXT;
  v_module     TEXT;
  v_role       TEXT;
  v_sid_text   TEXT;
  v_jwt_sid    UUID;
  v_active_sid UUID;
  v_device     TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN;                                   -- anonymous / service role
  END IF;

  v_method := upper(COALESCE(current_setting('request.method', true), ''));
  v_path := COALESCE(current_setting('request.path', true), '');
  IF v_path ~ '/rpc/[A-Za-z0-9_]+' THEN
    v_kind := 'rpc';
    v_name := substring(v_path FROM '/rpc/([A-Za-z0-9_]+)');
  ELSE
    v_kind := 'table';
    v_name := substring(v_path FROM '([A-Za-z0-9_]+)/?$');
  END IF;

  -- Single active device session check (all roles: admin, officer, farmer, buyer).
  v_sid_text := NULLIF(btrim(COALESCE(auth.jwt()->>'session_id', '')), '');
  IF v_sid_text IS NOT NULL THEN
    IF NOT (
         (v_kind = 'rpc' AND v_name IN (
           'claim_active_session',
           'get_active_session_status',
           'release_active_session',
           'unregister_push_token',
           'register_account',
           'cancel_failed_registration',
           'ping'
         ))
      OR (v_kind = 'table' AND v_method IN ('GET', 'HEAD', 'OPTIONS')
          AND v_name IN ('user_roles', 'user_active_sessions'))
    ) THEN
      v_jwt_sid := v_sid_text::uuid;
      SELECT session_id, device_name
        INTO v_active_sid, v_device
      FROM public.user_active_sessions
      WHERE user_id = v_uid;

      IF FOUND AND v_active_sid IS DISTINCT FROM v_jwt_sid THEN
        RAISE EXCEPTION 'SESSION_REPLACED: Your account was signed in on another device (%).',
          COALESCE(v_device, 'another device')
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  -- Only Officers are gated by module permissions. One indexed lookup for everyone else.
  SELECT role INTO v_role FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'officer' THEN
    RETURN;
  END IF;

  IF v_method IN ('GET', 'HEAD', 'OPTIONS') THEN
    RETURN;                                   -- View Only still reads everything
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
