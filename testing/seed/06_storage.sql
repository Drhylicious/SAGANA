-- Storage buckets and policies rebuilt from the repo scripts (LOCAL test DB). Errors are tolerated.

-- ===== supabase_schema_fixes.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 3: Storage bucket policies
-- Run these after creating the buckets manually in the Supabase dashboard
-- (Storage → New bucket → name → Public ON)
-- Buckets needed: profile_photos, crop_images, listing_photos
-- ─────────────────────────────────────────────────────────────────────────────

-- PROFILE PHOTOS bucket policies
-- Allows authenticated users to upload to their own folder
-- and anyone to read (public bucket)

INSERT INTO storage.buckets (id, name, public)
VALUES ('profile_photos', 'profile_photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;
INSERT INTO storage.buckets (id, name, public)
VALUES ('crop_images', 'crop_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;
INSERT INTO storage.buckets (id, name, public)
VALUES ('listing_photos', 'listing_photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;
-- ── Profile photos policies ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "Profile photos public read"   ON storage.objects;
DROP POLICY IF EXISTS "Profile photos owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Profile photos owner delete"  ON storage.objects;
CREATE POLICY "Profile photos public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'profile_photos');
CREATE POLICY "Profile photos owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Profile photos owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Profile photos owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
-- ── Crop images policies ──────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Crop images public read"   ON storage.objects;
DROP POLICY IF EXISTS "Crop images owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Crop images owner delete"  ON storage.objects;
CREATE POLICY "Crop images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'crop_images');
CREATE POLICY "Crop images owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'crop_images'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Crop images owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'crop_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Crop images owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'crop_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
-- ── Listing photos policies ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "Listing photos public read"   ON storage.objects;
DROP POLICY IF EXISTS "Listing photos owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Listing photos owner delete"  ON storage.objects;
CREATE POLICY "Listing photos public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'listing_photos');
CREATE POLICY "Listing photos owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'listing_photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Listing photos owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'listing_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Listing photos owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'listing_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ===== supabase_schema_profile_storage.sql
-- ============================================================
-- SAGANA — Farmer Profile Screen: Storage Setup Only
-- Covers: Farmer Profile Screen (profile photo upload)
--
-- NO TABLE CHANGES REQUIRED.
-- All fields used by this screen already exist:
--   - user_information.profile_photo_url, full_name, phone_number, sitio
--   - farmer_profiles.member_id, farm_name, farm_location,
--     land_area_hectares, years_farming, capital_shares,
--     member_since, is_verified
--   - farmer_crops.crop_name (queried for "Primary Crops" display)
--
-- Only a new Storage bucket is needed for profile photo uploads.
-- ============================================================

-- Create in Supabase Dashboard → Storage, or via SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('profile_photos', 'profile_photos', true)
ON CONFLICT DO NOTHING;

-- ===== supabase_schema_inventory_images_feature.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Storage bucket + RLS policies
-- Mirrors profile_photos / crop_images / listing_photos exactly
-- (supabase_schema_fixes.sql) — public read, owner-folder (uploader's own
-- auth.uid()) write. Program images use the same bucket under a
-- program_images/ path prefix rather than a second bucket, since the
-- policies are identical and a prefix is enough to keep the two image
-- kinds from colliding.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public)
VALUES ('cooperative_inventory_images', 'cooperative_inventory_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;
DROP POLICY IF EXISTS "Inventory images public read"   ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner update"  ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner delete"  ON storage.objects;
CREATE POLICY "Inventory images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'cooperative_inventory_images');
CREATE POLICY "Inventory images owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'cooperative_inventory_images'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Inventory images owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'cooperative_inventory_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Inventory images owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'cooperative_inventory_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ===== supabase_schema_registration_08_farmer_read_and_storage_gate.sql
-- ════════════════════════════════════════════════════════════
-- 2. Storage uploads
--    (If your SQL editor role may not create policies on storage.objects, the
--    block prints a notice instead of failing; the same three policies can
--    then be added under Dashboard > Storage > Policies.)
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  DROP POLICY IF EXISTS "approved farmers only: product photo uploads (insert)" ON storage.objects;
  DROP POLICY IF EXISTS "approved farmers only: product photo uploads (update)" ON storage.objects;
  DROP POLICY IF EXISTS "approved farmers only: product photo uploads (delete)" ON storage.objects;

  CREATE POLICY "approved farmers only: product photo uploads (insert)"
    ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    );

  CREATE POLICY "approved farmers only: product photo uploads (update)"
    ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    )
    WITH CHECK (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    );

  CREATE POLICY "approved farmers only: product photo uploads (delete)"
    ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
    USING (
      bucket_id NOT IN ('crop_images', 'listing_photos', 'cooperative_inventory_images')
      OR NOT public.is_unapproved_applicant()
    );
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Not allowed to create policies on storage.objects from this role. Add the three restrictive policies in Dashboard > Storage > Policies instead (see the header of this file).';
END;
$$;

-- ===== supabase_schema_officer_permissions_14_inventory_photo_permissions.sql
DROP POLICY IF EXISTS "Inventory images owner upload" ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner update" ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner delete" ON storage.objects;
DROP POLICY IF EXISTS "Inventory images staff upload" ON storage.objects;
DROP POLICY IF EXISTS "Inventory images staff update" ON storage.objects;
DROP POLICY IF EXISTS "Inventory images staff delete" ON storage.objects;
CREATE POLICY "Inventory images staff upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'cooperative_inventory_images'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = (auth.uid())::text
    AND public.can_manage_inventory_photos()
  );
