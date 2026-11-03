-- ============================================================
-- SAGANA — Officer permissions, script 9: DELETE DISAPPROVED ACCOUNTS (Manager only)
--
-- Replaces admin_delete_rejected_applicant(). Requires script 01 (is_manager()).
-- Best run after script 08.
--
-- THE RULES
--   * Only the MANAGER may permanently delete a disapproved account. Today the
--     function checks is_platform_admin(), which also accepts an Officer who
--     manages Members; that is why an Officer could delete rejected applicants.
--     It now checks is_manager().
--   * It applies to every disapproved Farmer: self-registered applicants and
--     Farmers an Officer created. (Status 'rejected' is shown as "Disapproved".)
--   * It refuses when the account owns any genuine financial or transaction
--     history. Every table that stores user data cascades on delete, so without
--     this check a delete would silently erase it. The check no longer treats the
--     empty capital-shares row that every Officer-created Farmer has as a record
--     (only a balance above zero, or any contribution / capital event, counts).
--   * Before deleting it writes ONE accountability entry to admin_activity_log
--     (source 'db', shown in Staff Accountability to the Manager): who created the
--     account and when, who disapproved it, when and why, and who deleted it. The
--     account's own request and status-history rows are removed with it by the
--     cascade, so that entry is what keeps the record.
--
-- WHAT IS NOT DELETED: genuine history is never deleted — the account is refused
-- instead. Tables that are missing in a database are skipped.
--
-- Not applied automatically. Run in the Supabase SQL editor. Re-runnable.
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_manager() is missing. Run officer_permissions_01 first.';
  END IF;
END $$;

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_delete_rejected_applicant(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_role_count  integer;
  v_role        text;
  v_status      text;
  v_pair        record;
  v_n           bigint;
  v_found       text := '';
  v_name        text;
  v_username    text;
  v_deleter     text;
  v_created_by  text;
  v_created_role text;
  v_created_at  timestamptz;
  v_decided_by  text;
  v_decided_role text;
  v_decided_at  timestamptz;
  v_reason      text;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Only the Manager can delete a disapproved account.';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot delete your own account';
  END IF;

  SELECT count(*) INTO v_role_count FROM user_roles WHERE user_id = p_user_id;
  SELECT role, status, rejection_reason INTO v_role, v_status, v_reason
  FROM user_roles WHERE user_id = p_user_id;

  IF v_role_count <> 1 OR v_role <> 'farmer' OR v_status <> 'rejected' THEN
    RAISE EXCEPTION 'Only disapproved farmer accounts can be deleted';
  END IF;

  -- Genuine history is never deleted. (table, column that holds the account's id)
  FOR v_pair IN
    SELECT * FROM (VALUES
      ('harvest_records', 'farmer_id'),
      ('orders', 'farmer_id'),
      ('orders', 'buyer_id'),
      ('farmer_loans', 'farmer_id'),
      ('loan_requests', 'farmer_id'),
      ('capital_contribution_events', 'farmer_id'),
      ('member_contributions', 'farmer_id'),
      ('member_sales_transactions', 'farmer_id'),
      ('informal_sales', 'farmer_id'),
      ('farmer_expenses', 'farmer_id'),
      ('marketplace_listings', 'farmer_id'),
      ('listing_edit_requests', 'farmer_id'),
      ('cooperative_purchase_offers', 'farmer_id'),
      ('market_linking_programs', 'farmer_id'),
      ('market_linking_sales', 'farmer_id'),
      ('da_amad_enrollments', 'farmer_id'),
      ('program_members', 'farmer_id'),
      ('program_enrollment_requests', 'farmer_id'),
      ('program_product_purchases', 'farmer_id'),
      ('stock_movements', 'farmer_id'),
      ('inventory_batches', 'farmer_id'),
      ('crop_requests', 'farmer_id')
    ) AS t(tbl, col)
  LOOP
    IF to_regclass('public.' || quote_ident(v_pair.tbl)) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I WHERE %I = $1', v_pair.tbl, v_pair.col)
        INTO v_n USING p_user_id;
      IF v_n > 0 THEN
        v_found := v_found || CASE WHEN v_found = '' THEN '' ELSE ', ' END
                   || v_pair.tbl || ' (' || v_n || ')';
      END IF;
    END IF;
  END LOOP;

  -- A capital-shares row at 0 is not a record; a balance above 0 is.
  IF to_regclass('public.member_capital_shares') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM public.member_capital_shares WHERE farmer_id = $1 AND COALESCE(total_contribution, 0) > 0'
      INTO v_n USING p_user_id;
    IF v_n > 0 THEN
      v_found := v_found || CASE WHEN v_found = '' THEN '' ELSE ', ' END || 'member_capital_shares (balance)';
    END IF;
  END IF;

  IF v_found <> '' THEN
    RAISE EXCEPTION 'This account has records that must be kept (%) and cannot be deleted.', v_found;
  END IF;

  -- ── The accountability entry (written before the rows are removed) ──────────
  SELECT ui.full_name, ui.username INTO v_name, v_username
  FROM user_information ui WHERE ui.user_id = p_user_id;

  SELECT full_name INTO v_deleter FROM user_information WHERE user_id = auth.uid();

  SELECT r.requested_by_name, r.requested_by_role, r.requested_at
  INTO v_created_by, v_created_role, v_created_at
  FROM account_creation_requests r WHERE r.user_id = p_user_id;

  SELECT e.actor_name, e.actor_role, e.created_at, COALESCE(e.reason, v_reason)
  INTO v_decided_by, v_decided_role, v_decided_at, v_reason
  FROM member_status_events e
  WHERE e.member_id = p_user_id AND e.to_status = 'rejected'
  ORDER BY e.created_at DESC LIMIT 1;

  INSERT INTO admin_activity_log (
    admin_id, module, action_type, description, reference_id,
    actor_role, actor_name, table_name, operation, record_id, reference_label,
    old_values, new_values, source
  ) VALUES (
    auth.uid(), 'members', 'deleted',
    'Deleted a disapproved account: ' || COALESCE(v_name, p_user_id::text),
    p_user_id,
    'admin', v_deleter, 'user_roles', 'deleted', p_user_id::text, v_name,
    jsonb_build_object(
      'username',        v_username,
      'full_name',       v_name,
      'created_by',      COALESCE(v_created_by, 'Self-registered'),
      'created_by_role', COALESCE(v_created_role, 'applicant'),
      'created_at',      v_created_at,
      'disapproved_by',  v_decided_by,
      'disapproved_role', v_decided_role,
      'disapproved_at',  v_decided_at,
      'reason',          v_reason
    ),
    NULL,
    'db'
  );

  DELETE FROM auth.users WHERE id = p_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_rejected_applicant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_rejected_applicant(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- The function now checks is_manager():
--   SELECT prosrc ILIKE '%is_manager()%' AS manager_only
--   FROM pg_proc WHERE proname = 'admin_delete_rejected_applicant';          -- expect true
-- After a real deletion, the Manager sees the entry in Staff Accountability, or:
--   SELECT actor_name, description, old_values FROM admin_activity_log
--   WHERE action_type = 'deleted' AND module = 'members' ORDER BY created_at DESC LIMIT 5;
-- ─────────────────────────────────────────────────────────────────────────
