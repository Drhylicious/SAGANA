-- ============================================================
-- SAGANA — Remove Buyer suspension (Buyers are Active / Inactive only)
--
-- NOT EXECUTED. Run each BLOCK on its own, in order.
--
-- WHAT THIS CHANGES IN THE DATABASE
--   1. Any Buyer who is currently Suspended is set back to Active (reason and
--      end date cleared), with one history row per Buyer in member_status_events
--      saying the Buyer suspension feature was removed.
--   2. A CHECK constraint on user_roles makes it impossible for a Buyer's status
--      to be 'suspended' from now on, whichever screen, RPC or script tries.
--      suspend_member() is NOT rewritten: called for a Buyer it now fails on that
--      constraint. Farmers are unaffected (their suspension stays as it is).
--
-- WHAT IS DELIBERATELY NOT CHANGED
--   * Farmer suspension: suspend_member / reactivate_member, the status value and
--     the columns suspension_reason / suspended_until.
--   * place_order(): its "account suspended" check is the caller's own status and
--     also serves Farmers who buy; it can never trigger for a Buyer again.
--   * History: old member_status_events rows and old Recent Activity messages
--     that say a Buyer was suspended stay as they are. Their wording keeps
--     working because the app keeps the message text.
--   * Inactive: still derived from last activity (30 days) and never stored.
--
-- Run this BEFORE releasing the app build that removes the Buyer suspension
-- screens, so no Buyer is left Suspended with no way to reactivate them.
-- ============================================================


-- ─── BLOCK 1 — WHAT EXISTS TODAY (read-only). Run first. ───────────────────

-- 1a. Buyers by stored status:
SELECT status, count(*) FROM public.user_roles WHERE role = 'buyer' GROUP BY status ORDER BY status;

-- 1b. The Suspended Buyers that Block 2 will reactivate:
SELECT r.user_id, ui.full_name, ui.username, r.suspension_reason, r.suspended_until, r.updated_at
FROM public.user_roles r
LEFT JOIN public.user_information ui ON ui.user_id = r.user_id
WHERE r.role = 'buyer' AND r.status = 'suspended'
ORDER BY r.updated_at;

-- 1c. Buyer suspension history that will be KEPT (not deleted):
SELECT count(*) AS buyer_suspension_history_rows
FROM public.member_status_events e
JOIN public.user_roles r ON r.user_id = e.member_id AND r.role = 'buyer'
WHERE e.to_status = 'suspended';

-- 1d. Any existing rule on user_roles.status (the new CHECK is added next to it):
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.user_roles'::regclass AND contype = 'c';


-- ─── BLOCK 2 — APPLY (one transaction). ────────────────────────────────────

BEGIN;

-- 2a. Reactivate every suspended Buyer, and record it.
INSERT INTO public.member_status_events (member_id, from_status, to_status, reason, actor_id)
SELECT r.user_id, 'suspended', 'active',
       'Buyer suspension was removed from SAGANA; account set to Active', NULL
FROM public.user_roles r
WHERE r.role = 'buyer' AND r.status = 'suspended';

UPDATE public.user_roles
SET status = 'active',
    suspension_reason = NULL,
    suspended_until = NULL
WHERE role = 'buyer' AND status = 'suspended';

-- 2b. From now on a Buyer can never be Suspended.
ALTER TABLE public.user_roles
  DROP CONSTRAINT IF EXISTS user_roles_buyer_never_suspended;
ALTER TABLE public.user_roles
  ADD CONSTRAINT user_roles_buyer_never_suspended
  CHECK (NOT (role = 'buyer' AND status = 'suspended'));

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ─── BLOCK 3 — VERIFY (read-only). ─────────────────────────────────────────
-- Expect: 0 suspended Buyers; the constraint is listed.

SELECT count(*) AS suspended_buyers_left
FROM public.user_roles WHERE role = 'buyer' AND status = 'suspended';

SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.user_roles'::regclass AND conname = 'user_roles_buyer_never_suspended';

-- Expect an error mentioning user_roles_buyer_never_suspended (nothing is saved):
--   BEGIN;
--   UPDATE public.user_roles SET status = 'suspended'
--   WHERE user_id = (SELECT user_id FROM public.user_roles WHERE role = 'buyer' LIMIT 1);
--   ROLLBACK;
