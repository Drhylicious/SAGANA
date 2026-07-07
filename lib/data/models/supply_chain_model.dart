// ─── Supply Chain Farmer (map marker data) ───────────────────────────────────

class SupplyChainFarmerModel {
  final String userId;
  final String fullName;
  final String? memberId;
  final String? sitio;
  final String? profilePhotoUrl;
  final double farmLatitude;
  final double farmLongitude;
  final List<String> primaryCrops;
  final double outstandingLoanBalance;
  final String loanStatus; // 'none' | 'active' | 'overdue'
  final DateTime? lastHarvestDate;
  final bool isVerified;

  const SupplyChainFarmerModel({
    required this.userId,
    required this.fullName,
    this.memberId,
    this.sitio,
    this.profilePhotoUrl,
    required this.farmLatitude,
    required this.farmLongitude,
    required this.primaryCrops,
    required this.outstandingLoanBalance,
    required this.loanStatus,
    this.lastHarvestDate,
    required this.isVerified,
  });

  bool get hasOutstandingLoan =>
      outstandingLoanBalance > 0 || loanStatus == 'overdue';

  bool get isOverdue => loanStatus == 'overdue';

  /// Primary crop for pin color coding
  String get primaryCrop =>
      primaryCrops.isNotEmpty ? primaryCrops.first : '';

  bool growsCrop(String cropName) {
    final lower = cropName.toLowerCase();
    return primaryCrops.any((c) => c.toLowerCase().contains(lower));
  }

  factory SupplyChainFarmerModel.fromMap(Map<String, dynamic> map) {
    return SupplyChainFarmerModel(
      userId:       map['user_id'] as String,
      fullName:     map['full_name'] as String? ?? 'Farmer',
      memberId:     map['member_id'] as String?,
      sitio:        map['sitio'] as String?,
      profilePhotoUrl: map['profile_photo_url'] as String?,
      farmLatitude: (map['farm_latitude'] as num).toDouble(),
      farmLongitude: (map['farm_longitude'] as num).toDouble(),
      primaryCrops: (map['crops'] as List<dynamic>?)
              ?.map((c) => c.toString())
              .toList() ??
          [],
      outstandingLoanBalance:
          (map['outstanding_balance'] as num? ?? 0).toDouble(),
      loanStatus: map['loan_status'] as String? ?? 'none',
      lastHarvestDate: map['last_harvest_date'] != null
          ? DateTime.tryParse(map['last_harvest_date'] as String)
          : null,
      isVerified: map['is_verified'] as bool? ?? false,
    );
  }
}

// ─── Map Crop Stats (for bottom summary drawer) ───────────────────────────────

class CropMapStat {
  final String cropName;
  final String abbreviation;
  final int farmerCount;

  const CropMapStat({
    required this.cropName,
    required this.abbreviation,
    required this.farmerCount,
  });
}

// ─── Supply Chain Summary ─────────────────────────────────────────────────────

class SupplyChainSummary {
  final int totalMembers;
  final int mappedMembers;
  final List<CropMapStat> cropStats;

  const SupplyChainSummary({
    required this.totalMembers,
    required this.mappedMembers,
    required this.cropStats,
  });

  int get unmappedMembers => totalMembers - mappedMembers;
}

// ─── Map Filter ───────────────────────────────────────────────────────────────

enum MapCropFilter { all, peanut, ginger, palay, banana, copra }

extension MapCropFilterExt on MapCropFilter {
  String get label {
    switch (this) {
      case MapCropFilter.all:    return 'All Crops';
      case MapCropFilter.peanut: return 'Peanut';
      case MapCropFilter.ginger: return 'Ginger';
      case MapCropFilter.palay:  return 'Palay';
      case MapCropFilter.banana: return 'Banana';
      case MapCropFilter.copra:  return 'Copra';
    }
  }

  bool matches(SupplyChainFarmerModel farmer) {
    if (this == MapCropFilter.all) return true;
    return farmer.growsCrop(label);
  }
}

enum MapStatusFilter { active, loans }
