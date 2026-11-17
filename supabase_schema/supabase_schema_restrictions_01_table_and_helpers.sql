-- ============================================================
-- supabase_schema_restrictions_01_table_and_helpers.sql
--
-- FEATURE RESTRICTIONS (1 of 4). Run the four scripts in order:
--   01 table + helpers   02 apply / lift / history   03 enforcement   04 hide suspended listings
--
-- A restriction stops a Farmer Member from STARTING one kind of new activity. The
-- account stays Active and everything already in progress (listings, sales, offers,
-- orders, loans, program participation) carries on untouched. Whole-account
-- suspension still exists, separately (suspend_member).
--
-- THE SEVEN FEATURES (member_restrictions.feature)
--   marketplace_listing  create a new Marketplace listing
--   coop_offer           start a new Offer to Cooperative
--   informal_sale        record a new Informal Sale
--   ginger_da_amad       submit a new Ginger sale through DA-AMAD Market Linking
--   checkout             check out / Buy Now (Marketplace and Cooperative Products)
--   loan_request         submit a new loan request
--   program_join         join a new program
--
-- ONE ROW = ONE RESTRICTION on ONE feature. Rows are never deleted: lifting, ending
-- or closing one only changes its status, so the table is also the history.
--   status  active  in force (until ends_at, when there is one)
--           lifted  removed early by a Manager / Officer
--           ended   the end date passed
--           closed  closed because the member was reactivated after a suspension
--
-- A restriction is IN FORCE when status = 'active' AND (ends_at IS NULL OR ends_at > now()),
-- so an end date takes effect at that moment, without waiting for a scheduled job.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.member_restrictions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  feature         text NOT NULL,
  reason          text NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  starts_at       timestamptz NOT NULL DEFAULT now(),
  ends_at         timestamptz,
  applied_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  applied_by_name text,
  applied_by_role text,
  closed_at       timestamptz,
  closed_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  closed_by_name  text,
  close_reason    text,
  CONSTRAINT member_restrictions_feature_chk
    CHECK (feature IN ('marketplace_listing', 'coop_offer', 'informal_sale', 'ginger_da_amad', 'checkout', 'loan_request', 'program_join')),
  CONSTRAINT member_restrictions_status_chk
    CHECK (status IN ('active', 'lifted', 'ended', 'closed')),
  CONSTRAINT member_restrictions_reason_chk
    CHECK (btrim(reason) <> ''),
  CONSTRAINT member_restrictions_end_after_start_chk
    CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS member_restrictions_active_idx
  ON public.member_restrictions (member_id, feature) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS member_restrictions_member_idx
  ON public.member_restrictions (member_id, starts_at DESC);

COMMENT ON TABLE public.member_restrictions IS
  'One row per feature restriction applied to a Farmer Member; the history of who restricted what, why, when and how it ended. Written only by restrict_member() / lift_member_restriction() and the daily job.';

-- Staff read it (Members screens). Nobody writes it directly: only the SECURITY
-- DEFINER functions in script 02. A Farmer reads their own through my_restrictions(),
-- which hides which staff member acted.
ALTER TABLE public.member_restrictions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff read member_restrictions" ON public.member_restrictions;
CREATE POLICY "staff read member_restrictions" ON public.member_restrictions
  FOR SELECT USING (public.is_staff());
REVOKE ALL ON public.member_restrictions FROM anon, authenticated;
GRANT SELECT ON public.member_restrictions TO authenticated;

-- ════════════════════════════════════════════════════════════
-- The words a Farmer reads when a feature is refused.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.restriction_feature_label(p_feature text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_feature
    WHEN 'marketplace_listing' THEN 'Creating a new Marketplace listing'
    WHEN 'coop_offer'          THEN 'Offering produce to the Cooperative'
    WHEN 'informal_sale'       THEN 'Recording an informal sale'
    WHEN 'ginger_da_amad'      THEN 'Submitting a new Ginger sale through DA-AMAD'
    WHEN 'checkout'            THEN 'Checking out'
    WHEN 'loan_request'        THEN 'Requesting a loan'
    WHEN 'program_join'        THEN 'Joining a program'
    ELSE p_feature
  END;
$$;

-- The restriction in force on one feature for one member, if any (the one that lasts
-- longest when there are several).
CREATE OR REPLACE FUNCTION public.member_feature_restriction(p_member uuid, p_feature text)
RETURNS TABLE (reason text, ends_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT r.reason, r.ends_at
  FROM public.member_restrictions r
  WHERE r.member_id = p_member
    AND r.feature = p_feature
    AND r.status = 'active'
    AND (r.ends_at IS NULL OR r.ends_at > now())
  ORDER BY (r.ends_at IS NULL) DESC, r.ends_at DESC
  LIMIT 1;
$$;

-- Called at the top of every "start something new" function (script 03). Does nothing
-- for anyone without a restriction in force on that feature, which includes Managers,
-- Officers and Buyers. Otherwise it stops the action with one short, readable sentence.
CREATE OR REPLACE FUNCTION public.assert_feature_available(p_feature text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_reason text;
  v_ends   timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;
  SELECT f.reason, f.ends_at INTO v_reason, v_ends
  FROM public.member_feature_restriction(v_uid, p_feature) f;
  IF v_reason IS NULL THEN
    RETURN;
  END IF;
  RAISE EXCEPTION '% is restricted: %.',
    public.restriction_feature_label(p_feature),
    rtrim(v_reason, '. ')
      || CASE WHEN v_ends IS NULL THEN ''
              ELSE ' (until ' || to_char(v_ends AT TIME ZONE 'Asia/Manila', 'FMMon FMDD, YYYY') || ')' END
    USING DETAIL = 'feature_restricted:' || p_feature;
END;
$function$;

-- What the signed-in Farmer is restricted from right now (no staff names).
CREATE OR REPLACE FUNCTION public.my_restrictions()
RETURNS TABLE (feature text, reason text, starts_at timestamptz, ends_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT r.feature, r.reason, r.starts_at, r.ends_at
  FROM public.member_restrictions r
  WHERE r.member_id = auth.uid()
    AND r.status = 'active'
    AND (r.ends_at IS NULL OR r.ends_at > now())
  ORDER BY r.starts_at DESC;
$$;

REVOKE ALL ON FUNCTION public.restriction_feature_label(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.member_feature_restriction(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.assert_feature_available(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.my_restrictions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restriction_feature_label(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_restrictions() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECK (read-only). Run on its own. Every row PASS.
-- ============================================================
SELECT 'restrictions table exists' AS check_name,
       CASE WHEN to_regclass('public.member_restrictions') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'row level security is on',
       CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.member_restrictions'::regclass)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'only staff can read it directly',
       CASE WHEN (SELECT count(*) FROM pg_policies WHERE tablename = 'member_restrictions') = 1
              AND NOT has_table_privilege('authenticated', 'public.member_restrictions', 'INSERT')
              AND NOT has_table_privilege('authenticated', 'public.member_restrictions', 'UPDATE')
              AND NOT has_table_privilege('authenticated', 'public.member_restrictions', 'DELETE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'a Farmer can read their own through my_restrictions()',
       CASE WHEN has_function_privilege('authenticated', 'public.my_restrictions()', 'EXECUTE') THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'the check helper is internal only',
       CASE WHEN NOT has_function_privilege('authenticated', 'public.assert_feature_available(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END;
