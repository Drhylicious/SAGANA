-- ============================================================
-- SAGANA — Crop Shelf Life Management  (script s01: foundation)
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it once in the Supabase SQL editor.
-- One transaction, safe to re-run. Then run s02 (existing data), then the
-- price-rules scripts r01 and r02.
--
-- WHAT IT ADDS
--   1. crop_master.shelf_life_days       the crop's default shelf life (days),
--                                        set in Crop Management.
--      crop_shelf_life_reference         the sourced figures gathered for this
--                                        feature; used to suggest a value.
--   2. shelf_life_settings               one row: the expiry-day Marketplace
--                                        discount percentage (Manager-set).
--   3. batch_shelf_life                  one row per harvest batch: its own
--                                        duration, expiry date, hold, loss.
--      listing_shelf_life                one row per listing that was discounted
--                                        or made unavailable by shelf life.
--      shelf_life_events                 the history used by the reports.
--      These are SEPARATE tables on purpose: Buyers can read inventory_batches
--      and marketplace_listings, and shelf-life data must never reach a Buyer.
--      Only the owning Farmer and staff can read the three tables.
--   4. Triggers (no existing function is replaced):
--        inventory_batches  AFTER INSERT   a new harvest batch gets its shelf
--                                          life from the crop; the countdown
--                                          starts at the harvest date.
--        inventory_batches  BEFORE UPDATE  a batch on HOLD (recorded when its
--                                          shelf life had already passed) cannot
--                                          be committed to ANY selling channel.
--        marketplace_listings BEFORE INSERT a batch past its shelf life cannot
--                                          be listed until the Farmer confirms it.
--        orders             BEFORE INSERT  an unavailable listing cannot be bought.
--        listing_edit_requests AFTER UPDATE an approved shelf-life review is applied.
--      plus a RESTRICTIVE read policy that hides an unavailable listing from
--      everyone except its Farmer, staff, and a Buyer who already ordered from it.
--   5. Functions the app calls:
--        confirm_batch_still_good(batch, days, price)
--        report_batch_rotten(batch, note)
--        process_shelf_life()        reminders, the expiry-day discount, and
--                                    making overdue listings unavailable.
--        get_my_listing_edit_requests()  now also returns the proposed shelf life.
--   6. public_marketplace_listings / public_listed_crop_names (guest browsing)
--      are patched IN PLACE from their live definition to skip unavailable
--      listings. Nothing else in them changes.
--   7. A daily pg_cron job for process_shelf_life() (skipped with a NOTICE where
--      pg_cron is not available; the app also runs it when the Farmer or staff
--      opens the related screens).
--
-- THE DAYS (Asia/Manila calendar days)
--   expiry date        = harvest date + shelf life days
--   expiry date - 1    the Farmer is reminded to check the produce
--   expiry date        the approved Marketplace listing is discounted
--   expiry date + 1    the listing becomes unavailable (unless confirmed)
--
-- NOT CHANGED: cooperative Inventory Management, Program Management, any
-- existing selling function, stock arithmetic, or the listing approval workflow.
-- ============================================================

BEGIN;

-- ═══ 0. Things this file relies on ══════════════════════════════════════
DO $$
BEGIN
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing. Run supabase_schema_role_based_staff_access.sql first.';
  END IF;
  IF to_regprocedure('public.staff_can_manage(text, uuid)') IS NULL THEN
    RAISE EXCEPTION 'staff_can_manage() is missing. Run supabase_schema_officer_permissions_01_foundation.sql first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='inventory_batches' AND column_name='adjusted_kg') THEN
    RAISE EXCEPTION 'Run supabase_schema_farmer_stock_management.sql first (inventory_batches.adjusted_kg is missing).';
  END IF;
  IF to_regclass('public.listing_edit_requests') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_listing_edit_approval.sql first (listing_edit_requests is missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='notifications' AND column_name='route_extra') THEN
    RAISE EXCEPTION 'notifications.route_extra is missing. Run supabase_schema_phase7_tap_to_navigate.sql first.';
  END IF;
END;
$$;

-- Today's date where the cooperative is.
CREATE OR REPLACE FUNCTION public._ph_today()
RETURNS date
LANGUAGE sql
STABLE
AS $$ SELECT (now() AT TIME ZONE 'Asia/Manila')::date; $$;

-- ═══ 1. The crop's default shelf life ═══════════════════════════════════
ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS shelf_life_days INTEGER
    CHECK (shelf_life_days IS NULL OR shelf_life_days BETWEEN 1 AND 3650);

COMMENT ON COLUMN public.crop_master.shelf_life_days IS
  'Default shelf life in days for a newly recorded harvest of this crop. '
  'NULL = not set yet: harvests of the crop are not tracked until it is.';

-- The figures gathered for this feature. One row per name a crop may go by
-- (lower case). Only figures with a source are listed; the Manager sets the rest.
CREATE TABLE IF NOT EXISTS public.crop_shelf_life_reference (
  crop_key        TEXT    PRIMARY KEY,
  shelf_life_days INTEGER NOT NULL CHECK (shelf_life_days BETWEEN 1 AND 3650),
  condition       TEXT    NOT NULL DEFAULT 'Ambient (about 27-32 C), no cold storage',
  source          TEXT    NOT NULL,
  source_url      TEXT
);

ALTER TABLE public.crop_shelf_life_reference ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "crop_shelf_life_reference: staff reads" ON public.crop_shelf_life_reference;
CREATE POLICY "crop_shelf_life_reference: staff reads"
  ON public.crop_shelf_life_reference FOR SELECT
  USING (public.is_staff());
REVOKE ALL ON public.crop_shelf_life_reference FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.crop_shelf_life_reference TO authenticated;

