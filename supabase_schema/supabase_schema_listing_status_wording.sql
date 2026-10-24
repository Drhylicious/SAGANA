-- ============================================================
-- SAGANA — Listing wording: Pending Approval / Available / Sold Out / Disapproved
--
-- The Marketplace screens now say, for a Farmer's listing:
--     pending_review  -> Pending Approval
--     approved        -> Available      (Sold Out once nothing is left)
--     sold            -> Sold Out
--     rejected        -> Disapproved
-- The stored status values do NOT change. This script only brings the words in
-- the notifications written by the database in line with the screens.
--
-- HOW. Same approach as the Order wording and the Manager wording scripts: the
-- notices are written by several database functions, so rather than rewrite
-- live function bodies, a BEFORE INSERT trigger rewords each listing notice as
-- it is stored. Only exact phrases are touched, so a Manager's typed reason is
-- never altered. Notices already sent are reworded once (stored text only;
-- nothing is deleted).
--
--   title 'Listing Rejected'                          -> 'Listing Disapproved'
--   body  ' listing was rejected.'                    -> ' listing was disapproved.'
--   body  ' listing is now live on the Marketplace.'  -> ' listing is now available on the Marketplace.'
--   body  ' was submitted for review.'                -> ' was submitted for approval.'   (staff notice)
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. The listing notice texts that exist today (informational). Anything that
--    still says "rejected", "live" or "review" after this script is a wording
--    this script does not know about:
--    SELECT type, title, left(body, 90) AS body_start, count(*)
--    FROM public.notifications
--    WHERE type IN ('listing', 'listing_submitted')
--    GROUP BY 1, 2, 3 ORDER BY 1, 2, 4 DESC;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public.notifications_listing_wording()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type IN ('listing', 'listing_submitted') THEN
    NEW.title := CASE NEW.title
      WHEN 'Listing Rejected' THEN 'Listing Disapproved'
      ELSE NEW.title
    END;
    -- First occurrence only, so any reason typed after it is left alone.
    NEW.body := regexp_replace(NEW.body, ' listing was rejected\.', ' listing was disapproved.');
    NEW.body := regexp_replace(NEW.body, ' listing is now live on the Marketplace\.', ' listing is now available on the Marketplace.');
    NEW.body := regexp_replace(NEW.body, ' was submitted for review\.', ' was submitted for approval.');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_listing_wording ON public.notifications;
CREATE TRIGGER trg_notifications_listing_wording
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_listing_wording();

-- Re-word the listing notices already sent.
UPDATE public.notifications
SET title = CASE title
      WHEN 'Listing Rejected' THEN 'Listing Disapproved'
      ELSE title
    END,
    body = regexp_replace(
             regexp_replace(
               regexp_replace(body, ' listing was rejected\.', ' listing was disapproved.'),
               ' listing is now live on the Marketplace\.', ' listing is now available on the Marketplace.'),
             ' was submitted for review\.', ' was submitted for approval.')
WHERE type IN ('listing', 'listing_submitted')
  AND (title = 'Listing Rejected'
       OR body ~ ' listing was rejected\.'
       OR body ~ ' listing is now live on the Marketplace\.'
       OR body ~ ' was submitted for review\.');

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Trigger exists (expect 1 row):
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_notifications_listing_wording' AND NOT tgisinternal;
-- 2. Nothing left with the old wording (expect 0):
--    SELECT count(*) FROM public.notifications
--    WHERE type IN ('listing', 'listing_submitted')
--      AND (title = 'Listing Rejected'
--           OR body ~ ' listing was rejected\.'
--           OR body ~ ' listing is now live on the Marketplace\.'
--           OR body ~ ' was submitted for review\.');
-- 3. Trigger behaviour (inside a transaction that is rolled back; expect
--    'Listing Disapproved' / '... was disapproved. Reason: price too high'):
--    BEGIN;
--      INSERT INTO public.notifications (user_id, type, title, body, is_read, created_at)
--      SELECT user_id, 'listing', 'Listing Rejected',
--             'Your Palay listing was rejected. Reason: price too high', TRUE, NOW()
--      FROM public.user_roles LIMIT 1
--      RETURNING title, body;
--    ROLLBACK;
-- ─────────────────────────────────────────────────────────────────────────
