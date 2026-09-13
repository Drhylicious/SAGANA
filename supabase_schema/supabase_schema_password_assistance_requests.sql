-- Pre-authentication "Request Password Assistance" flow, submitted from the
-- Login screen's Contact Admin sheet. No logged-in user exists at this point
-- (this runs before authentication), so this uses a different trust model
-- than the rest of the account-management module (create_farmer_account,
-- admin_reset_user_password), which assume an already-authenticated Admin.

CREATE TABLE public.password_reset_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved')),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES auth.users(id)
);

-- Callable by anon (no logged-in user exists at this point in the flow —
-- this runs from the login screen, before authentication). Deliberately
-- returns the same result whether or not the username exists, so this
-- can't be used to enumerate valid SAGANA usernames. Also deliberately
-- silent (no exception) on a duplicate pending request, so a user
-- repeatedly tapping the button doesn't flood the table with rows the
-- admin has to sift through for the same account.
CREATE OR REPLACE FUNCTION public.request_password_assistance(p_username TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT user_id INTO v_user_id
  FROM user_information
  WHERE username = lower(trim(p_username));

  IF v_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM password_reset_requests
    WHERE user_id = v_user_id AND status = 'pending'
  ) THEN
    INSERT INTO password_reset_requests (user_id, username)
    VALUES (v_user_id, lower(trim(p_username)));
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.request_password_assistance(TEXT) TO anon;

-- Admin-only read access, same pattern as user_roles' existing policy
ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "password_reset_requests: admin reads all"
  ON public.password_reset_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "password_reset_requests: admin updates"
  ON public.password_reset_requests FOR UPDATE
  USING (EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()));
