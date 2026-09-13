-- Warning 2.1: the farmer RLS policy on marketplace_listings was FOR ALL
-- (SELECT/INSERT/UPDATE/DELETE), letting a farmer's client issue a raw
-- write directly against their own listing row and bypass every
-- reservation-aware RPC (create_listing_with_reservation, withdraw_listing,
-- delete_listing, resubmit_listing_with_reservation). No current code path
-- does this — every write in listing_repository.dart already goes through
-- an RPC — so this closes the gap at the database level too, matching
-- the precedent already set for `orders` RLS
-- (supabase_schema_orders_farmer_update_removal.sql).
--
-- Narrowed to SELECT only: confirmed no repository ever does a raw
-- .insert() into this table either — creation is exclusively via the
-- SECURITY DEFINER create_listing_with_reservation RPC, which bypasses
-- RLS regardless of what this policy grants.

DROP POLICY IF EXISTS "marketplace_listings: farmer manages own" ON public.marketplace_listings;

CREATE POLICY "marketplace_listings: farmer reads own"
  ON public.marketplace_listings FOR SELECT
  USING (auth.uid() = farmer_id);
