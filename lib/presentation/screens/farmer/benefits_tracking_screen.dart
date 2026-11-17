import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../../data/models/admin_reports_model.dart' show MemberMonthStatus;
import '../../../data/repositories/benefits_tracking_repository.dart';
import '../../../data/repositories/capital_contribution_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/capital_share_credit_widgets.dart';
import '../../widgets/member_contribution_breakdown.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';

/// Member Contribution Report (Farmer). Read-only: one year at a time. It tracks
/// the Farmer's CAPITAL SHARE, worked out the same way as the Manager's report:
/// the Capital Share, and what the three sources added to it that year:
///
///  1. Monthly Contributions: the payments received.
///  2. Cooperative Product Purchases: the member-price discount added to the
///     Capital Share (the purchase itself is for reference).
///  3. Successful Offers to the Cooperative: nothing is added to the Capital Share
///     for them today (the sale value is for reference).
///
/// There is nothing to submit here: no payout or refund exists.
class BenefitsTrackingScreen extends StatefulWidget {
  const BenefitsTrackingScreen({super.key});

  @override
  State<BenefitsTrackingScreen> createState() => _BenefitsTrackingScreenState();
}

class _BenefitsTrackingScreenState extends State<BenefitsTrackingScreen> {
  static const _monthlyColor = AppConstants.amber;
  static const _purchasesColor = AppConstants.buyerBlue;
  static const _offersColor = AppConstants.primaryGreen;

  static final _money = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  final _repo = BenefitsTrackingRepository();
  final _capitalRepo = CapitalContributionRepository();
  StreamSubscription<bool>? _connectivitySub;

  List<int> _years = [DateTime.now().year];
  int _year = DateTime.now().year;
  BenefitsYear? _data;
  MemberCapitalSummary? _capital;

