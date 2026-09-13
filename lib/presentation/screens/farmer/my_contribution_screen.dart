import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

class MyContributionScreen extends StatefulWidget {
  const MyContributionScreen({super.key});

  @override
  State<MyContributionScreen> createState() => _MyContributionScreenState();
}

class _MyContributionScreenState extends State<MyContributionScreen> {
  final _repo = ContributionRepository();

  MemberContribution? _current;
  MemberContribution? _previous;
  List<MemberSalesTransaction> _transactions = [];
  CapitalSharesModel? _shares;
  CoopAnnualTotal? _coopTotal;

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
    final results = await Future.wait([
      _repo.fetchCurrentYearContribution(),
      _repo.fetchPreviousYearContribution(),
      _repo.fetchRecentTransactions(),
      _repo.fetchCapitalShares(),
      _repo.fetchCoopTotal(year),
    ]);
    if (!mounted) return;
    setState(() {
      _current = results[0] as MemberContribution?;
      _previous = results[1] as MemberContribution?;
      _transactions = results[2] as List<MemberSalesTransaction>;
      _shares = results[3] as CapitalSharesModel?;
      _coopTotal = results[4] as CoopAnnualTotal?;
      _isLoading = false;
    });
  }

  double get _memberSharePercent {
    if (_current == null || _coopTotal == null) return 0;
    return _repo.computeMemberSharePercent(
      memberSales: _current!.totalSalesAmount,
      coopTotalSales: _coopTotal!.totalCoopSales,
    );
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final prevYear = year - 1;

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      // Offline banner
                      if (!_isOnline) ...[
                        const OfflineBanner(message: "You're offline — your contribution data may not be up to date."),
                        const SizedBox(height: 16),
                      ],

                      // Sales section
                      if (_isLoading)
                        const _SectionShimmer(height: 240)
                      else
                        _SalesProgressSection(
                          current: _current,
                          coopTotal: _coopTotal,
                          memberSharePercent: _memberSharePercent,
                          year: year,
                        ),
                      const SizedBox(height: 20),

                      // Estimated distribution
                      if (_isLoading)
                        const _SectionShimmer(height: 160)
                      else
                        _EstimatedDistributionCard(current: _current),
                      const SizedBox(height: 20),

                      // Timeline
                      const _DistributionTimeline(),
                      const SizedBox(height: 20),

                      // Recent sales table
                      if (!_isLoading) ...[
                        Text(
                          'Recent Sales Breakdown',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.charcoal,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SalesTable(transactions: _transactions),
                        const SizedBox(height: 20),
                      ],

                      // Capital shares + previous year payout
                      if (_isLoading)
                        const _SectionShimmer(height: 140)
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _CapitalSharesCard(shares: _shares),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _PreviousYearPayoutCard(
                                contribution: _previous,
                                year: prevYear,
                              ),
                            ),
                          ],
                        ),
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
              title: 'My Contribution',
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

class _SalesProgressSection extends StatelessWidget {
  final MemberContribution? current;
  final CoopAnnualTotal? coopTotal;
  final double memberSharePercent;
  final int year;

  const _SalesProgressSection({
    required this.current,
    required this.coopTotal,
    required this.memberSharePercent,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Current year sales card
        _CurrentYearSalesCard(current: current, year: year),
        const SizedBox(height: 14),
        // Share meter card
        _ShareMeterCard(
          current: current,
          coopTotal: coopTotal,
          memberSharePercent: memberSharePercent,
        ),
      ],
    );
  }
}

class _CurrentYearSalesCard extends StatelessWidget {
  final MemberContribution? current;
  final int year;

  const _CurrentYearSalesCard({required this.current, required this.year});

