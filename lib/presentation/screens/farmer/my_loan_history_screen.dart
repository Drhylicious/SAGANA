import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/loan_sorting.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/farmer_loan_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';

/// Farmer > Input Loans > Loan History > View All.
///
/// Every loan the Farmer has, most recent first (by the date it was issued), with
/// the same All / Active / Overdue / Paid chips as Manager > Loan History. The
/// chip counts are computed from the same list the cards come from.
class MyLoanHistoryScreen extends StatefulWidget {
  const MyLoanHistoryScreen({super.key});

  @override
  State<MyLoanHistoryScreen> createState() => _MyLoanHistoryScreenState();
}

class _MyLoanHistoryScreenState extends State<MyLoanHistoryScreen> {
  final _repo = LoanRepository();

  final _searchCtrl = TextEditingController();

  List<LoanModel> _loans = [];
  String _search = '';
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final loans = await _repo.fetchLoans();
    if (!mounted) return;
    setState(() {
      _loans = loansNewestFirst(loans);
      _isLoading = false;
    });
  }

  /// The loans that match the search box (all of them when it is empty). The
  /// status chips then narrow THESE, so the search and the chips always work
  /// together.
  List<LoanModel> get _searched => loansMatchingId(_loans, _search);

  /// The number on a chip: how many of the searched loans it would show, so the
  /// counts always match the list.
  int _count(String? status) => status == null
      ? _searched.length
      : _searched.where((l) => l.status == status).length;

  List<LoanModel> get _visible => _statusFilter == null
      ? _searched
      : _searched.where((l) => l.status == _statusFilter).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visible = _visible;

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
              // 1. Search by Loan ID
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: l10n.loanMySearchHint,
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                    prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              // 2. Status chips (the same ones as before), counting what the search finds
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: LoanStatusChips(
                  active: _statusFilter,
                  onChanged: (s) => setState(() => _statusFilter = s),
                  counts: {
                    null: _count(null),
                    'active': _count('active'),
                    'overdue': _count('overdue'),
                    'paid': _count('paid'),
                  },
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                      : visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 40),
                            LoanEmptyNote(
                              icon: Icons.agriculture_outlined,
                              text: _loans.isEmpty
                                  ? l10n.loanMyNoLoans
                                  : (_search.trim().isNotEmpty && _searched.isEmpty
                                        ? l10n.loanMySearchNoMatch
                                        : l10n.loanMyNoLoansForFilter),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => FarmerLoanCard(loan: visible[i]),
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
              title: l10n.loanMyHistoryTitle,
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
