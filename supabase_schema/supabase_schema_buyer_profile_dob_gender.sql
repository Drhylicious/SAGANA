-- ============================================================
-- SAGANA — Buyer Profile: Date of Birth + Gender
--
-- Buyer Management (Admin Marketplace review) confirmed every field
-- present in Buyer Edit Profile should also be shown in Buyer Details.
-- Two of those fields — date of birth and gender — didn't exist
-- anywhere in the schema for buyers yet (only farmer_profiles had
-- them, added by supabase_schema_phase_b_member_id_capital_dob.sql).
-- This adds the buyer-side equivalent onto buyer_profiles, following
-- the exact same column names/constraint as farmer_profiles so both
-- roles share one convention.
-- ============================================================

ALTER TABLE public.buyer_profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS gender TEXT;

ALTER TABLE public.buyer_profiles
  DROP CONSTRAINT IF EXISTS buyer_profiles_gender_check;
ALTER TABLE public.buyer_profiles
  ADD CONSTRAINT buyer_profiles_gender_check
  CHECK (gender IS NULL OR gender IN ('male', 'female', 'prefer_not_to_say'));

COMMENT ON COLUMN public.buyer_profiles.date_of_birth IS
  'Optional, buyer-entered via Edit Profile. No 18+ enforcement at the
   DB level (matches farmer_profiles — the 18+ check is client-side only,
   at date-of-birth entry time).';
COMMENT ON COLUMN public.buyer_profiles.gender IS
  'male | female | prefer_not_to_say — optional, buyer-entered.';
