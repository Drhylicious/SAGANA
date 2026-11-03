-- Run AFTER Phase 2 in Supabase SQL editor, preferably staging.
-- Requires 2 active Farmers, Manager, Officer, and an active public market type.
-- Uses real offer/accept/deliver/receipt RPCs. All test writes roll back.
BEGIN;
CREATE OR REPLACE FUNCTION pg_temp.phase2_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text,true);
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.phase2_assert(ok boolean, message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(ok,false) THEN RAISE EXCEPTION 'FAIL: %',message; END IF;
  RAISE NOTICE 'PASS: %',message;
END $$;
DO $$
DECLARE f uuid; f2 uuid; manager uuid; officer uuid; farmer uuid; staff uuid;
 cm uuid; fc uuid; hr uuid; batch uuid; offer uuid; item uuid; sale uuid; retry_sale uuid;
 mtype text; crop text := 'Zz Phase2 ' || substr(gen_random_uuid()::text,1,8);
 qty numeric; idx int := 0; req uuid := gen_random_uuid(); blocked boolean;
 before_batches jsonb; after_batches jsonb;
BEGIN
 SELECT user_id INTO f FROM user_roles WHERE role='farmer' AND status='active' AND NOT COALESCE(pending_acknowledgement,false) ORDER BY user_id LIMIT 1;
 SELECT user_id INTO f2 FROM user_roles WHERE role='farmer' AND status='active' AND NOT COALESCE(pending_acknowledgement,false) AND user_id<>f ORDER BY user_id LIMIT 1;
 SELECT user_id INTO manager FROM user_roles WHERE role='admin' AND status='active' LIMIT 1;
 SELECT user_id INTO officer FROM user_roles WHERE role='officer' AND status='active' LIMIT 1;
 SELECT code INTO mtype FROM market_types WHERE is_active AND buyer_visible ORDER BY sort_order LIMIT 1;
 IF f IS NULL OR f2 IS NULL OR manager IS NULL OR officer IS NULL OR mtype IS NULL THEN
   RAISE EXCEPTION 'Test prerequisites missing: two active Farmers, Manager, Officer and public market type are required.';
 END IF;
 INSERT INTO crop_master(crop_name,category,crop_type) VALUES(crop,'Other',mtype) RETURNING id INTO cm;
 FOREACH qty IN ARRAY ARRAY[50,30,20,60]::numeric[] LOOP
   idx := idx + 1; farmer := CASE WHEN idx=4 THEN f2 ELSE f END;
   staff := CASE WHEN idx%2=0 THEN officer ELSE manager END;
   INSERT INTO farmer_crops(farmer_id,crop_name,category,crop_master_id,photo_url)
     VALUES(farmer,crop,'Other',cm,'https://example.invalid/phase2-crop.jpg') ON CONFLICT(farmer_id,crop_name) DO NOTHING;
   SELECT id INTO fc FROM farmer_crops WHERE farmer_id=farmer AND crop_master_id=cm;
   INSERT INTO harvest_records(farmer_id,crop_id,crop_name,quantity_kg,harvest_date,storage_location,unit)
     VALUES(farmer,fc,crop,qty,DATE '2096-03-04','Test barn','kg') RETURNING id INTO hr;
   INSERT INTO inventory_batches(farmer_id,harvest_record_id,crop_id,crop_name,quantity_kg,available_kg,status,is_coop_eligible,crop_type)
     VALUES(farmer,hr,fc,crop,qty,qty,'available',true,mtype) RETURNING id INTO batch;
   PERFORM pg_temp.phase2_user(farmer);
   offer := offer_batch_to_cooperative(batch,qty,10,NULL);
   RESET ROLE;
   PERFORM pg_temp.phase2_user(staff);
   PERFORM accept_cooperative_offer(offer,1,NULL);
   blocked := false;
   BEGIN PERFORM confirm_cooperative_offer_receipt(offer,NULL); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
   PERFORM pg_temp.phase2_assert(blocked,'approval is not physical receipt');
   RESET ROLE;
   PERFORM pg_temp.phase2_assert(NOT EXISTS(SELECT 1 FROM cooperative_harvest_batches WHERE offer_id=offer),'no premature transfer');
   PERFORM pg_temp.phase2_user(farmer);
   PERFORM deliver_cooperative_offer(offer,'https://example.invalid/phase2-delivery.jpg',NULL);
   RESET ROLE;
   PERFORM pg_temp.phase2_user(staff);
   sale := confirm_cooperative_offer_receipt(offer,'Physical receipt confirmed');
   retry_sale := confirm_cooperative_offer_receipt(offer,'Retry');
   PERFORM pg_temp.phase2_assert(sale=retry_sale,'receipt retry returns the same sale');
   RESET ROLE;
   PERFORM pg_temp.phase2_assert((SELECT sold_kg=qty AND available_kg=0 AND reserved_kg=0 FROM inventory_batches WHERE id=batch),'Farmer stock settled once');
 END LOOP;
 SELECT id INTO item FROM cooperative_inventory WHERE source_farmer_id=f AND source_crop_id=cm;
 PERFORM pg_temp.phase2_assert((SELECT quantity_on_hand=100 AND source=(SELECT full_name FROM user_information WHERE user_id=f) FROM cooperative_inventory WHERE id=item),'JD crop group = 100 with real Farmer name');
 PERFORM pg_temp.phase2_assert((SELECT count(*)=3 AND sum(original_quantity)=100 FROM cooperative_harvest_batches WHERE inventory_id=item),'three preserved receipt batches');
 PERFORM pg_temp.phase2_assert((SELECT count(*)=2 AND sum(quantity_on_hand)=160 FROM cooperative_inventory WHERE source_crop_id=cm),'separate Farmer groups, total 160');
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO before_batches FROM cooperative_harvest_batches b WHERE inventory_id=item;
 PERFORM pg_temp.phase2_user(officer);
 PERFORM adjust_cooperative_stock(item,-10,'adjustment',req,'Correction');
 PERFORM adjust_cooperative_stock(item,-10,'adjustment',req,'Correction');
 PERFORM pg_temp.phase2_assert((SELECT quantity_on_hand=90 FROM cooperative_inventory WHERE id=item),'manual adjustment retry deducted once');
 blocked:=false;
 BEGIN PERFORM adjust_cooperative_stock(item,-91,'adjustment',gen_random_uuid()); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 PERFORM pg_temp.phase2_assert(blocked,'over-deduction rejected');
 UPDATE cooperative_inventory SET reorder_level=5 WHERE id=item;
 INSERT INTO loan_items_master(inventory_item_id,unit_price,is_loan_eligible) VALUES(item,10,true);
 PERFORM adjust_cooperative_stock(item,-90,'written_off',gen_random_uuid(),'Test disposal');
 PERFORM delete_inventory_item(item);
 RESET ROLE;
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO after_batches FROM cooperative_harvest_batches b WHERE inventory_id=item;
 PERFORM pg_temp.phase2_assert(before_batches=after_batches,'adjustment and archive preserve every original batch field');
 PERFORM pg_temp.phase2_assert((SELECT NOT is_active AND archived_at IS NOT NULL FROM cooperative_inventory WHERE id=item),'safe archival');
 PERFORM pg_temp.phase2_assert((SELECT count(DISTINCT action)=6 FROM cooperative_inventory_history WHERE inventory_id=item AND action IN('harvest_received','adjustment','edited','published','unpublished','archived')),'receipt, adjustment, edit, publication and archival history');
 PERFORM pg_temp.phase2_user(f);
 PERFORM pg_temp.phase2_assert(NOT EXISTS(SELECT 1 FROM cooperative_harvest_batches WHERE inventory_id=item),'Farmer cannot read cooperative receipt ledger');
 blocked:=false;
 BEGIN PERFORM adjust_cooperative_stock(item,1,'restock',gen_random_uuid()); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 PERFORM pg_temp.phase2_assert(blocked,'Farmer cannot mutate cooperative inventory');
 RESET ROLE;
 RAISE NOTICE 'PASS: Phase 2 integration; all fixture writes will now roll back.';
END $$;
ROLLBACK;
