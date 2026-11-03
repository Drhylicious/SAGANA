// Local, in-memory Postgres (PGlite) harness. Loads the REAL migration scripts on
// top of minimal stand-ins for the Supabase auth schema and the pre-existing
// tables/policies, then exercises them as different users with row level security.
// Nothing here touches Supabase.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const SQLDIR = fileURLToPath(new URL('../../supabase_schema/', import.meta.url));
export const db = new PGlite();

export const ID = {
  mgr:  '00000000-0000-0000-0000-0000000000a1',
  off1: '00000000-0000-0000-0000-0000000000b1', // all Manage
  off2: '00000000-0000-0000-0000-0000000000b2', // Members View, rest Manage
  off3: '00000000-0000-0000-0000-0000000000b3', // all View
  far1: '00000000-0000-0000-0000-0000000000c1',
  far2: '00000000-0000-0000-0000-0000000000c2',
  buy1: '00000000-0000-0000-0000-0000000000d1',
  buy2: '00000000-0000-0000-0000-0000000000d2',
};

export const results = [];
export function check(id, name, ok, detail = '') {
  results.push({ id, name, ok: !!ok, detail: ok ? '' : String(detail) });
}

export function script(name) {
  return fs.readFileSync(SQLDIR + name, 'utf8');
}

export async function runScript(name) {
  await db.exec(script(name));
}

// One simulated PostgREST request: claims, method, path, role switch, the gate
// (pre-request function), then the body. Rolled back unless commit is set.
export async function as(uid, opts, body) {
  const { method = 'POST', path = '/x', gate = true, role = 'authenticated', commit = false } = opts || {};
  await db.exec('BEGIN');
  try {
    const claims = uid ? JSON.stringify({ sub: uid, role: 'authenticated' }) : '';
    await db.query(
      `SELECT set_config('request.jwt.claims', $1, true),
              set_config('request.method', $2, true),
              set_config('request.path', $3, true)`,
      [claims, method, path],
    );
    if (role) await db.exec(`SET LOCAL ROLE ${role}`);
    if (gate) await db.query('SELECT public.staff_permission_gate()');
    const value = body ? await body(db) : null;
    await db.exec('RESET ROLE');
    await db.exec(commit ? 'COMMIT' : 'ROLLBACK');
    return { ok: true, value };
  } catch (e) {
    try { await db.exec('ROLLBACK'); } catch (_) {}
    return { ok: false, error: e.message, code: e.code };
  }
}

export async function q(sql, params) {
  return (await db.query(sql, params)).rows;
}

export async function createUser(id, role, name, username, status = 'active') {
  await db.query(
    `INSERT INTO auth.users (id, email, aud, role) VALUES ($1, $2, 'authenticated', 'authenticated')`,
    [id, username + '@sagana.local'],
  );
  await db.query(
    `INSERT INTO user_roles (user_id, role, status) VALUES ($1, $2, $3)`,
    [id, role, status],
  );
  await db.query(
    `INSERT INTO user_information (user_id, full_name, username) VALUES ($1, $2, $3)`,
    [id, name, username],
  );
  if (role === 'officer') {
    await db.query(`INSERT INTO officer_profiles (user_id) VALUES ($1)`, [id]);
  }
}

export async function setLevels(uid, levels) {
  for (const [m, l] of Object.entries(levels)) {
    await db.query(
      `INSERT INTO officer_permissions (user_id, module, access_level) VALUES ($1,$2,$3)
       ON CONFLICT (user_id, module) DO UPDATE SET access_level = EXCLUDED.access_level`,
      [uid, m, l],
    );
  }
}