CREATE POLICY "Inventory images staff update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'cooperative_inventory_images' AND public.can_manage_inventory_photos())
  WITH CHECK (bucket_id = 'cooperative_inventory_images' AND public.can_manage_inventory_photos());
CREATE POLICY "Inventory images staff delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'cooperative_inventory_images' AND public.can_manage_inventory_photos());

-- ===== supabase_schema_officer_permissions_15_photo_bucket_limits.sql
-- ============================================================
-- SAGANA — Officer permissions, script 15 (OPTIONAL): PHOTO FOLDER SIZE LIMIT
--
-- You asked me to VERIFY the file-size limits and image-only restrictions of the
-- four photo folders (buckets) without disrupting uploads. This file does the
-- verification, and then an optional, cautious fix for the size limit only.
--
-- STEP 1 — VERIFY (read-only; run this first and send me the result):
--
--   SELECT id, public, file_size_limit, allowed_mime_types
--   FROM storage.buckets
--   WHERE id IN ('profile_photos','crop_images','listing_photos','cooperative_inventory_images')
--   ORDER BY id;
--
--   file_size_limit NULL  = no limit of its own (only the project-wide upload limit)
--   allowed_mime_types NULL = any file type is accepted
--
-- STEP 2 — WHAT I RECOMMEND, AND WHY THE TYPE RESTRICTION IS NOT IN THIS FILE
--   Size: every photo is taken or picked with the app's image compression
--   (quality 80), so a normal photo is well under 5 MB. A 10 MB cap per file is a
--   safe ceiling that no real photo reaches. The statement below only FILLS A
--   MISSING LIMIT: a bucket that already has a limit is left exactly as it is.
--
--   Image-only: NOT applied here. Reason: the app's upload does not set a file type;
--   the storage library works it out from the file's extension, which comes from the
--   picked file's name. A photo with an unusual extension (or none) is sent as a
--   generic file type and an image-only rule would REJECT it. That would break
--   uploads that work today. To enforce image-only safely we first need the app to
--   send the type explicitly, plus a test of a camera photo and a gallery photo of
--   each kind. Until then, leave allowed_mime_types as it is.
--   (If STEP 1 shows that a bucket already has allowed_mime_types, tell me: that rule
--   is already in force and I will check it against the extensions the app produces.)
--
-- RUN STEP 3 ONLY IF STEP 1 SHOWED file_size_limit = NULL for some bucket.
-- Not applied automatically. Re-runnable (it never changes a limit that is set).
-- To undo: UPDATE storage.buckets SET file_size_limit = NULL WHERE id = '<bucket>';
-- ============================================================

