-- ============================================================
-- SAGANA — Harvest batch numbers + per-batch unit of measure
--
-- 1. BATCH NUMBERS   BATCH-POTATO-261025-A0001
--                          |      |      |||
--                          |      |      ||+-- sequence (>= 4 digits) for this CROP in this YEAR
--                          |      |      |+--- (digits)
--                          |      |      +---- the crop's own letter(s): A, B, ... Z, AA, AB ...
--                          |      +----------- harvest date, YYMMDD
--                          +------------------ crop name from Crop Management (A-Z, 0-9 only)
--
--    The app shows it with a leading "#" (#BATCH-POTATO-261025-A0001); the
--    "#" is display only and is not stored, the same as ORD- and LRN-.
--
--    * Each crop (crop_master row) gets ONE permanent letter prefix the moment
--      it is created, by a trigger, so a crop added later by any path (crop
--      request approval, Crop Management, SQL) is covered with no code change
--      and no crop name is hardcoded anywhere.
--    * Each (crop, harvest-date YEAR) has its own counter. Harvesting the same
--      crop again continues its sequence for that year; every sequence starts
--      again at 0001 in a new year. The year is the harvest date's year, so a
--      harvest recorded late for last December continues last year's sequence
--      and its YY always matches its own sequence (the number stays unique).
--    * The number is issued by a BEFORE INSERT trigger on harvest_records. Any
--      value a client sends is ignored and replaced. The counter row is locked
--      while a number is issued, so two harvests recorded at the same moment
--      get different numbers. inventory_batches copies the number from its
--      harvest record, so the two always agree.
--    * A batch number can never be changed after it is issued.
--
--    EXISTING harvest records and batches keep their number (BATCH-POTA-
--    20261025-1234 style). Nothing is renumbered, deleted or rewritten.
--
-- 2. UNITS           harvest_records, inventory_batches and the records made
--    from a batch (marketplace_listings, orders, cooperative_purchase_offers,
--    informal_sales, and the member_sales_transactions row an accepted offer
--    creates) get a `unit` column (default 'kg').
--
--    * The unit is chosen once, at harvest, from the existing public.units
--      list (the same list Inventory Management and Price Management use).
--    * The *_kg column names are kept. They now mean "quantity in this row's
--      unit". Every calculation in the database (reservation, order, cancel,
--      complete, offers) works on ONE batch at a time, so it stays inside one
--      unit; nothing here converts between units, and nothing may add two
--      different units together.
--    * Listings, orders, offers and informal sales copy the unit from their
--      source by trigger, so no existing function had to be changed.
--    * A batch's unit can never be changed after it is created.
--    * A crop reserved for one selling channel (Ginger / DA-AMAD Market
--      Linking, crop_master.exclusive_channel) can only be harvested in kg,
--      because that whole workflow is measured in kg.
--    * Every existing row becomes 'kg', which is what it always was.
--
-- Quantity columns are DECIMAL(10,2) and CHECK (> 0) already, so 0.45, 1.25
-- and 10.75 are stored exactly; nothing about the column types changes.
--
-- Not applied automatically. Run the PRE-FLIGHT queries, then run this file in
-- the Supabase SQL editor, then run the VERIFICATION block at the end.
-- Safe to re-run.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ─────────────────────────
-- 0. The two views this file redefines (section 8) must still match
--    supabase_schema_analytics_views_crop_id_fix.sql; the only change is the added
--    "AND hr.unit = 'kg'". If someone changed them in the dashboard since, tell me
--    before running this file:
--    SELECT pg_get_viewdef('public.top_harvested_crops'::regclass, true);
--    SELECT pg_get_viewdef('public.crop_cycle_volumes'::regclass, true);
-- A. The units list must contain 'kg' (expect 1 row):
--    SELECT name FROM public.units WHERE lower(name) = 'kg' AND is_active;
-- B. Crops that will receive a letter (expect the number of crops you have):
--    SELECT count(*) FROM public.crop_master;
-- C. Harvest dates outside 2000-2099 (expect 0 rows; the new trigger would
--    refuse a NEW harvest like that, old rows are not checked):
--    SELECT id, harvest_date FROM public.harvest_records
--    WHERE harvest_date < DATE '2000-01-01' OR harvest_date > DATE '2099-12-31';
-- D. Every harvestable crop is linked to the catalog (expect 0 rows):
--    SELECT fc.id, fc.crop_name FROM public.farmer_crops fc
--    WHERE fc.crop_master_id IS NULL AND EXISTS
--      (SELECT 1 FROM public.harvest_records h WHERE h.crop_id = fc.id);
-- E. Tables this file changes exist (expect 7 rows):
--    SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'
--    AND table_name IN ('crop_master','harvest_records','inventory_batches',
--      'marketplace_listings','orders','cooperative_purchase_offers','informal_sales');
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.units WHERE lower(name) = 'kg' AND is_active) THEN
    RAISE EXCEPTION 'The units list has no active "kg". Run supabase_schema_units.sql first.';
  END IF;
  IF to_regclass('public.farmer_crops') IS NULL OR to_regclass('public.crop_master') IS NULL THEN
    RAISE EXCEPTION 'farmer_crops / crop_master are missing.';
  END IF;
