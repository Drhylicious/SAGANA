// Supply Chain Management is a read-only tracking view. Every record here is one
// supply movement the database already keeps in another module (Inventory,
// Programs, Offer to Cooperative, Order Management, Loans); this file only
// describes and filters them. Nothing in this module creates or changes data.

/// The stages a product is tracked through, in supply-chain order.
enum SupplyStage {
  /// Inventory Management: the supplier / source a restock came from.
  source,

  /// Program Management: a benefit distributed, or a harvest returned.
  program,

  /// Offer to Cooperative: a purchase received into Cooperative Inventory.
  offer,

  /// Order Management: a Cooperative Product or Marketplace order that reaches
  /// the consumer by pickup or delivery.
  consumer,

  /// Another real transaction type found in the system: inventory issued on a loan.
  other;

  String get key => name;

  static SupplyStage? fromKey(String? key) {
    for (final s in SupplyStage.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

enum SupplyDirection {
  incoming,
  outgoing;

  static SupplyDirection fromKey(String? key) =>
      key == 'incoming' ? SupplyDirection.incoming : SupplyDirection.outgoing;
}

/// What kind of movement a record is (the SQL `record_type`).
enum SupplyRecordType {
  inventoryRestock,
  programDistribution,
  cooperativePurchase,
  cooperativeSale,
  marketplaceSale,
  loanIssue,
  unknown;

  static SupplyRecordType fromKey(String? key) {
    switch (key) {
      case 'inventory_restock':
        return SupplyRecordType.inventoryRestock;
      case 'program_distribution':
        return SupplyRecordType.programDistribution;
      case 'cooperative_purchase':
        return SupplyRecordType.cooperativePurchase;
      case 'cooperative_sale':
        return SupplyRecordType.cooperativeSale;
      case 'marketplace_sale':
        return SupplyRecordType.marketplaceSale;
      case 'loan_issue':
        return SupplyRecordType.loanIssue;
      default:
        return SupplyRecordType.unknown;
    }
  }
}

/// A person or place a supply came from or went to. [role] is the stored role:
/// supplier | farmer | buyer | cooperative.
class SupplyParty {
  final String? name;
  final String? role;

  const SupplyParty({this.name, this.role});

  bool get hasName => name != null && name!.trim().isNotEmpty;
  bool get isCooperative => role == 'cooperative';
}

/// One row of `get_supply_chain_records`.
class SupplyChainRecord {
  final String key;
  final SupplyStage stage;
  final SupplyRecordType type;
  final SupplyDirection direction;
  final DateTime occurredAt;

  /// The supply has really moved. An order counts once it is completed; an order
  /// still being fulfilled is tracked but not yet counted.
  final bool isConfirmed;

  final String itemName;
  final String? category;
  // The item's type from Inventory Management: 'crop' or 'non_crop' (null when unknown).
  final String? itemType;
  // The Crop Master crop of a crop-type item (null for a Non-Crop Item).
  final String? cropName;
  final double quantity;
  final String unit;

  /// The Cooperative Inventory item the supply entered or left (null for a
  /// Farmer Marketplace sale, which is the Farmer's own harvest stock).
  final String? inventoryId;

  /// Where that item originally came from (its Farmer, or its recorded Source).
  final String? itemSource;

  final SupplyParty from;
  final SupplyParty to;
  final String? farmerName;
  final String? programName;

  /// Order number, loan reference or offer reference.
  final String? reference;
  final String? batchNumber;

  /// pickup | delivery (orders only).
  final String? fulfillmentMethod;

  /// The stored order status (orders only).
  final String? fulfillmentStatus;

  final String? refType;
  final String? refId;

  const SupplyChainRecord({
    required this.key,
    required this.stage,
    required this.type,
    required this.direction,
    required this.occurredAt,
    required this.isConfirmed,
    required this.itemName,
    this.category,
    this.itemType,
    this.cropName,
    required this.quantity,
    required this.unit,
    this.inventoryId,
    this.itemSource,
    this.from = const SupplyParty(),
    this.to = const SupplyParty(),
    this.farmerName,
    this.programName,
    this.reference,
    this.batchNumber,
    this.fulfillmentMethod,
    this.fulfillmentStatus,
    this.refType,
    this.refId,
  });

  bool get isIncoming => direction == SupplyDirection.incoming;
  bool get isOrder => stage == SupplyStage.consumer;
  bool get isInProgress => !isConfirmed;

  static String? _s(dynamic v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  factory SupplyChainRecord.fromMap(Map<String, dynamic> m) {
    return SupplyChainRecord(
      key: m['record_key'] as String,
      stage: SupplyStage.fromKey(m['stage'] as String?) ?? SupplyStage.other,
      type: SupplyRecordType.fromKey(m['record_type'] as String?),
      direction: SupplyDirection.fromKey(m['direction'] as String?),
      occurredAt: DateTime.parse(m['occurred_at'] as String).toLocal(),
      isConfirmed: m['is_confirmed'] as bool? ?? false,
      itemName: _s(m['item_name']) ?? '—',
      category: _s(m['category']),
      itemType: _s(m['item_type']),
      cropName: _s(m['crop_name']),
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      unit: _s(m['unit']) ?? 'kg',
      inventoryId: _s(m['inventory_id']),
      itemSource: _s(m['item_source']),
      from: SupplyParty(name: _s(m['from_name']), role: _s(m['from_role'])),
      to: SupplyParty(name: _s(m['to_name']), role: _s(m['to_role'])),
      farmerName: _s(m['farmer_name']),
      programName: _s(m['program_name']),
      reference: _s(m['reference_label']),
      batchNumber: _s(m['batch_number']),
      fulfillmentMethod: _s(m['fulfillment_method']),
      fulfillmentStatus: _s(m['fulfillment_status']),
      refType: _s(m['ref_type']),
      refId: _s(m['ref_id']),
    );
  }

  /// Everything a search can match, lower-cased once.
  String get searchText => [
    itemName,
    category,
    itemType,
    cropName,
    itemSource,
    from.name,
    to.name,
    farmerName,
    programName,
    reference,
    batchNumber,
  ].whereType<String>().join(' ').toLowerCase();
}

/// The figures of a set of records. Counts, not quantities: items are measured
/// in different units (kg, sack, bag, piece) and SAGANA never adds across units.
class SupplyChainTotals {
  final int incoming;
  final int outgoing;
  final int inProgress;

  const SupplyChainTotals({
    required this.incoming,
    required this.outgoing,
    required this.inProgress,
  });

  static const empty = SupplyChainTotals(incoming: 0, outgoing: 0, inProgress: 0);

  /// Total Supplies: every supply that has moved, incoming and outgoing.
  int get total => incoming + outgoing;

  factory SupplyChainTotals.of(Iterable<SupplyChainRecord> records) {
    var incoming = 0, outgoing = 0, inProgress = 0;
    for (final r in records) {
      if (!r.isConfirmed) {
        inProgress++;
      } else if (r.isIncoming) {
        incoming++;
      } else {
        outgoing++;
      }
    }
    return SupplyChainTotals(
      incoming: incoming,
      outgoing: outgoing,
      inProgress: inProgress,
    );
  }

  factory SupplyChainTotals.fromMap(Map<String, dynamic> m) => SupplyChainTotals(
    incoming: (m['incoming'] as num?)?.toInt() ?? 0,
    outgoing: (m['outgoing'] as num?)?.toInt() ?? 0,
    inProgress: (m['in_progress'] as num?)?.toInt() ?? 0,
  );
}

/// The movement filter: every record, or only those that bring supplies in or send
/// them out (an order being fulfilled counts under the direction it will move).
enum SupplyFlowFilter { all, incoming, outgoing }

/// The date range of the records shown. Defaults to this year, which starts again
/// each January like the Dashboard's Total Supplies.
enum SupplyDateRange { allTime, thisMonth, thisQuarter, thisYear }

bool supplyInDateRange(SupplyDateRange range, DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  switch (range) {
    case SupplyDateRange.allTime:
      return true;
    case SupplyDateRange.thisYear:
      return date.year == n.year;
    case SupplyDateRange.thisQuarter:
      return date.year == n.year && (date.month - 1) ~/ 3 == (n.month - 1) ~/ 3;
    case SupplyDateRange.thisMonth:
      return date.year == n.year && date.month == n.month;
  }
}

/// The stage filter, named after the SAGANA module each record belongs to.
/// A Consumer-stage record (an order) is split by who received it: a Farmer
/// Member (Cooperative Product orders, or a Farmer buying in the Marketplace) or
/// a Buyer. Price Management holds market prices, not supply movements, so it
/// is not a stage.
enum SupplyStageFilter {
  all,
  inventory,
  programs,
  cooperativePurchases,
  farmerMembers,
  buyers,
  loans;

  /// The one filter value a record belongs to (never [all]).
  static SupplyStageFilter of(SupplyChainRecord r) {
    switch (r.stage) {
      case SupplyStage.source:
        return SupplyStageFilter.inventory;
      case SupplyStage.program:
        return SupplyStageFilter.programs;
      case SupplyStage.offer:
        return SupplyStageFilter.cooperativePurchases;
      case SupplyStage.other:
        return SupplyStageFilter.loans;
      case SupplyStage.consumer:
        return r.to.role == 'farmer'
            ? SupplyStageFilter.farmerMembers
            : SupplyStageFilter.buyers;
    }
  }
}

/// Filters and searches [records]. Pure, so the screen, its counts and its
/// table always agree.
List<SupplyChainRecord> filterSupplyRecords(
  List<SupplyChainRecord> records, {
  SupplyDateRange range = SupplyDateRange.allTime,
  SupplyStageFilter stage = SupplyStageFilter.all,
  SupplyFlowFilter flow = SupplyFlowFilter.all,
  String query = '',
  DateTime? now,
}) {
  final q = query.trim().toLowerCase();
  return records.where((r) {
    if (!supplyInDateRange(range, r.occurredAt, now: now)) return false;
    if (stage != SupplyStageFilter.all && SupplyStageFilter.of(r) != stage) {
      return false;
    }
    if (flow == SupplyFlowFilter.incoming && !r.isIncoming) return false;
    if (flow == SupplyFlowFilter.outgoing && r.isIncoming) return false;
    return q.isEmpty || r.searchText.contains(q);
  }).toList();
}

/// The other movements of the same stock, oldest first. A record is related when
/// it touched the same Cooperative Inventory item, or the same Farmer harvest
/// batch: that batch number links a Farmer Marketplace sale to the Offer to
/// Cooperative that took part of the same harvest. [record] itself is not
/// included.
List<SupplyChainRecord> relatedSupplyRecords(
  SupplyChainRecord record,
  Iterable<SupplyChainRecord> all,
) {
  bool same(SupplyChainRecord r) =>
      (record.inventoryId != null && r.inventoryId == record.inventoryId) ||
      (record.batchNumber != null && r.batchNumber == record.batchNumber);

  return all.where((r) => r.key != record.key && same(r)).toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
}
