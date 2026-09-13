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
  IF NOT EXISTS (
    SELECT 1
    FROM public.admin_profiles
    WHERE user_id = auth.uid()
  ) THEN
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

NOTIFY pgrst, 'reload schema';