-- ─────────────────────────────────────────────────────────────────────────────
-- batch1_01_broadcast_preview.sql
-- Batch 1 (1.1) of the approved implementation plan.
--
-- The broadcast screen used to count recipients with its own copy of the
-- recipient rules on the device. This adds a server-side count, so the number
-- shown before sending is the number the server actually delivers to.
--
-- resolve_broadcast_recipients is not callable by the app (Phase 3 revoked it
-- from authenticated). This wrapper is the only new way in: it checks that the
-- caller is an admin or officer, then returns the count.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.preview_broadcast_recipients(
  p_recipient_type text,
  p_recipient_filter text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ids UUID[];
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can preview broadcast recipients';
  END IF;

  v_ids := public.resolve_broadcast_recipients(p_recipient_type, p_recipient_filter);
  RETURN COALESCE(array_length(v_ids, 1), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.preview_broadcast_recipients(text, text) TO authenticated;

-- ─── Verification (run after applying) ───────────────────────────────────────
--   select public.preview_broadcast_recipients('all_members', null);
--   -- as an admin: a number equal to the active farmer count
--   select count(*) from user_roles where role = 'farmer' and status = 'active';
