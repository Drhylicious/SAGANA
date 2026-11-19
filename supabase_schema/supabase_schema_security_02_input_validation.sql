-- Found by the software-testing round (API tests, 2026-11-19). Re-runnable. Run in the Supabase SQL Editor.
--
-- 1. A Farmer could save a market-linking request for 0 kg, a negative number of kg, or more kg than
-- the batch holds, by calling the API directly (the app's own screen never allows it, but the
-- database accepted it). The request table's row-level policy only checked who owns the row.
-- Staff screens would then show "requested -4 kg". The database now refuses these on insert.
-- Staff and the service role are not affected.

CREATE OR REPLACE FUNCTION public.guard_market_linking_request_volume()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available numeric;
BEGIN
  IF public.is_staff() OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.requested_volume_kg IS NOT NULL THEN
    IF NEW.requested_volume_kg <= 0 THEN
      RAISE EXCEPTION 'The quantity to sell must be more than zero.';
    END IF;
    IF NEW.inventory_batch_id IS NOT NULL THEN
      SELECT available_kg INTO v_available FROM public.inventory_batches WHERE id = NEW.inventory_batch_id;
      IF v_available IS NOT NULL AND NEW.requested_volume_kg > v_available THEN
        RAISE EXCEPTION 'The quantity to sell is more than the batch has available (% kg).', v_available;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_request_volume ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_request_volume
  BEFORE INSERT ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.guard_market_linking_request_volume();

REVOKE ALL ON FUNCTION public.guard_market_linking_request_volume() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Same round, two more small gaps found by the API tests:
--
-- 2. A signed-in user could rewrite the TITLE, TEXT, TYPE or SCREEN LINK of their own notification
--    through the API. The app only ever changes "read / unread". Only that column can now be
--    changed by an ordinary user (staff and the database's own functions are not affected).
-- 3. A broadcast with a blank title or a blank message was accepted and delivered as an empty
--    notification. The database now refuses it.

CREATE OR REPLACE FUNCTION public.guard_notification_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND NOT public.is_staff() THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.type IS DISTINCT FROM OLD.type
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.body IS DISTINCT FROM OLD.body
       OR NEW.route_on_tap IS DISTINCT FROM OLD.route_on_tap
       OR NEW.route_extra IS DISTINCT FROM OLD.route_extra
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Only the read status of a notification can be changed.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_update_guard ON public.notifications;
CREATE TRIGGER trg_notification_update_guard
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.guard_notification_update();

CREATE OR REPLACE FUNCTION public.guard_broadcast_not_blank()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF btrim(COALESCE(NEW.title, '')) = '' THEN
    RAISE EXCEPTION 'A broadcast needs a title.';
  END IF;
  IF btrim(COALESCE(NEW.body, '')) = '' THEN
    RAISE EXCEPTION 'A broadcast needs a message.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_broadcast_not_blank ON public.broadcast_logs;
CREATE TRIGGER trg_broadcast_not_blank
  BEFORE INSERT OR UPDATE OF title, body ON public.broadcast_logs
  FOR EACH ROW EXECUTE FUNCTION public.guard_broadcast_not_blank();

NOTIFY pgrst, 'reload schema';
