-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_phase4_balik_notice.sql
-- Phase 4 — Balik-Tangkilik payout notice, moved into the database.
--
-- The farmer is notified when a distribution is recorded: the first time the
-- payout date is set for a farmer's year with a non-zero total. The amount is
-- the sum of the stored actuals (balik-tangkilik + interest + patronage), which
-- is the same figure the app previously sent from the device.
--
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_notify_balik_distributed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  IF NEW.actual_payout_date IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.actual_payout_date IS NULL) THEN
    v_total := COALESCE(NEW.actual_balik_tangkilik, 0)
             + COALESCE(NEW.actual_interest_on_capital, 0)
             + COALESCE(NEW.actual_purchase_patronage, 0);

    IF v_total > 0 THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        NEW.farmer_id,
        'capital',
        'Balik-Tangkilik Payout Recorded',
        'Your Balik-Tangkilik payout for ' || NEW.year || ' of ₱'
          || TO_CHAR(v_total, 'FM999999990.00') || ' has been recorded.',
        FALSE,
        NOW(),
        '/farmer/profile/contribution'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_balik_distributed ON member_contributions;
CREATE TRIGGER trg_notify_balik_distributed
  AFTER INSERT OR UPDATE OF actual_payout_date ON member_contributions
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_balik_distributed();
