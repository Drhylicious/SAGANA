-- ============================================================
-- SAGANA — Offer to Cooperative: price negotiation
--
-- A Farmer offers a harvested batch to the Cooperative at an ASKING PRICE PER
-- KG. The Cooperative (a Manager or Officer) and the Farmer then take turns:
-- each side may ACCEPT the other's latest price or send a COUNTEROFFER. The
-- sale is final only when the side that RECEIVED the latest price accepts it.
-- Either side can also leave: the Cooperative can DECLINE, the Farmer can
-- CANCEL. Every step is kept in a history table.
--
-- STATUS (cooperative_purchase_offers.status)
--     pending    the negotiation is open (it is whose turn is in last_proposed_by)
--     confirmed  agreed and settled (shown as "Accepted")
--     declined   the Cooperative ended it
--     cancelled  the Farmer ended it                       (new value)
--   Who has to answer next, while pending:
--     last_proposed_by = 'farmer'       -> the Cooperative's turn
--     last_proposed_by = 'cooperative'  -> the Farmer's turn
--
-- WHAT CHANGES
--   * cooperative_purchase_offers: asking_price_per_kg, current_price_per_kg,
--     agreed_price_per_kg, last_proposed_by, negotiation_round (+ 'cancelled').
--   * NEW table cooperative_offer_events: the negotiation history (who, what
--     price, when, optional note). Written only by the functions below.
--   * offer_batch_to_cooperative(): now takes the asking price, and checks that
--     the batch belongs to the caller (it did not before).
--   * NEW counter_cooperative_offer(), accept_cooperative_offer(),
--     cancel_cooperative_offer(); decline_cooperative_offer() gains an optional
--     round check.
--   * confirm_cooperative_offer() is REMOVED: a Manager could settle at any
--     amount without the Farmer's agreement. Acceptance replaces it, and it
--     settles exactly as confirm_cooperative_offer() did.
--   * RLS: a Farmer can no longer INSERT offer rows directly (they could set any
--     status or amount); staff can no longer write offer rows directly. Reads
--     are unchanged. See section 6; skip it only if you want to keep that
--     behaviour.
--
-- WHAT DOES NOT CHANGE (deliberately)
--   * Quantity is fixed at the offered quantity. Only the price is negotiated.
--   * Stock is reserved when the offer is made (_apply_batch_reservation), is
--     released only when the offer is declined or cancelled
--     (_release_batch_reservation), and is NOT touched on acceptance. This is
--     the existing behaviour; acceptance does not add to inventory_batches.sold_kg
--     (a known gap recorded in the Admin Marketplace document).
--   * The settlement is one member_sales_transactions row, so it appears in
--     Farmer > Transaction History, the Manager's Sales Report and the
--     Balik-Tangkilik totals, exactly as a confirmed offer did.
--   * Ginger (DA-AMAD Market Linking only) is still refused by the existing
--     trg_channel_offer trigger on INSERT. Offers already open when this script
--     runs keep going: they have no price yet, so the Cooperative proposes one
--     (counteroffer) or declines.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end. Every statement is safe to re-run.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run these first and keep the results) ────────
-- A. Columns and status rule of the offers table (expect no price columns yet):
--    SELECT column_name, data_type, is_nullable FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='cooperative_purchase_offers' ORDER BY ordinal_position;
--    SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conrelid='public.cooperative_purchase_offers'::regclass;
-- B. Policies and triggers on the offers table:
--    SELECT policyname, cmd, permissive, qual, with_check FROM pg_policies
--    WHERE tablename='cooperative_purchase_offers';
--    SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--    WHERE tgrelid='public.cooperative_purchase_offers'::regclass AND NOT tgisinternal;
-- C. The live bodies of the functions this script replaces or relies on:
--    SELECT proname, pg_get_function_identity_arguments(oid) AS args FROM pg_proc
--    WHERE pronamespace='public'::regnamespace AND proname IN
--      ('offer_batch_to_cooperative','confirm_cooperative_offer','decline_cooperative_offer',
--       '_apply_batch_reservation','_release_batch_reservation','is_staff') ORDER BY 1,2;
-- D. Triggers on the settlement table (an unexpected one could react to the new rows):
--    SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--    WHERE tgrelid='public.member_sales_transactions'::regclass AND NOT tgisinternal;
-- E. Offers open right now (these continue, with no price yet):
--    SELECT status, count(*) FROM public.cooperative_purchase_offers GROUP BY 1;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

