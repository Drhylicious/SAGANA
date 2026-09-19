-- ============================================================
-- SAGANA — Phase 2: Widen broadcast_logs.recipient_type CHECK
-- ============================================================
-- The Dart RecipientType enum and the Compose UI both fully expose
-- allBuyers ('all_buyers') and specificBuyer ('specific_buyer'), but
-- broadcast_logs.recipient_type only ever allowed
-- ('all_members','outstanding_loans','specific_crop','specific_farmer').
-- Broadcasting to buyers still inserted the notifications successfully,
-- but the broadcast_logs audit-log insert then threw a constraint
-- violation, which the client silently swallowed — the admin saw a
-- false "Send failed" even though the buyers were notified.
-- ============================================================

ALTER TABLE public.broadcast_logs DROP CONSTRAINT IF EXISTS broadcast_logs_recipient_type_check;

ALTER TABLE public.broadcast_logs ADD CONSTRAINT broadcast_logs_recipient_type_check
  CHECK (recipient_type IN (
    'all_members', 'outstanding_loans', 'specific_crop', 'specific_farmer',
    'all_buyers', 'specific_buyer'
  ));

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conname = 'broadcast_logs_recipient_type_check';
-- -- expect all 6 values listed above
--
-- In-app: send a broadcast to "All Buyers" or a specific buyer and
-- confirm it now shows success (not "Send failed") and appears in
-- Broadcast History.
-- ============================================================