INSERT INTO public.crop_shelf_life_reference (crop_key, shelf_life_days, source, source_url) VALUES
  ('pechay',       3, 'Visayas State College of Agriculture study in NAST Transactions vol. 19 (1997): pechay became unmarketable in 2-3 days at ambient.',
                      'https://transactions.nast.ph/?p=5952'),
  ('petsay',       3, 'Same as pechay (NAST Transactions vol. 19, 1997).', 'https://transactions.nast.ph/?p=5952'),
  ('pak choi',     3, 'Same as pechay (NAST Transactions vol. 19, 1997).', 'https://transactions.nast.ph/?p=5952'),
  ('bok choy',     3, 'Same as pechay (NAST Transactions vol. 19, 1997).', 'https://transactions.nast.ph/?p=5952'),
  ('kangkong',     3, 'Study of Philippine indigenous leafy vegetables: kangkong (tinangkong) lasted 3 days at ambient.',
                      'https://www.researchgate.net/publication/383409734'),
  ('alugbati',     2, 'Study of Philippine indigenous leafy vegetables: alugbati lasted 2 days at ambient.',
                      'https://www.researchgate.net/publication/383409734'),
  ('malunggay',    2, 'Study of Philippine indigenous leafy vegetables: malunggay lasted 2 days at ambient.',
                      'https://www.researchgate.net/publication/383409734'),
  ('pako',         2, 'Study of Philippine indigenous leafy vegetables: pako lasted 2 days at ambient.',
                      'https://www.researchgate.net/publication/383409734'),
  ('eggplant',     5, 'Visayas State University study of eggplant: 4.5-7.1 days; about 5 days at ambient (25-28 C).',
                      'https://atr.vsu.edu.ph/wp-content/uploads/pdf_files/Volume35No.1/6.pdf'),
  ('talong',       5, 'Same as eggplant (Visayas State University).',
                      'https://atr.vsu.edu.ph/wp-content/uploads/pdf_files/Volume35No.1/6.pdf'),
  ('tomato',       7, 'NAST Transactions vol. 19 (1997): 7-13 days at ambient (27-32 C); the lower figure is used.',
                      'https://transactions.nast.ph/?p=5952'),
  ('kamatis',      7, 'Same as tomato (NAST Transactions vol. 19, 1997).', 'https://transactions.nast.ph/?p=5952'),
  ('ampalaya',     3, 'Philippine postharvest technology review (Nuevo and Apaga, 2010): bitter gourd held up to 3 days.',
                      'https://cci-hub.org/wp-content/uploads/2022/01/Technology-Reducing-Post-harvest-Losses-and-Maintaining-Quality-of-Fruits-and-Vegetables-Philippines-Nuevo-and-Apaga-2010-compressed.pdf'),
  ('bitter gourd', 3, 'Same as ampalaya (Nuevo and Apaga, 2010).',
                      'https://cci-hub.org/wp-content/uploads/2022/01/Technology-Reducing-Post-harvest-Losses-and-Maintaining-Quality-of-Fruits-and-Vegetables-Philippines-Nuevo-and-Apaga-2010-compressed.pdf')
ON CONFLICT (crop_key) DO NOTHING;

-- The reference figure for a crop name, if one is on file (whole-word match).
CREATE OR REPLACE FUNCTION public._reference_shelf_life(p_crop_name TEXT)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.shelf_life_days
  FROM public.crop_shelf_life_reference r
  WHERE lower(COALESCE(p_crop_name, '')) ~ ('(^|[^a-z])' || r.crop_key || '([^a-z]|$)')
  ORDER BY length(r.crop_key) DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._reference_shelf_life(TEXT) FROM PUBLIC, anon, authenticated;

-- A crop created without a shelf life (for example by approving a Farmer's crop
-- request) takes the reference figure when there is one. Otherwise it stays unset.
CREATE OR REPLACE FUNCTION public._crop_master_default_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.shelf_life_days IS NULL THEN
    NEW.shelf_life_days := public._reference_shelf_life(NEW.crop_name);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_crop_master_default_shelf_life ON public.crop_master;
CREATE TRIGGER trg_crop_master_default_shelf_life
  BEFORE INSERT ON public.crop_master
  FOR EACH ROW EXECUTE FUNCTION public._crop_master_default_shelf_life();