-- ═══ 0. Things this script relies on ════════════════════════════════════
DO $$
BEGIN
  IF to_regclass('public.cooperative_purchase_offers') IS NULL THEN
    RAISE EXCEPTION 'cooperative_purchase_offers is missing.';
  END IF;
  IF to_regclass('public.member_sales_transactions') IS NULL THEN
    RAISE EXCEPTION 'member_sales_transactions is missing.';
  END IF;
  IF to_regprocedure('public._apply_batch_reservation(uuid, numeric)') IS NULL
     OR to_regprocedure('public._release_batch_reservation(uuid, numeric)') IS NULL THEN
    RAISE EXCEPTION 'The batch reservation helpers are missing (_apply_batch_reservation / _release_batch_reservation).';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing. Run supabase_schema_role_based_staff_access.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Offer columns and the new status ════════════════════════════════
ALTER TABLE public.cooperative_purchase_offers
  ADD COLUMN IF NOT EXISTS asking_price_per_kg  NUMERIC(10,2) CHECK (asking_price_per_kg  > 0),
  ADD COLUMN IF NOT EXISTS current_price_per_kg NUMERIC(10,2) CHECK (current_price_per_kg > 0),
  ADD COLUMN IF NOT EXISTS agreed_price_per_kg  NUMERIC(10,2) CHECK (agreed_price_per_kg  > 0),
  ADD COLUMN IF NOT EXISTS last_proposed_by     TEXT    NOT NULL DEFAULT 'farmer'
                                               CHECK (last_proposed_by IN ('farmer', 'cooperative')),
  ADD COLUMN IF NOT EXISTS negotiation_round    INTEGER NOT NULL DEFAULT 1
                                               CHECK (negotiation_round >= 1);

-- Allow 'cancelled'. The original CHECK has a generated name, so find it by its
-- definition rather than by name.
DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.cooperative_purchase_offers'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
      AND pg_get_constraintdef(oid) ILIKE '%pending%'
  LOOP
    EXECUTE format('ALTER TABLE public.cooperative_purchase_offers DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.cooperative_purchase_offers
  ADD CONSTRAINT cooperative_purchase_offers_status_check
  CHECK (status IN ('pending', 'confirmed', 'declined', 'cancelled'));

-- One settlement row per offer, ever. Belt and braces behind the status guard.
CREATE UNIQUE INDEX IF NOT EXISTS uq_coop_offers_sales_transaction
  ON public.cooperative_purchase_offers (member_sales_transaction_id)
  WHERE member_sales_transaction_id IS NOT NULL;

-- Offers settled before this script: record the per-kg price they implied.
UPDATE public.cooperative_purchase_offers
SET agreed_price_per_kg = round(confirmed_amount / confirmed_quantity_kg, 2)
WHERE status = 'confirmed'
  AND agreed_price_per_kg IS NULL
  AND confirmed_quantity_kg > 0
  AND confirmed_amount > 0;

-- ═══ 2. Negotiation history ═════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cooperative_offer_events (
  id           UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  offer_id     UUID          NOT NULL REFERENCES public.cooperative_purchase_offers(id) ON DELETE CASCADE,
  round        INTEGER       NOT NULL CHECK (round >= 1),
  action       TEXT          NOT NULL CHECK (action IN ('offered', 'countered', 'accepted', 'declined', 'cancelled')),
  actor_role   TEXT          NOT NULL CHECK (actor_role IN ('farmer', 'cooperative')),
  actor_id     UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  price_per_kg NUMERIC(10,2) CHECK (price_per_kg > 0),
  quantity_kg  NUMERIC(10,2),
  note         TEXT,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coop_offer_events_offer
  ON public.cooperative_offer_events (offer_id, created_at);

ALTER TABLE public.cooperative_offer_events ENABLE ROW LEVEL SECURITY;

-- Read only. There is deliberately no INSERT / UPDATE / DELETE policy: history
-- is written by the SECURITY DEFINER functions below and nowhere else.
DROP POLICY IF EXISTS "coop_offer_events: farmer reads own" ON public.cooperative_offer_events;
CREATE POLICY "coop_offer_events: farmer reads own"
  ON public.cooperative_offer_events FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.cooperative_purchase_offers o
    WHERE o.id = cooperative_offer_events.offer_id AND o.farmer_id = auth.uid()
  ));

