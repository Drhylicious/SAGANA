-- ============================================================
-- SAGANA — Cooperative Program Management
-- Tracks SP3's official programs: Crop, Peanut, Production,
-- Livestock. Each program can have enrolled members and
-- associated activities that appear on the calendar.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.cooperative_programs (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_name TEXT        NOT NULL UNIQUE,
  program_type TEXT        NOT NULL DEFAULT 'other',
  description  TEXT,
  season_year  INT         NOT NULL DEFAULT EXTRACT(YEAR FROM NOW())::INT,
  status       TEXT        NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'completed', 'suspended')),
  budget       DECIMAL(12,2),
  created_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_cooperative_programs_updated_at
  BEFORE UPDATE ON public.cooperative_programs
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.cooperative_programs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cooperative_programs: admin manages all"
  ON public.cooperative_programs FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "cooperative_programs: members read active"
  ON public.cooperative_programs FOR SELECT
  USING (status = 'active' AND auth.role() = 'authenticated');

-- Member enrollment in programs
CREATE TABLE IF NOT EXISTS public.program_members (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_id  UUID        NOT NULL REFERENCES public.cooperative_programs(id) ON DELETE CASCADE,
  farmer_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status      TEXT        NOT NULL DEFAULT 'active'
              CHECK (status IN ('active', 'withdrawn', 'completed')),
  notes       TEXT,
  UNIQUE (program_id, farmer_id)
);

ALTER TABLE public.program_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "program_members: admin manages all"
  ON public.program_members FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "program_members: farmer reads own"
  ON public.program_members FOR SELECT
  USING (auth.uid() = farmer_id);

-- Program activities — these feed into the calendar
CREATE TABLE IF NOT EXISTS public.program_activities (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_id   UUID        NOT NULL REFERENCES public.cooperative_programs(id) ON DELETE CASCADE,
  title        TEXT        NOT NULL,
  description  TEXT,
  activity_date DATE       NOT NULL,
  location     TEXT,
  created_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.program_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "program_activities: admin manages all"
  ON public.program_activities FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "program_activities: members read all"
  ON public.program_activities FOR SELECT
  USING (auth.role() = 'authenticated');

-- Seed the 4 core SP3 programs
INSERT INTO public.cooperative_programs (program_name, program_type, description, season_year) VALUES
  ('Crop Program',       'crop',       'Rice and corn production support program for SP3 farmer-members.', EXTRACT(YEAR FROM NOW())::INT),
  ('Peanut Program',     'peanut',     'Peanut cultivation and cooperative buyback program.', EXTRACT(YEAR FROM NOW())::INT),
  ('Production Program', 'production', 'General agricultural production support and technology training.', EXTRACT(YEAR FROM NOW())::INT),
  ('Livestock Program',  'livestock',  'Hog and poultry dispersal and livelihood program.', EXTRACT(YEAR FROM NOW())::INT)
ON CONFLICT (program_name) DO NOTHING;
