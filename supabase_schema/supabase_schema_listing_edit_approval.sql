-- ============================================================
-- SAGANA — Listing edit requests (approved listings) + staff accountability history
--
-- PART 1  A Farmer's change to an APPROVED listing needs Manager / Officer approval
-- PART 2  workflow_events: who did what, when — for listings, orders, Market
--         Linking (DA-AMAD) and its enrollments (Offer to Cooperative already has
--         cooperative_offer_events, which is reused as it is)
--
-- PART 1 — HOW IT WORKS
--   * A Pending Approval listing is still edited directly (update_my_listing): the
--     Manager has not approved anything yet, so there is nothing to protect. It now
--     refuses an APPROVED listing and points to the request below.
--   * request_listing_edit(): the Farmer proposes quantity / asking price /
--     description / photo for an Available (approved, quantity left) listing. A row
--     is stored in listing_edit_requests with BOTH the original and the proposed
--     values. The listing itself is NOT touched: it stays published exactly as it
--     is, no stock moves, orders and carts see nothing. One open request per
--     listing.
--   * approve_listing_edit() (Manager / Officer): re-checks everything against the
--     listing AS IT IS NOW (orders may have come in), then applies the change with
--     the same reservation arithmetic as before (the extra is reserved from the
--     batch, a reduction is released), and moves remaining_kg by the same amount.
--     Existing orders keep their own quantity and price.
--   * reject_listing_edit(): a reason is REQUIRED. Only the request is rejected; the
--     published listing is untouched. The Farmer is notified with the reason.
--   * cancel_listing_edit_request(): the Farmer withdraws their own open request.
--   * If the listing stops being Approved (sold, withdrawn ...) while a request is
--     open, the request is cancelled automatically.
--   Crop, unit, batch and status can never be changed by an edit.
--
-- PART 2 — WHO DID WHAT
--   workflow_events is append-only and is written only by triggers and by the
--   functions in this file (clients cannot insert). Triggers on marketplace_listings,
--   orders, market_linking_programs, market_linking_sales and da_amad_enrollments
--   record every status change with auth.uid() as the actor, the actor's role, the
--   from/to status and, where there is one, the reason. No existing function body
--   is replaced for this. Each actor is its own row, so two staff members handling
--   one order or one request appear separately.
--   * Manager / Officer read the table directly (RLS: is_staff()).
--   * Farmers and Buyers have NO table access. A Farmer reads their own listing's
--     history through get_my_listing_history(), which returns "You" / "Cooperative"
--     instead of any staff identity, and their edit requests through
--     get_my_listing_edit_requests(), which leaves out the reviewer.
--   History starts when this script is applied; earlier staff actions were never
--   recorded, so a few opening rows ("submitted" / "placed") are backfilled and
--   nothing is guessed about who approved what before.
--
-- Run after: supabase_schema_farmer_listing_edit.sql and the files it names.
-- Safe to re-run. Not applied automatically.
-- Then run supabase_schema_listing_edit_approval_test.sql.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._apply_batch_reservation(uuid,numeric)') IS NULL
     OR to_regprocedure('public._release_batch_reservation(uuid,numeric)') IS NULL THEN
    RAISE EXCEPTION 'The batch reservation helpers are missing. Run the earlier marketplace scripts first.';
  END IF;
  IF to_regprocedure('public.notify_staff(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'notify_staff() is missing. Run supabase_schema_phase2_notification_completeness.sql first.';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing. Run supabase_schema_role_based_staff_access.sql first.';
  END IF;
  IF to_regprocedure('public.update_my_listing(uuid,numeric,numeric,text,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_farmer_listing_edit.sql first (update_my_listing is missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'marketplace_listings' AND column_name = 'unit') THEN
    RAISE EXCEPTION 'Run supabase_schema_harvest_batch_number_and_units.sql first (marketplace_listings.unit is missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'market_linking_programs' AND column_name = 'unit')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'market_linking_sales' AND column_name = 'unit') THEN
    RAISE EXCEPTION 'Run supabase_schema_ginger_any_unit.sql first (the Market Linking unit columns are missing).';
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 2 (first, because Part 1 writes to it): the history table
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.workflow_events (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT        NOT NULL
              CHECK (entity_type IN ('listing', 'order', 'market_linking', 'market_linking_enrollment')),
  entity_id   UUID        NOT NULL,
  action      TEXT        NOT NULL,
  from_status TEXT,
  to_status   TEXT,
  actor_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  -- admin | officer | farmer | buyer | system (no signed-in user: a scheduled job)
  actor_role  TEXT        NOT NULL DEFAULT 'system',
  reason      TEXT,
  details     JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workflow_events_entity
  ON public.workflow_events (entity_type, entity_id, created_at);
CREATE INDEX IF NOT EXISTS idx_workflow_events_actor
  ON public.workflow_events (actor_id, created_at DESC);

ALTER TABLE public.workflow_events ENABLE ROW LEVEL SECURITY;

-- Staff only, read only. There is deliberately no INSERT / UPDATE / DELETE policy:
-- history is written by SECURITY DEFINER code and nowhere else. Farmers and Buyers
-- never read this table (it holds staff identities).
DROP POLICY IF EXISTS "workflow_events: staff reads" ON public.workflow_events;
CREATE POLICY "workflow_events: staff reads"
  ON public.workflow_events FOR SELECT
  USING (public.is_staff());

REVOKE ALL ON public.workflow_events FROM PUBLIC, anon;
GRANT SELECT ON public.workflow_events TO authenticated;

-- The one writer.
CREATE OR REPLACE FUNCTION public._wf_log(
  p_type    TEXT,
  p_id      UUID,
  p_action  TEXT,
  p_from    TEXT DEFAULT NULL,
  p_to      TEXT DEFAULT NULL,
  p_reason  TEXT DEFAULT NULL,
  p_details JSONB DEFAULT NULL,
  p_system  BOOLEAN DEFAULT FALSE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  UUID := CASE WHEN p_system THEN NULL ELSE auth.uid() END;
  v_role TEXT := 'system';
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT role INTO v_role FROM public.user_roles WHERE user_id = v_uid;
    v_role := COALESCE(v_role, 'system');
  END IF;
  INSERT INTO public.workflow_events
    (entity_type, entity_id, action, from_status, to_status, actor_id, actor_role, reason, details)
  VALUES
    (p_type, p_id, p_action, p_from, p_to, v_uid, v_role, NULLIF(btrim(COALESCE(p_reason, '')), ''), p_details);
END;
$$;
REVOKE ALL ON FUNCTION public._wf_log(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, JSONB, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- ─── Listings ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wf_listing_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_changes JSONB := '{}'::jsonb;
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public._wf_log('listing', NEW.id, 'submitted', NULL, NEW.status, NULL,
      jsonb_build_object('quantity', NEW.volume_kg, 'price', NEW.price_per_kg, 'unit', NEW.unit));
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public._wf_log('listing', NEW.id,
      CASE
        WHEN NEW.status = 'approved' AND OLD.status = 'pending_review' THEN 'approved'
        WHEN NEW.status = 'approved' THEN 'reopened'
        WHEN NEW.status = 'rejected'  THEN 'disapproved'
        WHEN NEW.status = 'withdrawn' THEN 'withdrawn'
        WHEN NEW.status = 'sold'      THEN 'sold_out'
        ELSE 'status_changed'
      END,
      OLD.status, NEW.status,
      CASE WHEN NEW.status = 'rejected' THEN NEW.admin_notes END);
    RETURN NEW;
  END IF;

  -- A change to what the listing says. The edit-request approval writes its own,
  -- richer event and switches this one off for its own UPDATE.
  IF COALESCE(current_setting('sagana.skip_listing_edit_event', true), '') <> '1' THEN
    IF NEW.volume_kg IS DISTINCT FROM OLD.volume_kg THEN
      v_changes := v_changes || jsonb_build_object('quantity', jsonb_build_object('from', OLD.volume_kg, 'to', NEW.volume_kg));
    END IF;
    IF NEW.price_per_kg IS DISTINCT FROM OLD.price_per_kg THEN
      v_changes := v_changes || jsonb_build_object('price', jsonb_build_object('from', OLD.price_per_kg, 'to', NEW.price_per_kg));
    END IF;
    IF NEW.description IS DISTINCT FROM OLD.description THEN
      v_changes := v_changes || jsonb_build_object('description', jsonb_build_object('from', OLD.description, 'to', NEW.description));
    END IF;
    IF NEW.photo_url IS DISTINCT FROM OLD.photo_url THEN
      v_changes := v_changes || jsonb_build_object('photo', TRUE);
    END IF;
    IF v_changes <> '{}'::jsonb THEN
      PERFORM public._wf_log('listing', NEW.id, 'edited', OLD.status, NEW.status, NULL,
        jsonb_build_object('changes', v_changes, 'unit', NEW.unit));
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_listing ON public.marketplace_listings;
CREATE TRIGGER trg_zz_wf_listing
  AFTER INSERT OR UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._wf_listing_trigger();

-- ─── Orders ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wf_order_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public._wf_log('order', NEW.id, 'placed', NULL, NEW.status, NULL,
      jsonb_build_object('quantity', NEW.quantity_kg, 'unit', NEW.unit, 'price', NEW.price_per_kg,
                         'total', NEW.total_price, 'fulfillment', NEW.fulfillment_method));
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public._wf_log('order', NEW.id, NEW.status, OLD.status, NEW.status);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_order ON public.orders;
CREATE TRIGGER trg_zz_wf_order
  AFTER INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._wf_order_trigger();

-- ─── Market Linking (DA-AMAD) requests ────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wf_market_linking_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public._wf_log('market_linking', NEW.id, 'submitted', NULL, NEW.status, NULL,
      jsonb_build_object('quantity', NEW.volume_kg, 'unit', NEW.unit));
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public._wf_log('market_linking', NEW.id, NEW.status, OLD.status, NEW.status);
  END IF;

  -- Buyer Details saved / changed (stage 2).
  IF COALESCE(btrim(NEW.buyer_name), '') <> ''
     AND (NEW.buyer_name    IS DISTINCT FROM OLD.buyer_name
       OR NEW.buyer_contact IS DISTINCT FROM OLD.buyer_contact
       OR NEW.buyer_email   IS DISTINCT FROM OLD.buyer_email) THEN
    PERFORM public._wf_log('market_linking', NEW.id, 'buyer_details_saved', NEW.status, NEW.status, NULL,
      jsonb_build_object('buyer', NEW.buyer_name));
  END IF;

  -- The Farmer's cancellation request and the staff answer.
  IF NEW.cancellation_status IS DISTINCT FROM OLD.cancellation_status AND NEW.cancellation_status IS NOT NULL THEN
    PERFORM public._wf_log('market_linking', NEW.id,
      CASE NEW.cancellation_status
        WHEN 'requested' THEN 'cancellation_requested'
        WHEN 'approved'  THEN 'cancellation_approved'
        WHEN 'rejected'  THEN 'cancellation_declined'
        WHEN 'withdrawn' THEN 'cancellation_withdrawn'
        ELSE 'cancellation_' || NEW.cancellation_status
      END,
      NEW.status, NEW.status,
      CASE WHEN NEW.cancellation_status = 'requested' THEN NEW.cancellation_reason
           ELSE NEW.cancellation_review_notes END);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_market_linking ON public.market_linking_programs;
CREATE TRIGGER trg_zz_wf_market_linking
  AFTER INSERT OR UPDATE ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public._wf_market_linking_trigger();

CREATE OR REPLACE FUNCTION public._wf_market_linking_sale_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._wf_log('market_linking', NEW.program_id, 'sale_recorded', NULL, NULL, NULL,
    jsonb_build_object('quantity', NEW.confirmed_volume_kg, 'unit', NEW.unit, 'price', NEW.price_per_kg,
                       'total', NEW.total_amount, 'buyer', NEW.buyer_name));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_market_linking_sale ON public.market_linking_sales;
CREATE TRIGGER trg_zz_wf_market_linking_sale
  AFTER INSERT ON public.market_linking_sales
  FOR EACH ROW EXECUTE FUNCTION public._wf_market_linking_sale_trigger();

-- ─── DA-AMAD enrollments ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wf_enrollment_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public._wf_log('market_linking_enrollment', NEW.id, 'submitted', NULL, NEW.status);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public._wf_log('market_linking_enrollment', NEW.id, NEW.status, OLD.status, NEW.status,
      CASE WHEN NEW.status = 'rejected' THEN NEW.admin_notes END);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_enrollment ON public.da_amad_enrollments;
CREATE TRIGGER trg_zz_wf_enrollment
  AFTER INSERT OR UPDATE ON public.da_amad_enrollments
  FOR EACH ROW EXECUTE FUNCTION public._wf_enrollment_trigger();

-- ─── Opening rows for records that already exist (idempotent) ─────────────
INSERT INTO public.workflow_events (entity_type, entity_id, action, to_status, actor_id, actor_role, created_at)
SELECT 'listing', l.id, 'submitted', 'pending_review', l.farmer_id,
       COALESCE((SELECT ur.role FROM public.user_roles ur WHERE ur.user_id = l.farmer_id), 'farmer'), l.created_at
FROM public.marketplace_listings l
WHERE NOT EXISTS (SELECT 1 FROM public.workflow_events e
                  WHERE e.entity_type = 'listing' AND e.entity_id = l.id AND e.action = 'submitted');

INSERT INTO public.workflow_events (entity_type, entity_id, action, to_status, actor_id, actor_role, created_at)
SELECT 'order', o.id, 'placed', 'pending', o.buyer_id,
       COALESCE((SELECT ur.role FROM public.user_roles ur WHERE ur.user_id = o.buyer_id), 'buyer'), o.created_at
FROM public.orders o
WHERE NOT EXISTS (SELECT 1 FROM public.workflow_events e
                  WHERE e.entity_type = 'order' AND e.entity_id = o.id AND e.action = 'placed');

-- ═══════════════════════════════════════════════════════════════════════
-- PART 1: edit requests
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.listing_edit_requests (
  id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id           UUID          NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  farmer_id            UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status               TEXT          NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  unit                 TEXT          NOT NULL DEFAULT 'kg',
  -- The listing as it was when the request was made.
  original_quantity    NUMERIC(10,2) NOT NULL,
  original_price       NUMERIC(10,2) NOT NULL,
  original_description TEXT,
  original_photo_url   TEXT,
  -- What the Farmer asks for. A NULL photo means "keep the photo".
  proposed_quantity    NUMERIC(10,2) NOT NULL CHECK (proposed_quantity > 0),
  proposed_price       NUMERIC(10,2) NOT NULL CHECK (proposed_price > 0),
  proposed_description TEXT          NOT NULL,
  proposed_photo_url   TEXT,
  review_reason        TEXT,
  reviewed_by          UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at          TIMESTAMPTZ,
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- One open request per listing.
CREATE UNIQUE INDEX IF NOT EXISTS uq_listing_edit_requests_one_pending
  ON public.listing_edit_requests (listing_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_listing_edit_requests_status
  ON public.listing_edit_requests (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_listing_edit_requests_listing
  ON public.listing_edit_requests (listing_id, created_at DESC);

ALTER TABLE public.listing_edit_requests ENABLE ROW LEVEL SECURITY;

-- Staff read everything. A Farmer reads nothing directly: the table holds the
-- reviewer's identity, so the Farmer goes through get_my_listing_edit_requests().
DROP POLICY IF EXISTS "listing_edit_requests: staff reads" ON public.listing_edit_requests;
CREATE POLICY "listing_edit_requests: staff reads"
  ON public.listing_edit_requests FOR SELECT
  USING (public.is_staff());

REVOKE ALL ON public.listing_edit_requests FROM PUBLIC, anon;
GRANT SELECT ON public.listing_edit_requests TO authenticated;

-- Live updates for the Pending Approvals screen.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
                     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'listing_edit_requests') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.listing_edit_requests';
  END IF;
END;
$$;

-- ─── Pending Approval listings are still edited directly ──────────────────
CREATE OR REPLACE FUNCTION public.update_my_listing(
  p_listing_id    UUID,
  p_quantity      NUMERIC,
  p_price_per_kg  NUMERIC,
  p_description   TEXT,
  p_refresh_photo BOOLEAN DEFAULT FALSE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_role    TEXT;
  v_status  TEXT;
  l         marketplace_listings%ROWTYPE;
  v_ordered NUMERIC;
  v_delta   NUMERIC;
  v_photo   TEXT;
  v_name    TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can edit a listing.';
  END IF;

  SELECT * INTO l FROM marketplace_listings
   WHERE id = p_listing_id AND farmer_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF l.status = 'approved' THEN
    RAISE EXCEPTION 'An approved listing is changed by sending an edit request for approval.';
  END IF;
  IF l.status <> 'pending_review' THEN
    RAISE EXCEPTION 'This listing can no longer be edited.';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_quantity > 99999999.99 THEN
    RAISE EXCEPTION 'The quantity is too large.';
  END IF;
  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter an asking price greater than zero.';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;
  IF p_price_per_kg > 99999999.99 THEN
    RAISE EXCEPTION 'The price is too large.';
  END IF;
  IF p_description IS NULL OR btrim(p_description) = '' THEN
    RAISE EXCEPTION 'A description is required for a listing.';
  END IF;

  v_ordered := l.volume_kg - l.remaining_kg;
  IF p_quantity <= v_ordered THEN
    RAISE EXCEPTION 'The quantity must be more than the % % already ordered.', v_ordered, l.unit;
  END IF;

  v_delta := p_quantity - l.volume_kg;
  IF v_delta <> 0 THEN
    IF l.inventory_batch_id IS NULL THEN
      RAISE EXCEPTION 'This listing is no longer linked to a harvest batch, so its quantity cannot be changed.';
    END IF;
    IF v_delta > 0 THEN
      PERFORM public._apply_batch_reservation(l.inventory_batch_id, v_delta);
    ELSE
      PERFORM public._release_batch_reservation(l.inventory_batch_id, -v_delta);
    END IF;
  END IF;

  IF p_refresh_photo THEN
    v_photo := public.farmer_crop_photo_for_batch(l.inventory_batch_id);
    IF v_photo IS NULL THEN
      RAISE EXCEPTION 'PHOTO_REQUIRED: Take a photo of your actual crop in Crop Roster before selling this batch.';
    END IF;
  END IF;

  UPDATE marketplace_listings
     SET volume_kg    = p_quantity,
         remaining_kg = l.remaining_kg + v_delta,
         price_per_kg = p_price_per_kg,
         description  = btrim(p_description),
         photo_url    = COALESCE(v_photo, l.photo_url)
   WHERE id = l.id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'listing',
    'Listing Updated',
    COALESCE(v_name, 'A farmer') || ' updated their ' || COALESCE(l.crop_name, 'produce') ||
      ' listing (pending approval): ' || p_quantity || ' ' || l.unit || ' at ' || p_price_per_kg || ' per ' || l.unit || '.',
    '/admin/marketplace/pending'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.update_my_listing(UUID, NUMERIC, NUMERIC, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_listing(UUID, NUMERIC, NUMERIC, TEXT, BOOLEAN) TO authenticated;

-- ─── The Farmer asks for a change to an approved listing ──────────────────
CREATE OR REPLACE FUNCTION public.request_listing_edit(
  p_listing_id   UUID,
  p_quantity     NUMERIC,
  p_price_per_kg NUMERIC,
  p_description  TEXT,
  p_photo_url    TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_role      TEXT;
  v_status    TEXT;
  l           marketplace_listings%ROWTYPE;
  v_ordered   NUMERIC;
  v_delta     NUMERIC;
  v_available NUMERIC;
  v_desc      TEXT := btrim(COALESCE(p_description, ''));
  v_photo     TEXT := NULLIF(btrim(COALESCE(p_photo_url, '')), '');
  v_id        UUID;
  v_name      TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can edit a listing.';
  END IF;

  SELECT * INTO l FROM marketplace_listings
   WHERE id = p_listing_id AND farmer_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF l.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved listing needs an edit request. A listing that is pending approval is edited directly.';
  END IF;
  IF l.remaining_kg <= 0 THEN
    RAISE EXCEPTION 'This listing is sold out and can no longer be edited.';
  END IF;
  IF EXISTS (SELECT 1 FROM listing_edit_requests WHERE listing_id = l.id AND status = 'pending') THEN
    RAISE EXCEPTION 'You already have an edit request waiting for approval on this listing.';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_quantity > 99999999.99 THEN
    RAISE EXCEPTION 'The quantity is too large.';
  END IF;
  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter an asking price greater than zero.';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;
  IF p_price_per_kg > 99999999.99 THEN
    RAISE EXCEPTION 'The price is too large.';
  END IF;
  IF v_desc = '' THEN
    RAISE EXCEPTION 'A description is required for a listing.';
  END IF;

  -- The new photo must be one this Farmer uploaded to the listing photo bucket.
  IF v_photo IS NOT NULL AND position('/listing_photos/' || v_uid::text || '/' IN v_photo) = 0 THEN
    RAISE EXCEPTION 'That photo was not uploaded from your account.';
  END IF;

  v_ordered := l.volume_kg - l.remaining_kg;
  IF p_quantity <= v_ordered THEN
    RAISE EXCEPTION 'The quantity must be more than the % % already ordered.', v_ordered, l.unit;
  END IF;

  v_delta := p_quantity - l.volume_kg;
  IF v_delta <> 0 THEN
    IF l.inventory_batch_id IS NULL THEN
      RAISE EXCEPTION 'This listing is no longer linked to a harvest batch, so its quantity cannot be changed.';
    END IF;
    IF v_delta > 0 THEN
      -- An early answer only: nothing is reserved until the change is approved,
      -- and the approval checks the batch again.
      SELECT available_kg INTO v_available FROM inventory_batches WHERE id = l.inventory_batch_id;
      IF COALESCE(v_available, 0) < v_delta THEN
        RAISE EXCEPTION 'Not enough available quantity in this batch.';
      END IF;
    END IF;
  END IF;

  IF p_quantity = l.volume_kg AND p_price_per_kg = l.price_per_kg
     AND v_desc = btrim(COALESCE(l.description, '')) AND v_photo IS NULL THEN
    RAISE EXCEPTION 'You have not changed anything.';
  END IF;

  INSERT INTO listing_edit_requests (
    listing_id, farmer_id, unit,
    original_quantity, original_price, original_description, original_photo_url,
    proposed_quantity, proposed_price, proposed_description, proposed_photo_url
  ) VALUES (
    l.id, v_uid, l.unit,
    l.volume_kg, l.price_per_kg, l.description, l.photo_url,
    p_quantity, p_price_per_kg, v_desc, v_photo
  ) RETURNING id INTO v_id;

  PERFORM public._wf_log('listing', l.id, 'edit_requested', l.status, l.status, NULL,
    jsonb_build_object('request_id', v_id, 'unit', l.unit,
      'changes', jsonb_strip_nulls(jsonb_build_object(
        'quantity',    CASE WHEN p_quantity <> l.volume_kg THEN jsonb_build_object('from', l.volume_kg, 'to', p_quantity) END,
        'price',       CASE WHEN p_price_per_kg <> l.price_per_kg THEN jsonb_build_object('from', l.price_per_kg, 'to', p_price_per_kg) END,
        'description', CASE WHEN v_desc <> btrim(COALESCE(l.description, '')) THEN jsonb_build_object('from', l.description, 'to', v_desc) END,
        'photo',       CASE WHEN v_photo IS NOT NULL THEN TRUE END))));

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'listing',
    'Listing Edit Request',
    COALESCE(v_name, 'A farmer') || ' asked to change their published ' || COALESCE(l.crop_name, 'produce') ||
      ' listing. It stays as it is until you decide.',
    '/admin/marketplace/pending'
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.request_listing_edit(UUID, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_listing_edit(UUID, NUMERIC, NUMERIC, TEXT, TEXT) TO authenticated;

-- ─── Manager / Officer approves: the change is applied ────────────────────
CREATE OR REPLACE FUNCTION public.approve_listing_edit(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  r           listing_edit_requests%ROWTYPE;
  l           marketplace_listings%ROWTYPE;
  b           inventory_batches%ROWTYPE;
  v_ordered   NUMERIC;
  v_delta     NUMERIC;
  v_new_avail NUMERIC;
  v_new_state TEXT;
  v_changes   JSONB;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can approve a listing edit';
  END IF;

  SELECT * INTO r FROM listing_edit_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Edit request not found';
  END IF;
  IF r.status <> 'pending' THEN
    RAISE EXCEPTION 'This edit request was already decided (%).', r.status;
  END IF;

  -- The same lock place_order takes.
  SELECT * INTO l FROM marketplace_listings WHERE id = r.listing_id FOR UPDATE;
  IF NOT FOUND OR l.status <> 'approved' THEN
    RAISE EXCEPTION 'The listing is no longer published, so this change cannot be applied. Disapprove the request instead.';
  END IF;
  IF l.remaining_kg <= 0 THEN
    RAISE EXCEPTION 'The listing is sold out, so this change cannot be applied. Disapprove the request instead.';
  END IF;

  -- Orders may have come in since the request was made.
  v_ordered := l.volume_kg - l.remaining_kg;
  IF r.proposed_quantity <= v_ordered THEN
    RAISE EXCEPTION 'Buyers have already ordered % % of this listing, which is not less than the requested quantity. Disapprove the request instead.',
      v_ordered, l.unit;
  END IF;

  v_delta := r.proposed_quantity - l.volume_kg;
  IF v_delta <> 0 THEN
    IF l.inventory_batch_id IS NULL THEN
      RAISE EXCEPTION 'The listing is no longer linked to a harvest batch, so its quantity cannot be changed.';
    END IF;
    IF v_delta > 0 THEN
      -- The helper used for a Farmer's own reservation refuses anyone but the
      -- batch owner, so the same arithmetic is done here for the approving staff.
      SELECT * INTO b FROM inventory_batches WHERE id = l.inventory_batch_id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'The harvest batch of this listing was not found.';
      END IF;
      IF b.available_kg < v_delta THEN
        RAISE EXCEPTION 'Not enough available quantity in the Farmer''s batch (% % free, % % more requested). Disapprove the request instead.',
          b.available_kg, l.unit, v_delta, l.unit;
      END IF;
      v_new_avail := b.available_kg - v_delta;
      v_new_state := CASE
        WHEN v_new_avail <= 0 THEN CASE WHEN b.sold_kg >= b.quantity_kg THEN 'sold_out' ELSE 'reserved' END
        WHEN v_new_avail < b.quantity_kg * 0.15 THEN 'low_stock'
        ELSE 'available' END;
      UPDATE inventory_batches SET available_kg = v_new_avail, status = v_new_state WHERE id = b.id;
    ELSE
      PERFORM public._release_batch_reservation(l.inventory_batch_id, -v_delta);
    END IF;
  END IF;

  v_changes := jsonb_strip_nulls(jsonb_build_object(
    'quantity',    CASE WHEN r.proposed_quantity <> l.volume_kg THEN jsonb_build_object('from', l.volume_kg, 'to', r.proposed_quantity) END,
    'price',       CASE WHEN r.proposed_price <> l.price_per_kg THEN jsonb_build_object('from', l.price_per_kg, 'to', r.proposed_price) END,
    'description', CASE WHEN r.proposed_description <> btrim(COALESCE(l.description, '')) THEN jsonb_build_object('from', l.description, 'to', r.proposed_description) END,
    'photo',       CASE WHEN r.proposed_photo_url IS NOT NULL THEN TRUE END));

  PERFORM set_config('sagana.skip_listing_edit_event', '1', true);
  UPDATE marketplace_listings
     SET volume_kg    = r.proposed_quantity,
         remaining_kg = l.remaining_kg + v_delta,
         price_per_kg = r.proposed_price,
         description  = r.proposed_description,
         photo_url    = COALESCE(r.proposed_photo_url, l.photo_url)
   WHERE id = l.id;
  PERFORM set_config('sagana.skip_listing_edit_event', '0', true);

  UPDATE listing_edit_requests
     SET status = 'approved', reviewed_by = v_uid, reviewed_at = NOW()
   WHERE id = r.id;

  PERFORM public._wf_log('listing', l.id, 'edit_approved', l.status, l.status, NULL,
    jsonb_build_object('request_id', r.id, 'unit', l.unit, 'changes', v_changes));

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (r.farmer_id, 'listing', 'Listing Changes Approved',
          'Your changes to the ' || COALESCE(l.crop_name, 'produce') || ' listing were approved and are now live.',
          FALSE, NOW(), '/farmer/marketplace');
END;
$$;
REVOKE ALL ON FUNCTION public.approve_listing_edit(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_listing_edit(UUID) TO authenticated;

-- ─── Manager / Officer disapproves: a reason is required ──────────────────
CREATE OR REPLACE FUNCTION public.reject_listing_edit(p_request_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_reason TEXT := btrim(COALESCE(p_reason, ''));
  r        listing_edit_requests%ROWTYPE;
  v_crop   TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can disapprove a listing edit';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason for disapproving this edit request.';
  END IF;

  SELECT * INTO r FROM listing_edit_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Edit request not found';
  END IF;
  IF r.status <> 'pending' THEN
    RAISE EXCEPTION 'This edit request was already decided (%).', r.status;
  END IF;

  UPDATE listing_edit_requests
     SET status = 'rejected', reviewed_by = v_uid, reviewed_at = NOW(), review_reason = v_reason
   WHERE id = r.id;

  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = r.listing_id;

  PERFORM public._wf_log('listing', r.listing_id, 'edit_rejected', NULL, NULL, v_reason,
    jsonb_build_object('request_id', r.id, 'unit', r.unit));

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (r.farmer_id, 'listing', 'Listing Changes Disapproved',
          'Your requested changes to the ' || COALESCE(v_crop, 'produce') ||
            ' listing were not approved. Your listing stays as it was. Reason: ' || v_reason,
          FALSE, NOW(), '/farmer/marketplace');
END;
$$;
REVOKE ALL ON FUNCTION public.reject_listing_edit(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_listing_edit(UUID, TEXT) TO authenticated;

-- ─── The Farmer takes back their own open request ─────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_listing_edit_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r     listing_edit_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT * INTO r FROM listing_edit_requests WHERE id = p_request_id AND farmer_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Edit request not found';
  END IF;
  IF r.status <> 'pending' THEN
    RAISE EXCEPTION 'This edit request was already decided (%).', r.status;
  END IF;

  UPDATE listing_edit_requests SET status = 'cancelled', reviewed_at = NOW() WHERE id = r.id;
  PERFORM public._wf_log('listing', r.listing_id, 'edit_cancelled', NULL, NULL, NULL,
    jsonb_build_object('request_id', r.id, 'unit', r.unit));
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_listing_edit_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_listing_edit_request(UUID) TO authenticated;

-- ─── A listing that stops being published closes its open request ─────────
CREATE OR REPLACE FUNCTION public._listing_close_edit_requests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id, unit FROM listing_edit_requests WHERE listing_id = NEW.id AND status = 'pending' LOOP
    UPDATE listing_edit_requests
       SET status = 'cancelled', reviewed_at = NOW(),
           review_reason = 'The listing is no longer published.'
     WHERE id = r.id;
    PERFORM public._wf_log('listing', NEW.id, 'edit_cancelled', NULL, NULL,
      'The listing is no longer published.', jsonb_build_object('request_id', r.id, 'unit', r.unit), TRUE);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_listing_close_edit_requests ON public.marketplace_listings;
CREATE TRIGGER trg_listing_close_edit_requests
  AFTER UPDATE OF status ON public.marketplace_listings
  FOR EACH ROW WHEN (OLD.status = 'approved' AND NEW.status <> 'approved')
  EXECUTE FUNCTION public._listing_close_edit_requests();

-- ─── What a Farmer may read (no staff identity anywhere) ──────────────────
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
           r.review_reason, r.reviewed_at, r.created_at
    FROM public.listing_edit_requests r
    WHERE r.listing_id = p_listing_id AND r.farmer_id = auth.uid()
    ORDER BY r.created_at DESC
    LIMIT 50
  ) x;
$$;
REVOKE ALL ON FUNCTION public.get_my_listing_edit_requests(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_listing_edit_requests(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_listing_history(p_listing_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
  FROM (
    SELECT e.id, e.action, e.from_status, e.to_status, e.reason, e.details, e.created_at,
           CASE
             WHEN e.actor_id = auth.uid()            THEN 'you'
             WHEN e.actor_role IN ('admin', 'officer') THEN 'cooperative'
             ELSE 'system'
           END AS by
    FROM public.workflow_events e
    JOIN public.marketplace_listings l ON l.id = e.entity_id
    WHERE e.entity_type = 'listing' AND l.id = p_listing_id AND l.farmer_id = auth.uid()
    ORDER BY e.created_at DESC
    LIMIT 200
  ) x;
$$;
REVOKE ALL ON FUNCTION public.get_my_listing_history(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_listing_history(UUID) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY CHECKS (read-only) ───────────────────────────────────────
-- 1. The new objects exist (expect 6 functions + 2 tables + 7 triggers):
--      SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN
--        ('request_listing_edit','approve_listing_edit','reject_listing_edit',
--         'cancel_listing_edit_request','get_my_listing_edit_requests','get_my_listing_history');
--      SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'trg_zz_wf_%' OR tgname = 'trg_listing_close_edit_requests';
-- 2. Farmers and anon have no direct table access (expect false, false, false, false):
--      SELECT has_table_privilege('anon','public.workflow_events','SELECT'),
--             has_table_privilege('anon','public.listing_edit_requests','SELECT'),
--             has_function_privilege('anon','public.approve_listing_edit(uuid)','EXECUTE'),
--             has_function_privilege('anon','public.request_listing_edit(uuid,numeric,numeric,text,text)','EXECUTE');
-- 3. Every row of an existing listing has its opening event (expect 0):
--      SELECT count(*) FROM marketplace_listings l WHERE NOT EXISTS
--        (SELECT 1 FROM workflow_events e WHERE e.entity_type='listing' AND e.entity_id=l.id);
