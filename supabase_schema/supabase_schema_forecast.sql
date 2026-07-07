-- ============================================================
-- SAGANA — Planting Trend Forecast Schema
-- Covers: Farmer Analytics Screen → Planting Insights section
--
-- METHODOLOGY (disclosed for thesis defense):
-- Weighted Moving Average (WMA) over the last 3 thirty-day
-- harvest cycles, cooperative-wide (all farmers combined).
-- Weight ratio 3:2:1, most recent cycle weighted highest.
--
--   forecast = (3 * cycle_n + 2 * cycle_n-1 + 1 * cycle_n-2) / 6
--
-- This is a supply-side forecast only. It predicts expected
-- cooperative-wide harvest volume for the next 30-day cycle,
-- it does NOT claim to know buyer demand. Trend direction
-- (Up/Stable/Down) is derived by comparing the forecast to the
-- most recent actual cycle.
--
-- Minimum data requirement: a crop needs at least 2 cycles of
-- harvest history before a forecast is shown. Below that, the
-- view returns NULL for forecast_kg and the app displays
-- "Not enough harvest history yet."
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- VIEW: crop_cycle_volumes
-- Buckets all harvest_records into rolling 30-day cycles per crop,
-- cooperative-wide (sum across all farmers).
-- cycle_index: 0 = most recent 30 days, 1 = the 30 days before that, etc.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.crop_cycle_volumes AS
SELECT
  crop_name,
  FLOOR(EXTRACT(EPOCH FROM (NOW() - harvest_date)) / (30 * 86400))::INT AS cycle_index,
  SUM(quantity_kg) AS cycle_volume_kg
FROM public.harvest_records
WHERE harvest_date >= NOW() - INTERVAL '180 days'  -- last 6 cycles max, keeps the view light
GROUP BY crop_name, cycle_index;

-- ─────────────────────────────────────────────────────────────────────────────
-- VIEW: crop_planting_forecast
-- Computes the WMA forecast and trend label per crop.
-- Only crops with at least 2 distinct cycles get a non-null forecast.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.crop_planting_forecast AS
WITH cycles AS (
  SELECT
    crop_name,
    cycle_index,
    cycle_volume_kg
  FROM public.crop_cycle_volumes
  WHERE cycle_index BETWEEN 0 AND 2  -- only need the 3 most recent cycles
),
pivoted AS (
  SELECT
    crop_name,
    MAX(CASE WHEN cycle_index = 0 THEN cycle_volume_kg END) AS cycle_0,
    MAX(CASE WHEN cycle_index = 1 THEN cycle_volume_kg END) AS cycle_1,
    MAX(CASE WHEN cycle_index = 2 THEN cycle_volume_kg END) AS cycle_2,
    COUNT(DISTINCT cycle_index) AS cycles_available
  FROM cycles
  GROUP BY crop_name
)
SELECT
  crop_name,
  cycles_available,
  COALESCE(cycle_0, 0) AS most_recent_cycle_kg,
  CASE
    WHEN cycles_available >= 2 THEN
      ROUND(
        (
          3 * COALESCE(cycle_0, 0) +
          2 * COALESCE(cycle_1, 0) +
          1 * COALESCE(cycle_2, cycle_1, 0)
        ) / 6.0
      , 1)
    ELSE NULL
  END AS forecast_next_cycle_kg,
  CASE
    WHEN cycles_available < 2 THEN 'insufficient_data'
    WHEN COALESCE(cycle_0, 0) = 0 THEN 'insufficient_data'
    WHEN (
      (
        3 * COALESCE(cycle_0, 0) + 2 * COALESCE(cycle_1, 0) + 1 * COALESCE(cycle_2, cycle_1, 0)
      ) / 6.0
    ) > COALESCE(cycle_0, 0) * 1.10 THEN 'trending_up'
    WHEN (
      (
        3 * COALESCE(cycle_0, 0) + 2 * COALESCE(cycle_1, 0) + 1 * COALESCE(cycle_2, cycle_1, 0)
      ) / 6.0
    ) < COALESCE(cycle_0, 0) * 0.90 THEN 'trending_down'
    ELSE 'stable'
  END AS trend
FROM pivoted;

-- Note: views inherit RLS from underlying tables (harvest_records),
-- but since this is cooperative-wide aggregate data with no farmer_id
-- exposed, it's safe to expose to all authenticated users (farmers
-- benefit from seeing cooperative-wide planting trends, not just
-- their own data, since the recommendation is inherently collective).

GRANT SELECT ON public.crop_planting_forecast TO authenticated;
GRANT SELECT ON public.crop_cycle_volumes TO authenticated;
