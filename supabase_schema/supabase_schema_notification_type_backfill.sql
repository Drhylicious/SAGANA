-- ============================================================
-- SAGANA — Backfill historical notification types (Item 1 follow-up)
-- supabase_schema_notification_type_fixes.sql corrected the type
-- value used by 6 functions going forward, but CREATE OR REPLACE
-- FUNCTION doesn't touch rows already in the table. This is a
-- one-time backfill for rows inserted before that migration ran,
-- matched by their exact, unique title string (each of the 4
-- affected titles is only ever produced by one function).
-- Only rows still carrying the old type = 'system' are touched —
-- safe to run more than once, and safe to run even if some rows
-- have already been corrected some other way.
-- ============================================================

UPDATE notifications
SET type = 'listing'
WHERE type = 'system' AND title = 'Listing Rejected';

UPDATE notifications
SET type = 'crop_request'
WHERE type = 'system' AND title IN ('Crop Request Approved', 'Crop Request Declined');

UPDATE notifications
SET type = 'cooperative_offer'
WHERE type = 'system'
  AND title IN ('Cooperative Purchase Confirmed', 'Cooperative Purchase Offer Declined');

UPDATE notifications
SET type = 'program'
WHERE type = 'system' AND title = 'Program Return Settled';

NOTIFY pgrst, 'reload schema';