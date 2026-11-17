-- ============================================================
-- supabase_schema_password_previous_01.sql
--
-- USERNAME-BASED PASSWORD RESET: do not allow the old password again.
--
-- When the Manager resets a password (Request Password Assistance), the person's
-- real password is overwritten by a temporary one, so after that nothing remembers
-- it. The server already refuses the temporary password itself as the new one. This
-- script also keeps the password that was replaced (as the same bcrypt hash the
-- sign-in table already holds, never the password itself) until the person has set
-- their new one, so the new password can be refused if it is the old one.
--
--   1. password_reset_previous: one hash per person, no access for the app roles.
--   2. admin_reset_user_password(): the LIVE function, plus keeping the replaced hash
--      (the first one only, so a second reset cannot replace it with a temporary one).
--   3. new_password_matches_previous(text): true when the typed password is that
--      old one. Answers only for the signed-in person.
--   4. clear_must_change_password(): the LIVE function, plus removing the kept hash
--      once the new password is set.
--
-- The email reset flow is not touched. Safe to re-run.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.password_reset_previous (
  user_id       uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  previous_hash text        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.password_reset_previous ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.password_reset_previous FROM PUBLIC, anon, authenticated;

-- ─── 2. admin_reset_user_password (live definition + keep the replaced hash) ────
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(p_user_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_temp_password text;
  v_charset text := 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  v_length int := 10;
  i int;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = p_user_id::uuid
  ) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  v_temp_password := '';
  FOR i IN 1..v_length LOOP
    v_temp_password := v_temp_password ||
      substr(v_charset, floor(random() * length(v_charset) + 1)::int, 1);
  END LOOP;

  -- Keep the password being replaced (its hash), but only the first time: while the
  -- person still has a temporary password, a second reset must not overwrite it.
  INSERT INTO public.password_reset_previous (user_id, previous_hash)
  SELECT id, encrypted_password
  FROM auth.users
  WHERE id = p_user_id::uuid
    AND COALESCE(encrypted_password, '') <> ''
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE auth.users
  SET encrypted_password = crypt(v_temp_password, gen_salt('bf')),
      updated_at = now()
  WHERE id = p_user_id::uuid;

  UPDATE public.user_roles
  SET must_change_password = true
  WHERE user_id = p_user_id::uuid;

  RETURN v_temp_password;
END;
$function$;

-- ─── 3. Is the typed password the one that was replaced? ─────────────────────
CREATE OR REPLACE FUNCTION public.new_password_matches_previous(p_password text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.password_reset_previous p
    WHERE p.user_id = auth.uid()
      AND p_password IS NOT NULL
      AND crypt(p_password, p.previous_hash) = p.previous_hash
  );
$function$;

REVOKE ALL ON FUNCTION public.new_password_matches_previous(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.new_password_matches_previous(text) TO authenticated;

-- ─── 4. clear_must_change_password (live definition + drop the kept hash) ────
CREATE OR REPLACE FUNCTION public.clear_must_change_password()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE user_roles
  SET must_change_password = FALSE
  WHERE user_id = auth.uid();

  DELETE FROM public.password_reset_previous WHERE user_id = auth.uid();
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only). Run on their own. Every row PASS.
-- ============================================================
SELECT 'table exists, closed to the app roles' AS check_name,
       CASE WHEN to_regclass('public.password_reset_previous') IS NOT NULL
             AND NOT has_table_privilege('authenticated', 'public.password_reset_previous', 'SELECT')
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'reset keeps the replaced hash',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'admin_reset_user_password' AND pronamespace = 'public'::regnamespace)
                 LIKE '%password_reset_previous%' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'check function exists',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'new_password_matches_previous' AND pronamespace = 'public'::regnamespace)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'clearing removes the kept hash',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'clear_must_change_password' AND pronamespace = 'public'::regnamespace)
                 LIKE '%password_reset_previous%' THEN 'PASS' ELSE 'FAIL' END;
