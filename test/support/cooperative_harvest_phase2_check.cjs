const {PGlite}=require('../../.phase2_validation/node_modules/@electric-sql/pglite');
const fs=require('fs');
const assert=require('node:assert/strict');
const sql=fs.readFileSync('supabase_schema/supabase_schema_cooperative_harvest_phase2.sql','utf8');
const ids={manager:'00000000-0000-4000-8000-000000000001',officer:'00000000-0000-4000-8000-000000000002',farmer:'00000000-0000-4000-8000-000000000003',farmer2:'00000000-0000-4000-8000-000000000004',crop:'00000000-0000-4000-8000-000000000005'};
async function main(){
 const db=new PGlite();
 await db.exec(`
 CREATE ROLE authenticated; CREATE ROLE anon;
 CREATE SCHEMA auth;
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 CREATE TABLE user_information(user_id uuid primary key, full_name text);
 CREATE TABLE user_roles(user_id uuid primary key,role text);
 CREATE FUNCTION is_staff() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id=auth.uid() AND role IN ('admin','officer')) $$;
 CREATE TABLE cooperative_inventory(id uuid primary key default gen_random_uuid(), item_name text not null,category text not null,unit text not null,quantity_on_hand numeric(12,2) not null default 0 check(quantity_on_hand>=0),quantity_reserved numeric(12,2) not null default 0,reorder_level numeric default 0,unit_cost numeric,source text,created_by uuid,is_active boolean default true,last_restocked_at timestamptz,created_at timestamptz default now(),updated_at timestamptz default now());
 CREATE TABLE inventory_transactions(id uuid primary key default gen_random_uuid(),inventory_id uuid not null references cooperative_inventory(id) on delete cascade,transaction_type text,quantity numeric,notes text,recorded_by uuid,reference_id uuid,reference_type text,created_at timestamptz default now());
 CREATE UNIQUE INDEX receipt_once ON inventory_transactions(reference_id) WHERE transaction_type='harvest_received' AND reference_type='cooperative_offer';
 CREATE TABLE farmer_crops(id uuid primary key default gen_random_uuid(),farmer_id uuid,crop_master_id uuid);
 CREATE TABLE harvest_records(id uuid primary key default gen_random_uuid(), harvest_date date, storage_location text);
 CREATE TABLE inventory_batches(id uuid primary key default gen_random_uuid(),farmer_id uuid,harvest_record_id uuid,crop_id uuid,batch_number text,quantity_kg numeric,available_kg numeric,reserved_kg numeric,sold_kg numeric);
 CREATE TABLE member_sales_transactions(id uuid primary key default gen_random_uuid(),farmer_id uuid,crop_name text,crop_type text,quantity_kg numeric,amount numeric,sale_date date,recorded_by uuid);
 CREATE TABLE cooperative_purchase_offers(id uuid primary key default gen_random_uuid(),farmer_id uuid,inventory_batch_id uuid,crop_name text,unit text,status text,confirmed_at timestamptz,delivered_at timestamptz,delivery_photo_url text,received_at timestamptz,received_by uuid,member_sales_transaction_id uuid,confirmed_quantity_kg numeric,confirmed_amount numeric,coop_inventory_id uuid,receipt_note text,negotiation_round int default 1,agreed_price_per_kg numeric);
 CREATE TABLE cooperative_offer_events(offer_id uuid,round int,action text,actor_role text,actor_id uuid,price_per_kg numeric,quantity_kg numeric,note text);
 CREATE TABLE loan_items_master(id uuid primary key default gen_random_uuid(),inventory_item_id uuid unique,is_loan_eligible boolean default true);
 CREATE TABLE program_products(id uuid primary key default gen_random_uuid(),inventory_item_id uuid,is_available boolean default true);
 CREATE TABLE program_members(inventory_item_id uuid);
 CREATE FUNCTION confirm_cooperative_offer_receipt(uuid,text) RETURNS uuid LANGUAGE sql AS $$SELECT $1$$;
 CREATE FUNCTION adjust_inventory_stock(uuid,numeric,text,text,uuid) RETURNS numeric LANGUAGE sql AS $$SELECT $2$$;
 CREATE FUNCTION reconcile_batch_sold(uuid) RETURNS void LANGUAGE sql AS $$UPDATE inventory_batches SET sold_kg=(SELECT COALESCE(sum(confirmed_quantity_kg),0) FROM cooperative_purchase_offers WHERE inventory_batch_id=$1 AND status='completed') WHERE id=$1$$;
 CREATE FUNCTION _coop_offer_notify_farmer(uuid,text,text) RETURNS void LANGUAGE sql AS $$SELECT$$;
 CREATE FUNCTION _coop_offer_peso(numeric) RETURNS text LANGUAGE sql AS $$SELECT $1::text$$;
 GRANT USAGE ON SCHEMA public,auth TO authenticated,anon;
 GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
 INSERT INTO user_information VALUES('${ids.manager}','Manager'),('${ids.officer}','Officer'),('${ids.farmer}','JD'),('${ids.farmer2}','Other Farmer');
 INSERT INTO user_roles VALUES('${ids.manager}','admin'),('${ids.officer}','officer'),('${ids.farmer}','farmer'),('${ids.farmer2}','farmer');
 `);
 const q=async(s,p=[]) => (await db.query(s,p)).rows;
 const scalar=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const as=async(uid)=>db.exec(`RESET ROLE; SET request.jwt.claim.sub='${uid}'; SET ROLE authenticated;`);
 const reset=async()=>db.exec('RESET ROLE');
 async function fail(s,p=[]){let failed=false;try{await q(s,p)}catch(e){failed=true;}assert(failed,`Expected failure: ${s}`);}
 const fc=(await q('INSERT INTO farmer_crops(farmer_id,crop_master_id) VALUES($1,$2) RETURNING id',[ids.farmer,ids.crop]))[0].id;
 const hr=(await q("INSERT INTO harvest_records(harvest_date,storage_location) VALUES('2026-10-20','Barn A') RETURNING id"))[0].id;
 const source=(await q("INSERT INTO inventory_batches(farmer_id,harvest_record_id,crop_id,batch_number,quantity_kg,available_kg,reserved_kg,sold_kg) VALUES($1,$2,$3,'BATCH-JD',200,100,100,0) RETURNING id",[ids.farmer,hr,fc]))[0].id;
 async function offer(farmer,qty,sourceId=source,unit='kg'){
   return (await q("INSERT INTO cooperative_purchase_offers(farmer_id,inventory_batch_id,crop_name,unit,status,confirmed_quantity_kg,confirmed_amount,agreed_price_per_kg) VALUES($1,$2,'Tomato',$3,'delivered',$4::numeric,$4::numeric*10,10) RETURNING id",[farmer,sourceId,unit,qty]))[0].id;
 }
 // Seed one real legacy pool and receipt before the migration.
 const legacyOffer=await offer(ids.farmer,50);
 const legacyItem=await scalar("INSERT INTO cooperative_inventory(item_name,category,unit,source,quantity_on_hand) VALUES('Tomato','Harvest Stock','kg','Farmer deliveries (Offer to Cooperative)',50) RETURNING id");
 await q("UPDATE cooperative_purchase_offers SET status='completed',received_at=now(),received_by=$1,member_sales_transaction_id=gen_random_uuid(),coop_inventory_id=$2 WHERE id=$3",[ids.manager,legacyItem,legacyOffer]);
 await q("INSERT INTO inventory_transactions(inventory_id,transaction_type,quantity,reference_id,reference_type,recorded_by) VALUES($1,'harvest_received',50,$2,'cooperative_offer',$3)",[legacyItem,legacyOffer,ids.manager]);
 // A legacy offer: settled at acceptance, completed by Phase 1, never delivered or received.
 const skippedOffer=await offer(ids.farmer,40);
 const skippedSale=await scalar('SELECT gen_random_uuid()');
 await q("UPDATE cooperative_purchase_offers SET status='completed',confirmed_at=now(),received_at=now(),received_by=NULL,delivered_at=NULL,member_sales_transaction_id=$1 WHERE id=$2",[skippedSale,skippedOffer]);
 if(process.argv.includes('--inconsistent')) {
   // Delivery evidence but no receiver is inconsistent data, not a legacy offer: abort.
   await q('UPDATE cooperative_purchase_offers SET delivered_at=now() WHERE id=$1',[skippedOffer]);
   let message=''; try { await db.exec(sql); } catch(e) { message=e.message; }
   assert(message.includes('delivery/receipt activity'),message);
   await db.exec('ROLLBACK');
   assert.equal(await scalar("SELECT count(*)::int FROM information_schema.columns WHERE table_name='cooperative_inventory' AND column_name='source_farmer_id'"),0);
   console.log('PASS inconsistent completed offer: migration aborts and rolls back; nothing is stamped.');
   await db.close(); return;
 }
 if(process.argv.includes('--ambiguous')) {
   await q('UPDATE cooperative_inventory SET quantity_on_hand=49 WHERE id=$1',[legacyItem]);
   let message=''; try { await db.exec(sql); } catch(e) { message=e.message; }
   assert(message.includes('Resolve its Farmer allocation'),message);
   await db.exec('ROLLBACK');
   assert.equal(await scalar('SELECT quantity_on_hand FROM cooperative_inventory WHERE id=$1',[legacyItem]),'49.00');
   assert.equal(await scalar("SELECT count(*)::int FROM information_schema.columns WHERE table_name='cooperative_inventory' AND column_name='source_farmer_id'"),0);
   console.log('PASS ambiguous legacy pool: migration refuses guessed allocation and rolls back every schema/data change.');
   await db.close(); return;
 }
 await db.exec(sql);
 assert.equal(await scalar("SELECT quantity_on_hand FROM cooperative_inventory WHERE id=$1",[legacyItem]),'0.00');
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_harvest_batches'),1);
 // The legacy offer is skipped: no batch, no stock, no receipt transaction, no invented receiver/date.
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_harvest_batches WHERE offer_id=$1',[skippedOffer]),0);
 assert.equal(await scalar('SELECT count(*)::int FROM inventory_transactions WHERE reference_id=$1',[skippedOffer]),0);
 assert.equal(await scalar('SELECT received_by FROM cooperative_purchase_offers WHERE id=$1',[skippedOffer]),null);
 assert.equal(await scalar('SELECT coop_inventory_id FROM cooperative_purchase_offers WHERE id=$1',[skippedOffer]),null);
 assert.equal(await scalar('SELECT member_sales_transaction_id FROM cooperative_purchase_offers WHERE id=$1',[skippedOffer]),skippedSale);
 await db.exec(sql); // Repeatability, including an already-migrated pool.
 const item=await scalar('SELECT inventory_id FROM cooperative_harvest_batches WHERE offer_id=$1',[legacyOffer]);
 for(const qty of [30,20]){
  const o=await offer(ids.farmer,qty);
  await as(ids.officer);
  const tx=await scalar('SELECT confirm_cooperative_offer_receipt($1,NULL)',[o]);
  assert.equal(await scalar('SELECT confirm_cooperative_offer_receipt($1,NULL)',[o]),tx);
  await reset();
 }
 assert.equal(await scalar('SELECT quantity_on_hand FROM cooperative_inventory WHERE id=$1',[item]),'100.00');
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_harvest_batches WHERE inventory_id=$1',[item]),3);
 const fc2=await scalar('INSERT INTO farmer_crops(farmer_id,crop_master_id) VALUES($1,$2) RETURNING id',[ids.farmer2,ids.crop]);
 const source2=await scalar("INSERT INTO inventory_batches(farmer_id,harvest_record_id,crop_id,batch_number) VALUES($1,$2,$3,'BATCH-OTHER') RETURNING id",[ids.farmer2,hr,fc2]);
 const o2=await offer(ids.farmer2,60,source2);
 await as(ids.manager); await q('SELECT confirm_cooperative_offer_receipt($1,NULL)',[o2]); await reset();
 assert.equal(await scalar('SELECT sum(quantity_on_hand) FROM cooperative_inventory WHERE source_crop_id=$1',[ids.crop]),'160.00');
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_inventory WHERE source_crop_id=$1',[ids.crop]),2);
 // Unit isolation and source snapshots survive independent item operations.
 const unitOffer=await offer(ids.farmer,2,source,'sack');
 await as(ids.manager); await q('SELECT confirm_cooperative_offer_receipt($1,NULL)',[unitOffer]); await reset();
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_inventory WHERE source_farmer_id=$1',[ids.farmer]),2);
 assert.equal(await scalar('SELECT storage_location FROM cooperative_harvest_batches WHERE offer_id=$1',[unitOffer]),'Barn A');
 await q('UPDATE cooperative_inventory SET quantity_reserved=100 WHERE id=$1',[item]);
 await as(ids.officer);
 await fail("SELECT adjust_cooperative_stock($1,-1,'adjustment',gen_random_uuid())",[item]);
 await reset();
 await q('UPDATE cooperative_inventory SET quantity_reserved=0 WHERE id=$1',[item]);
 const request=await scalar('SELECT gen_random_uuid()');
 await as(ids.officer);
 await q("SELECT adjust_cooperative_stock($1,5.25,'restock',$2,'Added','2026-10-21','Barn B')",[item,request]);
 await q("SELECT adjust_cooperative_stock($1,5.25,'restock',$2,'Added','2026-10-21','Barn B')",[item,request]);
 await fail("SELECT adjust_cooperative_stock($1,6,'restock',$2,'Added','2026-10-21','Barn B')",[item,request]);
 assert.equal(await scalar('SELECT quantity_on_hand FROM cooperative_inventory WHERE id=$1',[item]),'105.25');
 // A manual restock is a Manual Stock Addition: its own batch, no offer and no source Farmer.
 const manual=await q("SELECT b.offer_id,b.source_farmer_id,b.source_farmer_name,h.reference_type,h.actor_name FROM cooperative_harvest_batches b JOIN cooperative_inventory_history h ON h.batch_id=b.id WHERE b.inventory_id=$1 AND h.action='restock'",[item]);
 assert.equal(manual.length,1);
 assert.equal(manual[0].offer_id,null); assert.equal(manual[0].source_farmer_id,null); assert.equal(manual[0].source_farmer_name,null);
 assert.equal(manual[0].reference_type,'manual'); assert.equal(manual[0].actor_name,'Officer');
 await fail("SELECT adjust_cooperative_stock($1,-106,'adjustment',gen_random_uuid())",[item]);
 await fail('SELECT delete_inventory_item($1)',[item]);
 await fail('UPDATE cooperative_inventory SET quantity_on_hand=9 WHERE id=$1',[item]);
 await fail("UPDATE cooperative_inventory SET source='Someone else' WHERE id=$1",[item]);
 await q('UPDATE cooperative_inventory SET reorder_level=20 WHERE id=$1',[item]);
 await q('INSERT INTO loan_items_master(inventory_item_id) VALUES($1)',[item]);
 await q("SELECT adjust_cooperative_stock($1,-105.25,'adjustment',gen_random_uuid(),'Stock correction')",[item]);
 await q('SELECT delete_inventory_item($1)',[item]);
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_harvest_batches WHERE inventory_id=$1',[item]),4);
 await fail('DELETE FROM cooperative_harvest_batches WHERE inventory_id=$1',[item]);
 await fail('DELETE FROM cooperative_inventory WHERE id=$1',[item]);
 await fail('DELETE FROM cooperative_inventory_history WHERE inventory_id=$1',[item]);
 await fail("SELECT adjust_inventory_stock($1,1,'restock',NULL,NULL)",[item]);
 await fail("SELECT adjust_cooperative_stock($1,NULL,'restock',gen_random_uuid())",[item]);
 await fail('SELECT _coop_receive_harvest($1)',[legacyOffer]);
 const actions=(await q('SELECT action FROM cooperative_inventory_history WHERE inventory_id=$1',[item])).map(r=>r.action);
 for(const action of ['harvest_received','restock','adjustment','edited','published','unpublished','archived']) assert(actions.includes(action),action);
 await reset();
 const o3=await offer(ids.farmer,1);
 await as(ids.manager); await q('SELECT confirm_cooperative_offer_receipt($1,NULL)',[o3]);
 assert.equal(await scalar('SELECT quantity_on_hand FROM cooperative_inventory WHERE id=$1',[item]),'1.00');
 assert.equal(await scalar('SELECT is_active FROM cooperative_inventory WHERE id=$1',[item]),true);
 await as(ids.farmer);
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_inventory_history'),0);
 assert.equal(await scalar('SELECT count(*)::int FROM cooperative_harvest_batches'),0);
 await fail("SELECT adjust_cooperative_stock($1,1,'restock',gen_random_uuid())",[item]);
 await fail('SELECT confirm_cooperative_offer_receipt($1,NULL)',[o3]);
 await reset();
 assert.equal(await scalar('SELECT sum(original_quantity) FROM cooperative_harvest_batches WHERE inventory_id=$1',[item]),'106.25');
 await db.exec(sql);
 console.log('PASS isolated PostgreSQL: migration/backfill/rerun, 50+30+20 grouping, second Farmer 60, receipt retries, manual idempotency, exact decimals, immutable provenance, audit events, archive/restore, role isolation and direct-write guards.');
 await db.close();
}
main().catch(e=>{console.error(e.message);console.error(e.where ?? '');process.exit(1);});
