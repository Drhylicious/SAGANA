-- ============================================================
-- SAGANA — Unified purchasing m07: Pickup switch, cooperative location, delivery guards
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after m01 - m06
-- (and after m02a if you ran the original m02).
--
-- WHAT IT DOES
--   1. PICKUP ON/OFF, separate from Delivery ON/OFF. delivery_settings.pickup_enabled (default ON),
--      changed only by the Manager through set_pickup_enabled(). At least ONE method must stay on:
--      Pickup cannot be switched off unless Delivery is on and ready, and Delivery cannot be
--      switched off while Pickup is off. A trigger enforces it for every path (for example when a
--      new pin or new rates switch Delivery off automatically).
--   2. The switches are ENFORCED in the database, for everyone, whatever the app shows:
--        - a Pickup order is refused while Pickup is OFF,
--        - a Delivery order is refused unless it belongs to a delivery group (that is, unless
--          Delivery is ON, set up and the address was validated). While Delivery is OFF nobody
--          can place a Delivery order any more. Orders already placed are not touched.
--      Applies to Marketplace orders (orders) and Cooperative orders (program_product_purchases).
--   3. COOPERATIVE LOCATION. The map pin is set to Barangay Payanas (13.3213, 122.0392) ONLY if
--      no pin is stored yet. It is data in cooperative_details, not code: the Manager moves it
--      to the exact spot in Cooperative Details at any time.
--   4. NOT A PERSONAL NUMBER. save_cooperative_details() refuses a contact number that is the
--      phone of any Manager or Officer account: the cooperative's number is the cooperative's,
--      never a staff member's personal one.
--   5. get_delivery_status() now also reports pickup_enabled.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.delivery_settings') IS NULL OR to_regprocedure('public._delivery_missing()') IS NULL THEN
    RAISE EXCEPTION 'Run m02 (and m02a) first.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Pickup switch
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.delivery_settings ADD COLUMN IF NOT EXISTS pickup_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Never both off, whatever changed Delivery (a new pin, new rates, the switch itself).
CREATE OR REPLACE FUNCTION public._delivery_settings_one_method()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NOT NEW.pickup_enabled AND NOT NEW.delivery_enabled THEN
    NEW.pickup_enabled := TRUE;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_delivery_settings_one_method ON public.delivery_settings;
CREATE TRIGGER trg_delivery_settings_one_method BEFORE INSERT OR UPDATE ON public.delivery_settings
  FOR EACH ROW EXECUTE FUNCTION public._delivery_settings_one_method();

CREATE OR REPLACE FUNCTION public.set_pickup_enabled(p_enabled boolean)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE s delivery_settings%ROWTYPE;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can switch Pickup on or off.';
  END IF;
  SELECT * INTO s FROM delivery_settings WHERE id FOR UPDATE;
  IF NOT p_enabled AND NOT (s.delivery_enabled AND COALESCE(array_length(public._delivery_missing(), 1), 0) = 0) THEN
    RAISE EXCEPTION 'ONE_METHOD_REQUIRED: Pickup cannot be switched off while Delivery is off. Switch Delivery on first.';
  END IF;
  UPDATE delivery_settings SET pickup_enabled = p_enabled, updated_by = auth.uid(), updated_at = NOW() WHERE id;
