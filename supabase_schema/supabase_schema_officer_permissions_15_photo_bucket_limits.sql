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

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT id, file_size_limit, allowed_mime_types FROM storage.buckets
--   WHERE id IN ('profile_photos','crop_images','listing_photos','cooperative_inventory_images') ORDER BY id;
-- Then upload one camera photo and one gallery photo in each of the four places
-- (profile, crop, listing, inventory): all must still work.
-- ─────────────────────────────────────────────────────────────────────────
