-- ============================================================
-- SAGANA — Phase 0: Shared notification-creation helper (foundation)
-- ============================================================
-- Every notification-creating RPC currently hand-writes its own
-- `INSERT INTO notifications (...)`. This adds one shared helper,
-- notify_user(), that future RPCs (Phase 2 onward) can call instead of
-- repeating the insert. Zero behavior change to any existing RPC —
-- nothing is rewired to use it yet, except approve_crop_request below,
-- which is being edited in this same migration anyway to fix its type
-- inconsistency, so it adopts the helper at the same time.
--
-- Also fixes a confirmed inconsistency: approve_crop_request notifies
-- the farmer with type='system' while reject_crop_request (its sibling,
-- same workflow) correctly uses type='crop_request'. 'system' has no
-- matching NotificationFilter chip in the farmer UI, so an approved
-- crop request was only ever visible under "All" — not under the
-- "Crop Requests" filter reject_crop_request's notifications show up
-- under. Standardizing both to 'crop_request'.
--
-- notify_user() is SECURITY DEFINER and its EXECUTE grant is revoked
-- from PUBLIC/anon/authenticated — it's only reachable from inside
-- other SECURITY DEFINER functions (which run as the function owner,
-- not the calling client), the same way every other notification-
-- creating RPC already works. It is NOT itself exposed as a callable
-- PostgREST RPC endpoint for arbitrary clients.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id UUID,
  p_type    TEXT,
  p_title   TEXT,
  p_body    TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (p_user_id, p_type, p_title, p_body, FALSE, NOW());
END;
$$;

REVOKE ALL ON FUNCTION public.notify_user(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_user(UUID, TEXT, TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.notify_user(UUID, TEXT, TEXT, TEXT) FROM authenticated;

-- ─── approve_crop_request → 'crop_request' (was 'system'), via notify_user ─

CREATE OR REPLACE FUNCTION public.approve_crop_request(p_request_id uuid, p_admin_notes text DEFAULT NULL::text, p_crop_type text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_request RECORD;
  v_crop_master_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  IF p_crop_type IS NOT NULL AND p_crop_type NOT IN ('sp3_cooperative', 'da_amad_market', 'open_market') THEN
    RAISE EXCEPTION 'Invalid crop_type: %', p_crop_type;
  END IF;

  SELECT id INTO v_crop_master_id
  FROM crop_master
  WHERE lower(crop_name) = lower(v_request.requested_name)
  LIMIT 1;

  IF v_crop_master_id IS NULL THEN
    INSERT INTO crop_master (crop_name, category, crop_type, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      COALESCE(p_crop_type, v_request.crop_type, 'open_market'),
      TRUE,
      (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM crop_master)
    )
    RETURNING id INTO v_crop_master_id;
  END IF;

  UPDATE crop_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  IF v_request.farmer_crop_id IS NOT NULL THEN
    UPDATE farmer_crops SET crop_master_id = v_crop_master_id WHERE id = v_request.farmer_crop_id;
  END IF;

  PERFORM notify_user(
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.'
  );

  RETURN v_crop_master_id;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) notify_user exists and is not directly callable by clients:
--    SELECT has_function_privilege('anon', 'notify_user(uuid,text,text,text)', 'EXECUTE');          -- expect false
--    SELECT has_function_privilege('authenticated', 'notify_user(uuid,text,text,text)', 'EXECUTE');  -- expect false
--
-- 2) approve_crop_request now uses 'crop_request' (not 'system'):
--    SELECT prosrc ILIKE '%''crop_request''%' AND prosrc NOT ILIKE '%''system''%'
--    FROM pg_proc WHERE proname = 'approve_crop_request';                                            -- expect true
--
-- 3) Approve a real pending crop request in-app and confirm the farmer's
--    notification now shows up under the "Crop Requests" filter, not just
--    "All".
-- ============================================================
