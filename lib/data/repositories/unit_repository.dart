import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/input_validation_utils.dart';
import '../models/admin_log_message.dart';
import 'admin_activity_repository.dart';

/// What happened when a unit was added.
enum AddUnitOutcome { added, duplicate, invalid, failed }

class AddUnitResult {
  final AddUnitOutcome outcome;

  /// The unit as stored (for [AddUnitOutcome.added] and
  /// [AddUnitOutcome.duplicate], the existing spelling).
  final String? name;
  const AddUnitResult(this.outcome, [this.name]);
}

/// The unit-of-measure list shared by Inventory Management and Price
/// Management (public.units — see supabase_schema_units.sql). Same shape as
/// CategoryRepository: names only, since consuming tables keep the unit as
/// plain text.
class UnitRepository {
  final _client = Supabase.instance.client;

  /// Used only when the table cannot be read (before the migration has run, or
  /// offline with nothing cached), so the forms stay usable. These are the
  /// units the two screens offered before the table existed.
  static const fallbackUnits = [
    'kg',
    'g',
    'sack',
    'bag',
    'piece',
    'liter',
    'set',
    'bottle',
  ];

  Future<List<String>> fetchUnits() async {
    try {
      final rows = await _client
          .from('units')
          .select('name')
          .eq('is_active', true)
          .order('sort_order')
          .order('name');
      final names = rows.map((r) => r['name'] as String).toList();
      return names.isEmpty ? fallbackUnits : names;
    } catch (_) {
      return fallbackUnits;
    }
  }

  /// Adds [raw] as a new unit. A name that already exists (ignoring case and
  /// spacing) is reported as a duplicate, not added twice.
  Future<AddUnitResult> addUnit(String raw) async {
    if (checkUnitName(raw) != null) {
      return const AddUnitResult(AddUnitOutcome.invalid);
    }
    final name = normalizeUnitName(raw);
    try {
      final row = await _client
          .from('units')
          .insert({'name': name})
          .select('name')
          .single();
      final added = row['name'] as String;
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'unit_added',
        message: AdminLogMessage('adminLogUnitAdded', {'name': added}),
      );
      return AddUnitResult(AddUnitOutcome.added, added);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await _client
            .from('units')
            .select('name')
            .ilike('name', name)
            .limit(1);
        return AddUnitResult(
          AddUnitOutcome.duplicate,
          existing.isNotEmpty ? existing.first['name'] as String : name,
        );
      }
      return const AddUnitResult(AddUnitOutcome.failed);
    } catch (_) {
      return const AddUnitResult(AddUnitOutcome.failed);
    }
  }
}
