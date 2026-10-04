-- Batch 8: destructive database cleanup (Purok and registry notes)
--
-- Removes the last database objects that carry Purok, plus the registry notes
-- columns, as approved in the Batch 8 plan:
--   - check_sp3_registry: recreated without suggested_purok (its return type
--     changes, so it is dropped and created again; the body is otherwise the
--     live definition, including the ambiguous-name guard).
--   - Purok rows in farmer_profile_activity and buyer_profile_activity: deleted
--     (zero rows at the time of the live check; kept for idempotence).
--   - user_information.purok, sp3_member_registry.purok: dropped.
--   - sp3_member_registry.notes, officer_registry.notes: dropped.
--
-- Accepted data loss (approved): 6 user_information rows with a purok value,
-- 3 sp3_member_registry rows with a purok value, and 3 sp3_member_registry rows
-- with notes. Counts were taken from the live database immediately before this
-- file was written.
--
-- Everything runs in one transaction: if any step fails, nothing changes.

BEGIN;

-- ─── 1. check_sp3_registry without suggested_purok ───────────────────────────

DROP FUNCTION IF EXISTS public.check_sp3_registry(text);

CREATE FUNCTION public.check_sp3_registry(p_full_name text)
 RETURNS TABLE(registry_id uuid, is_available boolean, phone_number text, email text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_norm text := lower(trim(p_full_name));
  v_unclaimed_count integer;
BEGIN
  -- How many still-unclaimed registry rows share this normalized name.
  -- More than one means two different real people were entered under
  -- the identical name — auto-matching either one would silently link
  -- the wrong person's identity to this registrant's account.
  SELECT count(*) INTO v_unclaimed_count
  FROM sp3_member_registry r
  WHERE r.normalized_name = v_norm
    AND r.is_registered = false;

  IF v_unclaimed_count > 1 THEN
    RETURN; -- ambiguous: no rows, same as "no match" to every caller
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    NOT r.is_registered AS is_available,
    r.phone_number,
    r.email
  FROM sp3_member_registry r
  WHERE r.normalized_name = v_norm
  ORDER BY r.is_registered ASC, r.created_at ASC
  LIMIT 1;
END;
$function$;

-- Restore the grants the live function had (anon, authenticated, service_role,
-- and the default PUBLIC execute).
GRANT EXECUTE ON FUNCTION public.check_sp3_registry(text) TO anon, authenticated, service_role;

-- ─── 2. Purok rows in the activity logs ──────────────────────────────────────

DELETE FROM public.farmer_profile_activity WHERE description ILIKE '%purok%';
DELETE FROM public.buyer_profile_activity  WHERE description ILIKE '%purok%';

-- ─── 3. Drop the columns (no CASCADE: any unexpected dependency fails here) ──

ALTER TABLE public.user_information  DROP COLUMN IF EXISTS purok;
ALTER TABLE public.sp3_member_registry DROP COLUMN IF EXISTS purok;
ALTER TABLE public.sp3_member_registry DROP COLUMN IF EXISTS notes;
ALTER TABLE public.officer_registry  DROP COLUMN IF EXISTS notes;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. The four columns are gone (expect 0 rows):
--    SELECT table_name, column_name FROM information_schema.columns
--    WHERE table_schema = 'public'
--      AND ((table_name = 'user_information' AND column_name = 'purok')
--        OR (table_name = 'sp3_member_registry' AND column_name IN ('purok','notes'))
--        OR (table_name = 'officer_registry' AND column_name = 'notes'));
--
-- 2. Nothing in the database still names purok (expect 0 rows):
--    SELECT proname FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND prosrc ILIKE '%purok%';
--    SELECT viewname FROM pg_views WHERE schemaname = 'public' AND definition ILIKE '%purok%';
--
-- 3. check_sp3_registry has one overload, with the new return columns (expect 1 row,
--    result does not mention suggested_purok):
--    SELECT count(*) AS overloads,
--           bool_or(pg_get_function_result(oid) ILIKE '%suggested_purok%') AS has_suggested_purok
--    FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'check_sp3_registry';
--
-- 4. Registry matching still works for a known name (expect a row with
--    registry_id, is_available, phone_number and email):
--    SELECT * FROM public.check_sp3_registry('<a name from sp3_member_registry>');
--
-- 5. Activity logs have no purok text (expect 0 and 0):
--    SELECT count(*) FROM farmer_profile_activity WHERE description ILIKE '%purok%';
--    SELECT count(*) FROM buyer_profile_activity  WHERE description ILIKE '%purok%';
