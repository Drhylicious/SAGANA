-- ============================================================
-- SAGANA — Order numbers: ORD-YYYYMMDD-XXXX
--
-- Until now an order's "number" was not stored anywhere. The app made it up
-- from the first 8 characters of the order's id (ORD-7D750007) in several
-- places. This script makes the database issue a real, stored order number:
--
--     ORD-20261024-A001
--         |        |
--         |        +-- sequence for the YEAR: A001 ... A999, B001 ... Z999,
--         |            then AA001 ... (a letter block of 999 orders)
--         +----------- the date the order was placed (Philippine time)
--
--   * The sequence runs through the whole year and starts again at A001 on
--     1 January (Philippine time). It is one counter per year, not per day.
--   * It is issued by a BEFORE INSERT trigger on orders, so it does not
--     matter which function or screen creates the order. A value sent by a
--     client is ignored and replaced.
--   * The counter row is locked while a number is issued, so orders placed at
--     the same moment are given different numbers, in order, with no gaps
--     (a number is only used when its order is saved).
--   * An order number can never be changed once it is set.
--
-- ORDERS THAT ALREADY EXIST keep their identifier: their order_number stays
-- empty and the app keeps showing their ORD-xxxxxxxx reference. Nothing is
-- renumbered or deleted.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end (and supabase_schema_order_number_test.sql).
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Orders that exist now (they keep their old reference):
--    SELECT count(*) AS orders_now FROM public.orders;
-- B. Triggers already on orders (informational):
--    SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.orders'::regclass AND NOT tgisinternal ORDER BY 1;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.orders') IS NULL THEN
    RAISE EXCEPTION 'public.orders is missing.';
  END IF;
END;
$$;

-- ═══ 1. Column ══════════════════════════════════════════════════════════
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_number TEXT;

-- Shape check. Existing rows are NULL and pass.
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_order_number_format;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_order_number_format
  CHECK (order_number IS NULL OR order_number ~ '^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$');

-- Unique, whatever happens.
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_order_number
  ON public.orders (order_number)
  WHERE order_number IS NOT NULL;

-- ═══ 2. The yearly counter ══════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.order_number_counters (
  year      INTEGER PRIMARY KEY CHECK (year BETWEEN 2000 AND 9999),
  last_seq  INTEGER NOT NULL CHECK (last_seq >= 0)
);

-- Internal: nobody reads or writes it from the app.
ALTER TABLE public.order_number_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_number_counters FROM PUBLIC, anon, authenticated;

-- ═══ 3. Number format ═══════════════════════════════════════════════════
-- 1 -> A001, 999 -> A999, 1000 -> B001, 25974 -> Z999, 25975 -> AA001.
CREATE OR REPLACE FUNCTION public.format_order_sequence(p_seq INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_block    INTEGER;
  v_in_block INTEGER;
  v_q        INTEGER;
  v_letters  TEXT := '';
BEGIN
  IF p_seq IS NULL OR p_seq < 1 THEN
    RAISE EXCEPTION 'The order sequence must be 1 or more.';
  END IF;
  v_block    := (p_seq - 1) / 999;          -- 0 = A, 25 = Z, 26 = AA, ...
  v_in_block := ((p_seq - 1) % 999) + 1;    -- 1 .. 999
  v_q := v_block + 1;
  WHILE v_q > 0 LOOP                         -- letters: A..Z, AA..ZZ, ...
    v_q := v_q - 1;
    v_letters := chr(65 + (v_q % 26)) || v_letters;
    v_q := v_q / 26;
  END LOOP;
  RETURN v_letters || lpad(v_in_block::TEXT, 3, '0');
END;
$$;

-- ═══ 4. Issuing a number ════════════════════════════════════════════════
-- The year and the date are taken in Philippine time, so an order placed just
-- after midnight there belongs to the new day and, on 1 January, the new year.
CREATE OR REPLACE FUNCTION public.next_order_number(p_at TIMESTAMPTZ DEFAULT NOW())
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local TIMESTAMP;
  v_year  INTEGER;
  v_seq   INTEGER;
BEGIN
  v_local := p_at AT TIME ZONE 'Asia/Manila';
  v_year  := EXTRACT(YEAR FROM v_local)::INTEGER;

  -- One atomic statement: the first order of a year creates the row at 1; every
  -- other order locks the row, adds 1 and waits its turn behind any order
  -- being saved at the same moment.
  INSERT INTO order_number_counters (year, last_seq)
  VALUES (v_year, 1)
  ON CONFLICT (year) DO UPDATE SET last_seq = order_number_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;

  RETURN 'ORD-' || to_char(v_local, 'YYYYMMDD') || '-' || public.format_order_sequence(v_seq);
END;
$$;

REVOKE ALL ON FUNCTION public.next_order_number(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- ═══ 5. Triggers on orders ══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.assign_order_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Always issued here; whatever a client sent is replaced.
  NEW.order_number := public.next_order_number(COALESCE(NEW.created_at, NOW()));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_assign_order_number ON public.orders;
CREATE TRIGGER trg_orders_assign_order_number
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.assign_order_number();

CREATE OR REPLACE FUNCTION public.protect_order_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.order_number IS DISTINCT FROM OLD.order_number THEN
    RAISE EXCEPTION 'An order number cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_protect_order_number ON public.orders;
CREATE TRIGGER trg_orders_protect_order_number
  BEFORE UPDATE OF order_number ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.protect_order_number();

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Objects exist (expect 2 triggers, 3 functions, the column, the index):
--    SELECT tgname FROM pg_trigger WHERE tgrelid='public.orders'::regclass
--      AND tgname IN ('trg_orders_assign_order_number','trg_orders_protect_order_number');
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('format_order_sequence','next_order_number','assign_order_number');
--    SELECT column_name FROM information_schema.columns
--      WHERE table_name='orders' AND column_name='order_number';
--    SELECT indexname FROM pg_indexes WHERE indexname='uq_orders_order_number';
-- 2. Orders from before this script were not touched (expect orders_now from the
--    pre-flight = rows with no number, until new orders are placed):
--    SELECT count(*) FILTER (WHERE order_number IS NULL) AS old_orders,
--           count(*) FILTER (WHERE order_number IS NOT NULL) AS numbered FROM public.orders;
-- 3. After placing orders: every number has the right shape (expect 0 rows):
--    SELECT id, order_number FROM public.orders
--    WHERE order_number IS NOT NULL AND order_number !~ '^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$';
-- 4. No duplicates (expect 0 rows):
--    SELECT order_number, count(*) FROM public.orders WHERE order_number IS NOT NULL
--    GROUP BY 1 HAVING count(*) > 1;
-- 5. The date in each number is the order's date in Philippine time (expect 0 rows):
--    SELECT id, order_number, created_at FROM public.orders
--    WHERE order_number IS NOT NULL
--      AND substr(order_number, 5, 8) <> to_char(created_at AT TIME ZONE 'Asia/Manila', 'YYYYMMDD');
-- 6. The sequence restarts each year. For each year the counter should equal the
--    number of numbered orders of that year (a smaller count only means an order
--    was deleted afterwards, which leaves its number unused):
--    SELECT c.year, c.last_seq,
--           (SELECT count(*) FROM public.orders o
--             WHERE o.order_number LIKE 'ORD-' || c.year || '%') AS numbered_orders
--    FROM public.order_number_counters c ORDER BY c.year;
-- ─────────────────────────────────────────────────────────────────────────
