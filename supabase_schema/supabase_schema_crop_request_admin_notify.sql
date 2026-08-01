-- ============================================================
-- SAGANA — Admin Awareness of Crop Requests
-- Extends notifications.type to match what admin_notifications_screen.dart
-- already expects (it was written for a richer vocabulary than the
-- original CHECK constraint allowed), and adds a trigger that notifies
-- every admin the moment a farmer submits a crop request — entirely
-- server-side, no farmer-side code involved.
-- ============================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'order', 'listing', 'loan', 'price', 'sync', 'system',
    'listing_submitted', 'loan_overdue', 'member_pending',
    'member_registered', 'member_updated',
    'low_stock', 'stock_depleted',
    'crop_request'
  ));

CREATE OR REPLACE FUNCTION notify_admins_of_crop_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'crop_request',
    'New Crop Request',
    NEW.requested_name || ' was requested by a farmer and needs review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_crop_request ON crop_requests;
CREATE TRIGGER trg_notify_admins_crop_request
  AFTER INSERT ON crop_requests
  FOR EACH ROW
  EXECUTE FUNCTION notify_admins_of_crop_request();

NOTIFY pgrst, 'reload schema';
