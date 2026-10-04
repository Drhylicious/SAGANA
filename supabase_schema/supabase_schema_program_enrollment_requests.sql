-- ============================================================
-- SAGANA — Program Self-Service Enrollment Requests
-- (Farmer Profile tab investigation — Cooperative Benefits / Programs
-- full workflow)
--
-- Problem: enrolling a farmer into a cooperative_programs record
-- (program_members) was entirely Admin-initiated — ProgramRepository.
-- enrollFarmer() has no farmer-facing counterpart, and program_members'
-- RLS has no farmer INSERT policy at all. A farmer could not discover or
-- request enrollment in a program themselves, for either purpose
-- (distribution or sales).
--
-- Fix: mirror the existing, working DA-AMAD Market Linking pattern
-- (supabase_schema_da_amad_enrollment.sql) exactly — a separate request
-- table with its own pending/approved/rejected lifecycle, submitted via a
-- SECURITY DEFINER RPC (auth.uid()-derived, never a client-supplied
-- farmer id) and reviewed via a second SECURITY DEFINER RPC. Approval is
-- the one point where a real program_members row is created — reusing
-- the exact reactivate-or-insert shape ProgramRepository.enrollFarmer()
-- already uses, so a farmer who was previously withdrawn and re-requests
-- doesn't collide with program_members' UNIQUE(program_id, farmer_id).
--
-- A separate table (rather than widening program_members.status's
-- existing CHECK to add 'pending'/'rejected') was chosen deliberately:
-- program_repository.dart already has multiple `.eq('status', 'active')`
-- call sites relying on program_members' three-value status meaning
-- exactly what it means today; adding new values there would require
-- auditing all of them. This table leaves that column untouched.
--
-- Unlike DA-AMAD's (silent) precedent, this migration also adds an
-- admin-notify-on-submit trigger, mirroring the newer, better UX already
-- established for Market Linking's farmer-request flow
-- (supabase_schema_market_linking_farmer_requests.sql) — a pending
-- request isn't only visible once an admin happens to open the review
-- screen.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.program_enrollment_requests (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  program_id    UUID        NOT NULL REFERENCES public.cooperative_programs(id) ON DELETE CASCADE,
  status        TEXT        NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes   TEXT,
  reviewed_by   UUID        REFERENCES auth.users(id),
  submitted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_program_enrollment_requests_farmer
  ON public.program_enrollment_requests (farmer_id);
CREATE INDEX IF NOT EXISTS idx_program_enrollment_requests_program
  ON public.program_enrollment_requests (program_id);

ALTER TABLE public.program_enrollment_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "program_enrollment_requests: farmer reads own"
  ON public.program_enrollment_requests FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "program_enrollment_requests: admin manages all"
  ON public.program_enrollment_requests FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- No farmer INSERT/UPDATE policy — submission and review both go through
-- the SECURITY DEFINER RPCs below.

-- ─── Submit (farmer) ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_program_enrollment_request(p_program_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_program_status TEXT;
  v_new_id UUID;
BEGIN
  SELECT status INTO v_program_status
  FROM cooperative_programs WHERE id = p_program_id;

  IF v_program_status IS NULL THEN
    RAISE EXCEPTION 'Program not found';
  END IF;
  IF v_program_status <> 'active' THEN
    RAISE EXCEPTION 'This program is not currently accepting enrollments';
  END IF;

  IF EXISTS (
    SELECT 1 FROM program_enrollment_requests
    WHERE farmer_id = v_farmer_id AND program_id = p_program_id
      AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'You already have a pending or approved request for this program';
  END IF;

  IF EXISTS (
    SELECT 1 FROM program_members
    WHERE farmer_id = v_farmer_id AND program_id = p_program_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are already enrolled in this program';
  END IF;

  INSERT INTO program_enrollment_requests (farmer_id, program_id, status, submitted_at)
  VALUES (v_farmer_id, p_program_id, 'pending', NOW())
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_program_enrollment_request(UUID) TO authenticated;

-- ─── Respond (admin) ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.respond_to_program_enrollment_request(
  p_request_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID;
  v_program_id UUID;
  v_status TEXT;
  v_program_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review enrollment requests';
  END IF;

  SELECT farmer_id, program_id, status INTO v_farmer_id, v_program_id, v_status
  FROM program_enrollment_requests WHERE id = p_request_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
  END IF;

  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = v_program_id;

  UPDATE program_enrollment_requests
  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_request_id;

  IF p_approve THEN
    -- Reactivate-or-insert, identical shape to ProgramRepository.
    -- enrollFarmer() (program_members has UNIQUE(program_id, farmer_id),
    -- and a farmer who was previously withdrawn already has a row here).
    IF EXISTS (
      SELECT 1 FROM program_members
      WHERE program_id = v_program_id AND farmer_id = v_farmer_id
    ) THEN
      UPDATE program_members
      SET status = 'active', enrolled_at = NOW()
      WHERE program_id = v_program_id AND farmer_id = v_farmer_id;
    ELSE
      INSERT INTO program_members (program_id, farmer_id)
      VALUES (v_program_id, v_farmer_id);
    END IF;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'program',
    CASE WHEN p_approve THEN 'Program Enrollment Approved' ELSE 'Program Enrollment Declined' END,
    CASE WHEN p_approve
      THEN 'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was approved.'
      ELSE COALESCE(
        'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was declined: ' || p_notes,
        'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was declined. You may submit a new request.'
      )
    END,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_program_enrollment_request(UUID, BOOLEAN, TEXT) TO authenticated;

-- ─── Notify admins on submit ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_admins_of_program_enrollment_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_program_name TEXT;
BEGIN
  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = NEW.program_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'program',
    'New Program Enrollment Request',
    'A farmer requested to enroll in ' || COALESCE(v_program_name, 'a program') || ' and needs review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_program_enrollment_request ON public.program_enrollment_requests;
CREATE TRIGGER trg_notify_admins_program_enrollment_request
  AFTER INSERT ON public.program_enrollment_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_admins_of_program_enrollment_request();

NOTIFY pgrst, 'reload schema';
