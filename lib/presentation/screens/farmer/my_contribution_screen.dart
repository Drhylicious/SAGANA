import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/quantity_utils.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/capital_contribution_repository.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/repositories/member_sales_aggregation.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../core/l10n/app_localizations.dart';

/// Rejects any edit that would leave more than 2 digits after the decimal
/// point — checked against the WHOLE resulting string, not per-character
/// (a per-character `FilteringTextInputFormatter.allow` pattern can't
/// express "at most 2 decimal digits," since every individual keystroke
/// trivially satisfies a `\d{0,2}` quantifier on its own).
class _MaxTwoDecimalsFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d*\.?\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || _pattern.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

class MyContributionScreen extends StatefulWidget {
  const MyContributionScreen({super.key});

  @override
  State<MyContributionScreen> createState() => _MyContributionScreenState();
}

class _MyContributionScreenState extends State<MyContributionScreen> {
  final _repo = ContributionRepository();
  final _capitalRepo = CapitalContributionRepository();
  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  MemberContribution? _current;
  MemberContribution? _previous;
  List<MemberSalesTransaction> _transactions = [];
  List<ProgramPurchase> _purchases = [];
  ProgramPurchaseBreakdown? _purchaseBreakdown;
  CapitalSharesModel? _shares;
  double _sellingSharePercent = 0;
  double _buyingSharePercent = 0;
  MemberCapitalSummary? _capitalSummary;

