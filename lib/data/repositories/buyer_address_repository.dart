import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/buyer_address_model.dart';
import 'buyer_profile_repository.dart';

/// Buyer-scoped access to buyer_addresses (My Addresses). Keyed by
/// auth.users.id regardless of the caller's active role — farmer-as-buyer
/// shares this same address book, same convention as orders.buyer_id
/// already accepting farmer callers. No RPC layer: an address row only
/// ever touches its own owner, so plain RLS-scoped .from() calls are
/// sufficient (unlike orders, which needs RPCs for cross-user guards).
class BuyerAddressRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<BuyerAddressModel>> fetchAddresses() async {
    try {
      final rows = await _client
          .from('buyer_addresses')
          .select()
          .eq('user_id', _userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return rows.map((r) => BuyerAddressModel.fromMap(r)).toList();
    } catch (e) {
      debugPrint('BuyerAddressRepository.fetchAddresses failed: $e');
      return [];
    }
  }

  Future<BuyerAddressModel?> fetchDefaultAddress() async {
    try {
      final row = await _client
          .from('buyer_addresses')
          .select()
          .eq('user_id', _userId)
          .eq('is_default', true)
          .maybeSingle();
      return row != null ? BuyerAddressModel.fromMap(row) : null;
    } catch (e) {
      debugPrint('BuyerAddressRepository.fetchDefaultAddress failed: $e');
      return null;
    }
  }

  // Writes rethrow rather than swallow — the caller (Add/Edit Address
  // screen) needs to show the buyer a real error, not silently no-op.

  Future<String> addAddress({
    required String label,
    String? recipientName,
    String? contactNumber,
    required String addressLine,
    double? latitude,
    double? longitude,
    String? notes,
    bool isDefault = false,
    BuyerAddressStructure? structure,
  }) async {
    // First address ever is always usable immediately, regardless of
    // whatever the caller passed — no separate "set default" tap needed.
    final existing = await fetchAddresses();
    final effectiveIsDefault = existing.isEmpty ? true : isDefault;

    final row = await _client
        .from('buyer_addresses')
        .insert({
          'user_id': _userId,
          'label': label,
          'recipient_name': recipientName,
          'contact_number': contactNumber,
          'address_line': addressLine,
          'latitude': latitude,
          'longitude': longitude,
          'notes': notes,
          'is_default': effectiveIsDefault,
          ...?structure?.toColumns(),
        })
        .select('id')
        .single();
    await BuyerProfileRepository().logActivity('Added address ($label)');
    return row['id'] as String;
  }

  Future<void> updateAddress({
    required String id,
    required String label,
    String? recipientName,
    String? contactNumber,
    required String addressLine,
    double? latitude,
    double? longitude,
    String? notes,
    BuyerAddressStructure? structure,
    // true: the structure is replaced as a whole, so cleared optional
    // fields are saved as NULL. false: only non-null fields are written.
    bool replaceStructure = false,
  }) async {
    await _client
        .from('buyer_addresses')
        .update({
          'label': label,
          'recipient_name': recipientName,
          'contact_number': contactNumber,
          'address_line': addressLine,
          'latitude': latitude,
          'longitude': longitude,
          'notes': notes,
          'updated_at': DateTime.now().toIso8601String(),
          ...?structure?.toColumns(includeNulls: replaceStructure),
        })
        .eq('id', id);
    await BuyerProfileRepository().logActivity('Updated address ($label)');
  }

  Future<void> deleteAddress(String id) async {
    final existing = await _client
        .from('buyer_addresses')
        .select('label, is_default')
        .eq('id', id)
        .maybeSingle();

    await _client.from('buyer_addresses').delete().eq('id', id);

    final label = existing?['label'] as String?;
    if (label != null) {
      await BuyerProfileRepository().logActivity('Deleted address ($label)');
    }

    if (existing?['is_default'] == true) {
      final remaining = await fetchAddresses();
      if (remaining.isNotEmpty) {
        // Automatic reassignment, not a distinct action the buyer took —
        // don't log a second "Set X as default" entry right under the
        // "Deleted address" one above.
        await setDefaultAddress(remaining.first.id, logActivity: false);
      }
    }
  }

  // logActivity: false for callers where setting the default is an
  // implicit side effect of a different action already being logged
  // (adding a brand-new address as default, or the automatic reassignment
  // in deleteAddress above) rather than a distinct "Set as default" tap —
  // avoids a redundant second log entry for one buyer action. Still
  // unsets every other address's is_default regardless — that DB-level
  // behavior is never optional, only the logging is.
  Future<void> setDefaultAddress(String id, {bool logActivity = true}) async {
    final existing = await _client
        .from('buyer_addresses')
        .select('label')
        .eq('id', id)
        .maybeSingle();

    await _client
        .from('buyer_addresses')
        .update({'is_default': false})
        .eq('user_id', _userId);
    await _client
        .from('buyer_addresses')
        .update({'is_default': true})
        .eq('id', id);

    final label = existing?['label'] as String?;
    if (logActivity && label != null) {
      await BuyerProfileRepository().logActivity(
        'Set "$label" as default address',
      );
    }
  }
}
