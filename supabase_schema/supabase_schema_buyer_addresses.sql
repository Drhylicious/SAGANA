-- Checkout + My Addresses — Phase 1 (additive only)
--
-- Storage for the new "My Addresses" feature. Keyed by auth.users.id
-- regardless of whether the caller's active role is buyer or farmer —
-- farmer-as-buyer shares this exact marketplace/checkout flow, same
-- convention as orders.buyer_id already accepting farmer callers
-- (supabase_schema_place_order_farmer_purchasing.sql). No RPC layer:
-- an address row only ever touches its own owner, so plain RLS-scoped
-- .from() calls are sufficient (same shape as buyer_profile_activity).

CREATE TABLE IF NOT EXISTS public.buyer_addresses (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label            TEXT NOT NULL,
  recipient_name   TEXT,
  contact_number   TEXT NOT NULL,
  address_line     TEXT NOT NULL,
  latitude         DOUBLE PRECISION,
  longitude        DOUBLE PRECISION,
  notes            TEXT,
  is_default       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS buyer_addresses_user_id_idx
  ON public.buyer_addresses (user_id, created_at DESC);

ALTER TABLE public.buyer_addresses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own addresses"
  ON public.buyer_addresses
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
