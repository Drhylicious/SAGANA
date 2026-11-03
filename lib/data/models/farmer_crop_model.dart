import 'package:flutter/material.dart';
import '../services/market_types_service.dart';

/// Standalone so callers that only have a raw crop_type string (e.g. a
/// catalog Map, not a full FarmerCropModel) can reuse the same mapping
/// without constructing a throwaway model instance.
String marketTypeLabelFor(String? cropType) =>
    MarketTypes.instance.label(cropType);

class FarmerCropModel {
  final String id;
  final String farmerId;
  final String cropName;
  final String category;
  /// The Farmer's own, camera-captured photo of this crop (farmer_crops.photo_url).
  /// The Crop Master image is a reference for the catalog only and is never
  /// loaded, shown or assigned here.
  final String? photoUrl;
  final String? cropMasterId; // null until linked to the official catalog
  /// Market type as registered on the crop's catalog entry —
  /// a market_types.code (Public or Cooperative). Null until the crop
  /// is linked to crop_master (i.e. while isPendingApproval is true).
  final String? cropType;

  /// The one selling channel this crop is reserved for (crop_master
  /// .exclusive_channel), or null. Ginger → DA-AMAD Market Linking.
  final String? exclusiveChannel;
  final int harvestCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String?
  requestStatus; // 'pending' | 'approved' | 'rejected' | null (added directly from catalog, no request involved)
  final String? requestNotes;  // admin's reason, shown to farmer when rejected

  const FarmerCropModel({
    required this.id,
    required this.farmerId,
    required this.cropName,
    required this.category,
    this.photoUrl,
    this.cropMasterId,
    this.cropType,
    this.exclusiveChannel,
    required this.harvestCount,
    required this.createdAt,
    this.updatedAt,
    this.requestStatus,
    this.requestNotes,
  });

  bool get hasHarvests => harvestCount > 0;
  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// Selling through the Marketplace, to the Cooperative or via Market Linking
  /// needs the Farmer's own photo; harvesting and Informal Sales do not.
  bool get needsPhoto => !hasPhoto;

  /// The photo a card renders: the Farmer's own photo, or null (the caller shows
  /// a plain category icon and a "Photo Required" mark). Never a catalog image.
  String? get displayImageUrl => hasPhoto ? photoUrl : null;

  bool get hasDisplayImage => hasPhoto;

  /// Human-readable label for [cropType], for display wherever a crop's
  /// market type needs to be shown (Request New Crop, Record New Harvest,
  /// Manage Inventory, etc).
  String get marketTypeLabel => marketTypeLabelFor(cropType);

  /// True until Admin approves a "Request New Crop" submission and links
  /// it to a real crop_master entry.
  bool get isPendingApproval => cropMasterId == null;

  /// True when an admin has explicitly declined the crop request.
  bool get isRejected => requestStatus == 'rejected';

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
      cropType: map['crop_type'] as String?,
      exclusiveChannel: map['exclusive_channel'] as String?,
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
    String? cropType,
    int? harvestCount,
  }) {
    return FarmerCropModel(
      id: id,
      farmerId: farmerId,
      cropName: cropName ?? this.cropName,
      category: category ?? this.category,
      photoUrl: photoUrl ?? this.photoUrl,
      cropMasterId: cropMasterId ?? this.cropMasterId,
      cropType: cropType ?? this.cropType,
      exclusiveChannel: exclusiveChannel,
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
      case HarvestFilter.all:
        return 'All';
      case HarvestFilter.synced:
        return 'Synced';
      case HarvestFilter.pending:
        return 'Pending';
      case HarvestFilter.thisMonth:
        return 'This Month';
    }
  }
}