-- ============================================================
-- SAGANA — Remove old admin-direct Market Linking test data
-- (Ginger / DA-AMAD Market Linking revision round)
--
-- The old admin-direct enrollment flow (enrollFarmer() / startNewRound(),
-- both removed from the app in this same revision round) inserted rows
-- directly at created_by = the ADMIN's own user id, bypassing the
-- farmer's own Submit to Sell -> 'requested' -> Approve/Decline path.
-- The new flow (submitRequest()) always sets created_by = the farmer's
-- own uid, identical to farmer_id.
--
-- Verified with the user before writing this migration — the read-only
-- query below returned exactly one row:
--   id 6ff32bfc-6c89-4592-bafe-d1b0a09ee328, farmer_id a98f740c-...,
--   crop_name Ginger, status submitted, created_by d4e0e668-... (an
--   admin id, not the farmer's), submitted_at 2026-09-13.
-- Status was 'submitted', never buyer_found/completed, so no
-- inventory_batches.available_kg or sales-channel data was ever touched
-- by it — nothing else references this row.
-- ============================================================

BEGIN;

DELETE FROM public.market_linking_programs
WHERE created_by IS DISTINCT FROM farmer_id;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) The old row is gone, and no other rows were caught by the same
--    condition (i.e. every remaining row genuinely came from a farmer's
--    own request):
--    SELECT id, farmer_id, crop_name, status, created_by, submitted_at
--    FROM market_linking_programs
--    WHERE created_by IS DISTINCT FROM farmer_id;
--    -- expect zero rows
--
-- 2) Nothing else changed — row count dropped by exactly 1:
--    SELECT COUNT(*) FROM market_linking_programs;
--
-- 3) Farmer-side My Market Linking screen for that farmer (a98f740c-...)
--    no longer shows the removed entry; Admin's Market Linking screen
--    KPI counts (Enrolled/Submitted/etc.) drop accordingly.
