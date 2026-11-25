-- ============================================================================
-- SAGANA — Remove Harvest Return & Benefit Type; Retain Free Distribution & Product Sales
--
-- FOR YOUR REVIEW — NOT APPLIED. Run manually in Supabase SQL Editor.
-- Wrap in a single transaction so partial state cannot occur.
--
-- WHAT THIS SCRIPT DOES:
--   1. Returns all items previously distributed through Harvest Return programs
--      (`benefit_type = 'revenue_share'`) back to `cooperative_inventory` and
--      records `restock` ledger entries in `inventory_transactions`.
--   2. Removes all Harvest Return programs, member enrollments, outcome reports,
--      return receipts/events, failed-outcome resolutions, redistribution
--      requests, report reminders, and linked history/activity logs without
--      touching unrelated Free Distribution, Product Sales, Inventory, or Loans.
--   3. Drops Harvest Return / Outcome Review tables, triggers, functions, and
--      columns (`benefit_type`, `return_item_id`, `return_quantity`, etc.).
--   4. Updates `program_missing_fields()`, `program_completion_blockers()`,
--      `get_program_history()`, and `get_supply_chain_records()` for the
--      simplified two-purpose Program Management (Free Distribution & Product Sales).
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Return previously distributed Harvest Return items to Cooperative Inventory
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
  v_inv_active BOOLEAN;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cooperative_programs'
      AND column_name = 'benefit_type'
  ) THEN
    FOR r IN
      SELECT pm.id AS member_id,
             pm.inventory_item_id,
             pm.quantity_given,
             cp.id AS program_id,
             cp.program_name
        FROM public.program_members pm
        JOIN public.cooperative_programs cp ON cp.id = pm.program_id
       WHERE cp.benefit_type = 'revenue_share'
         AND pm.distributed_at IS NOT NULL
         AND pm.inventory_item_id IS NOT NULL
         AND COALESCE(pm.quantity_given, 0) > 0
    LOOP
      SELECT is_active INTO v_inv_active
        FROM public.cooperative_inventory
       WHERE id = r.inventory_item_id
         FOR UPDATE;

      IF FOUND THEN
        UPDATE public.cooperative_inventory
           SET quantity_on_hand = quantity_on_hand + r.quantity_given,
               last_restocked_at = NOW(),
               is_active = TRUE,
               archived_at = NULL
         WHERE id = r.inventory_item_id;

        INSERT INTO public.inventory_transactions (
          inventory_id, transaction_type, quantity,
          reference_id, reference_type, notes, recorded_by
        )
        VALUES (
          r.inventory_item_id,
          'restock',
          r.quantity_given,
          r.member_id,
          'harvest_return_cleanup',
          'Returned from removed Harvest Return program: ' || COALESCE(r.program_name, 'Program'),
          auth.uid()
        );
      END IF;
    END LOOP;
  END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Drop Harvest Return & Outcome Review tables first (removes FKs to program_members)
-- ────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_lock_program_benefit_type ON public.cooperative_programs;
DROP TRIGGER IF EXISTS trg_program_members_require_return_quantity ON public.program_members;

