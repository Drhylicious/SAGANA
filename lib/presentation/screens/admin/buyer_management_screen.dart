import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

// ─── Buyer Model (lightweight — no separate file needed) ─────────────────────

class _BuyerModel {
  final String userId;
  final String fullName;
  final String? phoneNumber;
  final String? sitio;
  final String? profilePhotoUrl;
  final String accountStatus; // 'active' | 'inactive'
  final int totalOrders;
  final double totalSpent;
  final DateTime joinedAt;

  const _BuyerModel({
    required this.userId,
    required this.fullName,
    this.phoneNumber,
    this.sitio,
    this.profilePhotoUrl,
    required this.accountStatus,
    required this.totalOrders,
    required this.totalSpent,
    required this.joinedAt,
  });

  bool get isActive => accountStatus == 'active';

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : 'B';
  }

  String get joinedLabel {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[joinedAt.month - 1]} ${joinedAt.year}';
  }
}

// ─── Repository (inline — too small for a separate file) ─────────────────────

class _BuyerRepository {
  final _client = Supabase.instance.client;

  Future<List<_BuyerModel>> fetchBuyers() async {
    try {
      // All buyer role rows
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, status, created_at')
          .eq('role', 'buyer');

      if (roleRows.isEmpty) return [];

      final userIds = roleRows.map((r) => r['user_id'] as String).toList();
      final roleMap = {
        for (final r in roleRows) r['user_id'] as String: r,
      };

      // User info
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, phone_number, sitio, profile_photo_url')
          .inFilter('user_id', userIds);
      final infoMap = {
        for (final r in infoRows) r['user_id'] as String: r,
      };

      // Order stats per buyer
      final orderRows = await _client
          .from('orders')
          .select('buyer_id, total_price')
          .inFilter('buyer_id', userIds);
      final orderCountMap = <String, int>{};
      final orderSpentMap = <String, double>{};
      for (final r in orderRows) {
        final id = r['buyer_id'] as String;
        orderCountMap[id] = (orderCountMap[id] ?? 0) + 1;
        orderSpentMap[id] = (orderSpentMap[id] ?? 0) +
            (r['total_price'] as num).toDouble();
      }

      return userIds.map((uid) {
        final role = roleMap[uid]!;
        final info = infoMap[uid] ?? {};
        return _BuyerModel(
          userId:        uid,
          fullName:      info['full_name'] as String? ?? 'Buyer',
          phoneNumber:   info['phone_number'] as String?,
          sitio:         info['sitio'] as String?,
          profilePhotoUrl: info['profile_photo_url'] as String?,
          accountStatus: role['status'] as String? ?? 'active',
          totalOrders:   orderCountMap[uid] ?? 0,
          totalSpent:    orderSpentMap[uid] ?? 0,
          joinedAt:      DateTime.parse(role['created_at'] as String),
        );
      }).toList()
        ..sort((a, b) => b.totalOrders.compareTo(a.totalOrders));
    } catch (_) {
      return [];
    }
  }

