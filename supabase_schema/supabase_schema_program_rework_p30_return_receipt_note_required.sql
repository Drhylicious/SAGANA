-- ============================================================
-- SAGANA — p30: a harvest-return receipt must carry a note (database side)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. No data is changed or deleted.
--
-- The receipt form now requires a note. This makes the database refuse a new receipt without one, whichever
-- screen records it. The quantity rules already live in record_program_return_receipt() and are unchanged:
-- more than the quantity still due is refused (RETURN_OVER_RECEIPT), as is zero, a negative number, NaN, or
-- more than 2 decimals. Receipts already recorded without a note are left exactly as they are
-- (only NEW receipts are checked). The existing function is NOT replaced. Run after p29.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._return_receipt_require_note()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NULLIF(btrim(COALESCE(NEW.note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'REASON_REQUIRED: Write a note for this receipt.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_return_receipt_require_note ON public.program_return_receipts;
CREATE TRIGGER trg_return_receipt_require_note
  BEFORE INSERT ON public.program_return_receipts
  FOR EACH ROW EXECUTE FUNCTION public._return_receipt_require_note();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK (expect 1 row):
--   SELECT tgname FROM pg_trigger WHERE tgname = 'trg_return_receipt_require_note' AND NOT tgisinternal;
