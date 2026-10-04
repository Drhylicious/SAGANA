-- Staff access by user role, not by the Admin profile row.
--
-- Staff (Admin or Officer, by user_roles.role) may use module features.
-- Admin-only actions (member and account management, the Balik payout, the
-- admin-only tables) use the Admin role alone.
-- Officer accounts no longer receive an admin profile row.
-- Expense categories: only farmers may add them.
--
-- Not applied automatically. Run in the Supabase SQL editor.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = auth.uid() AND r.role IN ('admin', 'officer'));
$$;

-- 1. Policies: check the role, not the admin profile row.
DROP POLICY IF EXISTS "admin_activity_log: admin inserts own" ON public.admin_activity_log;
CREATE POLICY "admin_activity_log: admin inserts own" ON public.admin_activity_log FOR INSERT TO public WITH CHECK (((admin_id = auth.uid()) AND (public.is_staff())));
DROP POLICY IF EXISTS "admin_activity_log: admin reads all" ON public.admin_activity_log;
CREATE POLICY "admin_activity_log: admin reads all" ON public.admin_activity_log FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (delete)" ON public.broadcast_logs;
CREATE POLICY "Admin full access to broadcast_logs (delete)" ON public.broadcast_logs FOR DELETE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (insert)" ON public.broadcast_logs;
CREATE POLICY "Admin full access to broadcast_logs (insert)" ON public.broadcast_logs FOR INSERT TO public WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (read)" ON public.broadcast_logs;
CREATE POLICY "Admin full access to broadcast_logs (read)" ON public.broadcast_logs FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (update)" ON public.broadcast_logs;
CREATE POLICY "Admin full access to broadcast_logs (update)" ON public.broadcast_logs FOR UPDATE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid())))))) WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "cooperative_annual_totals: admin manages all (delete)" ON public.cooperative_annual_totals;
CREATE POLICY "cooperative_annual_totals: admin manages all (delete)" ON public.cooperative_annual_totals FOR DELETE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "cooperative_annual_totals: admin manages all (insert)" ON public.cooperative_annual_totals;
CREATE POLICY "cooperative_annual_totals: admin manages all (insert)" ON public.cooperative_annual_totals FOR INSERT TO public WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "cooperative_annual_totals: admin manages all (read)" ON public.cooperative_annual_totals;
CREATE POLICY "cooperative_annual_totals: admin manages all (read)" ON public.cooperative_annual_totals FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "cooperative_annual_totals: admin manages all (update)" ON public.cooperative_annual_totals;
CREATE POLICY "cooperative_annual_totals: admin manages all (update)" ON public.cooperative_annual_totals FOR UPDATE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid())))))) WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "cooperative_inventory: admin manages all" ON public.cooperative_inventory;
CREATE POLICY "cooperative_inventory: admin manages all" ON public.cooperative_inventory FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "cooperative_programs: admin manages all" ON public.cooperative_programs;
CREATE POLICY "cooperative_programs: admin manages all" ON public.cooperative_programs FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "coop_offers: admin manages all" ON public.cooperative_purchase_offers;
CREATE POLICY "coop_offers: admin manages all" ON public.cooperative_purchase_offers FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "crop_categories: admin manages all" ON public.crop_categories;
CREATE POLICY "crop_categories: admin manages all" ON public.crop_categories FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "crop_master: admin manages all" ON public.crop_master;
CREATE POLICY "crop_master: admin manages all" ON public.crop_master FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "crop_requests: admin manages all" ON public.crop_requests;
CREATE POLICY "crop_requests: admin manages all" ON public.crop_requests FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "da_amad_enrollments: admin manages all" ON public.da_amad_enrollments;
CREATE POLICY "da_amad_enrollments: admin manages all" ON public.da_amad_enrollments FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "expense_categories: admin manages all (delete)" ON public.expense_categories;
DROP POLICY IF EXISTS "expense_categories: admin manages all (insert)" ON public.expense_categories;
DROP POLICY IF EXISTS "expense_categories: admin manages all (read)" ON public.expense_categories;
DROP POLICY IF EXISTS "expense_categories: admin manages all (update)" ON public.expense_categories;
DROP POLICY IF EXISTS "farm_ownership_types: admin manages all (delete)" ON public.farm_ownership_types;
CREATE POLICY "farm_ownership_types: admin manages all (delete)" ON public.farm_ownership_types FOR DELETE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "farm_ownership_types: admin manages all (insert)" ON public.farm_ownership_types;
CREATE POLICY "farm_ownership_types: admin manages all (insert)" ON public.farm_ownership_types FOR INSERT TO public WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "farm_ownership_types: admin manages all (read)" ON public.farm_ownership_types;
CREATE POLICY "farm_ownership_types: admin manages all (read)" ON public.farm_ownership_types FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "farm_ownership_types: admin manages all (update)" ON public.farm_ownership_types;
CREATE POLICY "farm_ownership_types: admin manages all (update)" ON public.farm_ownership_types FOR UPDATE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid())))))) WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "farmer_crops: admin reads all" ON public.farmer_crops;
CREATE POLICY "farmer_crops: admin reads all" ON public.farmer_crops FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "farmer_dashboard_settings: admin update" ON public.farmer_dashboard_settings;
CREATE POLICY "farmer_dashboard_settings: admin update" ON public.farmer_dashboard_settings FOR UPDATE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid())))))) WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "farmer_expenses: admin reads all" ON public.farmer_expenses;
CREATE POLICY "farmer_expenses: admin reads all" ON public.farmer_expenses FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "farmer_loan_items: admin manages all" ON public.farmer_loan_items;
CREATE POLICY "farmer_loan_items: admin manages all" ON public.farmer_loan_items FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "farmer_loan_payments: admin manages all" ON public.farmer_loan_payments;
CREATE POLICY "farmer_loan_payments: admin manages all" ON public.farmer_loan_payments FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "farmer_loans: admin manages all" ON public.farmer_loans;
CREATE POLICY "farmer_loans: admin manages all" ON public.farmer_loans FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "harvest_records: admin reads all" ON public.harvest_records;
CREATE POLICY "harvest_records: admin reads all" ON public.harvest_records FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "informal_sales: admin reads all" ON public.informal_sales;
CREATE POLICY "informal_sales: admin reads all" ON public.informal_sales FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "inventory_batches: admin reads all" ON public.inventory_batches;
CREATE POLICY "inventory_batches: admin reads all" ON public.inventory_batches FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "inventory_categories: admin manages all" ON public.inventory_categories;
CREATE POLICY "inventory_categories: admin manages all" ON public.inventory_categories FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "inventory_transactions: admin manages all" ON public.inventory_transactions;
CREATE POLICY "inventory_transactions: admin manages all" ON public.inventory_transactions FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "loan_items_master: admin manages all" ON public.loan_items_master;
CREATE POLICY "loan_items_master: admin manages all" ON public.loan_items_master FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "loan_policy_settings: admin reads" ON public.loan_policy_settings;
CREATE POLICY "loan_policy_settings: admin reads" ON public.loan_policy_settings FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "Admin full access to market_linking_programs" ON public.market_linking_programs;
CREATE POLICY "Admin full access to market_linking_programs" ON public.market_linking_programs FOR ALL TO public USING ((public.is_staff())) WITH CHECK ((public.is_staff()));
DROP POLICY IF EXISTS "marketplace_listings: admin manages all" ON public.marketplace_listings;
CREATE POLICY "marketplace_listings: admin manages all" ON public.marketplace_listings FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "member_contributions: admin manages all (delete)" ON public.member_contributions;
CREATE POLICY "member_contributions: admin manages all (delete)" ON public.member_contributions FOR DELETE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "member_contributions: admin manages all (insert)" ON public.member_contributions;
CREATE POLICY "member_contributions: admin manages all (insert)" ON public.member_contributions FOR INSERT TO public WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "member_contributions: admin manages all (read)" ON public.member_contributions;
CREATE POLICY "member_contributions: admin manages all (read)" ON public.member_contributions FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "member_contributions: admin manages all (update)" ON public.member_contributions;
CREATE POLICY "member_contributions: admin manages all (update)" ON public.member_contributions FOR UPDATE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid())))))) WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "member_sales_transactions: admin manages all" ON public.member_sales_transactions;
CREATE POLICY "member_sales_transactions: admin manages all" ON public.member_sales_transactions FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "Admin insert notifications" ON public.notifications;
CREATE POLICY "Admin insert notifications" ON public.notifications FOR INSERT TO public WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "notifications: admin reads all" ON public.notifications;
CREATE POLICY "notifications: admin reads all" ON public.notifications FOR SELECT TO public USING (((auth.uid() = user_id) OR (public.is_staff())));
DROP POLICY IF EXISTS "Admin full access to orders" ON public.orders;
CREATE POLICY "Admin full access to orders" ON public.orders FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "password_reset_requests: admin reads all" ON public.password_reset_requests;
CREATE POLICY "password_reset_requests: admin reads all" ON public.password_reset_requests FOR SELECT TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "password_reset_requests: admin updates" ON public.password_reset_requests;
CREATE POLICY "password_reset_requests: admin updates" ON public.password_reset_requests FOR UPDATE TO public USING (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid())))))) WITH CHECK (((public.is_platform_admin(auth.uid())) AND (NOT (EXISTS ( SELECT 1 FROM officer_profiles o WHERE (o.user_id = auth.uid()))))));
DROP POLICY IF EXISTS "Admin full access to price_records" ON public.price_records;
CREATE POLICY "Admin full access to price_records" ON public.price_records FOR ALL TO public USING ((public.is_staff())) WITH CHECK ((public.is_staff()));
DROP POLICY IF EXISTS "price_records: admin inserts" ON public.price_records;
CREATE POLICY "price_records: admin inserts" ON public.price_records FOR INSERT TO public WITH CHECK ((public.is_staff()));
DROP POLICY IF EXISTS "price_records: admin updates" ON public.price_records;
CREATE POLICY "price_records: admin updates" ON public.price_records FOR UPDATE TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "program_activities: admin manages all" ON public.program_activities;
CREATE POLICY "program_activities: admin manages all" ON public.program_activities FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "program_enrollment_requests: admin manages all" ON public.program_enrollment_requests;
CREATE POLICY "program_enrollment_requests: admin manages all" ON public.program_enrollment_requests FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "program_members: admin manages all" ON public.program_members;
CREATE POLICY "program_members: admin manages all" ON public.program_members FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "program_product_purchases: admin manages all" ON public.program_product_purchases;
CREATE POLICY "program_product_purchases: admin manages all" ON public.program_product_purchases FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "program_products: admin manages all" ON public.program_products;
CREATE POLICY "program_products: admin manages all" ON public.program_products FOR ALL TO public USING ((public.is_staff()));
DROP POLICY IF EXISTS "user_roles: admin reads all" ON public.user_roles;
CREATE POLICY "user_roles: admin reads all" ON public.user_roles FOR SELECT TO public USING ((public.is_staff()));

