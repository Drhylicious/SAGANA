import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class MyLoansScreen extends StatefulWidget {
  const MyLoansScreen({super.key});

  @override
  State<MyLoansScreen> createState() => _MyLoansScreenState();
}

class _MyLoansScreenState extends State<MyLoansScreen> {
  final _repo = LoanRepository();

  List<LoanModel> _loans = [];
  double _totalOutstanding = 0;
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
    final results = await Future.wait([
      _repo.fetchLoans(),
      _repo.fetchTotalOutstanding(),
    ]);
    if (!mounted) return;
    setState(() {
      _loans = results[0] as List<LoanModel>;
      _totalOutstanding = results[1] as double;
      _isLoading = false;
    });
  }

  // ── BOD date logic (port of HTML JS) ──────────────────────────────────────
  DateTime _nextBodSaturday() {
    final now = DateTime.now();
    DateTime candidate = _firstSaturdayOf(now.year, now.month);
    // If this month's first Saturday has passed, use next month's
    if (now.isAfter(candidate)) {
      final next = DateTime(now.year, now.month + 1, 1);
      candidate = _firstSaturdayOf(next.year, next.month);
    }
    return candidate;
  }

  DateTime _firstSaturdayOf(int year, int month) {
    DateTime d = DateTime(year, month, 1);
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final activeLoans = _loans.where((l) => !l.isPaid).toList();
    final bodDate = _nextBodSaturday();
    final allPaid = !_isLoading && _totalOutstanding == 0 && _loans.isNotEmpty;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              if (!_isOnline) const _OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      // Outstanding balance card
                      _OutstandingCard(
                        total: _totalOutstanding,
                        allPaid: allPaid,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 20),

                      // BOD schedule card
                      _BodScheduleCard(bodDate: bodDate),
                      const SizedBox(height: 20),

                      // Info banner
                      const _InfoBanner(),
                      const SizedBox(height: 20),

                      // Active loans header
                      if (!_isLoading) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Active Loans',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppConstants.charcoal,
                              ),
                            ),
                            Text(
                              '${activeLoans.length} Loan${activeLoans.length == 1 ? '' : 's'}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppConstants.outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Loan list / empty / shimmer
                      if (_isLoading)
                        ...List.generate(
                          2,
                          (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: _LoanShimmer(),
                          ),
                        )
                      else if (activeLoans.isEmpty)
                        _EmptyState()
                      else
                        ...activeLoans.map(
                          (loan) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _LoanCard(loan: loan),
                          ),
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
              title: 'My Input Loans',
              onBack: () => Navigator.of(context).pop(),
              profilePhotoUrl: null,
              onProfileTap: () {},
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: AppConstants.errorRed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          const SizedBox(width: 8),
          Text(
            'Connectivity lost. Showing offline data.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outstanding Balance Card
// ─────────────────────────────────────────────────────────────────────────────

class _OutstandingCard extends StatelessWidget {
  final double total;
  final bool allPaid;
  final bool isLoading;

  const _OutstandingCard({
    required this.total,
    required this.allPaid,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final color = allPaid ? AppConstants.successGreen : AppConstants.errorRed;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL OUTSTANDING BALANCE',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          if (isLoading)
            Container(width: 180, height: 32, color: const Color(0xFFE8E8E8))
          else if (allPaid)
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppConstants.successGreen,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Great job! All loans are fully paid.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.successGreen,
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '₱',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.errorRed,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  NumberFormat('#,##0.00').format(total),
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.errorRed,
                    letterSpacing: -0.5,
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
// BOD Schedule Card
// ─────────────────────────────────────────────────────────────────────────────

class _BodScheduleCard extends StatelessWidget {
  final DateTime bodDate;
  const _BodScheduleCard({required this.bodDate});

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('MMMM d, yyyy').format(bodDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppConstants.primaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.10),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              Icons.calendar_month_rounded,
              size: 100,
              color: AppConstants.primaryGreen.withValues(alpha: 0.05),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next Payment Due',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatted,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.secondaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      'UPCOMING',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2A1800),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: Colors.white),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppConstants.amber,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.onSurfaceVariant,
                            height: 1.4,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Payments are reviewed during the ',
                            ),
                            TextSpan(
                              text: 'SP3 BOD Meeting',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: AppConstants.onSurface,
                              ),
                            ),
                            const TextSpan(
                              text: ' every 1st Saturday of the month.',
                            ),
                          ],
                        ),
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
// Info Banner
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDBF1FE),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.agriculture_rounded,
            color: AppConstants.primaryGreen,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Input-Only Loans',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primaryGreen,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'SAGANA loans are provided as physical agricultural inputs '
                  '(seeds, fertilizers, tools, etc.) and never as cash disbursements.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
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
// Loan Card
// ─────────────────────────────────────────────────────────────────────────────

class _LoanCard extends StatefulWidget {
  final LoanModel loan;
  const _LoanCard({required this.loan});

  @override
  State<_LoanCard> createState() => _LoanCardState();
}

class _LoanCardState extends State<_LoanCard> {
  bool _historyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final statusColor = loan.isOverdue
        ? AppConstants.errorRed
        : AppConstants.primaryContainer;
    final statusLabel = loan.isOverdue ? 'Overdue' : 'Active';
    final remainingColor = loan.isOverdue
        ? AppConstants.errorRed
        : AppConstants.primaryGreen;
    final progressColor = loan.isOverdue
        ? AppConstants.errorRed
        : AppConstants.primaryGreen;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
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
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Ref: ',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppConstants.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              loan.referenceNo,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppConstants.onSurface,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Issued: ${DateFormat('MMM d, yyyy').format(loan.issuedDate)}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: loan.isOverdue
                            ? const Color(0xFFFFDAD6)
                            : AppConstants.primaryContainer.withValues(
                                alpha: 0.15,
                              ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Itemized inputs ────────────────────────────────────────
                ...loan.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.displayLabel,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppConstants.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '₱${NumberFormat('#,##0').format(item.lineTotal)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppConstants.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F6FF).withValues(alpha: 0.50),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(AppConstants.radiusLg),
                bottomRight: Radius.circular(AppConstants.radiusLg),
              ),
              border: Border(
                top: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Value',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '₱${NumberFormat('#,##0.00').format(loan.totalValue)}',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppConstants.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Remaining',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '₱${NumberFormat('#,##0.00').format(loan.remainingBalance)}',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: remainingColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: loan.repaidPercent,
                    minHeight: 8,
                    backgroundColor: AppConstants.outline.withValues(
                      alpha: 0.20,
                    ),
                    valueColor: AlwaysStoppedAnimation(progressColor),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(loan.repaidPercent * 100).toStringAsFixed(0)}% repaid',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppConstants.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Payment history toggle
                GestureDetector(
                  onTap: () =>
                      setState(() => _historyExpanded = !_historyExpanded),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Payment History',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppConstants.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _historyExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: AppConstants.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Payment history detail
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _PaymentHistoryList(payments: loan.payments),
                  crossFadeState: _historyExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 220),
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
// Payment History List
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentHistoryList extends StatelessWidget {
  final List<LoanPaymentModel> payments;
  const _PaymentHistoryList({required this.payments});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'No payments recorded yet.',
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
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppConstants.outline.withValues(alpha: 0.10)),
        ),
      ),
      child: Column(
        children: payments.map((p) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${DateFormat('MMM d, yyyy').format(p.paymentDate)} (BOD Sat)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '-₱${NumberFormat('#,##0.00').format(p.amountPaid)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.successGreen,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Bal: ₱${NumberFormat('#,##0.00').format(p.runningBalance)}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppConstants.outline,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFCFE6F2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 38,
              color: AppConstants.outline,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No active loans',
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "You currently don't have any outstanding input loans with the cooperative.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(
              'Contact SP3 Office',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loan Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _LoanShimmer extends StatelessWidget {
  const _LoanShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}
