/// One completed sale, across any of the 4 selling channels, for the
/// logged-in farmer only. Distinct from Admin's SalesTransactionRow
/// (admin_reports_model.dart): no farmerName (the viewer already knows
/// who they are).
///
/// buyerName is populated for every channel except Offer to Cooperative
/// (that transaction is directly with the cooperative/Admin side, so
/// there's no external buyer to name). For Market Linking specifically,
/// this is deliberately different from MyMarketLinkingScreen's own
/// in-progress enrollment view, which still hides buyer identity while a
/// deal is pending — once a sale is completed (the only state Transaction
/// History ever shows), that's just receipt-level detail, same as a
/// Marketplace order.
class FarmerTransactionModel {
  final String id;
  final String
  sellingType; // 'offer_to_cooperative' | 'marketplace' | 'informal_sale' | 'da_amad_market_linking'
  final String cropName;
  final double quantityKg;
  final double amount;
  final DateTime transactionDate;
  final String? referenceNo; // offer_to_cooperative only
  final String? buyerName; // every channel except offer_to_cooperative
  final String? orderStatus; // marketplace only
  final String?
  cropImageUrl; // the farmer's own crop photo, resolved by crop name

  const FarmerTransactionModel({
    required this.id,
    required this.sellingType,
    required this.cropName,
    required this.quantityKg,
    required this.amount,
    required this.transactionDate,
    this.referenceNo,
    this.buyerName,
    this.orderStatus,
    this.cropImageUrl,
  });
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
