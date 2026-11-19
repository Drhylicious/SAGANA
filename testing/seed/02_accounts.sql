-- Test accounts for the LOCAL test database only. Password for all: Test@12345
-- Sign-in name = username (the app maps it to <username>@sagana.local).
CREATE OR REPLACE FUNCTION pg_temp.mk(p_username text, p_role text, p_status text, p_first text, p_surname text,
                                      p_phone text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := gen_random_uuid(); v_email text := p_username || '@sagana.local';
BEGIN
  IF EXISTS (SELECT 1 FROM user_information WHERE username = p_username) THEN
    RETURN (SELECT user_id FROM user_information WHERE username = p_username);
  END IF;
  INSERT INTO auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,
    email_change,email_change_token_new,email_change_token_current,phone_change,phone_change_token,reauthentication_token)
  VALUES ('00000000-0000-0000-0000-000000000000',v_id,'authenticated','authenticated',v_email,
    extensions.crypt('Test@12345', extensions.gen_salt('bf',10)),now(),
    '{"provider":"email","providers":["email"]}','{}'::jsonb,now(),now(),'','','','','','','','');
  INSERT INTO auth.identities (provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
  VALUES (v_id::text,v_id,jsonb_build_object('sub',v_id::text,'email',v_email,'email_verified',false,'phone_verified',false),
    'email',now(),now(),now());
  INSERT INTO user_roles (user_id,role,status,must_change_password) VALUES (v_id,p_role,p_status,false);
  INSERT INTO user_information (user_id,full_name,surname,first_name,phone_number,username)
    VALUES (v_id,p_first||' '||p_surname,p_surname,p_first,p_phone,p_username);
  IF p_role = 'farmer' THEN
    INSERT INTO farmer_profiles (user_id,is_verified,date_of_birth,gender)
      VALUES (v_id,(p_status='active'),'1985-05-05','male');
    INSERT INTO buyer_addresses (user_id,label,recipient_name,contact_number,address_line,is_default,street,house_no,latitude,longitude)
      VALUES (v_id,'Home',p_first,p_phone,'x',true,'Test Street','1',13.3,122.1);
    INSERT INTO member_capital_shares (farmer_id,share_value_per_unit,total_contribution) VALUES (v_id,2000,0) ON CONFLICT DO NOTHING;
  ELSIF p_role = 'officer' THEN
    INSERT INTO officer_profiles (user_id,date_of_birth,gender) VALUES (v_id,'1990-01-01','female');
  ELSIF p_role = 'buyer' THEN
    INSERT INTO buyer_profiles (user_id) VALUES (v_id);
  ELSIF p_role = 'admin' THEN
    INSERT INTO admin_profiles (user_id) VALUES (v_id);
  END IF;
  PERFORM public.issue_member_identifier(v_id, CASE p_role WHEN 'admin' THEN 'officer' ELSE p_role END, NULL);
  RETURN v_id;
END $$;

DO $$
DECLARE o_view uuid; o_manage uuid; f1 uuid; f2 uuid;
BEGIN
  PERFORM pg_temp.mk('t_manager',  'admin',   'active',  'Mara',   'Manager',  '09170000001');
  o_view   := pg_temp.mk('t_officer_view',   'officer', 'active', 'Olivia', 'ViewOnly', '09170000002');
  o_manage := pg_temp.mk('t_officer_manage', 'officer', 'active', 'Oscar',  'Manage',   '09170000003');
  f1 := pg_temp.mk('t_farmer1', 'farmer', 'active',  'Fidel', 'Farmer',  '09170000004');
  f2 := pg_temp.mk('t_farmer2', 'farmer', 'active',  'Faye',  'Farmer',  '09170000005');
  PERFORM pg_temp.mk('t_pending',  'farmer', 'pending', 'Pam',    'Pending',  '09170000006');
  PERFORM pg_temp.mk('t_buyer1',   'buyer',  'active',  'Bea',    'Buyer',    '09170000007');
  PERFORM public._apply_officer_permissions(o_view,   '{}'::jsonb, 'view');
  PERFORM public._apply_officer_permissions(o_manage, '{}'::jsonb, 'manage');
  -- Farmer 1 and 2: capital share, crops with a crop-roster photo
  INSERT INTO capital_contribution_events (farmer_id, amount, source, note, effective_date)
    SELECT x, 5000, 'opening_balance', 'seed', current_date - 30 FROM unnest(ARRAY[f1,f2]) x
    WHERE NOT EXISTS (SELECT 1 FROM capital_contribution_events WHERE farmer_id = x);
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    SELECT f, cm.crop_name, cm.category, cm.id, 'http://127.0.0.1/test.jpg'
    FROM unnest(ARRAY[f1,f2]) f, crop_master cm WHERE cm.crop_name IN ('Tomato','Ginger')
    ON CONFLICT (farmer_id, crop_name) DO NOTHING;
END $$;

-- The Officer View-Only/Manage gate (staff_permission_gate) is applied by PostgREST on every request.
ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.staff_permission_gate';
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

SELECT username, role, status FROM user_information JOIN user_roles USING (user_id) WHERE username LIKE 't\_%' ORDER BY 2,1;
