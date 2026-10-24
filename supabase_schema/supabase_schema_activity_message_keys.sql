-- Structured Recent Activity messages for the profile, crop and home tables.
-- Each writer now stores a stable message_key plus message_params (jsonb),
-- next to the English copy in description. Readers render the key in the
-- user's language. Rows written before this migration have message_key NULL
-- and are matched back to a key from their English text in the app.
--
-- Safe to re-run. Apply before testing bilingual Recent Activity: writes that
-- include these columns fail until it has run.
--
-- Note: admin_activity_log is covered by supabase_schema_admin_activity_log_keys.sql.

alter table public.buyer_profile_activity
  add column if not exists message_key text,
  add column if not exists message_params jsonb;

alter table public.farmer_profile_activity
  add column if not exists message_key text,
  add column if not exists message_params jsonb;

alter table public.farmer_crop_activity
  add column if not exists message_key text,
  add column if not exists message_params jsonb;

alter table public.farmer_home_activity
  add column if not exists message_key text,
  add column if not exists message_params jsonb;
