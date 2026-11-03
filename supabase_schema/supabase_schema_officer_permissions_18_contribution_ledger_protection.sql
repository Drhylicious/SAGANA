-- ============================================================
-- SAGANA — Officer permissions, script 18: CONTRIBUTION LEDGER PROTECTION
--
-- DECISION (yours): prevent Officers from directly editing or deleting existing
-- contribution records through the API. Keep the original records and the
-- accountability history. Do NOT remove their authorized ability to add
-- contributions.
--
-- THE LEDGER is capital_contribution_events: one row per contribution (member
-- payment, opening balance, manual adjustment, Balik-Tangkilik reinvestment). A
-- member's running total (member_capital_shares.total_contribution) is re-derived
-- from the ledger by a database trigger after every change.
--
-- TODAY: the rule "cce: admin manages all" (ALL = read, insert, update, delete) is
-- true for the Manager AND for an Officer with Members = Manage. So an Officer could
-- change an amount or delete a row through the API, and could set a member's total
-- directly. The app never does either: it only ADDS rows. Every change is already
-- written to the staff audit trail with the old values, so it was visible but not
-- prevented.
--
-- WHAT THIS DOES
--   capital_contribution_events
--     * ADD (insert)      Manager and Officer with Members = Manage, as today. The
--                         "recorded by" must be the person adding it (or empty), so
--                         an entry cannot be attributed to someone else.
--     * EDIT / DELETE     Manager only. Through the API an Officer's attempt changes
--                         NOTHING (the database reports 0 rows changed), because row
--                         security hides every row from them for these two actions.
--                         As a second layer, a trigger refuses the change with the
--                         message "Contribution records cannot be changed or deleted.
--                         Add a correction entry instead." for anything that reaches
--                         the table another way (a database function an Officer calls
--                         that runs with owner rights). Corrections are new rows (the
--                         source 'manual_adjustment' already exists and may be
--                         negative), so the original record always stays.
--   member_capital_shares (the derived total)
--     * insert            as today
--     * EDIT / DELETE     Manager only (nobody in the app writes it; the trigger that
--                         keeps it in step runs with the database owner's rights and
--                         is unaffected)
--   Reading is unchanged (staff, and each Farmer their own).
--
-- WHAT DOES NOT CHANGE
--   Adding a contribution from Farmer Details (online, and the offline replay), the
--   Farmer's own notice, Balik-Tangkilik reinvestment, account creation. The audit
--   trigger keeps recording every add, edit and delete with who and when.
--   The Manager can still correct or delete a row (audited with the old values). If
--   you want the ledger append-only for the Manager too, say so; it is one more line.
--
-- SAFETY CHECK (read-only; the script prints a NOTICE and continues): functions
--   that change these tables WITHOUT the database owner's rights would be affected by
--   the new rules. None is expected.
--
-- REQUIRES scripts 01 and 05. Not applied automatically. Run in the SQL editor.
-- Re-runnable.
--
-- ROLLBACK:
--   DROP TRIGGER trg_cce_no_officer_change ON public.capital_contribution_events;
--   DROP POLICY "cce: staff add" ON public.capital_contribution_events;
--   DROP POLICY "cce: manager changes" ON public.capital_contribution_events;
--   DROP POLICY "cce: manager removes" ON public.capital_contribution_events;
--   CREATE POLICY "cce: admin manages all" ON public.capital_contribution_events
--     FOR ALL USING (public.is_platform_admin());
--   (and the same for member_capital_shares: "member_capital_shares: admin manages all")
-- ============================================================

DO $$
DECLARE
  v_names text;
