-- ============================================================
-- SAGANA — Farmer Profile Screen: Storage Setup Only
-- Covers: Farmer Profile Screen (profile photo upload)
--
-- NO TABLE CHANGES REQUIRED.
-- All fields used by this screen already exist:
--   - user_information.profile_photo_url, full_name, phone_number, sitio
--   - farmer_profiles.member_id, farm_name, farm_location,
--     land_area_hectares, years_farming, capital_shares,
--     member_since, is_verified
--   - farmer_crops.crop_name (queried for "Primary Crops" display)
--
-- Only a new Storage bucket is needed for profile photo uploads.
-- ============================================================

-- Create in Supabase Dashboard → Storage, or via SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('profile_photos', 'profile_photos', true)
ON CONFLICT DO NOTHING;
