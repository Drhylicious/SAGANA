import 'package:flutter/material.dart';

class FarmerCropModel {
  final String id;
  final String farmerId;
  final String cropName;
  final String category;
  final String? photoUrl;
  final String? cropMasterId; // null until linked to the official catalog
  final int harvestCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? requestStatus; // 'pending' | 'approved' | 'rejected' | null (added directly from catalog, no request involved)
  final String? requestNotes;  // admin's reason, shown to farmer when rejected

  const FarmerCropModel({
    required this.id,
    required this.farmerId,
    required this.cropName,
    required this.category,
    this.photoUrl,
    this.cropMasterId,
    required this.harvestCount,
    required this.createdAt,
    this.updatedAt,
    this.requestStatus,
    this.requestNotes,
  });

  bool get hasHarvests => harvestCount > 0;
  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// True until Admin approves a "Request New Crop" submission and links
  /// it to a real crop_master entry.
  bool get isPendingApproval => cropMasterId == null;

  /// True when an admin has explicitly declined the crop request.
  bool get isRejected => requestStatus == 'rejected';

  static const List<String> categories = [
    'Grain',
    'Legume',
    'Root & Spice Crop',
    'Fruit',
    'Tree Crop',
    'Vegetable',
    'Other',
  ];

  /// Shared category → icon mapping. Previously duplicated privately
  /// inside select_crop_screen.dart's _SelectableCropCard — pulled out
  /// here so any screen needing a category glyph (Market Rate Details,
  /// select_crop_screen, future screens) uses the same one, not a
  /// private copy each time.
  static IconData iconForCategory(String category) {
    switch (category) {
      case 'Grain':
        return Icons.grass_rounded;
      case 'Legume':
        return Icons.eco_rounded;
      case 'Root & Spice Crop':
        return Icons.spa_rounded;
      case 'Fruit':
        return Icons.local_florist_rounded;
      case 'Tree Crop':
        return Icons.park_rounded;
      case 'Vegetable':
        return Icons.agriculture_rounded;
      default:
        return Icons.eco_rounded;
    }
  }

  factory FarmerCropModel.fromMap(Map<String, dynamic> map) {
    return FarmerCropModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      cropName: map['crop_name'] as String,
      category: map['category'] as String? ?? 'Other',
      photoUrl: map['photo_url'] as String?,
      cropMasterId: map['crop_master_id'] as String?,
      harvestCount: map['harvest_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      requestStatus: map['request_status'] as String?,
      requestNotes: map['request_notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmer_id': farmerId,
      'crop_name': cropName,
      'category': category,
      'photo_url': photoUrl,
      'crop_master_id': cropMasterId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  FarmerCropModel copyWith({
    String? cropName,
    String? category,
    String? photoUrl,
    String? cropMasterId,
    int? harvestCount,
  }) {
    return FarmerCropModel(
      id: id,
      farmerId: farmerId,
      cropName: cropName ?? this.cropName,
      category: category ?? this.category,
      photoUrl: photoUrl ?? this.photoUrl,
      cropMasterId: cropMasterId ?? this.cropMasterId,
      harvestCount: harvestCount ?? this.harvestCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Equality is by [id] only — two instances representing the same crop
  /// row (even if fetched separately, e.g. one passed via navigation and one
  /// freshly refetched) must compare equal so widgets like DropdownButton
  /// that match values by == don't break across independent fetches.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FarmerCropModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
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