  bool _isLoading = true;
  bool _isOnline = true;

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
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final year = DateTime.now().year;
    final userId = _userId;
    final results = await Future.wait([
      _repo.fetchCurrentYearContribution(),
      _repo.fetchPreviousYearContribution(),
      _repo.fetchRecentTransactions(),
      _repo.fetchRecentProgramPurchases(),
      _repo.fetchCapitalShares(),
      _repo.fetchMyActivityShare(year),
      _capitalRepo.fetchCapitalSummary(userId),
      // This farmer's own member-price purchases (the database only returns
      // their own): regular price, discount and net paid.
      fetchMemberProgramPurchaseBreakdown(Supabase.instance.client, year),
    ]);
    if (!mounted) return;
    setState(() {
      _current = results[0] as MemberContribution?;
      _previous = results[1] as MemberContribution?;
      _transactions = results[2] as List<MemberSalesTransaction>;
      _purchases = results[3] as List<ProgramPurchase>;
      _purchaseBreakdown =
          (results[7] as Map<String, ProgramPurchaseBreakdown>)[userId];
      _shares = results[4] as CapitalSharesModel?;
      final share = results[5] as ({double selling, double buying});
      _sellingSharePercent = share.selling;
      _buyingSharePercent = share.buying;
      _capitalSummary = results[6] as MemberCapitalSummary;
      _isLoading = false;
    });
  }

  /// Prompts for an amount (up to what's available), then submits it as a
  /// PENDING payout decision via request_payout_decision() — this no
  /// longer moves any money immediately. The capital transfer only
  /// happens once an admin confirms it (Balik-Tangkilik Management's
  /// History review), closing the risk of the same payout being claimed
  /// as both cash and capital. Works for whichever year is actually
  /// finalized (this year or last year), not hardcoded to "last year."
  Future<void> _requestAddToCapital(
    MemberContribution contribution,
    int year,
  ) async {
    if (contribution.hasAnyPayoutDecision) return;
    final available = contribution.availableToReinvest;
    if (available <= 0) return;

    final controller = TextEditingController(
      text: available.toStringAsFixed(2),
    );
    // A tiny epsilon, NOT cent-rounding — rounding the entered amount to
    // the nearest cent before comparing was the actual bug in the first
    // attempt at this fix: 1400.002222 rounds DOWN to 1400.00 at the
    // nearest-cent step, which then compared as exactly equal to the
    // ₱1,400.00 limit and silently passed. The epsilon here only absorbs
    // genuine binary floating-point representation noise (values differing
    // by fractions of a centavo due to double precision), not real excess
    // amounts like this one, which must still be rejected.
    const epsilon = 0.000001;
    String? error;

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Live-validated on every keystroke, not just on submit — the
          // field previously accepted typing any amount with no feedback
          // until "Submit Request" was pressed, which read as if the
          // limit wasn't enforced at all even though submission itself
          // was already correctly blocked.
          double? entered = double.tryParse(controller.text.trim());
          if (entered == null || entered <= 0) {
            error = AppLocalizations.of(context).enhEnterAValidAmount;
          } else if (entered - available > epsilon) {
            error = AppLocalizations.of(context).enhCannotExceed(
              (NumberFormat('#,##0.00').format(available)).toString(),
            );
          } else {
            error = null;
          }
          final isValid = error == null;

          return AlertDialog(
            title: Text(
              AppLocalizations.of(context).enhAddToCapitalShare,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(
                    context,
                  ).enhRequestToMovePartOrAllOfYour((year).toString()),
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).enhAvailable360(
                    (NumberFormat('#,##0.00').format(available)).toString(),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    _MaxTwoDecimalsFormatter(),
                  ],
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    ).farmerDetailsAmountLabel,
                    prefixText: '₱ ',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              TextButton(
                onPressed: isValid
                    ? () => Navigator.of(dialogContext).pop(entered)
                    : null,
                child: Text(AppLocalizations.of(context).enhSubmitRequest),
              ),
            ],
          );
        },
      ),
    );
    if (amount == null) return;

    try {
      await _repo.requestPayoutDecision(
        year: year,
        decision: 'capital',
        amount: amount,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        AppLocalizations.of(context).enhRequestToAddToYourCapitalShareWas(
          (NumberFormat('#,##0.00').format(amount)).toString(),
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppLocalizations.of(context).enhCouldNotSubmitRequest((e).toString()),
        isError: true,
      );
    }
  }

  /// "Keep as Cash" now goes through the same request-then-admin-confirms
  /// path as "Add to Capital" — previously this only showed an
  /// acknowledgment message with no record of any kind, which meant
  /// nothing stopped a farmer from also using "Add to Capital" for the
  /// same money later (a genuine double-processing risk, since nothing
  /// tracked that cash had already been claimed). Submitting this locks
  /// out "Add to Capital" for this year immediately, even before admin
  /// confirms it.
  Future<void> _requestKeepAsCash(
    MemberContribution contribution,
    int year,
  ) async {
    if (contribution.hasAnyPayoutDecision) return;
    final available = contribution.availableToReinvest;
    if (available <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).enhKeepAsCash363,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          AppLocalizations.of(context).enhRequestToReceiveYourPayoutOfAsCash(
            (year).toString(),
            (NumberFormat('#,##0.00').format(available)).toString(),
          ),
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context).enhSubmitRequest),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repo.requestPayoutDecision(year: year, decision: 'cash');
      if (!mounted) return;
      AppToast.show(
        context,
        AppLocalizations.of(context).enhYourRequestToReceiveThisPayoutAsCash,
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppLocalizations.of(context).enhCouldNotSubmitRequest((e).toString()),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final prevYear = year - 1;

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
                offlineMessage: AppLocalizations.of(
                  context,
                ).offlineContribution,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      // My activity this year — selling and buying, both
                      // shown together so neither reads as the "main"
                      // source and the other as an afterthought.
                      if (_isLoading)
                        const SkeletonBlock(height: 320)
                      else
                        _MyActivityCard(
                          current: _current,
                          sellingSharePercent: _sellingSharePercent,
                          buyingSharePercent: _buyingSharePercent,
                          year: year,
                          purchaseBreakdown: _purchaseBreakdown,
                        ),
                      const SizedBox(height: 20),

                      // This year's payout — estimated while still in
                      // progress, or finalized with the cash/capital
                      // choice once the co-op has actually paid it out.
                      if (_isLoading)
                        const SkeletonBlock(height: 160)
                      else
                        _ThisYearPayoutCard(
                          current: _current,
                          year: year,
                          onAddToCapital: _current == null
                              ? null
                              : () => _requestAddToCapital(_current!, year),
                          onKeepCash: _current == null
                              ? null
                              : () => _requestKeepAsCash(_current!, year),
                        ),
                      const SizedBox(height: 20),

                      // Timeline
                      const _DistributionTimeline(),
                      const SizedBox(height: 20),

                      // Recent activity — sales and purchases, each its
                      // own small labeled table, so both sources are
                      // equally visible instead of only sales having a
                      // transaction-level view.
                      if (!_isLoading) ...[
                        Text(
                          AppLocalizations.of(context).enhRecentSales,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SalesTable(transactions: _transactions),
                        if (_purchases.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            AppLocalizations.of(context).enhRecentPurchases,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PurchasesTable(purchases: _purchases),
                        ],
                        const SizedBox(height: 20),
                      ],

                      // Capital Shares — shares, investment value, and
                      // loan-eligibility progress, all in one place.
                      // Recording an actual payment (membership renewal
                      // or otherwise) is admin-only, same as Loan
                      // Management — this card is read-only for the
                      // farmer, showing where their own progress stands.
                      if (_isLoading)
                        const SkeletonBlock(height: 220)
                      else
                        _CapitalSharesCard(
                          shares: _shares,
                          summary: _capitalSummary,
                        ),

                      // Last year's payout — only shown when there's
                      // actually something to show; otherwise a "No
                      // payout data" card just takes up space for no
                      // reason.
                      if (!_isLoading && (_previous?.isPaid ?? false)) ...[
                        const SizedBox(height: 20),
                        _PreviousYearPayoutCard(
                          contribution: _previous,
                          year: prevYear,
                          onAddToCapital: _previous == null
                              ? null
                              : () =>
                                    _requestAddToCapital(_previous!, prevYear),
                          onKeepCash: _previous == null
                              ? null
                              : () => _requestKeepAsCash(_previous!, prevYear),
                        ),
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
              title: AppLocalizations.of(context).activityMyContribution,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales Progress Section
// ─────────────────────────────────────────────────────────────────────────────

class _MyActivityCard extends StatelessWidget {
  final MemberContribution? current;
  final double sellingSharePercent;
  final double buyingSharePercent;
  final int year;
  final ProgramPurchaseBreakdown? purchaseBreakdown;

  const _MyActivityCard({
    required this.current,
    required this.sellingSharePercent,
    required this.buyingSharePercent,
    required this.year,
    this.purchaseBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final totalSales = current?.totalSalesAmount ?? 0;
    final palayKg = current?.palaySalesKg ?? 0;
    final palayAmt = current?.palaySalesAmount ?? 0;
    final peanutKg = current?.peanutSalesKg ?? 0;
    final peanutAmt = current?.peanutSalesAmount ?? 0;
    final otherCropsKg = current?.otherCropsQtyKg ?? 0;
    final otherCropsAmt = current?.otherCropsAmount ?? 0;
    final totalPurchases = current?.programPurchasesAmount ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(
              context,
            ).enhMyActivityThisYear((year).toString()),
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // Selling to the cooperative — Offer to Cooperative.
          Row(
            children: [
              Icon(
                Icons.agriculture_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context).enhSellingToCooperative,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₱${NumberFormat('#,##0.00').format(totalSales)}',
            style:
                GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ).copyWith(
                  fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                ),
          ),
          const SizedBox(height: 12),
          _CropSalesRow(
            icon: Icons.grass_rounded,
            iconColor: AppConstants.primaryGreen,
            label: AppLocalizations.of(context).reportsPalay,
            amount: palayAmt,
            kg: palayKg,
            bgColor: AppConstants.primaryGreen.withValues(alpha: 0.05),
          ),
          const SizedBox(height: 8),
          _CropSalesRow(
            icon: Icons.eco_rounded,
            iconColor: AppConstants.amber,
            label: AppLocalizations.of(context).reportsPeanut,
            amount: peanutAmt,
            kg: peanutKg,
            bgColor: AppConstants.amber.withValues(alpha: 0.05),
          ),
          // Any crop other than Palay/Peanut sold via Offer to
          // Cooperative (Phase 9's any-crop widening) — only shown when
          // non-zero, so farmers who only ever sold Palay/Peanut see no
          // change to this card.
          if (otherCropsAmt > 0) ...[
            const SizedBox(height: 8),
            _CropSalesRow(
              icon: Icons.spa_rounded,
              iconColor: AppConstants.buyerBlue,
              label: AppLocalizations.of(context).enhOtherCrops,
              amount: otherCropsAmt,
              kg: otherCropsKg,
              bgColor: AppConstants.buyerBlue.withValues(alpha: 0.05),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: AppConstants.errorRed,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).enhGingerSalesThroughDAAMADMarketLinkingAre,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ActivityShareProgress(
            percent: sellingSharePercent,
            color: AppConstants.primaryGreen,
            myTotal: totalSales,
          ),

          const SizedBox(height: 18),
          Container(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.10),
          ),
          const SizedBox(height: 18),

          // Buying from the cooperative — Product Sales Program.
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 16,
                color: AppConstants.buyerBlue,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context).enhBuyingFromCooperative,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.buyerBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₱${NumberFormat('#,##0.00').format(totalPurchases)}',
            style:
                GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.buyerBlue,
                ).copyWith(
                  fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                ),
          ),
          if ((purchaseBreakdown?.discount ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context).enhRegularPriceMemberDiscountNetPaid(
                (NumberFormat(
                  '#,##0.00',
                ).format(purchaseBreakdown!.regular)).toString(),
                (NumberFormat(
                  '#,##0.00',
                ).format(purchaseBreakdown!.discount)).toString(),
                (NumberFormat(
                  '#,##0.00',
                ).format(purchaseBreakdown!.net)).toString(),
              ),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _ActivityShareProgress(
            percent: buyingSharePercent,
            color: AppConstants.buyerBlue,
            myTotal: totalPurchases,
          ),
        ],
      ),
    );
  }
}

