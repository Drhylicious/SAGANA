-- ============================================================
-- SAGANA — Replace generic seeded programs with the real ones
-- identified in the stakeholder interview. Renames in place
-- where a program maps cleanly (preserves any existing
-- enrollments/activities); the two that don't correspond to
-- anything real are removed and replaced.
-- ============================================================

UPDATE public.cooperative_programs
SET program_name = 'Peanut Seed Distribution',
    description = 'SP3 distributes peanut seeds to members ahead of the next planting season.'
WHERE program_name = 'Peanut Program';

UPDATE public.cooperative_programs
SET program_name = 'Livestock Dispersal',
    description = 'Members receive livestock from SP3 and return a percentage of proceeds to the cooperative after selling.'
WHERE program_name = 'Livestock Program';

-- Neither of these corresponds to a program the cooperative actually runs.
DELETE FROM public.cooperative_programs WHERE program_name IN ('Crop Program', 'Production Program');

INSERT INTO public.cooperative_programs (program_name, program_type, description, season_year) VALUES
  ('Government Seed Distribution', 'government', 'Seeds from the Municipal Agriculture Office, distributed by SP3 to eligible farmers.', EXTRACT(YEAR FROM NOW())::INT),
  ('Government Fertilizer Distribution', 'government', 'Fertilizer from the Municipal Agriculture Office, distributed by SP3 to eligible farmers.', EXTRACT(YEAR FROM NOW())::INT)
ON CONFLICT (program_name) DO NOTHING;