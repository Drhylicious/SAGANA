-- ============================================================
-- SAGANA — Clean-slate Mr. Salangsang's Market Linking test data
-- (Market Linking / DA-AMAD Enrollment revision round)
--
-- After the underlying data got reset, Mr. Salangsang
-- (farmer_id a98f740c-8aff-43ce-8183-6188266b7d25) ended up in an
-- inconsistent mixed state: a fresh 'pending' da_amad_enrollments row
-- from testing the new Enrollment flow, alongside leftover
-- market_linking_programs test rows (Submitted/Completed) from testing
-- the flow before Enrollment existed. Removes ALL of this one farmer's
-- rows in both tables so Market Linking starts clean for him — scoped
-- strictly to his farmer_id, nothing else is touched.
-- ============================================================

-- Run this SELECT first if you want to see exactly what will be removed
-- before running the DELETEs below:
--
-- SELECT id, status, crop_name, buyer_name, submitted_at
-- FROM market_linking_programs
-- WHERE farmer_id = 'a98f740c-8aff-43ce-8183-6188266b7d25';
--
-- SELECT id, status, admin_notes, submitted_at
-- FROM da_amad_enrollments
-- WHERE farmer_id = 'a98f740c-8aff-43ce-8183-6188266b7d25';

BEGIN;

DELETE FROM public.market_linking_programs
WHERE farmer_id = 'a98f740c-8aff-43ce-8183-6188266b7d25';

DELETE FROM public.da_amad_enrollments
WHERE farmer_id = 'a98f740c-8aff-43ce-8183-6188266b7d25';

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- Both should return zero rows:
--
-- SELECT * FROM market_linking_programs
-- WHERE farmer_id = 'a98f740c-8aff-43ce-8183-6188266b7d25';
--
-- SELECT * FROM da_amad_enrollments
-- WHERE farmer_id = 'a98f740c-8aff-43ce-8183-6188266b7d25';
--
-- In the app: Admin's Market Linking Overview KPIs should all read 0/empty
-- for anything tied to this farmer, and his own My Market Linking screen
-- should show the "no Ginger yet" or "enroll now" starting state again
-- (whichever applies given his current Crop Roster).