-- STEP 3 — fill a missing size limit (10 MB = 10485760 bytes)
UPDATE storage.buckets
SET file_size_limit = 10485760
WHERE id IN ('profile_photos', 'crop_images', 'listing_photos', 'cooperative_inventory_images')
  AND file_size_limit IS NULL;

-- ===== supabase_schema_officer_remove_old_account.sql
-- Expect this account's own profile ids (for example id columns that equal the
-- user id) and nothing that points at other people's records.


-- ─── BLOCK 1D — FILES IN STORAGE OWNED BY THIS UID (read-only). ────────────
SELECT o.bucket_id, o.name, o.created_at
FROM storage.objects o
WHERE to_jsonb(o) ->> 'owner_id' = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
   OR to_jsonb(o) ->> 'owner'    = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
   OR o.name LIKE '32dbca85-d93e-49bc-a468-06d08e70a6ed%';

-- ===== supabase_schema_program_rework_p3_outcome_workflow.sql
-- ════════════════════════════════════════════════════════════
-- 2. Private evidence bucket
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('program_evidence', 'program_evidence', FALSE, 10485760,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;
-- Files live in the uploader's own folder:  <user id>/<file>
DROP POLICY IF EXISTS "Program evidence upload" ON storage.objects;
CREATE POLICY "Program evidence upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'program_evidence'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = (auth.uid())::text
    AND (public.is_staff()
         OR EXISTS (SELECT 1 FROM public.user_roles ur
                    WHERE ur.user_id = auth.uid() AND ur.role = 'farmer' AND ur.status = 'active'))
  );
-- Staff read every photo; a Farmer reads only their own folder.
DROP POLICY IF EXISTS "Program evidence read" ON storage.objects;
CREATE POLICY "Program evidence read"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'program_evidence'
    AND (public.is_staff() OR (storage.foldername(name))[1] = (auth.uid())::text)
  );
-- A person may remove a photo they uploaded and have not submitted yet.
DROP POLICY IF EXISTS "Program evidence delete own" ON storage.objects;
CREATE POLICY "Program evidence delete own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'program_evidence'
    AND (storage.foldername(name))[1] = (auth.uid())::text
    AND NOT EXISTS (SELECT 1 FROM public.program_outcome_photos p WHERE p.storage_path = name)
  );
-- Every photo path must be in the caller's own folder and really exist.
CREATE OR REPLACE FUNCTION public._outcome_check_paths(p_paths TEXT[], p_min INT, p_max INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_path TEXT;
  v_n    INT := COALESCE(array_length(p_paths, 1), 0);
BEGIN
  IF v_n < p_min THEN
    RAISE EXCEPTION 'Add at least % photo(s).', p_min;
  END IF;
  IF v_n > p_max THEN
    RAISE EXCEPTION 'You can add at most % photos.', p_max;
  END IF;
  IF v_n <> (SELECT count(DISTINCT x) FROM unnest(p_paths) x) THEN
    RAISE EXCEPTION 'The same photo was added twice.';
  END IF;
  FOREACH v_path IN ARRAY COALESCE(p_paths, ARRAY[]::TEXT[]) LOOP
    IF v_path NOT LIKE (auth.uid()::TEXT || '/%') THEN
      RAISE EXCEPTION 'A photo does not belong to you.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects o
                   WHERE o.bucket_id = 'program_evidence' AND o.name = v_path) THEN
      RAISE EXCEPTION 'A photo was not uploaded. Please add it again.';
    END IF;
  END LOOP;
END;
$$;

-- ===== supabase_schema_program_rework_preflight.sql
-- ─── 8. Storage: buckets and who may write to them (photo evidence design) ───
SELECT id, name, public, file_size_limit, allowed_mime_types FROM storage.buckets ORDER BY name;
