-- ============================================================
-- supabase_schema_app_release_01_update_check.sql
--
-- IN-APP UPDATE CHECK (1 of 2). Run once in the Supabase SQL editor.
-- Then publish each new APK with supabase_schema_app_release_02_publish_release.sql.
--
-- WHAT THIS DOES
--   The app asks the server "what is the newest SAGANA build?" and compares that with
--   its own build number (the number after the "+" in pubspec.yaml, e.g. 1.0.0+2 ->
--   build 2). Builds are compared as whole numbers, never as version text.
--
--     installed build >= latest build              -> up to date, nothing shown
--     installed build <  latest build              -> OPTIONAL update (can say "Later")
--     installed build <  latest min_supported_build -> REQUIRED update (cannot be skipped)
--
--   "Required" is for a release that depends on database changes an older app cannot
--   handle. It is enforced by the app, not by the database: an old app that is not
--   updated is blocked on screen, but its requests are not rejected by the server.
--
-- WHO CAN SEE IT
--   Everyone, including signed-out users and guests (the check also runs on the login
--   screen). Only latest_app_release() is exposed; the table itself has no client
--   access. Rows are written by you in the SQL editor (script 02), nobody else.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_releases (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  version_name        text        NOT NULL,                 -- shown to people, e.g. 1.0.1
  build_number        integer     NOT NULL,                 -- the number after "+" in pubspec.yaml
  min_supported_build integer     NOT NULL DEFAULT 1,       -- apps older than this must update
  notes_en            text,                                 -- "What's new" (English)
  notes_tl            text,                                 -- "Ano'ng bago" (Filipino); falls back to English
  landing_url         text        NOT NULL DEFAULT 'https://sagana-landing.vercel.app/get',
  is_active           boolean     NOT NULL DEFAULT true,    -- false = withdrawn, ignored by the app
  published_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT app_releases_build_unique UNIQUE (build_number),
  CONSTRAINT app_releases_build_positive_chk CHECK (build_number > 0),
  CONSTRAINT app_releases_version_chk CHECK (btrim(version_name) <> ''),
  CONSTRAINT app_releases_min_build_chk
    CHECK (min_supported_build >= 1 AND min_supported_build <= build_number),
  CONSTRAINT app_releases_url_chk CHECK (landing_url ~ '^https://')
);

COMMENT ON TABLE public.app_releases IS
  'One row per published SAGANA APK. The app reads the newest active row through latest_app_release() to offer or require an update.';

-- No client may read or write the table directly. The SQL editor (service role) writes it.
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_releases FROM PUBLIC, anon, authenticated;

-- The one thing the app is allowed to ask for: the newest active release, or null.
CREATE OR REPLACE FUNCTION public.latest_app_release()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
           'version_name',        r.version_name,
           'build_number',        r.build_number,
           'min_supported_build', r.min_supported_build,
           'notes_en',            r.notes_en,
           'notes_tl',            r.notes_tl,
           'landing_url',         r.landing_url,
           'published_at',        r.published_at
         )
  FROM public.app_releases r
  WHERE r.is_active
  ORDER BY r.build_number DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.latest_app_release() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.latest_app_release() TO anon, authenticated;

COMMIT;

-- ============================================================
-- CHECK (read-only). Expect: table_exists = true, rls_on = true.
-- The latest_release row is empty until you run script 02 once.
-- ============================================================
SELECT
  to_regclass('public.app_releases') IS NOT NULL AS table_exists,
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.app_releases'::regclass) AS rls_on,
  public.latest_app_release() AS latest_release;
