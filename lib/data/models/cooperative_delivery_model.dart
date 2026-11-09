/// Cooperative Details, Delivery status, the delivery fee bands and a delivery quote.
///
/// Everything here mirrors what the database sends (see supabase_schema_unify_m02 / m03).
/// No fee, distance or contact number is ever invented in the app: a missing value stays
/// missing and Delivery stays switched off until the Manager has set it all up.
library;

/// The one shared record for the whole cooperative (never a Manager's or Officer's own
/// details). The address is fixed to Barangay Payanas, Torrijos, Marinduque (MIMAROPA, 4903).
class CooperativeDetails {
  final String cooperativeName;
  final String barangayCode;
  final String barangayName;
  final String cityMunicipalityName;
  final String provinceName;
  final String regionName;
  final String postalCode;
  final String? sitioPurok;
  final String? addressNotes;

  /// Null while the number is still a placeholder.
  final String? contactNumber;
  final bool contactIsPlaceholder;
  final bool contactVerified;

  /// Staff only (a consumer never receives the pin).
  final double? latitude;
  final double? longitude;

  const CooperativeDetails({
    required this.cooperativeName,
    this.barangayCode = '1704006019',
    this.barangayName = 'Payanas',
    this.cityMunicipalityName = 'Torrijos',
    this.provinceName = 'Marinduque',
    this.regionName = 'MIMAROPA Region',
    this.postalCode = '4903',
    this.sitioPurok,
    this.addressNotes,
    this.contactNumber,
    this.contactIsPlaceholder = true,
    this.contactVerified = false,
    this.latitude,
    this.longitude,
  });

  bool get hasPin => latitude != null && longitude != null;
  bool get hasRealContact =>
      !contactIsPlaceholder && (contactNumber?.trim().isNotEmpty ?? false);

  /// The complete cooperative address, the one customers see for Pickup:
  /// "Barangay Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903". It is always built from
  /// the Cooperative Details record, never typed in anywhere else.
  String get addressLine => [
    'Barangay $barangayName',
    cityMunicipalityName,
    provinceName,
    regionName,
    postalCode,
  ].where((p) => p.trim().isNotEmpty).join(', ');

  factory CooperativeDetails.fromMap(Map<String, dynamic> m) =>
      CooperativeDetails(
        cooperativeName:
            (m['cooperative_name'] as String?) ?? 'SP3 Agriculture Cooperative',
        barangayCode: (m['barangay_code'] as String?) ?? '1704006019',
        barangayName: (m['barangay_name'] as String?) ?? 'Payanas',
        cityMunicipalityName:
            (m['city_municipality_name'] as String?) ?? 'Torrijos',
        provinceName: (m['province_name'] as String?) ?? 'Marinduque',
        regionName: (m['region_name'] as String?) ?? 'MIMAROPA Region',
        postalCode: (m['postal_code'] as String?) ?? '4903',
        sitioPurok: m['sitio_purok'] as String?,
        addressNotes: m['address_notes'] as String?,
        contactNumber: m['contact_number'] as String?,
        contactIsPlaceholder: (m['contact_is_placeholder'] as bool?) ?? true,
        contactVerified: (m['contact_verified'] as bool?) ?? false,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
      );
}

/// What is still missing before Delivery may be switched on (keys from the database).
const String kDeliveryMissingPin = 'cooperative_pin';
const String kDeliveryMissingContact = 'contact_number';
const String kDeliveryMissingContactVerified = 'contact_verified';
const String kDeliveryMissingBarangay = 'allowed_barangay';
const String kDeliveryMissingBands = 'fee_bands';
const String kDeliveryMissingDemoBands = 'fee_bands_demo_only';

class DeliveryStatus {
  /// Delivery is switched on AND everything it needs is in place.
  final bool enabled;

  /// Everything it needs is in place (it may still be switched off).
  final bool ready;

  /// The Pickup switch. Pickup and Delivery are switched separately, and at least one stays on.
  final bool pickupEnabled;
  final List<String> allowedBarangayCodes;

  /// Staff only.
  final List<String> missing;

  const DeliveryStatus({
    this.enabled = false,
    this.ready = false,
    this.pickupEnabled = true,
    this.allowedBarangayCodes = const ['1704006019'],
    this.missing = const [],
  });

  /// Delivery is off until the database says otherwise.
  static const off = DeliveryStatus();

  factory DeliveryStatus.fromMap(Map<String, dynamic> m) => DeliveryStatus(
    enabled: (m['enabled'] as bool?) ?? false,
    ready: (m['ready'] as bool?) ?? false,
    // A database that does not know the Pickup switch yet keeps Pickup on.
    pickupEnabled: (m['pickup_enabled'] as bool?) ?? true,
    allowedBarangayCodes: [
      for (final c
          in (m['allowed_barangay_codes'] as List?) ?? const ['1704006019'])
        c.toString(),
    ],
    missing: [
      for (final c in (m['missing'] as List?) ?? const []) c.toString(),
    ],
  );
}

