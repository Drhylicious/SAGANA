-- ============================================================
-- SAGANA — Which migration scripts are already applied? (READ-ONLY)
--
-- Run the whole file once in the Supabase SQL editor. It changes nothing. It
-- looks for ONE object that each script introduced (a table, column, function,
-- constraint or policy) and reports:
--   APPLIED              that object exists
--   NOT APPLIED          it does not
--   cannot be detected   the script only edits existing code or data, so there is
--                        no new object to look for (see the note in the list)
--
-- The step numbers match the execution list given with this file. Run only the
-- steps that say NOT APPLIED, in step order. Do NOT re-run an APPLIED step: most
-- scripts replace whole functions, and re-running an older one after a newer one
-- puts the older behaviour back.
-- ============================================================

CREATE OR REPLACE FUNCTION pg_temp.has_fn(n text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
                 WHERE s.nspname = 'public' AND p.proname = n) $$;
CREATE OR REPLACE FUNCTION pg_temp.has_tbl(n text) RETURNS boolean LANGUAGE sql AS $$
  SELECT to_regclass('public.' || n) IS NOT NULL $$;
CREATE OR REPLACE FUNCTION pg_temp.has_col(t text, c text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = t AND column_name = c) $$;
CREATE OR REPLACE FUNCTION pg_temp.has_con(n text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = n) $$;
CREATE OR REPLACE FUNCTION pg_temp.has_pol(t text, n text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = t AND policyname = n) $$;

