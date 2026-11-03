import '../models/analytics_model.dart';
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
      rate('rate-1', 'Tomato', 'Vegetable', 45, 40),
      rate('rate-2', 'Corn', 'Grain', 22, 24),
      rate('rate-3', 'Eggplant', 'Vegetable', 38, 38),
    ];
  }

  static List<ActivityItem> get activity => [
    ActivityItem(
      id: '${idPrefix}act-1',
      type: ActivityType.harvest,
      title: 'Sample harvest recorded',
      subtitle: 'Tomato · 120 kg',
      timestamp: _daysAgo(1),
    ),
    ActivityItem(
      id: '${idPrefix}act-2',
      type: ActivityType.listing,
      title: 'Sample listing approved',
      subtitle: 'Corn · 300 kg',
      timestamp: _daysAgo(3),
    ),
    ActivityItem(
      id: '${idPrefix}act-3',
      type: ActivityType.profile,
      title: 'Sample profile update',
      subtitle: 'Contact details',
      timestamp: _daysAgo(6),
    ),
  ];

  // ── Harvest ───────────────────────────────────────────────────────────────

  static List<HarvestModel> get harvests => [
    HarvestModel(
      id: '${idPrefix}harvest-1',
      farmerId: '${idPrefix}farmer',
      cropId: '${idPrefix}crop-1',
      cropName: 'Tomato',
      cropCategory: 'Vegetable',
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
      cropName: 'Corn',
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
      cropName: 'Eggplant',
      cropCategory: 'Vegetable',
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
      cropName: 'Tomato',
      pricePerKg: 45,
      volumeKg: 100,
      remainingKg: 60,
      status: 'approved',
      description: 'Sample listing',
      createdAt: _daysAgo(2),
    ),
    MarketplaceListingModel(
      id: '${idPrefix}listing-2',
      farmerId: '${idPrefix}farmer',
      cropName: 'Corn',
      pricePerKg: 22,
      volumeKg: 300,
      remainingKg: 300,
      status: 'pending_review',
      description: 'Sample listing',
      createdAt: _daysAgo(1),
    ),
    MarketplaceListingModel(
      id: '${idPrefix}listing-3',
      farmerId: '${idPrefix}farmer',
      cropName: 'Eggplant',
      pricePerKg: 38,
      volumeKg: 80,
      remainingKg: 0,
      status: 'sold',
      description: 'Sample listing',
      createdAt: _daysAgo(12),
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
        CropYieldBreakdown(cropName: 'Corn', quantityKg: 300 * s, percentOfMax: 1),
        CropYieldBreakdown(
          cropName: 'Tomato',
          quantityKg: 120 * s,
          percentOfMax: 0.4,
        ),
        CropYieldBreakdown(
          cropName: 'Eggplant',
          quantityKg: 85 * s,
          percentOfMax: 0.28,
        ),
      ],
    );
  }

  static List<TransactionRecord> get transactions => [
    TransactionRecord(
      id: '${idPrefix}txn-1',
      cropName: 'Tomato',
      quantityKg: 40,
      totalAmount: 1800,
      date: _daysAgo(2),
      reference: 'SAMPLE-T1',
      source: TransactionSource.marketplace,
    ),
    TransactionRecord(
      id: '${idPrefix}txn-2',
      cropName: 'Corn',
      quantityKg: 150,
      totalAmount: 3300,
      date: _daysAgo(9),
      reference: 'SAMPLE-T2',
      source: TransactionSource.cooperative,
    ),
  ];

  static List<CropPriceCard> get priceCards {
    final type = MarketTypes.instance.defaultCode ?? '';
    return [
      CropPriceCard(
        cropName: 'Tomato',
        priceType: type,
        currentPrice: 45,
        previousPrice: 40,
        recordedAt: _daysAgo(1),
      ),
      CropPriceCard(
        cropName: 'Corn',
        priceType: type,
        currentPrice: 22,
        previousPrice: 24,
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
      cropName: 'Tomato',
      category: 'Vegetable',
      mostRecentCycleKg: 480,
      forecastNextCycleKg: 520,
      trend: 'trending_up',
      cyclesAvailable: 3,
    ),
    PlantingForecast(
      cropName: 'Corn',
      category: 'Grain',
      mostRecentCycleKg: 900,
      forecastNextCycleKg: 900,
      trend: 'stable',
      cyclesAvailable: 3,
    ),
  ];

  static const List<TopSellingCrop> topCrops = [
    TopSellingCrop(cropName: 'Corn', volumeKg: 900, percentOfMax: 1),
    TopSellingCrop(cropName: 'Tomato', volumeKg: 480, percentOfMax: 0.53),
    TopSellingCrop(cropName: 'Eggplant', volumeKg: 250, percentOfMax: 0.28),
  ];
}
