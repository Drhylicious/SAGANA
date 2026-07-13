import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import '../../routes/app_routes.dart';

class AdminTopBar extends StatelessWidget {
  final String title;
  final int unreadCount;
  final VoidCallback? onBroadcastTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;

  const AdminTopBar({
    super.key,
    required this.title,
    this.unreadCount = 0,
    this.onBroadcastTap,
    this.onNotificationTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final sagana = Theme.of(context).extension<SaganaColors>() ?? SaganaColors.light;
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              // SAGANA icon (branding only — non-interactive)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // subtle light-green background for the branding circle
                  color: AppConstants.primaryContainer.withValues(alpha: 0.95),
                  // softened border
                  border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/sagana_icon.png',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Title
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Broadcast
              GestureDetector(
                onTap: onBroadcastTap ?? () => Navigator.pushNamed(context, AppRoutes.announcementDashboard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.campaign_rounded, color: cs.primary, size: 26),
                ),
              ),

              const SizedBox(width: 6),

              // Notifications (with unread badge)
              GestureDetector(
                onTap: onNotificationTap ?? () => Navigator.pushNamed(context, AppRoutes.adminNotifications),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications_outlined, color: cs.primary, size: 26),
                    if (unreadCount > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Profile / avatar
              GestureDetector(
                onTap: onProfileTap ?? () => Navigator.pushNamed(context, AppRoutes.adminProfile),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primaryContainer,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.80), width: 2),
                  ),
                  child: const Icon(Icons.person_rounded, color: AppConstants.onPrimaryContainer, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminTopBarDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final int unreadCount;
  final VoidCallback? onBroadcastTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;

  const AdminTopBarDelegate({
    required this.title,
    this.unreadCount = 0,
    this.onBroadcastTap,
    this.onNotificationTap,
    this.onProfileTap,
  });

  @override
  double get minExtent => 64;
  @override
  double get maxExtent => 64;
  @override
  bool shouldRebuild(covariant AdminTopBarDelegate old) => old.unreadCount != unreadCount || old.title != title;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return AdminTopBar(
      title: title,
      unreadCount: unreadCount,
      onBroadcastTap: onBroadcastTap,
      onNotificationTap: onNotificationTap,
      onProfileTap: onProfileTap,
    );
  }
}
