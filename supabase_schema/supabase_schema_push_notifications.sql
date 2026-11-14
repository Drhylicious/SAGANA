-- ============================================================================
-- Native phone push notifications (Buyer, Farmer, Manager, Officer)
--
-- Run ONCE in the Supabase SQL editor, AFTER deploying the Edge Function
-- `send-push-notification` (supabase/functions/send-push-notification).
--
-- How it fits together
--   1. The app registers this phone's FCM token with register_push_token().
--   2. Every new row in `notifications` (the in-app record) fires a trigger that
--      asks the Edge Function to push that same row to the recipient's phones, so
--      the in-app list and the phone notification are always the same event.
--   3. The function sends it through Firebase Cloud Messaging with the row id and
--      route_on_tap, so tapping it opens the same screen as tapping it in-app.
--
-- The trigger never blocks or fails a notification insert: if push is not set up
-- yet (no config rows below) or the request fails, the in-app row is still saved.
-- ============================================================================

-- 1. Phone tokens ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.device_push_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token       text NOT NULL UNIQUE,
  platform    text,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_push_tokens_user_idx
  ON public.device_push_tokens (user_id);

ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;

-- A user may see and remove only their own phones. Writes go through the
-- functions below (a token can move between accounts on a shared phone).
DROP POLICY IF EXISTS device_push_tokens_select_own ON public.device_push_tokens;
CREATE POLICY device_push_tokens_select_own ON public.device_push_tokens
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS device_push_tokens_delete_own ON public.device_push_tokens;
CREATE POLICY device_push_tokens_delete_own ON public.device_push_tokens
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 2. Register / unregister ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_platform text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN;
  END IF;
  -- One phone token belongs to one account at a time: signing in as someone else
  -- on the same phone moves it.
  INSERT INTO public.device_push_tokens (user_id, token, platform, updated_at)
  VALUES (auth.uid(), p_token, p_platform, now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.device_push_tokens
  WHERE token = p_token AND user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.register_push_token(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unregister_push_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_token(text) TO authenticated;

-- 3. Private config (function URL + shared secret) ----------------------------
-- No policies: only the service role and SECURITY DEFINER functions can read it.
CREATE TABLE IF NOT EXISTS public.push_config (
  key   text PRIMARY KEY,
  value text NOT NULL
);
ALTER TABLE public.push_config ENABLE ROW LEVEL SECURITY;

-- 4. Trigger: every new notification also goes to the phone --------------------
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.push_new_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  SELECT value INTO v_url    FROM public.push_config WHERE key = 'function_url';
  SELECT value INTO v_secret FROM public.push_config WHERE key = 'webhook_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN
    RETURN NEW;  -- push not configured yet: in-app notification only
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body    := jsonb_build_object(
      'notification_id', NEW.id,
      'user_id',         NEW.user_id,
      'title',           NEW.title,
      'body',            NEW.body,
      'route',           NEW.route_on_tap,
      'route_extra',     NEW.route_extra
    )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;  -- never block the in-app notification
END;
$$;

DROP TRIGGER IF EXISTS trg_push_new_notification ON public.notifications;
CREATE TRIGGER trg_push_new_notification
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.push_new_notification();

-- 5. Turn it on (edit the two values, then run these two statements) ----------
-- function_url   : https://<PROJECT-REF>.supabase.co/functions/v1/send-push-notification
-- webhook_secret : any long random string; set the SAME value as the Edge
--                  Function secret PUSH_WEBHOOK_SECRET.
--
-- INSERT INTO public.push_config (key, value) VALUES
--   ('function_url',   'https://<PROJECT-REF>.supabase.co/functions/v1/send-push-notification'),
--   ('webhook_secret', '<LONG-RANDOM-STRING>')
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