DROP POLICY IF EXISTS "coop_offer_events: staff reads all" ON public.cooperative_offer_events;
CREATE POLICY "coop_offer_events: staff reads all"
  ON public.cooperative_offer_events FOR SELECT
  USING (public.is_staff());

GRANT SELECT ON public.cooperative_offer_events TO authenticated;

-- History for offers that existed before this script: when they were offered,
-- and how the ones already closed were closed. Run once (NOT EXISTS makes a
-- second run add nothing).
INSERT INTO public.cooperative_offer_events
  (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, created_at)
SELECT o.id, 1, 'offered', 'farmer', o.farmer_id, o.asking_price_per_kg, o.offered_quantity_kg, o.offered_at
FROM public.cooperative_purchase_offers o
WHERE NOT EXISTS (SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id = o.id);

INSERT INTO public.cooperative_offer_events
  (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note, created_at)
SELECT o.id, 1,
       CASE o.status WHEN 'confirmed' THEN 'accepted' ELSE 'declined' END,
       'cooperative', o.confirmed_by,
       CASE WHEN o.status = 'confirmed' THEN o.agreed_price_per_kg END,
       o.confirmed_quantity_kg, o.admin_notes, o.confirmed_at
FROM public.cooperative_purchase_offers o
WHERE o.status IN ('confirmed', 'declined')
  AND o.confirmed_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.cooperative_offer_events e
    WHERE e.offer_id = o.id AND e.action IN ('accepted', 'declined')
  );

-- ═══ 3. Internal helpers ════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._coop_offer_peso(p_amount NUMERIC)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT '₱' || to_char(p_amount, 'FM999999990.00');
$$;

