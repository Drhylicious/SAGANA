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