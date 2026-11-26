-- ============================================================================
-- SAGANA — Free Distribution Cooperative Share %, Batch Outcome Tracking,
--          and Cash Share Payment Recording
--
-- FOR YOUR REVIEW — NOT APPLIED. Run manually in Supabase SQL Editor.
-- Safe to re-run (idempotent). Wrapped in a single transaction.
--
-- WHAT THIS SCRIPT DOES:
--   1. Adds `cooperative_share_percent` (default 0, 0..100) to
--      `public.cooperative_programs`, locked once any item is distributed.
--   2. Creates `public.program_sale_shares` to record cooperative shares owed
--      from completed sales of Free Distribution Harvested Produce batches
--      (`orders`, `informal_sales`, `market_linking_sales`).
--   3. Blocks `Offer to Cooperative` on `program_received` batches so farmers
--      cannot sell free distributed produce back to the cooperative.
--   4. Adds `get_program_distribution_summary()`,
--      `get_farmer_distribution_summary()`, and
--      `record_program_share_payment()` (for Manager + Dashboard Manage Officers).
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Cooperative Share % on Free Distribution programs
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS cooperative_share_percent NUMERIC(5,2) NOT NULL DEFAULT 0;

ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_share_percent_chk;
ALTER TABLE public.cooperative_programs
  ADD CONSTRAINT cooperative_programs_share_percent_chk
  CHECK (cooperative_share_percent >= 0 AND cooperative_share_percent <= 100);

CREATE OR REPLACE FUNCTION public._lock_program_share_percent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.cooperative_share_percent IS DISTINCT FROM OLD.cooperative_share_percent THEN
    IF OLD.program_purpose = 'sales' AND NEW.cooperative_share_percent <> 0 THEN
      RAISE EXCEPTION 'Product Sales programs cannot have a Free Distribution cooperative share.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.program_members pm
       WHERE pm.program_id = OLD.id
         AND pm.distributed_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'Cooperative share percentage cannot be changed after items have been distributed.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_program_share_percent ON public.cooperative_programs;
CREATE TRIGGER trg_lock_program_share_percent
  BEFORE UPDATE OF cooperative_share_percent ON public.cooperative_programs
  FOR EACH ROW
  EXECUTE FUNCTION public._lock_program_share_percent();

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Program Sale Shares ledger (Harvested Produce sales only)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.program_sale_shares (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id        UUID NOT NULL REFERENCES public.cooperative_programs(id) ON DELETE RESTRICT,
  program_member_id UUID NOT NULL REFERENCES public.program_members(id) ON DELETE RESTRICT,
  farmer_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  batch_id          UUID NOT NULL REFERENCES public.inventory_batches(id) ON DELETE RESTRICT,
  sale_channel      TEXT NOT NULL CHECK (sale_channel IN ('marketplace', 'informal_sale', 'market_linking')),
  sale_ref_id       UUID NOT NULL,
  quantity_sold     NUMERIC(12,2) NOT NULL CHECK (quantity_sold > 0),
  gross_amount      NUMERIC(12,2) NOT NULL CHECK (gross_amount >= 0),
  share_percent     NUMERIC(5,2)  NOT NULL CHECK (share_percent > 0 AND share_percent <= 100),
  amount_owed       NUMERIC(12,2) NOT NULL CHECK (amount_owed >= 0),
  status            TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'paid')),
  paid_at           TIMESTAMPTZ,
  recorded_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_program_sale_shares_source UNIQUE (sale_channel, sale_ref_id)
);

CREATE INDEX IF NOT EXISTS idx_program_sale_shares_program ON public.program_sale_shares (program_id, status);
CREATE INDEX IF NOT EXISTS idx_program_sale_shares_farmer  ON public.program_sale_shares (farmer_id, status);
CREATE INDEX IF NOT EXISTS idx_program_sale_shares_batch   ON public.program_sale_shares (batch_id);

ALTER TABLE public.program_sale_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "program_sale_shares: staff read all" ON public.program_sale_shares;
CREATE POLICY "program_sale_shares: staff read all"
  ON public.program_sale_shares FOR SELECT TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "program_sale_shares: farmer reads own" ON public.program_sale_shares;
CREATE POLICY "program_sale_shares: farmer reads own"
  ON public.program_sale_shares FOR SELECT TO authenticated
  USING (farmer_id = auth.uid());

