-- Let Admins read the buyer_addresses rows of farmers they review.
--
-- Why: an outsider Farmer's registration address is saved in buyer_addresses
-- (owner-only RLS). The Admin needs to see it when reviewing the applicant
-- in Members. This adds a read-only SELECT policy for Admins only.
--
-- Officers are NOT included. The Members tab is Admin-only: the app hides it
-- from Officers and redirects them away from it (app_router.dart, admin shell).
--
-- Owners keep their existing "Users manage own addresses" policy. Writes are
-- still owner-only: no INSERT, UPDATE, or DELETE policy is added here.
--
-- Not applied automatically. Run in the Supabase SQL editor, then the
-- post-deploy verification at the bottom.

BEGIN;

DROP POLICY IF EXISTS "admin and officer read buyer addresses" ON public.buyer_addresses;
DROP POLICY IF EXISTS "admin reads buyer addresses" ON public.buyer_addresses;

CREATE POLICY "admin reads buyer addresses"
  ON public.buyer_addresses
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'admin'
    )
  );

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ──────────────────────────────────────────────
-- 1. The policy exists, and it is SELECT only:
--    select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'buyer_addresses';
--    Expected: "Users manage own addresses" (ALL) and
--              "admin reads buyer addresses" (SELECT).
--
-- 2. Signed in as an Admin, open a farmer's details whose registration
--    address exists. Expected: the Address Information card shows it.
--
-- 3. Signed in as an Officer, the address query returns only the Officer's
--    own rows (none), and the Members tab stays hidden.