/// Shared "my share of the cooperative-wide total" block — used for both
/// the selling and buying sections above, so the two sources are
/// visually identical in structure and only differ by color/numbers,
/// never implying one matters more than the other.
class _ActivityShareProgress extends StatelessWidget {
  final double percent;
  final Color color;
  final double myTotal;

  const _ActivityShareProgress({
    required this.percent,
    required this.color,
    required this.myTotal,
  });

  @override
  Widget build(BuildContext context) {
    final barValue = (percent / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                AppLocalizations.of(context).enhMyShare,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            Text(
              '${percent.toStringAsFixed(2)}%',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: barValue),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (_, value, __) => LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AppLocalizations.of(context).enhMyTotal,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        Text(
          '₱${NumberFormat('#,##0').format(myTotal)}',
          style:
              GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ).copyWith(
                fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
              ),
        ),
      ],
    );
  }
}

class _CropSalesRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double amount;
  final double kg;
  final Color bgColor;

  const _CropSalesRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.amount,
    required this.kg,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${NumberFormat('#,##0.00').format(amount)}',
                style:
                    GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ).copyWith(
                      fontFamilyFallback: const [
                        'Roboto',
                        'Arial',
                        'sans-serif',
                      ],
                    ),
              ),
              Text(
                formatKgTotal(kg),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// This Year's Payout Card — shows the running estimate while the year is
// still in progress, and flips to the finalized figures (with the
// cash/capital choice) the moment the co-op actually records a
// distribution for this year. Previously this always showed "ESTIMATE
// ONLY" regardless of status, so a payout finalized during its own
// calendar year had no way to appear as final or offer the reinvest
// choice until the following year rolled the record into "previous year."
// ─────────────────────────────────────────────────────────────────────────────

/// Shared by _ThisYearPayoutCard and _PreviousYearPayoutCard — describes
/// whichever payout decision the farmer has already submitted for a year,
/// pending or confirmed.
String _payoutDecisionMessage(AppLocalizations l10n, MemberContribution c) {
  final isCash =
      c.payoutDecision == 'pending_cash' ||
      c.payoutDecision == 'cash_confirmed';
  final amount = NumberFormat('#,##0.00').format(c.payoutDecisionAmount ?? 0);
  final action = isCash
      ? l10n.enhPayoutCashAction(amount)
      : l10n.enhPayoutCapitalAction(amount);
  return c.hasPendingPayoutDecision
      ? l10n.enhPayoutDecisionPending(action)
      : l10n.enhPayoutDecisionConfirmed(action);
}

class _ThisYearPayoutCard extends StatelessWidget {
  final MemberContribution? current;
  final int year;
  final VoidCallback? onAddToCapital;
  final VoidCallback? onKeepCash;

  const _ThisYearPayoutCard({
    required this.current,
    required this.year,
    this.onAddToCapital,
    this.onKeepCash,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = current?.isPaid ?? false;
    final bt = isPaid
        ? (current?.actualBalikTangkilik ?? 0)
        : (current?.estimatedBalikTangkilik ?? 0);
    final interest = isPaid
        ? (current?.actualInterestOnCapital ?? 0)
        : (current?.estimatedInterestOnCapital ?? 0);
    final productSales = isPaid
        ? (current?.actualProductSalesTotal ?? 0)
        : (current?.estimatedProductSalesTotal ?? 0);
    final hasProductSales =
        productSales > 0 || (current?.programPurchasesAmount ?? 0) > 0;
    final total = isPaid
        ? (current?.actualGrandTotal ?? 0)
        : (current?.estimatedGrandTotal ?? 0);
    final available = current?.availableToReinvest ?? 0;
    final reinvested = current?.reinvestedAmount ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppConstants.primaryContainer, AppConstants.primaryGreen],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 8,
            top: 8,
            child: Icon(
              Icons.calculate_rounded,
              size: 80,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppConstants.successGreen
                      : AppConstants.warningAmber,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(
                  isPaid
                      ? AppLocalizations.of(context).enhFINALIZED
                      : AppLocalizations.of(context).enhESTIMATEONLY,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isPaid ? Colors.white : const Color(0xFF2A1800),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPaid
                    ? AppLocalizations.of(
                        context,
                      ).enhBalikTangkilikPayout((year).toString())
                    : AppLocalizations.of(
                        context,
                      ).enhEstimatedDistribution((year).toString()),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              _PatronageSourceHeader(
                icon: Icons.agriculture_rounded,
                title: AppLocalizations.of(
                  context,
                ).balikTangkilikSalesSectionTitle,
                caption: AppLocalizations.of(
                  context,
                ).enhMoneyBackFromCropsYouSoldToThe,
              ),
              const SizedBox(height: 10),
              _DistributionRow(label: 'Balik-Tangkilik', value: bt),
              const SizedBox(height: 8),
              _DistributionRow(
                label: AppLocalizations.of(context).enhInterestOnCapitalShare,
                value: interest,
              ),
              if (hasProductSales) ...[
                const SizedBox(height: 16),
                _PatronageSourceHeader(
                  icon: Icons.storefront_rounded,
                  title: AppLocalizations.of(
                    context,
                  ).balikTangkilikProgramSectionTitle,
                  caption: AppLocalizations.of(
                    context,
                  ).enhMoneyBackFromProductsYouBoughtFromThe,
                ),
                const SizedBox(height: 10),
                _DistributionRow(
                  label: AppLocalizations.of(context).enhPurchasePatronage,
                  value: productSales,
                ),
              ],
              const SizedBox(height: 14),
              Container(
                height: 1,
                color: context.saganaColors.cardBackground.withValues(
                  alpha: 0.20,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isPaid
                        ? AppLocalizations.of(context).enhTotalPayout
                        : AppLocalizations.of(context).enhTotalDistribution,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '₱${NumberFormat('#,##0.00').format(total)}',
                    style:
                        GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.secondaryContainer,
                        ).copyWith(
                          fontFamilyFallback: const [
                            'Roboto',
                            'Arial',
                            'sans-serif',
                          ],
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isPaid) ...[
                if (current != null && current!.hasAnyPayoutDecision) ...[
                  // A decision has already been submitted for this year —
                  // both buttons are gone for good (whether still pending
                  // admin confirmation or already confirmed), since only
                  // one decision is ever allowed per farmer per year. This
                  // is the fix for the exact double-processing risk the
                  // old "Keep as Cash just shows a message" design left
                  // open — a farmer could otherwise still tap "Add to
                  // Capital" afterward for the same money.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.saganaColors.cardBackground.withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          current!.hasPendingPayoutDecision
                              ? Icons.hourglass_top_rounded
                              : Icons.check_circle_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _payoutDecisionMessage(
                              AppLocalizations.of(context),
                              current!,
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (available > 0) ...[
                  Text(
                    AppLocalizations.of(
                      context,
                    ).enhWhatWouldYouLikeToDoWithThis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onKeepCash,
                          icon: const Icon(
                            Icons.payments_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: Text(
                            AppLocalizations.of(context).enhKeepAsCash363,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onAddToCapital,
                          icon: const Icon(Icons.savings_rounded, size: 16),
                          label: Text(
                            AppLocalizations.of(context).enhAddToCapital385,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppConstants.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (reinvested > 0)
                  Text(
                    AppLocalizations.of(
                      context,
                    ).enhYouAddedTheFullToYourCapitalShare(
                      (NumberFormat('#,##0.00').format(reinvested)).toString(),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
              ] else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.saganaColors.cardBackground.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).enhThisIsAnEstimateOnlyActualDistributionAmounts,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.80),
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatronageSourceHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  const _PatronageSourceHeader({
    required this.icon,
    required this.title,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.90)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontStyle: FontStyle.italic,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

class _DistributionRow extends StatelessWidget {
  final String label;
  final double value;
  const _DistributionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.80),
              ),
            ),
          ),
          Text(
            '₱${NumberFormat('#,##0.00').format(value)}',
            style:
                GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ).copyWith(
                  fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Distribution Timeline
// ─────────────────────────────────────────────────────────────────────────────

class _DistributionTimeline extends StatefulWidget {
  const _DistributionTimeline();

  @override
  State<_DistributionTimeline> createState() => _DistributionTimelineState();
}

class _DistributionTimelineState extends State<_DistributionTimeline> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context).enhHowDoesThisWork,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                children: [
                  // Vertical line
                  Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: AppConstants.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.analytics_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(
                            context,
                          ).enhAuditedFinancialStatement,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Text(
                          AppLocalizations.of(context).enhJanuaryMarch,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IntrinsicHeight(
              child: Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: context.adaptiveSurface(
                            const Color(0xFFD5ECF8),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Icon(
                          Icons.account_balance_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).enhAnnualGeneralAssembly,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          AppLocalizations.of(
                            context,
                          ).enhWithinFirstDaysOfTheYear,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: context.adaptiveSurface(const Color(0xFFD5ECF8)),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Icon(
                    Icons.payments_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).enhBalikTangkilikReleased,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).enhPostAssemblyDistribution,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales Table
// ─────────────────────────────────────────────────────────────────────────────

class _SalesTable extends StatelessWidget {
  final List<MemberSalesTransaction> transactions;
  const _SalesTable({required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).enhNoSalesTransactionsRecordedYet,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              const Color(0xFFE6F6FF).withValues(alpha: 0.80),
            ),
            headingTextStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            dataTextStyle: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            dividerThickness: 0.5,
            columns: [
              DataColumn(label: Text(AppLocalizations.of(context).rptDate)),
              DataColumn(
                label: Text(AppLocalizations.of(context).priceTrendCropLabel),
              ),
              DataColumn(
                label: Text(AppLocalizations.of(context).enhQty396),
                numeric: true,
              ),
              DataColumn(
                label: Text(AppLocalizations.of(context).rptAmount),
                numeric: true,
              ),
            ],
            rows: transactions.map((t) {
              final isPalay = t.cropType == 'palay';
              return DataRow(
                cells: [
                  DataCell(Text(DateFormat('MMM d, yyyy').format(t.saleDate))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isPalay
                            ? AppConstants.primaryGreen.withValues(alpha: 0.10)
                            : AppConstants.amber.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        t.cropName.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isPalay
                              ? Theme.of(context).colorScheme.primary
                              : AppConstants.amber,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(formatQuantityUnit(t.quantityKg, t.unit))),
                  DataCell(
                    Text(
                      '₱${NumberFormat('#,##0.00').format(t.amount)}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500)
                          .copyWith(
                            fontFamilyFallback: const [
                              'Roboto',
                              'Arial',
                              'sans-serif',
                            ],
                          ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Mirrors _SalesTable for the buying side (Option B) — only rendered
/// when non-empty (see the call site), so it never shows an empty-state
/// message a farmer who never used a Product Sales Program doesn't need.
class _PurchasesTable extends StatelessWidget {
  final List<ProgramPurchase> purchases;
  const _PurchasesTable({required this.purchases});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              const Color(0xFFE6F6FF).withValues(alpha: 0.80),
            ),
            headingTextStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            dataTextStyle: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            dividerThickness: 0.5,
            columns: [
              DataColumn(label: Text(AppLocalizations.of(context).rptDate)),
              DataColumn(
                label: Text(
                  AppLocalizations.of(context).editListingFieldProduct,
                ),
              ),
              DataColumn(
                label: Text(AppLocalizations.of(context).enhQty396),
                numeric: true,
              ),
              if (purchases.any((p) => p.hasDiscount)) ...[
                DataColumn(
                  label: Text(AppLocalizations.of(context).enhRegular),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(AppLocalizations.of(context).enhDiscount),
                  numeric: true,
                ),
              ],
              DataColumn(
                label: Text(AppLocalizations.of(context).loanDashPaid),
                numeric: true,
              ),
            ],
            rows: purchases.map((p) {
              final date = p.confirmedAt ?? p.requestedAt;
              return DataRow(
                cells: [
                  DataCell(Text(DateFormat('MMM d, yyyy').format(date))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppConstants.buyerBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.itemName.isNotEmpty
                            ? p.itemName.toUpperCase()
                            : 'ITEM',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.buyerBlue,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${NumberFormat('#,##0').format(p.quantity)} ${p.unit}',
                    ),
                  ),
                  if (purchases.any((x) => x.hasDiscount)) ...[
                    DataCell(
                      Text(
                        '₱${NumberFormat('#,##0.00').format(p.regularTotal)}',
                      ),
                    ),
                    DataCell(
                      Text(
                        p.hasDiscount
                            ? '− ₱${NumberFormat('#,##0.00').format(p.discountAmount)}'
                            : '—',
                      ),
                    ),
                  ],
                  DataCell(
                    Text(
                      '₱${NumberFormat('#,##0.00').format(p.totalAmount)}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500)
                          .copyWith(
                            fontFamilyFallback: const [
                              'Roboto',
                              'Arial',
                              'sans-serif',
                            ],
                          ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capital Shares Card
// ─────────────────────────────────────────────────────────────────────────────

class _CapitalSharesCard extends StatelessWidget {
  final CapitalSharesModel? shares;
  final MemberCapitalSummary? summary;

  const _CapitalSharesCard({required this.shares, this.summary});

  @override
  Widget build(BuildContext context) {
    final totalShares = shares?.totalShares ?? 0;
    final investmentValue = shares?.investmentValue ?? 0;
    final perShare = shares?.shareValuePerUnit ?? 100;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).enhCapitalShares400,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppConstants.amber,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalShares',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context).enhTotalShares,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  width: 1,
                  height: 36,
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.20),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₱${NumberFormat('#,##0').format(investmentValue)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ).copyWith(
                            fontFamilyFallback: const [
                              'Roboto',
                              'Arial',
                              'sans-serif',
                            ],
                          ),
                    ),
                    Text(
                      AppLocalizations.of(context).enhInvestmentValue,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.saganaColors.cardBackground.withValues(
                alpha: 0.50,
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).enhShareValue,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(
                          context,
                        ).enhShare404((perShare.toStringAsFixed(2)).toString()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ).copyWith(
                              fontFamilyFallback: const [
                                'Roboto',
                                'Arial',
                                'sans-serif',
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(
                    context,
                  ).enhInterestRatesAreDeterminedAnnuallyByTheBoard,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: summary!.shareProgress,
                minHeight: 6,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.15),
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              summary!.meetsLoanEligibility
                  ? AppLocalizations.of(context).enhMeetsTheMinimumForALoan(
                      (summary!.minimumForLoan.toStringAsFixed(0)).toString(),
                    )
                  : AppLocalizations.of(
                      context,
                    ).enhNeedsMoreToReachTheLoanMinimum(
                      (summary!.loanShortfall.toStringAsFixed(0)).toString(),
                      (summary!.minimumForLoan.toStringAsFixed(0)).toString(),
                    ),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: summary!.meetsLoanEligibility
                    ? AppConstants.successGreen
                    : AppConstants.warningAmber,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Previous Year Payout Card
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutDecisionBadge extends StatelessWidget {
  final MemberContribution contribution;
  final bool isPending;
  const _PayoutDecisionBadge({
    required this.contribution,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPending
        ? AppConstants.warningAmber
        : AppConstants.successGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPending
                ? Icons.hourglass_top_rounded
                : Icons.check_circle_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _payoutDecisionMessage(
                AppLocalizations.of(context),
                contribution,
              ),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviousYearPayoutCard extends StatelessWidget {
  final MemberContribution? contribution;
  final int year;
  final VoidCallback? onAddToCapital;
  final VoidCallback? onKeepCash;

  const _PreviousYearPayoutCard({
    required this.contribution,
    required this.year,
    this.onAddToCapital,
    this.onKeepCash,
  });

  @override
  Widget build(BuildContext context) {
    final offerToCoopTotal = contribution?.actualOfferToCoopTotal ?? 0;
    final productSalesTotal = contribution?.actualProductSalesTotal ?? 0;
    final total = contribution?.actualGrandTotal ?? 0;
    final isPaid = contribution?.isPaid ?? false;
    final payoutDate = contribution?.actualPayoutDate;
    final reinvested = contribution?.reinvestedAmount ?? 0;
    final available = contribution?.availableToReinvest ?? 0;
    final hasDecision = contribution?.hasAnyPayoutDecision ?? false;
    final isPending = contribution?.hasPendingPayoutDecision ?? false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).enhActualPayout((year).toString()),
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (isPaid)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.successGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).balikTangkilikPaidBadge,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.successGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (contribution == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).enhNoPayoutDataFor((year).toString()),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            )
          else ...[
            _PayoutRow(
              label: AppLocalizations.of(
                context,
              ).balikTangkilikSalesSectionTitle,
              value: offerToCoopTotal,
            ),
            if (productSalesTotal > 0) ...[
              const SizedBox(height: 8),
              _PayoutRow(
                label: AppLocalizations.of(
                  context,
                ).balikTangkilikProgramSectionTitle,
                value: productSalesTotal,
              ),
            ],
            const SizedBox(height: 10),
            Container(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.10),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).enhTotalReceived,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    if (payoutDate != null)
                      Text(
                        DateFormat('MMM d, yyyy').format(payoutDate),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                Text(
                  '₱${NumberFormat('#,##0.00').format(total)}',
                  style:
                      GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ).copyWith(
                        fontFamilyFallback: const [
                          'Roboto',
                          'Arial',
                          'sans-serif',
                        ],
                      ),
                ),
              ],
            ),
            if (reinvested > 0) ...[
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).enhAlreadyAddedToYourCapitalShare(
                  (NumberFormat('#,##0.00').format(reinvested)).toString(),
                ),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
            if (isPaid && available > 0) ...[
              const SizedBox(height: 10),
              if (hasDecision)
                _PayoutDecisionBadge(
                  contribution: contribution!,
                  isPending: isPending,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onKeepCash,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context).enhKeepAsCash363,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onAddToCapital,
                        icon: const Icon(Icons.savings_rounded, size: 16),
                        label: Text(
                          AppLocalizations.of(context).enhAddToCapital385,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primaryGreen,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final String label;
  final double value;
  const _PayoutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          '₱${NumberFormat('#,##0.00').format(value)}',
          style:
              GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ).copyWith(
                fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
              ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Shimmer
// ─────────────────────────────────────────────────────────────────────────────
