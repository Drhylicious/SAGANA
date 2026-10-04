-- Removes the Harvest Entry Form's "Notes" field entirely, per explicit
-- product direction: it was a free-text catch-all ("Describe crop
-- conditions, humidity, weather, etc.") with no downstream use — not
-- surfaced in any report, filter, or admin workflow, only ever echoed
-- back on the two harvest-history detail sheets (Farmer and Admin). The
-- Dart side (harvest_entry_form_screen.dart, harvest_entry_repository.dart,
-- harvest_model.dart, harvest_repository.dart, both harvest-history
-- screens) no longer reads or writes it — this drops the column to match.
-- Any notes farmers already entered are lost; accepted per explicit
-- decision, same as supabase_schema_drop_quality_grade.sql.

ALTER TABLE public.harvest_records DROP COLUMN IF EXISTS notes;

NOTIFY pgrst, 'reload schema';