  @override
  Widget build(BuildContext context) {
    final total = current?.totalSalesAmount ?? 0;
    final palayKg = current?.palaySalesKg ?? 0;
    final palayAmt = current?.palaySalesAmount ?? 0;
    final peanutKg = current?.peanutSalesKg ?? 0;
    final peanutAmt = current?.peanutSalesAmount ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 16,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Icon(
              Icons.agriculture_rounded,
              size: 100,
              color: AppConstants.primaryGreen.withValues(alpha: 0.05),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Total Sales to SP3 ($year)',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '₱${NumberFormat('#,##0.00').format(total)}',
                style:
                    GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.primaryContainer,
                    ).copyWith(
                      fontFamilyFallback: const [
                        'Roboto',
                        'Arial',
                        'sans-serif',
                      ],
                    ),
              ),
              const SizedBox(height: 14),
              _CropSalesRow(
                icon: Icons.grass_rounded,
                iconColor: AppConstants.primaryGreen,
                label: 'Palay',
                amount: palayAmt,
                kg: palayKg,
                bgColor: AppConstants.primaryGreen.withValues(alpha: 0.05),
              ),
              const SizedBox(height: 8),
              _CropSalesRow(
                icon: Icons.eco_rounded,
                iconColor: AppConstants.amber,
                label: 'Peanut',
                amount: peanutAmt,
                kg: peanutKg,
                bgColor: AppConstants.amber.withValues(alpha: 0.05),
              ),
              const SizedBox(height: 12),
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
                      'Ginger sales through DA-AMAD market linking are not included.',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
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
                '${NumberFormat('#,##0').format(kg)} kg',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShareMeterCard extends StatelessWidget {
  final MemberContribution? current;
  final CoopAnnualTotal? coopTotal;
  final double memberSharePercent;

  const _ShareMeterCard({
    required this.current,
    required this.coopTotal,
    required this.memberSharePercent,
  });

