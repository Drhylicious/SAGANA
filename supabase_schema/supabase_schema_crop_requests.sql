-- ============================================================
-- SAGANA — Crop Taxonomy Governance
-- Links farmer_crops to the official crop_master catalog and
-- adds the Request New Crop workflow.
-- ============================================================

ALTER TABLE public.farmer_crops
  ADD COLUMN IF NOT EXISTS crop_master_id UUID REFERENCES public.crop_master(id);

CREATE TABLE IF NOT EXISTS public.crop_requests (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_name   TEXT        NOT NULL,
  category         TEXT,
  status           TEXT        NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes      TEXT,
  reviewed_by      UUID        REFERENCES auth.users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_crop_requests_status
  ON public.crop_requests (status, created_at DESC);

ALTER TABLE public.crop_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "crop_requests: farmer creates and reads own"
  ON public.crop_requests FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "crop_requests: farmer inserts own"
  ON public.crop_requests FOR INSERT
  WITH CHECK (auth.uid() = farmer_id);

CREATE POLICY "crop_requests: admin manages all"
  ON public.crop_requests FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.admin_profiles ap WHERE ap.user_id = auth.uid())
  );