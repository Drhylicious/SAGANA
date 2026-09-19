import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/services/admin_profile_state_service.dart';
import '../../data/services/auth_service.dart';
import '../../routes/app_routes.dart';
import 'app_dialog.dart';
import 'profile_avatar.dart';
import 'shared_widgets.dart';

/// Shared Sign Out confirmation for every Admin screen that hosts the
/// Navigation Drawer — reproduces AdminSettingsScreen's exact confirm ->
/// clear profile state -> logout -> return to Login flow, so the Drawer's
/// Sign Out row behaves identically no matter which root screen it was
/// opened from.
Future<void> confirmAdminSignOut(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await AppDialog.show<bool>(
    context: context,
    child: ConfirmDialog(
      title: l10n.adminProfileSignOutTitle,
      message: l10n.adminProfileSignOutMessage,
      confirmLabel: l10n.adminProfileSignOut,
      cancelLabel: l10n.issueLoanCancel,
    ),
  );
  if (confirmed == true) {
    AdminProfileStateService.instance.clear();
    await AuthService.logout();
    if (context.mounted) context.go(AppRoutes.login);
  }
}

class AdminTopBar extends StatelessWidget {
  final String title;
  final int unreadCount;
  final VoidCallback? onBroadcastTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  // Whether the SAGANA icon opens the Navigation Drawer. Deliberately a
  // bool rather than a caller-supplied VoidCallback: Scaffold.of(context)
  // must be called with a context that is a DESCENDANT of the Scaffold
  // being opened, not the screen's own outer build context (which sits
  // above the Scaffold it's about to return) — so this must be resolved
  // from AdminTopBar's own build context below, not from the caller.
  final bool enableMenu;

  const AdminTopBar({
    super.key,
    required this.title,
    this.unreadCount = 0,
    this.onBroadcastTap,
    this.onNotificationTap,
    this.onProfileTap,
    this.enableMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final profileState = AdminProfileStateService.instance;
    final sagana = Theme.of(context).extension<SaganaColors>() ?? SaganaColors.light;
    final cs = Theme.of(context).colorScheme;

    if (profileState.profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (profileState.profile == null) {
          unawaited(profileState.refresh());
        }
      });
    }

    return AnimatedBuilder(
      animation: profileState,
      builder: (context, _) {
        final displayName = profileState.fullName ?? 'Admin';
        final profilePhotoUrl = profileState.profilePhotoUrl;

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
                  // SAGANA icon — opens the Navigation Drawer when
                  // enableMenu is set (root/primary screens only); stays
                  // branding-only, non-interactive otherwise, so
                  // secondary screens reusing this bar are unaffected.
                  GestureDetector(
                    onTap: enableMenu ? () => Scaffold.of(context).openDrawer() : null,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.95),
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
                    onTap: onBroadcastTap ?? () => context.push(AppRoutes.announcementDashboard),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.campaign_rounded, color: cs.primary, size: 26),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Notifications (with unread badge)
                  GestureDetector(
                    onTap: onNotificationTap ?? () => context.push(AppRoutes.adminNotifications),
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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.80), width: 2),
                    ),
                    child: ProfileAvatar(
                      photoUrl: profilePhotoUrl,
                      displayName: displayName,
                      radius: 19,
                      onTap: onProfileTap ?? () => context.push(AppRoutes.adminProfile),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AdminTopBarDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final int unreadCount;
  final VoidCallback? onBroadcastTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final bool enableMenu;

  const AdminTopBarDelegate({
    required this.title,
    this.unreadCount = 0,
    this.onBroadcastTap,
    this.onNotificationTap,
    this.onProfileTap,
    this.enableMenu = false,
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
      enableMenu: enableMenu,
    );
  }
}