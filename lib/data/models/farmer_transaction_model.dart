import '../../core/utils/quantity_utils.dart';

/// One completed sale, across any of the 4 selling channels, for the
/// logged-in farmer only. Distinct from Admin's SalesTransactionRow
/// (admin_reports_model.dart): no farmerName (the viewer already knows
/// who they are).
///
/// Only COMPLETED sales are ever built from the database:
///   * Offer to Cooperative — the Manager / Officer confirmed the delivery
///     (member_sales_transactions is written only then);
///   * Marketplace — the order is Completed (the buyer confirmed receipt);
///   * Informal Sale — a recorded direct sale;
///   * DA-AMAD Market Linking — a recorded sale of a request (market_linking_sales).
///
/// [quantityKg] / [unit] are the quantity and the unit of the ORIGINAL harvest
/// entry (never assumed to be kg). [marketType] and [cropCategory] are the crop's
/// own (crop_master), so they read the same on every channel.
///
/// buyerName is populated for every channel except Offer to Cooperative
/// (that transaction is directly with the cooperative/Admin side, so
/// there's no external buyer to name). For Market Linking the sale also
/// carries the agreed price per unit and the buyer's contact number and email,
/// as saved when it was recorded — the same buyer the Farmer sees on their
/// request in Market Linking.
///
/// No staff identity is carried here: a Farmer sees "the Cooperative", never
/// which Manager or Officer handled the sale (that is recorded for staff only).

class FarmerTransactionModel {
  final String id;
  final String
  sellingType; // 'offer_to_cooperative' | 'marketplace' | 'informal_sale' | 'da_amad_market_linking'
  final String cropName;
  final double quantityKg;

  /// The unit quantityKg is measured in.
  final String unit;
  final double amount;

  /// The day the sale was completed: the delivery receipt (Offer to
  /// Cooperative), the buyer's confirmation of receipt (Marketplace), the sale
  /// date (Informal Sale), the date the sale was recorded (DA-AMAD).
  final DateTime transactionDate;
  final String? referenceNo; // offer_to_cooperative and marketplace
  final String? buyerName; // every channel except offer_to_cooperative
  final String? orderStatus; // marketplace only

  /// The agreed / charged price per [unit], when the channel stores one (Offer to
  /// Cooperative, Marketplace, DA-AMAD Market Linking). The field keeps its old
  /// name.
  final double? pricePerKg;

  /// Market Linking only: the buyer's contact number and email, as saved when the
  /// sale was recorded.
  final String? buyerContact;
  final String? buyerEmail;
  final String?
  cropImageUrl; // the farmer's own crop photo, resolved by crop name

  /// The crop's market type code (crop_master.crop_type: Public / Cooperative)
  /// and its category (Vegetable, Fruit, ...). Null when the crop is not in the
  /// catalog.
  final String? marketType;
  final String? cropCategory;

  /// The harvest batch the quantity came from (`BATCH-...`).
  final String? batchNumber;

  /// Marketplace only: `pickup` or `delivery`.
  final String? fulfillmentMethod;

  /// Offer to Cooperative only: when the Farmer delivered it.
  final DateTime? deliveredAt;

  const FarmerTransactionModel({
    required this.id,
    required this.sellingType,
    required this.cropName,
    required this.quantityKg,
    this.unit = kDefaultUnit,
    required this.amount,
    required this.transactionDate,
    this.referenceNo,
    this.buyerName,
    this.orderStatus,
    this.pricePerKg,
    this.buyerContact,
    this.buyerEmail,
    this.cropImageUrl,
    this.marketType,
    this.cropCategory,
    this.batchNumber,
    this.fulfillmentMethod,
    this.deliveredAt,
  });

  /// The same transaction with the crop's market type and category, and the
  /// harvest batch number, filled in.
  FarmerTransactionModel withDetails({
    String? marketType,
    String? cropCategory,
    String? batchNumber,
  }) =>
      FarmerTransactionModel(
        id: id,
        sellingType: sellingType,
        cropName: cropName,
        quantityKg: quantityKg,
        unit: unit,
        amount: amount,
        transactionDate: transactionDate,
        referenceNo: referenceNo,
        buyerName: buyerName,
        orderStatus: orderStatus,
        pricePerKg: pricePerKg,
        buyerContact: buyerContact,
        buyerEmail: buyerEmail,
        cropImageUrl: cropImageUrl,
        marketType: marketType ?? this.marketType,
        cropCategory: cropCategory ?? this.cropCategory,
        batchNumber: batchNumber ?? this.batchNumber,
        fulfillmentMethod: fulfillmentMethod,
        deliveredAt: deliveredAt,
      );
}

String sellingTypeLabel(String sellingType) {
  switch (sellingType) {
    case 'offer_to_cooperative':
      return 'Offer to Cooperative';
    case 'marketplace':
      return 'Marketplace';
    case 'informal_sale':
      return 'Informal Sale (F2F)';
    case 'da_amad_market_linking':
      return 'DA-AMAD Market Linking';
    default:
      return sellingType;
  }
}
