-- ============================================================
-- SAGANA — Market Linking: Requested Volume (Admin Marketplace
-- review, Market Linking phase)
--
-- The "Update Status" dialog previously had no way to capture how
-- much the buyer actually wants to purchase at the point a buyer is
-- found — only "Confirmed Volume", which only appears later, at
-- Completion, and only once a harvest batch is selected. This adds
-- a distinct column captured at Buyer Found time, independent of any
-- batch being attached.
-- ============================================================

ALTER TABLE public.market_linking_programs
  ADD COLUMN IF NOT EXISTS requested_volume_kg NUMERIC;

COMMENT ON COLUMN public.market_linking_programs.requested_volume_kg IS
  'Quantity the buyer expressed interest in purchasing, captured when the
   entry moves to buyer_found. Distinct from volume_kg (committed by the
   farmer at enrollment) and confirmed_volume_kg (final, set only at
   completion when a batch is attached) — this is the buyer''s stated
   intent in between those two points. Optional.';
