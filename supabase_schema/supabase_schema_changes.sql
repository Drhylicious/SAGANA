SELECT count(*) FROM public.cooperative_programs WHERE program_type IS NULL;
ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_program_type_check;
ALTER TABLE public.cooperative_programs
  ALTER COLUMN program_type TYPE TEXT,
  ALTER COLUMN program_type SET DEFAULT 'other',
  ALTER COLUMN program_type SET NOT NULL;
ALTER TABLE public.cooperative_programs
  ALTER COLUMN program_type TYPE TEXT,
  ALTER COLUMN program_type SET DEFAULT 'other',
  ALTER COLUMN program_type SET NOT NULL;
UPDATE public.cooperative_programs
  SET program_type = 'other'
  WHERE program_type IS NULL;
ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_program_type_check,
  ALTER COLUMN program_type TYPE TEXT,
  ALTER COLUMN program_type SET DEFAULT 'other';

-- run SET NOT NULL only after ensuring no NULLs exist
ALTER TABLE public.cooperative_annual_totals
  ADD COLUMN IF NOT EXISTS afs_finalized BOOLEAN NOT NULL DEFAULT false;

-- Verify FK exists between program_members and cooperative_programs
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'program_members';  

-- Needed by approveMember() to update auth email when approving a pending farmer
CREATE OR REPLACE FUNCTION update_user_email_to_username(
  p_user_id  UUID,
  p_username TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE auth.users
  SET email = lower(trim(p_username)) || '@sagana.local'
  WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_user_email_to_username TO authenticated;
REVOKE EXECUTE ON FUNCTION update_user_email_to_username FROM anon;

-- Add admin read policy to notifications table
CREATE POLICY "notifications: admin reads all"
  ON public.notifications FOR SELECT
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()
    )
  );

ALTER TABLE public.sp3_member_registry
ADD CONSTRAINT sp3_member_registry_registered_user_id_key
UNIQUE (registered_user_id);  

ALTER TABLE public.marketplace_listings
  DROP CONSTRAINT marketplace_listings_status_check;

ALTER TABLE public.marketplace_listings
  ADD CONSTRAINT marketplace_listings_status_check
  CHECK (status = ANY (ARRAY[
    'pending_review'::text,
    'approved'::text,
    'changes_required'::text,
    'withdrawn'::text,
    'rejected'::text,
    'sold'::text
  ]));

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SAGANA — Phase 4 Dead Code Cleanup
-- Completes Step 3 of supabase_schema_loan_inventory_link.sql,
-- which was left commented out (manual checkpoint) rather than
-- run automatically. Confirmed dead: no Dart code in the Loan or
-- Inventory modules reads item_name/category/unit from
-- loan_items_master — every read goes through the
-- cooperative_inventory join added by that migration's Step 1.
--
-- Deliberately narrower than the original Step 3: this drops only
-- the three unused columns. It does NOT add inventory_item_id
-- NOT NULL — that's a data-integrity constraint change, not a
-- dead-code removal, and is out of scope for this cleanup.
--
-- Idempotent — safe to run whether or not Step 3 was already
-- applied by hand.
-- ============================================================

ALTER TABLE public.loan_items_master
  DROP COLUMN IF EXISTS item_name,
  DROP COLUMN IF EXISTS category,
  DROP COLUMN IF EXISTS unit;

  DROP FUNCTION IF EXISTS decrement_inventory_stock(UUID, NUMERIC);

ALTER TABLE public.crop_master
ADD COLUMN IF NOT EXISTS crop_type TEXT;

NOTIFY pgrst, 'reload schema';

-- Phase 6a: optional real contact email for Farmers and Buyers.
-- Distinct from auth.users.email, which stays the synthetic
-- "username@sagana.local" address used for login (see AuthService).
-- No format/uniqueness constraint yet — deferred to Phase 6b, when this
-- value starts actually gating authentication behavior.
ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS contact_email TEXT;