/// What Delivery still needs, in the words of the checklist. Contact is ONE item: a number that is
/// entered AND verified (the database lists "not entered" and "not verified" separately, and a
/// number that is not entered cannot be verified, so a missing number is never shown as verified).
class DeliveryChecklist {
  final bool pinSet;
  final bool contactReady;
  final bool bandsSet;
  const DeliveryChecklist({required this.pinSet, required this.contactReady, required this.bandsSet});

  bool get complete => pinSet && contactReady && bandsSet;

  factory DeliveryChecklist.from(DeliveryStatus s) => DeliveryChecklist(
        pinSet: !s.missing.contains(kDeliveryMissingPin),
        contactReady: !s.missing.contains(kDeliveryMissingContact) && !s.missing.contains(kDeliveryMissingContactVerified),
        bandsSet: !s.missing.contains(kDeliveryMissingBands) && !s.missing.contains(kDeliveryMissingDemoBands),
      );
}

/// One distance band of the delivery fee: [minKm, maxKm) costs [fee] pesos.
class DeliveryFeeBand {
  final double minKm;
  final double maxKm;
  final double fee;
  final bool isDemo;
  final int version;

  const DeliveryFeeBand({
    required this.minKm,
    required this.maxKm,
    required this.fee,
    this.isDemo = false,
    this.version = 0,
  });

  Map<String, dynamic> toRpc() => {
    'min_km': minKm,
    'max_km': maxKm,
    'fee': fee,
  };

  factory DeliveryFeeBand.fromMap(Map<String, dynamic> m) => DeliveryFeeBand(
    minKm: (m['min_km'] as num).toDouble(),
    maxKm: (m['max_km'] as num).toDouble(),
    fee: (m['fee'] as num).toDouble(),
    isDemo: (m['is_demo'] as bool?) ?? false,
    version: (m['set_version'] as num?)?.toInt() ?? 0,
  );
}

/// Why a list of fee bands cannot be saved (the same rules the database applies).
enum BandsProblem { empty, badRow, notFromZero, gapOrOverlap }

/// Null when the bands are valid: they start at 0 km, each one ends after it starts,
/// every fee is zero or more, and each band starts exactly where the previous one ends.
BandsProblem? checkFeeBands(List<DeliveryFeeBand> bands) {
  if (bands.isEmpty) return BandsProblem.empty;
  final sorted = [...bands]..sort((a, b) => a.minKm.compareTo(b.minKm));
  for (final b in sorted) {
    if (b.maxKm <= b.minKm || b.fee < 0 || b.minKm < 0)
      return BandsProblem.badRow;
  }
  if (sorted.first.minKm != 0) return BandsProblem.notFromZero;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].minKm != sorted[i - 1].maxKm)
      return BandsProblem.gapOrOverlap;
  }
  return null;
}

/// The farthest distance a set of bands delivers to (the last band's end).
double farthestDeliveryKm(List<DeliveryFeeBand> bands) => bands.isEmpty
    ? 0
    : bands.map((b) => b.maxKm).reduce((a, b) => a > b ? a : b);

/// The fee of one delivery to one saved address, as the server worked it out.
class DeliveryQuote {
  final double distanceKm;
  final double fee;
  final double bandMinKm;
  final double bandMaxKm;

  const DeliveryQuote({
    required this.distanceKm,
    required this.fee,
    required this.bandMinKm,
    required this.bandMaxKm,
  });

  factory DeliveryQuote.fromMap(Map<String, dynamic> m) => DeliveryQuote(
    distanceKm: (m['distance_km'] as num).toDouble(),
    fee: (m['fee'] as num).toDouble(),
    bandMinKm: (m['band_min_km'] as num?)?.toDouble() ?? 0,
    bandMaxKm: (m['band_max_km'] as num?)?.toDouble() ?? 0,
  );
}

/// Why a delivery quote was refused (the code at the start of the database message).
enum DeliveryRefusal {
  off,
  notReady,
  outsideArea,
  noPin,
  tooFar,
  noBand,
  addressNotFound,
  other,
}

DeliveryRefusal deliveryRefusalOf(Object error) {
  final text = error.toString();
  const codes = {
    'DELIVERY_OFF': DeliveryRefusal.off,
    'DELIVERY_NOT_READY': DeliveryRefusal.notReady,
    'OUTSIDE_AREA': DeliveryRefusal.outsideArea,
    'NO_PIN': DeliveryRefusal.noPin,
    'TOO_FAR': DeliveryRefusal.tooFar,
    'NO_BAND': DeliveryRefusal.noBand,
    'ADDRESS_NOT_FOUND': DeliveryRefusal.addressNotFound,
  };
  for (final e in codes.entries) {
    if (text.contains(e.key)) return e.value;
  }
  return DeliveryRefusal.other;
}

/// What a delivery group sent back: its id and the one fee of the whole delivery.
class CheckoutGroupResult {
  final String groupId;
  final double deliveryFee;
  final double distanceKm;
  const CheckoutGroupResult({
    required this.groupId,
    required this.deliveryFee,
    required this.distanceKm,
  });

  factory CheckoutGroupResult.fromMap(Map<String, dynamic> m) =>
      CheckoutGroupResult(
        groupId: m['group_id'] as String,
        deliveryFee: (m['delivery_fee'] as num).toDouble(),
        distanceKm: (m['distance_km'] as num).toDouble(),
      );
}
