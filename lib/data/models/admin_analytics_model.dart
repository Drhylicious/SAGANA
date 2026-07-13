import 'admin_loan_model.dart' show FarmerPickerResult;

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