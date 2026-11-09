-- ============================================================
-- SAGANA — Unified purchasing m06: when can a Product Sales program be completed?
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after m04.
--
-- WHAT CHANGES (Product Sales programs only)
--   A program cannot be completed while
--     * any of its orders is still open (Pending, Approved, Ready for Pickup, Out for Delivery,
--       or handed over and awaiting the Farmer's confirmation), or
--     * any stock is still set aside for it (stock_allocated > 0). The Manager sells it, or uses
--       "Release stock" to give the unsold part back to the cooperative's general stock.
--   Stock that is NOT set aside for the program (shared inventory) never blocks completion.
--   Orders are never cancelled automatically. Programs are never deleted.
--
-- The old blockers "active products" and "pending purchases" are replaced by the two above.
-- Distribution programs are unchanged. complete_program() already refuses when any blocker is
-- above zero, so the rule is enforced by the database, not only by the screen. Completing still
-- closes the program's pending join requests (recorded, with a notice to each Farmer).
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'program_products' AND column_name = 'stock_allocated') THEN
    RAISE EXCEPTION 'Run m04 first (program_products.stock_allocated is missing).';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.program_completion_blockers(p_program_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_await    integer := 0;
  v_returns  integer := 0;
  v_orders   integer := 0;
  v_stock    integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'distribution' THEN
    SELECT count(*) INTO v_await
      FROM program_members m
     WHERE m.program_id = p_program_id
       AND m.status = 'active'
       AND m.distributed_at IS NOT NULL
       AND COALESCE(m.distribution_outcome, 'pending') NOT IN ('thriving', 'failed');
    SELECT count(*) INTO v_returns
      FROM program_returns r
     WHERE r.program_id = p_program_id AND r.status IN ('pending', 'partial');
  ELSE
    SELECT count(*) INTO v_orders
      FROM program_product_purchases p
     WHERE p.program_id = p_program_id
       AND p.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered');
    SELECT count(*) INTO v_stock
      FROM program_products pp
     WHERE pp.program_id = p_program_id AND pp.stock_allocated > 0;
  END IF;

  RETURN jsonb_build_object(
    'awaiting_outcome',  v_await,
    'open_returns',      v_returns,
    'open_orders',       v_orders,
    'allocated_stock',   v_stock
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  What blocks each active program today (Peanut Cookies: its allocated stock and open order):
--     SELECT cp.program_name, public.program_completion_blockers(cp.id)
--       FROM cooperative_programs cp WHERE cp.status = 'active' AND cp.program_purpose = 'sales';
-- V2  A program with open orders or allocated stock cannot be completed (expect PROGRAM_NOT_READY):
--     -- run complete_program('<id>') from the app as the Manager.
