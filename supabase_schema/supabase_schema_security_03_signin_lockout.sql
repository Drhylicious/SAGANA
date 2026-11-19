-- Sign-in lockout, found missing by the software-testing round (2026-11-19). Re-runnable.
--
-- Problem: the sign-in endpoint accepted an unlimited number of wrong passwords for an account
-- (60 in a row in the test, no slow-down), so a known username can be guessed at full speed.
-- Fix: Supabase Auth calls this function after EVERY password check of an existing account.
-- After 10 wrong passwords within 15 minutes the account is locked for the rest of that
-- window: even the correct password is refused until it ends (or a Manager clears the rows).
-- A correct password before the limit clears the count.
--
-- To turn it on in the live project (Dashboard > Authentication > Hooks > "Password Verification
-- Attempt"): choose "Postgres function" and select public.hook_password_verification_attempt.
-- (Supabase offers this hook on some plans only; if it is not available, turn on CAPTCHA under
-- Authentication > Attack Protection instead.)
-- Locally it is switched on in testing/stack/supabase/config.toml.

CREATE TABLE IF NOT EXISTS public.auth_signin_failures (
  id         bigserial PRIMARY KEY,
  user_id    uuid NOT NULL,
  failed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS auth_signin_failures_user_time ON public.auth_signin_failures (user_id, failed_at DESC);
ALTER TABLE public.auth_signin_failures ENABLE ROW LEVEL SECURITY;
-- No policy: nobody can read or write it through the API. Only the hook (below) and the service role touch it.
REVOKE ALL ON public.auth_signin_failures FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.hook_password_verification_attempt(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user    uuid := NULLIF(event->>'user_id', '')::uuid;
  v_valid   boolean := COALESCE((event->>'valid')::boolean, false);
  v_limit   constant int := 10;
  v_window  constant interval := interval '15 minutes';
  v_recent  int;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('decision', 'continue');
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.auth_signin_failures
  WHERE user_id = v_user AND failed_at > now() - v_window;

  -- Already locked: refuse, even if this password is right. (Does not add to the count.)
  IF v_recent >= v_limit THEN
    RETURN jsonb_build_object(
      'decision', 'reject',
      'message', 'Too many failed sign-in attempts. Please wait 15 minutes and try again.');
  END IF;

  IF v_valid THEN
    DELETE FROM public.auth_signin_failures WHERE user_id = v_user;
    RETURN jsonb_build_object('decision', 'continue');
  END IF;

  INSERT INTO public.auth_signin_failures (user_id) VALUES (v_user);
  DELETE FROM public.auth_signin_failures WHERE failed_at < now() - interval '1 day';
  RETURN jsonb_build_object('decision', 'continue');
END;
$$;

GRANT EXECUTE ON FUNCTION public.hook_password_verification_attempt(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.hook_password_verification_attempt(jsonb) FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.auth_signin_failures TO supabase_auth_admin;
GRANT USAGE, SELECT ON SEQUENCE public.auth_signin_failures_id_seq TO supabase_auth_admin;
