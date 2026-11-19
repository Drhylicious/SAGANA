-- Clears transactional test data (keeps accounts + reference data). LOCAL test DB only.
TRUNCATE orders, marketplace_listings, inventory_batches, harvest_records, stock_movements,
  farmer_loans, loan_requests, notifications, workflow_events, member_restrictions, admin_activity_log,
  batch_number_counters, order_number_counters, loan_reference_counters, loan_request_counters,
  checkout_groups, cooperative_purchase_offers, informal_sales, market_linking_programs,
  shelf_life_events, listing_edit_requests
RESTART IDENTITY CASCADE;
DELETE FROM units WHERE name IN ('viewtest','mgrtest');