  @override
  Widget build(BuildContext context) {
    final memberSales = current?.totalSalesAmount ?? 0;
    final coopSales = coopTotal?.totalCoopSales ?? 0;
    final barValue = (memberSharePercent / 100).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
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
            'My Share of Total Coop Sales',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.limeGreen,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  'Member Share',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primaryContainer,
                  ),
                ),
              ),
              Text(
                '${memberSharePercent.toStringAsFixed(2)}%',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
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
                minHeight: 12,
                backgroundColor: const Color(0xFFCFE6F2),
                valueColor: const AlwaysStoppedAnimation(
                  AppConstants.primaryGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: AppConstants.outline.withValues(alpha: 0.10),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coop Total',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.outline,
                    ),
                  ),
                  Text(
                    '₱${NumberFormat('#,##0').format(coopSales)}',
                    style:
                        GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Personal Total',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.outline,
                    ),
                  ),
                  Text(
                    '₱${NumberFormat('#,##0').format(memberSales)}',
                    style:
                        GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.primaryGreen,
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
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Estimated Distribution Card
// ─────────────────────────────────────────────────────────────────────────────

class _EstimatedDistributionCard extends StatelessWidget {
  final MemberContribution? current;
  const _EstimatedDistributionCard({required this.current});

  @override
  Widget build(BuildContext context) {
    final estBT = current?.estimatedBalikTangkilik ?? 0;
    final estInterest = current?.estimatedInterestOnCapital ?? 0;
    final estTotal = estBT + estInterest;

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
                  color: AppConstants.warningAmber,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(
                  '⚠️  ESTIMATE ONLY',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2A1800),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${DateTime.now().year} Estimated Distribution',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              _DistributionRow(
                label: 'Estimated Balik-Tangkilik',
                value: estBT,
              ),
              const SizedBox(height: 10),
              _DistributionRow(
                label: 'Estimated Interest on Capital Share',
                value: estInterest,
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.20)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Distribution',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '₱${NumberFormat('#,##0.00').format(estTotal)}',
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  'This is an estimate only. Actual distribution amounts are determined by the '
                  "cooperative's Audited Financial Statement and announced at the Annual General "
                  'Assembly within the first 90 days of next year.',
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

class _DistributionTimeline extends StatelessWidget {
  const _DistributionTimeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
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
          Text(
            'Annual Distribution Cycle',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppConstants.charcoal,
            ),
          ),
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
                        color: AppConstants.outline.withValues(alpha: 0.20),
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
                        'Audited Financial Statement',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      Text(
                        'January – March',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.outline,
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
                        color: const Color(0xFFD5ECF8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppConstants.outline.withValues(alpha: 0.20),
                        ),
                      ),
                      child: const Icon(
                        Icons.account_balance_rounded,
                        size: 14,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: AppConstants.outline.withValues(alpha: 0.20),
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
                        'Annual General Assembly',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.onSurface,
                        ),
                      ),
                      Text(
                        'Within first 90 days of the year',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.outline,
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
                  color: const Color(0xFFD5ECF8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppConstants.outline.withValues(alpha: 0.20),
                  ),
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  size: 14,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balik-Tangkilik Released',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.onSurface,
                      ),
                    ),
                    Text(
                      'Post-Assembly Distribution',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.outline,
                      ),
                    ),
                  ],
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
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        ),
        child: Center(
          child: Text(
            'No sales transactions recorded yet.',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppConstants.outline,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
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
              color: AppConstants.onSurfaceVariant,
            ),
            dataTextStyle: GoogleFonts.inter(
              fontSize: 12,
              color: AppConstants.onSurface,
            ),
            dividerThickness: 0.5,
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Crop')),
              DataColumn(label: Text('Qty'), numeric: true),
              DataColumn(label: Text('Amount'), numeric: true),
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
                              ? AppConstants.primaryContainer
                              : AppConstants.amber,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text('${NumberFormat('#,##0').format(t.quantityKg)} kg'),
                  ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Capital Shares Card
// ─────────────────────────────────────────────────────────────────────────────

class _CapitalSharesCard extends StatelessWidget {
  final CapitalSharesModel? shares;
  const _CapitalSharesCard({required this.shares});

  @override
  Widget build(BuildContext context) {
    final totalShares = shares?.totalShares ?? 0;
    final investmentValue = shares?.investmentValue ?? 0;
    final perShare = shares?.shareValuePerUnit ?? 100;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
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
                    'Capital Shares',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.charcoal,
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
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                    Text(
                      'Total Shares',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppConstants.outline,
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
                  color: AppConstants.outline.withValues(alpha: 0.20),
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
                            color: AppConstants.primaryGreen,
                          ).copyWith(
                            fontFamilyFallback: const [
                              'Roboto',
                              'Arial',
                              'sans-serif',
                            ],
                          ),
                    ),
                    Text(
                      'Investment Value',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppConstants.outline,
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
              color: Colors.white.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: AppConstants.outline.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Share Value',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '₱${perShare.toStringAsFixed(2)} / share',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
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
                  'Interest rates are determined annually by the Board of Directors based on coop performance.',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppConstants.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Previous Year Payout Card
// ─────────────────────────────────────────────────────────────────────────────

class _PreviousYearPayoutCard extends StatelessWidget {
  final MemberContribution? contribution;
  final int year;

  const _PreviousYearPayoutCard({
    required this.contribution,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    final bt = contribution?.actualBalikTangkilik ?? 0;
    final interest = contribution?.actualInterestOnCapital ?? 0;
    final total = bt + interest;
    final isPaid = contribution?.isPaid ?? false;
    final payoutDate = contribution?.actualPayoutDate;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
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
              Text(
                '$year Actual Payout',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.charcoal,
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
                    'PAID',
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
                  'No payout data for $year.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppConstants.outline,
                  ),
                ),
              ),
            )
          else ...[
            _PayoutRow(label: 'Balik-Tangkilik', value: bt),
            const SizedBox(height: 8),
            _PayoutRow(label: 'Interest on Capital', value: interest),
            const SizedBox(height: 10),
            Container(
              height: 1,
              color: AppConstants.outline.withValues(alpha: 0.10),
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
                      'Total Received',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.outline,
                      ),
                    ),
                    if (payoutDate != null)
                      Text(
                        DateFormat('MMM d, yyyy').format(payoutDate),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.primaryGreen,
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
                        color: AppConstants.charcoal,
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
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        Text(
          '₱${NumberFormat('#,##0.00').format(value)}',
          style:
              GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConstants.onSurface,
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

class _SectionShimmer extends StatelessWidget {
  final double height;
  const _SectionShimmer({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}
