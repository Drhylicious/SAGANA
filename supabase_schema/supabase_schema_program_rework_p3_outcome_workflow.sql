-- ============================================================
-- SAGANA — Program Management rework, PHASE 3: OUTCOME WORKFLOW (Proposal 11)
--
-- A Farmer who has received a program item reports the outcome — SUCCESSFUL or
-- FAILED — with an explanation, production information and 1-5 photos. Staff
-- review the evidence, an OFFICER does the field verification, and the outcome
-- is finalized. The reviewer and the verifier must be two different people.
-- Nothing here creates a loan, a repayment, a penalty or an inventory movement.
--
-- Requires (already applied): the Phase 5A and Phase 1 scripts, notify_staff(),
-- is_staff(), handle_updated_at(), audit_staff_change(), staff_permission_targets.
-- NOT APPLIED — run it yourself in the Supabase SQL editor, once, then the
-- verification block at the bottom. One transaction: all or nothing.
--
-- WHAT IT ADDS
--   program_outcome_reports   one row per report (a returned report stays as
--                             history; the Farmer files a new one)
--   program_outcome_photos    the photos (Farmer's evidence, Officer's field photos)
--   storage bucket program_evidence   PRIVATE (the other buckets are public)
--   submit_program_outcome_report()    Farmer
--   review_program_outcome()           Manager or Officer: validate / return
--   verify_program_outcome()           OFFICER only: field verification
--   finalize_program_outcome()         Manager or Officer, once both are done
--   get_my_outcome_reports()           what a Farmer may see (no staff names)
--   get_program_outcome_reports()      staff list with photos and who did what
--   get_program_history()              re-issued with the outcome events
--
-- STATUSES  (Farmer sees)  Pending Validation -> Successful | Failed
--                          Returned (staff asked for better evidence; file again)
--
-- SEPARATION OF DUTIES, enforced in three places so it cannot be bypassed:
--   1. review_program_outcome()  refuses if the caller already verified;
--   2. verify_program_outcome()  refuses if the caller already reviewed, and
--                                refuses anyone who is not an Officer;
--   3. a CHECK constraint refuses reviewed_by = verified_by on the table.
-- No override exists. If no other eligible person is available the report simply
-- stays pending.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Tables
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.program_outcome_reports (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_member_id  UUID NOT NULL REFERENCES public.program_members(id),
  program_id         UUID NOT NULL REFERENCES public.cooperative_programs(id),
  farmer_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- The Farmer's report
  reported_outcome   TEXT NOT NULL CHECK (reported_outcome IN ('successful', 'failed')),
  explanation        TEXT NOT NULL CHECK (btrim(explanation) <> ''),
  planted_date       DATE,
  harvest_date       DATE,
  quantity_harvested NUMERIC(12,2) CHECK (quantity_harvested IS NULL OR quantity_harvested > 0),
  quantity_unit      TEXT,
  area_planted       NUMERIC(12,2) CHECK (area_planted IS NULL OR area_planted > 0),
  area_unit          TEXT CHECK (area_unit IS NULL OR area_unit IN ('sqm', 'hectare')),
  failure_cause      TEXT,
  failure_date       DATE,
  status             TEXT NOT NULL DEFAULT 'pending_validation'
                     CHECK (status IN ('pending_validation', 'returned', 'finalized')),
  submitted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Evidence review (Manager or Officer)
  review_decision    TEXT CHECK (review_decision IN ('validated', 'returned')),
  reviewed_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by_name   TEXT,
  reviewed_by_role   TEXT,
  reviewed_at        TIMESTAMPTZ,
  review_note        TEXT,

  -- Field verification (Officer)
  verification_finding TEXT CHECK (verification_finding IN ('confirms', 'disputes')),
  verified_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  verified_by_name   TEXT,
  verified_by_role   TEXT,
  verified_at        TIMESTAMPTZ,
  field_visit_date   DATE,
  verified_quantity  NUMERIC(12,2) CHECK (verified_quantity IS NULL OR verified_quantity > 0),
  verified_unit      TEXT,
  verification_note  TEXT,

  -- Final decision
  final_outcome      TEXT CHECK (final_outcome IN ('successful', 'failed')),
  finalized_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  finalized_by_name  TEXT,
  finalized_by_role  TEXT,
  finalized_at       TIMESTAMPTZ,
  final_note         TEXT,

  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- What each kind of report must contain.
  CONSTRAINT outcome_success_needs_harvest CHECK (
    reported_outcome <> 'successful'
    OR (quantity_harvested IS NOT NULL AND quantity_unit IS NOT NULL AND btrim(quantity_unit) <> '')),
  CONSTRAINT outcome_failure_needs_cause CHECK (
    reported_outcome <> 'failed'
    OR (failure_cause IS NOT NULL AND btrim(failure_cause) <> '')),
  CONSTRAINT outcome_returned_needs_note CHECK (
    review_decision IS DISTINCT FROM 'returned'
    OR (review_note IS NOT NULL AND btrim(review_note) <> '')),
  CONSTRAINT outcome_final_matches_status CHECK ((status = 'finalized') = (final_outcome IS NOT NULL)),
  -- Strict separation of duties: the reviewer and the verifier are two people.
  CONSTRAINT outcome_reviewer_is_not_verifier CHECK (
    reviewed_by IS NULL OR verified_by IS NULL OR reviewed_by <> verified_by)
);