END;
$$;

-- ═══ 1. A permanent letter prefix for every crop ════════════════════════

-- 1 -> A, 26 -> Z, 27 -> AA, 28 -> AB ...
CREATE OR REPLACE FUNCTION public.batch_prefix_for_index(p_index INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_q       INTEGER;
  v_letters TEXT := '';
BEGIN
  IF p_index IS NULL OR p_index < 1 THEN
    RAISE EXCEPTION 'The batch prefix index must be 1 or more.';
  END IF;
  v_q := p_index;
  WHILE v_q > 0 LOOP
    v_q := v_q - 1;
    v_letters := chr(65 + (v_q % 26)) || v_letters;
    v_q := v_q / 26;
  END LOOP;
  RETURN v_letters;
END;
$$;

-- One row: the last prefix index handed out.
CREATE TABLE IF NOT EXISTS public.batch_prefix_state (
  id          INTEGER PRIMARY KEY CHECK (id = 1),
  last_index  INTEGER NOT NULL CHECK (last_index >= 0)
);
INSERT INTO public.batch_prefix_state (id, last_index) VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.batch_prefix_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.batch_prefix_state FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_batch_prefix()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_index INTEGER;
BEGIN
  -- Row lock: two crops created at once get different letters.
  UPDATE public.batch_prefix_state
     SET last_index = last_index + 1
   WHERE id = 1
  RETURNING last_index INTO v_index;
  RETURN public.batch_prefix_for_index(v_index);
END;
$$;
REVOKE ALL ON FUNCTION public.next_batch_prefix() FROM PUBLIC, anon, authenticated;

ALTER TABLE public.crop_master ADD COLUMN IF NOT EXISTS batch_prefix TEXT;

-- Existing crops, in a fixed order (oldest first, then by name), once.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM public.crop_master
    WHERE batch_prefix IS NULL
    ORDER BY created_at, crop_name, id
  LOOP
    UPDATE public.crop_master SET batch_prefix = public.next_batch_prefix() WHERE id = r.id;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_crop_master_batch_prefix
  ON public.crop_master (batch_prefix)
  WHERE batch_prefix IS NOT NULL;

-- New crops: always issued here (a value sent by a client is replaced), so any
-- code path that inserts into crop_master is covered.
CREATE OR REPLACE FUNCTION public.assign_crop_batch_prefix()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.batch_prefix := public.next_batch_prefix();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_crop_master_assign_batch_prefix ON public.crop_master;
CREATE TRIGGER trg_crop_master_assign_batch_prefix
  BEFORE INSERT ON public.crop_master
  FOR EACH ROW EXECUTE FUNCTION public.assign_crop_batch_prefix();

-- A crop's letter never changes once it has one (old batch numbers rely on it).
CREATE OR REPLACE FUNCTION public.protect_crop_batch_prefix()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.batch_prefix IS NOT NULL AND NEW.batch_prefix IS DISTINCT FROM OLD.batch_prefix THEN
    RAISE EXCEPTION 'A crop''s batch prefix cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_crop_master_protect_batch_prefix ON public.crop_master;
CREATE TRIGGER trg_crop_master_protect_batch_prefix
  BEFORE UPDATE OF batch_prefix ON public.crop_master
  FOR EACH ROW EXECUTE FUNCTION public.protect_crop_batch_prefix();

ALTER TABLE public.crop_master ALTER COLUMN batch_prefix SET NOT NULL;

-- ═══ 2. Unit columns ════════════════════════════════════════════════════
ALTER TABLE public.harvest_records             ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';
ALTER TABLE public.inventory_batches           ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';
ALTER TABLE public.marketplace_listings        ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';
ALTER TABLE public.orders                      ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';
ALTER TABLE public.cooperative_purchase_offers ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';
ALTER TABLE public.informal_sales              ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';

-- ═══ 3. The yearly, per-crop counter and the number itself ══════════════
CREATE TABLE IF NOT EXISTS public.batch_number_counters (
  crop_master_id  UUID    NOT NULL REFERENCES public.crop_master (id) ON DELETE CASCADE,
  year            INTEGER NOT NULL CHECK (year BETWEEN 2000 AND 2099),
  last_seq        INTEGER NOT NULL CHECK (last_seq >= 0),
  PRIMARY KEY (crop_master_id, year)
);
ALTER TABLE public.batch_number_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.batch_number_counters FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_batch_number(
  p_crop_master_id UUID,
  p_harvest_date   DATE
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name   TEXT;
  v_prefix TEXT;
  v_token  TEXT;
  v_year   INTEGER;
  v_seq    INTEGER;
BEGIN
  IF p_harvest_date IS NULL THEN
    RAISE EXCEPTION 'A harvest date is required.';
  END IF;
  v_year := EXTRACT(YEAR FROM p_harvest_date)::INTEGER;
  IF v_year NOT BETWEEN 2000 AND 2099 THEN
    RAISE EXCEPTION 'The harvest date must be between the years 2000 and 2099.';
  END IF;

  SELECT crop_name, batch_prefix INTO v_name, v_prefix
  FROM public.crop_master WHERE id = p_crop_master_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This crop is not in the cooperative''s crop list, so a batch number cannot be issued.';
  END IF;

  -- Crop name from Crop Management, letters and digits only (SWEET POTATO -> SWEETPOTATO).
  v_token := upper(regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g'));
  IF v_token = '' THEN
    v_token := 'CROP';
  END IF;

  -- One atomic statement: the first harvest of a crop in a year creates the row
  -- at 1; every other harvest locks the row, adds 1 and waits its turn.
  INSERT INTO public.batch_number_counters (crop_master_id, year, last_seq)
  VALUES (p_crop_master_id, v_year, 1)
  ON CONFLICT (crop_master_id, year)
  DO UPDATE SET last_seq = public.batch_number_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;

  RETURN 'BATCH-' || v_token || '-' || to_char(p_harvest_date, 'YYMMDD') || '-'
         || v_prefix || lpad(v_seq::TEXT, 4, '0');
END;
$$;
REVOKE ALL ON FUNCTION public.next_batch_number(UUID, DATE) FROM PUBLIC, anon, authenticated;

-- ═══ 4. Triggers on harvest_records ═════════════════════════════════════
CREATE OR REPLACE FUNCTION public.prepare_harvest_record()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_master  UUID;
  v_channel TEXT;
BEGIN
  SELECT fc.crop_master_id, cm.exclusive_channel
    INTO v_master, v_channel
  FROM public.farmer_crops fc
  LEFT JOIN public.crop_master cm ON cm.id = fc.crop_master_id
  WHERE fc.id = NEW.crop_id;

  IF v_master IS NULL THEN
    RAISE EXCEPTION 'This crop has not been approved by the Manager yet, so a harvest cannot be recorded.';
  END IF;

  -- Unit: normalised, and it must be one of the active units.
  NEW.unit := lower(btrim(COALESCE(NEW.unit, 'kg')));
  IF NOT EXISTS (
    SELECT 1 FROM public.units WHERE is_active AND lower(name) = NEW.unit
  ) THEN
    RAISE EXCEPTION 'Unknown unit "%". Choose a unit from the list.', NEW.unit;
  END IF;

  -- DA-AMAD Market Linking (Ginger) is measured in kg end to end.
  IF v_channel IS NOT NULL AND NEW.unit <> 'kg' THEN
    RAISE EXCEPTION 'This crop is sold through its own selling channel, which is measured in kg. Choose kg.';
  END IF;

  -- Always issued here; whatever a client sent is replaced.
  NEW.batch_number := public.next_batch_number(v_master, NEW.harvest_date);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_harvest_records_prepare ON public.harvest_records;
CREATE TRIGGER trg_harvest_records_prepare
  BEFORE INSERT ON public.harvest_records
  FOR EACH ROW EXECUTE FUNCTION public.prepare_harvest_record();

-- ═══ 5. inventory_batches follows its harvest record ════════════════════
CREATE OR REPLACE FUNCTION public.inherit_batch_from_harvest()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_number TEXT;
  v_unit   TEXT;
BEGIN
  SELECT batch_number, unit INTO v_number, v_unit
  FROM public.harvest_records WHERE id = NEW.harvest_record_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The harvest record for this batch was not found.';
  END IF;
  NEW.batch_number := v_number;
  NEW.unit := v_unit;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inventory_batches_inherit_harvest ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_inherit_harvest
  BEFORE INSERT ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public.inherit_batch_from_harvest();

-- ═══ 6. Records made from a batch copy its unit ═════════════════════════
CREATE OR REPLACE FUNCTION public.inherit_unit_from_batch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.inventory_batch_id IS NOT NULL THEN
    SELECT unit INTO NEW.unit FROM public.inventory_batches WHERE id = NEW.inventory_batch_id;
  END IF;
  NEW.unit := COALESCE(NEW.unit, 'kg');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.inherit_unit_from_listing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.listing_id IS NOT NULL THEN
    SELECT unit INTO NEW.unit FROM public.marketplace_listings WHERE id = NEW.listing_id;
  END IF;
  NEW.unit := COALESCE(NEW.unit, 'kg');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marketplace_listings_inherit_unit ON public.marketplace_listings;
CREATE TRIGGER trg_marketplace_listings_inherit_unit
  BEFORE INSERT ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.inherit_unit_from_batch();

DROP TRIGGER IF EXISTS trg_cooperative_purchase_offers_inherit_unit ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_cooperative_purchase_offers_inherit_unit
  BEFORE INSERT ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public.inherit_unit_from_batch();

DROP TRIGGER IF EXISTS trg_informal_sales_inherit_unit ON public.informal_sales;
CREATE TRIGGER trg_informal_sales_inherit_unit
  BEFORE INSERT ON public.informal_sales
  FOR EACH ROW EXECUTE FUNCTION public.inherit_unit_from_batch();

DROP TRIGGER IF EXISTS trg_orders_inherit_unit ON public.orders;
CREATE TRIGGER trg_orders_inherit_unit
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.inherit_unit_from_listing();

-- The sale an accepted cooperative offer creates (member_sales_transactions) has
-- no batch of its own; it is tied to the offer by
-- cooperative_purchase_offers.member_sales_transaction_id, so it takes the
-- offer's unit once that link is written.
ALTER TABLE public.member_sales_transactions ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';

CREATE OR REPLACE FUNCTION public.copy_offer_unit_to_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.member_sales_transaction_id IS NOT NULL THEN
    UPDATE public.member_sales_transactions
       SET unit = NEW.unit
     WHERE id = NEW.member_sales_transaction_id
       AND unit IS DISTINCT FROM NEW.unit;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cooperative_purchase_offers_copy_unit ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_cooperative_purchase_offers_copy_unit
  AFTER INSERT OR UPDATE OF member_sales_transaction_id ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public.copy_offer_unit_to_transaction();

-- ═══ 7. A batch number and a unit never change ══════════════════════════
CREATE OR REPLACE FUNCTION public.protect_batch_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.batch_number IS DISTINCT FROM OLD.batch_number THEN
    RAISE EXCEPTION 'A batch number cannot be changed.';
  END IF;
  IF NEW.unit IS DISTINCT FROM OLD.unit THEN
    RAISE EXCEPTION 'The unit of a harvest or batch cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_harvest_records_protect_identity ON public.harvest_records;
CREATE TRIGGER trg_harvest_records_protect_identity
  BEFORE UPDATE OF batch_number, unit ON public.harvest_records
  FOR EACH ROW EXECUTE FUNCTION public.protect_batch_identity();

DROP TRIGGER IF EXISTS trg_inventory_batches_protect_identity ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_protect_identity
  BEFORE UPDATE OF batch_number, unit ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public.protect_batch_identity();

-- ═══ 8. Cooperative-wide kg views add kg only ═══════════════════════════
-- top_harvested_crops (Top Harvested Crops chart) and crop_cycle_volumes
-- (Planting Forecast) are totals in kg. They are redefined exactly as in
-- supabase_schema_analytics_views_crop_id_fix.sql (the latest definition), with
-- one added condition so a harvest measured in another unit is never added to a
-- kilogram total. crop_planting_forecast reads crop_cycle_volumes and needs no
-- change.
CREATE OR REPLACE VIEW public.top_harvested_crops AS
SELECT
  COALESCE(cm.crop_name, hr.crop_name) AS crop_name,
  SUM(hr.quantity_kg) AS total_kg
FROM public.harvest_records hr
LEFT JOIN public.farmer_crops fc ON fc.id = hr.crop_id
LEFT JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE hr.harvest_date >= NOW() - INTERVAL '90 days'
  AND hr.unit = 'kg'
GROUP BY COALESCE(cm.crop_name, hr.crop_name);

CREATE OR REPLACE VIEW public.crop_cycle_volumes AS
SELECT
  COALESCE(cm.crop_name, hr.crop_name) AS crop_name,
  FLOOR(EXTRACT(EPOCH FROM (NOW() - hr.harvest_date)) / (30 * 86400))::INT AS cycle_index,
  SUM(hr.quantity_kg) AS cycle_volume_kg
FROM public.harvest_records hr
LEFT JOIN public.farmer_crops fc ON fc.id = hr.crop_id
LEFT JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE hr.harvest_date >= NOW() - INTERVAL '180 days'
  AND hr.unit = 'kg'
GROUP BY COALESCE(cm.crop_name, hr.crop_name), cycle_index;

GRANT SELECT ON public.top_harvested_crops TO authenticated;
GRANT SELECT ON public.crop_cycle_volumes TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Every crop has its own letter (expect 0 rows, then 0 rows):
--    SELECT id, crop_name FROM public.crop_master WHERE batch_prefix IS NULL;
--    SELECT batch_prefix, count(*) FROM public.crop_master GROUP BY 1 HAVING count(*) > 1;
-- 2. The letters are A, B, C ... in order of creation:
--    SELECT crop_name, batch_prefix FROM public.crop_master ORDER BY created_at, crop_name;
-- 3. The letter generator (expect A | Z | AA | AB | AZ | BA):
--    SELECT public.batch_prefix_for_index(1), public.batch_prefix_for_index(26),
--           public.batch_prefix_for_index(27), public.batch_prefix_for_index(28),
--           public.batch_prefix_for_index(52), public.batch_prefix_for_index(53);
-- 4. Old harvests / batches were not touched. Old numbers differ from the new
--    shape; units are all kg (expect the same row counts as before, 0 non-kg):
--    SELECT count(*) AS harvests, count(*) FILTER (WHERE unit <> 'kg') AS non_kg
--    FROM public.harvest_records;
--    SELECT count(*) AS batches, count(*) FILTER (WHERE unit <> 'kg') AS non_kg
--    FROM public.inventory_batches;
-- 5. After recording new harvests: every NEW number has the right shape and
--    both tables agree (expect 0 rows each):
--    SELECT id, batch_number FROM public.harvest_records
--    WHERE created_at > now() - interval '1 day'
--      AND batch_number !~ '^BATCH-[A-Z0-9]+-[0-9]{6}-[A-Z]+[0-9]{4,}$';
--    SELECT h.id FROM public.harvest_records h
--    JOIN public.inventory_batches b ON b.harvest_record_id = h.id
--    WHERE b.batch_number <> h.batch_number OR b.unit <> h.unit;
-- 6. No duplicates (expect 0 rows each):
--    SELECT batch_number, count(*) FROM public.harvest_records GROUP BY 1 HAVING count(*) > 1;
--    SELECT batch_number, count(*) FROM public.inventory_batches GROUP BY 1 HAVING count(*) > 1;
-- 7. Per crop and year the sequence runs 0001, 0002, 0003 ... with the crop's own
--    letter, and starts again at 0001 in a new year (read the list by eye; a gap
--    only means a harvest was deleted afterwards, which leaves its number unused):
--    SELECT cm.crop_name, cm.batch_prefix, EXTRACT(YEAR FROM h.harvest_date)::int AS yr,
--           split_part(h.batch_number, '-', 4) AS letter_and_seq, h.batch_number, h.harvest_date
--    FROM public.harvest_records h
--    JOIN public.farmer_crops fc ON fc.id = h.crop_id
--    JOIN public.crop_master cm ON cm.id = fc.crop_master_id
--    WHERE h.batch_number ~ '^BATCH-[A-Z0-9]+-[0-9]{6}-[A-Z]+[0-9]{4,}$'
--    ORDER BY cm.batch_prefix, yr, letter_and_seq;
--    -- and the counters agree with the highest number issued:
--    SELECT cm.crop_name, c.year, c.last_seq FROM public.batch_number_counters c
--    JOIN public.crop_master cm ON cm.id = c.crop_master_id ORDER BY cm.batch_prefix, c.year;
-- 8. The date in each new number is the harvest date (expect 0 rows):
--    SELECT id, batch_number, harvest_date FROM public.harvest_records
--    WHERE batch_number ~ '^BATCH-[A-Z0-9]+-[0-9]{6}-'
--      AND split_part(batch_number, '-', 3) <> to_char(harvest_date, 'YYMMDD');
-- 9. Listings / orders / offers / informal sales carry their batch's unit (expect 0 rows each):
--    SELECT l.id FROM public.marketplace_listings l
--      JOIN public.inventory_batches b ON b.id = l.inventory_batch_id WHERE l.unit <> b.unit;
--    SELECT o.id FROM public.orders o
--      JOIN public.marketplace_listings l ON l.id = o.listing_id WHERE o.unit <> l.unit;
--    SELECT t.id FROM public.member_sales_transactions t
--      JOIN public.cooperative_purchase_offers o ON o.member_sales_transaction_id = t.id WHERE t.unit <> o.unit;
-- 10. Ginger (exclusive channel) has no non-kg harvest (expect 0 rows):
--    SELECT h.id FROM public.harvest_records h
--      JOIN public.farmer_crops fc ON fc.id = h.crop_id
--      JOIN public.crop_master cm ON cm.id = fc.crop_master_id
--    WHERE cm.exclusive_channel IS NOT NULL AND h.unit <> 'kg';
-- ───────────────────────────────────────────────────────────────────────────
