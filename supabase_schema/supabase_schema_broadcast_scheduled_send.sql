-- ============================================================
-- SAGANA — Phase 2: Real scheduled-send for Broadcast Announcements
-- ============================================================
-- Previously, the "Schedule" toggle in Compose didn't defer anything —
-- sendBroadcast() always inserted notifications immediately, only
-- back/post-dating the stored created_at/sent_at to the picked time,
-- while the UI told the admin "Scheduled for X". This makes scheduling
-- real: a scheduled send now queues a broadcast_logs row with
-- sent_at = NULL, and process_scheduled_broadcasts() (run periodically,
-- see supabase/functions/process-scheduled-broadcasts) resolves
-- recipients and inserts notifications only once scheduled_at has
-- actually passed.
--
-- Mirrors the existing daily-loan-maintenance pattern exactly (see
-- supabase_schema_loan_overdue_automation.sql): pg_cron attempted
-- best-effort (Pro plan+), external scheduler (GitHub Actions → Edge
-- Function) as the Free-tier-compatible path, GRANT EXECUTE TO
-- authenticated (same risk profile — calling it early only processes
-- rows already past their scheduled_at; nothing can be forced to send
-- before its time).
-- ============================================================

-- ─── 1. sent_at becomes nullable — NULL means "queued, not sent yet" ───────

ALTER TABLE public.broadcast_logs ALTER COLUMN sent_at DROP NOT NULL;
ALTER TABLE public.broadcast_logs ALTER COLUMN sent_at DROP DEFAULT;

-- ─── 2. Recipient resolution + send, run for every row past its time ──────

CREATE OR REPLACE FUNCTION public.process_scheduled_broadcasts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row             RECORD;
  v_recipient_ids   UUID[];
  v_processed_count INT := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM broadcast_logs
    WHERE sent_at IS NULL
      AND scheduled_at IS NOT NULL
      AND scheduled_at <= NOW()
    FOR UPDATE SKIP LOCKED
  LOOP
    v_recipient_ids := NULL;

    CASE v_row.recipient_type
      WHEN 'all_members' THEN
        SELECT array_agg(user_id) INTO v_recipient_ids
        FROM user_roles WHERE role = 'farmer' AND status = 'active';
      WHEN 'all_buyers' THEN
        SELECT array_agg(user_id) INTO v_recipient_ids
        FROM user_roles WHERE role = 'buyer' AND status = 'active';
      WHEN 'outstanding_loans' THEN
        SELECT array_agg(DISTINCT farmer_id) INTO v_recipient_ids
        FROM farmer_loans WHERE status != 'paid';
      WHEN 'specific_crop' THEN
        IF v_row.recipient_filter IS NOT NULL THEN
          SELECT array_agg(DISTINCT farmer_id) INTO v_recipient_ids
          FROM farmer_crops WHERE crop_name ILIKE v_row.recipient_filter;
        END IF;
      WHEN 'specific_farmer' THEN
        IF v_row.recipient_filter IS NOT NULL THEN
          v_recipient_ids := ARRAY[v_row.recipient_filter::UUID];
        END IF;
      WHEN 'specific_buyer' THEN
        IF v_row.recipient_filter IS NOT NULL THEN
          v_recipient_ids := ARRAY[v_row.recipient_filter::UUID];
        END IF;
      ELSE
        v_recipient_ids := NULL;
    END CASE;

    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
      SELECT uid, 'system', v_row.title, v_row.body, FALSE, NOW()
      FROM unnest(v_recipient_ids) AS uid;
    END IF;

    UPDATE broadcast_logs
    SET sent_at = NOW(),
        recipient_count = COALESCE(array_length(v_recipient_ids, 1), 0)
    WHERE id = v_row.id;

    v_processed_count := v_processed_count + 1;
  END LOOP;

  RETURN v_processed_count;
END;
$$;

GRANT EXECUTE ON FUNCTION process_scheduled_broadcasts TO authenticated;

-- ─── 3. pg_cron scheduling (Pro plan and above only) ───────────────────────
-- Best-effort, same as run_daily_loan_maintenance's DO block — no-ops with
-- a NOTICE on Free tier where pg_cron can't be enabled. Runs every 5
-- minutes; on Free tier, use the process-scheduled-broadcasts Edge
-- Function + an external scheduler (GitHub Actions workflow included)
-- instead.

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  PERFORM cron.schedule(
    'process-scheduled-broadcasts',
    '*/5 * * * *',
    $cron$ SELECT process_scheduled_broadcasts(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron scheduling skipped (likely unavailable on this plan): %', SQLERRM;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) sent_at is nullable now:
--    SELECT is_nullable FROM information_schema.columns
--    WHERE table_name = 'broadcast_logs' AND column_name = 'sent_at';  -- expect 'YES'
--
-- 2) Manually queue a due test row and confirm processing works:
--    INSERT INTO broadcast_logs (title, body, category, recipient_type, scheduled_at, sent_at)
--    VALUES ('Test', 'Test body', 'general', 'all_buyers', NOW() - INTERVAL '1 minute', NULL)
--    RETURNING id;
--    SELECT process_scheduled_broadcasts();  -- expect >= 1
--    SELECT sent_at, recipient_count FROM broadcast_logs WHERE title = 'Test';  -- sent_at populated
--    (clean up the test row afterward)
--
-- 3) In-app: enable Schedule, pick a near-future time, send. Confirm the
--    broadcast does NOT appear in recipients' notifications until after
--    that time (once the scheduler / Edge Function has run).
-- ============================================================
