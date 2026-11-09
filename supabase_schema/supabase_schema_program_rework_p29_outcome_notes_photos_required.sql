-- ============================================================
-- SAGANA — p29: every field of the outcome report is required (database side)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. No data is changed or deleted.
--
-- The Farmer's report was already fully required in the database (explanation, quantity/unit, dates, 1-5 photos).
-- The staff steps had optional parts. They are now required here too, so the rule holds whichever screen calls:
--   1. Review      - a review note is required for BOTH decisions (validated or returned).
--   2. Verification - at least ONE field photo is required (checked when the transaction commits, because the
--                     photos are saved just after the report row).
--   3. Final decision - the final note is required.
-- Only NEW actions are checked (the moment a review / verification / finalization is first recorded). Reports
-- already reviewed, verified or finalized without these are left exactly as they are.
-- Run after p28. The existing functions are NOT replaced.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._outcome_required_notes()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.review_decision IS NOT NULL AND OLD.review_decision IS NULL
     AND NULLIF(btrim(COALESCE(NEW.review_note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'REASON_REQUIRED: Write a note for this review.';
  END IF;
  IF NEW.status = 'finalized' AND OLD.status IS DISTINCT FROM 'finalized'
     AND NULLIF(btrim(COALESCE(NEW.final_note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'REASON_REQUIRED: Write the final note.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_outcome_required_notes ON public.program_outcome_reports;
CREATE TRIGGER trg_outcome_required_notes
  BEFORE UPDATE ON public.program_outcome_reports
  FOR EACH ROW EXECUTE FUNCTION public._outcome_required_notes();

CREATE OR REPLACE FUNCTION public._outcome_require_field_photo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM program_outcome_photos
                  WHERE report_id = NEW.id AND uploader_role = 'staff') THEN
    RAISE EXCEPTION 'PHOTO_REQUIRED: Add at least one field photo.';
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_outcome_require_field_photo ON public.program_outcome_reports;
CREATE CONSTRAINT TRIGGER trg_outcome_require_field_photo
  AFTER UPDATE OF verified_at ON public.program_outcome_reports
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (OLD.verified_at IS NULL AND NEW.verified_at IS NOT NULL)
  EXECUTE FUNCTION public._outcome_require_field_photo();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- R1  Both guards are installed (expect 2 rows):
--     SELECT tgname FROM pg_trigger WHERE tgname IN ('trg_outcome_required_notes', 'trg_outcome_require_field_photo') AND NOT tgisinternal;
-- R2  Reports verified earlier without a field photo are untouched (only information; nothing is changed):
--     SELECT r.id, r.verified_at FROM program_outcome_reports r
--      WHERE r.verified_at IS NOT NULL
--        AND NOT EXISTS (SELECT 1 FROM program_outcome_photos p WHERE p.report_id = r.id AND p.uploader_role = 'staff');