-- 2. Functions: check the role, not the admin profile row.
-- adjust_inventory_stock
CREATE OR REPLACE FUNCTION public.adjust_inventory_stock(p_inventory_id uuid, p_quantity numeric, p_transaction_type text, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current NUMERIC;
  v_new NUMERIC;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can adjust cooperative inventory stock';
  END IF;

  SELECT quantity_on_hand INTO v_current
    FROM cooperative_inventory
    WHERE id = p_inventory_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_id;
  END IF;

  v_new := GREATEST(v_current + p_quantity, 0);

  UPDATE cooperative_inventory
  SET quantity_on_hand = v_new,
      last_restocked_at = CASE WHEN p_quantity > 0 THEN NOW() ELSE last_restocked_at END
  WHERE id = p_inventory_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, notes, recorded_by
  ) VALUES (
    p_inventory_id, p_transaction_type, p_quantity, p_notes, p_recorded_by
  );

  RETURN v_new;
END;
$function$;

-- admin_reset_user_password
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(p_user_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_temp_password text;
  v_charset text := 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  v_length int := 10;
  i int;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = p_user_id::uuid
  ) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  v_temp_password := '';
  FOR i IN 1..v_length LOOP
    v_temp_password := v_temp_password ||
      substr(v_charset, floor(random() * length(v_charset) + 1)::int, 1);
  END LOOP;

  UPDATE auth.users
  SET encrypted_password = crypt(v_temp_password, gen_salt('bf')),
      updated_at = now()
  WHERE id = p_user_id::uuid;

  UPDATE public.user_roles
  SET must_change_password = true
  WHERE user_id = p_user_id::uuid;

  RETURN v_temp_password;
END;
$function$;

