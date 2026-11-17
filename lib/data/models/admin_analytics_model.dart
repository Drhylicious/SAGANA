import 'admin_loan_model.dart' show FarmerPickerResult;
import 'analytics_model.dart'
    show CropPriceCard, PlantingForecast, TopSellingCrop;

/// Splits the active members into the three participation tiers. Only people
/// in [memberIds] are counted, so a former member who still has old harvest or
/// listing rows cannot push the tiers past the member total. A member who both
/// harvested and listed counts under harvested only.
({Set<String> harvested, Set<String> listedOnly, List<String> inactive})
classifyParticipation({
  required List<String> memberIds,
  required Set<String> harvestedIds,
  required Set<String> listedIds,
}) {
  final members = memberIds.toSet();
  final harvested = harvestedIds.intersection(members);
  final listedOnly = listedIds.intersection(members).difference(harvested);
  final inactive = memberIds
      .where((id) => !harvested.contains(id) && !listedOnly.contains(id))
      .toList();
  return (harvested: harvested, listedOnly: listedOnly, inactive: inactive);
}

/// Tiered breakdown of farmer activity for Analytics Dashboard's Member
/// Participation section. A farmer who both harvested and listed counts
/// under "harvested" only, to avoid double-counting — harvesting is the
/// more fundamental activity of the two.
class MemberParticipationSummary {
  final int activeHarvestedCount;
  final int activeListedCount;
  final int inactiveCount;
  final int totalMembers;
  final List<FarmerPickerResult> inactiveFarmers;

  const MemberParticipationSummary({
    required this.activeHarvestedCount,
    required this.activeListedCount,
    required this.inactiveCount,
    required this.totalMembers,
    required this.inactiveFarmers,
  });

  factory MemberParticipationSummary.empty() => const MemberParticipationSummary(
        activeHarvestedCount: 0,
        activeListedCount: 0,
        inactiveCount: 0,
        totalMembers: 0,
        inactiveFarmers: [],
      );
}

/// Everything the Analytics Dashboard shows, gathered for CSV and PDF export.
/// Member Participation covers the chosen period; the price snapshot, top
/// harvested crops and planting forecast are current, as on the screen.
class AnalyticsExportData {
  final MemberParticipationSummary participation;
  final List<TopSellingCrop> topCrops;
  final List<CropPriceCard> priceCards;

  /// Market type name for each [CropPriceCard.priceType] code.
  final Map<String, String> marketTypeNames;
  final List<PlantingForecast> forecasts;

  const AnalyticsExportData({
    required this.participation,
    required this.topCrops,
    required this.priceCards,
    required this.marketTypeNames,
    required this.forecasts,
  });

  int get participatedCount =>
      participation.activeHarvestedCount + participation.activeListedCount;

  double get participationRatePercent => participation.totalMembers > 0
      ? participatedCount / participation.totalMembers * 100
      : 0;

  String marketTypeName(String code) => marketTypeNames[code] ?? code;
}
