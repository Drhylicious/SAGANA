-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_phase3_broadcast_delivery.sql
-- Phase 3 — Broadcast delivery.
--
-- Before: the device resolved recipients, wrote the notices, then wrote the
-- log. A failed log write left notices behind with an error on screen, so a
-- retry sent duplicates. A send with no matching recipients reported success.
-- The immediate path and the scheduled path also resolved recipients with
-- separate code.
--
-- After:
--   • resolve_broadcast_recipients() is the one place that decides recipients.
--     Immediate sends and scheduled sends both use it.
--   • send_broadcast() resolves, inserts the notices and writes the log in one
--     transaction. The recipient count is the number of rows actually inserted.
--     It raises NO_RECIPIENTS when nothing matches, so nothing is reported as sent.
--   • client_key makes a repeated send with the same key a no-op: the earlier
--     result is returned and nothing is sent again.
--   • process_scheduled_broadcasts() uses the same resolver and records the
--     rows actually inserted.
--
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Idempotency key on the log ─────────────────────────────────────────────
ALTER TABLE public.broadcast_logs
  ADD COLUMN IF NOT EXISTS client_key UUID;

-- A plain unique index (NULLs are distinct), so INSERT … ON CONFLICT (client_key)
-- works for the scheduled-send upsert as well.
CREATE UNIQUE INDEX IF NOT EXISTS broadcast_logs_client_key_key
  ON public.broadcast_logs (client_key);

-- ─── Single source of truth for recipients ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_broadcast_recipients(
  p_recipient_type TEXT,
  p_recipient_filter TEXT
)
RETURNS UUID[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ids UUID[];
BEGIN
  CASE p_recipient_type
    WHEN 'all_members' THEN
      SELECT array_agg(user_id) INTO v_ids
      FROM user_roles WHERE role = 'farmer' AND status = 'active';
    WHEN 'all_buyers' THEN
      SELECT array_agg(user_id) INTO v_ids
      FROM user_roles WHERE role = 'buyer' AND status = 'active';
    WHEN 'outstanding_loans' THEN
      SELECT array_agg(DISTINCT farmer_id) INTO v_ids
      FROM farmer_loans WHERE status != 'paid';
    WHEN 'specific_crop' THEN
      IF p_recipient_filter IS NOT NULL AND p_recipient_filter <> '' THEN
        SELECT array_agg(DISTINCT farmer_id) INTO v_ids
        FROM farmer_crops WHERE crop_name ILIKE p_recipient_filter;
      END IF;
    WHEN 'specific_farmer' THEN
      IF p_recipient_filter IS NOT NULL AND p_recipient_filter <> '' THEN
        v_ids := ARRAY[p_recipient_filter::UUID];
      END IF;
    WHEN 'specific_buyer' THEN
      IF p_recipient_filter IS NOT NULL AND p_recipient_filter <> '' THEN
        v_ids := ARRAY[p_recipient_filter::UUID];
      END IF;
    ELSE
      v_ids := NULL;
  END CASE;

  RETURN v_ids;
END;
$$;

-- Only the functions below call the resolver; the client never does.
REVOKE EXECUTE ON FUNCTION public.resolve_broadcast_recipients(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ─── Immediate send: resolve, insert, log — one transaction ─────────────────
CREATE OR REPLACE FUNCTION public.send_broadcast(
  p_title TEXT,
  p_body TEXT,
  p_category TEXT,
  p_recipient_type TEXT,
  p_recipient_filter TEXT,
  p_client_key UUID
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing INTEGER;
  v_ids UUID[];
  v_count INTEGER;
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can send broadcasts';
  END IF;

  -- Resend with the same key: report the earlier send, do not send again.
  IF p_client_key IS NOT NULL THEN
    SELECT recipient_count INTO v_existing
    FROM broadcast_logs WHERE client_key = p_client_key;
    IF FOUND THEN
      RETURN v_existing;
    END IF;
  END IF;

  v_ids := public.resolve_broadcast_recipients(p_recipient_type, p_recipient_filter);
  IF v_ids IS NULL OR array_length(v_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'NO_RECIPIENTS';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT uid, 'system', p_title, p_body, FALSE, NOW()
  FROM unnest(v_ids) AS uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO broadcast_logs (
    title, body, category, recipient_type, recipient_filter,
    recipient_count, scheduled_at, sent_at, created_by, created_at, client_key
  )
  VALUES (
    p_title, p_body, p_category, p_recipient_type, p_recipient_filter,
    v_count, NULL, NOW(), auth.uid(), NOW(), p_client_key
  );

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_broadcast(TEXT, TEXT, TEXT, TEXT, TEXT, UUID) TO authenticated;

-- ─── Scheduled sends: same resolver, count what was actually inserted ───────
CREATE OR REPLACE FUNCTION public.process_scheduled_broadcasts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row             RECORD;
  v_recipient_ids   UUID[];
  v_inserted        INT;
  v_processed_count INT := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM broadcast_logs
    WHERE sent_at IS NULL
      AND scheduled_at IS NOT NULL
      AND scheduled_at <= NOW()
    FOR UPDATE SKIP LOCKED
  LOOP
    v_recipient_ids := public.resolve_broadcast_recipients(
      v_row.recipient_type,
      v_row.recipient_filter
    );
    v_inserted := 0;

    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
      SELECT uid, 'system', v_row.title, v_row.body, FALSE, NOW()
      FROM unnest(v_recipient_ids) AS uid;
      GET DIAGNOSTICS v_inserted = ROW_COUNT;
    END IF;

    UPDATE broadcast_logs
    SET sent_at = NOW(),
        recipient_count = v_inserted
    WHERE id = v_row.id;

    v_processed_count := v_processed_count + 1;
  END LOOP;

  RETURN v_processed_count;
END;
$$;

-- Verification (run in Supabase after applying):
--   select count(*) from pg_indexes where tablename = 'broadcast_logs' and indexname = 'broadcast_logs_client_key_key';
--   Expected: 1.
