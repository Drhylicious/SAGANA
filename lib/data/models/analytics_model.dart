// ─── Period Filter ────────────────────────────────────────────────────────────
//
// Note on "season": AnalyticsPeriod.thisSeason is a 90-day rolling window
// (see startDate below), independent of calendar boundaries. This is a
// different definition from HarvestRepository's own "season" stat
// (fetchStats()), which counts calendar-year-to-date despite its internal
// variable being named startOfSeason. Both are intentionally correct for
// what each screen shows — this isn't a bug — but a farmer could see two
// different "season" totals on two different screens. Flagging here so
// the collision is documented rather than silently repeated if either
// definition is touched again.

enum AnalyticsPeriod { thisMonth, thisSeason, thisYear, allTime }

extension AnalyticsPeriodExt on AnalyticsPeriod {
  String get label {
    switch (this) {
      case AnalyticsPeriod.thisMonth: return 'This Month';
      case AnalyticsPeriod.thisSeason: return 'This Season';
      case AnalyticsPeriod.thisYear: return 'This Year';
      case AnalyticsPeriod.allTime: return 'All Time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case AnalyticsPeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case AnalyticsPeriod.thisSeason:
        return now.subtract(const Duration(days: 90));
      case AnalyticsPeriod.thisYear:
        return DateTime(now.year, 1, 1);
      case AnalyticsPeriod.allTime:
        return null;
    }
  }
}

// ─── Farm Performance Summary ─────────────────────────────────────────────────

class FarmPerformanceSummary {
  final double totalYieldKg;
  final double totalRevenue;
  final double totalExpenses;
  final List<CropYieldBreakdown> cropBreakdown;

  const FarmPerformanceSummary({
    required this.totalYieldKg,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.cropBreakdown,
  });

  double get netProfit => totalRevenue - totalExpenses;

  static const empty = FarmPerformanceSummary(
    totalYieldKg: 0, totalRevenue: 0, totalExpenses: 0, cropBreakdown: [],
  );
}

class CropYieldBreakdown {
  final String cropName;
  final double quantityKg;
  final double percentOfMax;

  const CropYieldBreakdown({
    required this.cropName,
    required this.quantityKg,
    required this.percentOfMax,
  });
}

// ─── Transaction (sold inventory) ─────────────────────────────────────────────

class TransactionRecord {
  final String id;
  final String cropName;
  final double quantityKg;
  final double totalAmount;
  final DateTime date;
  final String reference;

  const TransactionRecord({
    required this.id,
    required this.cropName,
    required this.quantityKg,
    required this.totalAmount,
    required this.date,
    required this.reference,
  });
}

// ─── Price Card (with margin) ─────────────────────────────────────────────────

class CropPriceCard {
  final String cropName;
  final String priceType; // 'sp3_cooperative' | 'open_market'
  final double currentPrice;
  final double? previousPrice;
  final double? costPerKg;

  const CropPriceCard({
    required this.cropName,
    required this.priceType,
    required this.currentPrice,
    this.previousPrice,
    this.costPerKg,
  });

  bool get isUp => previousPrice != null && currentPrice > previousPrice!;
  bool get isDown => previousPrice != null && currentPrice < previousPrice!;
  double? get priceDiff => previousPrice != null ? currentPrice - previousPrice! : null;

  double? get marginPerKg => costPerKg != null ? currentPrice - costPerKg! : null;
  bool get hasPositiveMargin => (marginPerKg ?? 0) >= 0;
}

// ─── Price History Point (for trend chart) ────────────────────────────────────

class PriceHistoryPoint {
  final DateTime date;
  final double price;
  const PriceHistoryPoint({required this.date, required this.price});
}

// ─── Planting Forecast ─────────────────────────────────────────────────────────

class PlantingForecast {
  final String cropName;
  final String category;
  final double mostRecentCycleKg;
  final double? forecastNextCycleKg;
  final String trend; // 'trending_up' | 'stable' | 'trending_down' | 'insufficient_data'
  final int cyclesAvailable;

  const PlantingForecast({
    required this.cropName,
    required this.category,
    required this.mostRecentCycleKg,
    required this.forecastNextCycleKg,
    required this.trend,
    required this.cyclesAvailable,
  });

  bool get hasForecast => forecastNextCycleKg != null && trend != 'insufficient_data';

  String get trendLabel {
    switch (trend) {
      case 'trending_up': return 'Trending Up';
      case 'trending_down': return 'Trending Down';
      case 'stable': return 'Stable';
      default: return 'Not Enough Data';
    }
  }

  String get explanation {
    if (!hasForecast) {
      return 'Not enough harvest history yet to forecast this crop. Needs at least 2 full harvest cycles cooperative-wide.';
    }
    final diff = forecastNextCycleKg! - mostRecentCycleKg;
    final diffAbs = diff.abs().toStringAsFixed(0);
    switch (trend) {
      case 'trending_up':
        return 'Projected to increase by ~$diffAbs kg next cycle based on recent harvest trends.';
      case 'trending_down':
        return 'Projected to decrease by ~$diffAbs kg next cycle based on recent harvest trends.';
      default:
        return 'Volume is expected to remain steady next cycle.';
    }
  }

  factory PlantingForecast.fromMap(Map<String, dynamic> map) {
    return PlantingForecast(
      cropName: map['crop_name'] as String,
      category: map['category'] as String? ?? 'Other',
      mostRecentCycleKg: (map['most_recent_cycle_kg'] as num? ?? 0).toDouble(),
      forecastNextCycleKg: map['forecast_next_cycle_kg'] != null
          ? (map['forecast_next_cycle_kg'] as num).toDouble()
          : null,
      trend: map['trend'] as String? ?? 'insufficient_data',
      cyclesAvailable: map['cycles_available'] as int? ?? 0,
    );
  }
}

// ─── Top Selling Crop (coop-wide bar chart) ────────────────────────────────────

class TopSellingCrop {
  final String cropName;
  final double volumeKg;
  final double percentOfMax;

  const TopSellingCrop({
    required this.cropName,
    required this.volumeKg,
    required this.percentOfMax,
  });
}