WITH r(step, script, applied) AS (VALUES
  ( 1, 'batch0_01_suspension_end_date',            pg_temp.has_col('user_roles','suspended_until') AND pg_temp.has_fn('reactivate_expired_suspensions')),
  ( 2, 'batch0_02_order_rejected_and_cancellation',pg_temp.has_fn('cancel_my_order')),
  ( 3, 'batch0_03_missing_notices',                pg_temp.has_fn('fn_notify_listing_sold')),
  ( 4, 'batch0_04_drop_unused_place_order',        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'place_order' AND pronargs = 2)),
  ( 5, 'batch1_01_broadcast_preview',              pg_temp.has_fn('preview_broadcast_recipients')),
  ( 6, 'batch6_01_loan_payment_overpay_guard',     NULL::boolean),   -- edits record_loan_payment only
  ( 7, 'batch9_01_decision_notices',               pg_temp.has_col('orders','cancelled_by') AND pg_temp.has_fn('record_program_thriving_outcome')),
  ( 8, 'batch10_01_bod_and_failed_outcome',        pg_temp.has_fn('bod_next_meeting')),
  ( 9, 'batch11_01_buyer_order_pending_notice',    pg_temp.has_fn('fn_notify_buyer_order_pending')),
  (10, 'registration_01_foundation',               pg_temp.has_tbl('member_identifiers') AND pg_temp.has_fn('issue_member_identifier')),
  (11, 'registration_02_accounts_and_approval',    pg_temp.has_fn('register_account')),
  (12, 'registration_04_identifiers_phone_address',pg_temp.has_fn('dba_set_membership_year')),
  (13, 'registration_05_farmer_access_gate',       pg_temp.has_fn('enforce_active_farmer_write')),
  (14, 'registration_06_manager_wording',          pg_temp.has_fn('to_manager_wording')),
  (15, 'registration_07_email_uniqueness_registry_lock', pg_temp.has_fn('user_information_email_guard')),
  (16, 'registration_08_farmer_read_and_storage_gate',   pg_temp.has_fn('is_unapproved_applicant')),
  (17, 'registration_09_manager_wording_errors',   NULL::boolean),   -- rewrites message text only
  (18, 'registration_10_officer_forced_password_change', NULL::boolean), -- covered by step 33
  (19, 'registration_11_fixed_address_all_members',
        COALESCE((SELECT prosrc ILIKE '%buyer%' FROM pg_proc WHERE proname = 'buyer_addresses_farmer_fixed_area' LIMIT 1), false)),
  (20, 'inventory_source',                         pg_temp.has_col('cooperative_inventory','source')),
  (21, 'market_visibility',                        pg_temp.has_fn('can_access_cooperative_market')),
  (22, 'market_types_channels',                    pg_temp.has_tbl('market_types')),
  (23, 'market_rules_by_data',                     pg_temp.has_fn('can_view_market_type')),
  (24, 'order_wording_price_visibility',           pg_temp.has_fn('notifications_order_wording')),
  (25, 'listing_status_wording',                   pg_temp.has_fn('notifications_listing_wording')),
  (26, 'coop_offer_negotiation',                   pg_temp.has_tbl('cooperative_offer_events')),
  (27, 'order_number',                             pg_temp.has_col('orders','order_number')),
  (28, 'loan_reference_number',                    pg_temp.has_tbl('loan_reference_counters')),
  (29, 'units',                                    pg_temp.has_tbl('units')),
  (30, 'harvest_batch_number_and_units',           pg_temp.has_tbl('batch_number_counters')),
  (31, 'selling_channels_integrity',               pg_temp.has_fn('reconcile_after_informal_sale')),
  (32, 'farmer_add_unit',                          pg_temp.has_fn('limit_farmer_unit_additions')),
  (33, 'registration_12_name_components',          pg_temp.has_col('user_information','surname')),
  (34, 'registration_13_farm_address_parts',       pg_temp.has_col('farmer_profiles','farm_street')),
  (35, 'registration_18_contact_email_verification', pg_temp.has_tbl('contact_email_codes')),
  (36, 'registration_19_recovery_verified_email_only', pg_temp.has_fn('recovery_email_is_verified')),
  (37, 'registration_20_change_email_pending',     pg_temp.has_col('user_information','pending_contact_email')),
  (38, 'registration_21_login_verified_email_only',pg_temp.has_fn('auth_email_verified_only')),
  (39, 'remove_order_rejection',                   pg_temp.has_tbl('orders_rejection_backup')),
  (40, 'crop_photos_selling_rules',                pg_temp.has_col('farmer_crops','photo_captured_at')),
  (41, 'market_linking_partial_sales',             pg_temp.has_tbl('market_linking_sales')),
  (42, 'market_linking_buyer_cancellation',        pg_temp.has_fn('request_market_linking_cancellation')),
  (43, 'market_linking_visibility_and_ack',        pg_temp.has_col('da_amad_enrollments','acknowledged_at')),
  (44, 'marketplace_filter_counts_realtime',
        (SELECT count(*) FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime' AND tablename IN ('marketplace_listings','orders')) = 2),
  (45, 'stock_integrity',                          pg_temp.has_con('marketplace_listings_remaining_le_volume')),
  (46, 'farmer_stock_management',                  pg_temp.has_tbl('stock_movements')),
  (47, 'order_fulfillment_workflow',               pg_temp.has_col('orders','ready_at')),
  (48, 'officer_order_access',                     NULL::boolean),   -- edits approve_order only
  (49, 'cooperative_harvest_phase2',               pg_temp.has_tbl('cooperative_harvest_batches')),
  (50, 'guest_public_access',                      pg_temp.has_fn('public_marketplace_listings')),
  (51, 'farmer_listing_edit',                      NULL::boolean),   -- edits update_my_listing; step 54 supersedes part of it
  (52, 'ginger_any_unit',                          pg_temp.has_col('market_linking_programs','unit')),
  (53, 'notification_units',                       NULL::boolean),   -- patches message text of live functions
  (54, 'listing_edit_approval',                    pg_temp.has_tbl('listing_edit_requests')),
  (55, 'farmer_loan_requests',                     pg_temp.has_tbl('loan_requests')),
  (56, 'coop_sale_reference',                      pg_temp.has_tbl('coop_sale_reference_counters')),
  (57, 'loan_request_integrity_hardening',         pg_temp.has_con('cooperative_inventory_quantity_non_negative')),
  (58, 'buyer_suspension_removal',                 pg_temp.has_con('user_roles_buyer_never_suspended')),
  (59, 'officer_permissions_01_foundation',        pg_temp.has_tbl('officer_permissions') AND pg_temp.has_fn('staff_access_level')),
  (60, 'officer_permissions_02_enforcement',       pg_temp.has_tbl('staff_permission_targets') AND pg_temp.has_fn('staff_permission_gate')),
  (61, 'officer_permissions_03_broadcast_access',  pg_temp.has_pol('broadcast_logs','broadcast_logs: staff insert')),
  (62, 'officer_permissions_04_account_approval',  pg_temp.has_tbl('account_creation_requests')),
  (63, 'officer_permissions_05_accountability',    pg_temp.has_col('admin_activity_log','source')),
  (64, 'officer_permissions_06_enable_gate',
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator'
                AND rolconfig::text ILIKE '%pgrst.db_pre_request=public.staff_permission_gate%')),
  (68, 'old Officer account already deleted',
        NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '32dbca85-d93e-49bc-a468-06d08e70a6ed'))
)
SELECT step,
       script,
       CASE applied WHEN true  THEN 'APPLIED'
                    WHEN false THEN 'NOT APPLIED'
                    ELSE 'cannot be detected' END AS status
FROM r
ORDER BY step;

-- Also useful: scripts that are conditional or one-off leave their own evidence.
-- Copra still in the catalog (copra_delete not applied / not wanted):
--   SELECT crop_name, is_active FROM crop_master WHERE crop_name ILIKE '%copra%';
-- "Peanut Cookies" category still present:
--   SELECT * FROM inventory_categories WHERE name ILIKE '%peanut cookies%';
