-- Reference data for the LOCAL test database only (the schema dump carries no data).
-- Safe to re-run.
INSERT INTO batch_prefix_state (id, last_index) VALUES (1, 0) ON CONFLICT (id) DO NOTHING;

INSERT INTO market_types (code, name, name_tl, buyer_visible, manager_sets_price, sort_order) VALUES
  ('open_market',     'Public Market',      'Pampublikong Pamilihan',   true,  false, 1),
  ('sp3_cooperative', 'Cooperative Market', 'Pamilihan ng Kooperatiba', false, true,  2)
ON CONFLICT (code) DO NOTHING;

INSERT INTO selling_channels (code, name, requires_exclusive_crop, sort_order) VALUES
  ('marketplace',            'Marketplace',               false, 1),
  ('offer_to_cooperative',   'Offer to Cooperative',      false, 2),
  ('informal_sale',          'Informal Sale',             false, 3),
  ('da_amad_market_linking', 'DA-AMAD Market Linking',    true,  4)
ON CONFLICT (code) DO NOTHING;

INSERT INTO units (name, sort_order) VALUES
  ('kg',1),('sack',2),('bag',3),('piece',4),('bundle',5),('liter',6)
ON CONFLICT DO NOTHING;

INSERT INTO crop_categories (name, sort_order) VALUES ('Vegetables',1),('Grains',2),('Spices',3),('Other',9) ON CONFLICT DO NOTHING;
INSERT INTO expense_categories (name, sort_order) VALUES ('Seeds',1),('Fertilizer',2),('Labor',3),('Other',9) ON CONFLICT DO NOTHING;
INSERT INTO inventory_categories (name, sort_order) VALUES ('Agricultural Supplies',1),('Harvest Stock',2),('Tools',3) ON CONFLICT DO NOTHING;
INSERT INTO farm_ownership_types (name, sort_order) VALUES ('Owner',1),('Tenant',2) ON CONFLICT DO NOTHING;
INSERT INTO program_types (name, sort_order) VALUES ('Seed Distribution',1),('Product Sales',2) ON CONFLICT DO NOTHING;

INSERT INTO crop_master (crop_name, category, crop_type, shelf_life_days, storage_life_days) VALUES
  ('Tomato', 'Vegetables', 'open_market',     7,  NULL),
  ('Palay',  'Grains',     'sp3_cooperative', 180, 365),
  ('Peanut', 'Grains',     'sp3_cooperative', 120, 365),
  ('Eggplant','Vegetables','open_market',     6,  NULL)
ON CONFLICT (crop_name) DO NOTHING;
INSERT INTO crop_master (crop_name, category, crop_type, shelf_life_days, exclusive_channel) VALUES
  ('Ginger', 'Spices', 'open_market', 60, 'da_amad_market_linking')
ON CONFLICT (crop_name) DO NOTHING;

INSERT INTO loan_policy_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
INSERT INTO farmer_dashboard_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
INSERT INTO shelf_life_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;
INSERT INTO delivery_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;
INSERT INTO cooperative_details (id) VALUES (true) ON CONFLICT (id) DO NOTHING;
INSERT INTO capital_share_rates (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
INSERT INTO capital_share_rate_versions (purchase_percent, offer_percent)
  SELECT 10, 10 WHERE NOT EXISTS (SELECT 1 FROM capital_share_rate_versions);

-- Price references (Fixed Price) so listings can be created.
INSERT INTO price_records (crop_name, crop_id, price, unit, price_type, source)
SELECT 'Tomato', id, 50, 'kg', 'open_market', 'test' FROM crop_master WHERE crop_name='Tomato'
  AND NOT EXISTS (SELECT 1 FROM price_records);
