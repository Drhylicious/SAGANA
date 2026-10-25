import 'admin_loan_model.dart' show FarmerPickerResult;

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