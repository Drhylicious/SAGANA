-- ============================================================
-- SAGANA — Program Management Redesign
-- Seed data replacement, Grant/Revenue-Share behavioral split,
-- benefit tracking on program_members, and program_distribution
-- as a new inventory_transactions movement type.
-- ============================================================

-- ─── Seed data: replace generic programs with the real ones ─────────────────

UPDATE public.cooperative_programs
SET program_name = 'Peanut Seed Distribution',
    description = 'SP3 distributes peanut seeds to members ahead of the next planting season.'
WHERE program_name = 'Peanut Program';

UPDATE public.cooperative_programs
SET program_name = 'Livestock Dispersal',
    description = 'Members receive livestock from SP3 and return a percentage of proceeds to the cooperative after selling.'
WHERE program_name = 'Livestock Program';

DELETE FROM public.cooperative_programs WHERE program_name IN ('Crop Program', 'Production Program');

INSERT INTO public.cooperative_programs (program_name, program_type, description, season_year) VALUES
  ('Government Seed Distribution', 'government', 'Seeds from the Municipal Agriculture Office, distributed by SP3 to eligible farmers.', EXTRACT(YEAR FROM NOW())::INT),
  ('Government Fertilizer Distribution', 'government', 'Fertilizer from the Municipal Agriculture Office, distributed by SP3 to eligible farmers.', EXTRACT(YEAR FROM NOW())::INT)
ON CONFLICT (program_name) DO NOTHING;

-- ─── Grant vs Revenue-Share ───────────────────────────────────────────────────

ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS benefit_type TEXT NOT NULL DEFAULT 'grant'
  CHECK (benefit_type IN ('grant', 'revenue_share'));

UPDATE public.cooperative_programs
SET benefit_type = 'revenue_share'
WHERE program_name = 'Livestock Dispersal';

-- ─── program_members: benefit + settlement tracking ──────────────────────────

ALTER TABLE public.program_members
  ADD COLUMN IF NOT EXISTS inventory_item_id UUID REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS quantity_given DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS distributed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS expected_return_percent DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS amount_returned DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;

-- ─── inventory_transactions: new movement type for program benefits ─────────

ALTER TABLE public.inventory_transactions
  DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;

ALTER TABLE public.inventory_transactions
  ADD CONSTRAINT inventory_transactions_transaction_type_check
  CHECK (transaction_type IN (
    'restock', 'loan_issued', 'adjustment', 'harvest_received',
    'sold', 'returned', 'written_off', 'program_distribution'
  ));

-- ─── RPC: settle a revenue-share program return ──────────────────────────────
-- Mirrors confirm_cooperative_offer's shape. Doesn't touch inventory — the
-- benefit itself was already decremented at distribution time; this only
-- records the money coming back.
--
-- DROP FUNCTION first: safe to re-run this file even after a partial or
-- prior run, and avoids the same overload-ambiguity issue hit on
-- approve_crop_request if this signature ever changes later.

DROP FUNCTION IF EXISTS public.confirm_program_return(UUID, DECIMAL, TEXT);

CREATE OR REPLACE FUNCTION confirm_program_return(
  p_program_member_id UUID,
  p_amount_returned DECIMAL,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member RECORD;
  v_program RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm a program return';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;
  IF v_member.settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'This enrollment has already been settled';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.benefit_type != 'revenue_share' THEN
    RAISE EXCEPTION 'This program does not require a return settlement';
  END IF;

  UPDATE program_members
  SET amount_returned = p_amount_returned,
      settled_at = NOW(),
      status = 'completed',
      notes = COALESCE(p_admin_notes, notes)
  WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_member.farmer_id,
    'system',
    'Program Return Settled',
    'Your return of ₱' || p_amount_returned || ' for ' || v_program.program_name || ' has been recorded. Thank you!',
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_program_return(UUID, DECIMAL, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
