-- ============================================================
-- SAGANA — Unified purchasing m03: delivery groups and the delivery fee
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after m01 and m02.
--
-- WHAT IT DOES
--   * checkout_groups: ONE row per checkout delivery. A cart with several items (from the
--     Marketplace, from Cooperative Products, or both) that is delivered to one address pays
--     ONE delivery fee. Add to Cart and Direct Buy are treated the same: both make a group.
--     The group stores a snapshot: the address (taken from the saved address on the server,
--     never typed text), the straight-line distance, the fee and which fee-band it came from.
--     The fee is kept apart from the product subtotal and never reaches a Farmer's sales.
--   * The fee is collected ONCE, at the first handover in the group (cash on delivery).
--   * compute / preview functions. They refuse unless Delivery is switched on AND ready
--     (m02), the saved address is in Barangay Payanas, and has a map pin.
--     There is no default rate and no silent zero: a distance with no band is refused.
--
-- Pickup never creates a group and is never charged.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.delivery_settings') IS NULL OR to_regclass('public.delivery_fee_bands') IS NULL THEN
    RAISE EXCEPTION 'Run m02 first (delivery settings are missing).';
  END IF;
  IF to_regclass('public.buyer_addresses') IS NULL THEN
    RAISE EXCEPTION 'public.buyer_addresses is missing.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. The group
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.checkout_groups (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id            UUID,
  address_id            UUID,
  recipient_name        TEXT,
  contact_number        TEXT NOT NULL,
  address_line          TEXT NOT NULL,
  barangay_code         TEXT NOT NULL,
  address_label         TEXT,
  delivery_notes        TEXT,
  latitude              DOUBLE PRECISION NOT NULL,
  longitude             DOUBLE PRECISION NOT NULL,
  origin_latitude       DOUBLE PRECISION NOT NULL,
  origin_longitude      DOUBLE PRECISION NOT NULL,
  distance_km           NUMERIC(8,2) NOT NULL CHECK (distance_km >= 0),
  delivery_fee          NUMERIC(10,2) NOT NULL CHECK (delivery_fee >= 0),
  fee_band_version      INTEGER NOT NULL,
  fee_band_min_km       NUMERIC(8,2) NOT NULL,
  fee_band_max_km       NUMERIC(8,2) NOT NULL,
  -- Option A: the cooperative is the origin. Kept as a column so a Farmer-origin option can be added later.
  origin_kind           TEXT NOT NULL DEFAULT 'cooperative' CHECK (origin_kind IN ('cooperative')),
  fee_collected_at      TIMESTAMPTZ,
  fee_collected_source  TEXT CHECK (fee_collected_source IS NULL OR fee_collected_source IN ('marketplace', 'cooperative')),
  fee_collected_order_id UUID,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_checkout_groups_buyer_request
  ON public.checkout_groups (buyer_id, request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS checkout_groups_buyer ON public.checkout_groups (buyer_id, created_at DESC);

-- A snapshot is never rewritten, except for the one-time "fee collected" mark.
CREATE OR REPLACE FUNCTION public._checkout_groups_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'A delivery group is part of the order record and cannot be deleted.';
  END IF;
  IF (to_jsonb(NEW) - 'fee_collected_at' - 'fee_collected_source' - 'fee_collected_order_id')
     IS DISTINCT FROM (to_jsonb(OLD) - 'fee_collected_at' - 'fee_collected_source' - 'fee_collected_order_id') THEN
    RAISE EXCEPTION 'A delivery group snapshot cannot be edited.';
  END IF;
  IF OLD.fee_collected_at IS NOT NULL AND NEW.fee_collected_at IS DISTINCT FROM OLD.fee_collected_at THEN
    RAISE EXCEPTION 'The delivery fee of this group was already collected.';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_checkout_groups_guard ON public.checkout_groups;
CREATE TRIGGER trg_checkout_groups_guard BEFORE UPDATE OR DELETE ON public.checkout_groups
  FOR EACH ROW EXECUTE FUNCTION public._checkout_groups_guard();

ALTER TABLE public.checkout_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "checkout_groups: owner reads" ON public.checkout_groups;
CREATE POLICY "checkout_groups: owner reads" ON public.checkout_groups FOR SELECT TO authenticated USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "checkout_groups: staff read" ON public.checkout_groups;
CREATE POLICY "checkout_groups: staff read" ON public.checkout_groups FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.checkout_groups FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.checkout_groups FROM authenticated;
GRANT SELECT ON public.checkout_groups TO authenticated;

-- The orders table points at its group.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_checkout_group_fk') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_checkout_group_fk
      FOREIGN KEY (checkout_group_id) REFERENCES public.checkout_groups(id) ON DELETE RESTRICT;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS orders_checkout_group ON public.orders (checkout_group_id) WHERE checkout_group_id IS NOT NULL;

-- ════════════════════════════════════════════════════════════
-- 2. Distance and the quote (straight line, rounded to 0.01 km)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._delivery_distance_km(p_lat1 double precision, p_lng1 double precision,
                                                        p_lat2 double precision, p_lng2 double precision)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  SELECT round((2 * 6371.0088 * asin(sqrt(
           power(sin(radians(p_lat2 - p_lat1) / 2), 2) +
           cos(radians(p_lat1)) * cos(radians(p_lat2)) * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
         )))::numeric, 2);
$$;

-- The fee for one delivery point. Refuses (never charges zero by default) when Delivery is off,
-- not ready, outside the allowed barangay, without a pin, or beyond the farthest band.
CREATE OR REPLACE FUNCTION public._delivery_quote(p_barangay_code text, p_lat double precision, p_lng double precision)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  s delivery_settings%ROWTYPE;
  d cooperative_details%ROWTYPE;
  b delivery_fee_bands%ROWTYPE;
  v_dist numeric;
  v_last numeric;
  v_missing text[];
BEGIN
  SELECT * INTO s FROM delivery_settings WHERE id;
  IF NOT s.delivery_enabled THEN
    RAISE EXCEPTION 'DELIVERY_OFF: Delivery is not available right now. Please choose Pickup.';
  END IF;
  v_missing := public._delivery_missing();
  IF COALESCE(array_length(v_missing, 1), 0) > 0 THEN
    RAISE EXCEPTION 'DELIVERY_NOT_READY: Delivery is not available right now. Please choose Pickup.';
  END IF;
  IF p_barangay_code IS NULL OR NOT (p_barangay_code = ANY (s.allowed_barangay_codes)) THEN
    RAISE EXCEPTION 'OUTSIDE_AREA: We deliver only within Barangay Payanas. Please choose Pickup, or use an address in Payanas.';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'NO_PIN: Add the delivery location on the map to this address first.';
  END IF;

  SELECT * INTO d FROM cooperative_details WHERE id;
  v_dist := public._delivery_distance_km(d.latitude, d.longitude, p_lat, p_lng);

  SELECT max(max_km) INTO v_last FROM delivery_fee_bands WHERE is_current;
  IF v_dist > v_last THEN
    RAISE EXCEPTION 'TOO_FAR: This address is too far for delivery. Please choose Pickup.';
  END IF;
  SELECT * INTO b FROM delivery_fee_bands
   WHERE is_current AND v_dist >= min_km AND (v_dist < max_km OR (v_dist = max_km AND max_km = v_last))
   ORDER BY min_km LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_BAND: No delivery fee is set for this distance. Please choose Pickup.';
  END IF;

  RETURN jsonb_build_object(
    'distance_km', v_dist, 'fee', b.fee, 'band_min_km', b.min_km, 'band_max_km', b.max_km,
    'band_version', b.set_version, 'origin_latitude', d.latitude, 'origin_longitude', d.longitude);
END $$;
REVOKE ALL ON FUNCTION public._delivery_quote(text, double precision, double precision) FROM PUBLIC, anon, authenticated;

-- The consumer's own saved address, validated on the server (never the typed text).
CREATE OR REPLACE FUNCTION public._saved_address_for_delivery(p_address_id uuid)
RETURNS buyer_addresses
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE a buyer_addresses%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role IN ('buyer', 'farmer') AND status = 'active') THEN
    RAISE EXCEPTION 'Only an active Buyer or Farmer can order.';
  END IF;
  SELECT * INTO a FROM buyer_addresses WHERE id = p_address_id AND user_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Choose one of your saved addresses.'; END IF;
  RETURN a;
END $$;
REVOKE ALL ON FUNCTION public._saved_address_for_delivery(uuid) FROM PUBLIC, anon, authenticated;

-- What would delivery cost to this saved address? (Shown at checkout; writes nothing.)
CREATE OR REPLACE FUNCTION public.get_delivery_quote(p_address_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE a buyer_addresses%ROWTYPE;
BEGIN
  a := public._saved_address_for_delivery(p_address_id);
  RETURN public._delivery_quote(a.barangay_code, a.latitude, a.longitude);
END $$;
REVOKE ALL ON FUNCTION public.get_delivery_quote(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_delivery_quote(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. Make the group (once per checkout delivery; a retry returns the same group)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_checkout_group(p_address_id uuid, p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  a buyer_addresses%ROWTYPE;
  g checkout_groups%ROWTYPE;
  q jsonb;
BEGIN
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'A request id is required.'; END IF;
  a := public._saved_address_for_delivery(p_address_id);

  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_id::text, 31));
  SELECT * INTO g FROM checkout_groups WHERE buyer_id = auth.uid() AND request_id = p_request_id;
  IF NOT FOUND THEN
    q := public._delivery_quote(a.barangay_code, a.latitude, a.longitude);
    INSERT INTO checkout_groups (
      buyer_id, request_id, address_id, recipient_name, contact_number, address_line, barangay_code,
      address_label, delivery_notes, latitude, longitude, origin_latitude, origin_longitude,
      distance_km, delivery_fee, fee_band_version, fee_band_min_km, fee_band_max_km)
    VALUES (
      auth.uid(), p_request_id, a.id, a.recipient_name, a.contact_number, a.address_line, a.barangay_code,
      a.label, a.notes, a.latitude, a.longitude, (q ->> 'origin_latitude')::double precision, (q ->> 'origin_longitude')::double precision,
      (q ->> 'distance_km')::numeric, (q ->> 'fee')::numeric, (q ->> 'band_version')::integer,
      (q ->> 'band_min_km')::numeric, (q ->> 'band_max_km')::numeric)
    RETURNING * INTO g;
  END IF;
  RETURN jsonb_build_object('group_id', g.id, 'delivery_fee', g.delivery_fee, 'distance_km', g.distance_km);
END $$;
REVOKE ALL ON FUNCTION public.create_checkout_group(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_checkout_group(uuid, uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. Collecting the fee: once per group, at the first handover (used by m04 / m05)
-- ════════════════════════════════════════════════════════════
-- Returns the fee to collect NOW for this handover: the whole fee for the first handover in the
-- group, 0 for every later one. The group row is locked, so two staff recording at the same
-- moment cannot both collect it.
CREATE OR REPLACE FUNCTION public._collect_group_fee(p_group_id uuid, p_order_id uuid, p_source text)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE g checkout_groups%ROWTYPE;
BEGIN
  IF p_group_id IS NULL THEN RETURN 0; END IF;
  SELECT * INTO g FROM checkout_groups WHERE id = p_group_id FOR UPDATE;
  IF NOT FOUND OR g.fee_collected_at IS NOT NULL THEN RETURN 0; END IF;
  UPDATE checkout_groups
     SET fee_collected_at = NOW(), fee_collected_source = p_source, fee_collected_order_id = p_order_id
   WHERE id = g.id;
  RETURN g.delivery_fee;
END $$;
REVOKE ALL ON FUNCTION public._collect_group_fee(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- What the first handover in the group will collect (read-only, for staff screens).
CREATE OR REPLACE FUNCTION public._group_fee_due(p_group_id uuid)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT CASE WHEN fee_collected_at IS NULL THEN delivery_fee ELSE 0 END
    FROM checkout_groups WHERE id = p_group_id;
$$;
REVOKE ALL ON FUNCTION public._group_fee_due(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  No group exists yet and Delivery is still refused:
--     SELECT count(*) FROM checkout_groups;                            -- 0
-- V2  (as a Buyer in the app, after m02) get_delivery_quote(<an address id>) answers
--     'DELIVERY_OFF' until the Manager has switched Delivery on.
-- V3  The distance function (about 1.11 km for 0.01 degrees of latitude):
--     SELECT public._delivery_distance_km(13.3213, 122.0394, 13.3313, 122.0394);
