-- ============================================================
-- SAGANA — Connectivity reachability probe
-- Admin/Farmer/Buyer devices report ConnectivityResult.wifi as
-- soon as an interface is up, even when the pisonet link behind
-- it is dead — a real, documented condition in Barangay Payanas.
-- ConnectivityService's app-wide fix needs a cheap, dataless,
-- role-agnostic round trip to confirm actual reachability rather
-- than just interface presence. Granted to anon as well as
-- authenticated since this must also work before login (the
-- service can initialize before an auth session exists) and it
-- exposes zero data either way.
-- ============================================================

CREATE OR REPLACE FUNCTION ping()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$ SELECT true; $$;

GRANT EXECUTE ON FUNCTION ping() TO authenticated, anon;