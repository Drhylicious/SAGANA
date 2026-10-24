import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/utils/client_id.dart';
import '../models/buyer_address_model.dart';
import '../services/offline_actions.dart';
import 'buyer_profile_repository.dart';
import '../models/admin_log_message.dart';

/// Buyer-scoped access to buyer_addresses (My Addresses). Keyed by
/// auth.users.id regardless of the caller's active role — farmer-as-buyer
/// shares this same address book, same convention as orders.buyer_id
/// already accepting farmer callers. No RPC layer: an address row only
/// ever touches its own owner, so plain RLS-scoped .from() calls are
/// sufficient (unlike orders, which needs RPCs for cross-user guards).
///
/// Writes are saved now when the server is reachable, otherwise kept on the
/// device until the next manual Sync (see OfflineActions).
class BuyerAddressRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<BuyerAddressModel>> fetchAddresses() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'buyer_addresses',
        fetch: () => _client
            .from('buyer_addresses')
            .select()
            .eq('user_id', _userId)
            .order('is_default', ascending: false)
            .order('created_at', ascending: false),
      );
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

  /// Returns the new address id. Offline, the id is generated on the device
  /// and used as the row's primary key when the address syncs.
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
    final id = newClientId();
    final structureColumns = structure?.toColumns();
    await OfflineActions.run(
      kind: 'address_add',
      payload: {
        'id': id,
        'label': label,
        'recipientName': recipientName,
        'contactNumber': contactNumber,
        'addressLine': addressLine,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
        'isDefault': isDefault,
        'structureColumns': structureColumns,
      },
      queueWhenOffline: false,
      online: () => addAddressOnline(
        id: id,
        label: label,
        recipientName: recipientName,
        contactNumber: contactNumber,
        addressLine: addressLine,
        latitude: latitude,
        longitude: longitude,
        notes: notes,
        isDefault: isDefault,
        structureColumns: structureColumns,
      ),
    );
    return id;
  }

  /// The server write behind addAddress(). Also run by offline replay. If a
  /// row with [id] already exists (an earlier replay inserted it before
  /// failing), nothing is inserted again.
  Future<String> addAddressOnline({
    String? id,
    required String label,
    String? recipientName,
    String? contactNumber,
    required String addressLine,
    double? latitude,
    double? longitude,
    String? notes,
    bool isDefault = false,
    Map<String, dynamic>? structureColumns,
  }) async {
    if (id != null) {
      final existing = await _client
          .from('buyer_addresses')
          .select('id')
          .eq('id', id)
          .maybeSingle();
      if (existing != null) return id;
    }

    // First address ever is always usable immediately, regardless of
    // whatever the caller passed — no separate "set default" tap needed.
    final existingAddresses = await fetchAddresses();
    final effectiveIsDefault = existingAddresses.isEmpty ? true : isDefault;

    final row = await _client
        .from('buyer_addresses')
        .insert({
          if (id != null) 'id': id,
          'user_id': _userId,
          'label': label,
          'recipient_name': recipientName,
          'contact_number': contactNumber,
          'address_line': addressLine,
          'latitude': latitude,
          'longitude': longitude,
          'notes': notes,
          'is_default': effectiveIsDefault,
          ...?structureColumns,
        })
        .select('id')
        .single();
    await BuyerProfileRepository().logActivity(
      AdminLogMessage('activityAddressAdded', {'label': '$label'}),
    );
    return row['id'] as String;
  }

  Future<SaveOutcome> updateAddress({
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
  }) {
    final structureColumns = structure?.toColumns(
      includeNulls: replaceStructure,
    );
    return OfflineActions.run(
      kind: 'address_update',
      payload: {
        'id': id,
        'label': label,
        'recipientName': recipientName,
        'contactNumber': contactNumber,
        'addressLine': addressLine,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
        'structureColumns': structureColumns,
      },
      queueWhenOffline: false,
      online: () => updateAddressOnline(
        id: id,
        label: label,
        recipientName: recipientName,
        contactNumber: contactNumber,
        addressLine: addressLine,
        latitude: latitude,
        longitude: longitude,
        notes: notes,
        structureColumns: structureColumns,
      ),
    );
  }

  /// The server write behind updateAddress(). Also run by offline replay.
  Future<void> updateAddressOnline({
    required String id,
    required String label,
    String? recipientName,
    String? contactNumber,
    required String addressLine,
    double? latitude,
    double? longitude,
    String? notes,
    Map<String, dynamic>? structureColumns,
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
          ...?structureColumns,
        })
        .eq('id', id);
    await BuyerProfileRepository().logActivity(
      AdminLogMessage('activityAddressUpdated', {'label': '$label'}),
    );
  }

  Future<SaveOutcome> deleteAddress(String id) {
    return OfflineActions.run(
      kind: 'address_delete',
      payload: {'id': id},
      queueWhenOffline: false,
      online: () => deleteAddressOnline(id),
    );
  }

  /// The server write behind deleteAddress(). Also run by offline replay.
  Future<void> deleteAddressOnline(String id) async {
    final existing = await _client
        .from('buyer_addresses')
        .select('label, is_default')
        .eq('id', id)
        .maybeSingle();

    await _client.from('buyer_addresses').delete().eq('id', id);

    final label = existing?['label'] as String?;
    if (label != null) {
      await BuyerProfileRepository().logActivity(
        AdminLogMessage('activityAddressDeleted', {'label': '$label'}),
      );
    }

    if (existing?['is_default'] == true) {
      final remaining = await fetchAddresses();
      if (remaining.isNotEmpty) {
        // Automatic reassignment, not a distinct action the buyer took —
        // don't log a second "Set X as default" entry right under the
        // "Deleted address" one above.
        await setDefaultAddressOnline(remaining.first.id, logActivity: false);
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
  Future<SaveOutcome> setDefaultAddress(String id, {bool logActivity = true}) {
    return OfflineActions.run(
      kind: 'address_default',
      payload: {'id': id, 'logActivity': logActivity},
      queueWhenOffline: false,
      online: () => setDefaultAddressOnline(id, logActivity: logActivity),
    );
  }

  /// The server write behind setDefaultAddress(). Also run by offline replay.
  Future<void> setDefaultAddressOnline(
    String id, {
    bool logActivity = true,
  }) async {
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
        AdminLogMessage('activityAddressDefault', {'label': '$label'}),
      );
    }
  }
}
