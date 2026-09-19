import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/temp_password_dialog.dart';

class ManageAccountsScreen extends StatefulWidget {
  final String initialTab;

  const ManageAccountsScreen({
    super.key,
    this.initialTab = 'farmer',
  });

  @override
  State<ManageAccountsScreen> createState() => _ManageAccountsScreenState();
}

class _ManageAccountsScreenState extends State<ManageAccountsScreen> with TickerProviderStateMixin {
  final _repo = AccountManagementRepository();
  List<AccountEntry> _farmers = [];
  List<AccountEntry> _officers = [];
  List<PasswordResetRequest> _requests = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    final initialIndex = widget.initialTab == 'officer' ? 1 : 0;
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
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
      final officerResults = await _repo.fetchAccountsByRole('officer');
      final requests = await _repo.fetchPendingPasswordRequests();
      if (!mounted) return;
      setState(() {
        _farmers = farmerResults;
        _officers = officerResults;
        _requests = requests;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveRequest(PasswordResetRequest request) async {
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
          content: Text(AppLocalizations.of(context).manageAccountsResolveError),
          backgroundColor: AppConstants.errorRed,
        ),
      );
    }
  }

  void _showAccountActions(AccountEntry account) {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (_) => ManagementModalShell(
        title: account.name,
        subtitle: account.username,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _resetPassword(account);
              },
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(
                  children: [
                    const Icon(Icons.lock_reset_rounded, color: AppConstants.primaryGreen),
                    const SizedBox(width: 12),
                    Text(
                      l10n.farmerMgmtActionResetPassword,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword(AccountEntry account) async {
    try {
      final tempPassword = await _repo.resetUserPassword(account.userId);
      if (!mounted) return;
      await showTempPasswordDialog(
        context: context,
        name: account.name,
        tempPassword: tempPassword,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).farmerMgmtResetPasswordError),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l10n.manageAccountsTitle,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: [
            const Tab(text: 'Farmers'),
            const Tab(text: 'Officer'),
            Tab(text: _requests.isEmpty
                ? l10n.manageAccountsRequestsTab
                : l10n.manageAccountsRequestsTabCount(_requests.length)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
          : TabBarView(
              controller: _tabController,
              children: [
                _AccountList(accounts: _farmers, cs: cs, sagana: sagana, onTap: _showAccountActions),
                _AccountList(accounts: _officers, cs: cs, sagana: sagana, onTap: _showAccountActions),
                _PasswordRequestsList(requests: _requests, cs: cs, sagana: sagana, onResolve: _resolveRequest),
              ],
            ),
    );
  }
}

class _AccountList extends StatelessWidget {
  final List<AccountEntry> accounts;
  final ColorScheme cs;
  final SaganaColors sagana;
  final void Function(AccountEntry) onTap;

  const _AccountList({
    required this.accounts,
    required this.cs,
    required this.sagana,
    required this.onTap,
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
        return InkWell(
          onTap: () => onTap(account),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              ProfileAvatar(
                photoUrl: account.profilePhotoUrl,
                displayName: account.name,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.username,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: account.status == 'active' ? AppConstants.successGreen.withValues(alpha: 0.12) : cs.outline.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  account.role,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: account.status == 'active' ? AppConstants.successGreen : cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          ),
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

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).manageAccountsNoPendingRequests,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = requests[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                child: Icon(Icons.lock_reset_rounded, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.fullName,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(request.username,
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => onResolve(request),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(AppLocalizations.of(context).manageAccountsResolveAction),
              ),
            ],
          ),
        );
      },
    );
  }
}