import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/models/program_assistance_model.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/loans_view.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/feature_restriction_notice.dart';
import '../../../data/models/member_restriction.dart';

/// Farmer > Profile > Input Loans.
///
/// Laid out like Manager > Loans so both roles read a loan the same way:
///   1. Outstanding Loans            (what is still owed, and how much is repaid)
///   2. Next Payment Due             (the next BOD payment, or what is overdue)
///   3. Input-only loans note
///   4. Loan History                 (the latest few loans; View All opens them all)
///   5. Payment History              (the latest few payments; View All opens them all)
/// and a + button to request a loan.
///
/// The landing page keeps to the most recent records so it stays short: the latest
/// [_recentLoans] loans and [_recentPayments] payments, newest first. View All opens
/// the full Loan History (with the status chips) and Payment History screens, which
/// sort the very same way (see loan_sorting.dart).
///
/// Every figure comes from the Farmer's own loans (farmer_loans with their items
/// and payments), so the balance, the history and the payments always agree. The
/// statuses are the stored ones: active, overdue (set by the daily maintenance /
/// the Manager's dashboard when a payment is late) and paid.
class MyLoansScreen extends StatefulWidget {
  const MyLoansScreen({super.key});

  @override
  State<MyLoansScreen> createState() => _MyLoansScreenState();
}

class _MyLoansScreenState extends State<MyLoansScreen> {
  final _repo = LoanRepository();

  List<LoanModel> _loans = [];
  List<AssistanceRequest> _assistance = [];
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
    final loans = await _repo.fetchLoans();
    final assistance = await ProgramAssistanceRepository().fetchMyApproved();
    if (!mounted) return;
    setState(() {
      _loans = loans;
      _assistance = assistance;
      _isLoading = false;
    });
  }

  Future<void> _requestLoan() async {
    // A restricted Farmer cannot start a new loan request; existing loans are untouched.
    if (!await ensureFeatureAvailable(context, RestrictableFeature.loanRequest)) return;
    if (!mounted) return;
    await context.pushRoute<void>(AppRoutes.requestLoan);
    if (mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: "loans",
                isOnline: _isOnline,
                offlineMessage: l10n.offlineLoans,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    children: loansViewChildren(
                      context,
                      loans: _loans,
                      assistance: _assistance,
                      isLoading: _isLoading,
                      onViewAllLoans: () =>
                          context.pushRoute<void>(AppRoutes.myLoanHistory),
                      onViewAllPayments: () =>
                          context.pushRoute<void>(AppRoutes.myPaymentHistory),
                    ),
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
              title: l10n.loanMyScreenTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, onPressed: _requestLoan,
        tooltip: l10n.loanReqRequestButton,
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }
}

