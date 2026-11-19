-- Volume data for the performance / load / stress tests. LOCAL test DB only. Takes a minute or two.
-- 150 farmers, 3 buyers, 1,500 approved listings (+ batches), 4,000 orders, 300 loans.
CREATE OR REPLACE FUNCTION pg_temp.mkv(p_username text, p_role text, p_phone text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := gen_random_uuid(); v_email text := p_username || '@sagana.local';
BEGIN
  INSERT INTO auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
    created_at,updated_at,confirmation_token,recovery_token,email_change,email_change_token_new,email_change_token_current,phone_change,phone_change_token,reauthentication_token)
  VALUES ('00000000-0000-0000-0000-000000000000',v_id,'authenticated','authenticated',v_email,'x',now(),
    '{"provider":"email","providers":["email"]}','{}'::jsonb,now(),now(),'','','','','','','','');
  INSERT INTO user_roles (user_id,role,status,must_change_password) VALUES (v_id,p_role,'active',false);
  INSERT INTO user_information (user_id,full_name,surname,first_name,phone_number,username)
    VALUES (v_id,'Perf '||p_username,'User','Perf',p_phone,p_username);
  IF p_role = 'farmer' THEN
    INSERT INTO farmer_profiles (user_id,is_verified,date_of_birth,gender) VALUES (v_id,true,'1985-05-05','male');
    INSERT INTO member_capital_shares (farmer_id,share_value_per_unit,total_contribution) VALUES (v_id,2000,0) ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO buyer_profiles (user_id) VALUES (v_id);
  END IF;
  RETURN v_id;
END $$;

DO $$
DECLARE
  f uuid; b uuid; fc uuid; h uuid; ib uuid; cm uuid;
  farmers uuid[] := '{}'; buyers uuid[] := '{}'; listings uuid[] := '{}'; l uuid;
  i int; j int; t0 timestamptz := clock_timestamp();
BEGIN
  SELECT id INTO cm FROM crop_master WHERE crop_name = 'Tomato';
  FOR i IN 1..150 LOOP
    f := pg_temp.mkv('perf_f' || i, 'farmer', '0919' || lpad(i::text, 7, '0'));
    farmers := farmers || f;
    INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
      VALUES (f, 'Tomato', 'Vegetables', cm, 'http://127.0.0.1/t.jpg') RETURNING id INTO fc;
    FOR j IN 1..10 LOOP
      INSERT INTO harvest_records (farmer_id, crop_id, crop_name, crop_category, quantity_kg, harvest_date, unit)
        VALUES (f, fc, 'Tomato', 'Vegetables', 100, current_date, 'kg') RETURNING id INTO h;
      INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, batch_number, quantity_kg, available_kg, unit)
        VALUES (f, h, fc, 'Tomato', 'x', 100, 100, 'kg') RETURNING id INTO ib;
      UPDATE inventory_batches SET available_kg = 40 WHERE id = ib;      -- 60 kg reserved by the listing
      INSERT INTO marketplace_listings (farmer_id, inventory_batch_id, crop_name, price_per_kg, volume_kg, remaining_kg, status, description, unit)
        VALUES (f, ib, 'Tomato', 50, 60, 60, 'approved', 'Perf listing ' || i || '-' || j, 'kg') RETURNING id INTO l;
      listings := listings || l;
    END LOOP;
  END LOOP;
  FOR i IN 1..3 LOOP
    buyers := buyers || pg_temp.mkv('perf_b' || i, 'buyer', '0920' || lpad(i::text, 7, '0'));
  END LOOP;
  RAISE NOTICE 'farmers+listings done in %', clock_timestamp() - t0;
  FOR i IN 1..4000 LOOP
    l := listings[1 + (i % array_length(listings, 1))];
    INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status, fulfillment_method)
      SELECT l, ml.farmer_id, buyers[1 + (i % 3)], 1, 50, 50,
             (ARRAY['pending','approved','pending','approved'])[1 + (i % 4)], 'pickup'
      FROM marketplace_listings ml WHERE ml.id = l;
  END LOOP;
  RAISE NOTICE 'orders done in %', clock_timestamp() - t0;
  FOR i IN 1..300 LOOP
    INSERT INTO farmer_loans (farmer_id, reference_no, issued_date, total_value, status, monthly_payment, next_payment_date)
      VALUES (farmers[1 + (i % 150)], 'x', current_date - (i % 90), 1000 + i, (ARRAY['active','overdue','paid'])[1 + (i % 3)], 100, current_date + 10);
  END LOOP;
  RAISE NOTICE 'all done in %', clock_timestamp() - t0;
END $$;
ANALYZE;
SELECT (SELECT count(*) FROM user_roles) users, (SELECT count(*) FROM marketplace_listings) listings,
       (SELECT count(*) FROM orders) orders, (SELECT count(*) FROM farmer_loans) loans,
       (SELECT count(*) FROM notifications) notifications, (SELECT count(*) FROM workflow_events) events;
