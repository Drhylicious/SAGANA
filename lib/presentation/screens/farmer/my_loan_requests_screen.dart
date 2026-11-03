import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/loan_request_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/loan_choice_chip.dart';
import '../../widgets/loan_request_widgets.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../../data/services/connectivity_service.dart';

/// Farmer > Request a Loan > My Loan Requests.
///
/// Every loan request the Farmer has sent and where it stands: Pending (waiting
/// for a Manager or Officer), Approved (the loan was issued), Disapproved (with
/// the reason) or Cancelled (withdrawn by the Farmer). A Pending request can be
/// cancelled from its details. The Farmer sees that the Cooperative decided, never
/// which staff member did.
class MyLoanRequestsScreen extends StatefulWidget {
  const MyLoanRequestsScreen({super.key});

  @override
  State<MyLoanRequestsScreen> createState() => _MyLoanRequestsScreenState();
}

class _MyLoanRequestsScreenState extends State<MyLoanRequestsScreen> {
  final _repo = LoanRepository();

  List<LoanRequestModel> _requests = [];
  String? _statusFilter; // null = All
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
    final rows = await _repo.fetchMyLoanRequests();
    if (!mounted) return;
    setState(() {
      _requests = rows;
      _isLoading = false;
    });
  }

  List<LoanRequestModel> get _visible => _statusFilter == null
      ? _requests
      : _requests.where((r) => r.status == _statusFilter).toList();

  int _count(String? status) =>
      status == null ? _requests.length : _requests.where((r) => r.status == status).length;

  Future<void> _open(LoanRequestModel request) async {
    final changed = await showManagementModal<bool>(
      context: context,
      builder: (_) => LoanRequestDetailSheet(request: request, repo: _repo),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = _visible;
    final options = <({String? status, String label})>[
      (status: null, label: '${l10n.loanReqAll} (${_count(null)})'),
      (status: 'pending', label: '${l10n.loanReqStatusPending} (${_count('pending')})'),
      (status: 'approved', label: '${l10n.loanReqStatusApproved} (${_count('approved')})'),
      (status: 'disapproved', label: '${l10n.loanReqStatusDisapproved} (${_count('disapproved')})'),
      (status: 'cancelled', label: '${l10n.loanReqStatusCancelled} (${_count('cancelled')})'),
    ];

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'loan_requests',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineLoans,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Center(
                      child: LoanChoiceChip(
                        label: options[i].label,
                        selected: _statusFilter == options[i].status,
                        selectedColor: AppConstants.buyerBlue,
                        onTap: () => setState(() => _statusFilter = options[i].status),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(padding: EdgeInsets.all(20), child: SkeletonList())
                      : visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          children: [
                            const SizedBox(height: 40),
                            Icon(
                              Icons.assignment_outlined,
                              size: 44,
                              color: AppConstants.outline.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _requests.isEmpty
                                  ? l10n.loanReqMyEmpty
                                  : l10n.loanReqMyEmptyForFilter,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.4,
                                color: AppConstants.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => LoanRequestCard(
                            request: visible[i],
                            onTap: () => _open(visible[i]),
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
              title: l10n.loanReqSectionTitle,
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