REVOKE ALL ON public.program_sale_shares FROM PUBLIC, anon;
GRANT SELECT ON public.program_sale_shares TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Block Offer to Cooperative on Free Distribution batches
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._block_program_received_coop_offer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM public.inventory_batches ib
      JOIN public.harvest_records hr ON hr.id = ib.harvest_record_id
     WHERE ib.id = NEW.inventory_batch_id
       AND hr.source_type = 'program_received'
  ) THEN
    RAISE EXCEPTION 'Produce received from a Free Distribution program cannot be offered back to the cooperative.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_program_received_coop_offer ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_block_program_received_coop_offer
  BEFORE INSERT ON public.cooperative_purchase_offers
  FOR EACH ROW
  EXECUTE FUNCTION public._block_program_received_coop_offer();

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Automatic share creation on completed sales
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._record_program_share_for_batch(
  p_batch_id      UUID,
  p_sale_channel  TEXT,
  p_sale_ref_id   UUID,
  p_qty_sold      NUMERIC,
  p_gross_amount  NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_src RECORD;
  v_owed NUMERIC(12,2);
BEGIN
  IF p_batch_id IS NULL OR p_sale_ref_id IS NULL OR COALESCE(p_qty_sold, 0) <= 0 THEN
    RETURN;
  END IF;

  SELECT hr.source_program_id,
         hr.source_program_member_id,
         ib.farmer_id,
         cp.cooperative_share_percent
    INTO v_src
    FROM public.inventory_batches ib
    JOIN public.harvest_records hr ON hr.id = ib.harvest_record_id
    JOIN public.cooperative_programs cp ON cp.id = hr.source_program_id
   WHERE ib.id = p_batch_id
     AND hr.source_type = 'program_received'
     AND hr.source_program_id IS NOT NULL
     AND hr.source_program_member_id IS NOT NULL
     AND cp.program_purpose = 'distribution'
     AND COALESCE(cp.cooperative_share_percent, 0) > 0;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_owed := round(GREATEST(COALESCE(p_gross_amount, 0), 0) * v_src.cooperative_share_percent / 100.0, 2);

  INSERT INTO public.program_sale_shares (
    program_id, program_member_id, farmer_id, batch_id,
    sale_channel, sale_ref_id, quantity_sold, gross_amount,
    share_percent, amount_owed, status
  )
  VALUES (
    v_src.source_program_id,
    v_src.source_program_member_id,
    v_src.farmer_id,
    p_batch_id,
    p_sale_channel,
    p_sale_ref_id,
    round(p_qty_sold, 2),
    round(GREATEST(COALESCE(p_gross_amount, 0), 0), 2),
    v_src.cooperative_share_percent,
    v_owed,
    CASE WHEN v_owed = 0 THEN 'paid' ELSE 'unpaid' END
  )
  ON CONFLICT (sale_channel, sale_ref_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public._record_program_share_for_batch(UUID, TEXT, UUID, NUMERIC, NUMERIC) FROM PUBLIC, anon, authenticated;

-- 4a. Marketplace orders completed
CREATE OR REPLACE FUNCTION public._trg_order_program_share()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_id UUID;
  v_price    NUMERIC;
  v_gross    NUMERIC;
BEGIN
  IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
    SELECT ml.inventory_batch_id, ml.price_per_kg
      INTO v_batch_id, v_price
      FROM public.marketplace_listings ml
     WHERE ml.id = NEW.listing_id;

    v_gross := COALESCE(NEW.total_amount, COALESCE(NEW.quantity_kg, 0) * COALESCE(v_price, 0));
    PERFORM public._record_program_share_for_batch(
      v_batch_id,
      'marketplace',
      NEW.id,
      NEW.quantity_kg,
      v_gross
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_program_share ON public.orders;
CREATE TRIGGER trg_order_program_share
  AFTER INSERT OR UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_order_program_share();

-- 4b. Informal sales recorded
CREATE OR REPLACE FUNCTION public._trg_informal_sale_program_share()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._record_program_share_for_batch(
    NEW.inventory_batch_id,
    'informal_sale',
    NEW.id,
    NEW.quantity_kg,
    COALESCE(NEW.amount, 0)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_informal_sale_program_share ON public.informal_sales;
CREATE TRIGGER trg_informal_sale_program_share
  AFTER INSERT ON public.informal_sales
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_informal_sale_program_share();

-- 4c. DA-AMAD Ginger Market Linking sales recorded
CREATE OR REPLACE FUNCTION public._trg_market_linking_sale_program_share()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._record_program_share_for_batch(
    NEW.inventory_batch_id,
    'market_linking',
    NEW.id,
    NEW.confirmed_volume_kg,
    COALESCE(NEW.total_amount, 0)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_sale_program_share ON public.market_linking_sales;
CREATE TRIGGER trg_market_linking_sale_program_share
  AFTER INSERT ON public.market_linking_sales
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_market_linking_sale_program_share();

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Read & Payment RPCs
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_program_distribution_summary(p_program_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dist_qty    NUMERIC := 0;
  v_sold_qty    NUMERIC := 0;
  v_unsold_qty  NUMERIC := 0;
  v_rotten_qty  NUMERIC := 0;
  v_owed        NUMERIC := 0;
  v_paid        NUMERIC := 0;
  v_unpaid      NUMERIC := 0;
  v_shares      JSONB := '[]'::jsonb;
  v_outcomes    JSONB := '[]'::jsonb;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only cooperative staff can view program distribution summaries.';
  END IF;

  SELECT COALESCE(sum(pm.quantity_given), 0)
    INTO v_dist_qty
    FROM public.program_members pm
   WHERE pm.program_id = p_program_id
     AND pm.distributed_at IS NOT NULL;

  SELECT COALESCE(sum(ib.sold_kg), 0),
         COALESCE(sum(ib.available_kg + ib.reserved_kg), 0),
         COALESCE(sum(COALESCE(bsl.spoiled_kg, 0)), 0),
         COALESCE(jsonb_agg(
           jsonb_build_object(
             'program_member_id', pm.id,
             'farmer_id', pm.farmer_id,
             'farmer_name', COALESCE(ui.full_name, 'Farmer'),
             'batch_id', ib.id,
             'batch_number', ib.batch_number,
             'crop_name', ib.crop_name,
             'unit', ib.unit,
             'distributed_qty', round(COALESCE(pm.quantity_given, ib.quantity_kg), 2),
             'available_qty', round(ib.available_kg, 2),
             'reserved_qty', round(ib.reserved_kg, 2),
             'sold_qty', round(ib.sold_kg, 2),
             'rotten_qty', round(COALESCE(bsl.spoiled_kg, 0), 2),
             'listed_qty', round(COALESCE((
               SELECT sum(ml.remaining_kg)
                 FROM public.marketplace_listings ml
                WHERE ml.inventory_batch_id = ib.id
                  AND ml.status = 'approved'
                  AND ml.remaining_kg > 0
             ), 0), 2),
             'market_linking_active', EXISTS (
               SELECT 1
                 FROM public.market_linking_programs mlp
                WHERE mlp.inventory_batch_id = ib.id
                  AND mlp.status IN ('pending', 'approved', 'in_progress')
             )
           ) ORDER BY pm.distributed_at DESC NULLS LAST
         ), '[]'::jsonb)
    INTO v_sold_qty, v_unsold_qty, v_rotten_qty, v_outcomes
    FROM public.program_members pm
    JOIN public.harvest_records hr ON hr.source_program_member_id = pm.id
    JOIN public.inventory_batches ib ON ib.harvest_record_id = hr.id
    LEFT JOIN public.batch_shelf_life bsl ON bsl.batch_id = ib.id
    LEFT JOIN public.user_information ui ON ui.user_id = pm.farmer_id
   WHERE pm.program_id = p_program_id;

  SELECT COALESCE(sum(s.amount_owed), 0),
         COALESCE(sum(CASE WHEN s.status = 'paid' THEN s.amount_owed ELSE 0 END), 0),
         COALESCE(sum(CASE WHEN s.status = 'unpaid' THEN s.amount_owed ELSE 0 END), 0),
         COALESCE(jsonb_agg(
           jsonb_build_object(
             'id', s.id,
             'program_id', s.program_id,
             'program_member_id', s.program_member_id,
             'farmer_id', s.farmer_id,
             'farmer_name', COALESCE(ui.full_name, 'Farmer'),
             'batch_id', s.batch_id,
             'crop_name', ib.crop_name,
             'unit', ib.unit,
             'sale_channel', s.sale_channel,
             'quantity_sold', s.quantity_sold,
             'gross_amount', s.gross_amount,
             'share_percent', s.share_percent,
             'amount_owed', s.amount_owed,
             'status', s.status,
             'paid_at', s.paid_at,
             'notes', s.notes,
             'created_at', s.created_at
           ) ORDER BY (s.status = 'unpaid') DESC, s.created_at DESC
         ), '[]'::jsonb)
    INTO v_owed, v_paid, v_unpaid, v_shares
    FROM public.program_sale_shares s
    LEFT JOIN public.user_information ui ON ui.user_id = s.farmer_id
    LEFT JOIN public.inventory_batches ib ON ib.id = s.batch_id
   WHERE s.program_id = p_program_id;

  RETURN jsonb_build_object(
    'distributed_qty', round(v_dist_qty, 2),
    'sold_qty',        round(v_sold_qty, 2),
    'unsold_qty',      round(v_unsold_qty, 2),
    'rotten_qty',      round(v_rotten_qty, 2),
    'total_owed',      round(v_owed, 2),
    'total_paid',      round(v_paid, 2),
    'total_unpaid',    round(v_unpaid, 2),
    'shares',          v_shares,
    'member_outcomes', v_outcomes
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_program_distribution_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_distribution_summary(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_farmer_distribution_summary(p_farmer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_to_distribute INT := 0;
  v_distributed_n INT := 0;
  v_completed_n   INT := 0;
  v_distributed_q NUMERIC := 0;
  v_sold_q        NUMERIC := 0;
  v_unsold_q      NUMERIC := 0;
  v_rotten_q      NUMERIC := 0;
  v_owed          NUMERIC := 0;
  v_paid          NUMERIC := 0;
  v_unpaid        NUMERIC := 0;
BEGIN
  IF NOT public.is_staff() AND auth.uid() <> p_farmer_id THEN
    RAISE EXCEPTION 'You are not allowed to view this farmer distribution summary.';
  END IF;

  SELECT count(*) FILTER (WHERE pm.status = 'active' AND pm.distributed_at IS NULL AND cp.status = 'active'),
         count(*) FILTER (WHERE pm.distributed_at IS NOT NULL),
         count(*) FILTER (WHERE cp.status = 'completed' OR pm.status = 'completed'),
         COALESCE(sum(pm.quantity_given) FILTER (WHERE pm.distributed_at IS NOT NULL), 0)
    INTO v_to_distribute, v_distributed_n, v_completed_n, v_distributed_q
    FROM public.program_members pm
    JOIN public.cooperative_programs cp ON cp.id = pm.program_id
   WHERE pm.farmer_id = p_farmer_id
     AND cp.program_purpose = 'distribution';

  SELECT COALESCE(sum(ib.sold_kg), 0),
         COALESCE(sum(ib.available_kg + ib.reserved_kg), 0),
         COALESCE(sum(COALESCE(bsl.spoiled_kg, 0)), 0)
    INTO v_sold_q, v_unsold_q, v_rotten_q
    FROM public.program_members pm
    JOIN public.harvest_records hr ON hr.source_program_member_id = pm.id
    JOIN public.inventory_batches ib ON ib.harvest_record_id = hr.id
    LEFT JOIN public.batch_shelf_life bsl ON bsl.batch_id = ib.id
   WHERE pm.farmer_id = p_farmer_id;

  SELECT COALESCE(sum(amount_owed), 0),
         COALESCE(sum(CASE WHEN status = 'paid' THEN amount_owed ELSE 0 END), 0),
         COALESCE(sum(CASE WHEN status = 'unpaid' THEN amount_owed ELSE 0 END), 0)
    INTO v_owed, v_paid, v_unpaid
    FROM public.program_sale_shares
   WHERE farmer_id = p_farmer_id;

  RETURN jsonb_build_object(
    'to_distribute_count', v_to_distribute,
    'distributed_count',   v_distributed_n,
    'completed_count',     v_completed_n,
    'distributed_qty',     round(v_distributed_q, 2),
    'sold_qty',            round(v_sold_q, 2),
    'unsold_qty',          round(v_unsold_q, 2),
    'rotten_qty',          round(v_rotten_q, 2),
    'total_owed',          round(v_owed, 2),
    'total_paid',          round(v_paid, 2),
    'total_unpaid',        round(v_unpaid, 2)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_farmer_distribution_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_farmer_distribution_summary(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_program_share_payment(
  p_share_id UUID,
  p_notes    TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.program_sale_shares%ROWTYPE;
BEGIN
  IF NOT public.has_module_access('dashboard', 'manage') THEN
    RAISE EXCEPTION 'Only the Manager or an Officer with Dashboard Manage access can record program share payments.';
  END IF;

  SELECT * INTO v_row FROM public.program_sale_shares WHERE id = p_share_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Program share record not found.';
  END IF;
  IF v_row.status = 'paid' THEN
    RAISE EXCEPTION 'This cooperative share has already been marked as paid.';
  END IF;

  UPDATE public.program_sale_shares
     SET status = 'paid',
         paid_at = NOW(),
         recorded_by = auth.uid(),
         notes = COALESCE(NULLIF(btrim(p_notes), ''), notes)
   WHERE id = p_share_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_program_share_payment(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_program_share_payment(UUID, TEXT) TO authenticated;

-- Register Officer permission gate for record_program_share_payment
DO $$
BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('rpc', 'record_program_share_payment', 'dashboard')
    ON CONFLICT (kind, name) DO UPDATE SET module = EXCLUDED.module;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
