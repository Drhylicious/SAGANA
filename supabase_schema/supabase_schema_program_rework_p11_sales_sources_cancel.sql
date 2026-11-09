-- ============================================================
-- SAGANA — "Distribute from" categories for Product Sales AND Distribution programs,
--          and purchase cancellation by the Farmer only
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it in the Supabase SQL editor after you have
-- checked it. One transaction, safe to re-run. Needs p5 (program_missing_fields) and
-- the Product Sales / role-based-access scripts you already ran.
--
-- WHAT IT DOES
--   1. cooperative_programs.source_categories  (text[]): the inventory CATEGORIES a
--      program distributes from (several allowed), for BOTH program types. Empty by
--      default. (If an earlier copy of this script already added it as
--      sale_source_categories, that column is renamed: nothing is lost.)
--   2. program_missing_fields(): the program needs at least one source ('sources').
--      A Distribution program that still has a single configured item (older programs)
--      counts as having its source until it is edited. An older program that has
--      neither shows as Incomplete: a Product Sales one stays operational, a
--      Distribution one cannot distribute until it is completed.
--   2b. distribute_program_benefit(): a member can be given any in-stock item from the
--      program's categories (or, for an older program, its configured item). One
--      distribution per member, stock checks and everything else are unchanged.
--   3. A trigger on program_products: a product can only be ADDED from an inventory
--      category the program distributes from. Existing products, prices and the
--      On sale switch are not affected. (The SQL editor, with no signed-in user, is not blocked.)
--   4. cancel_program_purchase(): ONLY the Farmer who made a pending purchase can cancel
--      it. The Manager and Officer can no longer cancel a purchase (the function
--      refuses them). Everything else about it is the same: pending purchases only,
--      the reason is saved, the staff are told.
--
-- STEP 0 — READ THE LIVE FUNCTION FIRST (read-only). The guard below stops the script if
-- the live cancel function is not the version this migration was written against:
--   SELECT pg_get_functiondef('public.cancel_program_purchase(uuid,text)'::regprocedure);
--   SELECT pg_get_functiondef('public.distribute_program_benefit(uuid,uuid,numeric,uuid)'::regprocedure);
--
-- Nothing is deleted. No purchase, product, program or inventory row is changed.
-- New code-prefixed errors: PRODUCT_NOT_IN_SOURCE, NO_STAFF_CANCEL
-- ============================================================

BEGIN;

DO $$
DECLARE v_def TEXT;
BEGIN
  IF to_regprocedure('public.cancel_program_purchase(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'cancel_program_purchase(uuid, text) was not found.';
  END IF;
  v_def := pg_get_functiondef('public.cancel_program_purchase(uuid,text)'::regprocedure);
  IF position('Only a pending purchase can be cancelled' IN v_def) = 0
     OR position('You can only cancel your own purchase' IN v_def) = 0 THEN
    RAISE EXCEPTION 'The live cancel_program_purchase() differs from the version this migration extends; stop and review.';
  END IF;
  v_def := pg_get_functiondef('public.distribute_program_benefit(uuid,uuid,numeric,uuid)'::regprocedure);
  IF position('This program distributes a different item' IN v_def) = 0
     AND position('not in a category this program distributes from' IN v_def) = 0 THEN
    RAISE EXCEPTION 'The live distribute_program_benefit() differs from the version this migration extends; stop and review.';
  END IF;
  IF to_regprocedure('public.program_missing_fields(cooperative_programs)') IS NULL THEN
    RAISE EXCEPTION 'Apply the p5 script first (program_missing_fields).';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. The sources a Product Sales program distributes from
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'cooperative_programs'
                AND column_name = 'sale_source_categories')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'cooperative_programs'
                AND column_name = 'source_categories') THEN
    ALTER TABLE public.cooperative_programs RENAME COLUMN sale_source_categories TO source_categories;
  END IF;
