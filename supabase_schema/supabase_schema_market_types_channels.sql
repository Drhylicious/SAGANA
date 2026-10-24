-- ============================================================
-- SAGANA — Market Types vs Selling Channels, step 1 of 2: STRUCTURE + DATA
--
-- SAGANA has exactly 2 MARKET TYPES and 4 SELLING CHANNELS. They are separate.
--
--   Market type (who may see / buy a listing)
--     Public Market       Buyers and Farmer Members
--     Cooperative Market  Farmer Members only
--
--   Selling channel (how a farmer sells a harvested batch)
--     Marketplace, Offer to Cooperative, Informal Sale,
--     DA-AMAD Market Linking (Ginger only)
--
-- Until now DA-AMAD was stored as a THIRD market type ('da_amad_market') and
-- Ginger was identified by it. This script corrects that:
--
--   1. market_types     the 2 market types as data (names, buyer visibility,
--                       who sets prices) instead of literals in code.
--   2. selling_channels the 4 channels as data.
--   3. crop_master.exclusive_channel   "this crop can ONLY be sold through
--                       channel X". Ginger gets 'da_amad_market_linking', taken
--                       from its existing da_amad_market row (not from its
--                       name). A unique index allows at most ONE crop per
--                       exclusive channel (DA-AMAD stays Ginger-only), and a
--                       trigger stops the app from setting it: only a database
--                       administrator can.
--   4. inventory_batches.exclusive_channel   copy of the crop's value, kept on
--                       the batch like crop_type and is_coop_eligible already are.
--   5. Ginger's market type becomes Public Market (open_market). Its crop,
--      batch, enrollment and stock are NOT deleted or moved.
--   6. The seven "crop_type IN (3 values)" CHECK constraints are replaced by
--      foreign keys to market_types, so 'da_amad_market' can no longer be
--      stored as a market type and a new market type is just a new row.
--   7. crop_master.is_cooperative_eligible is regenerated as
--      "no exclusive channel" (same result as before for every crop).
--
-- VERIFIED BEFORE WRITING (pre-flight B1, B3, B4, B6, B7, C1, C2):
--   da_amad_market rows: crop_master 1 (Ginger), inventory_batches 1 (10 kg
--   available), crop_requests 0, marketplace_listings 0, offers 0, informal
--   sales 0, price_records 0. No Ginger on a forbidden channel.
--
-- The whole script is ONE transaction: if any step fails (for example a
-- leftover 'da_amad_market' value somewhere unexpected), nothing is changed.
-- Not applied automatically. Run it in the Supabase SQL editor, then run
-- supabase_schema_market_rules_by_data.sql, then the verification block below.
-- ============================================================

BEGIN;

-- ─── 0. Safety stop ──────────────────────────────────────────────────────
-- These tables must hold no da_amad_market row. If one does, history would
-- have to be reclassified deliberately, not by this script.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.marketplace_listings        WHERE crop_type  = 'da_amad_market')
  OR EXISTS (SELECT 1 FROM public.cooperative_purchase_offers WHERE crop_type  = 'da_amad_market')
  OR EXISTS (SELECT 1 FROM public.informal_sales              WHERE crop_type  = 'da_amad_market')
  OR EXISTS (SELECT 1 FROM public.price_records               WHERE price_type = 'da_amad_market')
  THEN
    RAISE EXCEPTION 'Stop: da_amad_market is stored on listings, offers, informal sales or price records. Review those rows first.';
  END IF;
END;
$$;

