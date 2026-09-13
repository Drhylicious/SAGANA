-- One-time data fix — run this once, immediately, to unblock the existing
-- stf-0001 account. This does NOT prevent the bug from recurring; run
-- supabase_schema_create_account_missing_identity_fix.sql as well so
-- future accounts created via create_staff_account()/create_farmer_account()
-- get their identities row automatically.

-- Note: 'email' is a generated column on auth.identities
-- (GENERATED ALWAYS AS (lower(identity_data->>'email')) STORED), derived
-- automatically from identity_data — do not insert into it directly.

INSERT INTO auth.identities (
  provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) VALUES (
  '32dbca85-d93e-49bc-a468-06d08e70a6ed',
  '32dbca85-d93e-49bc-a468-06d08e70a6ed',
  jsonb_build_object(
    'sub', '32dbca85-d93e-49bc-a468-06d08e70a6ed',
    'email', 'stf-0001@sagana.local',
    'email_verified', false,
    'phone_verified', false
  ),
  'email', NOW(), NOW(), NOW()
);

-- Diagnostic: find every other existing account with the same missing-
-- identity problem, so you know exactly who else needs this same one-time
-- fix before it reaches real SP3 users. sp3-0001 working was never
-- evidence the RPC path was fine — it's evidence that account didn't go
-- through the RPC path at all (e.g. self-registration via
-- AuthService.register(), which calls Supabase's real signUp() and
-- creates the identity row correctly on its own).

SELECT u.id, u.email
FROM auth.users u
LEFT JOIN auth.identities i ON i.user_id = u.id
WHERE i.id IS NULL;
