class FarmerProfileModel {
  final String userId;
  final String fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? sitio;
  final String? memberId;

  // Farm basics
  final String? farmName;
  final String? farmLocation;   // legacy text label
  final String? farmAddress;    // human-readable address
  final double? landAreaHectares;
  final int? yearsFarming;

  // Map coordinates
  final double? farmLatitude;
  final double? farmLongitude;

  // Agricultural characteristics
  final String? farmOwnershipType; // owned | leased | communal
  final String? soilType;          // sandy | clay | loam | volcanic | mixed
  final String? waterSource;       // rain_fed | irrigated | well | river | mixed

  final double capitalShares;
  final DateTime? memberSince;
  final bool isVerified;
  final List<String> primaryCrops;

  const FarmerProfileModel({
    required this.userId,
    required this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.sitio,
    this.memberId,
    this.farmName,
    this.farmLocation,
    this.farmAddress,
    this.landAreaHectares,
    this.yearsFarming,
    this.farmLatitude,
    this.farmLongitude,
    this.farmOwnershipType,
    this.soilType,
    this.waterSource,
    required this.capitalShares,
    this.memberSince,
    required this.isVerified,
    required this.primaryCrops,
  });

  // ─── Computed helpers ────────────────────────────────────────────────────────

  bool get hasPhoto => profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty;
  bool get hasCoordinates => farmLatitude != null && farmLongitude != null;

  String get memberSinceLabel =>
      memberSince != null ? memberSince!.year.toString() : '—';

  /// Human-readable coordinates string (e.g. "13.6302° N, 121.9392° E")
  String get coordinatesLabel {
    if (!hasCoordinates) return 'Not pinned yet';
    final lat = farmLatitude!;
    final lon = farmLongitude!;
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}° $latDir, '
        '${lon.abs().toStringAsFixed(4)}° $lonDir';
  }

  // ─── Profile completion (7 fields) ───────────────────────────────────────────

  static const int _totalFields = 7;

  int get filledFieldCount {
    int count = 0;
    if (hasPhoto) count++;
    if (phoneNumber != null && phoneNumber!.isNotEmpty) count++;
    if (farmName != null && farmName!.isNotEmpty) count++;
    if (farmAddress != null && farmAddress!.isNotEmpty) count++;
    if (landAreaHectares != null && landAreaHectares! > 0) count++;
    if (yearsFarming != null && yearsFarming! > 0) count++;
    if (primaryCrops.isNotEmpty) count++;
    return count;
  }

  double get completionPercent => filledFieldCount / _totalFields;
  int get completionPercentInt => (completionPercent * 100).round();
  bool get isComplete => filledFieldCount >= _totalFields;

  // ─── Display labels for enums ──────────────────────────────────────────────

  String get ownershipLabel {
    switch (farmOwnershipType) {
      case 'owned':    return 'Owned';
      case 'leased':   return 'Leased';
      case 'communal': return 'Communal';
      default:         return 'Not specified';
    }
  }

  String get soilLabel {
    switch (soilType) {
      case 'sandy':    return 'Sandy';
      case 'clay':     return 'Clay';
      case 'loam':     return 'Loam';
      case 'volcanic': return 'Volcanic';
      case 'mixed':    return 'Mixed';
      default:         return 'Not specified';
    }
  }

  String get waterLabel {
    switch (waterSource) {
      case 'rain_fed':  return 'Rain-fed';
      case 'irrigated': return 'Irrigated';
      case 'well':      return 'Well';
      case 'river':     return 'River';
      case 'mixed':     return 'Mixed';
      default:          return 'Not specified';
    }
  }

  // ─── Serialization ────────────────────────────────────────────────────────────

  factory FarmerProfileModel.fromMap(Map<String, dynamic> map) {
    return FarmerProfileModel(
      userId:             map['user_id'] as String,
      fullName:           map['full_name'] as String? ?? 'Farmer',
      phoneNumber:        map['phone_number'] as String?,
      profilePhotoUrl:    map['profile_photo_url'] as String?,
      sitio:              map['sitio'] as String?,
      memberId:           map['member_id'] as String?,
      farmName:           map['farm_name'] as String?,
      farmLocation:       map['farm_location'] as String?,
      farmAddress:        map['farm_address'] as String?,
      landAreaHectares:   map['land_area_hectares'] != null
          ? (map['land_area_hectares'] as num).toDouble()
          : null,
      yearsFarming:       map['years_farming'] as int?,
      farmLatitude:       map['farm_latitude'] != null
          ? (map['farm_latitude'] as num).toDouble()
          : null,
      farmLongitude:      map['farm_longitude'] != null
          ? (map['farm_longitude'] as num).toDouble()
          : null,
      farmOwnershipType:  map['farm_ownership_type'] as String?,
      soilType:           map['soil_type'] as String?,
      waterSource:        map['water_source'] as String?,
      capitalShares:      (map['capital_shares'] as num? ?? 0).toDouble(),
      memberSince:        map['member_since'] != null
          ? DateTime.parse(map['member_since'] as String)
          : null,
      isVerified:         map['is_verified'] as bool? ?? false,
      primaryCrops:       (map['primary_crops'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
