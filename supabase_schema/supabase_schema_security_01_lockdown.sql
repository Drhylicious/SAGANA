-- Security lockdown found by the software-testing round (API tests, 2026-11-18).
-- Re-runnable. Run in the Supabase SQL Editor.
--
-- 1. Internal helper / scheduled-job functions were executable by anyone, including signed-out
--    callers (Supabase grants new functions to anon + authenticated by default):
--      notify_user                      - anyone could put a notification in ANY user's inbox
--      _apply_batch_reservation         - anyone could lower ANY farmer's available stock
--      _release_batch_reservation       - anyone could raise ANY farmer's available stock
--      run_daily_loan_maintenance,
--      notify_overdue_farmers,
--      notify_upcoming_loan_payments,
--      process_scheduled_broadcasts,
--      reactivate_expired_suspensions,
--      notify_bod_meeting_upcoming      - scheduled jobs; their staff check is skipped when signed out
--      suggest_next_username            - signed-out username lookup, not used by the app
--    The app never calls these (only SECURITY DEFINER functions and the database scheduler do), so
--    execution is limited to the database owner and the service role.
-- 2. Any signed-in user (a Buyer, another Farmer) could read EVERY farmer's available inventory
--    batches. They may now read only the batches that back an approved Marketplace listing.

DO $$
DECLARE s text;
BEGIN
  FOREACH s IN ARRAY ARRAY[
    'public.notify_user(uuid,text,text,text,text,text)',
    'public._apply_batch_reservation(uuid,numeric)',
    'public._release_batch_reservation(uuid,numeric)',
    'public.run_daily_loan_maintenance()',
    'public.notify_overdue_farmers()',
    'public.notify_upcoming_loan_payments()',
    'public.process_scheduled_broadcasts()',
    'public.reactivate_expired_suspensions()',
    'public.notify_bod_meeting_upcoming(date)',
    'public.suggest_next_username(text)'
  ] LOOP
    IF to_regprocedure(s) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', s);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', s);
    END IF;
  END LOOP;
END $$;

DROP POLICY IF EXISTS "inventory_batches: buyers read available" ON public.inventory_batches;
CREATE POLICY "inventory_batches: buyers read available"
ON public.inventory_batches FOR SELECT
USING (
  status = 'available'
  AND auth.role() = 'authenticated'
  AND EXISTS (
    SELECT 1 FROM public.marketplace_listings ml
    WHERE ml.inventory_batch_id = inventory_batches.id AND ml.status = 'approved'
  )
);

-- 3. The four public photo buckets accepted ANY file type: an HTML or script file uploaded there
--    could be opened from a Supabase link (hosting/phishing abuse). Types a browser would RENDER
--    (HTML, SVG, scripts, PDF ...) are now refused. Images are accepted, and so is a generic
--    binary type, because the app picks the type from the file name and a photo whose name has an
--    unusual or missing extension is sent as a generic binary (it is only downloaded, never shown
--    as a page). A strict images-only list could therefore refuse real photos.
UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif',
                               'image/heic', 'image/heif', 'application/octet-stream']
WHERE id IN ('crop_images', 'listing_photos', 'profile_photos', 'cooperative_inventory_images');

NOTIFY pgrst, 'reload schema';
