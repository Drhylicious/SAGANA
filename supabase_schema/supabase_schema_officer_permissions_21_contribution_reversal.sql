-- ============================================================
-- SAGANA — Officer permissions, script 21: CANCEL A CONTRIBUTION
--
-- WORDING: the screens and messages say "Cancel Contribution" / "cancelled". The
-- database keeps the accounting names (reverse_capital_contribution, reverses_event_id,
-- reversal_reason) so nothing is renamed.
--
-- DECISIONS (yours):
--   * ONLY the Manager and an Officer who manages Members can record a contribution
--     and cancel a recorded one. A Farmer can do neither (see item 5 below).
--   * Nothing is ever deleted or edited: cancelling adds a NEW entry that cancels the
--     original, so the whole history stays for auditing.
--   * Accountability: who recorded the contribution, who cancelled it, when each
--     happened, and why it was cancelled.
--
-- HOW A CANCELLATION WORKS
--   reverse_capital_contribution(entry, reason) adds one new ledger entry for the same
--   member, with the opposite amount and the same type, that points back to the entry
--   it cancels and carries the reason. The member's total follows the ledger as it
--   always has (the existing total-keeping trigger sums every entry).
--   Rules, all enforced here:
--     * the Manager, or an Officer whose Members access is Manage (the same request
--       gate as every other Members change: a View Only Officer is refused);
--     * a reason of 3 to 500 characters is required;
--     * an entry can be cancelled once, and a cancellation cannot itself be cancelled;
--     * a payout added to capital (type patronage_capital) is NOT cancelled here: it is
--       tied to a Balik-Tangkilik payout decision, which only the Manager handles there.
--
-- WHAT ELSE CHANGES
--   1. capital_contribution_events gets reverses_event_id and reversal_reason.
--   2. Adding a contribution through the API must now name the signed-in person as the
--      recorder (before, a blank recorder was accepted), and cannot create a cancellation
--      by itself: cancellations only come from the function above.
--   3. The ledger is now unchangeable for everyone: the Manager's API rules to edit or
--      delete an entry (script 18) are removed, and a trigger refuses any edit or delete
--      by a signed-in person. Mistakes are fixed by cancelling, never by editing.
--      (Database maintenance with no signed-in user is not blocked.)
--   4. The function is added to the request gate under the Members module.
--   5. A Farmer cannot add capital by themselves. The old self-service function
--      reinvest_patronage_capital() (superseded by the Manager-confirmed payout
--      workflow, and not called by the app) is locked for everyone but the database
--      owner: the earlier script only revoked it from "authenticated", which does not
--      remove the right every database role has by default (PUBLIC).
--   6. The member's notice. A trigger tells the member "Your capital contribution of
--      ₱X was recorded" for every new payment entry, so a cancellation (a negative
--      entry of the same type) would have said "₱-2,000.00 was recorded". It now says
--      "A capital contribution of ₱2,000.00 recorded for you was cancelled." No staff
--      name and no reason are put in the notice.
--   Accountability needs no new code: the existing audit trigger (script 05) already
--   writes every new ledger entry, with the person's name and role, and now also
--   captures the cancellation link and the reason.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo the immutability and the API rules, run script 18 again (it recreates the
-- Manager edit/delete rules); the new columns and the function can simply stay.
-- ============================================================

