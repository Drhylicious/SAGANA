-- PHASE 2: Cooperative Harvest Inventory Integration.
-- MANUAL migration. Run preflight first; see COOPERATIVE_HARVEST_PHASE2.md.
-- Requires Phase 1 farmer_stock_management, inventory_source, crop_master,
-- harvest_batch_number_and_units, loan_inventory_link and product sales.
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.confirm_cooperative_offer_receipt(uuid,text)') IS NULL
     OR to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'Apply the current Phase 1 receipt workflow first.';
  END IF;
END $$;

-- Block receipt writes during backfill; use the receipt's lock order.
LOCK TABLE public.cooperative_purchase_offers IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.cooperative_inventory IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.inventory_transactions IN ACCESS EXCLUSIVE MODE;

ALTER TABLE public.cooperative_inventory
  ADD COLUMN IF NOT EXISTS source_farmer_id uuid,
  ADD COLUMN IF NOT EXISTS source_crop_id uuid,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;
-- Snapshot identifiers deliberately survive deletion of a user/crop account.
CREATE UNIQUE INDEX IF NOT EXISTS cooperative_harvest_identity
  ON public.cooperative_inventory(source_farmer_id, source_crop_id, lower(btrim(unit)))
  WHERE source_farmer_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.cooperative_harvest_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_id uuid NOT NULL REFERENCES public.cooperative_inventory(id) ON DELETE RESTRICT,
  offer_id uuid UNIQUE,
  source_farmer_id uuid,
  source_farmer_name text,
  source_crop_id uuid,
  source_batch_id uuid,
  source_batch_number text,
  source_transaction_id uuid,
  inventory_transaction_id uuid NOT NULL UNIQUE,
  original_quantity numeric(12,2) NOT NULL CHECK(original_quantity > 0),
  unit text NOT NULL,
  harvest_date date,
  storage_location text,
  received_at timestamptz NOT NULL DEFAULT now(),
  recorded_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cooperative_batch_transaction_fk FOREIGN KEY(inventory_transaction_id)
    REFERENCES public.inventory_transactions(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX IF NOT EXISTS cooperative_harvest_batches_item ON public.cooperative_harvest_batches(inventory_id, received_at, id);

CREATE TABLE IF NOT EXISTS public.cooperative_inventory_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_id uuid NOT NULL REFERENCES public.cooperative_inventory(id) ON DELETE RESTRICT,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  action text NOT NULL,
  actor_id uuid,
  actor_name text,
  source_farmer_id uuid,
  source_farmer_name text,
  quantity_change numeric(12,2),
  unit text NOT NULL,
  batch_id uuid REFERENCES public.cooperative_harvest_batches(id) ON DELETE RESTRICT,
  transaction_id uuid UNIQUE,
  reference_id uuid,
  reference_type text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS cooperative_inventory_history_item ON public.cooperative_inventory_history(inventory_id, occurred_at DESC, id);

-- A request ID is stable across a timed-out retry, and bound to its exact payload.
CREATE TABLE IF NOT EXISTS public.cooperative_stock_requests (
  request_id uuid PRIMARY KEY,
  inventory_id uuid NOT NULL REFERENCES public.cooperative_inventory(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL,
  payload jsonb NOT NULL,
  resulting_quantity numeric(12,2) NOT NULL
);

ALTER TABLE public.cooperative_harvest_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cooperative_inventory_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cooperative_stock_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_read ON public.cooperative_harvest_batches;
CREATE POLICY staff_read ON public.cooperative_harvest_batches FOR SELECT TO authenticated USING(public.is_staff());
DROP POLICY IF EXISTS staff_read ON public.cooperative_inventory_history;
CREATE POLICY staff_read ON public.cooperative_inventory_history FOR SELECT TO authenticated USING(public.is_staff());
REVOKE ALL ON public.cooperative_harvest_batches, public.cooperative_inventory_history, public.cooperative_stock_requests FROM anon, authenticated;
GRANT SELECT ON public.cooperative_harvest_batches, public.cooperative_inventory_history TO authenticated;

CREATE OR REPLACE FUNCTION public._coop_person_name(p_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT full_name FROM user_information WHERE user_id = p_id;
$$;
REVOKE ALL ON FUNCTION public._coop_person_name(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._coop_immutable_record() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'Cooperative receipt batches and audit history are immutable.';
END $$;
DROP TRIGGER IF EXISTS immutable ON public.cooperative_harvest_batches;
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON public.cooperative_harvest_batches
  FOR EACH ROW EXECUTE FUNCTION public._coop_immutable_record();
DROP TRIGGER IF EXISTS immutable ON public.cooperative_inventory_history;
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON public.cooperative_inventory_history
  FOR EACH ROW EXECUTE FUNCTION public._coop_immutable_record();

-- Identity is authoritative on the server. The advisory lock also protects
-- name-based manual creates without silently merging pre-existing supply rows.
CREATE OR REPLACE FUNCTION public._coop_inventory_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Archive inventory with delete_inventory_item; history must be retained.';
  END IF;
  IF TG_OP = 'INSERT' OR NEW.item_name IS DISTINCT FROM OLD.item_name THEN
    IF NEW.source_farmer_id IS NULL THEN
      PERFORM pg_advisory_xact_lock(hashtextextended(lower(btrim(NEW.item_name)), 20));
      IF EXISTS (SELECT 1 FROM cooperative_inventory WHERE id <> NEW.id
        AND source_farmer_id IS NULL AND archived_at IS NULL
        AND lower(btrim(item_name)) = lower(btrim(NEW.item_name))) THEN
        RAISE EXCEPTION 'An inventory item with this name already exists.';
      END IF;
    END IF;
  END IF;
  IF NEW.source_farmer_id IS NOT NULL AND (NEW.source_crop_id IS NULL OR NEW.category <> 'Harvest Stock') THEN
    RAISE EXCEPTION 'Farmer harvest stock requires a crop identity and Harvest Stock category.';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.source_farmer_id IS NOT NULL AND
     (NEW.source_farmer_id, NEW.source_crop_id, NEW.unit, NEW.item_name, NEW.category, NEW.source)
     IS DISTINCT FROM (OLD.source_farmer_id, OLD.source_crop_id, OLD.unit, OLD.item_name, OLD.category, OLD.source) THEN
    RAISE EXCEPTION 'The source Farmer, crop and unit of received harvest cannot be edited.';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.unit, NEW.category) IS DISTINCT FROM (OLD.unit, OLD.category)
     AND EXISTS(SELECT 1 FROM cooperative_harvest_batches WHERE inventory_id=OLD.id) THEN
    RAISE EXCEPTION 'An item with harvest batches must retain its category and unit.';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.archived_at IS NOT NULL AND NEW.archived_at IS NOT NULL
     AND (NEW.quantity_on_hand, NEW.quantity_reserved, NEW.is_active)
       IS DISTINCT FROM (OLD.quantity_on_hand, OLD.quantity_reserved, OLD.is_active) THEN
    RAISE EXCEPTION 'Archived inventory cannot be changed.';
  END IF;
  -- Invoker trigger: direct API writes cannot bypass the row-locked stock RPC.
  IF current_user IN ('authenticated', 'anon') AND (
    (TG_OP = 'INSERT' AND (NEW.quantity_on_hand <> 0 OR NEW.quantity_reserved <> 0 OR NEW.source_farmer_id IS NOT NULL))
    OR (TG_OP = 'UPDATE' AND (NEW.quantity_on_hand, NEW.quantity_reserved, NEW.source_farmer_id, NEW.source_crop_id, NEW.archived_at)
      IS DISTINCT FROM (OLD.quantity_on_hand, OLD.quantity_reserved, OLD.source_farmer_id, OLD.source_crop_id, OLD.archived_at))
  ) THEN
    RAISE EXCEPTION 'Use the authorized cooperative stock RPC.';
  END IF;
  RETURN NEW;
END $$;

-- Metadata and catalog events complement the existing stock transaction ledger.
CREATE OR REPLACE FUNCTION public._coop_inventory_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a text; before_data jsonb := '{}'::jsonb; after_data jsonb;
BEGIN
  after_data := to_jsonb(NEW) - ARRAY['updated_at','quantity_on_hand','quantity_reserved','last_restocked_at'];
  IF TG_OP = 'INSERT' THEN a := 'created';
  ELSE
    before_data := to_jsonb(OLD) - ARRAY['updated_at','quantity_on_hand','quantity_reserved','last_restocked_at'];
    IF before_data = after_data THEN RETURN NEW; END IF;
    a := CASE WHEN OLD.archived_at IS NULL AND NEW.archived_at IS NOT NULL THEN 'archived'
              WHEN OLD.archived_at IS NOT NULL AND NEW.archived_at IS NULL THEN 'restored'
              ELSE 'edited' END;
  END IF;
  INSERT INTO cooperative_inventory_history(inventory_id, action, actor_id, actor_name,
    source_farmer_id, source_farmer_name, unit, details)
  VALUES(NEW.id, a, auth.uid(), public._coop_person_name(auth.uid()), NEW.source_farmer_id,
    CASE WHEN NEW.source_farmer_id IS NOT NULL THEN NEW.source END, NEW.unit,
    jsonb_build_object('before', before_data, 'after', after_data));
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._coop_transaction_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i cooperative_inventory; b cooperative_harvest_batches; actor uuid;
BEGIN
  SELECT * INTO i FROM cooperative_inventory WHERE id = NEW.inventory_id;
  SELECT * INTO b FROM cooperative_harvest_batches WHERE inventory_transaction_id = NEW.id;
  actor := COALESCE(auth.uid(), NEW.recorded_by);
  INSERT INTO cooperative_inventory_history(inventory_id, occurred_at, action, actor_id, actor_name,
    source_farmer_id, source_farmer_name, quantity_change, unit, batch_id, transaction_id,
    reference_id, reference_type, details)
  VALUES(i.id, NEW.created_at, NEW.transaction_type, actor, public._coop_person_name(actor),
    i.source_farmer_id, COALESCE(b.source_farmer_name, CASE WHEN i.source_farmer_id IS NOT NULL THEN i.source END),
    NEW.quantity, i.unit, b.id, NEW.id, NEW.reference_id, NEW.reference_type,
    jsonb_build_object('notes', NEW.notes));
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._coop_catalog_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r jsonb; prev jsonb; i cooperative_inventory; enabled boolean; was_enabled boolean; flag text;
BEGIN
  r := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  flag := CASE WHEN TG_TABLE_NAME = 'loan_items_master' THEN 'is_loan_eligible' ELSE 'is_available' END;
  enabled := TG_OP <> 'DELETE' AND COALESCE((r->>flag)::boolean, false);
  IF TG_OP = 'UPDATE' THEN
    prev := to_jsonb(OLD);
    IF prev->>'inventory_item_id' IS DISTINCT FROM r->>'inventory_item_id' THEN
      RAISE EXCEPTION 'Unpublish and create a new catalog link to change the inventory item.';
    END IF;
    was_enabled := COALESCE((prev->>flag)::boolean, false);
    IF enabled = was_enabled THEN RETURN NEW; END IF;
  END IF;
  SELECT * INTO i FROM cooperative_inventory WHERE id = (r->>'inventory_item_id')::uuid;
  IF NOT FOUND THEN RETURN COALESCE(NEW, OLD); END IF;
  IF enabled AND (i.archived_at IS NOT NULL OR NOT i.is_active) THEN
    RAISE EXCEPTION 'Archived inventory cannot be published.';
  END IF;
  INSERT INTO cooperative_inventory_history(inventory_id, action, actor_id, actor_name,
    source_farmer_id, source_farmer_name, unit, reference_id, reference_type)
  VALUES(i.id, CASE WHEN enabled THEN 'published' ELSE 'unpublished' END,
    auth.uid(), public._coop_person_name(auth.uid()), i.source_farmer_id,
    CASE WHEN i.source_farmer_id IS NOT NULL THEN i.source END, i.unit, (r->>'id')::uuid, TG_TABLE_NAME);
  RETURN COALESCE(NEW, OLD);
END $$;

-- Internal transfer: a completed receipt, row lock + unique offer key + unique
-- Farmer/crop/unit key make retries and simultaneous receipts safe.
CREATE OR REPLACE FUNCTION public._coop_receive_harvest(p_offer_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o cooperative_purchase_offers; b inventory_batches; h harvest_records;
  crop uuid; item uuid; tx uuid; old_item uuid; farmer_name text; u text;
BEGIN
  SELECT * INTO o FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND OR o.status <> 'completed' OR o.received_at IS NULL OR o.received_by IS NULL
     OR o.member_sales_transaction_id IS NULL THEN
    RAISE EXCEPTION 'A completed offer with confirmed physical receipt and sale is required.';
  END IF;
  SELECT inventory_id INTO item FROM cooperative_harvest_batches WHERE offer_id = o.id;
  IF FOUND THEN RETURN item; END IF;
  SELECT * INTO b FROM inventory_batches WHERE id = o.inventory_batch_id;
  SELECT * INTO h FROM harvest_records WHERE id = b.harvest_record_id;
  SELECT crop_master_id INTO crop FROM farmer_crops WHERE id = b.crop_id;
  IF crop IS NULL OR b.farmer_id IS DISTINCT FROM o.farmer_id OR h.id IS NULL THEN
    RAISE EXCEPTION 'The source harvest and crop identity must be resolved before transfer.';
  END IF;
  farmer_name := public._coop_person_name(o.farmer_id);
  IF NULLIF(btrim(farmer_name), '') IS NULL THEN RAISE EXCEPTION 'Source Farmer name is missing.'; END IF;
  IF o.confirmed_quantity_kg IS NULL OR o.confirmed_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Received quantity must be positive.';
  END IF;
  u := lower(btrim(COALESCE(NULLIF(o.unit, ''), 'kg')));
  SELECT id, inventory_id INTO tx, old_item FROM inventory_transactions
    WHERE reference_id = o.id AND reference_type = 'cooperative_offer' AND transaction_type = 'harvest_received';
  tx := COALESCE(tx, gen_random_uuid());
  INSERT INTO cooperative_inventory(item_name, category, unit, source, source_farmer_id, source_crop_id, created_by)
  VALUES(o.crop_name, 'Harvest Stock', u, farmer_name, o.farmer_id, crop, o.received_by)
  ON CONFLICT (source_farmer_id, source_crop_id, lower(btrim(unit))) WHERE source_farmer_id IS NOT NULL
  DO UPDATE SET is_active = true, archived_at = NULL
  RETURNING id INTO item;
  INSERT INTO cooperative_harvest_batches(inventory_id, offer_id, source_farmer_id, source_farmer_name,
    source_crop_id, source_batch_id, source_batch_number, source_transaction_id, inventory_transaction_id,
    original_quantity, unit, harvest_date, storage_location, received_at, recorded_by)
  VALUES(item, o.id, o.farmer_id, farmer_name, crop, b.id, b.batch_number, o.member_sales_transaction_id,
    tx, o.confirmed_quantity_kg, u, h.harvest_date, h.storage_location, o.received_at, o.received_by);
  UPDATE cooperative_inventory SET quantity_on_hand = quantity_on_hand + o.confirmed_quantity_kg,
    last_restocked_at = o.received_at WHERE id = item;
  IF old_item IS NOT NULL THEN
    -- Migration only: preserve the original transaction ID and timestamp,
    -- relocate its ownership, and remove exactly the same quantity from its pool.
    UPDATE cooperative_inventory SET quantity_on_hand = quantity_on_hand - o.confirmed_quantity_kg WHERE id = old_item;
    UPDATE inventory_transactions SET inventory_id = item WHERE id = tx;
  ELSE
    INSERT INTO inventory_transactions(id, inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by)
    VALUES(tx, item, 'harvest_received', o.confirmed_quantity_kg, o.id, 'cooperative_offer', o.received_by);
  END IF;
  RETURN item;
END $$;
REVOKE ALL ON FUNCTION public._coop_receive_harvest(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._coop_completed_transfer() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item uuid;
BEGIN
  item := public._coop_receive_harvest(NEW.id);
  UPDATE cooperative_purchase_offers SET coop_inventory_id = item WHERE id = NEW.id;
  RETURN NEW;
END $$;

-- Manual adjustments retain the original batches. Only genuine additions make
-- another batch. A stock deduction cannot consume reserved stock or floor at zero.
CREATE OR REPLACE FUNCTION public.adjust_cooperative_stock(
  p_inventory_id uuid, p_quantity numeric, p_transaction_type text, p_request_id uuid,
  p_notes text DEFAULT NULL, p_harvest_date date DEFAULT NULL, p_storage_location text DEFAULT NULL
) RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i cooperative_inventory; request cooperative_stock_requests; payload jsonb;
  tx uuid := gen_random_uuid(); result numeric;
BEGIN
  IF NOT public.is_staff() THEN RAISE EXCEPTION 'Only cooperative staff can adjust stock.'; END IF;
  IF p_request_id IS NULL OR p_quantity IS NULL OR p_quantity = 0 OR p_quantity::text IN ('NaN','Infinity','-Infinity')
     OR p_quantity <> round(p_quantity, 2) OR p_transaction_type IS NULL
     OR p_transaction_type NOT IN ('restock','adjustment','written_off')
     OR (p_transaction_type = 'restock' AND p_quantity < 0)
     OR (p_transaction_type <> 'restock' AND p_quantity > 0) THEN
    RAISE EXCEPTION 'Invalid stock quantity, action or request ID.';
  END IF;
  payload := jsonb_build_object('quantity',p_quantity,'type',p_transaction_type,'notes',p_notes,
    'harvest_date',p_harvest_date,'storage_location',p_storage_location);
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text, 21));
  SELECT * INTO request FROM cooperative_stock_requests WHERE request_id = p_request_id;
  IF FOUND THEN
    IF request.inventory_id <> p_inventory_id OR request.actor_id <> auth.uid() OR request.payload <> payload THEN
      RAISE EXCEPTION 'This request ID was already used for a different stock operation.';
    END IF;
    RETURN request.resulting_quantity;
  END IF;
  SELECT * INTO i FROM cooperative_inventory WHERE id = p_inventory_id FOR UPDATE;
  IF NOT FOUND OR i.archived_at IS NOT NULL OR NOT i.is_active THEN RAISE EXCEPTION 'Active inventory item not found.'; END IF;
  result := i.quantity_on_hand + p_quantity;
  IF result < i.quantity_reserved OR result < 0 THEN RAISE EXCEPTION 'Insufficient unreserved stock.'; END IF;
  IF p_quantity > 0 AND i.category = 'Harvest Stock' THEN
    -- A Manual Stock Addition is not a delivery from the Farmer, so the batch
    -- carries no source Farmer (offer_id is NULL too); the item keeps its identity.
    INSERT INTO cooperative_harvest_batches(inventory_id, source_crop_id,
      inventory_transaction_id, original_quantity, unit, harvest_date, storage_location, recorded_by)
    VALUES(i.id, i.source_crop_id,
      tx, p_quantity, i.unit, p_harvest_date, NULLIF(btrim(p_storage_location), ''), auth.uid());
  END IF;
  UPDATE cooperative_inventory SET quantity_on_hand = result,
    last_restocked_at = CASE WHEN p_quantity > 0 THEN now() ELSE last_restocked_at END WHERE id = i.id;
  INSERT INTO inventory_transactions(id, inventory_id, transaction_type, quantity, notes, recorded_by, reference_id, reference_type)
  VALUES(tx, i.id, p_transaction_type, p_quantity, p_notes, auth.uid(), p_request_id, 'manual');
  INSERT INTO cooperative_stock_requests VALUES(p_request_id, i.id, auth.uid(), payload, result);
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.adjust_cooperative_stock(uuid,numeric,text,uuid,text,date,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_cooperative_stock(uuid,numeric,text,uuid,text,date,text) TO authenticated;
-- Old builds must not bypass idempotency by calling the old signature.
REVOKE ALL ON FUNCTION public.adjust_inventory_stock(uuid,numeric,text,text,uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_inventory_item(p_inventory_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i cooperative_inventory;
BEGIN
  IF NOT public.is_staff() THEN RAISE EXCEPTION 'Only cooperative staff can archive inventory.'; END IF;
  SELECT * INTO i FROM cooperative_inventory WHERE id = p_inventory_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventory item not found.'; END IF;
  IF i.archived_at IS NOT NULL THEN RETURN; END IF;
  IF i.quantity_on_hand <> 0 OR i.quantity_reserved <> 0 THEN
    RAISE EXCEPTION 'Adjust or use the remaining stock before archiving this item.';
  END IF;
  UPDATE loan_items_master SET is_loan_eligible = false WHERE inventory_item_id = i.id AND is_loan_eligible;
  UPDATE program_products SET is_available = false WHERE inventory_item_id = i.id AND is_available;
  UPDATE cooperative_inventory SET is_active = false, archived_at = now() WHERE id = i.id;
END $$;
REVOKE ALL ON FUNCTION public.delete_inventory_item(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_inventory_item(uuid) TO authenticated;

-- Backfill and receipt function replacement are in the next section, before
-- enabling guards. Keeping everything in one transaction prevents partial rollout.

-- Protect historical data: a pooled balance cannot be assigned to Farmers when
-- stock has already been consumed/adjusted. Run the preflight and resolve those
-- balances explicitly before migration. No proportional or FIFO guess is made.
DO $$
DECLARE pending_offer record; i record;
BEGIN
  IF EXISTS (SELECT 1 FROM inventory_transactions t
    LEFT JOIN cooperative_purchase_offers o ON o.id=t.reference_id
    WHERE t.transaction_type='harvest_received' AND t.reference_type='cooperative_offer'
      AND (o.id IS NULL OR o.status <> 'completed' OR t.quantity IS DISTINCT FROM o.confirmed_quantity_kg)) THEN
    RAISE EXCEPTION 'Receipt ledger and completed offers disagree; inspect Phase 2 preflight.';
  END IF;
  -- Legacy offers were settled at acceptance, before the delivery/receipt
  -- workflow existed (Phase 1 only relabelled them completed and copied
  -- confirmed_at into received_at). With no delivery, no receipt event, no
  -- receiver and no receipt transaction there is no physical receipt to
  -- transfer: they are skipped, never stamped. Their sale rows stay as they are.
  -- Any OTHER completed offer missing receipt evidence is inconsistent data
  -- and still aborts the migration.
  IF EXISTS (SELECT 1 FROM cooperative_purchase_offers o
    WHERE o.status = 'completed' AND NOT EXISTS(SELECT 1 FROM cooperative_harvest_batches b WHERE b.offer_id = o.id)
    AND NOT (o.received_by IS NULL AND o.delivered_at IS NULL
      AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
      AND NOT EXISTS(SELECT 1 FROM cooperative_offer_events e WHERE e.offer_id = o.id AND e.action IN ('delivered', 'received'))
      AND NOT EXISTS(SELECT 1 FROM inventory_transactions t WHERE t.reference_id = o.id
        AND t.reference_type = 'cooperative_offer' AND t.transaction_type = 'harvest_received'))
    AND (o.received_at IS NULL OR o.received_by IS NULL OR o.member_sales_transaction_id IS NULL)) THEN
    RAISE EXCEPTION 'A completed offer has delivery/receipt activity but incomplete receipt evidence; inspect Phase 2 preflight before migrating.';
  END IF;
  FOR i IN
    SELECT ci.*, sum(t.quantity) AS receipt_total FROM cooperative_inventory ci
    JOIN inventory_transactions t ON t.inventory_id = ci.id AND t.transaction_type = 'harvest_received'
      AND t.reference_type = 'cooperative_offer'
    WHERE ci.source_farmer_id IS NULL
    GROUP BY ci.id
  LOOP
    IF i.quantity_on_hand <> i.receipt_total OR i.quantity_reserved <> 0
      OR EXISTS(SELECT 1 FROM inventory_transactions WHERE inventory_id = i.id
        AND NOT(transaction_type = 'harvest_received' AND reference_type = 'cooperative_offer'))
      OR EXISTS(SELECT 1 FROM loan_items_master WHERE inventory_item_id = i.id)
      OR EXISTS(SELECT 1 FROM program_products WHERE inventory_item_id = i.id)
      OR EXISTS(SELECT 1 FROM program_members WHERE inventory_item_id = i.id)
    THEN
      RAISE EXCEPTION 'Pooled inventory % has adjustments/reservations/catalog links. Resolve its Farmer allocation before Phase 2.', i.id;
    END IF;
  END LOOP;
  FOR pending_offer IN SELECT o.id FROM cooperative_purchase_offers o WHERE o.status = 'completed'
    AND NOT (o.received_by IS NULL AND o.delivered_at IS NULL
      AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
      AND NOT EXISTS(SELECT 1 FROM cooperative_offer_events e WHERE e.offer_id = o.id AND e.action IN ('delivered', 'received'))
      AND NOT EXISTS(SELECT 1 FROM inventory_transactions t WHERE t.reference_id = o.id
        AND t.reference_type = 'cooperative_offer' AND t.transaction_type = 'harvest_received'))
    ORDER BY o.received_at, o.id LOOP
    UPDATE cooperative_purchase_offers SET coop_inventory_id = public._coop_receive_harvest(pending_offer.id) WHERE id = pending_offer.id;
  END LOOP;
  -- Old empty pools remain for audit, but disappear from active inventory.
  UPDATE cooperative_inventory ci SET is_active = false, archived_at = COALESCE(archived_at, now())
    WHERE ci.source_farmer_id IS NULL AND ci.category = 'Harvest Stock' AND ci.quantity_on_hand = 0
      AND ci.source = 'Farmer deliveries (Offer to Cooperative)';
END $$;

-- Preserve all older stock transactions as history, including their true dates
-- and recorded users. Never invent historical edit/publish events.
INSERT INTO cooperative_inventory_history(inventory_id, occurred_at, action, actor_id, actor_name,
  source_farmer_id, source_farmer_name, quantity_change, unit, batch_id, transaction_id, reference_id, reference_type, details)
SELECT t.inventory_id, t.created_at, t.transaction_type, t.recorded_by, public._coop_person_name(t.recorded_by),
  i.source_farmer_id, b.source_farmer_name, t.quantity, i.unit, b.id, t.id, t.reference_id, t.reference_type,
  jsonb_build_object('notes',t.notes,'imported',true)
FROM inventory_transactions t JOIN cooperative_inventory i ON i.id = t.inventory_id
LEFT JOIN cooperative_harvest_batches b ON b.inventory_transaction_id = t.id
ON CONFLICT(transaction_id) DO NOTHING;

DROP TRIGGER IF EXISTS phase2_inventory_guard ON public.cooperative_inventory;
CREATE TRIGGER phase2_inventory_guard BEFORE INSERT OR UPDATE OR DELETE ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public._coop_inventory_guard();
DROP TRIGGER IF EXISTS phase2_inventory_audit ON public.cooperative_inventory;
CREATE TRIGGER phase2_inventory_audit AFTER INSERT OR UPDATE ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public._coop_inventory_audit();
DROP TRIGGER IF EXISTS phase2_transaction_audit ON public.inventory_transactions;
CREATE TRIGGER phase2_transaction_audit AFTER INSERT ON public.inventory_transactions
  FOR EACH ROW EXECUTE FUNCTION public._coop_transaction_audit();
DROP TRIGGER IF EXISTS phase2_loan_audit ON public.loan_items_master;
CREATE TRIGGER phase2_loan_audit AFTER INSERT OR UPDATE OR DELETE ON public.loan_items_master
  FOR EACH ROW EXECUTE FUNCTION public._coop_catalog_audit();
DROP TRIGGER IF EXISTS phase2_product_audit ON public.program_products;
CREATE TRIGGER phase2_product_audit AFTER INSERT OR UPDATE OR DELETE ON public.program_products
  FOR EACH ROW EXECUTE FUNCTION public._coop_catalog_audit();

-- Ledger clients may read, but only existing authorized SECURITY DEFINER stock
-- functions may insert transactions. Never allow clients to erase history.
REVOKE INSERT, UPDATE, DELETE ON public.inventory_transactions FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.cooperative_purchase_offers FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public._coop_preserve_transaction() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'Inventory transactions cannot be changed or deleted.';
END $$;
DROP TRIGGER IF EXISTS phase2_preserve_transaction ON public.inventory_transactions;
CREATE TRIGGER phase2_preserve_transaction BEFORE UPDATE OR DELETE ON public.inventory_transactions
  FOR EACH ROW EXECUTE FUNCTION public._coop_preserve_transaction();

-- Receipt RPC below replaces Phase 1, preserving sale settlement, Farmer stock
-- reconciliation and notifications. The completion trigger transfers every crop.
CREATE OR REPLACE FUNCTION public.confirm_cooperative_offer_receipt(
  p_offer_id UUID,
  p_note     TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_tx    UUID;

BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only the cooperative can confirm a delivery.';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;
  IF v_offer.status = 'completed' THEN
    RETURN v_offer.member_sales_transaction_id;
  END IF;
  IF v_offer.status <> 'delivered' THEN
    RAISE EXCEPTION 'Only a delivered offer can be confirmed as received (current status: %).', v_offer.status;
  END IF;
  IF v_offer.member_sales_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION 'This offer was already settled.';
  END IF;

  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, lower(v_offer.crop_name),
    v_offer.confirmed_quantity_kg, v_offer.confirmed_amount, CURRENT_DATE, auth.uid()
  ) RETURNING id INTO v_tx;

  -- The completion trigger performs the atomic inventory transfer.

  UPDATE cooperative_purchase_offers
     SET status = 'completed',
         member_sales_transaction_id = v_tx,
         received_at = NOW(),
         received_by = auth.uid(),
         receipt_note = NULLIF(btrim(p_note), '')
   WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'received', 'cooperative', auth.uid(),
     v_offer.agreed_price_per_kg, v_offer.confirmed_quantity_kg, NULLIF(btrim(p_note), ''));

  PERFORM public.reconcile_batch_sold(v_offer.inventory_batch_id);

  PERFORM public._coop_offer_notify_farmer(
    v_offer.farmer_id,
    'Delivery Confirmed',
    'SP3 confirmed receiving your ' || v_offer.confirmed_quantity_kg || ' kg ' || v_offer.crop_name ||
      '. The sale of ' || public._coop_offer_peso(v_offer.confirmed_amount) || ' is recorded.'
  );

  RETURN v_tx;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_cooperative_offer_receipt(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_cooperative_offer_receipt(UUID, TEXT) TO authenticated;

DROP TRIGGER IF EXISTS phase2_completed_transfer ON public.cooperative_purchase_offers;
CREATE TRIGGER phase2_completed_transfer AFTER UPDATE OF status ON public.cooperative_purchase_offers
  FOR EACH ROW WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public._coop_completed_transfer();
DROP TRIGGER IF EXISTS phase2_inserted_completed_transfer ON public.cooperative_purchase_offers;
CREATE TRIGGER phase2_inserted_completed_transfer AFTER INSERT ON public.cooperative_purchase_offers
  FOR EACH ROW WHEN (NEW.status = 'completed') EXECUTE FUNCTION public._coop_completed_transfer();

DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') AND NOT EXISTS(
    SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public' AND tablename = 'cooperative_inventory') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cooperative_inventory;
  END IF;
END $$;
COMMIT;
NOTIFY pgrst, 'reload schema';
