import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cooperative_delivery_model.dart';
import '../services/server_only.dart';

/// Cooperative Details, the Delivery switch, the fee bands and delivery quotes.
///
/// Reads work for every signed-in role that needs them (a consumer reads the
/// cooperative's name, address and contact; only staff receive the map pin and the list of
/// what is missing). Every write is a Manager-only database function. Writes throw (the
/// PostgrestException is kept as it is, so friendlyError() can read its code).
class CooperativeDeliveryRepository {
  final SupabaseClient _client;
  CooperativeDeliveryRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<T> _write<T>(Future<T> Function() call) async {
    await ServerOnly.ensureOnline();
    return call();
  }

  Future<CooperativeDetails> fetchDetails() async {
    final res = await _client.rpc('get_cooperative_details');
    return CooperativeDetails.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Delivery is off when the database cannot be reached: it is never assumed on.
  Future<DeliveryStatus> fetchDeliveryStatus() async {
    try {
      final res = await _client.rpc('get_delivery_status');
      return DeliveryStatus.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return DeliveryStatus.off;
    }
  }

  /// The current set of fee bands (empty until the Manager saves some). Staff only.
  Future<List<DeliveryFeeBand>> fetchCurrentBands() async {
    final rows = await _client
        .from('delivery_fee_bands')
        .select('min_km, max_km, fee, is_demo, set_version')
        .eq('is_current', true)
        .order('min_km');
    return [
      for (final r in rows)
        DeliveryFeeBand.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  /// The address is fixed (Payanas), so only the map pin and the contact number are saved.
  /// Sitio / Purok and directions are no longer part of the details and are cleared.
  Future<void> saveDetails({
    double? latitude,
    double? longitude,
    String? contactNumber,
  }) => _write(
    () => _client.rpc(
      'save_cooperative_details',
      params: {
        'p_sitio_purok': null,
        'p_address_notes': null,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_contact_number': contactNumber,
      },
    ),
  );

  Future<void> verifyContact() =>
      _write(() => _client.rpc('verify_cooperative_contact'));

  Future<int> saveBands(List<DeliveryFeeBand> bands) => _write(() async {
    final v = await _client.rpc(
      'save_delivery_fee_bands',
      params: {
        'p_bands': [for (final b in bands) b.toRpc()],
        'p_is_demo': false,
      },
    );
    return (v as num).toInt();
  });

  Future<void> setPickupEnabled(bool enabled) => _write(
    () => _client.rpc('set_pickup_enabled', params: {'p_enabled': enabled}),
  );

  Future<void> setDeliveryEnabled(bool enabled) => _write(
    () => _client.rpc('set_delivery_enabled', params: {'p_enabled': enabled}),
  );

  /// What delivery to this saved address costs (writes nothing). Throws with a code at the
  /// start of the message; see [deliveryRefusalOf].
  Future<DeliveryQuote> fetchQuote(String addressId) async {
    final res = await _client.rpc(
      'get_delivery_quote',
      params: {'p_address_id': addressId},
    );
    return DeliveryQuote.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// One group per checkout delivery. A retry with the same [requestId] returns the same group.
  Future<CheckoutGroupResult> createCheckoutGroup({
    required String addressId,
    required String requestId,
  }) => _write(() async {
    final res = await _client.rpc(
      'create_checkout_group',
      params: {'p_address_id': addressId, 'p_request_id': requestId},
    );
    return CheckoutGroupResult.fromMap(Map<String, dynamic>.from(res as Map));
  });
}
