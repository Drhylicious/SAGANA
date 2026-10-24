-- ─────────────────────────────────────────────────────────────────────────────
-- batch0_04_drop_unused_place_order.sql
-- Batch 0 (0N) of the approved implementation plan.
--
-- Removes the two-argument place_order(uuid, numeric) overload. The app calls
-- place_order with named fulfillment parameters, which only the fulfillment
-- overload matches. A search of the SQL files finds no function that calls the
-- two-argument version, so dropping it changes nothing the app uses.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.place_order(uuid, numeric);

-- ─── Verification (run after applying) ───────────────────────────────────────
--   select pg_get_function_identity_arguments(oid)
--   from pg_proc where proname = 'place_order';
--   -- expect only the fulfillment overload (more than two arguments)
