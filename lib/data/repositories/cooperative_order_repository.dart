import 'admin_activity_repository.dart';
import '../../core/utils/chunked_in.dart';
import '../../core/utils/fetch_all_rows.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/program_model.dart';
import '../services/order_evidence_service.dart';
import '../services/server_only.dart';

/// What the database answered when an order was placed.
class PlacedProgramOrder {
  final String orderId;
  final String orderNumber;
  final double totalAmount;

  /// True when this was a retry of a request that had already been placed.
  final bool existing;
  const PlacedProgramOrder({
    required this.orderId,
    required this.orderNumber,
    required this.totalAmount,
    required this.existing,
  });

  factory PlacedProgramOrder.fromMap(Map<String, dynamic> m) =>
      PlacedProgramOrder(
        orderId: m['order_id'] as String,
        orderNumber: (m['order_number'] as String?) ?? '',
        totalAmount: (m['total_amount'] as num).toDouble(),
        existing: (m['existing'] as bool?) ?? false,
      );
}

/// Cooperative Product orders (program_product_purchases).
///
/// They stay apart from the Marketplace `orders` table, but members and staff see both in
/// one list. Every write is a guarded database function (the table cannot be written
/// directly), and every write throws so the screen can show the real reason.
class CooperativeOrderRepository {
  final SupabaseClient _client;
  CooperativeOrderRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const _select =
      '*, cooperative_programs(program_name), program_products(cooperative_inventory(item_name, unit, image_url))';

  Future<T> _write<T>(Future<T> Function() call) async {
    await ServerOnly.ensureOnline();
    return call();
  }

  List<ProgramPurchase> _toOrders(List rows, Map<String, String> names) {
    return [
      for (final r in rows)
        () {
          final row = Map<String, dynamic>.from(r as Map);
          final program = row['cooperative_programs'] as Map<String, dynamic>?;
          final product = row['program_products'] as Map<String, dynamic>?;
          final inv =
              product?['cooperative_inventory'] as Map<String, dynamic>?;
          return ProgramPurchase.fromMap({
            ...row,
            'program_name': row['program_name'] ?? program?['program_name'],
            'item_name': row['item_name'] ?? inv?['item_name'],
            'unit': row['unit'] ?? inv?['unit'],
            'image_url': inv?['image_url'],
            'farmer_name': names[row['farmer_id'] as String],
          });
        }(),
    ];
  }

