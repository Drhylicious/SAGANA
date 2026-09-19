import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contribution_model.dart';

/// Admin-side capital-share contribution management (Issue 4d).
///
/// The ₱100/month dues are a payment schedule toward the ₱2,000 annual
/// capital share (Decision D1a) — the Admin records each actual payment
/// here (Decision D1c); there is no date-based auto-accrual. Every write
/// goes through capital_contribution_events; member_capital_shares
/// (total_contribution / total_shares) is kept in sync by DB trigger.
///
/// Write methods throw (they change money-adjacent state); reads swallow
/// and return safe empties, matching the rest of the codebase.
class CapitalContributionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Records one capital contribution for [farmerId].
  ///
  /// [source] is one of: `member_payment` (a ₱100+ payment toward the
  /// annual share), `patronage_capital` (member left their Balik-
  /// Tangkilik refund in the coop), `manual_adjustment` (correction — may
  /// be negative), `opening_balance`.
  Future<void> recordContribution({
    required String farmerId,
    required double amount,
    String source = 'member_payment',
    String? note,
  }) async {
    await _client.from('capital_contribution_events').insert({
      'farmer_id': farmerId,
      'amount': amount,
      'source': source,
      'note': (note != null && note.trim().isNotEmpty) ? note.trim() : null,
      'recorded_by': _client.auth.currentUser?.id,
    });
  }

  /// Ledger for one member, newest first.
  Future<List<CapitalContributionEvent>> fetchLedger(
    String farmerId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from('capital_contribution_events')
          .select()
          .eq('farmer_id', farmerId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .map((r) => CapitalContributionEvent.fromMap(r))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Current capital position for one member + the policy thresholds the
  /// Members-tab record needs to render its progress + warning UI.
  Future<MemberCapitalSummary> fetchCapitalSummary(String farmerId) async {
    try {
      final shareRow = await _client
          .from('member_capital_shares')
          .select('farmer_id, total_shares, share_value_per_unit, total_contribution')
          .eq('farmer_id', farmerId)
          .maybeSingle();

      final policyRow = await _client
          .from('loan_policy_settings')
          .select('minimum_capital_contribution, monthly_dues_amount, annual_capital_share_target')
          .eq('id', 1)
          .maybeSingle();

      final shares = shareRow != null
          ? CapitalSharesModel.fromMap(shareRow)
          : CapitalSharesModel(
              farmerId: farmerId,
              totalShares: 0,
              shareValuePerUnit: 2000,
            );

      return MemberCapitalSummary(
        shares: shares,
        minimumForLoan:
            (policyRow?['minimum_capital_contribution'] as num? ?? 2000).toDouble(),
        monthlyDues:
            (policyRow?['monthly_dues_amount'] as num? ?? 100).toDouble(),
        annualShareTarget:
            (policyRow?['annual_capital_share_target'] as num? ?? 2000).toDouble(),
      );
    } catch (_) {
      return MemberCapitalSummary(
        shares: CapitalSharesModel(
          farmerId: farmerId,
          totalShares: 0,
          shareValuePerUnit: 2000,
        ),
        minimumForLoan: 2000,
        monthlyDues: 100,
        annualShareTarget: 2000,
      );
    }
  }
}

class MemberCapitalSummary {
  final CapitalSharesModel shares;
  final double minimumForLoan;
  final double monthlyDues;
  final double annualShareTarget;

  const MemberCapitalSummary({
    required this.shares,
    required this.minimumForLoan,
    required this.monthlyDues,
    required this.annualShareTarget,
  });

  bool get meetsLoanEligibility =>
      shares.totalContribution >= minimumForLoan;

  double get loanShortfall =>
      (minimumForLoan - shares.totalContribution)
          .clamp(0, double.infinity)
          .toDouble();

  /// 0..1 progress toward the farmer's NEXT ₱2,000 capital share.
  ///
  /// Despite [annualShareTarget]'s name (it mirrors the DB column
  /// `annual_capital_share_target`, describing the recommended pace of one
  /// new share roughly per year), total_contribution is a LIFETIME-
  /// cumulative running total with no calendar-year reset anywhere in the
  /// schema (confirmed during the Admin-Report tab review, Phase 11) — a
  /// member's capital keeps growing forever across years, consistent with
  /// them being a permanent shareholder, not something that lapses or
  /// restarts each January. This progress is always "toward the next
  /// share," never "toward this calendar year's share."
  double get shareProgress {
    if (annualShareTarget <= 0) return 0;
    final withinShare = shares.totalContribution % annualShareTarget;
    // A member who has completed one or more whole shares still shows
    // partial progress toward the next one.
    return (withinShare / annualShareTarget).clamp(0.0, 1.0);
  }
}