export const STUBS = `
CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN; CREATE ROLE authenticator NOLOGIN;
CREATE SCHEMA auth; CREATE SCHEMA extensions;
GRANT USAGE ON SCHEMA public, auth, extensions TO anon, authenticated, service_role;

CREATE TABLE auth.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), instance_id uuid, aud text, role text,
  email text UNIQUE, encrypted_password text, email_confirmed_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(),
  confirmation_token text, recovery_token text, email_change text,
  email_change_token_new text, email_change_token_current text, phone_change text,
  phone_change_token text, reauthentication_token text,
  banned_until timestamptz, last_sign_in_at timestamptz);
CREATE TABLE auth.identities (
  provider_id text, user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  identity_data jsonb, provider text, last_sign_in_at timestamptz,
  created_at timestamptz, updated_at timestamptz);

CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
         (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')), '')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', 'anon') $$;
CREATE FUNCTION extensions.crypt(text, text) RETURNS text LANGUAGE sql AS $$ SELECT 'h:' || $1 $$;
CREATE FUNCTION extensions.gen_salt(text, int) RETURNS text LANGUAGE sql AS $$ SELECT 's' $$;
CREATE FUNCTION uuid_generate_v4() RETURNS uuid LANGUAGE sql AS $$ SELECT gen_random_uuid() $$;

CREATE TABLE user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin','farmer','buyer','officer')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('active','pending','suspended','draft','rejected')),
  must_change_password boolean DEFAULT false, suspension_reason text, suspended_until timestamptz,
  application_attempts int DEFAULT 0, pending_acknowledgement boolean DEFAULT false, rejection_reason text,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
CREATE TABLE user_information (
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text, surname text, first_name text, middle_initial text, suffix text,
  phone_number text, username text, contact_email text, last_active_at timestamptz);
CREATE TABLE officer_profiles (user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  position text, date_of_birth date, gender text);
CREATE TABLE notifications (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, type text, title text, body text,
  is_read boolean DEFAULT false, created_at timestamptz DEFAULT now(), route_on_tap text);
CREATE TABLE admin_activity_log (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  module text NOT NULL, action_type text NOT NULL, description text NOT NULL,
  reference_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE member_status_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  member_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  from_status text, to_status text NOT NULL, reason text,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE broadcast_logs (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text, body text,
  created_by uuid, sent_at timestamptz, scheduled_at timestamptz, client_key text UNIQUE);
CREATE TABLE cooperative_annual_totals (year int PRIMARY KEY, total numeric);
CREATE TABLE crop_master (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), crop_name text,
  price numeric, notes text, updated_at timestamptz DEFAULT now());
CREATE TABLE price_records (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), crop_name text,
  price_per_kg numeric, notes text);
CREATE TABLE farmer_loans (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id uuid REFERENCES auth.users(id), reference_no text, status text, total_value numeric);
CREATE TABLE cooperative_inventory (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_name text, quantity_on_hand numeric);
-- tables the Farmer creation, approval and deletion functions touch
CREATE TABLE farmer_profiles (user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  is_verified boolean DEFAULT false, date_of_birth date, gender text);
CREATE TABLE member_capital_shares (farmer_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  share_value_per_unit numeric, total_contribution numeric DEFAULT 0);
CREATE TABLE capital_contribution_events (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, amount numeric, source text, note text,
  recorded_by uuid);
CREATE TABLE harvest_records (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id uuid REFERENCES auth.users(id) ON DELETE CASCADE);
CREATE TABLE buyer_addresses (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, label text, recipient_name text,
  contact_number text, address_line text, is_default boolean, region_code text, region_name text,
  province_code text, province_name text, city_municipality_code text, city_municipality_name text,
  barangay_code text, barangay_name text, postal_code text, street text, building text, house_no text);

-- helpers as they exist in the live database before the Officer scripts
CREATE FUNCTION public.is_staff() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = auth.uid() AND r.role IN ('admin','officer')); $$;
CREATE FUNCTION public.is_platform_admin(p_uid uuid DEFAULT auth.uid()) RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id = p_uid AND role = 'admin'); $$;
CREATE FUNCTION public.normalize_name_part(p text, label text) RETURNS text LANGUAGE sql AS $$
  SELECT nullif(btrim(p), '') $$;
CREATE FUNCTION public.normalize_middle_initial(p text) RETURNS text LANGUAGE sql AS $$
  SELECT nullif(btrim(p), '') $$;
CREATE FUNCTION public.normalize_name_suffix(p text) RETURNS text LANGUAGE sql AS $$
  SELECT nullif(btrim(p), '') $$;
CREATE FUNCTION public.compose_full_name(f text, m text, s text, x text) RETURNS text LANGUAGE sql AS $$
  SELECT btrim(concat_ws(' ', f, m, s, x)) $$;
CREATE FUNCTION public.normalize_ph_mobile(p text) RETURNS text LANGUAGE sql AS $$ SELECT nullif(btrim(p),'') $$;
CREATE FUNCTION public.is_valid_email(p text) RETURNS boolean LANGUAGE sql AS $$ SELECT p LIKE '%@%' $$;
CREATE FUNCTION public.issue_member_identifier(u uuid, r text, y int) RETURNS text LANGUAGE sql AS $$ SELECT 'ID' $$;

-- pre-existing policies (the live state recorded in role_based_staff_access.sql)
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_roles: user reads own" ON user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_roles: staff reads" ON user_roles FOR SELECT USING (public.is_staff());
CREATE POLICY "user_roles: admin updates status" ON user_roles FOR UPDATE USING (public.is_platform_admin());
ALTER TABLE user_information ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ui: read" ON user_information FOR SELECT USING (true);
ALTER TABLE admin_activity_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_activity_log: admin inserts own" ON admin_activity_log FOR INSERT
  WITH CHECK (admin_id = auth.uid() AND public.is_staff());
CREATE POLICY "admin_activity_log: admin reads all" ON admin_activity_log FOR SELECT USING (public.is_staff());
ALTER TABLE member_status_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mse: member reads own" ON member_status_events FOR SELECT USING (auth.uid() = member_id);
CREATE POLICY "mse: admin manages all" ON member_status_events FOR ALL USING (public.is_platform_admin());
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications: read" ON notifications FOR SELECT USING (auth.uid() = user_id OR public.is_staff());
CREATE POLICY "Admin insert notifications" ON notifications FOR INSERT TO public WITH CHECK
  (public.is_platform_admin(auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid()));
ALTER TABLE broadcast_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin full access to broadcast_logs (read)" ON broadcast_logs FOR SELECT USING (public.is_staff());
CREATE POLICY "Admin full access to broadcast_logs (insert)" ON broadcast_logs FOR INSERT WITH CHECK
  (public.is_platform_admin(auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "Admin full access to broadcast_logs (update)" ON broadcast_logs FOR UPDATE USING
  (public.is_platform_admin(auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "Admin full access to broadcast_logs (delete)" ON broadcast_logs FOR DELETE USING
  (public.is_platform_admin(auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid()));
ALTER TABLE cooperative_annual_totals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cooperative_annual_totals: authenticated reads" ON cooperative_annual_totals FOR SELECT
  USING (auth.role() = 'authenticated');
CREATE POLICY "cooperative_annual_totals: admin manages all (read)" ON cooperative_annual_totals FOR SELECT
  USING (public.is_staff());
CREATE POLICY "cat: insert" ON cooperative_annual_totals FOR INSERT WITH CHECK
  (public.is_platform_admin(auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid()));
CREATE POLICY "cat: update" ON cooperative_annual_totals FOR UPDATE USING
  (public.is_platform_admin(auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid()));
ALTER TABLE crop_master ENABLE ROW LEVEL SECURITY;
CREATE POLICY "crop_master: staff" ON crop_master FOR ALL USING (public.is_staff());
ALTER TABLE price_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "price_records: staff" ON price_records FOR ALL USING (public.is_staff());
ALTER TABLE farmer_loans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "farmer_loans: staff" ON farmer_loans FOR ALL USING (public.is_staff());

CREATE SCHEMA storage;
CREATE TABLE storage.buckets (id text PRIMARY KEY, name text, public boolean DEFAULT false,
  file_size_limit bigint, allowed_mime_types text[]);
CREATE TABLE storage.objects (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text, name text, owner uuid);
CREATE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT (string_to_array(name, '/'))[1:greatest(array_length(string_to_array(name, '/'), 1) - 1, 0)] $$;
-- as live (registration_08): one argument with a default
CREATE FUNCTION public.is_unapproved_applicant(p_uid uuid DEFAULT auth.uid()) RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = p_uid AND role = 'farmer' AND status IN ('draft','pending','rejected'));
$$;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Inventory images public read" ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'cooperative_inventory_images');
CREATE POLICY "Inventory images owner upload" ON storage.objects FOR INSERT TO public
  WITH CHECK (bucket_id = 'cooperative_inventory_images' AND auth.uid() IS NOT NULL
              AND (storage.foldername(name))[1] = (auth.uid())::text);
CREATE POLICY "Inventory images owner update" ON storage.objects FOR UPDATE TO public
  USING (bucket_id = 'cooperative_inventory_images' AND (storage.foldername(name))[1] = (auth.uid())::text);
CREATE POLICY "Inventory images owner delete" ON storage.objects FOR DELETE TO public
  USING (bucket_id = 'cooperative_inventory_images' AND (storage.foldername(name))[1] = (auth.uid())::text);
CREATE POLICY "Crop images public read" ON storage.objects FOR SELECT TO public USING (bucket_id = 'crop_images');
CREATE POLICY "Crop images owner upload" ON storage.objects FOR INSERT TO public
  WITH CHECK (bucket_id = 'crop_images' AND auth.uid() IS NOT NULL
              AND (storage.foldername(name))[1] = (auth.uid())::text);
CREATE POLICY "Crop images owner delete" ON storage.objects FOR DELETE TO public
  USING (bucket_id = 'crop_images' AND (storage.foldername(name))[1] = (auth.uid())::text);
CREATE POLICY "approved farmers only: product photo uploads (insert)" ON storage.objects
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id <> ALL (ARRAY['crop_images','listing_photos','cooperative_inventory_images'])) OR (NOT is_unapproved_applicant()));
ALTER TABLE cooperative_annual_totals ADD COLUMN total_coop_sales numeric DEFAULT 0, ADD COLUMN total_program_sales numeric DEFAULT 0;
CREATE TABLE member_contributions (farmer_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, year int,
  total_sales_amount numeric DEFAULT 0, program_purchases_amount numeric DEFAULT 0, UNIQUE (farmer_id, year));
ALTER TABLE capital_contribution_events ADD COLUMN created_at timestamptz DEFAULT now();
ALTER TABLE capital_contribution_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cce: admin manages all" ON capital_contribution_events FOR ALL USING (public.is_platform_admin());
CREATE POLICY "capital_contribution_events: staff reads" ON capital_contribution_events FOR SELECT USING (public.is_staff());
CREATE POLICY "cce: farmer reads own" ON capital_contribution_events FOR SELECT USING (auth.uid() = farmer_id);
ALTER TABLE member_capital_shares ENABLE ROW LEVEL SECURITY;
CREATE POLICY "member_capital_shares: admin manages all" ON member_capital_shares FOR ALL USING (public.is_platform_admin());
CREATE POLICY "member_capital_shares: staff reads" ON member_capital_shares FOR SELECT USING (public.is_staff());
CREATE POLICY "member_capital_shares: farmer reads own" ON member_capital_shares FOR SELECT USING (auth.uid() = farmer_id);
-- the live trigger that keeps the member total in step with the ledger (runs with the owner's rights)
CREATE FUNCTION public.recompute_member_capital() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public AS $$
DECLARE v_farmer uuid := COALESCE(NEW.farmer_id, OLD.farmer_id); v_total numeric;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_total FROM capital_contribution_events WHERE farmer_id = v_farmer;
  IF v_total < 0 THEN v_total := 0; END IF;
  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (v_farmer, 2000.00, v_total)
  ON CONFLICT (farmer_id) DO UPDATE SET total_contribution = EXCLUDED.total_contribution;
  RETURN NULL;
END; $$;
CREATE TRIGGER trg_cce_recompute AFTER INSERT OR UPDATE OR DELETE ON capital_contribution_events
  FOR EACH ROW EXECUTE FUNCTION public.recompute_member_capital();
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA storage TO anon, authenticated, service_role;

GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA extensions TO anon, authenticated, service_role;
`;

export async function regrant() {
  await db.exec(`
    GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
  `);
}

export function report() {
  const failed = results.filter((r) => !r.ok);
  for (const r of results) {
    console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.id.padEnd(5)} ${r.name}${r.ok ? '' : '  -> ' + r.detail}`);
  }
  console.log(`\n${results.length - failed.length} passed, ${failed.length} failed of ${results.length}`);
  return failed.length;
}
