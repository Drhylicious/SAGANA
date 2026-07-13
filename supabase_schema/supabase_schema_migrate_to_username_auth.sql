-- ============================================================
-- SAGANA — Migrate Existing Accounts to Username Auth
-- Run ONCE in Supabase SQL Editor.
-- 
-- What this does:
-- 1. Generates usernames for farmer/staff accounts that have none
-- 2. Updates auth.users.email to username@sagana.local format
-- 3. Stores original email in user_information for reference
-- 4. Leaves admin and buyer accounts unchanged (they keep real emails)
-- ============================================================

-- Step 1: Add original_email column to user_information if not exists
ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS original_email TEXT,
  ADD COLUMN IF NOT EXISTS username TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_information_username
  ON public.user_information (username)
  WHERE username IS NOT NULL;

-- Step 2: For every farmer/staff with no username, generate one
-- Uses full_name initials + user_id fragment as fallback
DO $$
DECLARE
  rec RECORD;
  v_username TEXT;
  v_counter  INT := 1;
  v_candidate TEXT;
  v_exists BOOLEAN;
BEGIN
  FOR rec IN
    SELECT ui.user_id, ui.full_name, au.email, ur.role
    FROM public.user_information ui
    JOIN public.user_roles ur ON ur.user_id = ui.user_id
    JOIN auth.users au ON au.id = ui.user_id
    WHERE ur.role IN ('farmer', 'staff')
      AND (ui.username IS NULL OR ui.username = '')
      AND au.email NOT LIKE '%@sagana.local'
  LOOP
    -- Determine prefix by role
    IF rec.role = 'staff' THEN
      -- Generate STF-XXXX
      SELECT COUNT(*) + 1 INTO v_counter
      FROM public.user_information
      WHERE username ILIKE 'stf-%';
      LOOP
        v_candidate := 'stf-' || lpad(v_counter::TEXT, 4, '0');
        SELECT EXISTS (
          SELECT 1 FROM public.user_information WHERE username = v_candidate
        ) INTO v_exists;
        EXIT WHEN NOT v_exists;
        v_counter := v_counter + 1;
      END LOOP;
    ELSE
      -- Generate SP3-XXXX
      SELECT COUNT(*) + 1 INTO v_counter
      FROM public.user_information
      WHERE username ILIKE 'sp3-%';
      LOOP
        v_candidate := 'sp3-' || lpad(v_counter::TEXT, 4, '0');
        SELECT EXISTS (
          SELECT 1 FROM public.user_information WHERE username = v_candidate
        ) INTO v_exists;
        EXIT WHEN NOT v_exists;
        v_counter := v_counter + 1;
      END LOOP;
    END IF;

    v_username := v_candidate;

    -- Store original email before changing it
    UPDATE public.user_information
    SET
      username       = v_username,
      original_email = rec.email
    WHERE user_id = rec.user_id;

    -- Update auth.users.email to username@sagana.local
    UPDATE auth.users
    SET email = v_username || '@sagana.local'
    WHERE id = rec.user_id;

    RAISE NOTICE 'Migrated % (%) → %@sagana.local',
      rec.full_name, rec.email, v_username;

  END LOOP;
END;
$$;

-- Step 3: Verify migration results
SELECT
  ui.full_name,
  ui.username,
  ui.original_email,
  au.email AS auth_email,
  ur.role,
  ur.status
FROM public.user_information ui
JOIN public.user_roles ur ON ur.user_id = ui.user_id
JOIN auth.users au ON au.id = ui.user_id
WHERE ur.role IN ('farmer', 'staff')
ORDER BY ui.created_at;