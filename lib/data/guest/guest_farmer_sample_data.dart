import '../../core/l10n/app_localizations.dart';
import '../models/analytics_model.dart';
import '../models/cooperative_product_model.dart';
import '../models/dashboard_summary_model.dart';
import '../models/farmer_market_rate_model.dart';
import '../models/harvest_model.dart';
import '../models/marketplace_listing_model.dart';
import '../models/price_record_model.dart';
import '../services/market_types_service.dart';

/// Made-up figures for "Explore as Farmer". Nothing here is read from, or
/// written to, the database: it exists only so a visitor can see what the
/// Farmer screens look like. Every id starts with [idPrefix] so a sample row can
/// never be mistaken for (or sent as) a real record.
///
/// The crops are ones the SP3 Agriculture Cooperative's members actually grow
/// (peanut, palay, banana), so the preview reads like the real app. Keep this in
/// step with the Farmer tabs: when a tab gains or loses a section, the sample for
/// it changes here.
class GuestFarmerSampleData {
  GuestFarmerSampleData._();

  static const String idPrefix = 'guest-sample-';

  static DateTime _daysAgo(int d) => DateTime.now().subtract(Duration(days: d));

  // ── Home ──────────────────────────────────────────────────────────────────

  static DashboardSummaryModel get summary => const DashboardSummaryModel(
    monthlyYieldKg: 1250,
    previousMonthYieldKg: 1000,
    annualYieldKg: 9800,
    monthlyEarnings: 18500,
    annualEarnings: 142000,
    earningsGoal: 25000,
    unsyncedCount: 0,
  );

  static List<FarmerMarketRateModel> get marketRates {
    final type = MarketTypes.instance.defaultCode ?? '';
    FarmerMarketRateModel rate(
      String id,
      String crop,
      String category,
      double price,
      double previous,
    ) => FarmerMarketRateModel(
      cropCategory: category,
      price: PriceRecordModel(
        id: '$idPrefix$id',
        cropId: '$idPrefix$id',
        cropName: crop,
        price: price,
        unit: 'kg',
        priceType: type,
        previousPrice: previous,
        recordedAt: _daysAgo(1),
      ),
    );
    return [
      rate('rate-1', 'Peanut', 'Legume', 60, 55),
      rate('rate-2', 'Palay', 'Grain', 20, 20),
      rate('rate-3', 'Banana', 'Fruit', 25, 27),
    ];
  }

  /// Recent Activity rows, worded in the viewer's language. The types are ones
  /// the real feed produces today.
  static List<ActivityItem> activity(AppLocalizations l10n) => [
    ActivityItem(
      id: '${idPrefix}act-1',
      type: ActivityType.harvest,
      title: l10n.guestSampleActHarvest,
      subtitle: 'Peanut · 120 kg',
      timestamp: _daysAgo(1),
    ),
    ActivityItem(
      id: '${idPrefix}act-2',
      type: ActivityType.listing,
      title: l10n.guestSampleActListing,
      subtitle: 'Palay · 300 kg',
      timestamp: _daysAgo(3),
    ),
    ActivityItem(
      id: '${idPrefix}act-3',
      type: ActivityType.programEnrollment,
      title: l10n.guestSampleActProgram,
      subtitle: l10n.guestSampleProgramName,
      timestamp: _daysAgo(5),
    ),
    ActivityItem(
      id: '${idPrefix}act-4',
      type: ActivityType.loanRequested,
      title: l10n.guestSampleActLoan,
      subtitle: 'Peanut Seeds',
      timestamp: _daysAgo(8),
    ),
  ];

  // ── Harvest ───────────────────────────────────────────────────────────────

  static List<HarvestModel> get harvests => [
    HarvestModel(
      id: '${idPrefix}harvest-1',
      farmerId: '${idPrefix}farmer',
      cropId: '${idPrefix}crop-1',
      cropName: 'Peanut',
      cropCategory: 'Legume',
      quantityKg: 120,
      batchNumber: 'SAMPLE-0001',
      harvestDate: _daysAgo(1),
      isSynced: true,
      createdAt: _daysAgo(1),
    ),
    HarvestModel(
      id: '${idPrefix}harvest-2',
      farmerId: '${idPrefix}farmer',
      cropId: '${idPrefix}crop-2',
      cropName: 'Palay',
      cropCategory: 'Grain',
      quantityKg: 300,
      batchNumber: 'SAMPLE-0002',
      harvestDate: _daysAgo(8),
      isSynced: true,
      createdAt: _daysAgo(8),
    ),
    HarvestModel(
      id: '${idPrefix}harvest-3',
      farmerId: '${idPrefix}farmer',
      cropId: '${idPrefix}crop-3',
      cropName: 'Banana',
      cropCategory: 'Fruit',
      quantityKg: 85,
      batchNumber: 'SAMPLE-0003',
      harvestDate: _daysAgo(15),
      isSynced: true,
      createdAt: _daysAgo(15),
    ),
  ];

  static const Map<String, int> inventoryStats = {'total': 3, 'low_stock': 1};
  static const int seasonHarvestCount = 3;
  static const int cropCount = 3;

  // ── Listing ───────────────────────────────────────────────────────────────

