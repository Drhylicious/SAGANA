-- ============================================================
-- SAGANA — Crop Management: crop reference images
-- (Admin Dashboard investigation, Issue 4 / Phase 5)
--
-- Adds a reference-image field to the crop catalog (crop_master), shown
-- when the admin adds a crop and propagated to the Farmer side wherever a
-- crop from the master catalog is displayed. This is a separate concept
-- from farmer_crops.photo_url (a farmer's own photo of their specific
-- planting) — image_url here is the admin-curated, one-per-catalog-entry
-- reference image, same for every farmer growing that crop.
--
-- No storage bucket or RLS work needed here — the 'crop_images' bucket and
-- its owner-upload / public-read policies already exist (created in
-- supabase_schema_fixes.sql) but were never wired to an actual column or
-- upload flow until now. Uploads must be written under the uploading
-- admin's own uid folder (crop_images/<uid>/...), per the existing
-- "Crop images owner upload" policy's foldername check.
-- ============================================================

ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS image_url TEXT;
