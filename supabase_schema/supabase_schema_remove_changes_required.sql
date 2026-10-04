-- ============================================================
-- SAGANA — Remove the "Changes Required" listing workflow
--
-- Per explicit product direction: there's no real information on a
-- pending listing an admin would need the farmer to edit in place — a
-- listing is either approved or rejected. Removes the whole
-- changes_required status, the request_listing_changes RPC that set it,
-- and resubmit_listing_with_reservation (which only ever existed to let a
-- farmer resubmit a changes_required listing — no other caller exists).
--
-- Run this AFTER deploying the app build that no longer references
-- changes_required (already done in this pass) so nothing in the client
-- can set this status again before the constraint is tightened.
-- ============================================================

-- ─── 1. Migrate any existing changes_required rows first ──────────────────
-- The CHECK constraint below will no longer allow 'changes_required', so
-- any row still in that status must move to a valid one first. Converts
-- each to 'rejected' — the closest real equivalent now that "needs an
-- edit in place" isn't a state the workflow supports — and properly
-- releases its batch reservation exactly the way reject_listing() does
-- (reject_listing() itself can't be reused here: it only accepts a
-- pending_review listing, not changes_required). Preserves any existing
-- admin_notes and appends a note explaining the change; notifies the
-- farmer so this doesn't happen silently. No-op if there are none.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id, inventory_batch_id, remaining_kg, admin_notes, farmer_id, crop_name
    FROM marketplace_listings
    WHERE status = 'changes_required'
    FOR UPDATE
  LOOP
    IF r.inventory_batch_id IS NOT NULL AND r.remaining_kg > 0 THEN
      PERFORM _release_batch_reservation(r.inventory_batch_id, r.remaining_kg);
    END IF;

    UPDATE marketplace_listings
    SET status = 'rejected',
        remaining_kg = 0,
        admin_notes = COALESCE(r.admin_notes, '') ||
          CASE WHEN r.admin_notes IS NOT NULL AND r.admin_notes <> '' THEN E'\n\n' ELSE '' END ||
          '[Migrated automatically — the Changes Required workflow was removed; this listing is now Rejected.]',
        updated_at = NOW()
    WHERE id = r.id;

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      r.farmer_id, 'listing', 'Listing Status Updated',
      'Your ' || r.crop_name || ' listing has been marked Rejected. You can create a new listing for this batch.',
      FALSE, NOW(), '/farmer/marketplace'
    );
  END LOOP;
END $$;

-- ─── 2. Tighten the status CHECK constraint ────────────────────────────────
ALTER TABLE public.marketplace_listings
  DROP CONSTRAINT IF EXISTS marketplace_listings_status_check;

ALTER TABLE public.marketplace_listings
  ADD CONSTRAINT marketplace_listings_status_check
  CHECK (status IN ('pending_review', 'approved', 'withdrawn', 'rejected', 'sold'));

-- ─── 3. Drop the two RPCs that only ever served this workflow ─────────────
-- request_listing_changes: admin action that set changes_required.
-- resubmit_listing_with_reservation: farmer action that only accepted a
-- changes_required listing (guarded — see supabase_schema_rejected_listing_terminal.sql)
-- and has no other caller.
DROP FUNCTION IF EXISTS public.request_listing_changes(UUID, TEXT);
DROP FUNCTION IF EXISTS public.resubmit_listing_with_reservation(UUID, DECIMAL, DECIMAL, TEXT);

NOTIFY pgrst, 'reload schema';
