/// Dedicated model for cooperative_purchase_offers.
///
/// An offer is a negotiation over the PRICE PER KG of a fixed quantity. The
/// stored status values are 'pending' (the negotiation is open), 'confirmed'
/// (agreed and settled), 'declined' (the Cooperative ended it) and 'cancelled'
/// (the Farmer ended it). While an offer is pending, [lastProposedBy] says who
/// made the latest price, and so who has to answer next. Filter and query
/// logic must always use these stored values, never a display label.
class CooperativeOfferModel {
  final String id;
  final String farmerId;
  final String farmerName;
  final String cropName;
  final double offeredQuantityKg;
  final DateTime offeredAt;
  final String? inventoryBatchId;
  final String status; // pending | confirmed | declined | cancelled
  final double? confirmedQuantityKg;
  final double? confirmedAmount;
  final String? adminNotes;
  final DateTime? confirmedAt;

  /// The Farmer's first price. Null only for an offer made before price
  /// negotiation existed (the Cooperative then proposes the first price).
  final double? askingPricePerKg;

  /// The latest price on the table, from whichever side proposed it last.
  final double? currentPricePerKg;

  /// The price both sides agreed on; set when the offer is accepted.
  final double? agreedPricePerKg;

  /// 'farmer' or 'cooperative': who proposed [currentPricePerKg].
  final String lastProposedBy;

  /// Starts at 1 and goes up with every counteroffer. Sent back with an accept
  /// or counter so a price that changed in the meantime cannot be accepted.
  final int negotiationRound;

  // Detail-screen-only, left null by the list queries.
  final String? farmerPhone;
  final String? farmerPhotoUrl;
  final String? batchNumber;
  final DateTime? harvestDate;
  final String? category;

  const CooperativeOfferModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.cropName,
    required this.offeredQuantityKg,
    required this.offeredAt,
    this.inventoryBatchId,
    required this.status,
    this.confirmedQuantityKg,
    this.confirmedAmount,
    this.adminNotes,
    this.confirmedAt,
    this.askingPricePerKg,
    this.currentPricePerKg,
    this.agreedPricePerKg,
    this.lastProposedBy = 'farmer',
    this.negotiationRound = 1,
    this.farmerPhone,
    this.farmerPhotoUrl,
    this.batchNumber,
    this.harvestDate,
    this.category,
  });

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isDeclined => status == 'declined';
  bool get isCancelled => status == 'cancelled';

  /// Open, and the Cooperative has to answer (the Farmer proposed last).
  bool get awaitingCooperative => isPending && lastProposedBy == 'farmer';

  /// Open, and the Farmer has to answer (the Cooperative proposed last).
  bool get awaitingFarmer => isPending && lastProposedBy == 'cooperative';

  bool get hasPrice => currentPricePerKg != null;

  /// The latest price times the fixed quantity.
  double? get currentTotal =>
      currentPricePerKg == null ? null : currentPricePerKg! * offeredQuantityKg;

  /// The settled amount once accepted, else null.
  double? get settledAmount => isConfirmed ? confirmedAmount : null;

  String get offeredLabel {
    final diff = DateTime.now().difference(offeredAt);
    if (diff.inDays <= 0) return 'Offered today';
    if (diff.inDays == 1) return 'Offered yesterday';
    return 'Offered ${diff.inDays} days ago';
  }

  String get harvestedLabel {
    if (harvestDate == null) return '';
    final diff = DateTime.now().difference(harvestDate!);
    if (diff.inDays <= 0) return 'Harvested today';
    if (diff.inDays == 1) return 'Harvested yesterday';
    return 'Harvested ${diff.inDays} days ago';
  }

  /// Columns every offer query selects.
  static const String selectColumns =
      'id, farmer_id, crop_name, offered_quantity_kg, offered_at, '
      'inventory_batch_id, status, confirmed_quantity_kg, confirmed_amount, '
      'admin_notes, confirmed_at, asking_price_per_kg, current_price_per_kg, '
      'agreed_price_per_kg, last_proposed_by, negotiation_round';

  static double? _num(dynamic v) => v == null ? null : (v as num).toDouble();

  factory CooperativeOfferModel.fromMap(Map<String, dynamic> map) {
    return CooperativeOfferModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      farmerName: map['farmer_name'] as String? ?? 'Farmer',
      cropName: map['crop_name'] as String? ?? 'Produce',
      offeredQuantityKg: (map['offered_quantity_kg'] as num).toDouble(),
      offeredAt: DateTime.parse(map['offered_at'] as String),
      inventoryBatchId: map['inventory_batch_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      confirmedQuantityKg: _num(map['confirmed_quantity_kg']),
      confirmedAmount: _num(map['confirmed_amount']),
      adminNotes: map['admin_notes'] as String?,
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.parse(map['confirmed_at'] as String)
          : null,
      askingPricePerKg: _num(map['asking_price_per_kg']),
      currentPricePerKg: _num(map['current_price_per_kg']),
      agreedPricePerKg: _num(map['agreed_price_per_kg']),
      lastProposedBy: map['last_proposed_by'] as String? ?? 'farmer',
      negotiationRound: (map['negotiation_round'] as num?)?.toInt() ?? 1,
      farmerPhone: map['farmer_phone'] as String?,
      farmerPhotoUrl: map['farmer_photo_url'] as String?,
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      category: map['category'] as String?,
    );
  }
}

/// One step of a negotiation, from cooperative_offer_events.
class CooperativeOfferEvent {
  final String id;
  final String offerId;
  final int round;

  /// offered | countered | accepted | declined | cancelled
  final String action;

  /// 'farmer' or 'cooperative'
  final String actorRole;
  final String? actorId;
  final double? pricePerKg;
  final double? quantityKg;
  final String? note;
  final DateTime createdAt;

  const CooperativeOfferEvent({
    required this.id,
    required this.offerId,
    required this.round,
    required this.action,
    required this.actorRole,
    this.actorId,
    this.pricePerKg,
    this.quantityKg,
    this.note,
    required this.createdAt,
  });

  bool get byFarmer => actorRole == 'farmer';

  factory CooperativeOfferEvent.fromMap(Map<String, dynamic> map) {
    return CooperativeOfferEvent(
      id: map['id'] as String,
      offerId: map['offer_id'] as String,
      round: (map['round'] as num).toInt(),
      action: map['action'] as String,
      actorRole: map['actor_role'] as String,
      actorId: map['actor_id'] as String?,
      pricePerKg: (map['price_per_kg'] as num?)?.toDouble(),
      quantityKg: (map['quantity_kg'] as num?)?.toDouble(),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