  static List<MarketplaceListingModel> get listings => [
    MarketplaceListingModel(
      id: '${idPrefix}listing-1',
      farmerId: '${idPrefix}farmer',
      cropName: 'Peanut',
      pricePerKg: 60,
      volumeKg: 100,
      remainingKg: 60,
      status: 'approved',
      createdAt: _daysAgo(2),
    ),
    MarketplaceListingModel(
      id: '${idPrefix}listing-2',
      farmerId: '${idPrefix}farmer',
      cropName: 'Palay',
      pricePerKg: 20,
      volumeKg: 300,
      remainingKg: 300,
      status: 'pending_review',
      createdAt: _daysAgo(1),
    ),
    MarketplaceListingModel(
      id: '${idPrefix}listing-3',
      farmerId: '${idPrefix}farmer',
      cropName: 'Banana',
      pricePerKg: 25,
      volumeKg: 80,
      remainingKg: 0,
      status: 'sold',
      createdAt: _daysAgo(12),
    ),
  ];

  /// Cooperative Products (Product Sales programs) for the Marketplace pane. The
  /// database shows these to signed-in Farmers only, so a guest sees samples.
  static List<CooperativeProduct> cooperativeProducts(AppLocalizations l10n) =>
      [
        CooperativeProduct(
          productId: '${idPrefix}product-1',
          programId: '${idPrefix}program-1',
          programName: l10n.guestSampleProgramName,
          itemName: 'Peanut Seeds',
          category: 'Seeds',
          unit: 'kg',
          regularPrice: 90,
          memberDiscountPercent: 10,
          availableToSell: 200,
          buyers: 5,
          soldQuantity: 120,
        ),
        CooperativeProduct(
          productId: '${idPrefix}product-2',
          programId: '${idPrefix}program-1',
          programName: l10n.guestSampleProgramName,
          itemName: 'Organic Fertilizer',
          category: 'Fertilizer',
          unit: 'sack',
          regularPrice: 850,
          availableToSell: 40,
        ),
      ];

  // ── Analytics ─────────────────────────────────────────────────────────────

  /// A longer period shows a proportionally bigger sample, so switching the
  /// period selector visibly does something.
  static double _scale(AnalyticsPeriod p) {
    switch (p) {
      case AnalyticsPeriod.thisMonth:
        return 1;
      case AnalyticsPeriod.thisQuarter:
        return 3;
      case AnalyticsPeriod.thisYear:
        return 8;
      case AnalyticsPeriod.allTime:
        return 12;
    }
  }

  static FarmPerformanceSummary performance(AnalyticsPeriod p) {
    final s = _scale(p);
    return FarmPerformanceSummary(
      totalYieldKg: 505 * s,
      totalRevenue: 18500 * s,
      totalExpenses: 6200 * s,
      cropBreakdown: [
        CropYieldBreakdown(
          cropName: 'Palay',
          quantityKg: 300 * s,
          percentOfMax: 1,
        ),
        CropYieldBreakdown(
          cropName: 'Peanut',
          quantityKg: 120 * s,
          percentOfMax: 0.4,
        ),
        CropYieldBreakdown(
          cropName: 'Banana',
          quantityKg: 85 * s,
          percentOfMax: 0.28,
        ),
      ],
    );
  }

  static List<TransactionRecord> get transactions => [
    TransactionRecord(
      id: '${idPrefix}txn-1',
      cropName: 'Peanut',
      quantityKg: 40,
      totalAmount: 2400,
      date: _daysAgo(2),
      reference: 'SAMPLE-T1',
      source: TransactionSource.marketplace,
    ),
    TransactionRecord(
      id: '${idPrefix}txn-2',
      cropName: 'Palay',
      quantityKg: 150,
      totalAmount: 3000,
      date: _daysAgo(9),
      reference: 'SAMPLE-T2',
      source: TransactionSource.cooperative,
    ),
  ];

  static List<CropPriceCard> get priceCards {
    final type = MarketTypes.instance.defaultCode ?? '';
    return [
      CropPriceCard(
        cropName: 'Peanut',
        priceType: type,
        currentPrice: 60,
        previousPrice: 55,
        recordedAt: _daysAgo(1),
      ),
      CropPriceCard(
        cropName: 'Palay',
        priceType: type,
        currentPrice: 20,
        previousPrice: 20,
        recordedAt: _daysAgo(1),
      ),
    ];
  }

  static List<PriceHistoryPoint> priceHistory(CropPriceCard card) {
    final base = card.currentPrice;
    return [
      for (var i = 6; i >= 0; i--)
        PriceHistoryPoint(
          date: _daysAgo(i * 4),
          price: base + ((i % 3) - 1) * (base * 0.04),
        ),
    ];
  }

  static const List<PlantingForecast> forecasts = [
    PlantingForecast(
      cropName: 'Peanut',
      category: 'Legume',
      mostRecentCycleKg: 480,
      forecastNextCycleKg: 520,
      trend: 'trending_up',
      cyclesAvailable: 3,
    ),
    PlantingForecast(
      cropName: 'Palay',
      category: 'Grain',
      mostRecentCycleKg: 900,
      forecastNextCycleKg: 900,
      trend: 'stable',
      cyclesAvailable: 3,
    ),
  ];

  static const List<TopSellingCrop> topCrops = [
    TopSellingCrop(cropName: 'Palay', volumeKg: 900, percentOfMax: 1),
    TopSellingCrop(cropName: 'Peanut', volumeKg: 480, percentOfMax: 0.53),
    TopSellingCrop(cropName: 'Banana', volumeKg: 250, percentOfMax: 0.28),
  ];
}
