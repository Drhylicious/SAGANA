// ─── Supply Chain Farmer (map marker data) ───────────────────────────────────

// Deliberately carries only farm-location and currently-planted-crop data
// — the two things the Supply Chain map is meant to show. Loan balance/
// status and harvest history were removed (they belong to the Loan and
// Harvest modules respectively, not supply chain visibility) per the
// explicit review finding that this screen had drifted into showing
// account-status information unrelated to supply chain operations.
class SupplyChainFarmerModel {
  final String userId;
  final String fullName;
  final String? memberId;
  final String? purok;
  final String? profilePhotoUrl;
  final double farmLatitude;
  final double farmLongitude;
  final List<String> primaryCrops;
  final bool isVerified;

  const SupplyChainFarmerModel({
    required this.userId,
    required this.fullName,
    this.memberId,
    this.purok,
    this.profilePhotoUrl,
    required this.farmLatitude,
    required this.farmLongitude,
    required this.primaryCrops,
    required this.isVerified,
  });

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
      purok:        map['purok'] as String?,
      profilePhotoUrl: map['profile_photo_url'] as String?,
      farmLatitude: (map['farm_latitude'] as num).toDouble(),
      farmLongitude: (map['farm_longitude'] as num).toDouble(),
      primaryCrops: (map['crops'] as List<dynamic>?)
              ?.map((c) => c.toString())
              .toList() ??
          [],
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

// ─── Supply Chain Coverage (mapped vs. unmapped members) ─────────────────────
// Replaces the old SupplyChainOperationsSnapshot, which bundled in loan and
// marketplace-approval counts that don't describe supply chain coverage —
// see the removed fields' history for context. Coverage (can this member's
// farm be shown on the map at all) is the one genuinely supply-chain-scoped
// figure that belonged here.

class SupplyChainCoverage {
  final int totalMembers;
  final int mappedMembers;

  const SupplyChainCoverage({
    required this.totalMembers,
    required this.mappedMembers,
  });

  int get unmappedMembers => (totalMembers - mappedMembers).clamp(0, totalMembers);

  static const empty = SupplyChainCoverage(totalMembers: 52, mappedMembers: 0);
}

// ─── Unmapped Member (for the "no farm location" coverage list) ─────────────

class UnmappedMemberEntry {
  final String userId;
  final String fullName;
  final String? purok;

  const UnmappedMemberEntry({
    required this.userId,
    required this.fullName,
    this.purok,
  });
}