-- One notice per Manager / Officer.
CREATE OR REPLACE FUNCTION public._coop_offer_notify_staff(p_title TEXT, p_body TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ap.user_id, 'cooperative_offer', p_title, p_body, FALSE, NOW(),
         '/admin/marketplace/offer-to-cooperative'
  FROM user_roles ap WHERE ap.role IN ('admin', 'officer');
$$;

CREATE OR REPLACE FUNCTION public._coop_offer_notify_farmer(p_farmer_id UUID, p_title TEXT, p_body TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (p_farmer_id, 'cooperative_offer', p_title, p_body, FALSE, NOW(),
          '/farmer/profile/cooperative-offers');
$$;

REVOKE ALL ON FUNCTION public._coop_offer_notify_staff(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._coop_offer_notify_farmer(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ═══ 4. The negotiation functions ═══════════════════════════════════════

-- Retire the three functions whose shape changes, so no old call path remains.
DROP FUNCTION IF EXISTS public.offer_batch_to_cooperative(uuid, text, numeric);
DROP FUNCTION IF EXISTS public.confirm_cooperative_offer(uuid, numeric, numeric, text);
DROP FUNCTION IF EXISTS public.decline_cooperative_offer(uuid, text);

-- 4a. Farmer submits an offer ---------------------------------------------
CREATE OR REPLACE FUNCTION public.offer_batch_to_cooperative(
  p_batch_id             UUID,
  p_quantity_kg          NUMERIC,
  p_asking_price_per_kg  NUMERIC,
  p_note                 TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch    RECORD;
  v_offer_id UUID;
  v_name     TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'farmer') THEN
    RAISE EXCEPTION 'Only farmer members can offer a harvest to the cooperative.';
  END IF;
  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_asking_price_per_kg IS NULL OR p_asking_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter your asking price per kg.';
  END IF;
  IF p_asking_price_per_kg > 100000 THEN
    RAISE EXCEPTION 'That asking price is too high. Please check it.';
  END IF;

  -- The batch must be the caller's own. (The previous version did not check.)
  SELECT farmer_id, crop_name, is_coop_eligible INTO v_batch
  FROM inventory_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;
  IF NOT COALESCE(v_batch.is_coop_eligible, FALSE) THEN
    RAISE EXCEPTION 'This crop is not eligible for cooperative purchase.';
  END IF;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  -- trg_channel_offer (Ginger is DA-AMAD only) and trg_coop_offers_crop_type
  -- still run on this INSERT.
  INSERT INTO cooperative_purchase_offers (
    farmer_id, inventory_batch_id, crop_name, offered_quantity_kg,
    asking_price_per_kg, current_price_per_kg, last_proposed_by, negotiation_round
  ) VALUES (
    auth.uid(), p_batch_id, v_batch.crop_name, p_quantity_kg,
    p_asking_price_per_kg, p_asking_price_per_kg, 'farmer', 1
  ) RETURNING id INTO v_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (v_offer_id, 1, 'offered', 'farmer', auth.uid(), p_asking_price_per_kg, p_quantity_kg, NULLIF(btrim(p_note), ''));

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  PERFORM public._coop_offer_notify_staff(
    'New Cooperative Offer',
    COALESCE(v_name, 'A farmer') || ' offered ' || p_quantity_kg || ' kg ' || v_batch.crop_name ||
      ' at ' || public._coop_offer_peso(p_asking_price_per_kg) || '/kg and needs a response.'
  );

  RETURN v_offer_id;
END;
$$;

-- 4b. Either side sends a counteroffer ------------------------------------
CREATE OR REPLACE FUNCTION public.counter_cooperative_offer(
  p_offer_id        UUID,
  p_price_per_kg    NUMERIC,
  p_expected_round  INTEGER,
  p_note            TEXT DEFAULT NULL
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer  RECORD;
  v_side   TEXT;
  v_round  INTEGER;
  v_name   TEXT;
BEGIN
  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;

  v_side := CASE
    WHEN auth.uid() = v_offer.farmer_id THEN 'farmer'
    WHEN public.is_staff() THEN 'cooperative'
  END;
  IF v_side IS NULL THEN
    RAISE EXCEPTION 'You are not allowed to respond to this offer.';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'This negotiation is already closed.';
  END IF;
  IF p_expected_round IS DISTINCT FROM v_offer.negotiation_round THEN
    RAISE EXCEPTION 'This offer was updated. Please refresh and review the latest price.';
  END IF;
  IF v_side = v_offer.last_proposed_by THEN
    RAISE EXCEPTION 'You already proposed the latest price. Wait for the other side to respond.';
  END IF;
  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a price per kg greater than zero.';
  END IF;
  IF p_price_per_kg > 100000 THEN
    RAISE EXCEPTION 'That price is too high. Please check it.';
  END IF;
  IF v_offer.current_price_per_kg IS NOT NULL AND p_price_per_kg = v_offer.current_price_per_kg THEN
    RAISE EXCEPTION 'That is already the current price. Accept it, or propose a different price.';
  END IF;

  v_round := v_offer.negotiation_round + 1;

  UPDATE cooperative_purchase_offers
  SET current_price_per_kg = p_price_per_kg,
      last_proposed_by     = v_side,
      negotiation_round    = v_round
  WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_round, 'countered', v_side, auth.uid(), p_price_per_kg,
     v_offer.offered_quantity_kg, NULLIF(btrim(p_note), ''));

  IF v_side = 'cooperative' THEN
    PERFORM public._coop_offer_notify_farmer(
      v_offer.farmer_id,
      'Cooperative Counteroffer',
      'SP3 proposed ' || public._coop_offer_peso(p_price_per_kg) || '/kg for your ' ||
        v_offer.crop_name || '. Open it to accept or reply.'
    );
  ELSE
    SELECT full_name INTO v_name FROM user_information WHERE user_id = v_offer.farmer_id;
    PERFORM public._coop_offer_notify_staff(
      'Farmer Counteroffer',
      COALESCE(v_name, 'A farmer') || ' proposed ' || public._coop_offer_peso(p_price_per_kg) ||
        '/kg for ' || v_offer.crop_name || '.'
    );
  END IF;

  RETURN v_round;
END;
$$;

-- 4c. The receiving side accepts the latest price: the sale is final -------
CREATE OR REPLACE FUNCTION public.accept_cooperative_offer(
  p_offer_id        UUID,
  p_expected_round  INTEGER,
  p_note            TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer   RECORD;
  v_side    TEXT;
  v_qty     NUMERIC;
  v_amount  NUMERIC;
  v_staff   UUID;
  v_tx_id   UUID;
  v_name    TEXT;
BEGIN
  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;

  v_side := CASE
    WHEN auth.uid() = v_offer.farmer_id THEN 'farmer'
    WHEN public.is_staff() THEN 'cooperative'
  END;
  IF v_side IS NULL THEN
    RAISE EXCEPTION 'You are not allowed to respond to this offer.';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'This negotiation is already closed.';
  END IF;
  -- Stale-price guard: the price on the caller's screen must still be the
  -- latest one. Without it a price changed a moment ago could be accepted.
  IF p_expected_round IS DISTINCT FROM v_offer.negotiation_round THEN
    RAISE EXCEPTION 'This offer was updated. Please refresh and review the latest price.';
  END IF;
  -- Only the side that RECEIVED the latest price can accept it.
  IF v_side = v_offer.last_proposed_by THEN
    RAISE EXCEPTION 'You proposed the latest price. The other side has to accept it.';
  END IF;
  IF v_offer.current_price_per_kg IS NULL THEN
    RAISE EXCEPTION 'No price has been proposed yet. Propose a price first.';
  END IF;

  v_qty    := v_offer.offered_quantity_kg;
  v_amount := round(v_offer.current_price_per_kg * v_qty, 2);

  -- The Manager / Officer behind the deal: the one accepting now, or the one
  -- whose price the Farmer is accepting.
  IF v_side = 'cooperative' THEN
    v_staff := auth.uid();
  ELSE
    SELECT actor_id INTO v_staff
    FROM cooperative_offer_events
    WHERE offer_id = p_offer_id AND actor_role = 'cooperative' AND actor_id IS NOT NULL
    ORDER BY created_at DESC, id DESC
    LIMIT 1;
  END IF;

  -- Settle exactly as confirm_cooperative_offer() did.
  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, lower(v_offer.crop_name),
    v_qty, v_amount, CURRENT_DATE, COALESCE(v_staff, auth.uid())
  ) RETURNING id INTO v_tx_id;

  UPDATE cooperative_purchase_offers
  SET status                      = 'confirmed',
      confirmed_quantity_kg       = v_qty,
      confirmed_amount            = v_amount,
      agreed_price_per_kg         = v_offer.current_price_per_kg,
      member_sales_transaction_id = v_tx_id,
      confirmed_by                = v_staff,
      confirmed_at                = NOW()
  WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'accepted', v_side, auth.uid(),
     v_offer.current_price_per_kg, v_qty, NULLIF(btrim(p_note), ''));

  IF v_side = 'cooperative' THEN
    PERFORM public._coop_offer_notify_farmer(
      v_offer.farmer_id,
      'Cooperative Accepted Your Offer',
      'SP3 accepted your ' || v_qty || ' kg ' || v_offer.crop_name || ' at ' ||
        public._coop_offer_peso(v_offer.current_price_per_kg) || '/kg (total ' ||
        public._coop_offer_peso(v_amount) || ').'
    );
  ELSE
    SELECT full_name INTO v_name FROM user_information WHERE user_id = v_offer.farmer_id;
    PERFORM public._coop_offer_notify_staff(
      'Farmer Accepted the Price',
      COALESCE(v_name, 'A farmer') || ' accepted ' || public._coop_offer_peso(v_offer.current_price_per_kg) ||
        '/kg for ' || v_qty || ' kg ' || v_offer.crop_name || ' (total ' ||
        public._coop_offer_peso(v_amount) || ').'
    );
  END IF;

  RETURN v_tx_id;
END;
$$;

-- 4d. The Cooperative ends the negotiation ---------------------------------
CREATE OR REPLACE FUNCTION public.decline_cooperative_offer(
  p_offer_id        UUID,
  p_admin_notes     TEXT DEFAULT NULL,
  p_expected_round  INTEGER DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only the cooperative can decline an offer.';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'This negotiation is already closed.';
  END IF;
  IF p_expected_round IS NOT NULL AND p_expected_round <> v_offer.negotiation_round THEN
    RAISE EXCEPTION 'This offer was updated. Please refresh and review the latest price.';
  END IF;

  PERFORM public._release_batch_reservation(v_offer.inventory_batch_id, v_offer.offered_quantity_kg);

  UPDATE cooperative_purchase_offers
  SET status = 'declined', admin_notes = NULLIF(btrim(p_admin_notes), ''),
      confirmed_by = auth.uid(), confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'declined', 'cooperative', auth.uid(),
     v_offer.current_price_per_kg, v_offer.offered_quantity_kg, NULLIF(btrim(p_admin_notes), ''));

  PERFORM public._coop_offer_notify_farmer(
    v_offer.farmer_id,
    'Cooperative Offer Declined',
    'SP3 declined your ' || v_offer.offered_quantity_kg || ' kg ' || v_offer.crop_name ||
      ' offer. The kg were returned to your inventory.' ||
      CASE WHEN NULLIF(btrim(p_admin_notes), '') IS NOT NULL THEN ' Reason: ' || btrim(p_admin_notes) ELSE '' END
  );
END;
$$;

-- 4e. The Farmer ends the negotiation --------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_cooperative_offer(
  p_offer_id  UUID,
  p_note      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_name  TEXT;
BEGIN
  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND OR v_offer.farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'This negotiation is already closed.';
  END IF;

  PERFORM public._release_batch_reservation(v_offer.inventory_batch_id, v_offer.offered_quantity_kg);

  UPDATE cooperative_purchase_offers
  SET status = 'cancelled', confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'cancelled', 'farmer', auth.uid(),
     v_offer.current_price_per_kg, v_offer.offered_quantity_kg, NULLIF(btrim(p_note), ''));

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_offer.farmer_id;
  PERFORM public._coop_offer_notify_staff(
    'Cooperative Offer Cancelled',
    COALESCE(v_name, 'A farmer') || ' cancelled the ' || v_offer.offered_quantity_kg || ' kg ' ||
      v_offer.crop_name || ' offer.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.offer_batch_to_cooperative(UUID, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.counter_cooperative_offer(UUID, NUMERIC, INTEGER, TEXT)  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_cooperative_offer(UUID, INTEGER, TEXT)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decline_cooperative_offer(UUID, TEXT, INTEGER)           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_cooperative_offer(UUID, TEXT)                     FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.offer_batch_to_cooperative(UUID, NUMERIC, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.counter_cooperative_offer(UUID, NUMERIC, INTEGER, TEXT)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_cooperative_offer(UUID, INTEGER, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_cooperative_offer(UUID, TEXT, INTEGER)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_cooperative_offer(UUID, TEXT)                     TO authenticated;

-- ═══ 5. Wording: the Manager wording trigger already rewrites "admin" in the
-- notices above, and none of them use it. Nothing to add here. ══════════

-- ═══ 6. Close the direct-write paths on the offers table ═══════════════
-- Offers are created and changed ONLY through the functions above. Before this,
-- a Farmer could INSERT an offer row straight from the client with any status
-- or amount, and any staff account could UPDATE one directly.
DROP POLICY IF EXISTS "coop_offers: farmer inserts own" ON public.cooperative_purchase_offers;
DROP POLICY IF EXISTS "coop_offers: admin manages all"  ON public.cooperative_purchase_offers;

DROP POLICY IF EXISTS "coop_offers: staff reads all" ON public.cooperative_purchase_offers;
CREATE POLICY "coop_offers: staff reads all"
  ON public.cooperative_purchase_offers FOR SELECT
  USING (public.is_staff());
-- ("coop_offers: farmer creates and reads own" is a SELECT policy and stays.)

COMMIT;

-- ─── VERIFICATION (read-only unless a step says otherwise) ──────────────
-- 1. Objects exist (expect: 5 functions, the events table, 4 new columns + round):
--    SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc
--    WHERE pronamespace='public'::regnamespace AND proname IN
--      ('offer_batch_to_cooperative','counter_cooperative_offer','accept_cooperative_offer',
--       'decline_cooperative_offer','cancel_cooperative_offer') ORDER BY 1;
--    SELECT to_regclass('public.cooperative_offer_events');
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='cooperative_purchase_offers'
--      AND column_name IN ('asking_price_per_kg','current_price_per_kg','agreed_price_per_kg','last_proposed_by','negotiation_round');
-- 2. The old settle-at-any-amount function is gone (expect 0 rows):
--    SELECT 1 FROM pg_proc WHERE proname='confirm_cooperative_offer' AND pronamespace='public'::regnamespace;
-- 3. Policies on the offers table (expect SELECT policies only):
--    SELECT policyname, cmd FROM pg_policies WHERE tablename='cooperative_purchase_offers' ORDER BY 1;
-- 4. Every earlier offer has a history row (expect 0):
--    SELECT count(*) FROM public.cooperative_purchase_offers o
--    WHERE NOT EXISTS (SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id = o.id);
-- 5. No offer was settled twice (expect 0 rows):
--    SELECT member_sales_transaction_id, count(*) FROM public.cooperative_purchase_offers
--    WHERE member_sales_transaction_id IS NOT NULL GROUP BY 1 HAVING count(*) > 1;
-- 6. Each confirmed offer's amount equals its agreed price x quantity (expect 0 rows;
--    older offers have no agreed price and are skipped):
--    SELECT id FROM public.cooperative_purchase_offers
--    WHERE status='confirmed' AND agreed_price_per_kg IS NOT NULL
--      AND round(agreed_price_per_kg * confirmed_quantity_kg, 2) <> confirmed_amount;
-- 7. Settlement ties out. A pending, declined or cancelled offer must have no settlement
--    (expect 0 rows). A confirmed offer must have exactly one; offers confirmed before
--    the all-crops settlement change (supabase_schema_offer_to_cooperative_any_crop_transactions.sql)
--    may legitimately have none, so judge only rows confirmed after this script:
--    SELECT id FROM public.cooperative_purchase_offers
--    WHERE (status <> 'confirmed' AND member_sales_transaction_id IS NOT NULL)
--       OR (status = 'confirmed'  AND member_sales_transaction_id IS NULL);
-- ─────────────────────────────────────────────────────────────────────────
