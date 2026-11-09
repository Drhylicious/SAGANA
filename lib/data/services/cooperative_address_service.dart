import 'package:flutter/foundation.dart';
import '../models/cooperative_delivery_model.dart';
import '../repositories/cooperative_delivery_repository.dart';

/// The one place every screen gets the cooperative's name and address from (Pickup at checkout,
/// product pages, order screens). It reads the Cooperative Details record, so a pickup address
/// is never typed in or hardcoded anywhere else, and a change the Manager saves shows up
/// everywhere.
///
/// It keeps the last good copy in memory, so a screen still has an address after the network
/// drops. Nothing here throws: when the record cannot be read and nothing is remembered, [load]
/// returns null and the screen says the address is unavailable.
class CooperativeAddressService {
  CooperativeAddressService._();
  static final CooperativeAddressService instance =
      CooperativeAddressService._();

  /// Tests replace how the record is read.
  @visibleForTesting
  static Future<CooperativeDetails> Function()? fetcherOverride;

  CooperativeDetails? _cached;
  Future<CooperativeDetails?>? _inflight;

  /// The last good copy, if any.
  CooperativeDetails? get cached => _cached;

  Future<CooperativeDetails?> load({bool force = false}) {
    if (!force && _cached != null) return Future.value(_cached);
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<CooperativeDetails?> _fetch() async {
    try {
      final fetch =
          fetcherOverride ??
          () => CooperativeDeliveryRepository().fetchDetails();
      _cached = await fetch();
    } catch (_) {
      // Keep whatever copy there already is.
    }
    return _cached;
  }

  /// Called after the Manager saves, so the next read is fresh.
  void invalidate() {
    _cached = null;
  }

  /// Hand over a copy a screen has already read.
  void remember(CooperativeDetails details) {
    _cached = details;
  }

  @visibleForTesting
  void reset() {
    _cached = null;
    _inflight = null;
    fetcherOverride = null;
  }
}
