import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/models/buyer_activity_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/buyer_activity_card.dart';
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
  final _buyerOrderRepo = BuyerOrderRepository();

  bool _isLoading = true;
  BuyerProfileModel? _profile;
  int _unreadCount = 0;

  bool _isActivityLoading = true;
  List<BuyerActivityItem> _recentActivity = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadActivity();
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

  // Added alongside the notification-staleness fix: a lightweight refresh
  // for just the unread count, so returning from the notifications screen
  // doesn't need to re-fetch the profile via the full _load().
  Future<void> _loadUnreadCount() async {
    final count = await _notificationRepo.fetchUnreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  Future<void> _loadActivity() async {
    setState(() => _isActivityLoading = true);
    // Pool wider than the final 6 shown (5 of each) so a recent burst of
    // one category (e.g. several order updates) doesn't crowd out the
    // other category entirely before the merge+sort below picks the
    // overall 6 most recent.
    final results = await Future.wait([
      _buyerOrderRepo.fetchRecentOrderActivity(limit: 5),
      _repository.fetchRecentProfileActivity(limit: 5),
    ]);
    if (!mounted) return;
    final combined = [...results[0], ...results[1]]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _recentActivity = combined.take(6).toList();
      _isActivityLoading = false;
    });
  }

  Future<void> _refreshAll() => Future.wait([_load(), _loadActivity()]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final hasOrders = (_profile?.totalOrders ?? 0) > 0;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      drawer: AppNavigationDrawer(
        photoUrl: _profile?.profilePhotoUrl,
        displayName: _profile?.fullName ?? 'Buyer',
        contactEmail: _profile?.contactEmail,
        phoneNumber: _profile?.phoneNumber,
        onEditProfile: () async {
          Navigator.pop(context);
          await context.push(AppRoutes.buyerEditProfile);
          if (mounted) _refreshAll();
        },
        onMyAddresses: () async {
          Navigator.pop(context);
          await context.push(AppRoutes.myAddresses);
          if (mounted) _refreshAll();
        },
        onSignOut: () => confirmBuyerSignOut(context),
        onAboutSagana: () => context.push(AppRoutes.aboutSagana),
        onAboutOrganization: () => context.push(AppRoutes.aboutCooperative),
        onPrivacyPolicy: () => context.push(AppRoutes.privacyPolicy),
        onTermsOfUse: () => context.push(AppRoutes.termsOfUse),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _refreshAll,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 40,
                          ),
                          children: [
                            _buildIdentityCard(l10n),
                            const SizedBox(height: 20),
                            SectionLabel(label: l10n.purchaseSummary),
                            hasOrders ? _buildStatsRow(l10n) : _buildFirstOrderPrompt(context, l10n),
                            const SizedBox(height: 20),
                            _RecentActivitySection(
                              items: _recentActivity,
                              isLoading: _isActivityLoading,
                              onViewAll: () => context.push(AppRoutes.buyerRecentActivity),
                            ),
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
              onNotificationTap: () async {
                await context.push(AppRoutes.buyerNotifications);
                _loadUnreadCount();
              },
              enableMenu: true,
            ),
          ),
        ],
      ),
    );
  }

  // Mirrors FarmerProfileScreen's _ProfileHeaderCard visual language
  // (gradient glass card, avatar + name + contact line) without copying
  // Farmer-only content — no status badge (accountStatus is deliberately
  // never fetched for the buyer's own profile, see BuyerProfileModel), no
  // "Member since" line, and the contact line shows contactEmail (the
  // buyer's real, self-entered email) rather than the synthetic
  // auth-only email — omitted entirely when neither contactEmail nor
  // phoneNumber is set, never filled with a placeholder.
  Widget _buildIdentityCard(AppLocalizations l10n) {
    final profile = _profile;
    final hasContactEmail = profile?.contactEmail?.isNotEmpty ?? false;
    final hasPhone = profile?.phoneNumber?.isNotEmpty ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.80),
                AppConstants.buyerBlue.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: AppConstants.buyerBlue.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.06), blurRadius: 16),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
                  gradient: LinearGradient(
                    colors: [AppConstants.buyerBlue, AppConstants.buyerBlue.withValues(alpha: 0.35)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppConstants.onSurface)),
                          if (hasContactEmail || hasPhone) ...[
                            const SizedBox(height: 4),
                            // Built as a list rather than two independent
                            // `if` blocks with a fixed gap between them —
                            // a fixed gap before the phone line left a
                            // phantom 3px gap under the name whenever only
                            // the phone (no email) was set. Interspersing
                            // the gap only *between* present lines keeps
                            // either single-line or both-lines cases
                            // equally compact.
                            for (final (i, w) in [
                              if (hasContactEmail) _contactLine(Icons.email_outlined, profile!.contactEmail!),
                              if (hasPhone) _contactLine(Icons.phone_outlined, profile!.phoneNumber!),
                            ].indexed) ...[
                              if (i > 0) const SizedBox(height: 2),
                              w,
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppConstants.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
        ),
      ],
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
              icon: Icons.shopping_bag_rounded, color: AppConstants.buyerBlue,
              onTap: () => context.go(AppRoutes.myOrders)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(l10n.statCompleted, '${profile?.completedOrders ?? 0}',
              icon: Icons.check_circle_rounded, color: AppConstants.successGreen,
              onTap: () => context.go(AppRoutes.myOrders, extra: 2)), // Completed tab index
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(l10n.statSpent, '₱${(profile?.totalSpent ?? 0).toStringAsFixed(0)}',
              icon: Icons.payments_rounded, color: AppConstants.primaryGreen),
        ),
      ],
    );
  }

  // KPI-tile visual language — mirrors Admin Marketplace Dashboard's
  // _KpiStrip/_KpiTile (icon chip + label + value, tinted border/bg per
  // stat) rather than the plain value/label tile used previously, so
  // Purchase Summary reads as the same kind of stat card used elsewhere
  // in SAGANA.
  Widget _statTile(String label, String value, {required IconData icon, required Color color, VoidCallback? onTap}) {
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: AppConstants.onSurface)),
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

// Inline preview of the buyer's most recent activity — same date-grouped
// card presentation as the full BuyerRecentActivityScreen (shared via
// buyer_activity_card.dart) so the two surfaces read as one consistent
// feature rather than two different designs for the same data.
class _RecentActivitySection extends StatelessWidget {
  final List<BuyerActivityItem> items;
  final bool isLoading;
  final VoidCallback onViewAll;

  const _RecentActivitySection({
    required this.items,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SectionLabel(label: l10n.buyerActivityTitle),
            GestureDetector(
              onTap: onViewAll,
              child: Text(l10n.buyerActivityViewAll,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (isLoading)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 36, color: AppConstants.outline.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text(l10n.buyerActivityEmpty, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          )
        else
          ...groupBuyerActivityByDate(items, l10n).entries.map(
                (e) => BuyerActivityDateGroup(label: e.key, items: e.value),
              ),
      ],
    );
  }
}