END $$;
ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS source_categories TEXT[] NOT NULL DEFAULT '{}';
COMMENT ON COLUMN public.cooperative_programs.source_categories IS
  'The inventory categories a program distributes from (Product Sales: products are added from them; Distribution: items are given from them).';

-- ════════════════════════════════════════════════════════════
-- 2. Required fields: a Product Sales program needs at least one source
--    (the Phase 5 function plus one line)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.program_missing_fields(p public.cooperative_programs)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN p.program_name IS NULL OR btrim(p.program_name) = ''  THEN 'name' END,
    CASE WHEN p.program_type IS NULL OR btrim(p.program_type) = ''  THEN 'type' END,
    CASE WHEN p.image_url    IS NULL OR btrim(p.image_url)    = ''  THEN 'photo' END,
    CASE WHEN p.description  IS NULL OR btrim(p.description)  = ''  THEN 'description' END,
    CASE WHEN p.budget       IS NULL OR p.budget <= 0               THEN 'budget' END,
    -- Where it distributes from: categories; an older Distribution program with its
    -- single configured item still counts until it is edited.
    CASE WHEN COALESCE(array_length(p.source_categories, 1), 0) = 0
          AND (p.program_purpose = 'sales' OR p.distribution_item_id IS NULL)
                                                                    THEN 'sources' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND p.return_crop_id IS NULL                              THEN 'return_crop' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_quantity IS NULL OR p.return_quantity <= 0) THEN 'return_quantity' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_unit IS NULL OR btrim(p.return_unit) = '')  THEN 'return_unit' END
  ], NULL);
$$;

-- ════════════════════════════════════════════════════════════
-- 3. A product can only be added from a selected source
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.enforce_program_product_source()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_sources TEXT[];
  v_cat     TEXT;
BEGIN
  -- SQL editor / migrations have no signed-in user: not blocked.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT source_categories INTO v_sources FROM cooperative_programs WHERE id = NEW.program_id;
  SELECT category INTO v_cat FROM cooperative_inventory WHERE id = NEW.inventory_item_id;
  IF v_cat IS NULL
     OR NOT EXISTS (SELECT 1 FROM unnest(COALESCE(v_sources, '{}')) s
                     WHERE lower(btrim(s)) = lower(btrim(v_cat))) THEN
    RAISE EXCEPTION 'PRODUCT_NOT_IN_SOURCE: This item is not in a source the program distributes from.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enforce_program_product_source ON public.program_products;
CREATE TRIGGER trg_enforce_program_product_source
  BEFORE INSERT ON public.program_products
  FOR EACH ROW EXECUTE FUNCTION public.enforce_program_product_source();