BEGIN
  IF to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_manager() is missing. Run officer_permissions_01 first.';
  END IF;
  IF to_regclass('public.capital_contribution_events') IS NULL OR to_regclass('public.member_capital_shares') IS NULL THEN
    RAISE EXCEPTION 'capital_contribution_events or member_capital_shares is missing.';
  END IF;

  SELECT string_agg(p.proname, ', ') INTO v_names
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f' AND NOT p.prosecdef
    AND p.prosrc ~* '(update|delete\s+from)\s+(public\.)?(capital_contribution_events|member_capital_shares)';
  IF v_names IS NOT NULL THEN
    RAISE NOTICE 'Functions that change the ledger without owner rights (review them): %', v_names;
  END IF;
END $$;

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. The ledger
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "cce: admin manages all" ON public.capital_contribution_events;
DROP POLICY IF EXISTS "cce: staff add" ON public.capital_contribution_events;
DROP POLICY IF EXISTS "cce: manager changes" ON public.capital_contribution_events;
DROP POLICY IF EXISTS "cce: manager removes" ON public.capital_contribution_events;

CREATE POLICY "cce: staff add"
  ON public.capital_contribution_events FOR INSERT
  WITH CHECK (
    public.is_platform_admin()
    AND (recorded_by IS NULL OR recorded_by = auth.uid())
  );

CREATE POLICY "cce: manager changes"
  ON public.capital_contribution_events FOR UPDATE
  USING (public.is_manager())
  WITH CHECK (public.is_manager());

CREATE POLICY "cce: manager removes"
  ON public.capital_contribution_events FOR DELETE
  USING (public.is_manager());

-- Second layer. Row security already hides these rows from an Officer, so a direct
-- API edit or delete simply changes nothing. This trigger also stops (with a clear
-- message) a change that arrives through a function running with owner rights, and
-- keeps working if a broader rule is ever added by mistake.
CREATE OR REPLACE FUNCTION public.cce_block_non_manager_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Database maintenance (no signed-in user) and the Manager are not blocked.
  IF auth.uid() IS NULL OR public.is_manager() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'Contribution records cannot be changed or deleted. Add a correction entry instead.';
END;
$$;

REVOKE ALL ON FUNCTION public.cce_block_non_manager_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_cce_no_officer_change ON public.capital_contribution_events;
CREATE TRIGGER trg_cce_no_officer_change
  BEFORE UPDATE OR DELETE ON public.capital_contribution_events
  FOR EACH ROW EXECUTE FUNCTION public.cce_block_non_manager_change();

-- ════════════════════════════════════════════════════════════
-- 2. The derived total
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "member_capital_shares: admin manages all" ON public.member_capital_shares;
DROP POLICY IF EXISTS "member_capital_shares: staff add" ON public.member_capital_shares;
DROP POLICY IF EXISTS "member_capital_shares: manager changes" ON public.member_capital_shares;
DROP POLICY IF EXISTS "member_capital_shares: manager removes" ON public.member_capital_shares;

CREATE POLICY "member_capital_shares: staff add"
  ON public.member_capital_shares FOR INSERT
  WITH CHECK (public.is_platform_admin());

CREATE POLICY "member_capital_shares: manager changes"
  ON public.member_capital_shares FOR UPDATE
  USING (public.is_manager())
  WITH CHECK (public.is_manager());

CREATE POLICY "member_capital_shares: manager removes"
  ON public.member_capital_shares FOR DELETE
  USING (public.is_manager());

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT tablename, policyname, cmd FROM pg_policies
--   WHERE tablename IN ('capital_contribution_events','member_capital_shares') AND cmd <> 'SELECT'
--   ORDER BY tablename, cmd;
--   -- ledger: staff add (INSERT), manager changes (UPDATE), manager removes (DELETE); same pattern for the total
--   SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.capital_contribution_events'::regclass AND NOT tgisinternal;
--   -- expect trg_cce_no_officer_change among them (the recompute and audit triggers stay)
-- In the app: as an Officer (Members = Manage) add a contribution from Farmer Details: it
-- saves, the member's total updates, the member is notified. The Manager's Staff Accountability
-- shows "Recorded a contribution of ₱... for <member>". An API attempt to edit or delete it changes nothing.
-- ─────────────────────────────────────────────────────────────────────────