DROP TABLE IF EXISTS public.program_return_events CASCADE;
DROP TABLE IF EXISTS public.program_return_receipts CASCADE;
DROP TABLE IF EXISTS public.program_returns CASCADE;
DROP TABLE IF EXISTS public.program_outcome_photos CASCADE;
DROP TABLE IF EXISTS public.program_outcome_reports CASCADE;
DROP TABLE IF EXISTS public.program_failure_resolutions CASCADE;
DROP TABLE IF EXISTS public.program_redistribution_requests CASCADE;
DROP TABLE IF EXISTS public.program_report_reminders CASCADE;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Clean up all Harvest Return records and farmer-member references
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_hr_programs UUID[];
  v_hr_members  UUID[];
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cooperative_programs'
      AND column_name = 'benefit_type'
  ) THEN
    SELECT COALESCE(array_agg(id), '{}'::uuid[])
      INTO v_hr_programs
      FROM public.cooperative_programs
     WHERE benefit_type = 'revenue_share';

    SELECT COALESCE(array_agg(id), '{}'::uuid[])
      INTO v_hr_members
      FROM public.program_members
     WHERE program_id = ANY(v_hr_programs);

    -- Detach any loan requests that referenced a Harvest Return member
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'loan_requests' AND column_name = 'program_member_id'
    ) THEN
      UPDATE public.loan_requests
         SET program_member_id = NULL
       WHERE program_member_id = ANY(v_hr_members);
    END IF;

    -- Remove program-received harvest records created by Harvest Return distributions
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'harvest_records' AND column_name = 'source_program_id'
    ) THEN
      DELETE FROM public.harvest_records
       WHERE source_program_id = ANY(v_hr_programs)
          OR source_program_member_id = ANY(v_hr_members);
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'farmer_crops' AND column_name = 'source_program_id'
    ) THEN
      UPDATE public.farmer_crops
         SET source_program_id = NULL
       WHERE source_program_id = ANY(v_hr_programs);
    END IF;

    -- Temporarily disable delete-guard triggers for this migration only
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'program_assistance_items' AND t.tgname = 'trg_no_delete') THEN
      EXECUTE 'ALTER TABLE public.program_assistance_items DISABLE TRIGGER trg_no_delete';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'program_assistance_requests' AND t.tgname = 'trg_no_delete') THEN
      EXECUTE 'ALTER TABLE public.program_assistance_requests DISABLE TRIGGER trg_no_delete';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'program_members' AND t.tgname = 'trg_protect_program_members_delete') THEN
      EXECUTE 'ALTER TABLE public.program_members DISABLE TRIGGER trg_protect_program_members_delete';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'cooperative_programs' AND t.tgname = 'trg_protect_program_from_delete') THEN
      EXECUTE 'ALTER TABLE public.cooperative_programs DISABLE TRIGGER trg_protect_program_from_delete';
    END IF;

    -- Remove assistance requests tied to Harvest Return members
    IF to_regclass('public.program_assistance_items') IS NOT NULL
       AND to_regclass('public.program_assistance_requests') IS NOT NULL THEN
      DELETE FROM public.program_assistance_items
       WHERE request_id IN (
         SELECT id FROM public.program_assistance_requests
          WHERE program_member_id = ANY(v_hr_members)
       );
      DELETE FROM public.program_assistance_requests
       WHERE program_member_id = ANY(v_hr_members);
    END IF;

    -- Remove Harvest Return enrollment requests, activities, members, and programs
    DELETE FROM public.program_enrollment_requests WHERE program_id = ANY(v_hr_programs);
    IF to_regclass('public.program_activities') IS NOT NULL THEN
      DELETE FROM public.program_activities WHERE program_id = ANY(v_hr_programs);
    END IF;
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'program_members' AND column_name = 'previous_member_id'
    ) THEN
      UPDATE public.program_members
         SET previous_member_id = NULL
       WHERE previous_member_id = ANY(v_hr_members);
    END IF;
    DELETE FROM public.program_members WHERE program_id = ANY(v_hr_programs);

    -- Remove accountability log entries for Harvest Return programs and outcome/return tables
    IF to_regclass('public.admin_activity_log') IS NOT NULL THEN
      DELETE FROM public.admin_activity_log
       WHERE table_name IN (
         'program_returns', 'program_return_receipts', 'program_return_events',
         'program_outcome_reports', 'program_outcome_photos',
         'program_failure_resolutions', 'program_redistribution_requests',
         'program_report_reminders'
       )
          OR (table_name = 'cooperative_programs' AND record_id = ANY(SELECT unnest(v_hr_programs)::text))
          OR (table_name = 'program_members' AND record_id = ANY(SELECT unnest(v_hr_members)::text));
    END IF;

    DELETE FROM public.cooperative_programs WHERE id = ANY(v_hr_programs);

    -- Re-enable delete-guard triggers
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'program_assistance_items' AND t.tgname = 'trg_no_delete') THEN
      EXECUTE 'ALTER TABLE public.program_assistance_items ENABLE TRIGGER trg_no_delete';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'program_assistance_requests' AND t.tgname = 'trg_no_delete') THEN
      EXECUTE 'ALTER TABLE public.program_assistance_requests ENABLE TRIGGER trg_no_delete';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'program_members' AND t.tgname = 'trg_protect_program_members_delete') THEN
      EXECUTE 'ALTER TABLE public.program_members ENABLE TRIGGER trg_protect_program_members_delete';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'cooperative_programs' AND t.tgname = 'trg_protect_program_from_delete') THEN
      EXECUTE 'ALTER TABLE public.cooperative_programs ENABLE TRIGGER trg_protect_program_from_delete';
    END IF;
  END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Drop Harvest Return & Outcome Review RPCs and columns
