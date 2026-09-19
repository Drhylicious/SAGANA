import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_activity_repository.dart';
import 'crop_lookup.dart';
import 'notification_repository.dart';

// ─── Admin Order Model ─────────────────────────────────────────────────────

class AdminOrderModel {
  final String id;
  final String listingId;
  final String buyerId;
  final String buyerName;
  final String? buyerPhone;
  final String? buyerPhotoUrl;
  final String cropName;
  final String? variety;
  final String? listingPhotoUrl;
  final double quantityKg;
  final double pricePerKg;
  final double totalPrice;
  final String status; // pending | approved | completed | cancelled
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Detail-screen-only, same convention as BuyerOrderModel.
  final String? batchNumber;
  final DateTime? harvestDate;
  final String? category;

  // Canonical crop_master.crop_name, resolved via the order's listing's
  // crop_id — falls back to cropName when unresolved, same convention as
  // BuyerOrderModel/AdminListingModel.
  final String? canonicalCropName;

  const AdminOrderModel({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.buyerName,
    this.buyerPhone,
    this.buyerPhotoUrl,
    required this.cropName,
    this.variety,
    this.listingPhotoUrl,
    required this.quantityKg,
    required this.pricePerKg,
    required this.totalPrice,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.batchNumber,
    this.harvestDate,
    this.category,
    this.canonicalCropName,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  String get displayName {
    final name = canonicalCropName ?? cropName;
    final v = variety?.trim();
    if (v == null || v.isEmpty) return name;
    if (name.toLowerCase().contains(v.toLowerCase())) return name;
    return '$name ($v)';
  }

  String get statusLabel {
    switch (status) {
      case 'pending': return 'Pending Review';
      case 'approved': return 'Approved';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return status;
    }
  }

  String get orderReference => 'ORD-${id.substring(0, 8).toUpperCase()}';

  String get harvestedLabel {
    if (harvestDate == null) return '';
    final diff = DateTime.now().difference(harvestDate!);
    if (diff.inDays <= 0) return 'Harvested today';
    if (diff.inDays == 1) return 'Harvested yesterday';
    return 'Harvested ${diff.inDays} days ago';
  }

  factory AdminOrderModel.fromMap(Map<String, dynamic> map) {
    return AdminOrderModel(
      id: map['id'] as String,
      listingId: map['listing_id'] as String,
      buyerId: map['buyer_id'] as String,
      buyerName: map['buyer_name'] as String? ?? 'Buyer',
      buyerPhone: map['buyer_phone'] as String?,
      buyerPhotoUrl: map['buyer_photo_url'] as String?,
      cropName: map['crop_name'] as String? ?? 'Produce',
      variety: map['variety'] as String?,
      listingPhotoUrl: map['photo_url'] as String?,
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      category: map['category'] as String?,
      canonicalCropName: map['canonical_crop_name'] as String?,
    );
  }
}

// ─── Order Summary Stats ────────────────────────────────────────────────────

class OrderSummaryStats {
  final int total;
  final int pending;
  final int approved;
  final int completed;
  final int cancelled;

  const OrderSummaryStats({
    required this.total,
    required this.pending,
    required this.approved,
    required this.completed,
    required this.cancelled,
  });

  static const empty = OrderSummaryStats(
    total: 0, pending: 0, approved: 0, completed: 0, cancelled: 0,
  );
}

// ─── Admin Order Repository ──────────────────────────────────────────────────

class AdminOrderRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AdminOrderModel>> fetchOrders({
    String? statusFilter,
    String? buyerId,
    String? searchQuery,
  }) async {
    try {
      var query = _client.from('orders').select(
        'id, listing_id, buyer_id, quantity_kg, price_per_kg, total_price, '
        'status, notes, created_at, updated_at',
      );

      if (statusFilter != null) query = query.eq('status', statusFilter);
      if (buyerId != null) query = query.eq('buyer_id', buyerId);

      final rows = await query.order('created_at', ascending: false);
      if (rows.isEmpty) return [];

      final buyerIds = rows.map((r) => r['buyer_id'] as String).toSet().toList();
      final listingIds = rows.map((r) => r['listing_id'] as String).toSet().toList();

      final buyerMap = <String, Map<String, dynamic>>{};
      try {
        final buyers = await _client
            .from('user_information')
            .select('user_id, full_name, phone_number, profile_photo_url')
            .inFilter('user_id', buyerIds);
        for (final b in buyers) {
          buyerMap[b['user_id'] as String] = b;
        }
      } catch (_) {}

      final listingMap = <String, Map<String, dynamic>>{};
      try {
        final listings = await _client
            .from('marketplace_listings')
            .select('id, crop_name, crop_id, variety, photo_url')
            .inFilter('id', listingIds);
        for (final l in listings) {
          listingMap[l['id'] as String] = l;
        }
      } catch (_) {}

      final cropIds = listingMap.values
          .map((l) => l['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final canonicalNames = await fetchCropNameMap(_client, cropIds);

      var result = rows.map((r) {
        final buyer = buyerMap[r['buyer_id']];
        final listing = listingMap[r['listing_id']];
        final cropId = listing?['crop_id'] as String?;
        return AdminOrderModel.fromMap({
          ...r,
          'buyer_name': buyer?['full_name'],
          'buyer_phone': buyer?['phone_number'],
          'buyer_photo_url': buyer?['profile_photo_url'],
          'crop_name': listing?['crop_name'],
          'variety': listing?['variety'],
          'photo_url': listing?['photo_url'],
          'canonical_crop_name': cropId != null ? canonicalNames[cropId] : null,
        });
      }).toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        result = result.where((o) =>
            o.buyerName.toLowerCase().contains(q) ||
            o.cropName.toLowerCase().contains(q) ||
            o.orderReference.toLowerCase().contains(q)).toList();
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<OrderSummaryStats> fetchSummaryStats() async {
    try {
      final rows = await _client.from('orders').select('status');
      int pending = 0, approved = 0, completed = 0, cancelled = 0;
      for (final r in rows) {
        switch (r['status'] as String?) {
          case 'pending': pending++; break;
          case 'approved': approved++; break;
          case 'completed': completed++; break;
          case 'cancelled': cancelled++; break;
        }
      }
      return OrderSummaryStats(
        total: rows.length, pending: pending, approved: approved,
        completed: completed, cancelled: cancelled,
      );
    } catch (_) {
      return OrderSummaryStats.empty;
    }
  }

  Future<AdminOrderModel?> fetchOrderById(String orderId) async {
    try {
      final row = await _client
          .from('orders')
          .select('id, listing_id, buyer_id, quantity_kg, price_per_kg, '
              'total_price, status, notes, created_at, updated_at')
          .eq('id', orderId)
          .maybeSingle();
      if (row == null) return null;

      final buyerId = row['buyer_id'] as String;
      final listingId = row['listing_id'] as String;

      String buyerName = 'Buyer';
      String? buyerPhone, buyerPhotoUrl;
      try {
        final buyer = await _client
            .from('user_information')
            .select('full_name, phone_number, profile_photo_url')
            .eq('user_id', buyerId)
            .maybeSingle();
        buyerName = buyer?['full_name'] as String? ?? 'Buyer';
        buyerPhone = buyer?['phone_number'] as String?;
        buyerPhotoUrl = buyer?['profile_photo_url'] as String?;
      } catch (_) {}

      String cropName = 'Produce';
      String? variety, photoUrl, batchId, batchNumber, category, canonicalCropName;
      DateTime? harvestDate;
      try {
        final listing = await _client
            .from('marketplace_listings')
            .select('crop_name, crop_id, variety, photo_url, inventory_batch_id')
            .eq('id', listingId)
            .maybeSingle();
        cropName = listing?['crop_name'] as String? ?? 'Produce';
        variety = listing?['variety'] as String?;
        photoUrl = listing?['photo_url'] as String?;
        batchId = listing?['inventory_batch_id'] as String?;

        final cropId = listing?['crop_id'] as String?;
        if (cropId != null) {
          canonicalCropName = (await fetchCropNameMap(_client, [cropId]))[cropId];
        }

        try {
          final crop = await _client
              .from('crop_master')
              .select('category')
              .ilike('crop_name', cropName)
              .maybeSingle();
          category = crop?['category'] as String?;
        } catch (_) {}

        if (batchId != null) {
          try {
            final batch = await _client
                .from('inventory_batches')
                .select('batch_number, harvest_record_id')
                .eq('id', batchId)
                .maybeSingle();
            batchNumber = batch?['batch_number'] as String?;
            final harvestRecordId = batch?['harvest_record_id'] as String?;
            if (harvestRecordId != null) {
              final hr = await _client
                  .from('harvest_records')
                  .select('harvest_date')
                  .eq('id', harvestRecordId)
                  .maybeSingle();
              if (hr?['harvest_date'] != null) {
                harvestDate = DateTime.parse(hr!['harvest_date'] as String);
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      return AdminOrderModel.fromMap({
        ...row,
        'buyer_name': buyerName,
        'buyer_phone': buyerPhone,
        'buyer_photo_url': buyerPhotoUrl,
        'crop_name': cropName,
        'variety': variety,
        'photo_url': photoUrl,
        'batch_number': batchNumber,
        'harvest_date': harvestDate?.toIso8601String(),
        'category': category,
        'canonical_crop_name': canonicalCropName,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> approveOrder(String orderId) async {
    final row = await _client
        .from('orders')
        .update({'status': 'approved'})
        .eq('id', orderId)
        .eq('status', 'pending') // no-op if already moved on — avoids clobbering a race
        .select('buyer_id, listing_id')
        .maybeSingle();

    if (row == null) return; // already moved on — nothing to notify

    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'approved',
      description: 'Approved an order.',
      referenceId: orderId,
    );

    try {
      final listing = await _client
          .from('marketplace_listings')
          .select('crop_name')
          .eq('id', row['listing_id'] as String)
          .maybeSingle();
      final cropName = listing?['crop_name'] as String? ?? 'produce';

      await NotificationRepository().createNotification(
        userId: row['buyer_id'] as String,
        type: 'order',
        title: 'Order Approved',
        body: 'Your order for $cropName has been approved and is being prepared.',
      );
    } catch (_) {
      // Notification failure is non-fatal — order was already approved.
    }
  }

  /// Handles both "reject" (from pending) and "cancel" (from approved) —
  /// same inventory reversal either way. See note above the SQL.
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _client.rpc('cancel_order', params: {
      'p_order_id': orderId,
      if (reason != null) 'p_reason': reason,
    });
    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'cancelled',
      description: 'Cancelled an order.',
      referenceId: orderId,
    );
  }

  Future<void> completeOrder(String orderId) async {
    await _client.rpc('complete_order', params: {'p_order_id': orderId});
    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'completed',
      description: 'Completed an order.',
      referenceId: orderId,
    );
  }
}