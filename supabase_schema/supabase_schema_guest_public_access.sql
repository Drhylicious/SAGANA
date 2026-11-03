-- ============================================================
-- SAGANA — Phase 7: Guest (signed-out) read-only public access
--
-- WHAT THIS DOES
--   Guest Mode ("Explore as Buyer" / "Explore as Farmer") runs with NO Supabase
--   session, i.e. as the `anon` role. Instead of opening any table to `anon`
--   (which would weaken the private-data policies), this script adds five
--   read-only SECURITY DEFINER functions. Each one returns ONLY what a signed-in
--   Buyer is already allowed to see, and nothing more:
--
--     public_market_types()              Buyer-visible market types (labels).
--     public_marketplace_listings(...)   Approved listings in Buyer-visible
--                                        markets, for browse and for details.
--     public_listed_crop_names()         Crop names that have such a listing.
--     public_latest_prices()             Latest price per crop, Buyer-visible
--                                        markets only.
--     public_price_trend(...)            Price history for one crop, Buyer-visible
--                                        markets only.
--
-- WHAT IS DELIBERATELY NOT EXPOSED
--   * Cooperative Market (non Buyer-visible) listings and prices.
--   * Farmer identity: no farmer_id, name or contact on any returned row.
--   * Inventory batch ids, orders, buyers, profiles, loans, notifications,
--     recorded_by, admin notes, or any other table.
--   * No table or view is granted to `anon`. No existing policy is changed.
--
-- SAFE TO RE-RUN: CREATE OR REPLACE + idempotent grants. Nothing is written.
-- Run once, in the Supabase SQL editor. Then run
-- supabase_schema_guest_public_access_verify.sql (read-only) to check it.
-- ============================================================

-- ─── 1. Buyer-visible market types ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.public_market_types()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'code',               mt.code,
        'name',               mt.name,
        'name_tl',            mt.name_tl,
        'buyer_visible',      mt.buyer_visible,
        'manager_sets_price', mt.manager_sets_price,
        'sort_order',         mt.sort_order,
        'is_active',          mt.is_active
      )
      ORDER BY mt.sort_order, mt.name
    ),
    '[]'::jsonb
  )
  FROM public.market_types mt
  WHERE mt.buyer_visible AND mt.is_active;
$$;

-- ─── 2. Approved listings (browse list, or one listing for its details) ─────
-- p_listing_id NULL  -> a page of listings, newest first (max 200 per call).
-- p_listing_id set   -> just that listing (if it is approved and public).
CREATE OR REPLACE FUNCTION public.public_marketplace_listings(
  p_limit      integer DEFAULT NULL,
  p_offset     integer DEFAULT 0,
  p_listing_id uuid    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC), '[]'::jsonb)
  FROM (
    SELECT
      ml.created_at,
      jsonb_build_object(
        'id',                  ml.id,
        'crop_name',           ml.crop_name,
        'crop_id',             ml.crop_id,
        'variety',             ml.variety,
        'volume_kg',           ml.volume_kg,
        'remaining_kg',        ml.remaining_kg,
        'price_per_kg',        ml.price_per_kg,
        'unit',                ml.unit,
        'photo_url',           ml.photo_url,
        'description',         ml.description,
        'created_at',          ml.created_at,
        'market_type',         ml.crop_type,
        'category',            cm.category,
        'canonical_crop_name', CASE WHEN ml.crop_id IS NOT NULL THEN cm.crop_name END,
        'available_kg',        ib.available_kg,
        'batch_number',        ib.batch_number,
        'harvest_date',        hr.harvest_date,
        'sold_kg',             COALESCE(s.sold_kg, 0)
      ) AS j
    FROM public.marketplace_listings ml
    LEFT JOIN LATERAL (
      SELECT c.category, c.crop_name
      FROM public.crop_master c
      WHERE c.id = ml.crop_id OR lower(c.crop_name) = lower(ml.crop_name)
      ORDER BY (c.id = ml.crop_id) DESC
      LIMIT 1
    ) cm ON TRUE
    LEFT JOIN public.inventory_batches ib ON ib.id = ml.inventory_batch_id
    LEFT JOIN public.harvest_records   hr ON hr.id = ib.harvest_record_id
    LEFT JOIN public.marketplace_listing_units_sold s ON s.listing_id = ml.id
    WHERE ml.status = 'approved'
      AND (p_listing_id IS NULL OR ml.id = p_listing_id)
      AND (
        ml.crop_type IS NULL
        OR EXISTS (
          SELECT 1 FROM public.market_types mt
          WHERE mt.code = ml.crop_type AND mt.buyer_visible
        )
      )
    ORDER BY ml.created_at DESC
    LIMIT LEAST(COALESCE(p_limit, 200), 200)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  ) x;
