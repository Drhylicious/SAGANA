-- ============================================================
-- supabase_schema_restrictions_02_apply_lift_history.sql
--
-- FEATURE RESTRICTIONS (2 of 4). Run after script 01.
--
--   restrict_member(user, features[], reason, ends_at)  apply, one row per feature
--   lift_member_restriction(id)                         remove one early
--   get_member_discipline_history(user)                 restrictions + suspensions for the Members screens
--
-- WHO MAY USE THEM: the Manager, and an Officer with Manage access to Members, by the
-- same rule as suspend_member (is_platform_admin() through the Officer permission gate).
-- Only an ACTIVE Farmer Member can be restricted.
--
-- ALSO CHANGED (from the live definitions):
--   suspend_member                 refuses a Manager or Officer account
--   reactivate_member              also closes the member's restrictions (history kept)
--   reactivate_expired_suspensions also marks restrictions whose end date passed as ended
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.restrict_member(
  p_user_id  uuid,
  p_features text[],
  p_reason   text,
  p_ends_at  timestamptz DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status     text;
  v_reason     text := btrim(coalesce(p_reason, ''));
  v_features   text[];
  v_feature    text;
  v_labels     text[] := ARRAY[]::text[];
  v_actor_name text;
  v_actor_role text;
  v_until      text;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'A restriction reason is required';
  END IF;
  IF p_features IS NULL OR cardinality(p_features) = 0 THEN
    RAISE EXCEPTION 'Choose at least one feature to restrict';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at <= now() THEN
    RAISE EXCEPTION 'The end date must be in the future';
  END IF;

  SELECT r.status INTO v_status
  FROM user_roles r WHERE r.user_id = p_user_id AND r.role = 'farmer' FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Only a Farmer Member can be restricted';
  END IF;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'Only an active member can be restricted (current: %)', v_status;
  END IF;

  SELECT array_agg(DISTINCT f) INTO v_features FROM unnest(p_features) AS f;
  FOREACH v_feature IN ARRAY v_features LOOP
    IF v_feature NOT IN ('marketplace_listing', 'coop_offer', 'informal_sale', 'ginger_da_amad', 'checkout', 'loan_request', 'program_join') THEN
      RAISE EXCEPTION 'Unknown feature: %', v_feature;
    END IF;
  END LOOP;

  SELECT ui.full_name INTO v_actor_name FROM user_information ui WHERE ui.user_id = auth.uid();
  SELECT r.role INTO v_actor_role FROM user_roles r WHERE r.user_id = auth.uid();

  FOREACH v_feature IN ARRAY v_features LOOP
    INSERT INTO member_restrictions (member_id, feature, reason, ends_at, applied_by, applied_by_name, applied_by_role)
    VALUES (p_user_id, v_feature, v_reason, p_ends_at, auth.uid(), v_actor_name, v_actor_role);
    v_labels := v_labels || public.restriction_feature_label(v_feature);
  END LOOP;

  v_until := CASE WHEN p_ends_at IS NULL THEN ''
                  ELSE ' Until ' || to_char(p_ends_at AT TIME ZONE 'Asia/Manila', 'FMMon FMDD, YYYY') || '.' END;
  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Feature Restricted',
          array_to_string(v_labels, '; ') || ' is restricted: ' || rtrim(v_reason, '. ') || '.' || v_until,
          false, '/farmer/profile/restrictions');

  RETURN cardinality(v_features);
END;
$function$;

