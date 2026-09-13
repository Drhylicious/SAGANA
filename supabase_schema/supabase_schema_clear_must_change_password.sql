-- Lets a user clear their own forced-password-change flag after
-- successfully setting a new password via ForcePasswordChangeScreen.
-- Scoped entirely to auth.uid() — no user_id parameter exists, so there is
-- no way to call this against anyone else's account.
CREATE OR REPLACE FUNCTION public.clear_must_change_password()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE user_roles
  SET must_change_password = FALSE
  WHERE user_id = auth.uid();
END;
$function$;