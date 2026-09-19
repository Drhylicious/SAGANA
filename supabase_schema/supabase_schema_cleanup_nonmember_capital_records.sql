-- ============================================================
-- SAGANA — Clean Up Capital Records for Non-Member Accounts
-- (Admin-Report tab / Balik-Tangkilik review — Phase 5)
--
-- Draft and rejected accounts get a farmer_profiles row at registration,
-- before any admin review (create_farmer_account / self-registration —
-- see supabase_schema_username_auth.sql). reject_member() explicitly
-- never removes it: its own comment states "account stays listed,
-- farmer access NOT granted" (supabase_schema_phase_c_application_
-- lifecycle.sql). Any capital_contribution_events / member_capital_shares
-- rows recorded against such an account (test data, or a payment
-- recorded before rejection) never represented a real cooperative
-- member's capital and should not remain in the ledger.
--
-- Suspended accounts are deliberately EXCLUDED from this cleanup — they
-- were previously APPROVED members with real, legitimate contribution
-- history. The Loan module's own precedent (Record Payment's farmer
-- search deliberately keeps a suspended member's existing loans
-- reachable rather than hiding them) is the model followed here: only
-- 'draft' and 'rejected' never became real members, so only those two
-- statuses are cleaned up.
--
-- This is a companion to the query-level fix already applied to
-- BalikTangkilikRepository.fetchDistributionPreview(),
-- AdminReportsRepository.fetchMemberContributionReport(), and
-- AdminAnalyticsRepository.fetchMemberParticipation() (all three now
-- filter to user_roles.status = 'active' before reading farmer_profiles).
-- This migration additionally removes the underlying bad data so no
-- future, not-yet-audited query path can resurface it.
--
-- ============================================================
-- RUN THE PREVIEW QUERY BELOW FIRST, BEFORE running this migration,
-- to see exactly which accounts and rows will be affected:
--
--   SELECT ur.user_id, ur.status, ui.full_name,
--          (SELECT COUNT(*) FROM capital_contribution_events cce
--             WHERE cce.farmer_id = ur.user_id) AS contribution_events,
--          (SELECT total_contribution FROM member_capital_shares mcs
--             WHERE mcs.farmer_id = ur.user_id) AS capital_balance
--   FROM user_roles ur
--   JOIN user_information ui ON ui.user_id = ur.user_id
--   WHERE ur.role = 'farmer' AND ur.status IN ('draft', 'rejected');
-- ============================================================

BEGIN;

DELETE FROM public.capital_contribution_events cce
WHERE cce.farmer_id IN (
  SELECT ur.user_id FROM public.user_roles ur
  WHERE ur.role = 'farmer' AND ur.status IN ('draft', 'rejected')
);

DELETE FROM public.member_capital_shares mcs
WHERE mcs.farmer_id IN (
  SELECT ur.user_id FROM public.user_roles ur
  WHERE ur.role = 'farmer' AND ur.status IN ('draft', 'rejected')
);

COMMIT;

-- ============================================================
-- POST-RUN VERIFICATION
-- ============================================================
-- Confirm zero rows remain for draft/rejected accounts:
--   SELECT COUNT(*) FROM capital_contribution_events cce
--   JOIN user_roles ur ON ur.user_id = cce.farmer_id
--   WHERE ur.status IN ('draft', 'rejected');
--   -- expect 0
--
-- Confirm active and suspended members' data is untouched:
--   SELECT ur.status, COUNT(*) FROM member_capital_shares mcs
--   JOIN user_roles ur ON ur.user_id = mcs.farmer_id
--   GROUP BY ur.status;
--   -- expect rows only for 'active' and 'suspended', with unchanged counts
