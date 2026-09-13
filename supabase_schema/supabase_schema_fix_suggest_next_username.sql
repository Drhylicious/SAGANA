-- Fix: suggest_next_username() built uppercase candidates (e.g. 'SP3-0005')
-- but every stored username is lowercase, so the "already exists?" check
-- could never match — confirmed via pg_get_functiondef, not assumed. The
-- fix lowercases the candidate before the existence check and before
-- returning it.

CREATE OR REPLACE FUNCTION public.suggest_next_username(p_prefix text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT;
  v_candidate TEXT;
  v_exists BOOLEAN;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM user_information
  WHERE username ILIKE p_prefix || '-%';

  LOOP
    v_count := v_count + 1;
    v_candidate := lower(p_prefix || '-' || lpad(v_count::TEXT, 4, '0'));
    SELECT EXISTS (
      SELECT 1 FROM user_information WHERE username = v_candidate
    ) INTO v_exists;
    EXIT WHEN NOT v_exists;
  END LOOP;

  RETURN v_candidate;
END;
$function$;

NOTIFY pgrst, 'reload schema';
