-- ============================================================
-- SAGANA — Listing edit approval + staff history: scenario test
--
--   1. a Farmer asks to change an APPROVED listing: nothing changes yet (listing,
--      batch, orders), only one open request, and the direct edit is refused
--   2. the Manager approves: the change is applied, stock and remaining quantity
--      move by the difference, the existing order keeps its price, the Farmer is told
--   3. a second request is disapproved: a reason is required, only the request is
--      rejected, the listing is untouched, the Farmer is told the reason
--   4. approval re-checks the listing as it is NOW (an order that came in meanwhile
--      blocks a quantity that is no longer allowed)
--   5. the Farmer can cancel their own open request
--   6. history: staff see the actor of every step (separately, with their role);
--      the Farmer sees "you" / "cooperative" and no staff identity, and cannot
--      read the history or request tables directly
--   7. Marketplace orders are recorded with the staff member who acted
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report (PASS / FAIL / SKIP lines).
--
-- Run supabase_schema_listing_edit_approval.sql first, then this whole file.
-- ============================================================

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.chk(p_ok boolean, p_label text, p_detail text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN COALESCE(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_label ||
         CASE WHEN p_detail IS NULL THEN '' ELSE ' — ' || p_detail END || E'\n';
$$;

DO $test$
DECLARE
  v_rep  TEXT := E'\n';
  v_fail INT;
  F UUID; M UUID; B UUID; OFC UUID;
  v_mtype TEXT;
  v_unit  TEXT;
  v_name  CONSTANT TEXT := 'Zz Edit Approval Test Crop';
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID; v_listing UUID; v_o1 UUID; v_o2 UUID;
  v_req UUID; v_req2 UUID; v_req3 UUID;
  bt  inventory_batches%ROWTYPE;
  l   marketplace_listings%ROWTYPE;
  o   orders%ROWTYPE;
  rq  listing_edit_requests%ROWTYPE;
  v_msg TEXT;
  v_n   INT;
  v_json JSONB;
  v_body TEXT;
  ev    workflow_events%ROWTYPE;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' ORDER BY user_id LIMIT 1;
  SELECT user_id INTO OFC FROM user_roles WHERE role = 'officer' AND status = 'active' ORDER BY user_id LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' ORDER BY user_id LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'sack') THEN 'sack' ELSE 'kg' END INTO v_unit;

  IF F IS NULL OR M IS NULL OR B IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'LISTING EDIT APPROVAL TEST REPORT\nSKIP everything: needs an active farmer, admin and buyer and a buyer-visible market type (found: farmer=%, admin=%, buyer=%, market=%)', F, M, B, v_mtype;
  END IF;
  IF to_regprocedure('public.request_listing_edit(uuid,numeric,numeric,text,text)') IS NULL THEN
    RAISE EXCEPTION E'LISTING EDIT APPROVAL TEST REPORT\nSKIP everything: run supabase_schema_listing_edit_approval.sql first.';
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', manager ' || M || ', officer ' || COALESCE(OFC::text, 'none') || ', unit "' || v_unit || E'"\n';

  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    VALUES (F, v_name, 'Other', v_cm, 'https://example.invalid/zz-approval-1.jpg') RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 10.75, DATE '2096-03-08', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 10.75, 10.75, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;

  -- A published listing with one order against it.
  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, v_name, NULL, 4.25, 12.50, NULL, 'First description');
  RESET ROLE;
  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_listing);
  RESET ROLE;
  PERFORM pg_temp.as_user(B);
  v_o1 := place_order(v_listing, 1.25);
  RESET ROLE;

  -- ═════ 1. The request changes nothing ═════
  PERFORM pg_temp.as_user(F);
  v_req := request_listing_edit(v_listing, 6.00, 20.00, 'New description', NULL);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req;
  v_rep := v_rep || pg_temp.chk(rq.status = 'pending' AND rq.original_quantity = 4.25 AND rq.proposed_quantity = 6.00
      AND rq.original_price = 12.50 AND rq.proposed_price = 20.00 AND rq.unit = v_unit,
    '1.1 the request keeps the original and the proposed values',
    rq.original_quantity || '->' || rq.proposed_quantity || ' ' || rq.original_price || '->' || rq.proposed_price || ' ' || rq.status);
  v_rep := v_rep || pg_temp.chk(l.status = 'approved' AND l.volume_kg = 4.25 AND l.remaining_kg = 3.00
      AND l.price_per_kg = 12.50 AND l.description = 'First description',
    '1.2 the published listing is untouched while the request waits', l.status || ' ' || l.volume_kg || '/' || l.remaining_kg || ' @ ' || l.price_per_kg);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 6.50, '1.3 no stock moved yet (available still 6.50)', bt.available_kg::text);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM request_listing_edit(v_listing, 5.00, 15.00, 'Another', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%already have an edit request%', '1.4 only one open request per listing', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 5.00, 15.00, 'Direct', FALSE); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%edit request for approval%', '1.5 an approved listing can no longer be edited directly', v_msg);

  PERFORM pg_temp.as_user(F);
  SELECT count(*) INTO v_n FROM listing_edit_requests;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n = 0, '1.6 a Farmer cannot read the request table directly (it holds the reviewer)', v_n::text);
  PERFORM pg_temp.as_user(F);
  SELECT count(*) INTO v_n FROM workflow_events;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n = 0, '1.7 a Farmer cannot read the staff history table', v_n::text);

  PERFORM pg_temp.as_user(B);
  v_msg := NULL;
  BEGIN PERFORM request_listing_edit(v_listing, 5.00, 15.00, 'Buyer', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE 'Only an active Farmer%', '1.8 a Buyer cannot send an edit request', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM approve_listing_edit(v_req); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE 'Unauthorized%', '1.9 a Farmer cannot approve their own request', v_msg);

  -- ═════ 2. Approval applies it ═════
  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing_edit(v_req);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req;
  SELECT * INTO o FROM orders WHERE id = v_o1;
  v_rep := v_rep || pg_temp.chk(l.status = 'approved' AND l.volume_kg = 6.00 AND l.remaining_kg = 4.75
      AND l.price_per_kg = 20.00 AND l.description = 'New description',
    '2.1 approved: the listing now reads 6.00 @ 20.00, remaining 4.75 (6.00 - 1.25 ordered)', l.volume_kg || '/' || l.remaining_kg || ' @ ' || l.price_per_kg);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 4.75 AND bt.available_kg + bt.reserved_kg + bt.sold_kg + bt.adjusted_kg = bt.quantity_kg,
    '2.2 the batch reserved the extra 1.75 and still adds up', bt.available_kg || ' + ' || bt.reserved_kg || ' + ' || bt.sold_kg || ' + ' || bt.adjusted_kg || ' = ' || bt.quantity_kg);
  v_rep := v_rep || pg_temp.chk(o.quantity_kg = 1.25 AND o.price_per_kg = 12.50 AND o.total_price = 15.63,
    '2.3 the existing order keeps its own quantity and price', o.quantity_kg || ' x ' || o.price_per_kg || ' = ' || o.total_price);
  v_rep := v_rep || pg_temp.chk(rq.status = 'approved' AND rq.reviewed_by = M AND rq.reviewed_at IS NOT NULL,
    '2.4 the request records who approved it, and when', rq.status || ' by ' || COALESCE(rq.reviewed_by::text, 'nobody'));
  SELECT body INTO v_body FROM notifications WHERE user_id = F AND title = 'Listing Changes Approved' ORDER BY created_at DESC LIMIT 1;
  v_rep := v_rep || pg_temp.chk(v_body IS NOT NULL, '2.5 the Farmer is told the changes are live', v_body);

  -- ═════ 3. Disapproval: reason required, listing untouched ═════
  PERFORM pg_temp.as_user(F);
  v_req2 := request_listing_edit(v_listing, 7.00, 25.00, 'Even newer', NULL);
  RESET ROLE;

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM reject_listing_edit(v_req2, '   '); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%reason%', '3.1 disapproving without a reason is refused', v_msg);

  IF OFC IS NOT NULL THEN
    PERFORM pg_temp.as_user(OFC);
    PERFORM reject_listing_edit(v_req2, 'The price is far above the market price.');
    RESET ROLE;
  ELSE
    PERFORM pg_temp.as_user(M);
    PERFORM reject_listing_edit(v_req2, 'The price is far above the market price.');
    RESET ROLE;
  END IF;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req2;
  v_rep := v_rep || pg_temp.chk(rq.status = 'rejected' AND rq.review_reason LIKE 'The price is far%' AND rq.reviewed_by IS NOT NULL,
    '3.2 only the request is rejected, with its reason and reviewer', rq.status || ' / ' || COALESCE(rq.review_reason, 'no reason'));
  v_rep := v_rep || pg_temp.chk(l.status = 'approved' AND l.volume_kg = 6.00 AND l.price_per_kg = 20.00 AND bt.available_kg = 4.75,
    '3.3 the published listing and the stock are unchanged', l.status || ' ' || l.volume_kg || ' @ ' || l.price_per_kg || ', batch ' || bt.available_kg);
  SELECT body INTO v_body FROM notifications WHERE user_id = F AND title = 'Listing Changes Disapproved' ORDER BY created_at DESC LIMIT 1;
  v_rep := v_rep || pg_temp.chk(v_body LIKE '%far above the market price%', '3.4 the Farmer is told the reason', v_body);

  -- ═════ 4. Approval re-checks the listing as it is now ═════
  PERFORM pg_temp.as_user(F);
  v_req3 := request_listing_edit(v_listing, 3.00, 20.00, 'Smaller', NULL);   -- ordered so far: 1.25
  RESET ROLE;
  PERFORM pg_temp.as_user(B);
  v_o2 := place_order(v_listing, 2.00);                                       -- ordered now: 3.25
  RESET ROLE;
  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM approve_listing_edit(v_req3); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%already ordered%', '4.1 an order that came in meanwhile blocks a quantity that is no longer allowed', v_msg);
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req3;
  v_rep := v_rep || pg_temp.chk(rq.status = 'pending', '4.2 the blocked request stays open for the staff to disapprove', rq.status);

  -- ═════ 5. The Farmer cancels their own request ═════
  PERFORM pg_temp.as_user(F);
  PERFORM cancel_listing_edit_request(v_req3);
  RESET ROLE;
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req3;
  v_rep := v_rep || pg_temp.chk(rq.status = 'cancelled', '5.1 the Farmer can cancel their own open request', rq.status);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM request_listing_edit(v_listing, 99, 20.00, 'Too big', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%Not enough available quantity%', '5.2 a request for more than the batch holds is refused straight away', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM request_listing_edit(v_listing, 6.00, 20.00, 'New description', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%not changed anything%', '5.3 a request that changes nothing is refused', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM request_listing_edit(v_listing, 6.00, 20.00, 'Photo', 'https://evil.example/photo.jpg'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%not uploaded from your account%', '5.4 a photo that is not the Farmer''s own upload is refused', v_msg);

  -- ═════ 6. History ═════
  PERFORM pg_temp.as_user(M);
  SELECT count(*) INTO v_n FROM workflow_events WHERE entity_type = 'listing' AND entity_id = v_listing;
  SELECT * INTO ev FROM workflow_events
   WHERE entity_type = 'listing' AND entity_id = v_listing AND action = 'approved' LIMIT 1;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(ev.actor_id = M AND ev.actor_role = 'admin' AND ev.from_status = 'pending_review' AND ev.to_status = 'approved',
    '6.1 staff see who approved the NEW listing, with role and statuses', COALESCE(ev.actor_id::text, 'no actor') || ' ' || COALESCE(ev.actor_role, ''));
  SELECT * INTO ev FROM workflow_events
   WHERE entity_type = 'listing' AND entity_id = v_listing AND action = 'edit_approved' LIMIT 1;
  v_rep := v_rep || pg_temp.chk(ev.actor_id = M AND ev.details -> 'changes' -> 'price' ->> 'to' = '20.00',
    '6.2 ... and who approved the EDIT, with what changed', COALESCE(ev.details::text, 'no event'));
  SELECT * INTO ev FROM workflow_events
   WHERE entity_type = 'listing' AND entity_id = v_listing AND action = 'edit_rejected' LIMIT 1;
  v_rep := v_rep || pg_temp.chk(ev.actor_id IS NOT NULL AND ev.reason LIKE 'The price is far%' AND ev.actor_role IN ('admin', 'officer'),
    '6.3 ... and who disapproved an edit, with the reason', COALESCE(ev.actor_role, 'no event') || ': ' || COALESCE(ev.reason, ''));
  SELECT count(*) INTO v_n FROM workflow_events
   WHERE entity_type = 'listing' AND entity_id = v_listing AND action IN ('submitted', 'approved', 'edit_requested', 'edit_approved', 'edit_rejected', 'edit_cancelled');
  v_rep := v_rep || pg_temp.chk(v_n = 8, '6.4 submitted, approved, 3 requests, approval, disapproval and cancellation = 8 history rows', v_n::text);

  PERFORM pg_temp.as_user(F);
  v_json := get_my_listing_history(v_listing);
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(jsonb_array_length(v_json) >= 8, '6.5 the Farmer can read their listing''s history', jsonb_array_length(v_json)::text);
  v_rep := v_rep || pg_temp.chk(NOT (v_json::text LIKE '%actor_id%') AND NOT (v_json::text LIKE '%' || M::text || '%'),
    '6.6 ... and it carries no staff identity', 'no actor_id, no manager id');
  v_rep := v_rep || pg_temp.chk(v_json::text LIKE '%"by": "cooperative"%' AND v_json::text LIKE '%"by": "you"%',
    '6.7 ... only "you" and "cooperative"', 'ok');
  v_rep := v_rep || pg_temp.chk(v_json::text LIKE '%far above the market price%', '6.8 ... including the disapproval reason', 'ok');

  PERFORM pg_temp.as_user(F);
  v_json := get_my_listing_edit_requests(v_listing);
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(jsonb_array_length(v_json) = 3 AND NOT (v_json::text LIKE '%reviewed_by%'),
    '6.9 the Farmer''s request list has the 3 requests and no reviewer', jsonb_array_length(v_json)::text);

  PERFORM pg_temp.as_user(B);
  v_json := get_my_listing_history(v_listing);
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(jsonb_array_length(v_json) = 0, '6.10 someone else''s listing history comes back empty', jsonb_array_length(v_json)::text);

  -- ═════ 7. Orders: who did what ═════
  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_o1);
  RESET ROLE;
  PERFORM pg_temp.as_user(M);
  SELECT * INTO ev FROM workflow_events WHERE entity_type = 'order' AND entity_id = v_o1 AND action = 'approved' LIMIT 1;
  SELECT count(*) INTO v_n FROM workflow_events WHERE entity_type = 'order' AND entity_id = v_o1;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(ev.actor_id = M AND ev.from_status = 'pending' AND ev.to_status = 'approved',
    '7.1 the Manager who approved the order is recorded', COALESCE(ev.actor_id::text, 'no actor'));
  SELECT * INTO ev FROM workflow_events WHERE entity_type = 'order' AND entity_id = v_o1 AND action = 'placed' LIMIT 1;
  v_rep := v_rep || pg_temp.chk(ev.actor_id = B AND v_n = 2, '7.2 the Buyer who placed it is recorded too (2 rows so far)', COALESCE(ev.actor_id::text, 'no actor') || ', ' || v_n);

  IF OFC IS NOT NULL THEN
    v_msg := NULL;
    BEGIN
      PERFORM pg_temp.as_user(OFC);
      PERFORM mark_order_ready_for_pickup(v_o1);
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    SELECT * INTO ev FROM workflow_events WHERE entity_type = 'order' AND entity_id = v_o1 AND action = 'ready_for_pickup' LIMIT 1;
    IF ev.id IS NOT NULL THEN
      v_rep := v_rep || pg_temp.chk(ev.actor_id = OFC AND ev.actor_role = 'officer' AND ev.actor_id <> M,
        '7.3 a different staff member''s step is its own row, with the Officer role', ev.actor_role || ' ' || ev.actor_id);
    ELSE
      v_rep := v_rep || E'SKIP 7.3 officer fulfilment step (' || COALESCE(v_msg, 'the order is a delivery order or the step name differs') || E')\n';
    END IF;
  ELSE
    v_rep := v_rep || E'SKIP 7.3 two different staff members on one order (no active officer exists)\n';
  END IF;

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'LISTING EDIT APPROVAL TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
