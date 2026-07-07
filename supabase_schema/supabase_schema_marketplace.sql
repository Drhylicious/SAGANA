-- ============================================================
-- SAGANA — Marketplace Listings Schema
-- Covers: My Listings Screen, Create Listing Screen,
--         Listing Submission Success Screen
--
-- New table: marketplace_listings
-- Depends on: inventory_batches (inventory_batch_id FK, optional)
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: marketplace_listings
-- status workflow:
--   pending_review    — submitted by farmer, awaiting admin approval
--   approved          — live on marketplace, visible to buyers
--   changes_required  — admin requested edits (see admin_notes)
--   withdrawn         — farmer voluntarily removed listing
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.marketplace_listings (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id           UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  inventory_batch_id  UUID          REFERENCES public.inventory_batches(id) ON DELETE SET NULL,
  crop_name           TEXT          NOT NULL,
  variety             TEXT,
  price_per_kg        DECIMAL(10,2) NOT NULL CHECK (price_per_kg > 0),
  volume_kg           DECIMAL(10,2) NOT NULL CHECK (volume_kg > 0),
  status              TEXT          NOT NULL DEFAULT 'pending_review'
                      CHECK (status IN ('pending_review', 'approved', 'changes_required', 'withdrawn')),
  photo_url           TEXT,
  admin_notes         TEXT,
  reviewed_by         UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  submitted_at        TIMESTAMPTZ   DEFAULT NOW(),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_marketplace_listings_updated_at
  BEFORE UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_marketplace_listings_farmer
  ON public.marketplace_listings (farmer_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_marketplace_listings_approved
  ON public.marketplace_listings (status, created_at DESC)
  WHERE status = 'approved';

-- RLS
ALTER TABLE public.marketplace_listings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "marketplace_listings: farmer manages own"
  ON public.marketplace_listings FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

CREATE POLICY "marketplace_listings: admin manages all"
  ON public.marketplace_listings FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );

-- Buyers can read approved listings only
CREATE POLICY "marketplace_listings: buyers read approved"
  ON public.marketplace_listings FOR SELECT
  USING (status = 'approved' AND auth.role() = 'authenticated');

-- ─────────────────────────────────────────────────────────────────────────────
-- Storage Bucket
-- ─────────────────────────────────────────────────────────────────────────────
-- listing_photos — public read, farmer upload only
--
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('listing_photos', 'listing_photos', true)
-- ON CONFLICT DO NOTHING;