$$;

-- ─── 3. Crop names that currently have a public listing ─────────────────────
CREATE OR REPLACE FUNCTION public.public_listed_crop_names()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(DISTINCT lower(ml.crop_name)), '[]'::jsonb)
  FROM public.marketplace_listings ml
  WHERE ml.status = 'approved'
    AND (
      ml.crop_type IS NULL
      OR EXISTS (
        SELECT 1 FROM public.market_types mt
        WHERE mt.code = ml.crop_type AND mt.buyer_visible
      )
    );
$$;

-- ─── 4. Latest price per crop, Buyer-visible markets only ───────────────────
CREATE OR REPLACE FUNCTION public.public_latest_prices()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(x.j), '[]'::jsonb)
  FROM (
    SELECT DISTINCT ON (pr.crop_id, pr.price_type)
      jsonb_build_object(
        'id',             pr.id,
        'crop_id',        pr.crop_id,
        'crop_name',      pr.crop_name,
        'price',          pr.price,
        'previous_price', pr.previous_price,
        'unit',           pr.unit,
        'price_type',     pr.price_type,
        'recorded_at',    pr.recorded_at,
        'source',         pr.source,
        'crop_master',    jsonb_build_object(
                            'image_url',   cm.image_url,
                            'category',    cm.category,
                            'description', cm.description
                          )
      ) AS j
    FROM public.price_records pr
    JOIN public.market_types mt
      ON mt.code = pr.price_type AND mt.buyer_visible
    LEFT JOIN public.crop_master cm ON cm.id = pr.crop_id
    WHERE pr.crop_id IS NOT NULL
    ORDER BY pr.crop_id, pr.price_type, pr.recorded_at DESC
  ) x;
$$;

-- ─── 5. Price history for one crop, Buyer-visible markets only ──────────────
-- Same rule as the signed-in app: the last p_days days; if there is nothing
-- that recent, the latest 10 records instead. Oldest first.
CREATE OR REPLACE FUNCTION public.public_price_trend(
  p_crop_id    uuid,
  p_price_type text    DEFAULT NULL,
  p_days       integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days   integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(t.j ORDER BY t.recorded_at ASC), '[]'::jsonb)
    INTO v_result
  FROM (
    SELECT pr.recorded_at,
           jsonb_build_object(
             'id',             pr.id,
             'crop_id',        pr.crop_id,
             'crop_name',      pr.crop_name,
             'price',          pr.price,
             'previous_price', pr.previous_price,
             'unit',           pr.unit,
             'price_type',     pr.price_type,
             'recorded_at',    pr.recorded_at,
             'source',         pr.source
           ) AS j
    FROM public.price_records pr
    JOIN public.market_types mt
      ON mt.code = pr.price_type AND mt.buyer_visible
    WHERE pr.crop_id = p_crop_id
      AND (p_price_type IS NULL OR pr.price_type = p_price_type)
      AND pr.recorded_at >= now() - make_interval(days => v_days)
  ) t;

  IF jsonb_array_length(v_result) > 0 THEN
    RETURN v_result;
  END IF;

  SELECT COALESCE(jsonb_agg(t.j ORDER BY t.recorded_at ASC), '[]'::jsonb)
    INTO v_result
  FROM (
    SELECT pr.recorded_at,
           jsonb_build_object(
             'id',             pr.id,
             'crop_id',        pr.crop_id,
             'crop_name',      pr.crop_name,
             'price',          pr.price,
             'previous_price', pr.previous_price,
             'unit',           pr.unit,
             'price_type',     pr.price_type,
             'recorded_at',    pr.recorded_at,
             'source',         pr.source
           ) AS j
    FROM public.price_records pr
    JOIN public.market_types mt
      ON mt.code = pr.price_type AND mt.buyer_visible
    WHERE pr.crop_id = p_crop_id
      AND (p_price_type IS NULL OR pr.price_type = p_price_type)
    ORDER BY pr.recorded_at DESC
    LIMIT 10
  ) t;

  RETURN v_result;
END;
$$;

-- ─── 6. Grants: execute only; nothing else is opened to anon ────────────────
REVOKE ALL ON FUNCTION public.public_market_types()                              FROM PUBLIC;
REVOKE ALL ON FUNCTION public.public_marketplace_listings(integer, integer, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.public_listed_crop_names()                         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.public_latest_prices()                             FROM PUBLIC;
REVOKE ALL ON FUNCTION public.public_price_trend(uuid, text, integer)            FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.public_market_types()                              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_marketplace_listings(integer, integer, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_listed_crop_names()                         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_latest_prices()                             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_price_trend(uuid, text, integer)            TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