  Future<void> setStatus(String userId, String status) async {
    await _client
        .from('user_roles')
        .update({'status': status})
        .eq('user_id', userId);
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  final _repo       = _BuyerRepository();
  final _searchCtrl = TextEditingController();

  List<_BuyerModel> _buyers      = [];
  bool _isLoading = true;
  bool _isOnline  = true;
  String _searchQuery = '';
  bool? _activeFilter; // null=all, true=active, false=inactive

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged
        .listen((v) { if (mounted) setState(() => _isOnline = v); });
    _searchCtrl.addListener(() =>
        setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await _repo.fetchBuyers();
    if (!mounted) return;
    setState(() { _buyers = data; _isLoading = false; });
  }

  List<_BuyerModel> get _filtered {
    var list = _buyers;
    if (_activeFilter != null) {
      list = list.where((b) => b.isActive == _activeFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((b) =>
          b.fullName.toLowerCase().contains(q) ||
          (b.phoneNumber?.contains(q) ?? false) ||
          (b.sitio?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  int get _activeCount  => _buyers.where((b) => b.isActive).length;
  int get _inactiveCount => _buyers.where((b) => !b.isActive).length;

  void _showActions(_BuyerModel buyer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionsSheet(
        buyer: buyer,
        isOnline: _isOnline,
        onSendNotification: () {
          Navigator.pop(context);
          context.push(AppRoutes.announcementDashboard);
        },
        onViewOrders: () => Navigator.pop(context),
        onToggleStatus: () async {
          Navigator.pop(context);
          await _repo.setStatus(
            buyer.userId,
            buyer.isActive ? 'inactive' : 'active',
          );
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana  = context.saganaColors;
    final cs      = Theme.of(context).colorScheme;
    final visible = _filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                          children: [

                            // ── Summary pills ────────────────────────────
                            Row(children: [
                              _Pill(label: 'Total',
                                  value: _buyers.length,
                                  color: cs.primary,
                                  active: _activeFilter == null,
                                  onTap: () => setState(
                                      () => _activeFilter = null),
                                  cs: cs, sagana: sagana),
                              const SizedBox(width: 8),
                              _Pill(label: 'Active',
                                  value: _activeCount,
                                  color: AppConstants.successGreen,
                                  active: _activeFilter == true,
                                  onTap: () => setState(
                                      () => _activeFilter = true),
                                  cs: cs, sagana: sagana),
                              const SizedBox(width: 8),
                              _Pill(label: 'Inactive',
                                  value: _inactiveCount,
                                  color: cs.outline,
                                  active: _activeFilter == false,
                                  onTap: () => setState(
                                      () => _activeFilter = false),
                                  cs: cs, sagana: sagana),
                            ]),
                            const SizedBox(height: 14),

                            // ── Search ───────────────────────────────────
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search buyer name or phone...',
                                hintStyle: GoogleFonts.inter(
                                    fontSize: 13, color: cs.outline),
                                prefixIcon: Icon(Icons.search_rounded,
                                    color: cs.outline, size: 22),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.close_rounded,
                                            color: cs.outline, size: 18),
                                        onPressed: () =>
                                            _searchCtrl.clear())
                                    : null,
                              ),
                              style: GoogleFonts.inter(
                                  fontSize: 14, color: cs.onSurface),
                            ),
                            const SizedBox(height: 16),

                            // ── Result count ─────────────────────────────
                            Text('${visible.length} buyer${visible.length == 1 ? '' : 's'}',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                            const SizedBox(height: 12),

                            // ── Buyer cards ──────────────────────────────
                            if (visible.isEmpty)
                              _EmptyState(cs: cs)
                            else
                              ...visible.map((b) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _BuyerCard(
                                      buyer: b,
                                      cs: cs,
                                      sagana: sagana,
                                      onMoreTap: () => _showActions(b),
                                    ),
                                  )),
                          ],
                        ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopAppBar(
              buyerCount: _buyers.length,
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final int buyerCount;
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopAppBar({required this.buyerCount, required this.onBack,
    required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text('Buyer Management',
                    style: GoogleFonts.poppins(fontSize: 18,
                        fontWeight: FontWeight.w700, color: cs.primary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.buyerBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull),
                ),
                child: Text('$buyerCount buyers',
                    style: GoogleFonts.inter(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.buyerBlue)),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Filter Pill ──────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _Pill({required this.label, required this.value,
    required this.color, required this.active, required this.onTap,
    required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(color: active
              ? color : cs.outline.withValues(alpha: 0.15)),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(
                  color: active ? Colors.white : color,
                  shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text('$label: $value',
              style: GoogleFonts.inter(fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : cs.onSurface)),
        ]),
      ),
    );
  }
}

// ─── Buyer Card ───────────────────────────────────────────────────────────────

class _BuyerCard extends StatelessWidget {
  final _BuyerModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onMoreTap;
  const _BuyerCard({required this.buyer, required this.cs,
    required this.sagana, required this.onMoreTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: buyer.isActive
            ? cs.outline.withValues(alpha: 0.10)
            : cs.outline.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buyer.isActive
                  ? AppConstants.buyerBlue.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest,
            ),
            child: Center(child: Text(buyer.initials,
                style: GoogleFonts.poppins(fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: buyer.isActive
                        ? AppConstants.buyerBlue
                        : cs.outline))),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(buyer.fullName,
                        style: GoogleFonts.poppins(fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: buyer.isActive
                                ? cs.onSurface
                                : cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: buyer.isActive
                          ? AppConstants.successGreen.withValues(alpha: 0.12)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                    ),
                    child: Text(buyer.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: GoogleFonts.inter(fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: buyer.isActive
                                ? AppConstants.successGreen
                                : cs.outline)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  '${buyer.phoneNumber ?? 'No phone'}'
                  '${buyer.sitio != null ? '  •  ${buyer.sitio}' : ''}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 13, color: cs.outline),
                  const SizedBox(width: 4),
                  Text('${buyer.totalOrders} order${buyer.totalOrders == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                  if (buyer.totalSpent > 0) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.payments_outlined,
                        size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Text('₱${buyer.totalSpent.toStringAsFixed(0)} total',
                        style: GoogleFonts.poppins(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary)),
                  ],
                  const Spacer(),
                  Text('Since ${buyer.joinedLabel}',
                      style: GoogleFonts.inter(
                          fontSize: 10, color: cs.outline)),
                ]),
              ],
            ),
          ),

          const SizedBox(width: 8),
          GestureDetector(
            onTap: onMoreTap,
            child: Icon(Icons.more_vert_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(Icons.person_search_rounded,
            size: 48, color: cs.outline.withValues(alpha: 0.35)),
        const SizedBox(height: 12),
        Text('No buyers found',
            style: GoogleFonts.poppins(fontSize: 14,
                fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('Buyers appear here once they register in the app.',
            style: GoogleFonts.inter(
                fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

// ─── Actions Sheet ────────────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  final _BuyerModel buyer;
  final bool isOnline;
  final VoidCallback onSendNotification;
  final VoidCallback onViewOrders;
  final VoidCallback onToggleStatus;
  const _ActionsSheet({required this.buyer, required this.isOnline,
    required this.onSendNotification, required this.onViewOrders,
    required this.onToggleStatus});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(
                    AppConstants.radiusFull)))),
          const SizedBox(height: 16),
          Text(buyer.fullName,
              style: GoogleFonts.poppins(fontSize: 16,
                  fontWeight: FontWeight.w700, color: cs.onSurface)),
          Text('${buyer.totalOrders} orders  •  Since ${buyer.joinedLabel}',
              style: GoogleFonts.inter(
                  fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          _ActionRow(icon: Icons.history_rounded,
              label: 'View Order History',
              onTap: onViewOrders, cs: cs),
          _ActionRow(icon: Icons.campaign_outlined,
              label: 'Send Notification',
              onTap: onSendNotification, cs: cs),
          _ActionRow(
            icon: buyer.isActive
                ? Icons.block_rounded
                : Icons.check_circle_outline_rounded,
            label: buyer.isActive
                ? 'Deactivate Account'
                : 'Reactivate Account',
            onTap: isOnline ? onToggleStatus : null,
            cs: cs,
            isDestructive: buyer.isActive,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final bool isDestructive;
  const _ActionRow({required this.icon, required this.label,
    this.onTap, required this.cs, this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? cs.outline
        : (isDestructive ? cs.error : cs.onSurface);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Text(label,
              style: GoogleFonts.inter(fontSize: 14, color: color)),
        ]),
      ),
    );
  }
}
