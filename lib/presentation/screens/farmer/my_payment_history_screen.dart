import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/loan_sorting.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/farmer_loan_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';

/// Farmer > Input Loans > Payment History > View All.
///
/// Every payment the Farmer has made on any loan, most recent first (by the date
/// of the payment), grouped by month, with the total paid at the top. The order is
/// the same one the Input Loans landing page uses (see loan_sorting.dart).
class MyPaymentHistoryScreen extends StatefulWidget {
  const MyPaymentHistoryScreen({super.key});

  @override
  State<MyPaymentHistoryScreen> createState() => _MyPaymentHistoryScreenState();
}

class _MyPaymentHistoryScreenState extends State<MyPaymentHistoryScreen> {
  final _repo = LoanRepository();

  List<LoanPaymentEntry> _payments = [];
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
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final loans = await _repo.fetchLoans();
    if (!mounted) return;
    setState(() {
      _payments = paymentsNewestFirst(loans);
      _isLoading = false;
    });
  }

  double get _totalPaid =>
      _payments.fold<double>(0, (sum, e) => sum + e.payment.amountPaid);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The payments are already newest first; a month heading goes in front of the
    // first payment of each month.
    final items = <Widget>[];
    String? currentMonth;
    for (final e in _payments) {
      final month = DateFormat('MMMM yyyy').format(e.payment.paymentDate);
      if (month != currentMonth) {
        currentMonth = month;
        items.add(
          Padding(
            padding: EdgeInsets.only(top: items.isEmpty ? 0 : 14, bottom: 8),
            child: Text(
              month,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FarmerPaymentRow(loan: e.loan, payment: e.payment),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'loans',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineLoans,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                      : _payments.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 40),
                            LoanEmptyNote(
                              icon: Icons.payments_outlined,
                              text: l10n.loanMyNoPayments,
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                          children: [
                            _TotalPaidCard(total: _totalPaid, count: _payments.length),
                            const SizedBox(height: 16),
                            ...items,
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
              title: l10n.loanMyPaymentsTitle,
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

class _TotalPaidCard extends StatelessWidget {
  final double total;
  final int count;
  const _TotalPaidCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: const Icon(Icons.payments_rounded, size: 22, color: AppConstants.successGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.loanMyTotalPaid,
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₱${NumberFormat('#,##0.00').format(total)}',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.successGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              l10n.loanMyPaymentCount(count),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppConstants.successGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
