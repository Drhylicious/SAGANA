-- ============================================================
-- SAGANA — Remove dead farmer_profiles.capital_shares column
--
-- capital_shares on farmer_profiles has never been the real
-- source of truth for a farmer's capital shares — that's always
-- been member_capital_shares (total_shares × share_value_per_unit,
-- computed by FarmerProfileRepository.fetchProfile() /
-- ContributionRepository.fetchCapitalShares()). Every account-
-- creation RPC that accepts p_capital_shares (create_farmer_account,
-- admin_create_member, and their fixed-up variants) writes to
-- member_capital_shares, never to this column.
--
-- Confirmed dead on both sides via full-codebase grep (Farmer
-- Profile Tab review, Phase 6 / DC1): no Dart file reads this
-- column directly, and FarmerProfileRepository.fetchProfile()'s
-- map-merge order always overwrites any 'capital_shares' key with
-- the live-computed value before it reaches the UI, even if the
-- column ever held one.
-- ============================================================

ALTER TABLE public.farmer_profiles
  DROP COLUMN IF EXISTS capital_shares;

NOTIFY pgrst, 'reload schema';