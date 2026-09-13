CREATE OR REPLACE FUNCTION public.promote_contact_email(p_email TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_new_email TEXT;
  v_username TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT username INTO v_username
  FROM public.user_information
  WHERE user_id = v_user_id;

  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No username on file for this account';
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    -- Revert: no real email provided, go back to the synthetic address.
    v_new_email := lower(trim(v_username)) || '@sagana.local';
  ELSE
    v_new_email := lower(trim(p_email));

    IF v_new_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
      RAISE EXCEPTION 'Invalid email format';
    END IF;

    IF v_new_email LIKE '%@sagana.local' THEN
      RAISE EXCEPTION 'This domain is reserved for internal use';
    END IF;

    IF EXISTS (
      SELECT 1 FROM auth.users WHERE email = v_new_email AND id != v_user_id
    ) THEN
      RAISE EXCEPTION 'This email is already in use by another account';
    END IF;
  END IF;

  UPDATE auth.users
  SET email = v_new_email, updated_at = NOW()
  WHERE id = v_user_id;

  -- identities.email is a generated column derived from identity_data —
  -- confirmed earlier this session — so identity_data is what must be
  -- written, not the email column directly.
  UPDATE auth.identities
  SET identity_data = identity_data || jsonb_build_object('email', v_new_email),
      updated_at = NOW()
  WHERE user_id = v_user_id AND provider = 'email';

  UPDATE public.user_information
  SET contact_email = CASE WHEN p_email IS NULL OR trim(p_email) = '' THEN NULL ELSE v_new_email END
  WHERE user_id = v_user_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.promote_contact_email(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_use_otp_reset(p_identifier TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id UUID;
  v_email TEXT;
BEGIN
  SELECT ui.user_id, u.email INTO v_user_id, v_email
  FROM public.user_information ui
  JOIN auth.users u ON u.id = ui.user_id
  WHERE ui.username = lower(trim(p_identifier));

  IF v_user_id IS NULL THEN
    SELECT id, email INTO v_user_id, v_email
    FROM auth.users
    WHERE email = lower(trim(p_identifier));
  END IF;

  IF v_user_id IS NULL THEN
    RETURN FALSE; -- same false for "not found" as "no email" — no enumeration signal, consistent with request_password_assistance
  END IF;

  RETURN v_email IS NOT NULL AND v_email NOT LIKE '%@sagana.local';
END;
$function$;

GRANT EXECUTE ON FUNCTION public.can_use_otp_reset(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.can_use_otp_reset(TEXT) TO authenticated;