-- ════════════════════════════════════════════════════════════
-- 3b. Distribution: any item from the program's categories (one per member)
--     (the Phase 1 function, with only the item rule changed)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.distribute_program_benefit(
  p_program_member_id uuid,
  p_inventory_item_id uuid,
  p_quantity numeric,
  p_recorded_by uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_member    program_members%ROWTYPE;
  v_program   cooperative_programs%ROWTYPE;
  v_available NUMERIC;
  v_item_name TEXT;
  v_active    BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can distribute a program benefit';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'The quantity must be greater than zero';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;
  IF v_member.status <> 'active' THEN
    RAISE EXCEPTION 'Only an active member can receive a distribution';
  END IF;
  IF v_member.distributed_at IS NOT NULL THEN
    RAISE EXCEPTION 'This member has already received a distribution';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.program_purpose <> 'distribution' THEN
    RAISE EXCEPTION 'This is not a distribution program';
  END IF;
  -- NEW in Phase 1
  IF v_program.status <> 'active' THEN
    RAISE EXCEPTION 'This program is Completed and no longer distributes items.';
  END IF;
  -- Where it may distribute from: the program's categories (and, for an older
  -- program, its single configured item).
  IF v_program.distribution_item_id IS NULL
     AND COALESCE(array_length(v_program.source_categories, 1), 0) = 0 THEN
    RAISE EXCEPTION 'This program is Incomplete: where it distributes from is not set. Edit the program and choose the categories first.';
  END IF;
  IF p_inventory_item_id IS DISTINCT FROM v_program.distribution_item_id
     AND NOT EXISTS (
       SELECT 1
         FROM cooperative_inventory ci, unnest(COALESCE(v_program.source_categories, '{}')) c
        WHERE ci.id = p_inventory_item_id AND lower(btrim(ci.category)) = lower(btrim(c))) THEN
    RAISE EXCEPTION 'This item is not in a category this program distributes from.';
  END IF;

  SELECT quantity_on_hand, item_name, is_active
    INTO v_available, v_item_name, v_active
    FROM cooperative_inventory
   WHERE id = p_inventory_item_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_item_id;
  END IF;
  IF NOT v_active THEN
    RAISE EXCEPTION '% is archived and cannot be distributed', v_item_name;
  END IF;
  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
      v_item_name, v_available, p_quantity;
  END IF;

  UPDATE cooperative_inventory
     SET quantity_on_hand = quantity_on_hand - p_quantity
   WHERE id = p_inventory_item_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
  ) VALUES (
    p_inventory_item_id, 'program_distribution', -p_quantity, p_program_member_id, 'program', auth.uid()
  );

  UPDATE program_members
     SET inventory_item_id = p_inventory_item_id,
         quantity_given = p_quantity,
         distributed_at = NOW(),
         distributed_item_name = v_item_name
   WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_member.farmer_id, 'program', 'Benefit Distributed',
    'You received ' || p_quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' from your program.',
    FALSE, NOW()
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.distribute_program_benefit(uuid, uuid, numeric, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.distribute_program_benefit(uuid, uuid, numeric, uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. Only the Farmer cancels their own pending purchase
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cancel_program_purchase(p_purchase_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id UUID := auth.uid();
  v_purchase  RECORD;
BEGIN
  -- The Manager and Officer cannot cancel a Farmer's purchase request.
  IF public.is_staff() THEN
    RAISE EXCEPTION 'NO_STAFF_CANCEL: Only the Farmer who made the request can cancel it.';
  END IF;

  SELECT id, farmer_id, status
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF v_purchase.farmer_id <> v_caller_id THEN
    RAISE EXCEPTION 'You can only cancel your own purchase.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be cancelled.';
  END IF;

  UPDATE public.program_product_purchases
    SET status = 'cancelled',
        cancelled_at = NOW(),
        cancel_reason = p_reason
    WHERE id = p_purchase_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ap.user_id, 'program', 'Purchase Cancelled',
         'A farmer cancelled their pending program purchase.',
         FALSE, NOW(), '/admin/programs/purchases'
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');
END;
$function$;
REVOKE ALL ON FUNCTION public.cancel_program_purchase(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_program_purchase(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The column and the trigger exist (expect 1 row each):
--     SELECT column_name FROM information_schema.columns
--      WHERE table_name = 'cooperative_programs' AND column_name = 'source_categories';
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_enforce_program_product_source';
-- V2  Programs with no source (and no single configured item) show 'sources' as missing:
--     SELECT program_name, program_purpose, public.program_missing_fields(cp) FROM cooperative_programs cp;
-- V3  Staff cannot cancel; the function refuses a Manager/Officer (expect true, true):
--     SELECT pg_get_functiondef('public.cancel_program_purchase(uuid,text)'::regprocedure) ILIKE '%NO_STAFF_CANCEL%',
--            pg_get_functiondef('public.cancel_program_purchase(uuid,text)'::regprocedure) ILIKE '%only cancel your own purchase%';
-- V4  Nothing was removed (compare with before):
--     SELECT status, count(*) FROM program_product_purchases GROUP BY 1;
--     SELECT count(*) FROM program_products;
