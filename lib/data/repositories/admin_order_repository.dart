import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../services/order_evidence_service.dart';
import '../services/server_only.dart';
import '../../core/utils/order_reference.dart';
import '../../core/utils/order_status.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/farmer_crop_model.dart' show marketTypeLabelFor;
import 'admin_activity_repository.dart';
import 'crop_lookup.dart';
import '../models/admin_log_message.dart';

// ─── Admin Order Model ─────────────────────────────────────────────────────

class AdminOrderModel {
  final String id;

  /// The database-issued ORD-YYYYMMDD-XXXX number. Null for an order placed
  /// before order numbers existed (it keeps its old reference).
  final String? orderNumber;
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

  /// The unit quantityKg and pricePerKg are measured in (copied from the
  /// listing by the database; the fields keep their old names).
  final String unit;
  final double totalPrice;
  final String status; // pending | approved | ready_for_pickup | out_for_delivery | delivered | completed | cancelled
  final String? notes;
  // 'buyer' | 'farmer' for a pending order the buyer or farmer cancelled
  // (batch9_01). Null for rejections and for older cancellations.
  final String? cancelledBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Fulfillment — captured atomically with the order at Checkout (never
  // chosen later). All null for legacy pre-Checkout-rework orders.
  final String? fulfillmentMethod; // 'pickup' | 'delivery' | null
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? deliveryContactNumber;
  final String? deliveryNotes;
  final String? deliveryRecipientName;
  final String? deliveryLabel;

  // Fulfillment progress the Manager / Officer recorded, and the delivery photo.
  final DateTime? readyAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final String? deliveryPhotoUrl;
  final String? deliveryEvidenceNote;

  // Payment: cash collected by the cooperative (counter for Pickup, on delivery for Delivery).
  // Separate from the fulfillment status. A completed order from before payments were
  // recorded reads 'not_recorded'.
  final String paymentStatus; // 'unpaid' | 'paid' | 'not_recorded'
  final DateTime? paidAt;
  final double? amountCollected;
  final double deliveryFeeCollected;
  final String? paymentRecordedByName;
  final String? paymentRecordedByRole;
  final String? paymentNote;
  final String? checkoutGroupId;
  final String? completionMethod; // 'consumer' | 'staff'
  final String? staffCompletionReason;
  final String? staffCompletionPhotoUrl;
  final String? staffCompletedByName;
  final String? staffCompletedByRole;
  final DateTime? staffCompletedAt;

  // Detail-screen-only, same convention as BuyerOrderModel.
  final String? batchNumber;
  final DateTime? harvestDate;
  final String? category;
  final String?
  marketType; // sp3_cooperative | da_amad_market | open_market — from inventory_batches.crop_type
  final String? description;

  // Canonical crop_master.crop_name, resolved via the order's listing's
  // crop_id — falls back to cropName when unresolved, same convention as
  // BuyerOrderModel/AdminListingModel.
  final String? canonicalCropName;

  const AdminOrderModel({
    required this.id,
    required this.listingId,
    required this.buyerId,
    this.orderNumber,
    required this.buyerName,
    this.buyerPhone,
    this.buyerPhotoUrl,
    required this.cropName,
    this.variety,
    this.listingPhotoUrl,
    required this.quantityKg,
    required this.pricePerKg,
    this.unit = kDefaultUnit,
    required this.totalPrice,
    required this.status,
    this.notes,
    this.cancelledBy,
    required this.createdAt,
    required this.updatedAt,
    this.fulfillmentMethod,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryContactNumber,
    this.deliveryNotes,
    this.deliveryRecipientName,
    this.deliveryLabel,
    this.readyAt,
    this.outForDeliveryAt,
    this.deliveredAt,
    this.deliveryPhotoUrl,
    this.deliveryEvidenceNote,
    this.paymentStatus = 'unpaid',
    this.paidAt,
    this.amountCollected,
    this.deliveryFeeCollected = 0,
    this.paymentRecordedByName,
    this.paymentRecordedByRole,
    this.paymentNote,
    this.checkoutGroupId,
    this.completionMethod,
    this.staffCompletionReason,
    this.staffCompletionPhotoUrl,
    this.staffCompletedByName,
    this.staffCompletedByRole,
    this.staffCompletedAt,
    this.batchNumber,
    this.harvestDate,
    this.category,
    this.marketType,
    this.description,
    this.canonicalCropName,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isReadyForPickup => status == 'ready_for_pickup';
  bool get isOutForDelivery => status == 'out_for_delivery';
  bool get isDelivered => status == 'delivered';
  bool get isCompleted => status == 'completed';

  /// The Manager / Officer's next step on this order, or null when it is not theirs.
  StaffOrderAction? get nextAction =>
      nextStaffOrderAction(status, fulfillmentMethod, paymentStatus: paymentStatus);
  bool get isPaymentRecorded => paymentStatus == 'paid';
  bool get isCancelled => status == 'cancelled';

  bool get hasFulfillmentChoice => fulfillmentMethod != null;
  bool get isPickupChoice => fulfillmentMethod == 'pickup';
  bool get isDelivery => fulfillmentMethod == 'delivery';

  String get displayName {
    final name = canonicalCropName ?? cropName;
    final v = variety?.trim();
    if (v == null || v.isEmpty) return name;
    if (name.toLowerCase().contains(v.toLowerCase())) return name;
    return '$name ($v)';
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending Order';
      case 'approved':
        return 'Approved';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String get orderReference => orderReferenceOf(id, orderNumber);

  String get harvestedLabel {
    if (harvestDate == null) return '';
    final diff = DateTime.now().difference(harvestDate!);
    if (diff.inDays <= 0) return 'Harvested today';
    if (diff.inDays == 1) return 'Harvested yesterday';
    return 'Harvested ${diff.inDays} days ago';
  }

  String get marketTypeLabel => marketTypeLabelFor(marketType);

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory AdminOrderModel.fromMap(Map<String, dynamic> map) {
    return AdminOrderModel(
      id: map['id'] as String,
      orderNumber: map['order_number'] as String?,
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
      unit: unitOrDefault(map['unit'] as String?),
      totalPrice: (map['total_price'] as num).toDouble(),
      status: canonicalOrderStatus(map['status'] as String?),
      notes: map['notes'] as String?,
      cancelledBy: map['cancelled_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      fulfillmentMethod: map['fulfillment_method'] as String?,
      deliveryAddress: map['delivery_address'] as String?,
      deliveryLatitude: (map['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['delivery_longitude'] as num?)?.toDouble(),
      deliveryContactNumber: map['delivery_contact_number'] as String?,
      deliveryNotes: map['delivery_notes'] as String?,
      deliveryRecipientName: map['delivery_recipient_name'] as String?,
      deliveryLabel: map['delivery_label'] as String?,
      readyAt: _dt(map['ready_at']),
      outForDeliveryAt: _dt(map['out_for_delivery_at']),
      deliveredAt: _dt(map['delivered_at']),
      deliveryPhotoUrl: map['delivery_photo_url'] as String?,
      deliveryEvidenceNote: map['delivery_evidence_note'] as String?,
      paymentStatus: map['payment_status'] as String? ?? 'unpaid',
      paidAt: _dt(map['paid_at']),
      amountCollected: (map['amount_collected'] as num?)?.toDouble(),
      deliveryFeeCollected: (map['delivery_fee_collected'] as num?)?.toDouble() ?? 0,
      paymentRecordedByName: map['payment_recorded_by_name'] as String?,
      paymentRecordedByRole: map['payment_recorded_by_role'] as String?,
      paymentNote: map['payment_note'] as String?,
      checkoutGroupId: map['checkout_group_id'] as String?,
      completionMethod: map['completion_method'] as String?,
      staffCompletionReason: map['staff_completion_reason'] as String?,
      staffCompletionPhotoUrl: map['staff_completion_photo_url'] as String?,
      staffCompletedByName: map['staff_completed_by_name'] as String?,
      staffCompletedByRole: map['staff_completed_by_role'] as String?,
      staffCompletedAt: _dt(map['staff_completed_at']),
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      category: map['category'] as String?,
      marketType: map['market_type'] as String?,
      description: map['description'] as String?,
      canonicalCropName: map['canonical_crop_name'] as String?,
    );
  }
}

// ─── Order Summary Stats ────────────────────────────────────────────────────

class OrderSummaryStats {
  final int total;
  final int pending;
  final int approved;
  final int readyForPickup;
  final int outForDelivery;
  final int delivered;
  final int completed;
  final int cancelled;

  /// Ready for Pickup / Delivered orders whose cash the cooperative has not recorded yet:
  /// staff still have a step to do on them.
  final int awaitingPayment;

  const OrderSummaryStats({
    required this.total,
    required this.pending,
    required this.approved,
    this.readyForPickup = 0,
    this.outForDelivery = 0,
    this.delivered = 0,
    required this.completed,
    required this.cancelled,
    this.awaitingPayment = 0,
  });

  /// Orders waiting for the Manager / Officer: Pending + Approved + Out for
  /// Delivery + those whose payment is not recorded yet. Orders that are paid and wait only
  /// for the consumer's confirmation are not counted.
  int get needsAction => pending + approved + outForDelivery + awaitingPayment;

  static const empty = OrderSummaryStats(
    total: 0,
    pending: 0,
    approved: 0,
    completed: 0,
    cancelled: 0,
  );

  /// Builds the figures from [{status, n}] count rows ('total' is every order).
  factory OrderSummaryStats.fromCountRows(List<Map<String, dynamic>> rows) {
    int of(String status) => rows
        .where((r) => r['status'] == status)
        .fold<int>(0, (sum, r) => sum + ((r['n'] as num?)?.toInt() ?? 0));
    return OrderSummaryStats(
      total: of('total'),
      pending: of('pending'),
      approved: of('approved'),
      readyForPickup: of('ready_for_pickup'),
      outForDelivery: of('out_for_delivery'),
      delivered: of('delivered'),
      completed: of('completed'),
      cancelled: of('cancelled'),
      awaitingPayment: of('awaiting_payment'),
    );
  }
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
      // Merged order maps are cached per status and buyer filter (search text is
      // applied after the read). Models are built after the cache.
      final enriched = await OfflineCache.load(
        screen: 'orders_${statusFilter ?? 'all'}_${buyerId ?? 'all'}',
        fetch: () async {
          var query = _client
              .from('orders')
              .select(
                'id, order_number, listing_id, buyer_id, quantity_kg, price_per_kg, unit, total_price, '
                'status, notes, cancelled_by, created_at, updated_at, fulfillment_method, payment_status',
              );

          if (statusFilter != null) query = query.eq('status', statusFilter);
          if (buyerId != null) query = query.eq('buyer_id', buyerId);

          final rows = await query.order('created_at', ascending: false);
          if (rows.isEmpty) return <Map<String, dynamic>>[];

          final buyerIds = rows
              .map((r) => r['buyer_id'] as String)
              .toSet()
              .toList();
          final listingIds = rows
              .map((r) => r['listing_id'] as String)
              .toSet()
              .toList();

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

          return rows.map<Map<String, dynamic>>((r) {
            final buyer = buyerMap[r['buyer_id']];
            final listing = listingMap[r['listing_id']];
            final cropId = listing?['crop_id'] as String?;
            return {
              ...r,
              'buyer_name': buyer?['full_name'],
              'buyer_phone': buyer?['phone_number'],
              'buyer_photo_url': buyer?['profile_photo_url'],
              'crop_name': listing?['crop_name'],
              'variety': listing?['variety'],
              'photo_url': listing?['photo_url'],
              'canonical_crop_name': cropId != null
                  ? canonicalNames[cropId]
                  : null,
            };
          }).toList();
        },
      );

      var result = enriched.map((m) => AdminOrderModel.fromMap(m)).toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        result = result
            .where(
              (o) =>
                  o.buyerName.toLowerCase().contains(q) ||
                  o.cropName.toLowerCase().contains(q) ||
                  o.orderReference.toLowerCase().contains(q),
            )
            .toList();
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  /// The Marketplace Overview's order figures: exact counts taken by the
  /// database (a plain select would stop at 1000 rows). Total is every order;
  /// a legacy 'rejected' order counts as cancelled, as it is shown.
  Future<OrderSummaryStats> fetchSummaryStats() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'order_status_counts_v3',
        fetch: () async {
          // One count per status, over Marketplace orders AND Cooperative Product orders (the
          // staff list shows both). A table that cannot be read counts as zero.
          Future<int> n(String table, [List<String>? statuses, bool unpaidOnly = false]) async {
            try {
              var q = _client.from(table).count();
              if (statuses != null) q = q.inFilter('status', statuses);
              if (unpaidOnly) q = q.eq('payment_status', 'unpaid');
              return await q;
            } catch (_) {
              return 0;
            }
          }

          Future<int> both([List<String>? statuses, bool unpaidOnly = false]) async {
            final r = await Future.wait([
              n('orders', statuses, unpaidOnly),
              n('program_product_purchases', statuses, unpaidOnly),
            ]);
            return r[0] + r[1];
          }

          final results = await Future.wait([
            both(),
            both(['pending']),
            both(['approved']),
            both(['completed']),
            both(['cancelled', 'rejected']),
            both(['ready_for_pickup']),
            both(['out_for_delivery']),
            both(['delivered']),
            both(['ready_for_pickup', 'delivered'], true),
          ]);
          return [
            {'status': 'total', 'n': results[0]},
            {'status': 'pending', 'n': results[1]},
            {'status': 'approved', 'n': results[2]},
            {'status': 'completed', 'n': results[3]},
            {'status': 'cancelled', 'n': results[4]},
            {'status': 'ready_for_pickup', 'n': results[5]},
            {'status': 'out_for_delivery', 'n': results[6]},
            {'status': 'delivered', 'n': results[7]},
            {'status': 'awaiting_payment', 'n': results[8]},
          ];
        },
      );
      return OrderSummaryStats.fromCountRows(rows);
    } catch (_) {
      return OrderSummaryStats.empty;
    }
  }

  Future<AdminOrderModel?> fetchOrderById(String orderId) async {
    try {
      final row = await _client
          .from('orders')
          .select(
            'id, order_number, listing_id, buyer_id, quantity_kg, price_per_kg, unit, '
            'total_price, status, notes, cancelled_by, created_at, updated_at, '
            'fulfillment_method, delivery_address, delivery_latitude, '
            'delivery_longitude, delivery_contact_number, delivery_notes, '
            'delivery_recipient_name, delivery_label, ready_at, out_for_delivery_at, '
            'delivered_at, delivery_photo_url, delivery_evidence_note, payment_status, paid_at, '
            'amount_collected, delivery_fee_collected, payment_recorded_by_name, payment_recorded_by_role, '
            'payment_note, checkout_group_id, completion_method, staff_completion_reason, '
            'staff_completion_photo_url, staff_completed_by_name, staff_completed_by_role, staff_completed_at',
          )
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
      String? variety,
          photoUrl,
          batchId,
          batchNumber,
          category,
          canonicalCropName,
          marketType,
          description;
      DateTime? harvestDate;
      try {
        final listing = await _client
            .from('marketplace_listings')
            .select(
              'crop_name, crop_id, variety, photo_url, description, inventory_batch_id',
            )
            .eq('id', listingId)
            .maybeSingle();
        cropName = listing?['crop_name'] as String? ?? 'Produce';
        variety = listing?['variety'] as String?;
        photoUrl = listing?['photo_url'] as String?;
        description = listing?['description'] as String?;
        batchId = listing?['inventory_batch_id'] as String?;

        final cropId = listing?['crop_id'] as String?;
        if (cropId != null) {
          canonicalCropName = (await fetchCropNameMap(_client, [
            cropId,
          ]))[cropId];
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
                .select('batch_number, harvest_record_id, crop_type')
                .eq('id', batchId)
                .maybeSingle();
            batchNumber = batch?['batch_number'] as String?;
            marketType = batch?['crop_type'] as String?;
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
        'market_type': marketType,
        'description': description,
        'canonical_crop_name': canonicalCropName,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  // Guarded RPC, matching place_order/cancel_my_order/complete_order's own
  // convention (SECURITY DEFINER, admin check, FOR UPDATE row lock) —
  // was previously a raw client .update(), the one action in this module
  // that didn't go through a guarded RPC. Notifications now live
  // server-side inside approve_order() itself, same as complete_order. Returns false (silently, matching the old "no-op if
  // already moved on" behavior) if the order isn't pending anymore.
  Future<void> approveOrder(String orderId) async {
    await ServerOnly.ensureOnline();
    final applied =
        await _client.rpc('approve_order', params: {'p_order_id': orderId})
            as bool;
    if (!applied) return; // already moved on — nothing to log
    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'approved',
      message: const AdminLogMessage('adminLogOrderApproved'),
      referenceId: orderId,
    );
  }

  // ─── Fulfillment steps (Manager / Officer) ───────────────────────────────
  // Each is one guarded database function that checks the role, the order's
  // fulfillment method and its current status, and refuses a repeat. They are
  // recorded by hand, one at a time; nothing moves an order on its own.

  Future<void> markReadyForPickup(String orderId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('mark_order_ready_for_pickup', params: {'p_order_id': orderId});
    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'ready_for_pickup',
      message: const AdminLogMessage('adminLogOrderReadyForPickup'),
      referenceId: orderId,
    );
  }

  Future<void> markOutForDelivery(String orderId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('mark_order_out_for_delivery', params: {'p_order_id': orderId});
    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'out_for_delivery',
      message: const AdminLogMessage('adminLogOrderOutForDelivery'),
      referenceId: orderId,
    );
  }

  /// The delivery fee the next handover in this order delivery group has to collect: the whole
  /// group fee until it was collected once, then zero. No group (or no delivery fee) is zero.
  Future<double> fetchGroupFeeDue(String? groupId) async {
    if (groupId == null) return 0;
    try {
      final rows = await _client
          .from('checkout_groups')
          .select('delivery_fee, fee_collected_at')
          .eq('id', groupId)
          .limit(1);
      if (rows.isEmpty || rows.first['fee_collected_at'] != null) return 0;
      return (rows.first['delivery_fee'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Pickup: records the cash received at the counter. Delivery: records the handover (photo
  /// required, uploaded first) together with the cash collected, which marks it Delivered. The
  /// database checks the amount against the order total plus, for the first handover of a
  /// delivery group, the group's one delivery fee.
  Future<void> recordHandover({
    required String orderId,
    required double amount,
    Uint8List? photoBytes,
    String? photoExtension,
    String? note,
  }) async {
    await ServerOnly.ensureOnline();
    String? url;
    if (photoBytes != null) {
      url = await uploadOrderEvidence(
        client: _client,
        kind: 'delivery',
        orderId: orderId,
        bytes: photoBytes,
        extension: photoExtension ?? 'jpg',
      );
    }
    await _client.rpc('record_order_handover', params: {
      'p_order_id': orderId,
      'p_amount': amount,
      'p_photo_url': url,
      'p_note': note,
    });
    AdminActivityRepository().log(
      module: 'orders',
      actionType: 'delivered',
      message: const AdminLogMessage('adminLogOrderDelivered'),
      referenceId: orderId,
    );
  }

  /// The cash for an order that was already Delivered before payments were recorded.
  Future<void> recordPayment({required String orderId, required double amount, String? note}) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('record_order_payment', params: {
      'p_order_id': orderId,
      'p_amount': amount,
      'p_note': note,
    });
  }

  /// The consumer cannot confirm: staff complete it. Needs a reason and a photo; the database
  /// stores who did it and when.
  Future<void> completeForCustomer({
    required String orderId,
    required String reason,
    required Uint8List photoBytes,
    required String photoExtension,
  }) async {
    await ServerOnly.ensureOnline();
    final url = await uploadOrderEvidence(
      client: _client,
      kind: 'assisted',
      orderId: orderId,
      bytes: photoBytes,
      extension: photoExtension,
    );
    await _client.rpc('staff_complete_order', params: {
      'p_order_id': orderId,
      'p_reason': reason,
      'p_photo_url': url,
    });
  }

  // There is no Manager "reject / cancel order" any more. An order ends in one of
  // two ways: its Buyer or Farmer cancels it while it is still pending
  // (BuyerOrderRepository.cancelMyOrder), or the Manager / Officer approves it
  // and the consumer who ordered it then confirms they received it
  // (BuyerOrderRepository.confirmReceived). The Manager / Officer does not
  // complete an order: the database refuses it. An old stored 'rejected' reads
  // as 'cancelled'.
}
