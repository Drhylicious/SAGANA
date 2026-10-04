/// Structured-address fields for a write. Only non-null values are sent,
/// so an update that does not supply them leaves the stored values alone.
class BuyerAddressStructure {
  final String? regionCode;
  final String? regionName;
  final String? provinceCode;
  final String? provinceName;
  final String? cityMunicipalityCode;
  final String? cityMunicipalityName;
  final String? barangayCode;
  final String? barangayName;
  final String? postalCode;
  final String? street;
  final String? building;
  final String? houseNo;

  const BuyerAddressStructure({
    this.regionCode,
    this.regionName,
    this.provinceCode,
    this.provinceName,
    this.cityMunicipalityCode,
    this.cityMunicipalityName,
    this.barangayCode,
    this.barangayName,
    this.postalCode,
    this.street,
    this.building,
    this.houseNo,
  });

  /// [includeNulls] writes every column, so null values clear the stored
  /// field (saved as NULL). Used when the whole structure is replaced, such
  /// as an edit of an existing address; the default skips nulls.
  Map<String, dynamic> toColumns({bool includeNulls = false}) {
    final columns = <String, dynamic>{
      'region_code': regionCode,
      'region_name': regionName,
      'province_code': provinceCode,
      'province_name': provinceName,
      'city_municipality_code': cityMunicipalityCode,
      'city_municipality_name': cityMunicipalityName,
      'barangay_code': barangayCode,
      'barangay_name': barangayName,
      'postal_code': postalCode,
      'street': street,
      'building': building,
      'house_no': houseNo,
    };
    if (!includeNulls) columns.removeWhere((_, value) => value == null);
    return columns;
  }
}

class BuyerAddressModel {
  final String id;
  final String userId;
  final String label;
  final String? recipientName;
  // Nullable: a registration with no phone number saves the address without one.
  final String? contactNumber;
  final String addressLine;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Structured address (additive; null on rows saved before it existed).
  // PSGC names and codes are both stored so the saved address stays
  // readable even if the bundled PSGC data later changes.
  final String? regionCode;
  final String? regionName;
  final String? provinceCode;
  final String? provinceName;
  final String? cityMunicipalityCode;
  final String? cityMunicipalityName;
  final String? barangayCode;
  final String? barangayName;
  final String? postalCode;
  final String? street;
  final String? building;
  final String? houseNo;

  const BuyerAddressModel({
    required this.id,
    required this.userId,
    required this.label,
    this.recipientName,
    this.contactNumber,
    required this.addressLine,
    this.latitude,
    this.longitude,
    this.notes,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.regionCode,
    this.regionName,
    this.provinceCode,
    this.provinceName,
    this.cityMunicipalityCode,
    this.cityMunicipalityName,
    this.barangayCode,
    this.barangayName,
    this.postalCode,
    this.street,
    this.building,
    this.houseNo,
  });

  factory BuyerAddressModel.fromMap(Map<String, dynamic> map) {
    return BuyerAddressModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      label: map['label'] as String,
      recipientName: map['recipient_name'] as String?,
      contactNumber: map['contact_number'] as String?,
      addressLine: map['address_line'] as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      isDefault: map['is_default'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      regionCode: map['region_code'] as String?,
      regionName: map['region_name'] as String?,
      provinceCode: map['province_code'] as String?,
      provinceName: map['province_name'] as String?,
      cityMunicipalityCode: map['city_municipality_code'] as String?,
      cityMunicipalityName: map['city_municipality_name'] as String?,
      barangayCode: map['barangay_code'] as String?,
      barangayName: map['barangay_name'] as String?,
      postalCode: map['postal_code'] as String?,
      street: map['street'] as String?,
      building: map['building'] as String?,
      houseNo: map['house_no'] as String?,
    );
  }
}