-- ─── 1. Market types ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.market_types (
  code               TEXT        PRIMARY KEY,
  name               TEXT        NOT NULL,
  name_tl            TEXT,
  description        TEXT,
  buyer_visible      BOOLEAN     NOT NULL,   -- may a Buyer see/purchase listings of this type?
  manager_sets_price BOOLEAN     NOT NULL DEFAULT FALSE,  -- does the Manager set listing prices?
  sort_order         INTEGER     NOT NULL DEFAULT 0,
  is_active          BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.market_types
  (code, name, name_tl, description, buyer_visible, manager_sets_price, sort_order)
VALUES
  ('open_market',     'Public Market',      'Pampublikong Market',
   'Open to Buyers and Farmer Members.', TRUE,  FALSE, 1),
  ('sp3_cooperative', 'Cooperative Market', 'Market ng Kooperatiba',
   'Exclusive to Farmer Members. Buyers cannot see or purchase these listings.', FALSE, TRUE, 2)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.market_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "market_types: authenticated read" ON public.market_types;
CREATE POLICY "market_types: authenticated read"
  ON public.market_types FOR SELECT TO authenticated USING (TRUE);
-- No INSERT/UPDATE/DELETE policy: market types are changed by a database
-- administrator only.

-- ─── 2. Selling channels ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.selling_channels (
  code                    TEXT        PRIMARY KEY,
  name                    TEXT        NOT NULL,
  name_tl                 TEXT,
  description             TEXT,
  -- TRUE: only a crop reserved for this channel (crop_master.exclusive_channel)
  -- may use it. DA-AMAD Market Linking is the only such channel.
  requires_exclusive_crop BOOLEAN     NOT NULL DEFAULT FALSE,
  sort_order              INTEGER     NOT NULL DEFAULT 0,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.selling_channels
  (code, name, name_tl, description, requires_exclusive_crop, sort_order)
VALUES
  ('marketplace',            'Marketplace',            'Pamilihan',
   'A listing in the Public or Cooperative Market.', FALSE, 1),
  ('offer_to_cooperative',   'Offer to Cooperative',   'Alok sa Kooperatiba',
   'The harvest is offered directly to the cooperative.', FALSE, 2),
  ('informal_sale',          'Informal Sale',          'Impormal na Bentahan',
   'A face-to-face or outside-system sale, recorded here.', FALSE, 3),
  ('da_amad_market_linking', 'DA-AMAD Market Linking', 'DA-AMAD Market Linking',
   'Ginger only. The farmer enrolls, submits the harvest, and the cooperative finds a buyer.', TRUE, 4)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.selling_channels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "selling_channels: authenticated read" ON public.selling_channels;
CREATE POLICY "selling_channels: authenticated read"
  ON public.selling_channels FOR SELECT TO authenticated USING (TRUE);

-- ─── 3. Crop-level exclusive channel ─────────────────────────────────────
ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS exclusive_channel TEXT
  REFERENCES public.selling_channels (code) ON UPDATE CASCADE;

COMMENT ON COLUMN public.crop_master.exclusive_channel IS
  'When set, this crop can ONLY be sold through that selling channel. Set by a '
  'database administrator only (guard_crop_exclusive_channel); never from the app.';

-- Ginger is identified by its existing da_amad_market classification, not by name.
UPDATE public.crop_master
SET exclusive_channel = 'da_amad_market_linking'
WHERE crop_type = 'da_amad_market' AND exclusive_channel IS NULL;

-- At most one crop per exclusive channel: DA-AMAD stays Ginger-only.
CREATE UNIQUE INDEX IF NOT EXISTS uq_crop_master_exclusive_channel
  ON public.crop_master (exclusive_channel)
  WHERE exclusive_channel IS NOT NULL;

-- Regenerate is_cooperative_eligible from the exclusive channel (previously
-- "crop_type <> 'da_amad_market'"). Same value for every existing crop.
ALTER TABLE public.crop_master DROP COLUMN is_cooperative_eligible;
ALTER TABLE public.crop_master
  ADD COLUMN is_cooperative_eligible BOOLEAN
  GENERATED ALWAYS AS (exclusive_channel IS NULL) STORED;

-- ─── 4. Batch copy of the exclusive channel ──────────────────────────────
ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS exclusive_channel TEXT
  REFERENCES public.selling_channels (code) ON UPDATE CASCADE;

UPDATE public.inventory_batches ib
SET exclusive_channel = cm.exclusive_channel
FROM public.farmer_crops fc
JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE ib.crop_id = fc.id
  AND cm.exclusive_channel IS NOT NULL
  AND ib.exclusive_channel IS DISTINCT FROM cm.exclusive_channel;

-- New batches pick it up from their crop whatever created them (online or
-- offline sync), the same way marketplace_listings picks up crop_type.
CREATE OR REPLACE FUNCTION public.set_batch_exclusive_channel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.exclusive_channel IS NULL AND NEW.crop_id IS NOT NULL THEN
    SELECT cm.exclusive_channel INTO NEW.exclusive_channel
    FROM public.farmer_crops fc
    JOIN public.crop_master cm ON cm.id = fc.crop_master_id
    WHERE fc.id = NEW.crop_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_batch_exclusive_channel ON public.inventory_batches;
CREATE TRIGGER trg_set_batch_exclusive_channel
  BEFORE INSERT ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public.set_batch_exclusive_channel();

-- ─── 5. Ginger's market type becomes Public Market ───────────────────────
-- Counted in the pre-flight: crop_master 1, inventory_batches 1, crop_requests 0.
UPDATE public.crop_master        SET crop_type = 'open_market' WHERE crop_type = 'da_amad_market';
UPDATE public.crop_requests      SET crop_type = 'open_market' WHERE crop_type = 'da_amad_market';
UPDATE public.inventory_batches  SET crop_type = 'open_market' WHERE crop_type = 'da_amad_market';

-- ─── 6. CHECK constraints -> foreign keys ────────────────────────────────
-- Names are the live ones from pre-flight C1.
ALTER TABLE public.crop_master                  DROP CONSTRAINT crop_master_crop_type_check3;
ALTER TABLE public.crop_requests                DROP CONSTRAINT crop_requests_crop_type_check3;
ALTER TABLE public.inventory_batches            DROP CONSTRAINT inventory_batches_crop_type_check;
ALTER TABLE public.marketplace_listings         DROP CONSTRAINT marketplace_listings_crop_type_check;
ALTER TABLE public.cooperative_purchase_offers  DROP CONSTRAINT cooperative_purchase_offers_crop_type_check;
ALTER TABLE public.informal_sales               DROP CONSTRAINT informal_sales_crop_type_check;
ALTER TABLE public.price_records                DROP CONSTRAINT price_records_price_type_check3;

ALTER TABLE public.crop_master
  ADD CONSTRAINT crop_master_crop_type_fkey
  FOREIGN KEY (crop_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;
ALTER TABLE public.crop_requests
  ADD CONSTRAINT crop_requests_crop_type_fkey
  FOREIGN KEY (crop_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;
ALTER TABLE public.inventory_batches
  ADD CONSTRAINT inventory_batches_crop_type_fkey
  FOREIGN KEY (crop_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;
ALTER TABLE public.marketplace_listings
  ADD CONSTRAINT marketplace_listings_crop_type_fkey
  FOREIGN KEY (crop_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;
ALTER TABLE public.cooperative_purchase_offers
  ADD CONSTRAINT cooperative_purchase_offers_crop_type_fkey
  FOREIGN KEY (crop_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;
ALTER TABLE public.informal_sales
  ADD CONSTRAINT informal_sales_crop_type_fkey
  FOREIGN KEY (crop_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;
ALTER TABLE public.price_records
  ADD CONSTRAINT price_records_price_type_fkey
  FOREIGN KEY (price_type) REFERENCES public.market_types (code) ON UPDATE CASCADE;

-- ─── 7. The app can never assign an exclusive channel ────────────────────
-- A signed-in user (auth.uid() is set) cannot set or change it, whatever their
-- role. The SQL editor / database administrator (no auth.uid()) can.
CREATE OR REPLACE FUNCTION public.guard_crop_exclusive_channel()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND (TG_OP = 'INSERT' AND NEW.exclusive_channel IS NOT NULL
          OR TG_OP = 'UPDATE' AND NEW.exclusive_channel IS DISTINCT FROM OLD.exclusive_channel) THEN
    RAISE EXCEPTION 'A crop''s exclusive selling channel can only be set by a database administrator.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_crop_exclusive_channel ON public.crop_master;
CREATE TRIGGER trg_guard_crop_exclusive_channel
  BEFORE INSERT OR UPDATE OF exclusive_channel ON public.crop_master
  FOR EACH ROW EXECUTE FUNCTION public.guard_crop_exclusive_channel();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. Nothing stores da_amad_market any more (expect 0 on every line):
--    SELECT 'crop_master', count(*) FROM crop_master WHERE crop_type='da_amad_market'
--    UNION ALL SELECT 'crop_requests', count(*) FROM crop_requests WHERE crop_type='da_amad_market'
--    UNION ALL SELECT 'inventory_batches', count(*) FROM inventory_batches WHERE crop_type='da_amad_market'
--    UNION ALL SELECT 'price_records', count(*) FROM price_records WHERE price_type='da_amad_market';
--
-- 2. Ginger: Public Market, DA-AMAD channel, not cooperative-eligible
--    (expect 1 row: open_market | da_amad_market_linking | false):
--    SELECT crop_name, crop_type, exclusive_channel, is_cooperative_eligible
--    FROM crop_master WHERE exclusive_channel IS NOT NULL;
--
-- 3. Ginger's batch kept its stock and gained the channel
--    (expect 1 batch, open_market, da_amad_market_linking, available, 10.00 kg):
--    SELECT status, crop_type, exclusive_channel, available_kg
--    FROM inventory_batches WHERE exclusive_channel IS NOT NULL;
--
-- 4. Every other crop is unchanged (expect Banana, Copra, Eggplant, Potato, Tomato =
--    open_market; Palay, Peanut = sp3_cooperative; all is_cooperative_eligible = true
--    except Ginger):
--    SELECT crop_name, crop_type, exclusive_channel, is_cooperative_eligible
--    FROM crop_master ORDER BY crop_type, crop_name;
--
-- 5. The two tables hold the agreed rows (expect 2 and 4):
--    SELECT count(*) FROM market_types;  SELECT count(*) FROM selling_channels;
--
-- 6. The app cannot set the exclusive channel (expect the exception; nothing kept):
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<MANAGER_USER_ID>','role','authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      UPDATE public.crop_master SET exclusive_channel = 'da_amad_market_linking' WHERE crop_name = 'Banana';
--    ROLLBACK;
--
-- 7. A second crop cannot take the DA-AMAD channel (expect a unique-index error):
--    BEGIN;
--      UPDATE public.crop_master SET exclusive_channel = 'da_amad_market_linking' WHERE crop_name = 'Banana';
--    ROLLBACK;
-- ============================================================