-- One report in progress (or finished) per member. A RETURNED report does not
-- count, so the Farmer can file a new one.
CREATE UNIQUE INDEX IF NOT EXISTS uq_program_outcome_open
  ON public.program_outcome_reports (program_member_id)
  WHERE status <> 'returned';

CREATE INDEX IF NOT EXISTS idx_program_outcome_program
  ON public.program_outcome_reports (program_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_program_outcome_farmer
  ON public.program_outcome_reports (farmer_id, submitted_at DESC);

DROP TRIGGER IF EXISTS trg_program_outcome_updated_at ON public.program_outcome_reports;
CREATE TRIGGER trg_program_outcome_updated_at
  BEFORE UPDATE ON public.program_outcome_reports
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TABLE IF NOT EXISTS public.program_outcome_photos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id     UUID NOT NULL REFERENCES public.program_outcome_reports(id) ON DELETE CASCADE,
  uploaded_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  uploader_role TEXT NOT NULL CHECK (uploader_role IN ('farmer', 'staff')),
  storage_path  TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (report_id, storage_path)
);
CREATE INDEX IF NOT EXISTS idx_program_outcome_photos_report ON public.program_outcome_photos (report_id);

-- At most 5 photos per side (Farmer evidence / Officer field photos).
CREATE OR REPLACE FUNCTION public.limit_outcome_photos()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF (SELECT count(*) FROM program_outcome_photos
       WHERE report_id = NEW.report_id AND uploader_role = NEW.uploader_role) >= 5 THEN
    RAISE EXCEPTION 'A report can have at most 5 photos from the % side.', NEW.uploader_role;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_limit_outcome_photos ON public.program_outcome_photos;
CREATE TRIGGER trg_limit_outcome_photos
  BEFORE INSERT ON public.program_outcome_photos
  FOR EACH ROW EXECUTE FUNCTION public.limit_outcome_photos();

-- Row security: staff may read; nobody writes directly (every write is one of
-- the SECURITY DEFINER functions below). A Farmer never reads these tables.
ALTER TABLE public.program_outcome_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_outcome_photos  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "program_outcome_reports: staff reads" ON public.program_outcome_reports;
CREATE POLICY "program_outcome_reports: staff reads"
  ON public.program_outcome_reports FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "program_outcome_photos: staff reads" ON public.program_outcome_photos;
CREATE POLICY "program_outcome_photos: staff reads"
  ON public.program_outcome_photos FOR SELECT TO authenticated USING (public.is_staff());

REVOKE ALL ON public.program_outcome_reports, public.program_outcome_photos FROM PUBLIC, anon;
GRANT SELECT ON public.program_outcome_reports, public.program_outcome_photos TO authenticated;

-- Every staff change is recorded in the existing accountability trail.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_outcome_reports;
CREATE TRIGGER trg_audit_staff_change
  AFTER INSERT OR UPDATE OR DELETE ON public.program_outcome_reports
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('programs', '');

-- ════════════════════════════════════════════════════════════
-- 2. Private evidence bucket
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('program_evidence', 'program_evidence', FALSE, 10485760,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Files live in the uploader's own folder:  <user id>/<file>
DROP POLICY IF EXISTS "Program evidence upload" ON storage.objects;
CREATE POLICY "Program evidence upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'program_evidence'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = (auth.uid())::text
    AND (public.is_staff()
         OR EXISTS (SELECT 1 FROM public.user_roles ur
                    WHERE ur.user_id = auth.uid() AND ur.role = 'farmer' AND ur.status = 'active'))
  );

