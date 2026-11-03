-- ============================================================
-- SAGANA — Officer permissions, script 14: INVENTORY PHOTO PERMISSIONS (Storage)
--
-- APPROVED by you. The cooperative's inventory photos (and program images, which
-- use the same folder) follow the Dashboard permission:
--   * Manager ............................ can upload, replace and delete
--   * Officer with Dashboard = Manage .... can upload, replace and delete
--   * Officer with Dashboard = View Only .. can only VIEW
--   * Farmer / Buyer ..................... can only view (they never upload here)
--
-- WHY IT IS NEEDED: the gate (staff_permission_gate) only sees database requests,
-- not file uploads, so Storage needs its own rule. Today the rule is "anyone signed
-- in may upload into their own folder", which let a View Only Officer, or even a
-- Buyer, add files to the inventory photo folder.
--
-- ONLY THE BUCKET cooperative_inventory_images IS TOUCHED. Profile, crop and
-- listing photo rules are not changed. Viewing stays public (the app and the
-- marketplace show these photos by link). The existing restriction that keeps
-- unapproved applicants out of the product photo buckets stays.
--
-- HOW UPLOADS WORK, SO NOTHING BREAKS (checked in the code)
--   The app uploads to '<your user id>/item_<time>.jpg' (or
--   '<your user id>/program_images/<time>.jpg'), with upsert, and never deletes the
--   old file. So:
--     * INSERT must still be inside your OWN folder (kept, same as today);
--     * UPDATE and DELETE are allowed on any file in this bucket for someone who
--       can manage the inventory, so a Manage Officer can replace or remove a photo
--       the Manager uploaded (and the reverse). View Only cannot.
--
-- Replaces these three policies on storage.objects (names from the live database):
--   "Inventory images owner upload / update / delete"
-- Keeps: "Inventory images public read" and the restrictive
--   "approved farmers only: product photo uploads (insert / update / delete)".
--
-- REQUIRES scripts 01 (staff_access_level). Not applied automatically.
-- Run in the Supabase SQL editor. Re-runnable.
--
-- ROLLBACK (puts back the old owner-folder rules):
--   DROP POLICY "Inventory images staff upload" ON storage.objects;
--   DROP POLICY "Inventory images staff update" ON storage.objects;
--   DROP POLICY "Inventory images staff delete" ON storage.objects;
--   CREATE POLICY "Inventory images owner upload" ON storage.objects FOR INSERT TO public
--     WITH CHECK (bucket_id = 'cooperative_inventory_images' AND auth.uid() IS NOT NULL
--                 AND (storage.foldername(name))[1] = (auth.uid())::text);
--   CREATE POLICY "Inventory images owner update" ON storage.objects FOR UPDATE TO public
--     USING (bucket_id = 'cooperative_inventory_images' AND (storage.foldername(name))[1] = (auth.uid())::text);
--   CREATE POLICY "Inventory images owner delete" ON storage.objects FOR DELETE TO public
--     USING (bucket_id = 'cooperative_inventory_images' AND (storage.foldername(name))[1] = (auth.uid())::text);
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.staff_access_level(text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'staff_access_level() is missing. Run officer_permissions_01 first.';
  END IF;
END $$;

BEGIN;

-- True for the Manager, and for an Officer whose Dashboard access is Manage.
CREATE OR REPLACE FUNCTION public.can_manage_inventory_photos()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.staff_access_level('dashboard') = 'manage', false);
$$;

REVOKE ALL ON FUNCTION public.can_manage_inventory_photos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_inventory_photos() TO authenticated;

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

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT policyname, cmd, roles FROM pg_policies
--   WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname ILIKE 'Inventory images%'
--   ORDER BY policyname;
--   -- expect: public read (SELECT), staff upload / update / delete
-- In the app: Manager and an Officer with Dashboard = Manage add or change an
-- inventory item photo and a program image; an Officer with Dashboard = View Only
-- cannot reach the screens that do it (they show "view-only access"); photos are
-- still visible to everyone; crop, listing and profile photos upload as before.
-- ─────────────────────────────────────────────────────────────────────────
