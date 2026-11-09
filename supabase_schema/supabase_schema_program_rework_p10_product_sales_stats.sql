-- ============================================================
-- SAGANA — Product Sales catalog: how many people bought a product and how
--          much was sold ("Buyers" and "sold" on the Farmer catalog card).
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it in the Supabase SQL editor after you
-- have checked it. One small transaction, safe to re-run.
--
-- WHY A FUNCTION
--   A Farmer can only read their OWN purchases, so the app cannot add up everyone's
--   purchases itself. This function returns only the two totals per product. It
--   never returns who bought, what anyone paid, or any single purchase.
--
-- WHAT IS COUNTED
--   Only PAID purchases (a purchase the cooperative has confirmed). Pending and
--   cancelled requests are not sales, so they are not counted.
--     buyers         = the number of different people with a paid purchase
--     quantity_sold  = the total quantity of those purchases, in the product's own unit
--   Members and non-members are both counted: anyone can buy.
--
-- WHO MAY ASK
--   Any active Farmer, Manager or Officer, for a Product Sales program.
--
-- Changes no table, no row and no existing function.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_program_product_stats(p_program_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF NOT (public.is_staff()
          OR EXISTS (SELECT 1 FROM user_roles ur
                      WHERE ur.user_id = auth.uid() AND ur.role = 'farmer' AND ur.status = 'active')) THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Farmer or the cooperative can see this.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cooperative_programs WHERE id = p_program_id AND program_purpose = 'sales') THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'product_id', pp.id,
             'buyers', COALESCE(s.buyers, 0),
             'quantity_sold', COALESCE(s.sold, 0)))
      FROM program_products pp
      LEFT JOIN (
        SELECT p.product_id,
               count(DISTINCT p.farmer_id) AS buyers,
               sum(p.quantity)             AS sold
          FROM program_product_purchases p
         WHERE p.program_id = p_program_id AND p.status = 'paid'
         GROUP BY p.product_id
      ) s ON s.product_id = pp.id
     WHERE pp.program_id = p_program_id
  ), '[]'::jsonb);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_product_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_product_stats(UUID) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The function exists and is not open to anonymous users:
--     SELECT grantee, privilege_type FROM information_schema.routine_privileges
--      WHERE routine_name = 'get_program_product_stats' ORDER BY 1;     -- authenticated only
-- V2  It agrees with the purchases (run as a signed-in user in the app, or compare the
--     same numbers by hand for one program):
--     SELECT product_id, count(DISTINCT farmer_id) AS buyers, sum(quantity) AS sold
--       FROM program_product_purchases WHERE program_id = '<program id>' AND status = 'paid'
--      GROUP BY product_id;