-- Staff read every photo; a Farmer reads only their own folder.
DROP POLICY IF EXISTS "Program evidence read" ON storage.objects;
CREATE POLICY "Program evidence read"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'program_evidence'
    AND (public.is_staff() OR (storage.foldername(name))[1] = (auth.uid())::text)
  );

-- A person may remove a photo they uploaded and have not submitted yet.
DROP POLICY IF EXISTS "Program evidence delete own" ON storage.objects;
CREATE POLICY "Program evidence delete own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'program_evidence'
    AND (storage.foldername(name))[1] = (auth.uid())::text
    AND NOT EXISTS (SELECT 1 FROM public.program_outcome_photos p WHERE p.storage_path = name)
  );

-- ════════════════════════════════════════════════════════════
-- 3. Helpers (not callable from the app)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._outcome_actor()
RETURNS TABLE (a_name TEXT, a_role TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT (SELECT ui.full_name FROM user_information ui WHERE ui.user_id = auth.uid()),
         (SELECT ur.role FROM user_roles ur WHERE ur.user_id = auth.uid() LIMIT 1);
$$;
REVOKE ALL ON FUNCTION public._outcome_actor() FROM PUBLIC, anon, authenticated;

-- Every photo path must be in the caller's own folder and really exist.
CREATE OR REPLACE FUNCTION public._outcome_check_paths(p_paths TEXT[], p_min INT, p_max INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_path TEXT;
  v_n    INT := COALESCE(array_length(p_paths, 1), 0);
BEGIN
  IF v_n < p_min THEN
    RAISE EXCEPTION 'Add at least % photo(s).', p_min;
  END IF;
  IF v_n > p_max THEN
    RAISE EXCEPTION 'You can add at most % photos.', p_max;
  END IF;
  IF v_n <> (SELECT count(DISTINCT x) FROM unnest(p_paths) x) THEN
    RAISE EXCEPTION 'The same photo was added twice.';
  END IF;
  FOREACH v_path IN ARRAY COALESCE(p_paths, ARRAY[]::TEXT[]) LOOP
    IF v_path NOT LIKE (auth.uid()::TEXT || '/%') THEN
      RAISE EXCEPTION 'A photo does not belong to you.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects o
                   WHERE o.bucket_id = 'program_evidence' AND o.name = v_path) THEN
      RAISE EXCEPTION 'A photo was not uploaded. Please add it again.';
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public._outcome_check_paths(TEXT[], INT, INT) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. Farmer: submit a report
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.submit_program_outcome_report(
  p_program_member_id UUID,
  p_outcome           TEXT,
  p_explanation       TEXT,
  p_planted_date      DATE,
  p_harvest_date      DATE,
  p_quantity          NUMERIC,
  p_unit              TEXT,
  p_area              NUMERIC,
  p_area_unit         TEXT,
  p_failure_cause     TEXT,
  p_failure_date      DATE,
  p_photo_paths       TEXT[]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     UUID := auth.uid();
  v_member  program_members%ROWTYPE;
  v_program cooperative_programs%ROWTYPE;
  v_id      UUID;
  v_path    TEXT;
  v_farmer  TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'Only an active cooperative member can report an outcome.';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND OR v_member.farmer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Program enrollment not found.';
  END IF;
  IF v_member.status <> 'active' THEN
    RAISE EXCEPTION 'Only an active member can report an outcome.';
  END IF;
  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'You can report an outcome after you have received the program item.';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.program_purpose <> 'distribution' THEN
    RAISE EXCEPTION 'Outcomes are reported for distribution programs only.';
  END IF;

  IF EXISTS (SELECT 1 FROM program_outcome_reports
              WHERE program_member_id = p_program_member_id AND status <> 'returned') THEN
    RAISE EXCEPTION 'An outcome report for this program is already in progress or finished.';
  END IF;
  -- Earlier recorded (legacy) outcome with no report: not reported again.
  IF v_member.distribution_outcome IN ('thriving', 'failed') THEN
    RAISE EXCEPTION 'An outcome was already recorded for this program.';
  END IF;

  IF p_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'Choose Successful or Failed.';
  END IF;
  IF p_explanation IS NULL OR btrim(p_explanation) = '' THEN
    RAISE EXCEPTION 'Write your explanation.';
  END IF;
  IF p_outcome = 'successful' AND (p_quantity IS NULL OR p_quantity <= 0 OR p_unit IS NULL OR btrim(p_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity harvested and its unit.';
  END IF;
  IF p_outcome = 'failed' AND (p_failure_cause IS NULL OR btrim(p_failure_cause) = '') THEN
    RAISE EXCEPTION 'Describe what caused the failure.';
  END IF;
  IF p_area IS NOT NULL AND (p_area <= 0 OR p_area_unit IS NULL) THEN
    RAISE EXCEPTION 'Enter the area planted with its unit.';
  END IF;
  IF p_planted_date IS NOT NULL AND p_harvest_date IS NOT NULL AND p_harvest_date < p_planted_date THEN
    RAISE EXCEPTION 'The harvest date cannot be before the planting date.';
  END IF;

  PERFORM public._outcome_check_paths(p_photo_paths, 1, 5);

  INSERT INTO program_outcome_reports (
    program_member_id, program_id, farmer_id, reported_outcome, explanation,
    planted_date, harvest_date, quantity_harvested, quantity_unit, area_planted, area_unit,
    failure_cause, failure_date
  ) VALUES (
    p_program_member_id, v_member.program_id, v_uid, p_outcome, btrim(p_explanation),
    p_planted_date, p_harvest_date,
    CASE WHEN p_outcome = 'successful' THEN p_quantity END,
    CASE WHEN p_outcome = 'successful' THEN btrim(p_unit) END,
    p_area, CASE WHEN p_area IS NOT NULL THEN p_area_unit END,
    CASE WHEN p_outcome = 'failed' THEN btrim(p_failure_cause) END,
    CASE WHEN p_outcome = 'failed' THEN p_failure_date END
  ) RETURNING id INTO v_id;

  FOREACH v_path IN ARRAY p_photo_paths LOOP
    INSERT INTO program_outcome_photos (report_id, uploaded_by, uploader_role, storage_path)
    VALUES (v_id, v_uid, 'farmer', v_path);
  END LOOP;

  SELECT full_name INTO v_farmer FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'program',
    'Program Outcome Report',
    COALESCE(v_farmer, 'A farmer') || ' reported a ' || p_outcome || ' outcome for ' ||
      COALESCE(v_program.program_name, 'a program') || '. It is waiting for review and field verification.',
    '/admin/programs/outcomes'
  );

  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.submit_program_outcome_report(UUID, TEXT, TEXT, DATE, DATE, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, DATE, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_program_outcome_report(UUID, TEXT, TEXT, DATE, DATE, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, DATE, TEXT[]) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Staff: review the evidence (Manager or Officer)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.review_program_outcome(
  p_report_id UUID,
  p_decision  TEXT,
  p_note      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_r     program_outcome_reports%ROWTYPE;
  v_note  TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name  TEXT;
  v_role  TEXT;
  v_prog  TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can review an outcome report.';
  END IF;
  IF p_decision NOT IN ('validated', 'returned') THEN
    RAISE EXCEPTION 'The decision must be validated or returned.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report is no longer waiting for review (status: %).', v_r.status;
  END IF;
  IF v_r.review_decision IS NOT NULL THEN
    RAISE EXCEPTION 'The evidence on this report was already reviewed.';
  END IF;
  -- Strict separation of duties.
  IF v_r.verified_by = v_uid THEN
    RAISE EXCEPTION 'You already conducted the field verification for this report, so a different person must review the evidence.';
  END IF;
  IF p_decision = 'returned' AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain what the Farmer needs to fix.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET review_decision  = p_decision,
         reviewed_by      = v_uid,
         reviewed_by_name = v_name,
         reviewed_by_role = v_role,
         reviewed_at      = NOW(),
         review_note      = v_note,
         status           = CASE WHEN p_decision = 'returned' THEN 'returned' ELSE status END
   WHERE id = p_report_id;

  IF p_decision = 'returned' THEN
    SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_r.program_id;
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (v_r.farmer_id, 'program', 'Outcome Report Returned',
            'Your outcome report for ' || COALESCE(v_prog, 'the program') ||
              ' needs more evidence: ' || v_note || ' Please submit a new report.',
            FALSE, NOW(), '/farmer/profile/programs/enrolled');
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.review_program_outcome(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_program_outcome(UUID, TEXT, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Officer: field verification
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.verify_program_outcome(
  p_report_id        UUID,
  p_finding          TEXT,
  p_verified_quantity NUMERIC,
  p_verified_unit    TEXT,
  p_field_visit_date DATE,
  p_note             TEXT,
  p_photo_paths      TEXT[]
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_r     program_outcome_reports%ROWTYPE;
  v_name  TEXT;
  v_role  TEXT;
  v_path  TEXT;
BEGIN
  -- Only an Officer conducts the field verification.
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'officer') THEN
    RAISE EXCEPTION 'Only an Officer can conduct the field verification.';
  END IF;
  IF p_finding NOT IN ('confirms', 'disputes') THEN
    RAISE EXCEPTION 'The finding must be confirms or disputes.';
  END IF;
  IF p_note IS NULL OR btrim(p_note) = '' THEN
    RAISE EXCEPTION 'Write what you found during the field verification.';
  END IF;
  IF p_field_visit_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date of the field visit.';
  END IF;
  IF p_field_visit_date > (NOW() AT TIME ZONE 'Asia/Manila')::DATE THEN
    RAISE EXCEPTION 'The field visit date cannot be in the future.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report is no longer waiting for verification (status: %).', v_r.status;
  END IF;
  IF v_r.verified_by IS NOT NULL THEN
    RAISE EXCEPTION 'The field verification for this report was already recorded.';
  END IF;
  -- Strict separation of duties.
  IF v_r.reviewed_by = v_uid THEN
    RAISE EXCEPTION 'You already reviewed the evidence for this report, so a different person must conduct the field verification.';
  END IF;
  -- A successful report is checked against what the Officer actually measured.
  IF v_r.reported_outcome = 'successful'
     AND (p_verified_quantity IS NULL OR p_verified_quantity <= 0
          OR p_verified_unit IS NULL OR btrim(p_verified_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity you measured in the field and its unit.';
  END IF;

  PERFORM public._outcome_check_paths(p_photo_paths, 0, 5);

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET verification_finding = p_finding,
         verified_by          = v_uid,
         verified_by_name     = v_name,
         verified_by_role     = v_role,
         verified_at          = NOW(),
         field_visit_date     = p_field_visit_date,
         verified_quantity    = CASE WHEN v_r.reported_outcome = 'successful' THEN p_verified_quantity END,
         verified_unit        = CASE WHEN v_r.reported_outcome = 'successful' THEN btrim(p_verified_unit) END,
         verification_note    = btrim(p_note)
   WHERE id = p_report_id;

  FOREACH v_path IN ARRAY COALESCE(p_photo_paths, ARRAY[]::TEXT[]) LOOP
    INSERT INTO program_outcome_photos (report_id, uploaded_by, uploader_role, storage_path)
    VALUES (p_report_id, v_uid, 'staff', v_path);
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public.verify_program_outcome(UUID, TEXT, NUMERIC, TEXT, DATE, TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_program_outcome(UUID, TEXT, NUMERIC, TEXT, DATE, TEXT, TEXT[]) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. Staff: finalize (needs BOTH the review and the field verification)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.finalize_program_outcome(
  p_report_id     UUID,
  p_final_outcome TEXT,
  p_note          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  UUID := auth.uid();
  v_r    program_outcome_reports%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name TEXT;
  v_role TEXT;
  v_prog TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can finalize an outcome.';
  END IF;
  IF p_final_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'The final outcome must be successful or failed.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status = 'finalized' THEN
    RAISE EXCEPTION 'This outcome was already finalized.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report cannot be finalized (status: %).', v_r.status;
  END IF;
  IF v_r.review_decision IS DISTINCT FROM 'validated' THEN
    RAISE EXCEPTION 'The evidence must be reviewed and validated first.';
  END IF;
  IF v_r.verified_by IS NULL THEN
    RAISE EXCEPTION 'An Officer must complete the field verification first.';
  END IF;
  IF (p_final_outcome <> v_r.reported_outcome OR v_r.verification_finding = 'disputes') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain the decision: it differs from the report or the field verification disputed it.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET status            = 'finalized',
         final_outcome     = p_final_outcome,
         finalized_by      = v_uid,
         finalized_by_name = v_name,
         finalized_by_role = v_role,
         finalized_at      = NOW(),
         final_note        = v_note
   WHERE id = p_report_id;

  -- Keep the member's outcome in step (successful -> 'thriving' is the stored
  -- legacy value the rest of the app already understands). No loan, no return,
  -- no stock movement happens here.
  UPDATE program_members
     SET distribution_outcome = CASE p_final_outcome WHEN 'successful' THEN 'thriving' ELSE 'failed' END,
         outcome_recorded_at  = NOW()
   WHERE id = v_r.program_member_id;

  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_r.program_id;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program',
          CASE p_final_outcome WHEN 'successful' THEN 'Program Outcome: Successful' ELSE 'Program Outcome: Failed' END,
          'Your outcome for ' || COALESCE(v_prog, 'the program') || ' was confirmed as ' || p_final_outcome || '.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
END;
$function$;
REVOKE ALL ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 8. Reads
-- ════════════════════════════════════════════════════════════
-- A Farmer's own reports: no reviewer, verifier or any staff identity, and the
-- return note only when the report was returned to them.
CREATE OR REPLACE FUNCTION public.get_my_outcome_reports()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.submitted_at DESC), '[]'::jsonb)
  FROM (
    SELECT r.submitted_at,
           jsonb_build_object(
             'id', r.id,
             'program_member_id', r.program_member_id,
             'program_id', r.program_id,
             'reported_outcome', r.reported_outcome,
             'status', r.status,
             'submitted_at', r.submitted_at,
             'return_note', CASE WHEN r.status = 'returned' THEN r.review_note END,
             'final_outcome', r.final_outcome,
             'finalized_at', r.finalized_at,
             'review_done', r.review_decision = 'validated',
             'verification_done', r.verified_by IS NOT NULL,
             'photo_count', (SELECT count(*) FROM program_outcome_photos p
                              WHERE p.report_id = r.id AND p.uploader_role = 'farmer')
           ) AS j
    FROM program_outcome_reports r
    WHERE r.farmer_id = auth.uid()
  ) x;
$$;
REVOKE ALL ON FUNCTION public.get_my_outcome_reports() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_outcome_reports() TO authenticated;

-- Staff list (all programs, or one) with the photos and who did what.
CREATE OR REPLACE FUNCTION public.get_program_outcome_reports(p_program_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can read outcome reports.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.submitted_at DESC), '[]'::jsonb)
    FROM (
      SELECT r.submitted_at,
             to_jsonb(r) || jsonb_build_object(
               'program_name', cp.program_name,
               'farmer_name', ui.full_name,
               'item_name', pm.distributed_item_name,
               'quantity_given', pm.quantity_given,
               'distributed_at', pm.distributed_at,
               'photos', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'id', ph.id, 'path', ph.storage_path, 'by', ph.uploader_role)
                                   ORDER BY ph.created_at)
                                   FROM program_outcome_photos ph WHERE ph.report_id = r.id), '[]'::jsonb)
             ) AS j
      FROM program_outcome_reports r
      JOIN cooperative_programs cp ON cp.id = r.program_id
      LEFT JOIN program_members pm ON pm.id = r.program_member_id
      LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
      WHERE p_program_id IS NULL OR r.program_id = p_program_id
    ) x
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_outcome_reports(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_outcome_reports(UUID) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 9. Officer permission gate: the three staff actions are Dashboard writes
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc',   'review_program_outcome',   'dashboard'),
  ('rpc',   'verify_program_outcome',   'dashboard'),
  ('rpc',   'finalize_program_outcome', 'dashboard'),
  ('table', 'program_outcome_reports',  'dashboard'),
  ('table', 'program_outcome_photos',   'dashboard')
ON CONFLICT (kind, name) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- 10. get_program_history(): the Phase 5A function plus the outcome events
-- ════════════════════════════════════════════════════════════
-- The earlier outcome row written when a member's outcome is set (by this
-- workflow's finalize step) is NOT shown a second time: finalized reports show
-- their own event; only outcomes recorded before this workflow (no report) still
-- come from the accountability trail.
CREATE OR REPLACE FUNCTION public.get_program_history(p_program_id uuid)
RETURNS TABLE (
  out_at       timestamptz,
  out_type     text,
  out_actor    text,
  out_role     text,
  out_subject  text,
  out_details  jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can read a program history';
  END IF;

  RETURN QUERY
  WITH
  prog AS (SELECT * FROM cooperative_programs WHERE id = p_program_id),
  mem AS (
    SELECT pm.id, pm.enrolled_at, pm.farmer_id, ui.full_name
    FROM program_members pm
    LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
    WHERE pm.program_id = p_program_id
  ),
  act AS (SELECT a.id FROM program_activities a WHERE a.program_id = p_program_id),
  trail AS (
    SELECT l.* FROM admin_activity_log l
    WHERE l.source = 'db'
      AND (
        (l.table_name = 'cooperative_programs' AND l.record_id = p_program_id::text)
        OR (l.table_name = 'program_members'
            AND (l.record_id IN (SELECT m.id::text FROM mem m)
                 OR l.new_values ->> 'program_id' = p_program_id::text
                 OR l.old_values ->> 'program_id' = p_program_id::text))
        OR (l.table_name = 'program_activities'
            AND (l.record_id IN (SELECT a.id::text FROM act a)
                 OR l.new_values ->> 'program_id' = p_program_id::text
                 OR l.old_values ->> 'program_id' = p_program_id::text))
      )
  ),
  rep AS (
    SELECT r.*, ui.full_name AS farmer_name
    FROM program_outcome_reports r
    LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
    WHERE r.program_id = p_program_id
  )

  SELECT p.created_at, 'program_created'::text, ui.full_name, ur.role, NULL::text,
         jsonb_build_object('name', p.program_name)
  FROM prog p
  LEFT JOIN user_information ui ON ui.user_id = p.created_by
  LEFT JOIN user_roles ur ON ur.user_id = p.created_by

  UNION ALL
  SELECT t.created_at, 'program_updated', t.actor_name, t.actor_role, NULL,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t WHERE t.table_name = 'cooperative_programs' AND t.operation = 'updated'

  UNION ALL
  SELECT r.submitted_at, 'enrollment_requested', ui.full_name, 'farmer', ui.full_name, '{}'::jsonb
  FROM program_enrollment_requests r
  LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
  WHERE r.program_id = p_program_id

  UNION ALL
  SELECT r.reviewed_at, 'enrollment_declined', sui.full_name, sur.role, fui.full_name,
         jsonb_build_object('note', r.admin_notes)
  FROM program_enrollment_requests r
  LEFT JOIN user_information fui ON fui.user_id = r.farmer_id
  LEFT JOIN user_information sui ON sui.user_id = r.reviewed_by
  LEFT JOIN user_roles sur ON sur.user_id = r.reviewed_by
  WHERE r.program_id = p_program_id AND r.status = 'rejected' AND r.reviewed_at IS NOT NULL

  UNION ALL
  SELECT t.created_at, 'member_enrolled', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('re_enrolled', false)
  FROM trail t WHERE t.table_name = 'program_members' AND t.operation = 'created'

  UNION ALL
  SELECT m.enrolled_at, 'member_enrolled', NULL, NULL, m.full_name,
         jsonb_build_object('re_enrolled', false, 'actor_unrecorded', true)
  FROM mem m
  WHERE NOT EXISTS (
    SELECT 1 FROM trail t
    WHERE t.table_name = 'program_members' AND t.operation = 'created' AND t.record_id = m.id::text)

  UNION ALL
  SELECT t.created_at, 'member_enrolled', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('re_enrolled', true)
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated' AND t.new_values ->> 'status' = 'active'

  UNION ALL
  SELECT t.created_at, 'member_removed', t.actor_name, t.actor_role, t.reference_label, '{}'::jsonb
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated' AND t.new_values ->> 'status' = 'withdrawn'

  UNION ALL
  SELECT t.created_at, 'benefit_distributed', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('quantity', t.new_values -> 'quantity_given',
                            'item', t.new_values ->> 'distributed_item_name')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'distributed_at' AND t.new_values ->> 'distributed_at' IS NOT NULL

  UNION ALL
  -- Outcomes recorded BEFORE the evidence workflow (no report exists for them).
  SELECT t.created_at, 'outcome_recorded', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('outcome', t.new_values ->> 'distribution_outcome')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'distribution_outcome'
    AND NOT EXISTS (SELECT 1 FROM program_outcome_reports r
                    WHERE r.program_member_id::text = t.record_id AND r.status = 'finalized')

  UNION ALL
  SELECT t.created_at, 'return_confirmed', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('amount', t.new_values -> 'amount_returned')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'settled_at' AND t.new_values ->> 'settled_at' IS NOT NULL

  UNION ALL
  SELECT t.created_at, 'converted_to_loan', t.actor_name, t.actor_role, t.reference_label, '{}'::jsonb
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'converted_loan_id' AND t.new_values ->> 'converted_loan_id' IS NOT NULL

  UNION ALL
  SELECT t.created_at,
         CASE t.operation WHEN 'created' THEN 'activity_created'
                          WHEN 'updated' THEN 'activity_updated' ELSE 'activity_deleted' END,
         t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t WHERE t.table_name = 'program_activities'

  -- ── Outcome workflow (read from the report rows themselves) ──
  UNION ALL
  SELECT r.submitted_at, 'outcome_submitted', r.farmer_name, 'farmer', r.farmer_name,
         jsonb_build_object('outcome', r.reported_outcome)
  FROM rep r

  UNION ALL
  SELECT r.reviewed_at, 'outcome_reviewed', r.reviewed_by_name, r.reviewed_by_role, r.farmer_name,
         jsonb_build_object('decision', r.review_decision, 'note', r.review_note)
  FROM rep r WHERE r.reviewed_at IS NOT NULL

  UNION ALL
  SELECT r.verified_at, 'outcome_verified', r.verified_by_name, r.verified_by_role, r.farmer_name,
         jsonb_build_object('finding', r.verification_finding, 'note', r.verification_note,
                            'quantity', r.verified_quantity, 'unit', r.verified_unit)
  FROM rep r WHERE r.verified_at IS NOT NULL

  UNION ALL
  SELECT r.finalized_at, 'outcome_finalized', r.finalized_by_name, r.finalized_by_role, r.farmer_name,
         jsonb_build_object('outcome', r.final_outcome, 'reported', r.reported_outcome, 'note', r.final_note)
  FROM rep r WHERE r.finalized_at IS NOT NULL

  ORDER BY 1 DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_program_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_history(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run each by itself AFTER applying)
-- ============================================================
-- V1. Tables, bucket and functions exist (expect 2 rows, 1 row, 7 rows):
--     SELECT table_name FROM information_schema.tables WHERE table_schema='public'
--       AND table_name IN ('program_outcome_reports','program_outcome_photos');
--     SELECT id, public FROM storage.buckets WHERE id = 'program_evidence';           -- public = false
--     SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
--       ('submit_program_outcome_report','review_program_outcome','verify_program_outcome',
--        'finalize_program_outcome','get_my_outcome_reports','get_program_outcome_reports','get_program_history');
-- V2. The separation constraint and the Officer-only check are in place (expect 1 row, then true, true):
--     SELECT conname FROM pg_constraint WHERE conname = 'outcome_reviewer_is_not_verifier';
--     SELECT pg_get_functiondef('public.verify_program_outcome(uuid,text,numeric,text,date,text,text[])'::regprocedure) ILIKE '%role = ''officer''%' AS officer_only,
--            pg_get_functiondef('public.review_program_outcome(uuid,text,text)'::regprocedure) ILIKE '%already conducted the field verification%' AS reviewer_checked;
-- V3. The three staff functions are governed by the Officer permission gate (expect 5 rows):
--     SELECT kind, name, module FROM staff_permission_targets WHERE name LIKE '%program_outcome%' ORDER BY 1,2;
-- V4. Policies on the evidence bucket (expect 3 rows):
--     SELECT policyname, cmd FROM pg_policies WHERE schemaname='storage' AND policyname LIKE 'Program evidence%';
-- V5. Nothing existing changed (expect 5 distributed members; 0 reports yet):
--     SELECT count(*) FROM program_members WHERE distributed_at IS NOT NULL;
--     SELECT count(*) FROM program_outcome_reports;
-- V6. After a full test (Farmer submits, Manager reviews, Officer verifies, someone finalizes), the
--     reviewer and verifier are different people (expect 0 rows):
--     SELECT id FROM program_outcome_reports WHERE reviewed_by = verified_by;
-- ============================================================