-- ────────────────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_inventory_return_item_guard ON public.cooperative_inventory;
DROP TRIGGER IF EXISTS trg_lock_program_benefit_type ON public.cooperative_programs;
DROP TRIGGER IF EXISTS trg_lock_program_return_basis ON public.cooperative_programs;
DROP TRIGGER IF EXISTS trg_program_members_require_return_quantity ON public.program_members;
DROP TRIGGER IF EXISTS trg_program_member_return_item_is_given ON public.program_members;
DROP TRIGGER IF EXISTS trg_program_members_snapshot_return_item ON public.program_members;
DROP TRIGGER IF EXISTS trg_program_members_remember_requested_item ON public.program_members;
DROP TRIGGER IF EXISTS trg_close_request_when_round_starts ON public.program_members;

DROP POLICY IF EXISTS "cooperative_inventory: farmer reads items from own enrollments"
  ON public.cooperative_inventory;
CREATE POLICY "cooperative_inventory: farmer reads items from own enrollments"
  ON public.cooperative_inventory FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.program_members pm
      WHERE pm.farmer_id = auth.uid()
        AND pm.inventory_item_id = cooperative_inventory.id
    )
  );

DROP FUNCTION IF EXISTS public._inventory_return_item_guard() CASCADE;
DROP FUNCTION IF EXISTS public.lock_program_benefit_type() CASCADE;
DROP FUNCTION IF EXISTS public._program_members_require_return_quantity() CASCADE;
DROP FUNCTION IF EXISTS public._program_member_return_item_is_given() CASCADE;
DROP FUNCTION IF EXISTS public._program_members_snapshot_return_item() CASCADE;
DROP FUNCTION IF EXISTS public._program_members_remember_requested_item() CASCADE;
DROP FUNCTION IF EXISTS public._close_request_when_round_starts() CASCADE;
DROP FUNCTION IF EXISTS public._program_return_receipt_shelf_life() CASCADE;
DROP FUNCTION IF EXISTS public._program_open_return(uuid, text, numeric, text) CASCADE;
DROP FUNCTION IF EXISTS public._program_open_return(uuid, numeric, text) CASCADE;
DROP FUNCTION IF EXISTS public._program_open_resolution(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_program_outcome_reports(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_outcome_reports() CASCADE;
DROP FUNCTION IF EXISTS public.submit_program_outcome_report(uuid, text, text, date, date, numeric, text, numeric, text, text, date, text[]) CASCADE;
DROP FUNCTION IF EXISTS public.review_program_outcome(uuid, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.verify_program_outcome(uuid, text, numeric, text, date, text, text[]) CASCADE;
DROP FUNCTION IF EXISTS public.finalize_program_outcome(uuid, text, text, numeric, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.get_program_returns(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_program_returns() CASCADE;
DROP FUNCTION IF EXISTS public.record_program_return_receipt(uuid, numeric, text) CASCADE;
DROP FUNCTION IF EXISTS public.adjust_program_return(uuid, numeric, text) CASCADE;
DROP FUNCTION IF EXISTS public.close_program_return(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.get_failed_resolutions(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.record_failed_resolution(uuid, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.request_program_redistribution(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.approve_program_redistribution(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.redistribute_program_member(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.set_member_return_arrangement(uuid, uuid, numeric) CASCADE;
DROP FUNCTION IF EXISTS public.remind_program_report(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_farmer_programs_view(uuid) CASCADE;

ALTER TABLE public.cooperative_inventory
  DROP COLUMN IF EXISTS return_item_id CASCADE;

ALTER TABLE public.cooperative_programs
  DROP COLUMN IF EXISTS benefit_type CASCADE,
  DROP COLUMN IF EXISTS expected_return_percent CASCADE,
  DROP COLUMN IF EXISTS return_crop_id CASCADE,
  DROP COLUMN IF EXISTS return_quantity CASCADE,
  DROP COLUMN IF EXISTS return_unit CASCADE,
  DROP COLUMN IF EXISTS return_item_id CASCADE;

ALTER TABLE public.program_members
  DROP COLUMN IF EXISTS return_item_id CASCADE,
  DROP COLUMN IF EXISTS return_quantity CASCADE,
  DROP COLUMN IF EXISTS amount_returned CASCADE,
  DROP COLUMN IF EXISTS settled_at CASCADE,
  DROP COLUMN IF EXISTS distribution_outcome CASCADE,
  DROP COLUMN IF EXISTS outcome_recorded_at CASCADE,
  DROP COLUMN IF EXISTS converted_loan_id CASCADE,
  DROP COLUMN IF EXISTS round_no CASCADE,
  DROP COLUMN IF EXISTS requested_item_id CASCADE,
  DROP COLUMN IF EXISTS previous_member_id CASCADE;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Update remaining Program & Supply Chain functions
-- ────────────────────────────────────────────────────────────────────────────
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
    CASE WHEN COALESCE(array_length(p.source_categories, 1), 0) = 0
          AND (p.program_purpose = 'sales' OR p.distribution_item_id IS NULL)
                                                                    THEN 'sources' END
  ], NULL);
$$;

CREATE OR REPLACE FUNCTION public.program_completion_blockers(p_program_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_orders   integer := 0;
  v_stock    integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'sales' THEN
    SELECT count(*) INTO v_orders
      FROM program_product_purchases p
     WHERE p.program_id = p_program_id
       AND p.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered');
    SELECT count(*) INTO v_stock
      FROM program_products pp
     WHERE pp.program_id = p_program_id AND pp.stock_allocated > 0;
  END IF;

  RETURN jsonb_build_object(
    'open_orders',     v_orders,
    'allocated_stock', v_stock
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_program_history(p_program_id uuid)
RETURNS TABLE (
  out_at       timestamptz,
  out_type     text,
  out_actor    text,
  out_role     text,
  out_subject  text,
  out_details  jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can read a program history';
  END IF;

  RETURN QUERY
  WITH
  prog AS (SELECT * FROM cooperative_programs WHERE id = p_program_id),
  mem AS (
    SELECT pm.id, pm.enrolled_at, pm.farmer_id, ui.full_name
    FROM program_members pm
    LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
    WHERE pm.program_id = p_program_id
  ),
  act AS (SELECT a.id FROM program_activities a WHERE a.program_id = p_program_id),
  trail AS (
    SELECT l.* FROM admin_activity_log l
    WHERE l.source = 'db'
      AND (
        (l.table_name = 'cooperative_programs' AND l.record_id = p_program_id::text)
        OR (l.table_name = 'program_members'
            AND (l.record_id IN (SELECT m.id::text FROM mem m)
                 OR l.new_values ->> 'program_id' = p_program_id::text
                 OR l.old_values ->> 'program_id' = p_program_id::text))
        OR (l.table_name = 'program_activities'
            AND (l.record_id IN (SELECT a.id::text FROM act a)
                 OR l.new_values ->> 'program_id' = p_program_id::text
                 OR l.old_values ->> 'program_id' = p_program_id::text))
      )
  )

  SELECT p.created_at, 'program_created'::text, ui.full_name, ur.role, NULL::text,
         jsonb_build_object('name', p.program_name)
  FROM prog p
  LEFT JOIN user_information ui ON ui.user_id = p.created_by
  LEFT JOIN LATERAL (
    SELECT role FROM user_roles WHERE user_id = p.created_by LIMIT 1
  ) ur ON TRUE

  UNION ALL
  SELECT t.created_at, 'program_updated'::text, t.user_name, t.user_role, NULL::text,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t
  WHERE t.table_name = 'cooperative_programs' AND t.action_type = 'updated'

  UNION ALL
  SELECT r.created_at, 'enrollment_requested'::text, f.full_name, 'farmer'::text, f.full_name, '{}'::jsonb
  FROM program_enrollment_requests r
  LEFT JOIN user_information f ON f.user_id = r.farmer_id
  WHERE r.program_id = p_program_id

  UNION ALL
  SELECT r.reviewed_at, 'enrollment_declined'::text, ui.full_name, ur.role, f.full_name,
         jsonb_build_object('notes', r.admin_notes)
  FROM program_enrollment_requests r
  LEFT JOIN user_information f ON f.user_id = r.farmer_id
  LEFT JOIN user_information ui ON ui.user_id = r.reviewed_by
  LEFT JOIN LATERAL (
    SELECT role FROM user_roles WHERE user_id = r.reviewed_by LIMIT 1
  ) ur ON TRUE
  WHERE r.program_id = p_program_id AND r.status = 'rejected' AND r.reviewed_at IS NOT NULL

  UNION ALL
  SELECT m.enrolled_at, 'member_enrolled'::text, ui.full_name, ur.role, m.full_name, '{}'::jsonb
  FROM mem m
  LEFT JOIN LATERAL (
    SELECT user_name, user_role FROM trail t
    WHERE t.table_name = 'program_members' AND t.record_id = m.id::text AND t.action_type = 'created'
    ORDER BY t.created_at LIMIT 1
  ) t_ins ON TRUE
  LEFT JOIN program_enrollment_requests er
    ON er.program_id = p_program_id AND er.farmer_id = m.farmer_id AND er.status = 'approved'
  LEFT JOIN user_information ui ON ui.user_id = er.reviewed_by
  LEFT JOIN LATERAL (
    SELECT role FROM user_roles WHERE user_id = er.reviewed_by LIMIT 1
  ) ur ON TRUE

  UNION ALL
  SELECT t.created_at, 'benefit_distributed'::text, t.user_name, t.user_role, m.full_name,
         jsonb_build_object('quantity', t.new_values -> 'quantity_given', 'item', t.new_values -> 'distributed_item_name')
  FROM trail t
  LEFT JOIN mem m ON m.id::text = t.record_id
  WHERE t.table_name = 'program_members' AND t.action_type = 'updated'
    AND t.old_values ->> 'distributed_at' IS NULL
    AND t.new_values ->> 'distributed_at' IS NOT NULL

  UNION ALL
  SELECT t.created_at, 'activity_' || t.action_type, t.user_name, t.user_role,
         COALESCE(t.new_values ->> 'title', t.old_values ->> 'title'),
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t
  WHERE t.table_name = 'program_activities'

  ORDER BY 1 DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_history(uuid) TO authenticated;

-- Update Supply Chain read model so it no longer references dropped program_returns / program_return_receipts
DO $$
DECLARE
  v_fn_name text;
  v_sql     text;
BEGIN
  IF to_regprocedure('public._supply_chain_records_base(timestamptz,timestamptz)') IS NOT NULL THEN
    v_fn_name := 'public._supply_chain_records_base';
  ELSE
    v_fn_name := 'public.get_supply_chain_records';
  END IF;

  v_sql := format($fmt$
CREATE OR REPLACE FUNCTION %s(
  p_from timestamptz DEFAULT NULL,
  p_to   timestamptz DEFAULT NULL
)
RETURNS TABLE (
  record_key         text,
  stage              text,
  record_type        text,
  direction          text,
  occurred_at        timestamptz,
  is_confirmed       boolean,
  item_name          text,
  category           text,
  quantity           numeric,
  unit               text,
  inventory_id       uuid,
  item_source        text,
  from_name          text,
  from_role          text,
  to_name            text,
  to_role            text,
  farmer_name        text,
  program_name       text,
  reference_label    text,
  batch_number       text,
  fulfillment_method text,
  fulfillment_status text,
  ref_type           text,
  ref_id             uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
WITH
nm AS (
  SELECT user_id, full_name FROM user_information
),
rl AS (
  SELECT DISTINCT ON (user_id) user_id, role FROM user_roles ORDER BY user_id, role
),
io AS (
  SELECT ci.id, ci.item_name, ci.category, ci.unit,
         COALESCE(f.full_name, NULLIF(btrim(ci.source), '')) AS origin,
         (ci.source_farmer_id IS NOT NULL)                   AS from_farmer
    FROM cooperative_inventory ci
    LEFT JOIN nm f ON f.user_id = ci.source_farmer_id
),
rec AS (
  -- 1. SUPPLIER / INVENTORY SOURCE
  SELECT 'tx:' || t.id::text, 'source', 'inventory_restock', 'incoming',
         t.created_at, TRUE,
         io.item_name, io.category, abs(t.quantity)::numeric, io.unit, io.id, io.origin,
         io.origin,
         CASE WHEN io.from_farmer THEN 'farmer' ELSE 'supplier' END,
         NULL::text, 'cooperative',
         CASE WHEN io.from_farmer THEN io.origin END,
         NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
         'inventory_transaction', t.id
    FROM inventory_transactions t
    JOIN io ON io.id = t.inventory_id
   WHERE t.transaction_type = 'restock'
     AND t.quantity > 0
     AND COALESCE(t.reference_type, 'manual') NOT IN ('program_return', 'cooperative_offer')

  UNION ALL
  -- 2. PROGRAM: a benefit distributed to a member (Free Distribution)
  SELECT 'dist:' || pm.id::text, 'program', 'program_distribution', 'outgoing',
         pm.distributed_at, TRUE,
         COALESCE(pm.distributed_item_name, io.item_name), io.category,
         pm.quantity_given::numeric, COALESCE(pm.distributed_unit, io.unit),
         pm.inventory_item_id, io.origin,
         NULL::text, 'cooperative',
         f.full_name, 'farmer',
         CASE WHEN io.from_farmer THEN io.origin END,
         cp.program_name,
         NULL::text, NULL::text, NULL::text, NULL::text,
         'program_member', pm.id
    FROM program_members pm
    JOIN cooperative_programs cp ON cp.id = pm.program_id
    LEFT JOIN io ON io.id = pm.inventory_item_id
    LEFT JOIN nm f ON f.user_id = pm.farmer_id
   WHERE pm.distributed_at IS NOT NULL
     AND COALESCE(pm.quantity_given, 0) > 0

  UNION ALL
  -- 3. SUCCESSFUL COOPERATIVE PURCHASE
  SELECT 'offer:' || o.id::text, 'offer', 'cooperative_purchase', 'incoming',
         b.received_at, TRUE,
         io.item_name, io.category, b.original_quantity::numeric, b.unit,
         b.inventory_id, io.origin,
         COALESCE(b.source_farmer_name, f.full_name), 'farmer',
         NULL::text, 'cooperative',
         COALESCE(b.source_farmer_name, f.full_name),
         NULL::text,
         'OFFER-' || upper(left(replace(o.id::text, '-', ''), 8)),
         b.source_batch_number, NULL::text, o.status,
         'cooperative_offer', o.id
    FROM cooperative_harvest_batches b
    JOIN cooperative_purchase_offers o ON o.id = b.offer_id
    JOIN io ON io.id = b.inventory_id
    LEFT JOIN nm f ON f.user_id = o.farmer_id

  UNION ALL
  -- 4a. FINAL CONSUMER: Cooperative Product order
  SELECT 'coop-order:' || p.id::text, 'consumer', 'cooperative_sale', 'outgoing',
         COALESCE(p.completed_at, p.requested_at), (p.status = 'completed'),
         COALESCE(p.item_name, io.item_name), io.category,
         p.quantity::numeric, COALESCE(p.unit, io.unit),
         pp.inventory_item_id, io.origin,
         NULL::text, 'cooperative',
         f.full_name, 'farmer',
         CASE WHEN io.from_farmer THEN io.origin END,
         COALESCE(p.program_name, cp.program_name),
         p.order_number, NULL::text,
         p.fulfillment_method, p.status,
         'program_purchase', p.id
    FROM program_product_purchases p
    JOIN program_products pp ON pp.id = p.product_id
    LEFT JOIN io ON io.id = pp.inventory_item_id
    LEFT JOIN cooperative_programs cp ON cp.id = p.program_id
    LEFT JOIN nm f ON f.user_id = p.farmer_id
   WHERE p.status <> 'cancelled'

  UNION ALL
  -- 4b. FINAL CONSUMER: Farmer Marketplace order
  SELECT 'order:' || o.id::text, 'consumer', 'marketplace_sale', 'outgoing',
         COALESCE(o.received_at, o.created_at), (o.status = 'completed'),
         l.crop_name,
         (SELECT cm.category FROM crop_master cm WHERE lower(cm.crop_name) = lower(l.crop_name) LIMIT 1),
         o.quantity_kg::numeric, COALESCE(NULLIF(o.unit, ''), 'kg'),
         NULL::uuid, sf.full_name,
         sf.full_name, 'farmer',
         bf.full_name, COALESCE(rl.role::text, 'buyer'),
         sf.full_name,
         NULL::text,
         o.order_number, ib.batch_number,
         COALESCE(o.fulfillment_method, 'pickup'), o.status,
         'order', o.id
    FROM orders o
    JOIN marketplace_listings l ON l.id = o.listing_id
    LEFT JOIN inventory_batches ib ON ib.id = l.inventory_batch_id
    LEFT JOIN nm sf ON sf.user_id = l.farmer_id
    LEFT JOIN nm bf ON bf.user_id = o.buyer_id
    LEFT JOIN rl ON rl.user_id = o.buyer_id
   WHERE o.status NOT IN ('cancelled', 'rejected')

  UNION ALL
  -- 5. OTHER: inventory items issued to a Farmer on a loan
  SELECT 'tx:' || t.id::text, 'other', 'loan_issue', 'outgoing',
         t.created_at, TRUE,
         io.item_name, io.category, abs(t.quantity)::numeric, io.unit, io.id, io.origin,
         NULL::text, 'cooperative',
         f.full_name, 'farmer',
         CASE WHEN io.from_farmer THEN io.origin END,
         NULL::text,
         fl.reference_no, NULL::text, NULL::text, NULL::text,
         'loan', fl.id
    FROM inventory_transactions t
    JOIN farmer_loans fl ON fl.id = t.reference_id
    JOIN io ON io.id = t.inventory_id
    LEFT JOIN nm f ON f.user_id = fl.farmer_id
   WHERE t.transaction_type = 'loan_issued'
     AND t.reference_type = 'loan'
)
SELECT r.*
  FROM rec AS r(record_key, stage, record_type, direction, occurred_at, is_confirmed,
                item_name, category, quantity, unit, inventory_id, item_source,
                from_name, from_role, to_name, to_role, farmer_name, program_name,
                reference_label, batch_number, fulfillment_method, fulfillment_status,
                ref_type, ref_id)
 WHERE public.is_staff()
   AND (p_from IS NULL OR r.occurred_at >= p_from)
   AND (p_to   IS NULL OR r.occurred_at <  p_to)
 ORDER BY r.occurred_at DESC, r.record_key;
$body$;
$fmt$, v_fn_name);

  EXECUTE v_sql;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
