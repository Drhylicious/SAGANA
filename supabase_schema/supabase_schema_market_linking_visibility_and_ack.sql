-- ============================================================
-- SAGANA — Market Linking: buyer visibility, no address, and a one-time
--          enrollment congratulations that stays acknowledged
--
-- Layered on supabase_schema_market_linking_buyer_cancellation.sql (run that
-- first).
--
-- 1. BUYER DETAILS = full name, contact number, optional email. The address
--    is no longer asked for. save_market_linking_buyer_details() loses its
--    address parameter and no longer writes buyer_address (existing values stay
--    in the table, unused). It still touches only buyer information: it never
--    changes the status of a request that already has a buyer, nor any quantity,
--    price or stock, so a Manager/Officer can correct the buyer while the
--    request is active. The Farmer is told when a buyer is first recorded and
--    when the details change.
--
-- 2. THE FARMER SEES THEIR BUYER. No new access is needed: the existing row
--    level security already lets a Farmer read exactly their own requests
--    (market_linking_programs) and their own sales (market_linking_sales), and
--    no other Farmer's. Both tables are added to realtime, so a change a
--    Manager/Officer saves appears on the Farmer's screen by itself.
--
-- 3. COMPLETED SALES KEEP THEIR BUYER. Each sale already keeps the buyer's name
--    and contact as they were when it was recorded; this adds the email, filled
--    in automatically from the request, so a later correction of the buyer never
--    rewrites an earlier sale.
--
-- 4. ENROLLMENT CONGRATULATIONS ONCE. da_amad_enrollments.acknowledged_at is set
--    when the Farmer taps Continue (acknowledge_da_amad_enrollment()), so the
--    screen stays gone after logout/login, a new device, a browser with cleared
--    storage or a reinstall. Everyone already approved today is marked
--    acknowledged, so only an enrollment approved from now on shows it.
--
-- Nothing is deleted. Safe to re-run.
-- Not applied automatically: run in the Supabase SQL editor, then
-- supabase_schema_market_linking_visibility_test.sql.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.save_market_linking_buyer_details(uuid,text,text,text,text)') IS NULL
     AND to_regprocedure('public.save_market_linking_buyer_details(uuid,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_market_linking_buyer_cancellation.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Buyer Details without the address ═══════════════════════════════════
DROP FUNCTION IF EXISTS public.save_market_linking_buyer_details(UUID, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.save_market_linking_buyer_details(
  p_program_id    UUID,
  p_buyer_name    TEXT,
  p_buyer_contact TEXT,
  p_buyer_email   TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog market_linking_programs%ROWTYPE;
  v_name TEXT := NULLIF(btrim(COALESCE(p_buyer_name, '')), '');
  v_tel  TEXT := NULLIF(btrim(COALESCE(p_buyer_contact, '')), '');
  v_mail TEXT := NULLIF(btrim(COALESCE(p_buyer_email, '')), '');
  v_first BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can save buyer details';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Enter the buyer''s full name.';
  END IF;
  IF v_tel IS NULL THEN
    RAISE EXCEPTION 'Enter the buyer''s contact number.';
  END IF;
  IF v_mail IS NOT NULL AND v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Enter a valid e-mail address, or leave it blank.';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.status NOT IN ('submitted', 'buyer_found') THEN
    RAISE EXCEPTION 'This request is already closed (%), so the buyer details cannot be changed.', v_prog.status;
  END IF;

  v_first := v_prog.buyer_name IS NULL OR btrim(v_prog.buyer_name) = '';

  -- Buyer information only. Quantity, price, stock and sales are not touched,
  -- and a request that already has a buyer keeps its status.
  UPDATE market_linking_programs
     SET buyer_name     = v_name,
         buyer_contact  = v_tel,
         buyer_email    = v_mail,
         buyer_found_at = COALESCE(buyer_found_at, NOW()),
         status         = 'buyer_found'
   WHERE id = v_prog.id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_prog.farmer_id, 'system',
    CASE WHEN v_first THEN 'A Buyer Was Found' ELSE 'Buyer Details Updated' END,
    CASE WHEN v_first
         THEN 'A buyer was found for your ' || v_prog.crop_name || ' request: ' || v_name || '. You can see the details in Market Linking.'
         ELSE 'The buyer details for your ' || v_prog.crop_name || ' request were updated.' END,
    FALSE, NOW(), '/farmer/profile/market-linking'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.save_market_linking_buyer_details(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_market_linking_buyer_details(UUID, TEXT, TEXT, TEXT) TO authenticated;

-- ═══ 2. Completed sales keep the buyer's email as it was ════════════════════
ALTER TABLE public.market_linking_sales ADD COLUMN IF NOT EXISTS buyer_email TEXT;

-- Existing sales: the request's email, only where the request still names the
-- same buyer the sale was recorded for.
UPDATE public.market_linking_sales s
   SET buyer_email = p.buyer_email
  FROM public.market_linking_programs p
 WHERE p.id = s.program_id AND s.buyer_email IS NULL
   AND p.buyer_email IS NOT NULL AND p.buyer_name = s.buyer_name;

CREATE OR REPLACE FUNCTION public.snapshot_market_linking_sale_buyer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.buyer_email IS NULL THEN
    SELECT p.buyer_email INTO NEW.buyer_email
      FROM market_linking_programs p WHERE p.id = NEW.program_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_sales_buyer_snapshot ON public.market_linking_sales;
CREATE TRIGGER trg_market_linking_sales_buyer_snapshot
  BEFORE INSERT ON public.market_linking_sales
  FOR EACH ROW EXECUTE FUNCTION public.snapshot_market_linking_sale_buyer();

-- ═══ 3. Realtime: a saved change reaches the Farmer's screen by itself ══════
-- Row level security applies to realtime, so a Farmer is told only about their
-- own rows.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
                      AND tablename = 'market_linking_programs') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.market_linking_programs;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
                      AND tablename = 'market_linking_sales') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.market_linking_sales;
    END IF;
  END IF;
END;
$$;

-- ═══ 4. Enrollment congratulations: acknowledged once, remembered ═══════════
ALTER TABLE public.da_amad_enrollments ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;

-- Everyone already approved has had the chance to see it: mark them done, so the
-- screen only ever appears for an enrollment approved from now on.
UPDATE public.da_amad_enrollments
   SET acknowledged_at = COALESCE(reviewed_at, NOW())
 WHERE status = 'approved' AND acknowledged_at IS NULL;

CREATE OR REPLACE FUNCTION public.acknowledge_da_amad_enrollment(p_enrollment_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only the Farmer's own, approved enrollment; a repeat call changes nothing.
  UPDATE public.da_amad_enrollments
     SET acknowledged_at = COALESCE(acknowledged_at, NOW())
   WHERE id = p_enrollment_id
     AND farmer_id = auth.uid()
     AND status = 'approved';
END;
$$;
REVOKE ALL ON FUNCTION public.acknowledge_da_amad_enrollment(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_da_amad_enrollment(UUID) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. No approved enrollment is left unacknowledged (expect 0 rows):
--    SELECT id FROM da_amad_enrollments WHERE status = 'approved' AND acknowledged_at IS NULL;
-- 2. Realtime includes both tables (expect 2 rows):
--    SELECT tablename FROM pg_publication_tables
--    WHERE pubname = 'supabase_realtime' AND tablename IN ('market_linking_programs','market_linking_sales');
-- 3. The old 5-argument buyer function is gone (expect 1 row, 4 arguments):
--    SELECT pronargs FROM pg_proc WHERE proname = 'save_market_linking_buyer_details';
-- 4. Then run supabase_schema_market_linking_visibility_test.sql (expect FAILED CHECKS: 0).
-- ───────────────────────────────────────────────────────────────────────────