-- admin_update_listing_price
CREATE OR REPLACE FUNCTION public.admin_update_listing_price(p_listing_id uuid, p_new_price numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status    TEXT;
  v_crop_type TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can edit listing prices';
  END IF;

  IF p_new_price IS NULL OR p_new_price <= 0 THEN
    RAISE EXCEPTION 'Price must be greater than zero';
  END IF;

  SELECT ml.status, cm.crop_type INTO v_status, v_crop_type
  FROM marketplace_listings ml
  LEFT JOIN crop_master cm ON lower(cm.crop_name) = lower(ml.crop_name)
  WHERE ml.id = p_listing_id
  FOR UPDATE OF ml;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only live (approved) listings can have their price edited';
  END IF;

  IF v_crop_type IS DISTINCT FROM 'sp3_cooperative' THEN
    RAISE EXCEPTION 'Only Cooperative Market listings can have their price edited by an admin';
  END IF;

  UPDATE marketplace_listings SET price_per_kg = p_new_price WHERE id = p_listing_id;
END;
$function$;

-- approve_crop_request
CREATE OR REPLACE FUNCTION public.approve_crop_request(p_request_id uuid, p_admin_notes text DEFAULT NULL::text, p_crop_type text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request RECORD;
  v_crop_master_id UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  IF p_crop_type IS NOT NULL AND p_crop_type NOT IN ('sp3_cooperative', 'da_amad_market', 'open_market') THEN
    RAISE EXCEPTION 'Invalid crop_type: %', p_crop_type;
  END IF;

  SELECT id INTO v_crop_master_id
  FROM crop_master
  WHERE lower(crop_name) = lower(v_request.requested_name)
  LIMIT 1;

  IF v_crop_master_id IS NULL THEN
    INSERT INTO crop_master (crop_name, category, crop_type, image_url, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      COALESCE(p_crop_type, v_request.crop_type, 'open_market'),
      v_request.photo_url,
      TRUE,
      (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM crop_master)
    )
    RETURNING id INTO v_crop_master_id;
  END IF;

  UPDATE crop_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  IF v_request.farmer_crop_id IS NOT NULL THEN
    UPDATE farmer_crops
    SET crop_master_id = v_crop_master_id,
        photo_url = COALESCE(farmer_crops.photo_url, v_request.photo_url)
    WHERE id = v_request.farmer_crop_id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    FALSE,
    NOW(),
    '/farmer/harvest/crops'
  );

  RETURN v_crop_master_id;
END;
$function$;

-- approve_listing
CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status     TEXT;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can approve listings';
  END IF;

  SELECT status, farmer_id, crop_name INTO v_status, v_farmer_id, v_crop_name
  FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be approved (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'approved', admin_notes = NULL, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'listing', 'Listing Approved',
    'Your ' || v_crop_name || ' listing is now live on the Marketplace.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

-- approve_order
CREATE OR REPLACE FUNCTION public.approve_order(p_order_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status     TEXT;
  v_listing_id UUID;
  v_buyer_id   UUID;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can approve orders';
  END IF;

  SELECT status, listing_id, buyer_id, farmer_id
  INTO v_status, v_listing_id, v_buyer_id, v_farmer_id
  FROM orders WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_status <> 'pending' THEN
    RETURN FALSE;
  END IF;

  UPDATE orders SET status = 'approved' WHERE id = p_order_id;

  SELECT crop_name INTO v_crop_name FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Approved',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' has been approved and is being prepared.',
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Approved',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' order has been approved and is being prepared for the buyer.',
    FALSE, NOW(), '/farmer/marketplace'
  );

  RETURN TRUE;
END;
$function$;

-- cancel_order
CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can cancel orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Order cannot be cancelled once approved — current status: %', v_status;
  END IF;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'cancelled', notes = COALESCE(p_reason, notes)
  WHERE id = p_order_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Cancelled',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' was cancelled.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Cancelled',
    'An order for your ' || COALESCE(v_crop_name, 'produce') || ' listing was cancelled.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

-- cancel_program_purchase
CREATE OR REPLACE FUNCTION public.cancel_program_purchase(p_purchase_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id UUID := auth.uid();
  v_purchase  RECORD;
  v_is_admin  BOOLEAN;
BEGIN
  SELECT public.is_staff()
    INTO v_is_admin;

  SELECT id, farmer_id, status
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF NOT v_is_admin AND v_purchase.farmer_id <> v_caller_id THEN
    RAISE EXCEPTION 'You can only cancel your own purchase.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be cancelled.';
  END IF;

  UPDATE public.program_product_purchases
    SET status = 'cancelled',
        cancelled_at = NOW(),
        cancel_reason = p_reason
    WHERE id = p_purchase_id;

  IF v_is_admin THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_purchase.farmer_id, 'program', 'Purchase Cancelled',
      'Your program purchase was cancelled by the SP3 Admin.' ||
        CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
      FALSE, NOW(), '/farmer/profile/programs'
    );
  ELSE
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    SELECT ap.user_id, 'program', 'Purchase Cancelled',
           'A farmer cancelled their pending program purchase.',
           FALSE, NOW(), '/admin/programs/purchases'
    FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');
  END IF;
END;
$function$;

-- complete_market_linking
CREATE OR REPLACE FUNCTION public.complete_market_linking(p_id uuid, p_batch_id uuid DEFAULT NULL::uuid, p_confirmed_volume_kg numeric DEFAULT NULL::numeric, p_buyer_name text DEFAULT NULL::text, p_buyer_contact text DEFAULT NULL::text, p_price_per_kg numeric DEFAULT NULL::numeric, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_current_status TEXT;
  v_farmer_id UUID;
  v_batch_farmer_id UUID;
  v_quantity_kg DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_available DECIMAL;
  v_new_sold DECIMAL;
  v_new_status TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can complete market linking records';
  END IF;

  SELECT status, farmer_id INTO v_current_status, v_farmer_id
    FROM public.market_linking_programs
    WHERE id = p_id
    FOR UPDATE;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'Market linking record not found';
  END IF;

  IF v_current_status = 'completed' THEN
    RETURN; -- already completed — no-op, avoids double-deducting on a retry/race
  END IF;

  IF p_batch_id IS NOT NULL THEN
    IF p_confirmed_volume_kg IS NULL OR p_confirmed_volume_kg <= 0 THEN
      RAISE EXCEPTION 'confirmed_volume_kg is required when a batch is attached';
    END IF;

    SELECT quantity_kg, available_kg, sold_kg, farmer_id
      INTO v_quantity_kg, v_available_kg, v_sold_kg, v_batch_farmer_id
      FROM public.inventory_batches
      WHERE id = p_batch_id
      FOR UPDATE;

    IF v_available_kg IS NULL THEN
      RAISE EXCEPTION 'Batch not found';
    END IF;

    IF v_batch_farmer_id != v_farmer_id THEN
      RAISE EXCEPTION 'Batch does not belong to the farmer on this market linking record';
    END IF;

    IF p_confirmed_volume_kg > v_available_kg THEN
      RAISE EXCEPTION 'Confirmed volume (%) exceeds available batch stock (%)', p_confirmed_volume_kg, v_available_kg;
    END IF;

    v_new_available := v_available_kg - p_confirmed_volume_kg;
    v_new_sold := v_sold_kg + p_confirmed_volume_kg;

    -- Same thresholds as _apply_batch_reservation, for consistency.
    IF v_new_available <= 0 THEN
      v_new_status := 'sold_out';
    ELSIF v_new_available < v_quantity_kg * 0.15 THEN
      v_new_status := 'low_stock';
    ELSE
      v_new_status := 'available';
    END IF;

    UPDATE public.inventory_batches
      SET available_kg = v_new_available, sold_kg = v_new_sold, status = v_new_status
      WHERE id = p_batch_id;
  END IF;

  UPDATE public.market_linking_programs
    SET status = 'completed',
        completed_at = NOW(),
        inventory_batch_id = COALESCE(p_batch_id, inventory_batch_id),
        confirmed_volume_kg = COALESCE(p_confirmed_volume_kg, confirmed_volume_kg),
        buyer_name = COALESCE(p_buyer_name, buyer_name),
        buyer_contact = COALESCE(p_buyer_contact, buyer_contact),
        price_per_kg = COALESCE(p_price_per_kg, price_per_kg),
        notes = COALESCE(p_notes, notes)
    WHERE id = p_id;
END;
$function$;

-- complete_order
CREATE OR REPLACE FUNCTION public.complete_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_batch_id    UUID;
  v_remaining   NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can complete orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only approved orders can be marked completed (current status: %)', v_status;
  END IF;

  SELECT inventory_batch_id INTO v_batch_id
  FROM marketplace_listings WHERE id = v_listing_id;

  IF v_batch_id IS NOT NULL THEN
    UPDATE inventory_batches SET sold_kg = sold_kg + v_quantity_kg WHERE id = v_batch_id;
  END IF;

  SELECT remaining_kg INTO v_remaining
  FROM marketplace_listings WHERE id = v_listing_id;

  IF v_remaining <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = v_listing_id;
  END IF;

  UPDATE orders SET status = 'completed' WHERE id = p_order_id;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Completed',
    'Your order for ' || COALESCE(v_crop_name, 'produce') ||
      ' has been completed. Thank you for supporting SP3 farmers!',
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Completed',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' order has been completed and sold.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

-- confirm_cooperative_offer
CREATE OR REPLACE FUNCTION public.confirm_cooperative_offer(p_offer_id uuid, p_confirmed_quantity_kg numeric, p_confirmed_amount numeric, p_admin_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_offer RECORD;
  v_transaction_id UUID;
  v_crop_type TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can confirm cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  IF p_confirmed_quantity_kg <= 0 OR p_confirmed_quantity_kg > v_offer.offered_quantity_kg THEN
    RAISE EXCEPTION 'Confirmed quantity must be between 0 and the offered quantity (%).', v_offer.offered_quantity_kg;
  END IF;

  v_crop_type := lower(v_offer.crop_name);

  -- Every confirmed offer, any crop, settles through
  -- member_sales_transactions as of this migration (Phase 9 / "Full
  -- financial parity") — this is the single change from the prior
  -- version, which only did this for palay/peanut.
  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, v_crop_type,
    p_confirmed_quantity_kg, p_confirmed_amount, CURRENT_DATE, auth.uid()
  ) RETURNING id INTO v_transaction_id;

  UPDATE cooperative_purchase_offers
  SET status = 'confirmed',
      confirmed_quantity_kg = p_confirmed_quantity_kg,
      confirmed_amount = p_confirmed_amount,
      member_sales_transaction_id = v_transaction_id,
      admin_notes = p_admin_notes,
      confirmed_by = auth.uid(),
      confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Confirmed',
    'Your offer of ' || p_confirmed_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was confirmed by SP3 for ₱' || p_confirmed_amount || '.',
    FALSE,
    NOW(),
    '/farmer/harvest/inventory'
  );

  RETURN v_transaction_id;
END;
$function$;

-- confirm_payout_decision
CREATE OR REPLACE FUNCTION public.confirm_payout_decision(p_farmer_id uuid, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID := auth.uid();
  v_row RECORD;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) OR EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = v_admin) THEN
    RAISE EXCEPTION 'Only an admin can confirm a payout decision.';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = p_farmer_id AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', p_farmer_id, p_year;
  END IF;
  IF v_row.payout_decision NOT IN ('pending_cash', 'pending_capital') THEN
    RAISE EXCEPTION 'No pending payout decision to confirm (current: %)', v_row.payout_decision;
  END IF;

  IF v_row.payout_decision = 'pending_capital' THEN
    INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
    VALUES (
      p_farmer_id,
      v_row.payout_decision_amount,
      'patronage_capital',
      'Reinvested from ' || p_year || ' Balik-Tangkilik payout (admin-confirmed)',
      v_admin
    );

    UPDATE member_contributions
    SET reinvested_amount = COALESCE(reinvested_amount, 0) + v_row.payout_decision_amount,
        payout_decision = 'capital_confirmed',
        payout_decision_confirmed_at = NOW(),
        payout_decision_confirmed_by = v_admin
    WHERE farmer_id = p_farmer_id AND year = p_year;
  ELSE
    UPDATE member_contributions
    SET payout_decision = 'cash_confirmed',
        payout_decision_confirmed_at = NOW(),
        payout_decision_confirmed_by = v_admin
    WHERE farmer_id = p_farmer_id AND year = p_year;
  END IF;
END;
$function$;

-- confirm_program_purchase
CREATE OR REPLACE FUNCTION public.confirm_program_purchase(p_purchase_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id  UUID := auth.uid();
  v_purchase  RECORD;
  v_on_hand   DECIMAL;
  v_item_name TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only an admin can confirm a purchase.';
  END IF;

  SELECT id, product_id, quantity, status, farmer_id
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be confirmed.';
  END IF;

  -- Row-lock the linked inventory item through program_products, re-check
  -- stock at confirmation time (it may have moved since the request).
  SELECT ci.quantity_on_hand, ci.item_name
    INTO v_on_hand, v_item_name
    FROM public.cooperative_inventory ci
    JOIN public.program_products pp ON pp.inventory_item_id = ci.id
    WHERE pp.id = v_purchase.product_id
    FOR UPDATE OF ci;

  IF v_on_hand IS NULL OR v_on_hand < v_purchase.quantity THEN
    RAISE EXCEPTION 'Not enough stock remaining to confirm this purchase.';
  END IF;

  UPDATE public.cooperative_inventory ci
    SET quantity_on_hand = ci.quantity_on_hand - v_purchase.quantity
    FROM public.program_products pp
    WHERE pp.id = v_purchase.product_id
      AND ci.id = pp.inventory_item_id;

  INSERT INTO public.inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by, notes
  )
  SELECT pp.inventory_item_id, 'sold', -v_purchase.quantity, v_purchase.id, 'program_purchase', v_admin_id,
         'Program product sale'
  FROM public.program_products pp
  WHERE pp.id = v_purchase.product_id;

  UPDATE public.program_product_purchases
    SET status = 'paid',
        confirmed_at = NOW(),
        confirmed_by = v_admin_id
    WHERE id = p_purchase_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_purchase.farmer_id, 'program', 'Purchase Confirmed',
    'Your purchase of ' || v_purchase.quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' has been confirmed.',
    FALSE, NOW(), '/farmer/profile/programs'
  );
END;
$function$;

-- confirm_program_return
CREATE OR REPLACE FUNCTION public.confirm_program_return(p_program_member_id uuid, p_amount_returned numeric, p_admin_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member RECORD;
  v_program RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm a program return';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;
  IF v_member.settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'This enrollment has already been settled';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.benefit_type != 'revenue_share' THEN
    RAISE EXCEPTION 'This program does not require a return settlement';
  END IF;

  UPDATE program_members
  SET amount_returned = p_amount_returned,
      settled_at = NOW(),
      status = 'completed',
      notes = COALESCE(p_admin_notes, notes)
  WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_member.farmer_id,
    'program',
    'Program Return Settled',
    'Your return of ₱' || p_amount_returned || ' for ' || v_program.program_name || ' has been recorded. Thank you!',
    FALSE,
    NOW(),
    '/farmer/profile/programs'
  );
END;
$function$;

-- convert_program_distribution_to_loan
CREATE OR REPLACE FUNCTION public.convert_program_distribution_to_loan(p_program_member_id uuid, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(loan_id uuid, reference_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member       RECORD;
  v_item         RECORD;
  v_line_total   NUMERIC;
  v_items        JSONB;
  v_result       RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can convert a distribution to a loan';
  END IF;

  SELECT pm.*, cp.program_name INTO v_member
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  WHERE pm.id = p_program_member_id
  FOR UPDATE OF pm;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program member not found';
  END IF;

  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'This member has not been distributed a benefit yet';
  END IF;

  IF v_member.converted_loan_id IS NOT NULL THEN
    RAISE EXCEPTION 'This distribution has already been converted to a loan';
  END IF;

  IF v_member.inventory_item_id IS NULL OR v_member.quantity_given IS NULL THEN
    RAISE EXCEPTION 'This distribution has no recorded item/quantity to convert';
  END IF;

  SELECT item_name, unit, COALESCE(unit_cost, 0) AS unit_cost
  INTO v_item
  FROM cooperative_inventory
  WHERE id = v_member.inventory_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The distributed inventory item no longer exists';
  END IF;

  v_line_total := v_member.quantity_given * v_item.unit_cost;

  v_items := jsonb_build_array(jsonb_build_object(
    'itemName',  v_item.item_name,
    'quantity',  v_member.quantity_given,
    'unit',      v_item.unit,
    'unitPrice', v_item.unit_cost,
    'lineTotal', v_line_total
  ));

  SELECT * INTO v_result FROM issue_loan(
    v_member.farmer_id,
    v_items,
    CURRENT_DATE,
    p_monthly_payment,
    p_next_payment_date,
    COALESCE(p_notes, 'From Program Distribution: ' || v_member.program_name),
    auth.uid(),
    NULL
  );

  UPDATE farmer_loans
  SET source_program_id = v_member.program_id
  WHERE id = v_result.loan_id;

  UPDATE program_members
  SET distribution_outcome = 'failed',
      outcome_recorded_at = NOW(),
      converted_loan_id = v_result.loan_id
  WHERE id = p_program_member_id;

  RETURN QUERY SELECT v_result.loan_id, v_result.reference_no;
END;
$function$;

-- create_listing_with_reservation
CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(p_batch_id uuid, p_crop_name text, p_variety text, p_quantity_kg numeric, p_price_per_kg numeric, p_photo_url text, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_listing_id UUID;
  v_crop_id UUID;
BEGIN
  IF p_crop_name ILIKE '%ginger%' THEN
    RAISE EXCEPTION 'Ginger cannot be listed on the open Marketplace — it can only be sold through Market Linking.';
  END IF;

  IF p_description IS NULL OR btrim(p_description) = '' THEN
    RAISE EXCEPTION 'A description is required to create a listing.';
  END IF;

  SELECT fc.crop_master_id INTO v_crop_id
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  WHERE ib.id = p_batch_id;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, description, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, v_crop_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, btrim(p_description), 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'listing_submitted',
    'New Listing Submitted',
    p_crop_name || ' (' || p_quantity_kg || 'kg) was submitted for review.',
    FALSE,
    NOW()
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN v_listing_id;
END;
$function$;

-- create_officer_account
CREATE OR REPLACE FUNCTION public.create_officer_account(p_username text, p_password text, p_full_name text, p_date_of_birth date DEFAULT NULL::date, p_gender text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone_number text DEFAULT NULL::text, p_position text DEFAULT NULL::text, p_registry_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id     UUID;
  v_email       TEXT;
  v_reg         RECORD;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can create Officer accounts';
  END IF;

  IF p_registry_id IS NULL THEN
    RAISE EXCEPTION 'An Officer Registry record is required';
  END IF;
  SELECT * INTO v_reg FROM officer_registry WHERE id = p_registry_id FOR UPDATE;
  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Officer Registry record not found';
  END IF;
  IF v_reg.is_registered THEN
    RAISE EXCEPTION 'This Officer Registry record already has an account';
  END IF;

  IF p_date_of_birth IS NOT NULL
     AND p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years') THEN
    RAISE EXCEPTION 'Officer must be at least 18 years old';
  END IF;

  IF p_gender IS NOT NULL
     AND p_gender NOT IN ('male', 'female', 'prefer_not_to_say') THEN
    RAISE EXCEPTION 'Invalid gender value';
  END IF;

  v_email := lower(trim(p_username)) || '@sagana.local';
  IF EXISTS (SELECT 1 FROM user_information WHERE username = lower(trim(p_username))) THEN
    RAISE EXCEPTION 'Username % is already taken', p_username;
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, phone_change, phone_change_token,
    reauthentication_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    v_email, crypt(p_password, gen_salt('bf', 10)), NOW(),
    '{"provider":"email","providers":["email"]}',
    json_build_object('full_name', p_full_name)::jsonb,
    NOW(), NOW(),
    '', '', '', '',
    '', '', '',
    ''
  )
  RETURNING id INTO v_user_id;

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_user_id::text, v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email,
                       'email_verified', false, 'phone_verified', false),
    'email', NOW(), NOW(), NOW()
  );

  INSERT INTO user_roles (user_id, role, status)
  VALUES (v_user_id, 'officer', 'active');

  INSERT INTO user_information (user_id, full_name, phone_number, username, contact_email)
  VALUES (
    v_user_id,
    trim(p_full_name),
    NULLIF(trim(COALESCE(p_phone_number, v_reg.phone_number, '')), ''),
    lower(trim(p_username)),
    NULLIF(lower(trim(COALESCE(p_email, v_reg.email, ''))), '')
  );

  INSERT INTO officer_profiles (user_id, position, date_of_birth, gender)
  VALUES (v_user_id, p_position, p_date_of_birth, p_gender);

  -- Operational authorization (Decision D21, unchanged from Phase D-2):
  -- an Officer performs the same operational writes an Admin does.
  -- Officers no longer receive an admin profile row (access comes from the role).


  UPDATE officer_registry
  SET is_registered = TRUE, registered_user_id = v_user_id
  WHERE id = p_registry_id;

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Username already taken';
  WHEN OTHERS THEN RAISE;
END;
$function$;

-- decline_cooperative_offer
CREATE OR REPLACE FUNCTION public.decline_cooperative_offer(p_offer_id uuid, p_admin_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_offer RECORD;
  v_batch RECORD;
  v_new_available DECIMAL;
  v_new_status TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can decline cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  SELECT quantity_kg, available_kg, sold_kg INTO v_batch
    FROM inventory_batches WHERE id = v_offer.inventory_batch_id FOR UPDATE;

  v_new_available := v_batch.available_kg + v_offer.offered_quantity_kg;
  v_new_status := CASE
    WHEN v_new_available <= 0 THEN 'sold_out'
    WHEN v_new_available < v_batch.quantity_kg * 0.15 THEN 'low_stock'
    ELSE 'available'
  END;

  UPDATE inventory_batches
  SET available_kg = v_new_available, status = v_new_status
  WHERE id = v_offer.inventory_batch_id;

  UPDATE cooperative_purchase_offers
  SET status = 'declined', admin_notes = p_admin_notes,
      confirmed_by = auth.uid(), confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Offer Declined',
    'Your offer of ' || v_offer.offered_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was not accepted by SP3.' ||
      CASE WHEN p_admin_notes IS NOT NULL THEN ' Reason: ' || p_admin_notes ELSE '' END,
    FALSE,
    NOW(),
    '/farmer/harvest/inventory'
  );
END;
$function$;

-- issue_loan
CREATE OR REPLACE FUNCTION public.issue_loan(p_farmer_id uuid, p_items jsonb, p_issued_date date, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS TABLE(loan_id uuid, reference_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_loan_id       UUID;
  v_total_value   NUMERIC := 0;
  v_item          JSONB;
  v_inventory_id  UUID;
  v_quantity      NUMERIC;
  v_unit_price    NUMERIC;
  v_line_total    NUMERIC;
  v_available     NUMERIC;
  v_item_name     TEXT;
  v_year          INT := EXTRACT(YEAR FROM p_issued_date)::INT;
  v_next_seq      INT;
  v_reference_no  TEXT;
  v_existing_id   UUID;
  v_existing_ref  TEXT;
  v_contribution  NUMERIC;
  v_minimum       NUMERIC;
  v_farmer_status TEXT;
BEGIN
  -- Admin check — first statement in the body.
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Farmer membership-status gate (Admin-Loan Issue 1.3) — the target
  -- farmer must be an active member. Checked before the capital-share
  -- gate so a non-member gets a membership-specific error rather than a
  -- misleading capital-contribution one.
  SELECT status INTO v_farmer_status
  FROM user_roles
  WHERE user_id = p_farmer_id AND role = 'farmer';

  IF v_farmer_status IS NULL THEN
    RAISE EXCEPTION 'Farmer account not found';
  END IF;

  IF v_farmer_status <> 'active' THEN
    RAISE EXCEPTION 'Farmer is not an active cooperative member (status: %) and is not eligible for a loan', v_farmer_status;
  END IF;

  -- Capital-share loan eligibility — HARD block (Issue 4d). Runs before
  -- the replay check so a replayed call re-verifies too. The Issue-Loan
  -- screen shows its own warning banner; this is the backend authority.
  SELECT COALESCE(mcs.total_contribution, 0) INTO v_contribution
  FROM member_capital_shares mcs
  WHERE mcs.farmer_id = p_farmer_id;
  v_contribution := COALESCE(v_contribution, 0);

  SELECT COALESCE(lps.minimum_capital_contribution, 2000) INTO v_minimum
  FROM loan_policy_settings lps
  WHERE lps.id = 1;
  v_minimum := COALESCE(v_minimum, 2000);

  IF v_contribution < v_minimum THEN
    RAISE EXCEPTION
      'Farmer has not met the minimum capital contribution of % required for a loan (current contribution: %)',
      v_minimum, v_contribution;
  END IF;

  -- Input validation.
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one loan item is required';
  END IF;

  IF p_monthly_payment <= 0 THEN
    RAISE EXCEPTION 'Monthly payment must be greater than zero';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity   := (v_item->>'quantity')::NUMERIC;
    v_unit_price := (v_item->>'unitPrice')::NUMERIC;
    v_line_total := (v_item->>'lineTotal')::NUMERIC;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero: %', v_item->>'itemName';
    END IF;

    IF v_unit_price IS NULL OR v_unit_price < 0 THEN
      RAISE EXCEPTION 'Item unit price must not be negative: %', v_item->>'itemName';
    END IF;

    IF v_line_total IS NULL OR v_line_total < 0 THEN
      RAISE EXCEPTION 'Item line total must not be negative: %', v_item->>'itemName';
    END IF;
  END LOOP;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT fl.id, fl.reference_no INTO v_existing_id, v_existing_ref
      FROM farmer_loans fl
      WHERE fl.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT v_existing_id, v_existing_ref;
      RETURN;
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('loan_reference_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(fl.reference_no, '^LN-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_next_seq
  FROM farmer_loans fl
  WHERE fl.reference_no LIKE 'LN-' || v_year || '-%';

  v_reference_no := 'LN-' || v_year || '-' || LPAD(v_next_seq::TEXT, 3, '0');

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  INSERT INTO farmer_loans (
    farmer_id, reference_no, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date, idempotency_key
  ) VALUES (
    p_farmer_id, v_reference_no, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date, p_idempotency_key
  )
  RETURNING id INTO v_loan_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total)
    VALUES (
      v_loan_id,
      v_item->>'itemName',
      (v_item->>'quantity')::NUMERIC,
      v_item->>'unit',
      (v_item->>'unitPrice')::NUMERIC,
      (v_item->>'lineTotal')::NUMERIC
    );

    v_inventory_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    IF v_inventory_id IS NOT NULL THEN
      v_quantity := (v_item->>'quantity')::NUMERIC;

      SELECT quantity_on_hand, item_name INTO v_available, v_item_name
        FROM cooperative_inventory
        WHERE id = v_inventory_id
        FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory item % no longer exists', v_inventory_id;
      END IF;

      IF v_available < v_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
          v_item_name, v_available, v_quantity;
      END IF;

      UPDATE cooperative_inventory
      SET quantity_on_hand = quantity_on_hand - v_quantity
      WHERE id = v_inventory_id;

      INSERT INTO inventory_transactions (
        inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
      ) VALUES (
        v_inventory_id, 'loan_issued', -v_quantity, v_loan_id, 'loan', p_recorded_by
      );
    END IF;
  END LOOP;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    p_farmer_id, 'loan', 'Loan Issued',
    'A new loan (' || v_reference_no || ') worth ₱' ||
      to_char(v_total_value, 'FM999,999,990.00') || ' has been issued to you.',
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_loan_id, v_reference_no;
END;
$function$;

-- notify_admins_of_crop_request
CREATE OR REPLACE FUNCTION public.notify_admins_of_crop_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'crop_request',
    'New Crop Request',
    NEW.requested_name || ' was requested by a farmer and needs review.',
    FALSE,
    NOW(),
    '/admin/crops/requests'
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');
  RETURN NEW;
END;
$function$;

-- notify_admins_of_market_linking_request
CREATE OR REPLACE FUNCTION public.notify_admins_of_market_linking_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'requested' THEN
    INSERT INTO public.notifications (user_id, type, title, body, is_read, created_at)
    SELECT
      ap.user_id,
      'system',
      'New Market Linking Request',
      'A farmer requested to enroll ' || NEW.crop_name || ' in Market Linking and needs review.',
      FALSE,
      NOW()
    FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');
  END IF;
  RETURN NEW;
END;
$function$;

-- notify_admins_of_program_enrollment_request
CREATE OR REPLACE FUNCTION public.notify_admins_of_program_enrollment_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_program_name TEXT;
BEGIN
  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = NEW.program_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'program',
    'New Program Enrollment Request',
    'A farmer requested to enroll in ' || COALESCE(v_program_name, 'a program') || ' and needs review.',
    FALSE,
    NOW()
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN NEW;
END;
$function$;

-- notify_overdue_farmers
CREATE OR REPLACE FUNCTION public.notify_overdue_farmers()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mode           TEXT;
  v_delay_days     INT;
  v_notified_count INT := 0;
  v_loan           RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  SELECT notification_timing_mode, notification_delay_days
  INTO v_mode, v_delay_days
  FROM loan_policy_settings WHERE id = 1;

  FOR v_loan IN
    SELECT id, farmer_id, reference_no, total_value, amount_paid, next_payment_date
    FROM farmer_loans
    WHERE status = 'overdue'
      AND notified_overdue_at IS NULL
      AND (
        v_mode = 'on_transition'
        OR (v_mode = 'delayed' AND next_payment_date <= CURRENT_DATE - v_delay_days)
        OR (v_mode = 'next_bod_meeting' AND CURRENT_DATE >= next_bod_saturday_after(next_payment_date))
      )
  LOOP
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_loan.farmer_id,
      'loan',
      'Payment Reminder',
      'Your loan ' || v_loan.reference_no || ' has a missed payment. Outstanding balance: ₱' ||
      to_char(v_loan.total_value - v_loan.amount_paid, 'FM999,999,990.00') ||
      '. Please settle at the next BOD meeting or visit the cooperative office.',
      FALSE,
      NOW(),
      '/farmer/profile/loans'
    );

    UPDATE farmer_loans SET notified_overdue_at = NOW() WHERE id = v_loan.id;
    v_notified_count := v_notified_count + 1;
  END LOOP;

  RETURN v_notified_count;
END;
$function$;

-- record_loan_payment
CREATE OR REPLACE FUNCTION public.record_loan_payment(p_loan_id uuid, p_amount numeric, p_payment_date date, p_next_payment_date_if_active date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS TABLE(is_fully_paid boolean, running_balance numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total_value      NUMERIC;
  v_current_paid     NUMERIC;
  v_new_paid         NUMERIC;
  v_running_balance  NUMERIC;
  v_is_fully_paid    BOOLEAN;
  v_existing_balance NUMERIC;
  v_farmer_id        UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins may record loan payments';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT flp.running_balance INTO v_existing_balance
      FROM farmer_loan_payments flp
      WHERE flp.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT (v_existing_balance = 0), v_existing_balance;
      RETURN;
    END IF;
  END IF;

  SELECT total_value, COALESCE(amount_paid, 0), farmer_id
    INTO v_total_value, v_current_paid, v_farmer_id
    FROM farmer_loans
    WHERE id = p_loan_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loan % not found', p_loan_id;
  END IF;

  v_new_paid        := v_current_paid + p_amount;
  v_running_balance := GREATEST(v_total_value - v_new_paid, 0);
  v_is_fully_paid   := v_new_paid >= v_total_value;

  INSERT INTO farmer_loan_payments (
    loan_id, payment_date, amount_paid, running_balance, notes, recorded_by, idempotency_key
  ) VALUES (
    p_loan_id, p_payment_date, p_amount, v_running_balance, p_notes, p_recorded_by, p_idempotency_key
  );

  UPDATE farmer_loans
  SET amount_paid         = v_new_paid,
      status              = CASE WHEN v_is_fully_paid THEN 'paid' ELSE 'active' END,
      notified_overdue_at = NULL,
      next_payment_date   = CASE WHEN v_is_fully_paid
                               THEN next_payment_date
                               ELSE p_next_payment_date_if_active
                             END
  WHERE id = p_loan_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'loan',
    CASE WHEN v_is_fully_paid THEN 'Loan Fully Paid' ELSE 'Payment Recorded' END,
    'Your payment of ₱' || to_char(p_amount, 'FM999,999,990.00') || ' was recorded.' ||
      CASE WHEN v_is_fully_paid
        THEN ' Your loan is now fully paid off. Thank you!'
        ELSE ' Remaining balance: ₱' || to_char(v_running_balance, 'FM999,999,990.00') || '.'
      END,
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_is_fully_paid, v_running_balance;
END;
$function$;

-- reinvest_patronage_capital
CREATE OR REPLACE FUNCTION public.reinvest_patronage_capital(p_year integer, p_amount numeric, p_note text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer UUID := auth.uid();
  v_row RECORD;
  v_total_payout NUMERIC;
  v_available NUMERIC;
  v_farmer_name TEXT;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = v_farmer AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', v_farmer, p_year;
  END IF;
  IF v_row.status != 'paid' THEN
    RAISE EXCEPTION 'This year''s Balik-Tangkilik has not been finalized yet (status: %)', v_row.status;
  END IF;

  v_total_payout := COALESCE(v_row.actual_balik_tangkilik, 0)
                   + COALESCE(v_row.actual_interest_on_capital, 0)
                   + COALESCE(v_row.actual_purchase_patronage, 0);
  v_available := v_total_payout - v_row.reinvested_amount;

  IF p_amount > v_available THEN
    RAISE EXCEPTION 'Amount (%) exceeds what remains available to reinvest (%)', p_amount, v_available;
  END IF;

  INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
  VALUES (
    v_farmer,
    p_amount,
    'patronage_capital',
    COALESCE(p_note, 'Reinvested from ' || p_year || ' Balik-Tangkilik payout'),
    v_farmer
  );

  UPDATE member_contributions
  SET reinvested_amount = reinvested_amount + p_amount
  WHERE farmer_id = v_farmer AND year = p_year;

  SELECT full_name INTO v_farmer_name FROM user_information WHERE user_id = v_farmer;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'capital',
    'Patronage Capital Reinvested',
    COALESCE(v_farmer_name, 'A farmer') || ' reinvested ₱' || to_char(p_amount, 'FM999,999,990.00') ||
      ' of their ' || p_year || ' Balik-Tangkilik payout into their capital share.',
    FALSE,
    NOW(),
    '/admin/balik-tangkilik'
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN v_available - p_amount;
END;
$function$;

-- reject_crop_request
CREATE OR REPLACE FUNCTION public.reject_crop_request(p_request_id uuid, p_admin_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can reject crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  UPDATE crop_requests
  SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Declined',
    v_request.requested_name || ' was not added to the official list. Reason: ' || p_admin_notes,
    FALSE,
    NOW(),
    '/farmer/harvest/crops'
  );
END;
$function$;

-- reject_listing
CREATE OR REPLACE FUNCTION public.reject_listing(p_listing_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be rejected (current: %)', v_listing.status;
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_listing.remaining_kg > 0 THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.remaining_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, remaining_kg = 0,
      reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_listing.farmer_id, 'listing', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

-- reject_payout_decision
CREATE OR REPLACE FUNCTION public.reject_payout_decision(p_farmer_id uuid, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID := auth.uid();
  v_row RECORD;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) OR EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = v_admin) THEN
    RAISE EXCEPTION 'Only an admin can reject a payout decision.';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = p_farmer_id AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', p_farmer_id, p_year;
  END IF;
  IF v_row.payout_decision NOT IN ('pending_cash', 'pending_capital') THEN
    RAISE EXCEPTION 'Only a pending decision can be rejected (current: %)', v_row.payout_decision;
  END IF;

  UPDATE member_contributions
  SET payout_decision = NULL,
      payout_decision_amount = NULL,
      payout_decision_requested_at = NULL
  WHERE farmer_id = p_farmer_id AND year = p_year;
END;
$function$;

-- request_program_purchase
CREATE OR REPLACE FUNCTION public.request_program_purchase(p_program_id uuid, p_product_id uuid, p_quantity numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id   UUID := auth.uid();
  v_product     RECORD;
  v_on_hand     DECIMAL;
  v_reserved    DECIMAL;
  v_item_name   TEXT;
  v_farmer_name TEXT;
  v_purchase_id UUID;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.program_members
    WHERE program_id = p_program_id
      AND farmer_id = v_farmer_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not an active member of this program.';
  END IF;

  SELECT pp.id, pp.unit_price, pp.is_available, pp.inventory_item_id
    INTO v_product
    FROM public.program_products pp
    WHERE pp.id = p_product_id
      AND pp.program_id = p_program_id
    FOR SHARE;

  IF v_product IS NULL THEN
    RAISE EXCEPTION 'Product not found for this program.';
  END IF;
  IF NOT v_product.is_available THEN
    RAISE EXCEPTION 'This product is not currently available for purchase.';
  END IF;

  SELECT quantity_on_hand, quantity_reserved, item_name
    INTO v_on_hand, v_reserved, v_item_name
    FROM public.cooperative_inventory
    WHERE id = v_product.inventory_item_id
    FOR SHARE;

  IF v_on_hand IS NULL THEN
    RAISE EXCEPTION 'Linked inventory item no longer exists.';
  END IF;
  IF (v_on_hand - v_reserved) < p_quantity THEN
    RAISE EXCEPTION 'Not enough stock available for this quantity.';
  END IF;

  INSERT INTO public.program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status
  ) VALUES (
    p_program_id, p_product_id, v_farmer_id, p_quantity, v_product.unit_price,
    (v_product.unit_price * p_quantity), 'pending'
  )
  RETURNING id INTO v_purchase_id;

  SELECT full_name INTO v_farmer_name FROM public.user_information WHERE user_id = v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'program',
    'New Program Purchase Request',
    COALESCE(v_farmer_name, 'A farmer') || ' requested to purchase ' || p_quantity || ' ' ||
      COALESCE(v_item_name, 'item(s)') || '.',
    FALSE,
    NOW(),
    '/admin/programs/purchases'
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN v_purchase_id;
END;
$function$;

-- resolve_password_reset_request
CREATE OR REPLACE FUNCTION public.resolve_password_reset_request(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE password_reset_requests
  SET status = 'resolved', resolved_at = NOW(), resolved_by = auth.uid()
  WHERE id = p_request_id;
END;
$function$;

-- respond_to_da_amad_enrollment
CREATE OR REPLACE FUNCTION public.respond_to_da_amad_enrollment(p_enrollment_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID;
  v_status TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review enrollments';
  END IF;

  SELECT farmer_id, status INTO v_farmer_id, v_status
  FROM da_amad_enrollments WHERE id = p_enrollment_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Enrollment not found';
  END IF;
  IF v_status != 'pending' THEN
    RAISE EXCEPTION 'Enrollment already reviewed (status: %)', v_status;
  END IF;

  UPDATE da_amad_enrollments
  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_enrollment_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'system',
    CASE WHEN p_approve THEN 'Market Linking Enrollment Approved' ELSE 'Market Linking Enrollment Declined' END,
    CASE WHEN p_approve
      THEN 'You can now submit your Ginger harvest for sale through Market Linking.'
      ELSE COALESCE('Your enrollment was declined: ' || p_notes, 'Your enrollment was declined. You may submit a new request.')
    END,
    FALSE,
    NOW()
  );
END;
$function$;

-- respond_to_market_linking_request
CREATE OR REPLACE FUNCTION public.respond_to_market_linking_request(p_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID;
  v_status TEXT;
  v_crop_name TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review market linking requests';
  END IF;

  SELECT farmer_id, status, crop_name INTO v_farmer_id, v_status, v_crop_name
    FROM market_linking_programs
    WHERE id = p_id
    FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_status != 'requested' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
  END IF;

  UPDATE market_linking_programs
    SET status = CASE WHEN p_approve THEN 'submitted' ELSE 'cancelled' END,
        notes = COALESCE(p_notes, notes)
    WHERE id = p_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'system',
    CASE WHEN p_approve THEN 'Market Linking Request Approved'
         ELSE 'Market Linking Request Declined' END,
    CASE WHEN p_approve
      THEN v_crop_name || ' Market Linking enrollment was approved. Check My Market Linking for status.'
      ELSE 'Your Market Linking request was declined.' ||
           CASE WHEN p_notes IS NOT NULL AND p_notes <> ''
                THEN ' Reason: ' || p_notes ELSE '' END
    END,
    FALSE,
    NOW()
  );
END;
$function$;

-- respond_to_program_enrollment_request
CREATE OR REPLACE FUNCTION public.respond_to_program_enrollment_request(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID;
  v_program_id UUID;
  v_status TEXT;
  v_program_name TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review enrollment requests';
  END IF;

  SELECT farmer_id, program_id, status INTO v_farmer_id, v_program_id, v_status
  FROM program_enrollment_requests WHERE id = p_request_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
  END IF;

  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = v_program_id;

  UPDATE program_enrollment_requests
  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_request_id;

  IF p_approve THEN
    -- Reactivate-or-insert, identical shape to ProgramRepository.
    -- enrollFarmer() (program_members has UNIQUE(program_id, farmer_id),
    -- and a farmer who was previously withdrawn already has a row here).
    IF EXISTS (
      SELECT 1 FROM program_members
      WHERE program_id = v_program_id AND farmer_id = v_farmer_id
    ) THEN
      UPDATE program_members
      SET status = 'active', enrolled_at = NOW()
      WHERE program_id = v_program_id AND farmer_id = v_farmer_id;
    ELSE
      INSERT INTO program_members (program_id, farmer_id)
      VALUES (v_program_id, v_farmer_id);
    END IF;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'program',
    CASE WHEN p_approve THEN 'Program Enrollment Approved' ELSE 'Program Enrollment Declined' END,
    CASE WHEN p_approve
      THEN 'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was approved.'
      ELSE COALESCE(
        'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was declined: ' || p_notes,
        'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was declined. You may submit a new request.'
      )
    END,
    FALSE,
    NOW()
  );
END;
$function$;

-- submit_application
CREATE OR REPLACE FUNCTION public.submit_application()
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       UUID := auth.uid();
  v_status    TEXT;
  v_attempts  SMALLINT;
  v_full_name TEXT;
BEGIN
  SELECT status, application_attempts INTO v_status, v_attempts
  FROM user_roles WHERE user_id = v_uid
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'No membership record found';
  END IF;

  IF v_status NOT IN ('draft', 'rejected') THEN
    RAISE EXCEPTION 'Application cannot be submitted from status %', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'pending',
      application_attempts = COALESCE(v_attempts, 0) + 1,
      rejection_reason = NULL,
      pending_acknowledgement = false
  WHERE user_id = v_uid;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (v_uid, v_status, 'pending',
          'Application submitted (attempt ' || (COALESCE(v_attempts, 0) + 1) || ')', v_uid);

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (v_uid, 'member_pending', 'Application Submitted',
          'Your membership application has been sent to the SP3 Cooperative for review.',
          false);

  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = v_uid;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'member_pending',
    'New Membership Application',
    COALESCE(v_full_name, 'A farmer') || ' submitted a membership application and needs review.',
    FALSE,
    NOW(),
    '/admin/farmers'
  FROM public.user_roles ap WHERE ap.role IN ('admin');

  RETURN (COALESCE(v_attempts, 0) + 1)::SMALLINT;
END;
$function$;

-- transition_overdue_loans
CREATE OR REPLACE FUNCTION public.transition_overdue_loans()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_grace_days      INT;
  v_updated_count   INT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  SELECT grace_period_days INTO v_grace_days
  FROM loan_policy_settings WHERE id = 1;

  UPDATE farmer_loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND next_payment_date IS NOT NULL
    AND next_payment_date < (CURRENT_DATE - v_grace_days);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN v_updated_count;
END;
$function$;

-- update_user_email_to_username
CREATE OR REPLACE FUNCTION public.update_user_email_to_username(p_user_id uuid, p_username text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE auth.users
  SET email = lower(trim(p_username)) || '@sagana.local'
  WHERE id = p_user_id;
END;
$function$;

-- 3. Expense categories: added from the farmer's My Expenses screen only.
DROP POLICY IF EXISTS "expense_categories: authenticated inserts" ON public.expense_categories;
CREATE POLICY "expense_categories: farmer inserts" ON public.expense_categories FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = auth.uid() AND r.role = 'farmer'));

-- 4. Remove the admin profile row from officer accounts (they now have no Admin access by row).
DELETE FROM public.admin_profiles a WHERE EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = a.user_id) AND NOT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = a.user_id AND r.role = 'admin');

COMMIT;

NOTIFY pgrst, 'reload schema';
