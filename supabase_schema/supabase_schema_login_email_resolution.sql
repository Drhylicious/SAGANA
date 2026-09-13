    CREATE OR REPLACE FUNCTION public.resolve_login_email(p_identifier TEXT)
    RETURNS TEXT
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $function$
    DECLARE
    v_email TEXT;
    v_identifier TEXT := lower(trim(p_identifier));
    BEGIN
    IF v_identifier LIKE '%@%' THEN
        RETURN v_identifier;
    END IF;

    SELECT u.email INTO v_email
    FROM public.user_information ui
    JOIN auth.users u ON u.id = ui.user_id
    WHERE ui.username = v_identifier;

    IF v_email IS NULL THEN
        RAISE EXCEPTION 'Account not found';
    END IF;

    RETURN v_email;
    END;
    $function$;

    GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT) TO anon;
    GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT) TO authenticated;