import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';

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
  final _client = Supabase.instance.client;
  List<_AccountEntry> _farmers = [];
  List<_AccountEntry> _staff = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    final initialIndex = widget.initialTab == 'admin' ? 1 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex);
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
      final roles = await _client.from('user_roles').select('user_id, role, status').order('role');
      final accountEntries = <_AccountEntry>[];
      for (final row in roles) {
        final role = row['role'] as String?;
        final userId = row['user_id'] as String?;
        if (userId == null || role == null) continue;
        final userInfo = await _client
            .from('user_information')
            .select('full_name, username')
            .eq('user_id', userId)
            .maybeSingle();
        final name = userInfo?['full_name'] as String? ?? 'Unknown';
        final username = userInfo?['username'] as String? ?? '—';
        accountEntries.add(_AccountEntry(
          userId: userId,
          name: name,
          username: username,
          role: role,
          status: row['status'] as String? ?? 'active',
        ));
      }

      if (!mounted) return;
      setState(() {
        _farmers = accountEntries.where((entry) => entry.role == 'farmer').toList();
        _staff = accountEntries.where((entry) => entry.role == 'staff').toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'Manage Accounts',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [Tab(text: 'Farmers'), Tab(text: 'Staff')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
          : TabBarView(
              controller: _tabController,
              children: [
                _AccountList(accounts: _farmers, cs: cs, sagana: sagana),
                _AccountList(accounts: _staff, cs: cs, sagana: sagana),
              ],
            ),
    );
  }
}

class _AccountList extends StatelessWidget {
  final List<_AccountEntry> accounts;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _AccountList({required this.accounts, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No accounts found yet.',
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
                child: Icon(Icons.person_rounded, color: cs.primary),
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
        );
      },
    );
  }
}

class _AccountEntry {
  final String userId;
  final String name;
  final String username;
  final String role;
  final String status;

  const _AccountEntry({
    required this.userId,
    required this.name,
    required this.username,
    required this.role,
    required this.status,
  });
}