  Future<Map<String, String>> _names(List rows) async {
    final ids = rows.map((r) => r['farmer_id'] as String).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final info = await chunkedIn(ids, (slice) => _client.from('user_information').select('user_id, full_name').inFilter('user_id', slice));
      return {
        for (final r in info)
          r['user_id'] as String: (r['full_name'] as String?) ?? 'Unknown',
      };
    } catch (_) {
      return {};
    }
  }

  /// Every Cooperative order, newest first. Staff only (the database hides them from others).
  Future<List<ProgramPurchase>> fetchAllOrders() async {
    try {
      final rows = await fetchAllRows(
        (from, to) => _client
            .from('program_product_purchases')
            .select(_select)
            .order('requested_at', ascending: false)
            .order('id')
            .range(from, to),
      );
      return _toOrders(rows, await _names(rows));
    } catch (_) {
      return [];
    }
  }

  /// One Farmer's own orders (the database only returns their own).
  Future<List<ProgramPurchase>> fetchMyOrders() async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(_select)
          .order('requested_at', ascending: false);
      return _toOrders(rows, const {});
    } catch (_) {
      return [];
    }
  }

  /// The PSO numbers of some orders, by order id (an unreadable row simply has none).
  Future<Map<String, String>> fetchOrderNumbers(List<String> orderIds) async {
    if (orderIds.isEmpty) return {};
    try {
      final rows = await chunkedIn(orderIds, (slice) => _client.from('program_product_purchases').select('id, order_number').inFilter('id', slice));
      return {
        for (final r in rows)
          if (r['order_number'] != null)
            r['id'] as String: r['order_number'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<ProgramPurchase?> fetchOrderById(String id) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(_select)
          .eq('id', id)
          .limit(1);
      if (rows.isEmpty) return null;
      return _toOrders(rows, await _names(rows)).first;
    } catch (_) {
      return null;
    }
  }

  // ─── Farmer ────────────────────────────────────────────────────────────

  /// Places one order line. [requestId] must stay the same for a retry of the same line: the
  /// database then returns the existing order instead of reserving stock a second time.
  Future<PlacedProgramOrder> placeOrder({
    required String programId,
    required String productId,
    required double quantity,
    required String fulfillmentMethod,
    required String requestId,
    String? groupId,
  }) => _write(() async {
    final res = await _client.rpc(
      'place_program_order',
      params: {
        'p_program_id': programId,
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_fulfillment_method': fulfillmentMethod,
        'p_group_id': groupId,
        'p_request_id': requestId,
      },
    );
    return PlacedProgramOrder.fromMap(Map<String, dynamic>.from(res as Map));
  });

  Future<void> confirmReceived(String orderId) => _write(
    () => _client.rpc(
      'confirm_program_order_received',
      params: {'p_order_id': orderId},
    ),
  );

  /// The Farmer's own pending order, or staff with a reason.
  Future<void> cancel(String orderId, {String? reason}) => _write(
    () => _client.rpc(
      'cancel_program_purchase',
      params: {'p_purchase_id': orderId, 'p_reason': reason},
    ),
  );

  // ─── Manager / Officer with Marketplace = Manage ───────────────────────

  Future<void> approve(String orderId) => _write(() async {
    await _client.rpc('approve_program_order', params: {'p_order_id': orderId});
    logStaffAction(
      'orders',
      'coop_order_approved',
      'adminLogCoopOrderApproved',
      referenceId: orderId,
    );
  });

  Future<void> markReady(String orderId) => _write(() async {
    await _client.rpc(
      'mark_program_order_ready',
      params: {'p_order_id': orderId},
    );
    logStaffAction(
      'orders',
      'coop_order_ready',
      'adminLogCoopOrderReady',
      referenceId: orderId,
    );
  });

  Future<void> markOutForDelivery(String orderId) => _write(() async {
    await _client.rpc(
      'mark_program_order_out_for_delivery',
      params: {'p_order_id': orderId},
    );
    logStaffAction(
      'orders',
      'coop_order_out_for_delivery',
      'adminLogCoopOrderOutForDelivery',
      referenceId: orderId,
    );
  });

  /// Pickup: the cash received at the counter. Delivery: handed over (photo required) with the cash.
  Future<void> recordHandover({
    required String orderId,
    required double amount,
    Uint8List? photoBytes,
    String? photoExtension,
    String? note,
  }) => _write(() async {
    String? url;
    if (photoBytes != null) {
      url = await uploadOrderEvidence(
        client: _client,
        kind: 'handover',
        orderId: orderId,
        bytes: photoBytes,
        extension: photoExtension ?? 'jpg',
      );
    }
    await _client.rpc(
      'record_program_order_handover',
      params: {
        'p_order_id': orderId,
        'p_amount': amount,
        'p_photo_url': url,
        'p_note': note,
      },
    );
    logStaffAction(
      'orders',
      'coop_order_handover',
      'adminLogCoopOrderHandover',
      referenceId: orderId,
    );
  });

  Future<void> completeForMember({
    required String orderId,
    required String reason,
    required Uint8List photoBytes,
    required String photoExtension,
  }) => _write(() async {
    final url = await uploadOrderEvidence(
      client: _client,
      kind: 'assisted',
      orderId: orderId,
      bytes: photoBytes,
      extension: photoExtension,
    );
    await _client.rpc(
      'staff_complete_program_order',
      params: {'p_order_id': orderId, 'p_reason': reason, 'p_photo_url': url},
    );
    logStaffAction(
      'orders',
      'coop_order_completed',
      'adminLogCoopOrderCompleted',
      referenceId: orderId,
    );
  });
}
