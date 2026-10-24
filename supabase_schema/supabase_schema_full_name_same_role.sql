-- Full-name duplicate check, narrowed to the same account role.
--
-- Before: check_full_name_available(text) blocked a registration when ANY
-- account (Farmer, Buyer, Officer or Admin) had the same name, and when any
-- SP3 registry row was registered under it. A Farmer named like an Officer
-- was blocked even though they are different people.
--
-- After: check_full_name_available(text, text) takes the role being
--   registered ('farmer' | 'buyer').
--   - An account blocks the registration only when it has the SAME role.
--   - The SP3 registry check applies to Farmer registrations only.
--   - Officer and Admin accounts never block a self-registration.
--
-- Run manually in the Supabase SQL editor (or supabase db query --linked -f).
-- Verify with the test block in the verification notes before running.

BEGIN;

-- The old one-argument signature is removed so the client cannot call it by
-- mistake.
DROP FUNCTION IF EXISTS public.check_full_name_available(text);

CREATE OR REPLACE FUNCTION public.check_full_name_available(p_full_name text, p_role text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_norm text := lower(trim(p_full_name));
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('farmer', 'buyer') THEN
    -- The client maps any RPC error to 'error', which does not block.
    RAISE EXCEPTION 'check_full_name_available: role must be farmer or buyer';
  END IF;

  IF v_norm = '' THEN
    RETURN 'available';
  END IF;

  -- Same-role accounts only.
  IF EXISTS (
    SELECT 1
    FROM user_information ui
    JOIN user_roles ur ON ur.user_id = ui.user_id
    WHERE lower(trim(ui.full_name)) = v_norm
      AND ur.role = p_role
  ) THEN
    RETURN 'taken_account';
  END IF;

  -- SP3 registry: Farmer registrations only.
  IF p_role = 'farmer' AND EXISTS (
    SELECT 1
    FROM sp3_member_registry r
    WHERE r.normalized_name = v_norm
      AND r.is_registered = true
  ) THEN
    RETURN 'taken_registry';
  END IF;

  RETURN 'available';
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_full_name_available(text, text)
  TO anon, authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
