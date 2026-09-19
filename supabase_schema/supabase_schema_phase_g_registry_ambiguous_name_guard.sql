-- ============================================================
-- SAGANA — Phase G: check_sp3_registry ambiguous-name guard
-- (Closes the "known limitation" flagged in the Members module
-- documentation: exact full-name string matching cannot tell two
-- unrelated people apart if they share the same name.)
--
-- Problem
--   check_sp3_registry(p_full_name) matched on normalized_name with a
--   plain `LIMIT 1` and no ORDER BY. If the Admin had ever entered two
--   different real people under the identical name into
--   sp3_member_registry (both still unclaimed), a registrant with that
--   name would be silently, arbitrarily matched to WHICHEVER of the two
--   rows Postgres happened to return first — auto-granting instant
--   `sp3-XXXX` active membership under a stranger's registry identity
--   (wrong purok/phone/email auto-fill, wrong person's membership
--   "claimed"), with no way for either the registrant or the Admin to
--   notice anything went wrong.
--
-- Fix
--   Before matching, count how many still-unclaimed
--   (is_registered = false) rows share the normalized name. If more
--   than one candidate exists, the match is genuinely ambiguous —
--   the function now deliberately returns NO ROWS rather than guessing.
--   The client (AuthService.checkSp3Registry) already treats an empty
--   result exactly like "no registry match": both Register and Add
--   Member fall through to their existing, always-safe paths —
--   self-registration continues as an ordinary outsider application
--   (Admin reviews and approves by hand), and Add Member simply creates
--   the account without auto-linking a specific registry row. No client
--   code changes are required for this fix.
--
--   When there is no ambiguity (0 or 1 unclaimed candidates), behavior
--   is unchanged except for one robustness improvement: the final
--   `LIMIT 1` is now deterministically ordered (unclaimed rows first,
--   then oldest `created_at`) instead of relying on Postgres's
--   unspecified default row order.
--
-- Scope
--   This does not attempt to solve name-collision detection in general
--   (e.g. flagging it to the Admin at registry-entry time) — that is a
--   larger product/UX decision noted separately. This fix only ensures
--   the existing auto-match can never silently pick the wrong person
--   when a collision does occur.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.check_sp3_registry(p_full_name text)
 RETURNS TABLE(
   registry_id     uuid,
   is_available    boolean,
   suggested_purok text,
   phone_number    text,
   email           text
 )
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
    r.purok,
    r.phone_number,
    r.email
  FROM sp3_member_registry r
  WHERE r.normalized_name = v_norm
  ORDER BY r.is_registered ASC, r.created_at ASC
  LIMIT 1;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_sp3_registry(text) TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run manually)
-- ============================================================
-- 1) Unambiguous match still works exactly as before:
--    SELECT * FROM check_sp3_registry('<a known, uniquely-named,
--      unclaimed registry entry>');
--    -- expect: one row, is_available = true
--
-- 2) Already-registered match still reports alreadyRegistered:
--    SELECT * FROM check_sp3_registry('<a known, already-claimed
--      registry entry>');
--    -- expect: one row, is_available = false
--
-- 3) Ambiguous match is now refused rather than guessed:
--    -- Seed two unclaimed rows with the same name for this test only:
--    INSERT INTO sp3_member_registry (full_name, purok)
--      VALUES ('Ambiguity Test Person', 'Purok 1 — Centro 1'),
--             ('Ambiguity Test Person', 'Purok 2 — Centro 2');
--    SELECT * FROM check_sp3_registry('Ambiguity Test Person');
--    -- expect: ZERO rows (previously: one arbitrary row)
--    -- clean up the two test rows afterward:
--    DELETE FROM sp3_member_registry WHERE full_name = 'Ambiguity Test Person';
--
-- 4) No match still returns zero rows, unchanged:
--    SELECT * FROM check_sp3_registry('Totally Unregistered Person 12345');
--    -- expect: zero rows
-- ============================================================