END $$;
REVOKE ALL ON FUNCTION public.set_pickup_enabled(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pickup_enabled(boolean) TO authenticated;

-- Delivery off is refused while Pickup is off (the trigger above would otherwise turn Pickup back on).
CREATE OR REPLACE FUNCTION public.set_delivery_enabled(p_enabled boolean)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_missing text[]; s delivery_settings%ROWTYPE;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can switch Delivery on or off.';
  END IF;
  SELECT * INTO s FROM delivery_settings WHERE id FOR UPDATE;
  IF p_enabled THEN
    v_missing := public._delivery_missing();
    IF COALESCE(array_length(v_missing, 1), 0) > 0 THEN
      RAISE EXCEPTION 'DELIVERY_NOT_READY: Delivery cannot be switched on yet. Still missing: %', array_to_string(v_missing, ', ');
    END IF;
  ELSIF NOT s.pickup_enabled THEN
    RAISE EXCEPTION 'ONE_METHOD_REQUIRED: Delivery cannot be switched off while Pickup is off. Switch Pickup on first.';
  END IF;
  UPDATE delivery_settings
     SET delivery_enabled = p_enabled,
         enabled_at = CASE WHEN p_enabled THEN NOW() ELSE enabled_at END,
         enabled_by = CASE WHEN p_enabled THEN auth.uid() ELSE enabled_by END,
         updated_by = auth.uid(), updated_at = NOW()
   WHERE id;
END $$;
REVOKE ALL ON FUNCTION public.set_delivery_enabled(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_delivery_enabled(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_delivery_status()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  s delivery_settings%ROWTYPE;
  v_missing text[];
BEGIN
  SELECT * INTO s FROM delivery_settings WHERE id;
  v_missing := public._delivery_missing();
  RETURN jsonb_build_object(
    'enabled', s.delivery_enabled AND COALESCE(array_length(v_missing, 1), 0) = 0,
    'ready',   COALESCE(array_length(v_missing, 1), 0) = 0,
    'pickup_enabled', s.pickup_enabled,
    'allowed_barangay_codes', to_jsonb(s.allowed_barangay_codes),
    'missing', CASE WHEN public.is_staff() THEN to_jsonb(v_missing) ELSE '[]'::jsonb END
  );
END $$;
GRANT EXECUTE ON FUNCTION public.get_delivery_status() TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. The switches hold for every order, whatever the app shows
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._order_method_allowed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s delivery_settings%ROWTYPE; v_method text := COALESCE(NEW.fulfillment_method, 'pickup');
BEGIN
  SELECT * INTO s FROM delivery_settings WHERE id;
  IF v_method = 'pickup' AND NOT COALESCE(s.pickup_enabled, TRUE) THEN
    RAISE EXCEPTION 'PICKUP_OFF: Pickup is not available right now.';
  END IF;
  -- A Delivery order always belongs to a delivery group: it exists only while Delivery is on,
  -- set up and the saved address was checked (Payanas, with a pin, a fee from the bands).
  IF v_method = 'delivery' AND NEW.checkout_group_id IS NULL THEN
    RAISE EXCEPTION 'DELIVERY_OFF: Delivery is not available right now. Please choose Pickup.';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_orders_method_allowed ON public.orders;
CREATE TRIGGER trg_orders_method_allowed BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._order_method_allowed();
DROP TRIGGER IF EXISTS trg_program_orders_method_allowed ON public.program_product_purchases;
CREATE TRIGGER trg_program_orders_method_allowed BEFORE INSERT ON public.program_product_purchases
  FOR EACH ROW EXECUTE FUNCTION public._order_method_allowed();

-- ════════════════════════════════════════════════════════════
-- 3. The cooperative's location: Barangay Payanas, only when none is stored yet
-- ════════════════════════════════════════════════════════════
UPDATE public.cooperative_details SET latitude = 13.3213, longitude = 122.0392
 WHERE latitude IS NULL AND longitude IS NULL;

-- ════════════════════════════════════════════════════════════
-- 4. The cooperative's number is never a staff member's personal number
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.save_cooperative_details(
  p_sitio_purok    TEXT,
  p_address_notes  TEXT,
  p_latitude       DOUBLE PRECISION,
  p_longitude      DOUBLE PRECISION,
  p_contact_number TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  d cooperative_details%ROWTYPE;
  v_digits TEXT;
  v_contact TEXT := NULLIF(btrim(COALESCE(p_contact_number, '')), '');
  v_pin_changed BOOLEAN;
  v_contact_changed BOOLEAN;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can change the Cooperative Details.';
  END IF;
  IF (p_latitude IS NULL) <> (p_longitude IS NULL) THEN
    RAISE EXCEPTION 'The map pin needs both a latitude and a longitude.';
  END IF;
  IF v_contact IS NOT NULL THEN
    v_digits := regexp_replace(v_contact, '[^0-9]', '', 'g');
    IF length(v_digits) < 7 OR length(v_digits) > 13 THEN
      RAISE EXCEPTION 'Enter a valid contact number.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM user_information ui JOIN user_roles ur ON ur.user_id = ui.user_id
       WHERE ur.role IN ('admin', 'officer')
         AND ui.phone_number IS NOT NULL
         AND length(regexp_replace(ui.phone_number, '[^0-9]', '', 'g')) >= 7
         AND right(regexp_replace(ui.phone_number, '[^0-9]', '', 'g'), 10) = right(v_digits, 10)
    ) THEN
      RAISE EXCEPTION 'PERSONAL_NUMBER: This is the phone number of a Manager or Officer account. Enter the cooperative''s own number.';
    END IF;
  END IF;

  SELECT * INTO d FROM cooperative_details WHERE id FOR UPDATE;
  v_pin_changed := (d.latitude, d.longitude) IS DISTINCT FROM (p_latitude, p_longitude);
  v_contact_changed := d.contact_number IS DISTINCT FROM v_contact;

  UPDATE cooperative_details
     SET sitio_purok = NULLIF(btrim(COALESCE(p_sitio_purok, '')), ''),
         address_notes = NULLIF(btrim(COALESCE(p_address_notes, '')), ''),
         latitude = p_latitude, longitude = p_longitude,
         contact_number = v_contact,
         contact_is_placeholder = (v_contact IS NULL),
         contact_verified_at = CASE WHEN v_contact_changed THEN NULL ELSE contact_verified_at END,
         contact_verified_by = CASE WHEN v_contact_changed THEN NULL ELSE contact_verified_by END,
         updated_by = auth.uid()
   WHERE id;

  IF v_pin_changed OR v_contact_changed THEN
    UPDATE delivery_settings SET delivery_enabled = FALSE, updated_by = auth.uid(), updated_at = NOW()
     WHERE id AND delivery_enabled;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.save_cooperative_details(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_cooperative_details(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Officer permission registry (the Manager-only function checks the role itself)
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc', 'set_pickup_enabled', 'marketplace')
ON CONFLICT (kind, name) DO UPDATE SET module = EXCLUDED.module;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  Pickup is on, Delivery is off, never both off:
--     SELECT pickup_enabled, delivery_enabled FROM delivery_settings;           -- true, false
-- V2  The cooperative has a location (Barangay Payanas until the Manager moves it):
--     SELECT latitude, longitude FROM cooperative_details;                       -- 13.3213, 122.0392
-- V3  The order triggers exist (expect 2 rows):
--     SELECT tgname FROM pg_trigger WHERE tgname IN ('trg_orders_method_allowed','trg_program_orders_method_allowed');
-- V4  Status now carries the Pickup switch:
--     SELECT public.get_delivery_status();                                       -- includes "pickup_enabled": true
-- V5  With Delivery OFF, a Delivery order is refused (try from the app as a Buyer: only Pickup is offered).
