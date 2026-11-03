import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../widgets/account_card.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/view_only_banner.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/temp_password_dialog.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

class ManageAccountsScreen extends StatefulWidget {
  final String initialTab;

  const ManageAccountsScreen({super.key, this.initialTab = 'farmer'});

  @override
  State<ManageAccountsScreen> createState() => _ManageAccountsScreenState();
}

class _ManageAccountsScreenState extends State<ManageAccountsScreen>
    with TickerProviderStateMixin {
  final _repo = AccountManagementRepository();
  List<AccountEntry> _farmers = [];
  // The Management tab: the Manager first (display-only), then the Officers.
  List<AccountEntry> _management = [];
  List<PasswordResetRequest> _requests = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    // 'officer' opens the Management tab (the route name is unchanged).
    final initialIndex = widget.initialTab == 'officer' ? 1 : 0;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
    _loadAccounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      final farmerResults = await _repo.fetchAccountsByRole('farmer');
      final managerResults = await _repo.fetchAccountsByRole('admin');
      final officerResults = await _repo.fetchAccountsByRole('officer');
      final requests = await _repo.fetchPendingPasswordRequests();
      if (!mounted) return;
      setState(() {
        _farmers = farmerResults;
        _management = [...managerResults, ...officerResults];
        _requests = requests;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveRequest(PasswordResetRequest request) async {
    if (!canManageModule(StaffModule.members)) {
      showViewOnlyMessage(context);
      return;
    }
    try {
      final tempPassword = await _repo.resetUserPassword(request.userId);
      if (!mounted) return;
      await showTempPasswordDialog(
        context: context,
        name: request.fullName,
        tempPassword: tempPassword,
      );
      await _repo.resolvePasswordRequest(request.id);
      if (!mounted) return;
      _loadAccounts();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).manageAccountsResolveError,
          ),
          backgroundColor: AppConstants.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: Column(
        children: [
          SubPageTopBar(title: l10n.manageAccountsTitle, onBack: () => context.pop()),
          const ViewOnlyBanner(module: StaffModule.members),
          // The three sections: Farmers, Management (Manager and Officers),
          // Password Assistance Requests.
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
              controller: _tabController,
              labelColor: AppConstants.primaryGreen,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: AppConstants.primaryGreen,
              labelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
              tabs: [
                Tab(text: l10n.manageAccountsFarmersTab),
                Tab(text: l10n.manageAccountsManagementTab),
                Tab(
                  text: _requests.isEmpty
                      ? l10n.manageAccountsRequestsTab
                      : l10n.manageAccountsRequestsTabCount(_requests.length),
                ),
              ],
            ),
          ),
          Expanded(child: _isLoading
          ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
          : TabBarView(
              controller: _tabController,
              children: [
                _AccountList(
                  accounts: _farmers,
                  cs: cs,
                ),
                _AccountList(
                  accounts: _management,
                  cs: cs,
                  roleLabelFor: (a) => a.role == 'admin'
                      ? l10n.staffRoleManager
                      : l10n.staffRoleOfficer,
                ),
                _PasswordRequestsList(
                  requests: _requests,
                  cs: cs,
                  sagana: sagana,
                  onResolve: _resolveRequest,
                ),
              ],
            )),
        ],
      ),
    );
  }
}

class _AccountList extends StatelessWidget {
  final List<AccountEntry> accounts;
  final ColorScheme cs;

  /// Adds a role caption to each card when the list mixes roles.
  final String Function(AccountEntry)? roleLabelFor;

  const _AccountList({
    required this.accounts,
    required this.cs,
    this.roleLabelFor,
  });

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context).manageAccountsNoAccountsYet,
            style: GoogleFonts.inter(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: accounts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final account = accounts[index];
        return AccountCard(
          account: account,
          // Display-only: a card opens nothing.
          onTap: null,
          roleLabel: roleLabelFor?.call(account),
        );
      },
    );
  }
}

class _PasswordRequestsList extends StatelessWidget {
  final List<PasswordResetRequest> requests;
  final ColorScheme cs;
  final SaganaColors sagana;
  final void Function(PasswordResetRequest) onResolve;

  const _PasswordRequestsList({
    required this.requests,
    required this.cs,
    required this.sagana,
    required this.onResolve,
  });

  String _roleLabel(AppLocalizations l10n, String? role) {
    switch (role) {
      case 'farmer':
        return l10n.registerRoleFarmer;
      case 'buyer':
        return l10n.registerRoleBuyer;
      case 'officer':
        return l10n.createOfficerSectionOfficer;
      default:
        return role ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.manageAccountsRequestsHeader,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.manageAccountsRequestsHint,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.45,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (requests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const SizedBox(height: 24),
          Center(
            child: Text(
              l10n.manageAccountsNoPendingRequests,
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) return header;
        final request = requests[index - 1];
        final role = _roleLabel(l10n, request.role);
        final requested = MaterialLocalizations.of(context)
            .formatMediumDate(request.requestedAt.toLocal());
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(
                    photoUrl: request.profilePhotoUrl,
                    displayName: request.fullName,
                    radius: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  request.fullName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            if (role.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull,
                                  ),
                                ),
                                child: Text(
                                  role.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          request.username,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.manageAccountsRequestedOn(requested),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => onResolve(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(l10n.manageAccountsResolveAction),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
