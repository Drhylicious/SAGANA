-- ============================================================
-- SAGANA — Top Harvested Crops Schema
-- Covers: Farmer Analytics Screen → Top Harvested Crops chart
--
-- Cooperative-wide, fixed 90-day window, period-independent —
-- same design intent as crop_planting_forecast/crop_cycle_volumes:
-- this answers "what's the cooperative growing most," not a
-- farmer's own filtered performance, so it isn't tied to the
-- Analytics period selector.
--
-- Why this view exists: harvest_records' own RLS only grants
-- "farmer manages own" + "admin reads all" — there is no
-- farmer-facing coop-wide read policy. AnalyticsRepository was
-- previously querying harvest_records directly for this feature,
-- which meant a farmer only ever saw their own harvest data,
-- not the cooperative-wide reference this chart is meant to show.
-- This view uses the same view-owner-bypasses-RLS mechanism
-- crop_planting_forecast already relies on, instead of loosening
-- RLS on harvest_records itself.
-- ============================================================

CREATE OR REPLACE VIEW public.top_harvested_crops AS
SELECT
  crop_name,
  SUM(quantity_kg) AS total_kg
FROM public.harvest_records
WHERE harvest_date >= NOW() - INTERVAL '90 days'
GROUP BY crop_name;

-- Note: views inherit RLS from underlying tables, but since this is
-- cooperative-wide aggregate data with no farmer_id exposed, it's safe
-- to expose to all authenticated users — same reasoning already applied
-- to crop_planting_forecast/crop_cycle_volumes.

GRANT SELECT ON public.top_harvested_crops TO authenticated;