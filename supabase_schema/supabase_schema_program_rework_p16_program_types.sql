-- ============================================================
-- SAGANA — Program Type: a managed list (Crop, Livestock, Processed Products, ...)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
--
-- WHY
--   Program Type used to be a free-text box. It is now a dropdown whose choices come from
--   a table, so the Manager or an Officer can add a new type ("+ Add New Program Type") and
--   it appears in the list straight away, with no app change. Program Purpose
--   (Distribution / Product Sales) is a separate field and is not touched.
--
-- WHAT IT DOES
--   1. Creates program_types (a lookup table, like inventory_categories) and seeds:
--        Crop, Livestock, Processed Products.
--      Every signed-in user may read the active ones; only the Manager or an Officer may add
--      or change them. The Officer permission gate treats it as a Dashboard table.
--   2. Sets the Program Type of the three programs that remain:
--        Peanut Seed Distribution  ->  Crop
--        Livestock Dispersal       ->  Livestock
--        Peanut Cookies            ->  Processed Products
--      Only the program_type column of those rows changes. Their members, enrollment
--      requests, outcomes, returns, purchases, products and History are untouched, and
--      Distribution / Product Sales (the Purpose) stays exactly as it is.
--
-- cooperative_programs.program_type stays plain text (it stores the type's name), so every
-- existing screen, filter and report that reads it keeps working.
--
-- Run the PREVIEW first (read-only) to see what each program has today.
-- ============================================================

-- PREVIEW (read-only)
SELECT program_name, program_purpose, program_type AS type_today
  FROM cooperative_programs ORDER BY program_name;

BEGIN;

CREATE TABLE IF NOT EXISTS public.program_types (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL UNIQUE CHECK (btrim(name) <> ''),
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- "crop" and "Crop" are the same type.
CREATE UNIQUE INDEX IF NOT EXISTS program_types_name_ci ON public.program_types (lower(btrim(name)));

DROP TRIGGER IF EXISTS trg_program_types_updated_at ON public.program_types;
CREATE TRIGGER trg_program_types_updated_at
  BEFORE UPDATE ON public.program_types
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.program_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "program_types: authenticated reads active" ON public.program_types;
CREATE POLICY "program_types: authenticated reads active" ON public.program_types
  FOR SELECT TO authenticated USING (is_active = TRUE);
DROP POLICY IF EXISTS "program_types: staff manage" ON public.program_types;
CREATE POLICY "program_types: staff manage" ON public.program_types
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());
REVOKE ALL ON public.program_types FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON public.program_types TO authenticated;

INSERT INTO public.program_types (name, sort_order) VALUES
  ('Crop', 1),
  ('Livestock', 2),
  ('Processed Products', 3)
ON CONFLICT DO NOTHING;

-- Adding a type is a Dashboard action for the Officer permission gate.
INSERT INTO public.staff_permission_targets (kind, name, module)
VALUES ('table', 'program_types', 'dashboard')
ON CONFLICT (kind, name) DO NOTHING;

-- The three remaining programs, by exact name. Only program_type changes.
UPDATE public.cooperative_programs SET program_type = 'Crop'
 WHERE program_name = 'Peanut Seed Distribution' AND program_type IS DISTINCT FROM 'Crop';
UPDATE public.cooperative_programs SET program_type = 'Livestock'
 WHERE program_name = 'Livestock Dispersal' AND program_type IS DISTINCT FROM 'Livestock';
UPDATE public.cooperative_programs SET program_type = 'Processed Products'
 WHERE program_name = 'Peanut Cookies' AND program_type IS DISTINCT FROM 'Processed Products';

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The list has the three starting types:
--     SELECT name, is_active FROM program_types ORDER BY sort_order;
-- V2  The three programs are classified, and their Purpose did not change:
--     SELECT program_name, program_type, program_purpose, status FROM cooperative_programs ORDER BY program_name;
-- V3  Nothing else moved (same counts as before):
--     SELECT count(*) FROM program_members WHERE status = 'active';   -- 6
