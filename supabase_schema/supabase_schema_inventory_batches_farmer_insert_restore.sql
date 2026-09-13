-- ============================================================
-- SAGANA — M-8 hotfix. M-8 correctly narrowed the farmer policy
-- on inventory_batches from FOR ALL to SELECT-only, to close the
-- raw UPDATE/DELETE path around the reservation RPCs. It did not
-- account for harvest_entry_repository.dart's batch creation,
-- which does a raw client INSERT by design (never wrapped in an
-- RPC) — breaking every new harvest entry (403 on POST).
--
-- This restores INSERT only, with the exact same WITH CHECK
-- condition the original FOR ALL policy had. UPDATE and DELETE
-- remain closed — those stay RPC-only, which was M-8's actual
-- and still-correct intent.
-- ============================================================

CREATE POLICY "inventory_batches: farmer creates own"
  ON public.inventory_batches FOR INSERT
  WITH CHECK (auth.uid() = farmer_id);