CREATE OR REPLACE FUNCTION public.lift_member_restriction(p_restriction_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r member_restrictions%ROWTYPE;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO r FROM member_restrictions WHERE id = p_restriction_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Restriction not found';
  END IF;
  IF r.status <> 'active' THEN
    RAISE EXCEPTION 'This restriction is already closed';
  END IF;

  -- One whose date already passed simply ended on its own.
  IF r.ends_at IS NOT NULL AND r.ends_at <= now() THEN
    UPDATE member_restrictions
    SET status = 'ended', closed_at = now(), close_reason = 'Period ended (automatic)'
    WHERE id = r.id;
    RETURN;
  END IF;

  UPDATE member_restrictions
  SET status = 'lifted',
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_name = (SELECT ui.full_name FROM user_information ui WHERE ui.user_id = auth.uid()),
      close_reason = 'Lifted by staff'
  WHERE id = r.id;

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (r.member_id, 'member_updated', 'Restriction Lifted',
          public.restriction_feature_label(r.feature) || ' is available again.',
          false, '/farmer/profile/restrictions');
END;
$function$;

-- Restrictions and suspensions of one member, newest first, for Member Details.
-- (member_status_events is readable by the Manager only, so this is how an Officer
-- sees the same history.)
CREATE OR REPLACE FUNCTION public.get_member_discipline_history(p_user_id uuid)
RETURNS TABLE (
  kind          text,
  feature       text,
  reason        text,
  status        text,
  started_at    timestamptz,
  ends_at       timestamptz,
  ended_at      timestamptz,
  close_reason  text,
  actor_name    text,
  actor_role    text,
  ended_by_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_staff() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT * FROM (
    SELECT 'restriction'::text AS kind,
           r.feature AS feature,
           r.reason AS reason,
           (CASE WHEN r.status = 'active' AND r.ends_at IS NOT NULL AND r.ends_at <= now()
                 THEN 'ended' ELSE r.status END)::text AS status,
           r.starts_at AS started_at,
           r.ends_at AS ends_at,
           r.closed_at AS ended_at,
           r.close_reason AS close_reason,
           r.applied_by_name AS actor_name,
           r.applied_by_role AS actor_role,
           r.closed_by_name AS ended_by_name
    FROM member_restrictions r
    WHERE r.member_id = p_user_id
    UNION ALL
    SELECT (CASE WHEN e.to_status = 'suspended' THEN 'suspension' ELSE 'reactivation' END)::text,
           NULL::text,
           e.reason,
           e.to_status,
           e.created_at,
           NULL::timestamptz,
           NULL::timestamptz,
           NULL::text,
           e.actor_name,
           e.actor_role,
           NULL::text
    FROM member_status_events e
    WHERE e.member_id = p_user_id
      AND (e.to_status = 'suspended' OR e.from_status = 'suspended')
  ) h
  ORDER BY h.started_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.restrict_member(uuid, text[], text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lift_member_restriction(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_member_discipline_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restrict_member(uuid, text[], text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lift_member_restriction(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_discipline_history(uuid) TO authenticated;

-- An Officer needs Manage access to Members to apply or lift (view-only Officers
-- are stopped by the permission gate, like suspend_member).
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc',   'restrict_member',         'members'),
  ('rpc',   'lift_member_restriction', 'members'),
  ('table', 'member_restrictions',     'members')
ON CONFLICT (kind, name) DO NOTHING;

-- Every apply and lift by staff goes into the activity log, like other staff actions.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.member_restrictions;
CREATE TRIGGER trg_audit_staff_change
  AFTER INSERT OR UPDATE ON public.member_restrictions
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('members');

-- ── Suspension changes (live definitions, one small addition each) ──────────
CREATE OR REPLACE FUNCTION public.suspend_member(p_user_id uuid, p_reason text, p_suspended_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT (is_platform_admin() OR (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()) AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role = 'buyer'))) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  -- Staff accounts are never suspended.
  IF EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role IN ('admin', 'officer')) THEN
    RAISE EXCEPTION 'Manager and Officer accounts cannot be suspended';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A suspension reason is required';
  END IF;
  IF p_suspended_until IS NOT NULL AND p_suspended_until <= now() THEN
    RAISE EXCEPTION 'The reactivation date must be in the future';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'suspended',
      suspension_reason = trim(p_reason),
      suspended_until = p_suspended_until
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'suspended', trim(p_reason), auth.uid());
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT (is_platform_admin() OR (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()) AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role = 'buyer'))) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  -- Only a suspended member can be reactivated. Any other status must go
  -- through its own flow (approve_member for pending applicants).
  IF v_status <> 'suspended' THEN
    RAISE EXCEPTION 'Only a suspended member can be reactivated (current: %)', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'active',
      suspension_reason = NULL,
      suspended_until = NULL
  WHERE user_id = p_user_id;

  -- The restrictions that were in force are closed (kept in the history).
  UPDATE member_restrictions
  SET status = 'closed',
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_name = (SELECT ui.full_name FROM user_information ui WHERE ui.user_id = auth.uid()),
      close_reason = 'Member reactivated'
  WHERE member_id = p_user_id AND status = 'active';

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by Manager', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false, '/farmer/profile');
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reactivate_expired_suspensions()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT user_id
    FROM user_roles
    WHERE status = 'suspended'
      AND suspended_until IS NOT NULL
      AND suspended_until <= now()
    FOR UPDATE
  LOOP
    UPDATE user_roles
    SET status = 'active',
        suspension_reason = NULL,
        suspended_until = NULL
    WHERE user_id = v_row.user_id;

    INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
    VALUES (v_row.user_id, 'suspended', 'active', 'Suspension period ended (automatic)', NULL);

    v_count := v_count + 1;
  END LOOP;

  -- Restrictions whose end date has passed are marked ended (they already stopped
  -- applying the moment the date passed; this only completes the history).
  UPDATE member_restrictions
  SET status = 'ended',
      closed_at = now(),
      close_reason = 'Period ended (automatic)'
  WHERE status = 'active' AND ends_at IS NOT NULL AND ends_at <= now();

  RETURN v_count;
END;
$function$
;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECK (read-only). Run on its own. Every row PASS.
-- ============================================================
SELECT 'apply / lift / history functions exist' AS check_name,
       CASE WHEN (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                  AND proname IN ('restrict_member', 'lift_member_restriction', 'get_member_discipline_history')) = 3
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'Officer gate knows the new functions',
       CASE WHEN (SELECT count(*) FROM staff_permission_targets
                  WHERE name IN ('restrict_member', 'lift_member_restriction', 'member_restrictions')) = 3
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'staff actions are logged',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_staff_change'
                         AND tgrelid = 'public.member_restrictions'::regclass)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'suspend_member refuses staff accounts',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'suspend_member' AND pronamespace = 'public'::regnamespace)
                 LIKE '%cannot be suspended%' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'reactivating closes restrictions',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'reactivate_member' AND pronamespace = 'public'::regnamespace)
                 LIKE '%member_restrictions%' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'the daily job ends expired restrictions',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'reactivate_expired_suspensions' AND pronamespace = 'public'::regnamespace)
                 LIKE '%member_restrictions%' THEN 'PASS' ELSE 'FAIL' END;