DO $$
BEGIN
  IF to_regclass('public.capital_contribution_events') IS NULL THEN
    RAISE EXCEPTION 'capital_contribution_events is missing.';
  END IF;
  IF to_regclass('public.staff_permission_targets') IS NULL THEN
    RAISE EXCEPTION 'staff_permission_targets is missing. Run officer_permissions_02 first.';
  END IF;
  IF to_regprocedure('public.is_platform_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_platform_admin(uuid) is missing.';
  END IF;
  IF to_regprocedure('public.recompute_member_capital()') IS NULL THEN
    RAISE EXCEPTION 'recompute_member_capital() is missing (the trigger that keeps the member total in step).';
  END IF;
  IF to_regprocedure('public.fn_notify_capital_recorded()') IS NULL THEN
    RAISE EXCEPTION 'fn_notify_capital_recorded() is missing (the member notice trigger function).';
  END IF;
END $$;

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Columns
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.capital_contribution_events
  ADD COLUMN IF NOT EXISTS reverses_event_id uuid
    REFERENCES public.capital_contribution_events (id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS reversal_reason text;

COMMENT ON COLUMN public.capital_contribution_events.reverses_event_id IS
  'Set on a cancellation entry: the entry it cancels. Null on every normal entry.';
COMMENT ON COLUMN public.capital_contribution_events.reversal_reason IS
  'Why the entry was cancelled. Required on a cancellation entry, null otherwise.';

ALTER TABLE public.capital_contribution_events DROP CONSTRAINT IF EXISTS cce_reversal_consistent;
ALTER TABLE public.capital_contribution_events
  ADD CONSTRAINT cce_reversal_consistent CHECK (
    (reverses_event_id IS NULL AND reversal_reason IS NULL)
    OR (reverses_event_id IS NOT NULL AND length(btrim(reversal_reason)) BETWEEN 3 AND 500)
  );

-- One cancellation per entry, enforced by the database whatever the app does.
CREATE UNIQUE INDEX IF NOT EXISTS ux_cce_one_reversal
  ON public.capital_contribution_events (reverses_event_id)
  WHERE reverses_event_id IS NOT NULL;

-- ════════════════════════════════════════════════════════════
-- 2. Who may add through the API, and nobody may change or delete
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "cce: staff add" ON public.capital_contribution_events;
CREATE POLICY "cce: staff add"
  ON public.capital_contribution_events FOR INSERT
  WITH CHECK (
    public.is_platform_admin()
    AND recorded_by = auth.uid()
    AND reverses_event_id IS NULL
    AND reversal_reason IS NULL
  );

DROP POLICY IF EXISTS "cce: manager changes" ON public.capital_contribution_events;
DROP POLICY IF EXISTS "cce: manager removes" ON public.capital_contribution_events;

CREATE OR REPLACE FUNCTION public.cce_block_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Database maintenance (no signed-in user) is not blocked.
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'Contribution records cannot be changed or deleted. Cancel the entry instead.';
END;
$$;

DROP TRIGGER IF EXISTS trg_cce_no_officer_change ON public.capital_contribution_events;
DROP TRIGGER IF EXISTS trg_cce_immutable ON public.capital_contribution_events;
CREATE TRIGGER trg_cce_immutable
  BEFORE UPDATE OR DELETE ON public.capital_contribution_events
  FOR EACH ROW EXECUTE FUNCTION public.cce_block_change();
DROP FUNCTION IF EXISTS public.cce_block_non_manager_change();

-- ════════════════════════════════════════════════════════════
-- 3. The cancellation
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.reverse_capital_contribution(p_event_id uuid, p_reason text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_orig   public.capital_contribution_events%ROWTYPE;
  v_reason text := btrim(COALESCE(p_reason, ''));
  v_new    uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only the Manager or an Officer who manages Members can cancel a contribution.';
  END IF;
  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'Enter the reason for the cancellation (at least 3 characters).';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is too long (500 characters at most).';
  END IF;

  SELECT * INTO v_orig FROM public.capital_contribution_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contribution not found.';
  END IF;
  IF v_orig.reverses_event_id IS NOT NULL THEN
    RAISE EXCEPTION 'A cancellation cannot be cancelled.';
  END IF;
  IF v_orig.source = 'patronage_capital' THEN
    RAISE EXCEPTION 'A payout added to capital is handled in Balik-Tangkilik and cannot be cancelled here.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.capital_contribution_events WHERE reverses_event_id = p_event_id) THEN
    RAISE EXCEPTION 'This contribution has already been cancelled.';
  END IF;

  INSERT INTO public.capital_contribution_events
    (farmer_id, amount, source, note, recorded_by, reverses_event_id, reversal_reason)
  VALUES
    (v_orig.farmer_id, -v_orig.amount, v_orig.source, NULL, auth.uid(), v_orig.id, v_reason)
  RETURNING id INTO v_new;

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.reverse_capital_contribution(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reverse_capital_contribution(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. The request gate: a View Only Officer cannot cancel
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module)
VALUES ('rpc', 'reverse_capital_contribution', 'members')
ON CONFLICT (kind, name) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- 5. Farmers cannot add capital on their own
-- ════════════════════════════════════════════════════════════
-- Every other way in is already staff-only: the ledger's insert rule needs
-- is_platform_admin(), the create-account and payout-confirmation functions check
-- the caller, and the self-service renewal function was dropped. This one function
-- is the exception: it was revoked only from "authenticated" (payout_decision_workflow),
-- and PUBLIC still held the default right to run it.
DO $$
BEGIN
  IF to_regprocedure('public.reinvest_patronage_capital(integer,numeric,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.reinvest_patronage_capital(integer, numeric, text) FROM PUBLIC, anon, authenticated;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 6. The member's notice for a cancellation
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_notify_capital_recorded()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source = 'member_payment' THEN
    IF NEW.reverses_event_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        NEW.farmer_id,
        'capital',
        'Capital Contribution Cancelled',
        'A capital contribution of ₱' || TO_CHAR(ABS(NEW.amount), 'FM999999990.00') || ' recorded for you was cancelled.',
        FALSE,
        NOW(),
        '/farmer/profile/contribution'
      );
    ELSE
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        NEW.farmer_id,
        'capital',
        'Capital Contribution Recorded',
        'Your capital contribution of ₱' || TO_CHAR(NEW.amount, 'FM999999990.00') || ' was recorded.',
        FALSE,
        NOW(),
        '/farmer/profile/contribution'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT policyname, cmd FROM pg_policies
--   WHERE tablename = 'capital_contribution_events' ORDER BY cmd, policyname;
--   -- INSERT: "cce: staff add" only; no UPDATE or DELETE rule; SELECT: staff reads + farmer reads own
--   SELECT tgname FROM pg_trigger
--   WHERE tgrelid = 'public.capital_contribution_events'::regclass AND NOT tgisinternal;
--   -- expect trg_cce_immutable (and not trg_cce_no_officer_change), plus the recompute and audit triggers
--   SELECT * FROM staff_permission_targets WHERE name = 'reverse_capital_contribution';  -- 1 row, members
--   SELECT has_function_privilege('authenticated', 'public.reinvest_patronage_capital(integer,numeric,text)', 'EXECUTE');
--   -- false (a Farmer cannot call the old self-service function); an error "function does not exist" is fine too
--   SELECT prosrc LIKE '%was cancelled%' FROM pg_proc WHERE proname = 'fn_notify_capital_recorded';  -- true
-- In the app: Farmer Details > Contribution: each entry shows who recorded it and when;
-- Cancel Contribution on an entry asks for a reason, adds a "Cancellation" entry, and marks
-- the original "Cancelled". Staff Accountability shows it with the person, time and reason.
-- ─────────────────────────────────────────────────────────────────────────
