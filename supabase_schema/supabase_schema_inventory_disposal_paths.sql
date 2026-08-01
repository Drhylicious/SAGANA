-- ============================================================
-- SAGANA — Inventory Disposal Paths
-- Cooperative eligibility, Offer-to-Cooperative, Informal Sales,
-- and atomic quantity reservation for all three disposal paths.
-- ============================================================

-- Eligibility lives on the catalog, not guessed from crop names downstream.
ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS is_cooperative_eligible BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.crop_master
  SET is_cooperative_eligible = TRUE
  WHERE crop_name IN ('Palay', 'Peanut');

-- Denormalized onto each batch at harvest time (offline-safe, avoids a
-- 2-hop join on every Inventory fetch).
ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS is_coop_eligible BOOLEAN NOT NULL DEFAULT FALSE;

-- ─── Offer to Cooperative ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cooperative_purchase_offers (
  id                          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id                   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  inventory_batch_id          UUID        NOT NULL REFERENCES public.inventory_batches(id),
  crop_name                   TEXT        NOT NULL,
  offered_quantity_kg         DECIMAL(10,2) NOT NULL CHECK (offered_quantity_kg > 0),
  status                      TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'confirmed', 'declined')),
  confirmed_quantity_kg       DECIMAL(10,2),
  confirmed_amount            DECIMAL(10,2),
  member_sales_transaction_id UUID        REFERENCES public.member_sales_transactions(id),
  confirmed_by                UUID        REFERENCES auth.users(id),
  offered_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  confirmed_at                TIMESTAMPTZ
);

ALTER TABLE public.cooperative_purchase_offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "coop_offers: farmer creates and reads own" ON public.cooperative_purchase_offers;
CREATE POLICY "coop_offers: farmer creates and reads own"
  ON public.cooperative_purchase_offers FOR SELECT
  USING (auth.uid() = farmer_id);

DROP POLICY IF EXISTS "coop_offers: farmer inserts own" ON public.cooperative_purchase_offers;
CREATE POLICY "coop_offers: farmer inserts own"
  ON public.cooperative_purchase_offers FOR INSERT
  WITH CHECK (auth.uid() = farmer_id);

DROP POLICY IF EXISTS "coop_offers: admin manages all" ON public.cooperative_purchase_offers;
CREATE POLICY "coop_offers: admin manages all"
  ON public.cooperative_purchase_offers FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles ap WHERE ap.user_id = auth.uid()));

-- ─── Informal Sales ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.informal_sales (
  id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id           UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  inventory_batch_id  UUID        NOT NULL REFERENCES public.inventory_batches(id),
  crop_name           TEXT        NOT NULL,
  quantity_kg         DECIMAL(10,2) NOT NULL CHECK (quantity_kg > 0),
  buyer_name          TEXT,
  amount              DECIMAL(10,2),
  notes               TEXT,
  sale_date           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.informal_sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "informal_sales: farmer manages own" ON public.informal_sales;
CREATE POLICY "informal_sales: farmer manages own"
  ON public.informal_sales FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

DROP POLICY IF EXISTS "informal_sales: admin reads all" ON public.informal_sales;
CREATE POLICY "informal_sales: admin reads all"
  ON public.informal_sales FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.admin_profiles ap WHERE ap.user_id = auth.uid()));

-- ─── Shared quantity-decrement logic ────────────────────────────────────────
-- Mirrors InventoryRepository.updateQuantity()'s existing status thresholds,
-- so all three paths (and the existing manual-adjustment path) agree on
-- what "low stock" / "sold out" means.

CREATE OR REPLACE FUNCTION public._apply_batch_reservation(
  p_batch_id UUID,
  p_quantity DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_quantity_kg DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_available DECIMAL;
  v_new_status TEXT;
BEGIN
  SELECT quantity_kg, available_kg, sold_kg
    INTO v_quantity_kg, v_available_kg, v_sold_kg
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE; -- lock the row for the duration of this transaction

  IF v_available_kg < p_quantity THEN
    RAISE EXCEPTION 'Not enough available quantity in this batch.';
  END IF;

  v_new_available := v_available_kg - p_quantity;

  IF v_new_available <= 0 THEN
    v_new_status := CASE WHEN v_sold_kg >= v_quantity_kg THEN 'sold_out' ELSE 'reserved' END;
  ELSIF v_new_available < v_quantity_kg * 0.15 THEN
    v_new_status := 'low_stock';
  ELSE
    v_new_status := 'available';
  END IF;

  UPDATE public.inventory_batches
    SET available_kg = v_new_available, status = v_new_status
    WHERE id = p_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── RPC: create a Marketplace listing + reserve quantity ──────────────────

CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_variety TEXT,
  p_quantity_kg DECIMAL,
  p_price_per_kg DECIMAL,
  p_photo_url TEXT
) RETURNS UUID AS $$
DECLARE
  v_listing_id UUID;
BEGIN
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_name, variety, quantity_kg,
    price_per_kg, photo_url, status
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending'
  ) RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── RPC: offer a batch to the cooperative + reserve quantity ──────────────

CREATE OR REPLACE FUNCTION public.offer_batch_to_cooperative(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_quantity_kg DECIMAL
) RETURNS UUID AS $$
DECLARE
  v_offer_id UUID;
  v_eligible BOOLEAN;
BEGIN
  SELECT is_coop_eligible INTO v_eligible
    FROM public.inventory_batches WHERE id = p_batch_id;

  IF NOT v_eligible THEN
    RAISE EXCEPTION 'This crop is not eligible for cooperative purchase.';
  END IF;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.cooperative_purchase_offers (
    farmer_id, inventory_batch_id, crop_name, offered_quantity_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_quantity_kg
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── RPC: record an informal sale + reserve quantity ───────────────────────

CREATE OR REPLACE FUNCTION public.record_informal_sale(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_quantity_kg DECIMAL,
  p_buyer_name TEXT,
  p_amount DECIMAL,
  p_notes TEXT
) RETURNS UUID AS $$
DECLARE
  v_sale_id UUID;
BEGIN
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.informal_sales (
    farmer_id, inventory_batch_id, crop_name, quantity_kg,
    buyer_name, amount, notes
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_quantity_kg,
    p_buyer_name, p_amount, p_notes
  ) RETURNING id INTO v_sale_id;

  RETURN v_sale_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;