  bool _isLoading = true;
  bool _isOnline = true;
  // Guards against an older year's answer arriving after a newer one.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((v) {
          if (mounted) setState(() => _isOnline = v);
        });
    _loadAll();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> _loadAll() async {
    final id = ++_requestId;
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchYears(),
      _repo.fetchYear(_year),
      _capitalRepo.fetchCapitalSummary(_userId),
    ]);
    if (!mounted || id != _requestId) return;
    setState(() {
      _years = results[0] as List<int>;
      _data = results[1] as BenefitsYear;
      _capital = results[2] as MemberCapitalSummary;
      _isLoading = false;
    });
  }

  Future<void> _selectYear(int year) async {
    final id = ++_requestId;
    setState(() {
      _year = year;
      _isLoading = true;
    });
    final data = await _repo.fetchYear(year);
    if (!mounted || id != _requestId) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final data = _data;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'member_capital_shares',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineContribution,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _loadAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      YearNavigator(
                        selectedYear: _year,
                        years: _years,
                        onChanged: _selectYear,
                      ),
                      const SizedBox(height: AppConstants.spacingMd),
                      if (_isLoading || data == null) ...[
                        const SkeletonBlock(height: 200),
                        const SizedBox(height: AppConstants.spacingMd),
                        const SkeletonBlock(height: 180),
                        const SizedBox(height: AppConstants.spacingMd),
                        const SkeletonBlock(height: 180),
                      ] else ...[
                        _buildTotalCard(l10n, cs, data),
                        const SizedBox(height: AppConstants.spacingMd),
                        _buildMonthlyCard(l10n, cs, data),
                        const SizedBox(height: AppConstants.spacingMd),
                        _buildPurchasesCard(l10n, cs, data),
                        const SizedBox(height: AppConstants.spacingMd),
                        _buildOffersCard(l10n, cs, data),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.benefitsTrackingTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  // ─── The three sources together ───────────────────────────────────────────

  Widget _buildTotalCard(AppLocalizations l10n, ColorScheme cs, BenefitsYear d) {
    // Total Capital Share = Monthly Contribution + Cooperative Purchase + Offer to
    // Cooperative, so the three bars add up to what was added in the year.
    final added = d.capitalAddedInYear;
    double fraction(double v) => added > 0 ? (v / added).clamp(0.0, 1.0) : 0;
    String share(double v) =>
        l10n.rptShareOfTotal((fraction(v) * 100).toStringAsFixed(0));
    final balance = d.year == DateTime.now().year && _capital != null
        ? _capital!.shares.totalContribution
        : d.capitalAtYearEnd;
    final shares = _capital?.shares;
    final shareCount = d.year == DateTime.now().year && shares != null
        ? shares.totalShares
        : (shares == null || shares.shareValuePerUnit <= 0
              ? 0
              : (d.capitalAtYearEnd / shares.shareValuePerUnit).floor());
    final shareValue = shares?.shareValuePerUnit ?? 2000;
    final remaining = ((shareCount + 1) * shareValue - balance)
        .clamp(0.0, double.infinity)
        .toDouble();

    return ReportSectionCard(
      title: l10n.patTitleContributions(d.year),
      icon: Icons.paid_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.patTotalContributions,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          Text(
            _money.format(balance),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 24,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.patSharesSummary(
              shareCount,
              _money.format(remaining),
              MemberContributionBreakdown.pesoShort(shareValue),
            ),
            style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            l10n.patContributionsInYear(d.year),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          ReportBarRow(
            label: l10n.patSourceMonthly,
            valueText: _money.format(d.memberPaidInYear),
            fraction: fraction(d.memberPaidInYear),
            color: _monthlyColor,
            leading: const Icon(Icons.calendar_month_rounded, size: 15, color: _monthlyColor),
            caption: share(d.memberPaidInYear),
          ),
          ReportBarRow(
            label: l10n.patSourcePurchases,
            valueText: _money.format(d.purchaseCredited),
            fraction: fraction(d.purchaseCredited),
            color: _purchasesColor,
            leading: const Icon(Icons.shopping_bag_rounded, size: 15, color: _purchasesColor),
            caption: share(d.purchaseCredited),
          ),
          ReportBarRow(
            label: l10n.patSourceOffers,
            valueText: _money.format(d.offersCredited),
            fraction: fraction(d.offersCredited),
            color: _offersColor,
            leading: const Icon(Icons.handshake_rounded, size: 15, color: _offersColor),
            caption: share(d.offersCredited),
          ),
        ],
      ),
    );
  }

  // ─── 1. Monthly Contribution ──────────────────────────────────────────────

  Widget _buildMonthlyCard(AppLocalizations l10n, ColorScheme cs, BenefitsYear d) {
    return ReportSectionCard(
      title: l10n.patSourceMonthly,
      icon: Icons.calendar_month_rounded,
      accent: _monthlyColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // What the member paid in this year: this is what was added to the Capital Share.
          _bigAmount(l10n.patSourceMonthly, _money.format(d.memberPaidInYear), cs),
          const SizedBox(height: AppConstants.spacingMd),
          // Every contribution record as its own entry (date, status, amount), newest
          // first, and the months still owed.
          ContributionEntryList(
            records: d.records,
            months: [
              for (final m in d.months)
                MemberMonthStatus(
                  month: m.month,
                  amountDue: m.amountDue,
                  paid: m.paidAmount,
                  status: m.status.name,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 2. Cooperative Purchase ──────────────────────────────────────────────

  Widget _buildPurchasesCard(AppLocalizations l10n, ColorScheme cs, BenefitsYear d) {
    return ReportSectionCard(
      title: l10n.patSourcePurchases,
      icon: Icons.shopping_bag_rounded,
      accent: _purchasesColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bigAmount(l10n.patCreditedToCapital, _money.format(d.purchaseCredited), cs),
          const SizedBox(height: AppConstants.spacingMd),
          CreditGroupsView(
            isPurchase: true,
            farmerId: Supabase.instance.client.auth.currentUser!.id,
            made: d.purchasesNet,
            discountEarned: d.discountEarned,
            credited: d.purchaseCredited,
            creditedBase: d.purchaseShareBase,
            byVersion: d.purchaseByVersion,
            latestVersion: d.latestRateVersion,
            rateChanges: d.rateChanges,
            creditVersions: d.creditVersions,
            loadItems: () async => [for (final p in d.purchases) creditItemFromPurchase(p, l10n)],
          ),
          if (d.purchases.isEmpty) _emptyText(l10n.benefitsNoPurchases(d.year), cs),
          _viewAllLink(l10n.benefitsViewOrders, AppRoutes.farmerMyOrders, cs),
        ],
      ),
    );
  }

  // ─── 3. Offer to Cooperative ──────────────────────────────────────────────

  Widget _buildOffersCard(AppLocalizations l10n, ColorScheme cs, BenefitsYear d) {
    return ReportSectionCard(
      title: l10n.patSourceOffers,
      icon: Icons.handshake_rounded,
      accent: _offersColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bigAmount(l10n.patCreditedToCapital, _money.format(d.offersCredited), cs),
          const SizedBox(height: AppConstants.spacingMd),
          CreditGroupsView(
            isPurchase: false,
            farmerId: Supabase.instance.client.auth.currentUser!.id,
            made: d.offersAmount,
            discountEarned: 0,
            credited: d.offersCredited,
            creditedBase: d.offerShareBase,
            byVersion: d.offerByVersion,
            latestVersion: d.latestRateVersion,
            rateChanges: d.rateChanges,
            creditVersions: d.creditVersions,
            loadItems: () async => [for (final o in d.offers) creditItemFromOffer(o)],
          ),
          if (d.offers.isEmpty) _emptyText(l10n.benefitsNoOffers(d.year), cs),
          _viewAllLink(
            l10n.benefitsViewAllCoopOffers,
            AppRoutes.farmerCoopOffers,
            cs,
          ),
        ],
      ),
    );
  }

  /// A centred "View …" link that opens the Farmer's own full list.
  Widget _viewAllLink(String label, String route, ColorScheme cs) => Center(
    child: TextButton(
      onPressed: () => context.pushRoute(route),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary),
        ],
      ),
    ),
  );

  // ─── Small pieces ─────────────────────────────────────────────────────────

  /// The label on the left and its amount on the right, on the SAME row.
  Widget _bigAmount(String label, String value, ColorScheme cs) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: cs.onSurface,
        ),
      ),
    ],
  );

  Widget _emptyText(String text, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
    ),
  );
}
