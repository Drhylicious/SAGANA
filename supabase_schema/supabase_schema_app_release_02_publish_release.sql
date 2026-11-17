-- ============================================================
-- supabase_schema_app_release_02_publish_release.sql
--
-- IN-APP UPDATE CHECK (2 of 2): RUN THIS ONCE FOR EVERY NEW APK RELEASE.
-- Run script 01 first (once, ever).
--
-- WHEN TO RUN IT
--   AFTER the APK is uploaded to the GitHub Release and the landing page shows the new
--   version. Running it is what makes installed apps start offering the update.
--
-- HOW
--   1. Edit the five values in the "EDIT THESE" block below.
--   2. Run the whole script in the Supabase SQL editor.
--   3. Read the result row: it must show the build you just published.
--
-- THE RULES
--   build_number          must match the number after "+" in pubspec.yaml for that APK,
--                         and must be HIGHER than every earlier release. (1.0.1+3 -> 3)
--   min_supported_build   1 for a normal release (update is optional). Set it equal to
--                         build_number ONLY when older apps cannot work any more (for
--                         example the release needs database changes they cannot use):
--                         every app older than it is then blocked until it updates.
--   notes                 one or two short lines. Leave notes_tl NULL to show English.
--
-- To WITHDRAW a bad release (apps fall back to the previous active one):
--   UPDATE public.app_releases SET is_active = false WHERE build_number = <number>;
-- ============================================================

-- ─── EDIT THESE ──────────────────────────────────────────────
INSERT INTO public.app_releases
  (version_name, build_number, min_supported_build, notes_en, notes_tl)
VALUES
  ('1.0.0',                                   -- version_name  (shown to people)
   2,                                          -- build_number  (number after "+")
   1,                                          -- min_supported_build (1 = optional update)
   'First official SAGANA release.',           -- notes_en
   'Unang opisyal na bersyon ng SAGANA.')      -- notes_tl (or NULL)
ON CONFLICT (build_number) DO UPDATE
  SET version_name        = EXCLUDED.version_name,
      min_supported_build = EXCLUDED.min_supported_build,
      notes_en            = EXCLUDED.notes_en,
      notes_tl            = EXCLUDED.notes_tl,
      is_active           = true;
-- ─────────────────────────────────────────────────────────────

-- RESULT: what installed apps will now be told.
SELECT public.latest_app_release() AS latest_release;
