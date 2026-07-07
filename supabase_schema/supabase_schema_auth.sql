-- ============================================================
-- SAGANA — Authentication Schema
-- Covers: Splash Screen, Login Screen, Registration Screen
--
-- Tables created:
--   1. user_roles         — role + status per user
--   2. user_information   — shared profile fields from Register screen
--   3. farmer_profiles    — farmer placeholder row (populated later via Profile screens)
--   4. buyer_profiles     — buyer placeholder row
--   5. admin_profiles     — manually created only, never via Registration
--
-- Registration screen fields mapped:
--   Full Name        → user_information.full_name
--   Email            → auth.users.email (Supabase handles)
--   Phone Number     → user_information.phone_number
--   Sitio / Purok    → user_information.sitio
--   Password         → auth.users (Supabase handles, never stored in our tables)
--   Confirm Password → client-side validation only, never stored
--   Role selection   → user_roles.role
--
-- Login screen fields mapped:
--   Email            → auth.users.email
--   Password         → auth.users (Supabase Auth)
--   Role selector    → validated against user_roles.role after login
--
-- Splash screen:
--   Session check    → Supabase auth.currentSession
--   Role routing     → user_roles.role (with Hive cache fallback)
-- ============================================================

-- ─── Extensions ──────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── Updated At Trigger ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE 1: user_roles
-- One row per user. Created immediately on registration.
-- role:   'farmer' | 'buyer' — set from role selector in Register screen
--         'admin'  — set manually via SQL, never through the app
-- status: 'pending'  — farmer default (requires SP3 admin verification)
--         'active'   — buyer default (self-activates on email verification)
--         'suspended'— set by admin if needed
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_roles (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role        TEXT        NOT NULL CHECK (role IN ('admin', 'farmer', 'buyer')),
  status      TEXT        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('active', 'pending', 'suspended')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

CREATE TRIGGER trg_user_roles_updated_at
  BEFORE UPDATE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- User reads own role (used by Splash + Login routing)
CREATE POLICY "user_roles: user reads own"
  ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id);

-- Admin reads all roles (used by Farmer Management screen)
CREATE POLICY "user_roles: admin reads all"
  ON public.user_roles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'admin'
    )
  );

-- Admin updates status (activate/suspend farmers)
CREATE POLICY "user_roles: admin updates status"
  ON public.user_roles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'admin'
    )
  );

-- Allow insert during registration (before session is fully established)
CREATE POLICY "user_roles: insert on registration"
  ON public.user_roles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE 2: user_information
-- Stores every field from the Registration screen's personal info section.
-- full_name    ← Full Name field
-- phone_number ← Phone Number field (09XXXXXXXXX format)
-- sitio        ← Sitio/Purok dropdown (one of 7 Payanas puroks)
-- profile_photo_url ← not on Registration screen; added later via Profile Edit
-- notification_prefs ← not on Registration screen; defaults applied here
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_information (
  id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name           TEXT        NOT NULL,
  phone_number        TEXT,
  profile_photo_url   TEXT,
  -- One of: 'Purok 1-Centro 1', 'Purok 2-Centro 2', 'Purok 3-Centro 3',
  --         'Purok 4-Kailugan', 'Purok 5-Binubungan', 'Purok 6-Tigas',
  --         'Purok 7-Manggahan'
  sitio               TEXT,
  notification_prefs  JSONB       NOT NULL DEFAULT '{
    "listing_updates": true,
    "order_updates": true,
    "loan_reminders": true,
    "price_updates": true,
    "sync_alerts": true,
    "announcements": true
  }'::jsonb,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

CREATE TRIGGER trg_user_information_updated_at
  BEFORE UPDATE ON public.user_information
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.user_information ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_information: user manages own"
  ON public.user_information FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_information: admin reads all"
  ON public.user_information FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'admin'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE 3: farmer_profiles
-- Created as a placeholder row on registration.
-- Registration screen does NOT collect farm details — those come later
-- via the Farmer Profile → Edit Farm Details screen.
-- member_id   — assigned by admin after SP3 membership verification
-- is_verified — set to TRUE by admin; controls whether farmer can list produce
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.farmer_profiles (
  id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  member_id           TEXT        UNIQUE,
  farm_name           TEXT,
  farm_location       TEXT,
  land_area_hectares  DECIMAL(8,2),
  years_farming       INTEGER,
  capital_shares      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  member_since        DATE,
  is_verified         BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

CREATE TRIGGER trg_farmer_profiles_updated_at
  BEFORE UPDATE ON public.farmer_profiles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.farmer_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farmer_profiles: farmer manages own"
  ON public.farmer_profiles FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "farmer_profiles: admin manages all"
  ON public.farmer_profiles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'admin'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE 4: buyer_profiles
-- Minimal placeholder row created on registration.
-- Buyers are self-service — no admin verification required.
-- Additional fields may be added as buyer screens are built.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.buyer_profiles (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

CREATE TRIGGER trg_buyer_profiles_updated_at
  BEFORE UPDATE ON public.buyer_profiles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.buyer_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "buyer_profiles: buyer manages own"
  ON public.buyer_profiles FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "buyer_profiles: admin reads all"
  ON public.buyer_profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'admin'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE 5: admin_profiles
-- NEVER created through the Registration screen.
-- Admin accounts are created manually by Supabase dashboard + SQL only.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_profiles (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id  TEXT        UNIQUE,
  position     TEXT,
  department   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

CREATE TRIGGER trg_admin_profiles_updated_at
  BEFORE UPDATE ON public.admin_profiles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.admin_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_profiles: admin manages own"
  ON public.admin_profiles FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);