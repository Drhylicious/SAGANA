import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared repository for the admin-managed category lookup tables
/// (inventory_categories, crop_categories — see
/// supabase_schema_category_lookup_tables.sql). Replaces the previously
/// hardcoded AppConstants.inventoryCategories / FarmerCropModel.categories
/// lists as the source for every category dropdown, so an admin can add a
/// new category directly from the dropdown without a code change.
class CategoryRepository {
  final _client = Supabase.instance.client;

  Future<List<String>> fetchInventoryCategories() =>
      _fetchNames('inventory_categories');

  Future<List<String>> fetchCropCategories() => _fetchNames('crop_categories');

  Future<List<String>> _fetchNames(String table) async {
    try {
      final rows = await _client
          .from(table)
          .select('name')
          .eq('is_active', true)
          .order('sort_order')
          .order('name');
      return rows.map((r) => r['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> addInventoryCategory(String name) =>
      _addCategory('inventory_categories', name);

  Future<String?> addCropCategory(String name) =>
      _addCategory('crop_categories', name);

  /// Inserts a new category row and returns its name — or, if a category
  /// with that name already exists (case-insensitive UNIQUE violation),
  /// returns the existing one instead of failing, since "it's already
  /// there" is a fine outcome for what the admin is trying to do.
  Future<String?> _addCategory(String table, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    try {
      final row = await _client
          .from(table)
          .insert({'name': trimmed})
          .select('name')
          .single();
      return row['name'] as String;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await _client
            .from(table)
            .select('name')
            .ilike('name', trimmed)
            .limit(1);
        if (existing.isNotEmpty) return existing.first['name'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
