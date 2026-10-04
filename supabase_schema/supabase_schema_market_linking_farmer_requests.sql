-- ============================================================
-- SAGANA — Farmer-Initiated Market Linking Requests
-- (Farmer-Harvest Tab rework, Phase 6a / Schema Foundation)
--
-- Previously, enrollment into DA-AMAD Market Linking was admin-initiated
-- only (enrollFarmer()) — a farmer had no way to ask to be enrolled or to
-- submit a specific harvested Ginger batch for the cooperative to sell on
-- their behalf. This migration adds a farmer-initiated request path
-- without disturbing the existing admin-initiated flow at all.
--
-- Design: a new 'requested' status, strictly before 'submitted' in the
-- lifecycle. 'submitted' has always meant "actively enrolled, awaiting a
-- buyer" throughout the existing UI (Admin's market_linking_screen.dart,
-- Farmer's my_market_linking_screen.dart) — reusing it for "farmer asked,
-- not yet approved" would have been semantically wrong and would have
-- made every existing pending-enrollment view show unapproved requests
-- as if they were live. 'requested' rows are invisible to that existing
-- logic until an admin approves them into 'submitted'.
--
-- No CHECK constraint change was needed on notifications.type — this
-- migration's notification traffic uses the already-allowed 'system'
-- value rather than risking narrowing that constraint (it has been
-- widened by several independent migrations whose relative order isn't
-- knowable from static files alone, so reconstructing the current full
-- list here would risk accidentally dropping a value another migration
-- added). Can be refined to a dedicated type later if wanted.
-- ============================================================

BEGIN;

-- ─── Widen status ────────────────────────────────────────────────────────

ALTER TABLE public.market_linking_programs
  DROP CONSTRAINT IF EXISTS market_linking_programs_status_check;
ALTER TABLE public.market_linking_programs
  ADD CONSTRAINT market_linking_programs_status_check2
  CHECK (status IN ('requested', 'submitted', 'buyer_found', 'completed', 'cancelled'));

-- ─── Farmer can submit their own request ────────────────────────────────
-- Constrained to status='requested' and created_by=auth.uid() (their own
-- id, not an admin's) — a farmer can never insert directly into
-- 'submitted' or any later stage, only ask. If a batch is attached, it
-- must actually belong to them, so a farmer can never fabricate a
-- submission against another farmer's inventory.

CREATE POLICY "Farmers request own market linking enrollment"
  ON public.market_linking_programs FOR INSERT
  WITH CHECK (
    auth.uid() = farmer_id
    AND status = 'requested'
    AND created_by = auth.uid()
    AND (
      inventory_batch_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.inventory_batches ib
        WHERE ib.id = inventory_batch_id AND ib.farmer_id = auth.uid()
      )
    )
  );

-- ─── Farmer can withdraw their own still-pending request ────────────────
-- USING gates which existing rows this policy can even touch (must
-- currently be 'requested' and theirs); WITH CHECK gates what the row is
-- allowed to become (must end up 'cancelled', still theirs). Together
-- these only ever permit one specific transition: requested -> cancelled
-- on a farmer's own row. Application code (MarketLinkingRepository.
-- withdrawRequest()) only ever sends {'status': 'cancelled'} through this
-- path — RLS doesn't restrict which other columns a farmer could
-- technically include in the same UPDATE, so this is enforced by the
-- narrow application-code contract, matching the trust model this schema
-- already uses elsewhere for less sensitive farmer-owned tables (e.g.
-- harvest_records' "farmer manages own" is a blanket FOR ALL policy,
-- broader than this).

CREATE POLICY "Farmers withdraw own pending market linking request"
  ON public.market_linking_programs FOR UPDATE
  USING (auth.uid() = farmer_id AND status = 'requested')
  WITH CHECK (auth.uid() = farmer_id AND status = 'cancelled');

-- ─── Notify admins when a farmer submits a request ──────────────────────
-- Same pattern as notify_admins_of_crop_request() (crop_request_admin_
-- notify.sql) — a SECURITY DEFINER trigger function, so it can write to
-- notifications for every admin even though the triggering INSERT came
-- from a farmer session that only has INSERT rights on this table, not
-- on notifications.

CREATE OR REPLACE FUNCTION public.notify_admins_of_market_linking_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'requested' THEN
    INSERT INTO public.notifications (user_id, type, title, body, is_read, created_at)
    SELECT
      ap.user_id,
      'system',
      'New Market Linking Request',
      'A farmer requested to enroll ' || NEW.crop_name || ' in Market Linking and needs review.',
      FALSE,
      NOW()
    FROM public.admin_profiles ap;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_market_linking_request ON public.market_linking_programs;
CREATE TRIGGER trg_notify_admins_market_linking_request
  AFTER INSERT ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.notify_admins_of_market_linking_request();

-- ─── Admin approves/rejects a request ────────────────────────────────────
-- SECURITY DEFINER for the same reason as approve_crop_request/
-- reject_crop_request — a plain admin-session UPDATE can flip the status
-- fine (admins already have FOR ALL on this table), but notifying the
-- farmer of the outcome requires writing to another user's notifications
-- row, which no admin RLS policy permits directly.

CREATE OR REPLACE FUNCTION public.respond_to_market_linking_request(
  p_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID;
  v_status TEXT;
  v_crop_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review market linking requests';
  END IF;

  SELECT farmer_id, status, crop_name INTO v_farmer_id, v_status, v_crop_name
    FROM market_linking_programs
    WHERE id = p_id
    FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_status != 'requested' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
  END IF;

  UPDATE market_linking_programs
    SET status = CASE WHEN p_approve THEN 'submitted' ELSE 'cancelled' END,
        notes = COALESCE(p_notes, notes)
    WHERE id = p_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'system',
    CASE WHEN p_approve THEN 'Market Linking Request Approved'
         ELSE 'Market Linking Request Declined' END,
    CASE WHEN p_approve
      THEN v_crop_name || ' Market Linking enrollment was approved. Check My Market Linking for status.'
      ELSE 'Your Market Linking request was declined.' ||
           CASE WHEN p_notes IS NOT NULL AND p_notes <> ''
                THEN ' Reason: ' || p_notes ELSE '' END
    END,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_market_linking_request(UUID, BOOLEAN, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Status constraint widened:
--    SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conrelid = 'market_linking_programs'::regclass AND contype = 'c';
--
-- 2) New policies exist:
--    SELECT policyname, cmd FROM pg_policies
--    WHERE tablename = 'market_linking_programs';
--
-- 3) As a farmer session, confirm you CANNOT insert status='submitted'
--    directly (should fail the WITH CHECK), and CAN insert
--    status='requested' with created_by = your own uid.
--
-- 4) As a farmer session, confirm you CANNOT set someone else's batch as
--    inventory_batch_id on your own request row.
-- ============================================================
