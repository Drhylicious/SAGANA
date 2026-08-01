import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

class BuyerAccountScreen extends StatefulWidget {
  const BuyerAccountScreen({super.key});

  @override
  State<BuyerAccountScreen> createState() => _BuyerAccountScreenState();
}

class _BuyerAccountScreenState extends State<BuyerAccountScreen> {
  final _repository = BuyerProfileRepository();
  final _notificationRepo = NotificationRepository();

  bool _isLoading = true;
  BuyerProfileModel? _profile;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repository.fetchProfile(),
      _notificationRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as BuyerProfileModel?;
      _unreadCount = results[1] as int;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final hasOrders = (_profile?.totalOrders ?? 0) > 0;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 40,
                          ),
                          children: [
                            _buildIdentityCard(l10n),
                            const SizedBox(height: 20),
                            SectionLabel(label: l10n.purchaseSummary),
                            hasOrders ? _buildStatsRow(l10n) : _buildFirstOrderPrompt(context, l10n),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: BuyerTopBar(
              title: l10n.account,
              unreadCount: _unreadCount,
              onNotificationTap: () => context.push(AppRoutes.buyerNotifications),
              onSettingsTap: () => context.push(AppRoutes.buyerSettings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(AppLocalizations l10n) {
    final profile = _profile;
    return GlassCard(
      child: Row(
        children: [
          ProfileAvatar(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? l10n.buyerDefaultName,
            radius: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile?.fullName ?? l10n.buyerDefaultName,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(profile?.email ?? '',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 2),
                if (profile != null)
                  Text(profile.memberSinceLabel,
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Purchase stats — tappable, jumping into My Orders pre-filtered.
  // NOTE: this depends on a new optional `initialTabIndex` param on
  // MyOrdersScreen and a matching router change (both below) — flagging
  // again here since it's the one change from the last proposal round
  // that touches an existing, already-tested screen's public API.

  Widget _buildStatsRow(AppLocalizations l10n) {
    final profile = _profile;
    return Row(
      children: [
        Expanded(
          child: _statTile(l10n.statOrders, '${profile?.totalOrders ?? 0}',
              onTap: () => context.go(AppRoutes.myOrders)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(l10n.statCompleted, '${profile?.completedOrders ?? 0}',
              onTap: () => context.go(AppRoutes.myOrders, extra: 2)), // Completed tab index
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(l10n.statSpent, '₱${(profile?.totalSpent ?? 0).toStringAsFixed(0)}'),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, {VoidCallback? onTap}) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
        ],
      ),
    );
    if (onTap == null) return tile;
    return InkWell(borderRadius: BorderRadius.circular(AppConstants.radiusLg), onTap: onTap, child: tile);
  }

  Widget _buildFirstOrderPrompt(BuildContext context, AppLocalizations l10n) {
    return GlassCard(
      child: Column(
        children: [
          Icon(Icons.shopping_basket_outlined, size: 36, color: AppConstants.primaryGreen.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(l10n.buyerNoOrdersTitle, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.buyerNoOrdersSubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: l10n.browseMarketplace, onPressed: () => context.go(AppRoutes.marketplaceBrowse)),
          ),
        ],
      ),
    );
  }
}

