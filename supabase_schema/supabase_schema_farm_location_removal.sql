-- ============================================================
-- SAGANA — Remove legacy farm_location column
--
-- farm_location duplicated farm_address (both were written
-- identically by EditFarmDetailsScreen). Confirmed zero
-- remaining Dart consumers across the Farmer module, Admin's
-- FarmerDetailsRepository/AdminProfileRepository, and the CSV
-- export/report serializer services before this was drafted.
-- ============================================================

ALTER TABLE public.farmer_profiles
  DROP COLUMN IF EXISTS farm_location;

NOTIFY pgrst, 'reload schema';
