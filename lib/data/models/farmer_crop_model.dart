class FarmerCropModel {
  final String id;
  final String farmerId;
  final String cropName;
  final String category;
  final String? photoUrl;
  final int harvestCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const FarmerCropModel({
    required this.id,
    required this.farmerId,
    required this.cropName,
    required this.category,
    this.photoUrl,
    required this.harvestCount,
    required this.createdAt,
    this.updatedAt,
  });

  bool get hasHarvests => harvestCount > 0;
  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  static const List<String> categories = [
    'Grain',
    'Legume',
    'Root & Spice Crop',
    'Fruit',
    'Tree Crop',
    'Vegetable',
    'Other',
  ];

  factory FarmerCropModel.fromMap(Map<String, dynamic> map) {
    return FarmerCropModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      cropName: map['crop_name'] as String,
      category: map['category'] as String? ?? 'Other',
      photoUrl: map['photo_url'] as String?,
      harvestCount: map['harvest_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmer_id': farmerId,
      'crop_name': cropName,
      'category': category,
      'photo_url': photoUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  FarmerCropModel copyWith({
    String? cropName,
    String? category,
    String? photoUrl,
    int? harvestCount,
  }) {
    return FarmerCropModel(
      id: id,
      farmerId: farmerId,
      cropName: cropName ?? this.cropName,
      category: category ?? this.category,
      photoUrl: photoUrl ?? this.photoUrl,
      harvestCount: harvestCount ?? this.harvestCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

// ─── Harvest Filter ───────────────────────────────────────────────────────────

enum HarvestFilter { all, synced, pending, thisMonth }

extension HarvestFilterExt on HarvestFilter {
  String get label {
    switch (this) {
      case HarvestFilter.all: return 'All';
      case HarvestFilter.synced: return 'Synced';
      case HarvestFilter.pending: return 'Pending';
      case HarvestFilter.thisMonth: return 'This Month';
    }
  }
}
