import 'farmer_member_model.dart' show MemberStatus, MemberStatusExt;

class FarmerProfileModel {
  final String userId;
  final String fullName;
  final String? email; // synthetic auth address (username@sagana.local)
  final String? contactEmail; // optional real email, entered by the farmer
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? purok;
  final String? memberId;

  // Farm basics
  final String? farmName;
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
  final DateTime? dateOfBirth; // farmer personal info (Phase B), nullable
  final String? gender;        // male | female | prefer_not_to_say
  final DateTime? memberSince;
  final bool isVerified;
  final String accountStatus; // raw user_roles.status — 'active'|'suspended'|'pending'|'rejected'|'draft'
  final DateTime? lastActiveAt; // for the derived Inactive indicator (Issue 5)
  final String? rejectionReason;
  final String? suspensionReason;
  final List<String> primaryCrops;

  const FarmerProfileModel({
    required this.userId,
    required this.fullName,
    this.email,
    this.contactEmail,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.purok,
    this.memberId,
    this.farmName,
    this.farmAddress,
    this.landAreaHectares,
    this.yearsFarming,
    this.farmLatitude,
    this.farmLongitude,
    this.farmOwnershipType,
    this.soilType,
    this.waterSource,
    required this.capitalShares,
    this.dateOfBirth,
    this.gender,
    this.memberSince,
    required this.isVerified,
    this.accountStatus = 'active',
    this.lastActiveAt,
    this.rejectionReason,
    this.suspensionReason,
    required this.primaryCrops,
  });

  bool get isActive => accountStatus == 'active';

  /// Derived 6-value status (Active/Inactive/Suspended/Pending/Rejected/
  /// Draft) — same derivation the Members list uses (Issue 5 / Phase C).
  MemberStatus get memberStatus =>
      MemberStatusExt.derive(accountStatus, lastActiveAt);

  // ─── Computed helpers ────────────────────────────────────────────────────────

  bool get hasPhoto => profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty;
  bool get hasCoordinates => farmLatitude != null && farmLongitude != null;

  String? get dateOfBirthLabel {
    if (dateOfBirth == null) return null;
    return '${dateOfBirth!.year}-${dateOfBirth!.month.toString().padLeft(2, '0')}-${dateOfBirth!.day.toString().padLeft(2, '0')}';
  }

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
    if (landAreaHectares != null) count++;
    if (yearsFarming != null) count++;
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
      email:              map['email'] as String? ?? map['user_email'] as String?,
      contactEmail:       map['contact_email'] as String?,
      phoneNumber:        map['phone_number'] as String?,
      profilePhotoUrl:    map['profile_photo_url'] as String?,
      purok:              map['purok'] as String?,
      memberId:           map['member_id'] as String?,
      farmName:           map['farm_name'] as String?,
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
      dateOfBirth:        map['date_of_birth'] != null
          ? DateTime.tryParse(map['date_of_birth'] as String)
          : null,
      gender:             map['gender'] as String?,
      memberSince:        map['member_since'] != null
          ? DateTime.parse(map['member_since'] as String)
          : null,
      isVerified:         map['is_verified'] as bool? ?? false,
      accountStatus:      map['account_status'] as String? ?? 'active',
      lastActiveAt:       map['last_active_at'] != null
          ? DateTime.tryParse(map['last_active_at'] as String)
          : null,
      rejectionReason:    map['rejection_reason'] as String?,
      suspensionReason:   map['suspension_reason'] as String?,
      primaryCrops:       (map['primary_crops'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

// ─── My Programs (farmer-facing view of program_members enrollments) ────────

class MyProgramEntry {
  final String id;
  final String programId;
  final String programName;
  final String benefitType;
  final String programPurpose; // 'distribution' | 'sales'
  final String programStatus;
  final String enrollmentStatus;
  final DateTime enrolledAt;
  final String? itemName;
  final String? itemUnit;
  final double? quantityGiven;
  final DateTime? distributedAt;
  final double? expectedReturnPercent;
  final double? amountReturned;
  final DateTime? settledAt;
  final String? programImageUrl;
  final String? itemImageUrl;

  const MyProgramEntry({
    required this.id,
    required this.programId,
    required this.programName,
    required this.benefitType,
    this.programPurpose = 'distribution',
    required this.programStatus,
    required this.enrollmentStatus,
    required this.enrolledAt,
    this.itemName,
    this.itemUnit,
    this.quantityGiven,
    this.distributedAt,
    this.expectedReturnPercent,
    this.amountReturned,
    this.settledAt,
    this.programImageUrl,
    this.itemImageUrl,
  });

  bool get isRevenueShare => benefitType == 'revenue_share';
  bool get isDistributed => distributedAt != null;
  bool get isSettled => settledAt != null;
  bool get isSalesProgram => programPurpose == 'sales';

  factory MyProgramEntry.fromMap(Map<String, dynamic> m) {
    final program = m['cooperative_programs'] as Map<String, dynamic>? ?? {};
    final item = m['cooperative_inventory'] as Map<String, dynamic>?;
    return MyProgramEntry(
      id: m['id'] as String,
      programId: m['program_id'] as String,
      programName: program['program_name'] as String? ?? 'Program',
      benefitType: program['benefit_type'] as String? ?? 'grant',
      programPurpose: program['program_purpose'] as String? ?? 'distribution',
      programStatus: program['status'] as String? ?? 'active',
      enrollmentStatus: m['status'] as String? ?? 'active',
      enrolledAt: DateTime.parse(m['enrolled_at'] as String),
      // Falls back to the snapshot taken at distribution time — the live
      // join goes null if the inventory item was later deleted
      // (inventory_item_id is ON DELETE SET NULL there), so this keeps a
      // farmer's past distribution record meaningful either way.
      itemName: item?['item_name'] as String? ?? m['distributed_item_name'] as String?,
      itemUnit: item?['unit'] as String?,
      quantityGiven: m['quantity_given'] != null ? (m['quantity_given'] as num).toDouble() : null,
      distributedAt: m['distributed_at'] != null ? DateTime.parse(m['distributed_at'] as String) : null,
      expectedReturnPercent: program['expected_return_percent'] != null
          ? (program['expected_return_percent'] as num).toDouble()
          : null,
      amountReturned: m['amount_returned'] != null ? (m['amount_returned'] as num).toDouble() : null,
      settledAt: m['settled_at'] != null ? DateTime.parse(m['settled_at'] as String) : null,
      programImageUrl: program['image_url'] as String?,
      itemImageUrl: item?['image_url'] as String?,
    );
  }
}