-- ═══ 2. The expiry-day discount (Manager-set) ═══════════════════════════
CREATE TABLE IF NOT EXISTS public.shelf_life_settings (
  id                      BOOLEAN      PRIMARY KEY DEFAULT TRUE CHECK (id),
  expiry_discount_percent NUMERIC(5,2) NOT NULL DEFAULT 20
                          CHECK (expiry_discount_percent >= 0 AND expiry_discount_percent <= 90),
  updated_by              UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
INSERT INTO public.shelf_life_settings (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.shelf_life_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "shelf_life_settings: staff reads" ON public.shelf_life_settings;
CREATE POLICY "shelf_life_settings: staff reads"
  ON public.shelf_life_settings FOR SELECT
  USING (public.is_staff());
DROP POLICY IF EXISTS "shelf_life_settings: managing staff updates" ON public.shelf_life_settings;
CREATE POLICY "shelf_life_settings: managing staff updates"
  ON public.shelf_life_settings FOR UPDATE
  USING (public.staff_can_manage('dashboard'))
  WITH CHECK (public.staff_can_manage('dashboard'));
REVOKE ALL ON public.shelf_life_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.shelf_life_settings TO authenticated;

-- Officers: governed by the Dashboard module, like crop_master and price_records.
-- (supabase_schema_officer_permissions_02_enforcement.sql rebuilds this mapping
--  when re-run; run this script again after it.)
DO $$
BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('table', 'shelf_life_settings', 'dashboard')
    ON CONFLICT (kind, name) DO NOTHING;
  END IF;
END;
$$;

-- ═══ 3. Per-batch tracking, per-listing state, history ══════════════════
CREATE TABLE IF NOT EXISTS public.batch_shelf_life (
  batch_id        UUID          PRIMARY KEY REFERENCES public.inventory_batches(id) ON DELETE CASCADE,
  farmer_id       UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- The crop's default when the harvest was recorded (NULL: crop had none).
  default_days    INTEGER,
  -- The duration now in effect, counted from starts_on. The Farmer's own figure
  -- after they confirm the produce is still good.
  shelf_life_days INTEGER       CHECK (shelf_life_days IS NULL OR shelf_life_days BETWEEN 1 AND 3650),
  starts_on       DATE,
  expires_on      DATE,
  -- Recorded when its shelf life had already passed: no selling channel may take
  -- this batch until the Farmer confirms it.
  hold            BOOLEAN       NOT NULL DEFAULT FALSE,
  confirmed_at    TIMESTAMPTZ,
  -- The expiry date the Farmer was already reminded about.
  notified_for    DATE,
  -- Quantity reported as rotten. It is part of inventory_batches.adjusted_kg.
  spoiled_kg      NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (spoiled_kg >= 0),
  spoiled_at      TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_batch_shelf_life_farmer  ON public.batch_shelf_life (farmer_id);
CREATE INDEX IF NOT EXISTS idx_batch_shelf_life_expires ON public.batch_shelf_life (expires_on);

CREATE TABLE IF NOT EXISTS public.listing_shelf_life (
  listing_id          UUID          PRIMARY KEY REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  farmer_id           UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  unavailable         BOOLEAN       NOT NULL DEFAULT FALSE,
  unavailable_since   TIMESTAMPTZ,
  -- The expiry date the automatic discount was applied for.
  discount_applied_on DATE,
  discount_percent    NUMERIC(5,2),
  pre_discount_price  NUMERIC(10,2),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_listing_shelf_life_farmer ON public.listing_shelf_life (farmer_id);

CREATE TABLE IF NOT EXISTS public.shelf_life_events (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id       UUID          NOT NULL REFERENCES public.inventory_batches(id) ON DELETE CASCADE,
  farmer_id      UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  listing_id     UUID          REFERENCES public.marketplace_listings(id) ON DELETE SET NULL,
  event_type     TEXT          NOT NULL CHECK (event_type IN (
                   'held_overdue', 'reminder_sent', 'confirmed_good', 'reported_rotten',
                   'discount_applied', 'listing_unavailable', 'review_requested', 'review_approved')),
  crop_name      TEXT,
  batch_number   TEXT,
  quantity       NUMERIC(10,2),
  unit           TEXT,
  days           INTEGER,
  old_expires_on DATE,
  new_expires_on DATE,
  price_from     NUMERIC(10,2),
  price_to       NUMERIC(10,2),
  note           TEXT,
  actor_id       UUID,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_shelf_life_events_batch  ON public.shelf_life_events (batch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shelf_life_events_farmer ON public.shelf_life_events (farmer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shelf_life_events_type   ON public.shelf_life_events (event_type, created_at DESC);

ALTER TABLE public.batch_shelf_life   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_shelf_life ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shelf_life_events  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "batch_shelf_life: farmer reads own" ON public.batch_shelf_life;
CREATE POLICY "batch_shelf_life: farmer reads own"
  ON public.batch_shelf_life FOR SELECT TO authenticated USING (farmer_id = auth.uid());
DROP POLICY IF EXISTS "batch_shelf_life: staff reads all" ON public.batch_shelf_life;
CREATE POLICY "batch_shelf_life: staff reads all"
  ON public.batch_shelf_life FOR SELECT TO authenticated USING (public.is_staff());

DROP POLICY IF EXISTS "listing_shelf_life: farmer reads own" ON public.listing_shelf_life;
CREATE POLICY "listing_shelf_life: farmer reads own"
  ON public.listing_shelf_life FOR SELECT TO authenticated USING (farmer_id = auth.uid());
DROP POLICY IF EXISTS "listing_shelf_life: staff reads all" ON public.listing_shelf_life;
CREATE POLICY "listing_shelf_life: staff reads all"
  ON public.listing_shelf_life FOR SELECT TO authenticated USING (public.is_staff());

DROP POLICY IF EXISTS "shelf_life_events: farmer reads own" ON public.shelf_life_events;
CREATE POLICY "shelf_life_events: farmer reads own"
  ON public.shelf_life_events FOR SELECT TO authenticated USING (farmer_id = auth.uid());
DROP POLICY IF EXISTS "shelf_life_events: staff reads all" ON public.shelf_life_events;
CREATE POLICY "shelf_life_events: staff reads all"
  ON public.shelf_life_events FOR SELECT TO authenticated USING (public.is_staff());

-- Written only by the functions and triggers below.
REVOKE ALL ON public.batch_shelf_life, public.listing_shelf_life, public.shelf_life_events
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.batch_shelf_life, public.listing_shelf_life, public.shelf_life_events
  TO authenticated;

-- A shelf-life review rides on the existing edit-request workflow.
ALTER TABLE public.listing_edit_requests
  ADD COLUMN IF NOT EXISTS proposed_shelf_life_days INTEGER
    CHECK (proposed_shelf_life_days IS NULL OR proposed_shelf_life_days BETWEEN 1 AND 365);

COMMENT ON COLUMN public.listing_edit_requests.proposed_shelf_life_days IS
  'Set when the request is a shelf-life review: the remaining days the Farmer '
  'gives the produce after checking it. Applied to the harvest batch on approval.';

-- ─── Small helpers ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._shelf_life_event(
  p_batch UUID, p_type TEXT, p_listing UUID DEFAULT NULL, p_quantity NUMERIC DEFAULT NULL,
  p_days INTEGER DEFAULT NULL, p_old DATE DEFAULT NULL, p_new DATE DEFAULT NULL,
  p_price_from NUMERIC DEFAULT NULL, p_price_to NUMERIC DEFAULT NULL, p_note TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO shelf_life_events (batch_id, farmer_id, listing_id, event_type, crop_name, batch_number,
                                 quantity, unit, days, old_expires_on, new_expires_on,
                                 price_from, price_to, note, actor_id)
  SELECT b.id, b.farmer_id, p_listing, p_type, b.crop_name, b.batch_number,
         p_quantity, b.unit, p_days, p_old, p_new, p_price_from, p_price_to,
         NULLIF(btrim(COALESCE(p_note, '')), ''), auth.uid()
  FROM inventory_batches b WHERE b.id = p_batch;
$$;
REVOKE ALL ON FUNCTION public._shelf_life_event(UUID, TEXT, UUID, NUMERIC, INTEGER, DATE, DATE, NUMERIC, NUMERIC, TEXT)
  FROM PUBLIC, anon, authenticated;

-- Tapping one of these notices opens Manage Inventory on the batch.
CREATE OR REPLACE FUNCTION public._shelf_life_notify_farmer(
  p_farmer UUID, p_batch UUID, p_title TEXT, p_body TEXT
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap, route_extra)
  VALUES (p_farmer, 'listing', p_title, p_body, FALSE, NOW(), '/farmer/harvest/inventory', p_batch::text);
$$;
REVOKE ALL ON FUNCTION public._shelf_life_notify_farmer(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._listing_shelf_unavailable(p_listing_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT x.unavailable FROM listing_shelf_life x WHERE x.listing_id = p_listing_id), FALSE);
$$;
REVOKE ALL ON FUNCTION public._listing_shelf_unavailable(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._listing_shelf_unavailable(UUID) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public._user_ordered_listing(p_listing_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM orders o WHERE o.listing_id = p_listing_id AND o.buyer_id = auth.uid());
$$;
REVOKE ALL ON FUNCTION public._user_ordered_listing(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._user_ordered_listing(UUID) TO anon, authenticated;

-- ═══ 4. A new harvest batch starts its own countdown ════════════════════
-- Fires for every batch, however it was created (Record New Harvest, an offline
-- harvest when it syncs, produce received from a program). The countdown starts
-- at the HARVEST DATE, never when the crop was added to the Crop Roster.
CREATE OR REPLACE FUNCTION public._batch_shelf_life_init()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days    INTEGER;
  v_date    DATE;
  v_expires DATE;
  v_hold    BOOLEAN;
BEGIN
  SELECT cm.shelf_life_days INTO v_days
  FROM farmer_crops fc
  JOIN crop_master cm ON cm.id = fc.crop_master_id
  WHERE fc.id = NEW.crop_id;

  IF v_days IS NULL THEN
    RETURN NULL;                         -- the crop has no shelf life set: not tracked
  END IF;

  SELECT hr.harvest_date INTO v_date FROM harvest_records hr WHERE hr.id = NEW.harvest_record_id;
  v_date    := COALESCE(v_date, public._ph_today());
  v_expires := v_date + v_days;
  v_hold    := v_expires < public._ph_today();

  INSERT INTO batch_shelf_life (batch_id, farmer_id, default_days, shelf_life_days, starts_on, expires_on, hold)
  VALUES (NEW.id, NEW.farmer_id, v_days, v_days, v_date, v_expires, v_hold)
  ON CONFLICT (batch_id) DO NOTHING;

  IF v_hold THEN
    PERFORM public._shelf_life_event(NEW.id, 'held_overdue', NULL, NEW.quantity_kg, v_days, NULL, v_expires);
    PERFORM public._shelf_life_notify_farmer(
      NEW.farmer_id, NEW.id,
      'Check Your ' || NEW.crop_name,
      'The harvest date of your ' || NEW.crop_name || ' (' || NEW.batch_number ||
        ') is already beyond its ' || v_days || '-day shelf life. Check the produce and confirm it is still good before selling it.');
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._batch_shelf_life_init() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_inventory_batches_shelf_life_init ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_shelf_life_init
  AFTER INSERT ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public._batch_shelf_life_init();

-- A crop that had NO shelf life and now gets its first one: its harvest batches
-- that still hold stock start being tracked from that day. Changing an existing
-- shelf life only affects harvests recorded afterwards (it is the default for new
-- harvests), so batches already tracked are left alone.
CREATE OR REPLACE FUNCTION public._crop_master_first_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO batch_shelf_life (batch_id, farmer_id, default_days, shelf_life_days, starts_on, expires_on)
  SELECT b.id, b.farmer_id, NEW.shelf_life_days, NEW.shelf_life_days,
         public._ph_today(), public._ph_today() + NEW.shelf_life_days
  FROM inventory_batches b
  JOIN farmer_crops fc ON fc.id = b.crop_id
  WHERE fc.crop_master_id = NEW.id
    AND b.available_kg + b.reserved_kg > 0
  ON CONFLICT (batch_id) DO UPDATE
    SET default_days    = EXCLUDED.default_days,
        shelf_life_days = EXCLUDED.shelf_life_days,
        starts_on       = EXCLUDED.starts_on,
        expires_on      = EXCLUDED.expires_on,
        updated_at      = NOW()
    WHERE batch_shelf_life.shelf_life_days IS NULL;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._crop_master_first_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_crop_master_first_shelf_life ON public.crop_master;
CREATE TRIGGER trg_crop_master_first_shelf_life
  AFTER UPDATE OF shelf_life_days ON public.crop_master
  FOR EACH ROW
  WHEN (OLD.shelf_life_days IS NULL AND NEW.shelf_life_days IS NOT NULL)
  EXECUTE FUNCTION public._crop_master_first_shelf_life();

-- ═══ 5. A batch on hold cannot be sold through any channel ══════════════
-- Every channel (Marketplace, Offer to Cooperative, Informal Sale, DA-AMAD Market
-- Linking) commits stock by lowering available_kg, so this one rule covers all of
-- them. Taking stock out with Update Quantity or reporting it rotten is allowed.
CREATE OR REPLACE FUNCTION public._batch_shelf_life_sell_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_committed NUMERIC;
BEGIN
  -- Kg leaving "available" for a reservation or a sale (not an adjustment).
  v_committed := (NEW.quantity_kg - OLD.quantity_kg)
               - (NEW.available_kg - OLD.available_kg)
               - (NEW.adjusted_kg - OLD.adjusted_kg);
  IF v_committed >= 0.005
     AND EXISTS (SELECT 1 FROM batch_shelf_life s WHERE s.batch_id = NEW.id AND s.hold) THEN
    RAISE EXCEPTION 'SHELF_LIFE_HOLD: This harvest was recorded after its shelf life had already passed. Check the produce and confirm it is still good in Manage Inventory before selling it.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._batch_shelf_life_sell_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_inventory_batches_shelf_life_guard ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_shelf_life_guard
  BEFORE UPDATE ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public._batch_shelf_life_sell_guard();

-- ═══ 6. Marketplace only: no new listing from a batch past its shelf life ══
CREATE OR REPLACE FUNCTION public._listing_shelf_life_insert_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.inventory_batch_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM batch_shelf_life s
                 WHERE s.batch_id = NEW.inventory_batch_id
                   AND (s.hold OR s.expires_on < public._ph_today())) THEN
    RAISE EXCEPTION 'SHELF_LIFE_EXPIRED: This harvest is past its shelf life. Check the produce and confirm it is still good in Manage Inventory before listing it on the Marketplace.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._listing_shelf_life_insert_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_listings_shelf_life_insert_guard ON public.marketplace_listings;
CREATE TRIGGER trg_listings_shelf_life_insert_guard
  BEFORE INSERT ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._listing_shelf_life_insert_guard();

-- ═══ 7. An unavailable listing cannot be bought, and Buyers do not see it ══
CREATE OR REPLACE FUNCTION public._orders_shelf_life_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.listing_id IS NOT NULL AND public._listing_shelf_unavailable(NEW.listing_id) THEN
    RAISE EXCEPTION 'This listing is currently unavailable. Please choose another listing.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._orders_shelf_life_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_orders_shelf_life_guard ON public.orders;
CREATE TRIGGER trg_orders_shelf_life_guard
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_shelf_life_guard();

-- RESTRICTIVE: it only ever narrows what the existing policies already allow.
DROP POLICY IF EXISTS "marketplace_listings: shelf-life unavailable hidden" ON public.marketplace_listings;
CREATE POLICY "marketplace_listings: shelf-life unavailable hidden"
  ON public.marketplace_listings
  AS RESTRICTIVE
  FOR SELECT
  USING (
    farmer_id = auth.uid()
    OR NOT public._listing_shelf_unavailable(id)
    OR public.is_staff()
    OR public._user_ordered_listing(id)
  );

-- Guest browsing reads through two SECURITY DEFINER functions, which the policy
-- above does not reach. Each is patched in place from its LIVE definition: one
-- condition is added next to "status = 'approved'" and nothing else is touched.
DO $patch$
DECLARE
  v_oid oid;
  v_def text;
  v_new text;
BEGIN
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('public_marketplace_listings', 'public_listed_crop_names')
  LOOP
    v_def := pg_get_functiondef(v_oid);
    IF v_def ILIKE '%_listing_shelf_unavailable%' THEN
      CONTINUE;                                   -- already patched
    END IF;
    v_new := regexp_replace(
      v_def,
      $p$(ml\.status\s*=\s*'approved')$p$,
      '\1 AND NOT public._listing_shelf_unavailable(ml.id)',
      'i');
    IF v_new = v_def THEN
      RAISE NOTICE '%: no "ml.status = ''approved''" condition found, left unchanged. Send me its live definition.', v_oid::regprocedure;
      CONTINUE;
    END IF;
    EXECUTE v_new;
  END LOOP;
END
$patch$;

-- ═══ 8. The Farmer confirms the produce is still good ═══════════════════
-- p_days   the remaining shelf life, in days from today, after checking it.
-- p_price  only used when a published listing needs approval (see below);
--          NULL keeps the price it had before the automatic discount.
-- Returns 'applied' (took effect now) or 'submitted' (waiting for the Manager /
-- Officer, because a published listing was already discounted or unavailable).
CREATE OR REPLACE FUNCTION public.confirm_batch_still_good(
  p_batch_id UUID,
  p_days     INTEGER,
  p_price    NUMERIC DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_role    TEXT;
  v_status  TEXT;
  b         inventory_batches%ROWTYPE;
  s         batch_shelf_life%ROWTYPE;
  l         RECORD;
  v_today   DATE := public._ph_today();
  v_price   NUMERIC;
  v_request UUID;
  v_sent    INTEGER := 0;
  v_name    TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can confirm a harvest.';
  END IF;

  SELECT * INTO b FROM inventory_batches WHERE id = p_batch_id AND farmer_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;
  IF p_days IS NULL OR p_days < 1 OR p_days > 365 THEN
    RAISE EXCEPTION 'Enter the remaining shelf life as a whole number of days, from 1 to 365.';
  END IF;
  IF b.available_kg + b.reserved_kg <= 0 THEN
    RAISE EXCEPTION 'Nothing is left in this batch to confirm.';
  END IF;

  SELECT * INTO s FROM batch_shelf_life WHERE batch_id = b.id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO batch_shelf_life (batch_id, farmer_id) VALUES (b.id, v_uid) RETURNING * INTO s;
  END IF;

  -- Published listings already discounted or made unavailable: the change must be
  -- approved before it takes effect in the Marketplace.
  FOR l IN
    SELECT ml.*, x.pre_discount_price, x.discount_applied_on, x.unavailable
    FROM marketplace_listings ml
    JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE ml.inventory_batch_id = b.id
      AND ml.status = 'approved'
      AND ml.remaining_kg > 0
      AND (x.unavailable OR x.discount_applied_on IS NOT NULL)
    ORDER BY ml.created_at
    FOR UPDATE OF ml
  LOOP
    IF EXISTS (SELECT 1 FROM listing_edit_requests r
               WHERE r.listing_id = l.id AND r.status = 'pending'
                 AND r.proposed_shelf_life_days IS NOT NULL) THEN
      RAISE EXCEPTION 'Your shelf-life update for this listing is already waiting for approval.';
    END IF;

    v_price := COALESCE(p_price, l.pre_discount_price, l.price_per_kg);
    IF v_price <= 0 THEN
      RAISE EXCEPTION 'Enter a price greater than zero.';
    END IF;
    IF v_price <> round(v_price, 2) THEN
      RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
    END IF;
    IF v_price > 99999999.99 THEN
      RAISE EXCEPTION 'The price is too large.';
    END IF;

    -- An ordinary edit still waiting on this listing is replaced by this review.
    UPDATE listing_edit_requests
       SET status = 'cancelled', reviewed_at = NOW(),
           review_reason = 'Replaced by a shelf-life review.'
     WHERE listing_id = l.id AND status = 'pending';

    INSERT INTO listing_edit_requests (
      listing_id, farmer_id, unit,
      original_quantity, original_price, original_description, original_photo_url,
      proposed_quantity, proposed_price, proposed_description, proposed_photo_url,
      proposed_shelf_life_days
    ) VALUES (
      l.id, v_uid, l.unit,
      l.volume_kg, l.price_per_kg, l.description, l.photo_url,
      l.volume_kg, v_price, btrim(COALESCE(l.description, '')), NULL,
      p_days
    ) RETURNING id INTO v_request;

    PERFORM public._wf_log('listing', l.id, 'edit_requested', l.status, l.status, NULL,
      jsonb_build_object('request_id', v_request, 'unit', l.unit, 'shelf_life_days', p_days,
        'changes', jsonb_strip_nulls(jsonb_build_object(
          'price', CASE WHEN v_price <> l.price_per_kg
                        THEN jsonb_build_object('from', l.price_per_kg, 'to', v_price) END))));

    PERFORM public._shelf_life_event(b.id, 'review_requested', l.id, l.remaining_kg, p_days,
                                     s.expires_on, v_today + p_days, l.price_per_kg, v_price);
    v_sent := v_sent + 1;
  END LOOP;

  IF v_sent > 0 THEN
    UPDATE batch_shelf_life SET confirmed_at = NOW(), updated_at = NOW() WHERE batch_id = b.id;
    SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
    PERFORM public.notify_staff(
      'listing',
      'Shelf-Life Review for Approval',
      COALESCE(v_name, 'A farmer') || ' checked their ' || b.crop_name || ' (' || b.batch_number ||
        ') and says it is still good for ' || p_days || ' more day(s). Review the listing''s price and shelf life.',
      '/admin/marketplace/pending');
    RETURN 'submitted';
  END IF;

  -- Nothing published is affected: the Farmer's assessment applies at once.
  UPDATE batch_shelf_life
     SET shelf_life_days = p_days,
         starts_on       = v_today,
         expires_on      = v_today + p_days,
         hold            = FALSE,
         confirmed_at    = NOW(),
         notified_for    = NULL,
         updated_at      = NOW()
   WHERE batch_id = b.id;

  -- A listing still waiting for its first approval was never published, so its
  -- shelf-life flags are simply cleared; the reviewer sees the new duration.
  UPDATE listing_shelf_life x
     SET unavailable = FALSE, unavailable_since = NULL, updated_at = NOW()
   WHERE x.unavailable
     AND x.listing_id IN (SELECT ml.id FROM marketplace_listings ml
                          WHERE ml.inventory_batch_id = b.id AND ml.status = 'pending_review');

  PERFORM public._shelf_life_event(b.id, 'confirmed_good', NULL, b.available_kg + b.reserved_kg,
                                   p_days, s.expires_on, v_today + p_days);
  RETURN 'applied';
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_batch_still_good(UUID, INTEGER, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_batch_still_good(UUID, INTEGER, NUMERIC) TO authenticated;

-- An approved shelf-life review is applied to the harvest batch and the listing
-- becomes available again. approve_listing_edit() itself is not changed: it has
-- already applied the price when this runs.
CREATE OR REPLACE FUNCTION public._listing_edit_apply_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch UUID;
  v_old   DATE;
  v_today DATE := public._ph_today();
BEGIN
  SELECT inventory_batch_id INTO v_batch FROM marketplace_listings WHERE id = NEW.listing_id;

  UPDATE listing_shelf_life
     SET unavailable = FALSE, unavailable_since = NULL,
         discount_applied_on = NULL, discount_percent = NULL, pre_discount_price = NULL,
         updated_at = NOW()
   WHERE listing_id = NEW.listing_id;

  IF v_batch IS NOT NULL THEN
    SELECT expires_on INTO v_old FROM batch_shelf_life WHERE batch_id = v_batch;
    UPDATE batch_shelf_life
       SET shelf_life_days = NEW.proposed_shelf_life_days,
           starts_on       = v_today,
           expires_on      = v_today + NEW.proposed_shelf_life_days,
           hold            = FALSE,
           notified_for    = NULL,
           updated_at      = NOW()
     WHERE batch_id = v_batch;
    PERFORM public._shelf_life_event(v_batch, 'review_approved', NEW.listing_id, NEW.proposed_quantity,
                                     NEW.proposed_shelf_life_days, v_old,
                                     v_today + NEW.proposed_shelf_life_days,
                                     NEW.original_price, NEW.proposed_price);
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._listing_edit_apply_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_listing_edit_apply_shelf_life ON public.listing_edit_requests;
CREATE TRIGGER trg_listing_edit_apply_shelf_life
  AFTER UPDATE OF status ON public.listing_edit_requests
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved'
        AND NEW.proposed_shelf_life_days IS NOT NULL)
  EXECUTE FUNCTION public._listing_edit_apply_shelf_life();

-- ═══ 9. The Farmer reports the produce as rotten ════════════════════════
-- The loss is what is still unsold: the batch's available quantity plus whatever
-- its Marketplace listings had not sold yet. Quantities already ordered by a
-- Buyer, accepted in a cooperative offer or committed to a DA-AMAD request are
-- not touched (they follow their own workflow). No other batch is affected.
-- Returns the quantity recorded as a loss.
CREATE OR REPLACE FUNCTION public.report_batch_rotten(
  p_batch_id UUID,
  p_note     TEXT DEFAULT NULL
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_role     TEXT;
  v_status   TEXT;
  b          inventory_batches%ROWTYPE;
  l          marketplace_listings%ROWTYPE;
  v_released NUMERIC := 0;
  v_ordered  NUMERIC;
  v_loss     NUMERIC;
  v_adjusted NUMERIC;
  v_name     TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can report a loss.';
  END IF;

  SELECT * INTO b FROM inventory_batches WHERE id = p_batch_id AND farmer_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;

  -- Take the unsold part of every open listing of this batch off the Marketplace.
  FOR l IN
    SELECT * FROM marketplace_listings
    WHERE inventory_batch_id = b.id
      AND status IN ('pending_review', 'approved')
      AND remaining_kg > 0
    FOR UPDATE
  LOOP
    v_released := v_released + l.remaining_kg;
    v_ordered  := l.volume_kg - l.remaining_kg;
    IF l.status = 'pending_review' OR v_ordered <= 0 THEN
      UPDATE marketplace_listings SET status = 'withdrawn', remaining_kg = 0 WHERE id = l.id;
    ELSE
      -- Buyers already ordered part of it: the listing keeps those orders and
      -- simply has nothing left to buy (it reads Sold Out).
      UPDATE marketplace_listings SET volume_kg = v_ordered, remaining_kg = 0 WHERE id = l.id;
    END IF;
    UPDATE listing_shelf_life
       SET unavailable = FALSE, unavailable_since = NULL, updated_at = NOW()
     WHERE listing_id = l.id;
  END LOOP;

  v_loss := round(b.available_kg + v_released, 2);
  IF v_loss <= 0 THEN
    RAISE EXCEPTION 'Nothing is left in this batch to report as a loss.';
  END IF;

  v_adjusted := b.adjusted_kg + v_loss;
  UPDATE inventory_batches
     SET available_kg = 0,
         adjusted_kg  = v_adjusted,
         status       = CASE WHEN b.sold_kg + v_adjusted >= b.quantity_kg THEN 'sold_out' ELSE 'reserved' END
   WHERE id = b.id;

  -- Say what this adjustment was in the batch's stock history.
  UPDATE stock_movements
     SET note = 'Reported as rotten (loss)'
   WHERE batch_id = b.id AND txid = txid_current() AND movement_type = 'adjusted';

  INSERT INTO batch_shelf_life (batch_id, farmer_id, spoiled_kg, spoiled_at)
  VALUES (b.id, v_uid, v_loss, NOW())
  ON CONFLICT (batch_id) DO UPDATE
    SET spoiled_kg = batch_shelf_life.spoiled_kg + EXCLUDED.spoiled_kg,
        spoiled_at = NOW(),
        hold       = FALSE,
        updated_at = NOW();

  PERFORM public._shelf_life_event(b.id, 'reported_rotten', NULL, v_loss, NULL, NULL, NULL, NULL, NULL, p_note);

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'listing',
    'Harvest Loss Reported',
    COALESCE(v_name, 'A farmer') || ' reported ' || v_loss || ' ' || COALESCE(b.unit, 'kg') || ' of ' ||
      b.crop_name || ' (' || b.batch_number || ') as rotten. It is recorded as a loss.',
    '/admin/reports');

  RETURN v_loss;
END;
$$;
REVOKE ALL ON FUNCTION public.report_batch_rotten(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_batch_rotten(UUID, TEXT) TO authenticated;

-- ═══ 10. The daily pass: reminder, discount, unavailable ════════════════
-- Idempotent: every step records what it did, so running it again the same day
-- (the scheduled job and the app both call it) changes nothing more.
-- These three steps are MARKETPLACE rules. Offer to Cooperative, Informal Sale
-- and DA-AMAD Market Linking are not touched by them.
CREATE OR REPLACE FUNCTION public.process_shelf_life()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today     DATE := public._ph_today();
  v_pct       NUMERIC;
  r           RECORD;
  v_new_price NUMERIC;
  v_reminded  INTEGER := 0;
  v_discount  INTEGER := 0;
  v_unavail   INTEGER := 0;
BEGIN
  SELECT expiry_discount_percent INTO v_pct FROM shelf_life_settings WHERE id;
  v_pct := COALESCE(v_pct, 0);

  -- 1. The day before the expiry date: ask the Farmer to check the produce.
  FOR r IN
    SELECT s.batch_id, s.farmer_id, s.expires_on, s.shelf_life_days, b.crop_name, b.batch_number,
           b.available_kg + b.reserved_kg AS left_kg
    FROM batch_shelf_life s
    JOIN inventory_batches b ON b.id = s.batch_id
    WHERE s.expires_on BETWEEN v_today AND v_today + 1
      AND s.notified_for IS DISTINCT FROM s.expires_on
      AND EXISTS (SELECT 1 FROM marketplace_listings ml
                  WHERE ml.inventory_batch_id = s.batch_id
                    AND ml.status IN ('pending_review', 'approved')
                    AND ml.remaining_kg > 0)
    FOR UPDATE OF s SKIP LOCKED
  LOOP
    UPDATE batch_shelf_life SET notified_for = r.expires_on, updated_at = NOW() WHERE batch_id = r.batch_id;
    PERFORM public._shelf_life_notify_farmer(
      r.farmer_id, r.batch_id,
      'Check Your ' || r.crop_name,
      'Your ' || r.crop_name || ' is nearing its shelf life or expiration. Please manually check your harvested ' ||
        r.crop_name || '.');
    PERFORM public._shelf_life_event(r.batch_id, 'reminder_sent', NULL, r.left_kg, r.shelf_life_days, NULL, r.expires_on);
    v_reminded := v_reminded + 1;
  END LOOP;

  -- 2. On the expiry date: discount the published listing, once per expiry date.
  IF v_pct > 0 THEN
    FOR r IN
      SELECT ml.id, ml.farmer_id, ml.crop_name, ml.price_per_kg, ml.unit, ml.remaining_kg,
             s.batch_id, s.expires_on
      FROM marketplace_listings ml
      JOIN batch_shelf_life s ON s.batch_id = ml.inventory_batch_id
      LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
      WHERE ml.status = 'approved'
        AND ml.remaining_kg > 0
        AND s.expires_on = v_today
        AND x.discount_applied_on IS DISTINCT FROM s.expires_on
        AND NOT COALESCE(x.unavailable, FALSE)
      FOR UPDATE OF ml SKIP LOCKED
    LOOP
      v_new_price := GREATEST(round(r.price_per_kg * (1 - v_pct / 100), 2), 0.01);

      INSERT INTO listing_shelf_life (listing_id, farmer_id, discount_applied_on, discount_percent, pre_discount_price)
      VALUES (r.id, r.farmer_id, r.expires_on, v_pct, r.price_per_kg)
      ON CONFLICT (listing_id) DO UPDATE
        SET discount_applied_on = EXCLUDED.discount_applied_on,
            discount_percent    = EXCLUDED.discount_percent,
            pre_discount_price  = EXCLUDED.pre_discount_price,
            updated_at          = NOW();

      -- The system discount is the one price change the Price Management limits
      -- do not apply to (see the price-rules script).
      PERFORM set_config('sagana.shelf_discount', '1', true);
      UPDATE marketplace_listings SET price_per_kg = v_new_price WHERE id = r.id;
      PERFORM set_config('sagana.shelf_discount', '0', true);

      PERFORM public._shelf_life_notify_farmer(
        r.farmer_id, r.batch_id,
        r.crop_name || ' Listing Discounted',
        'Your ' || r.crop_name || ' reached its shelf life today, so its Marketplace price was reduced by ' ||
          rtrim(to_char(v_pct, 'FM990.99'), '.') || '% (from ₱' || to_char(r.price_per_kg, 'FM999999990.00') ||
          ' to ₱' || to_char(v_new_price, 'FM999999990.00') || ' per ' || r.unit ||
          '). Check the produce: you can adjust the price or its shelf life (needs approval), or report it as rotten.');
      PERFORM public._shelf_life_event(r.batch_id, 'discount_applied', r.id, r.remaining_kg, NULL, NULL,
                                       r.expires_on, r.price_per_kg, v_new_price);
      v_discount := v_discount + 1;
    END LOOP;
  END IF;

  -- 3. The day after: the listing becomes unavailable until the Farmer confirms
  --    the produce and the cooperative approves. A listing whose shelf-life
  --    review is already waiting for approval is left as it is until decided.
  FOR r IN
    SELECT ml.id, ml.farmer_id, ml.crop_name, ml.remaining_kg, s.batch_id, s.expires_on
    FROM marketplace_listings ml
    JOIN batch_shelf_life s ON s.batch_id = ml.inventory_batch_id
    LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE ml.status IN ('pending_review', 'approved')
      AND ml.remaining_kg > 0
      AND s.expires_on < v_today
      AND NOT COALESCE(x.unavailable, FALSE)
      AND NOT EXISTS (SELECT 1 FROM listing_edit_requests q
                      WHERE q.listing_id = ml.id AND q.status = 'pending'
                        AND q.proposed_shelf_life_days IS NOT NULL)
    FOR UPDATE OF ml SKIP LOCKED
  LOOP
    INSERT INTO listing_shelf_life (listing_id, farmer_id, unavailable, unavailable_since)
    VALUES (r.id, r.farmer_id, TRUE, NOW())
    ON CONFLICT (listing_id) DO UPDATE
      SET unavailable = TRUE, unavailable_since = NOW(), updated_at = NOW();

    PERFORM public._shelf_life_notify_farmer(
      r.farmer_id, r.batch_id,
      r.crop_name || ' Listing Unavailable',
      'Your ' || r.crop_name || ' is past its shelf life, so its Marketplace listing is now unavailable to buyers. ' ||
        'Check the produce: confirm it is still good (needs approval) to make it available again, or report it as rotten.');
    PERFORM public._shelf_life_event(r.batch_id, 'listing_unavailable', r.id, r.remaining_kg, NULL, NULL, r.expires_on);
    v_unavail := v_unavail + 1;
  END LOOP;

  RETURN jsonb_build_object('date', v_today, 'reminded', v_reminded,
                            'discounted', v_discount, 'made_unavailable', v_unavail);
END;
$$;
REVOKE ALL ON FUNCTION public.process_shelf_life() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_shelf_life() TO authenticated;

-- ═══ 11. The Farmer's own edit requests now show the proposed shelf life ══
-- Same function as supabase_schema_listing_edit_approval.sql with one more field.
CREATE OR REPLACE FUNCTION public.get_my_listing_edit_requests(p_listing_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
  FROM (
    SELECT r.id, r.listing_id, r.status, r.unit,
           r.original_quantity, r.original_price, r.original_description, r.original_photo_url,
           r.proposed_quantity, r.proposed_price, r.proposed_description, r.proposed_photo_url,
           r.proposed_shelf_life_days,
           r.review_reason, r.reviewed_at, r.created_at
    FROM public.listing_edit_requests r
    WHERE r.listing_id = p_listing_id AND r.farmer_id = auth.uid()
    ORDER BY r.created_at DESC
    LIMIT 50
  ) x;
$$;
REVOKE ALL ON FUNCTION public.get_my_listing_edit_requests(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_listing_edit_requests(UUID) TO authenticated;

-- ═══ 12. Live screens ═══════════════════════════════════════════════════
DO $$
DECLARE t TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH t IN ARRAY ARRAY['batch_shelf_life', 'listing_shelf_life'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      END IF;
    END LOOP;
  END IF;
END;
$$;

COMMIT;

-- ═══ 13. Daily schedule (outside the transaction: it may be unavailable) ══
-- 16:05 UTC = 00:05 in the Philippines. Where pg_cron cannot be enabled this
-- logs a NOTICE and moves on; the app still runs process_shelf_life() whenever a
-- Farmer opens Manage Inventory or their listings, or staff open the listings.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.schedule(
    'run-daily-shelf-life',
    '5 16 * * *',
    $cron$ SELECT public.process_shelf_life(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron scheduling skipped (likely unavailable on this plan): %', SQLERRM;
END;
$$;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS (read-only; run after the script) ────────────────────────────
-- C1  The new objects exist (expect 5 tables, 4 functions):
--     SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN
--       ('crop_shelf_life_reference','shelf_life_settings','batch_shelf_life','listing_shelf_life','shelf_life_events');
--     SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
--       ('confirm_batch_still_good','report_batch_rotten','process_shelf_life','get_my_listing_edit_requests');
-- C2  The triggers are in place (expect 7 rows):
--     SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
--       ('trg_crop_master_default_shelf_life','trg_crop_master_first_shelf_life',
--        'trg_inventory_batches_shelf_life_init',
--        'trg_inventory_batches_shelf_life_guard','trg_listings_shelf_life_insert_guard',
--        'trg_orders_shelf_life_guard','trg_listing_edit_apply_shelf_life');
-- C3  Buyers and guests cannot read shelf-life data (expect false on every column):
--     SELECT has_table_privilege('anon','public.batch_shelf_life','SELECT')   AS anon_batch,
--            has_table_privilege('anon','public.listing_shelf_life','SELECT') AS anon_listing,
--            has_table_privilege('anon','public.shelf_life_events','SELECT')  AS anon_events;
--     SELECT tablename, policyname FROM pg_policies
--      WHERE tablename IN ('batch_shelf_life','listing_shelf_life','shelf_life_events') ORDER BY 1, 2;
-- C4  Guest browsing skips unavailable listings (expect true, true):
--     SELECT proname, pg_get_functiondef(oid) ILIKE '%_listing_shelf_unavailable%' AS patched
--       FROM pg_proc WHERE pronamespace='public'::regnamespace
--        AND proname IN ('public_marketplace_listings','public_listed_crop_names');
-- C5  The schedule (one row; none if pg_cron is unavailable):
--     SELECT jobname, schedule FROM cron.job WHERE jobname = 'run-daily-shelf-life';
-- C6  The discount setting:
--     SELECT expiry_discount_percent FROM shelf_life_settings;
