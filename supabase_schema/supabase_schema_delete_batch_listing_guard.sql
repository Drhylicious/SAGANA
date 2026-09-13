-- Item B (Decision 2): block inventory batch deletion when an active
-- (pending_review / changes_required / approved) listing still references
-- it, rather than silently orphaning the listing via the existing
-- ON DELETE SET NULL foreign key. Mirrors delete_listing's own guard
-- pattern (RPC-enforced, not just app-layer).
--
-- 'rejected'/'withdrawn'/'sold' listings are intentionally NOT blockers —
-- those are terminal/inactive states where the batch reference no longer
-- represents a live commitment.

CREATE OR REPLACE FUNCTION public.delete_inventory_batch(p_batch_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_count INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM inventory_batches
    WHERE id = p_batch_id AND farmer_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Batch not found';
  END IF;

  SELECT COUNT(*) INTO v_active_count
    FROM marketplace_listings
    WHERE inventory_batch_id = p_batch_id
      AND status IN ('pending_review', 'changes_required', 'approved');

  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'This batch has % active listing(s) and cannot be deleted. Withdraw the listing first.', v_active_count;
  END IF;

  DELETE FROM inventory_batches WHERE id = p_batch_id AND farmer_id = auth.uid();
END;
$$;
