-- ═════════════════════════════════════════════════════════════════════════════
-- supabase_schema_fixes.sql
-- Run this entire file in Supabase SQL Editor → Run
-- Fixes all errors found during Farmer Side testing (June 2026)
-- ═════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 1: Add missing columns to farmer_loans
-- The dashboard_repository queries next_payment_date, monthly_payment,
-- and loan_reference which don't exist in the original schema.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE farmer_loans
  ADD COLUMN IF NOT EXISTS loan_reference     TEXT,
  ADD COLUMN IF NOT EXISTS next_payment_date  DATE,
  ADD COLUMN IF NOT EXISTS monthly_payment    NUMERIC(10, 2) DEFAULT 0;

-- Auto-generate loan_reference for any existing rows that have none
UPDATE farmer_loans
SET loan_reference = 'LOAN-' || UPPER(SUBSTRING(id::text, 1, 8))
WHERE loan_reference IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 2: Create orders table
-- Required by dashboard_repository and buyer side (future).
-- Tracks marketplace orders placed by buyers against farmer listings.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id            UUID NOT NULL REFERENCES marketplace_listings(id) ON DELETE CASCADE,
  farmer_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buyer_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quantity_kg           NUMERIC(10, 2) NOT NULL CHECK (quantity_kg > 0),
  price_per_kg          NUMERIC(10, 2) NOT NULL,
  total_price           NUMERIC(10, 2) NOT NULL,
  status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','approved','completed','cancelled')),
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger to keep updated_at current
CREATE OR REPLACE FUNCTION handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_updated_at ON orders;
CREATE TRIGGER orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- Indexes for the most common queries
CREATE INDEX IF NOT EXISTS orders_farmer_id_idx ON orders(farmer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_buyer_id_idx  ON orders(buyer_id,  created_at DESC);
CREATE INDEX IF NOT EXISTS orders_listing_id_idx ON orders(listing_id);
CREATE INDEX IF NOT EXISTS orders_status_idx    ON orders(status);

-- RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Farmers: see orders for their listings
CREATE POLICY "Farmers see own orders"
  ON orders FOR SELECT
  USING (auth.uid() = farmer_id);

-- Buyers: see their own orders
CREATE POLICY "Buyers see own orders"
  ON orders FOR SELECT
  USING (auth.uid() = buyer_id);

-- Buyers: place orders
CREATE POLICY "Buyers create orders"
  ON orders FOR INSERT
  WITH CHECK (auth.uid() = buyer_id);

-- Farmers: update order status (approve/complete)
CREATE POLICY "Farmers update order status"
  ON orders FOR UPDATE
  USING (auth.uid() = farmer_id);

-- Admin: full access
CREATE POLICY "Admin full access to orders"
  ON orders FOR ALL
  USING (
    EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 3: Storage bucket policies
-- Run these after creating the buckets manually in the Supabase dashboard
-- (Storage → New bucket → name → Public ON)
-- Buckets needed: profile_photos, crop_images, listing_photos
-- ─────────────────────────────────────────────────────────────────────────────

-- PROFILE PHOTOS bucket policies
-- Allows authenticated users to upload to their own folder
-- and anyone to read (public bucket)

INSERT INTO storage.buckets (id, name, public)
VALUES ('profile_photos', 'profile_photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('crop_images', 'crop_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('listing_photos', 'listing_photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ── Profile photos policies ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "Profile photos public read"   ON storage.objects;
DROP POLICY IF EXISTS "Profile photos owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Profile photos owner delete"  ON storage.objects;

CREATE POLICY "Profile photos public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'profile_photos');

CREATE POLICY "Profile photos owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Profile photos owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Profile photos owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Crop images policies ──────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Crop images public read"   ON storage.objects;
DROP POLICY IF EXISTS "Crop images owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Crop images owner delete"  ON storage.objects;

CREATE POLICY "Crop images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'crop_images');

CREATE POLICY "Crop images owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'crop_images'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Crop images owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'crop_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Crop images owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'crop_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Listing photos policies ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "Listing photos public read"   ON storage.objects;
DROP POLICY IF EXISTS "Listing photos owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Listing photos owner delete"  ON storage.objects;

CREATE POLICY "Listing photos public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'listing_photos');

CREATE POLICY "Listing photos owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'listing_photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Listing photos owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'listing_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Listing photos owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'listing_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );