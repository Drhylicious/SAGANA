import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/services/auth_service.dart';
import '../../routes/app_routes.dart';
import 'app_dialog.dart';
import 'shared_widgets.dart';

/// Shared Sign Out confirmation for every Buyer screen that hosts the
/// Navigation Drawer — mirrors BuyerSettingsScreen's existing private
/// _LogoutConfirmDialog content and flow (that widget is private to its
/// file, so this reproduces it via the shared ConfirmDialog rather than
/// exporting it) so the Drawer's Sign Out row behaves identically.
Future<void> confirmBuyerSignOut(BuildContext context) async {
  final confirmed = await AppDialog.show<bool>(
    context: context,
    child: const ConfirmDialog(
      title: 'Log Out?',
      message: "You'll need to sign in again to place new orders.",
      confirmLabel: 'Log Out',
    ),
  );
  if (confirmed == true) {
    await AuthService.logout();
    if (context.mounted) context.go(AppRoutes.login);
  }
}

/// Shared top bar for all primary Buyer screens (Browse, Orders, Prices,
/// Account) — the Buyer-module analog of AdminTopBar/FarmerTopBar.
/// Secondary screens (Listing Details, Order Detail, Cart, Edit Profile,
/// Notifications, Settings) do NOT use this — they keep their existing
/// plain back-button AppBar. Terminal/receipt screens (Order Success,
/// Cart Checkout Result) intentionally use neither.
///
/// [onSettingsTap] is nullable and only ever passed by BuyerAccountScreen —
/// every other primary screen omits it, so the gear only renders where
/// it was actually asked for, from one shared component rather than
/// four independent guesses.
class BuyerTopBar extends StatelessWidget {
  final String title;
  final int unreadCount;
  final VoidCallback onNotificationTap;
  final VoidCallback? onSettingsTap;
  // A bool, not a caller-supplied VoidCallback: Scaffold.of(context) must
  // be called with a context that is a DESCENDANT of the Scaffold being
  // opened, not the screen's own outer build context — so this is
  // resolved from BuyerTopBar's own build context, not the caller's.
  final bool enableMenu;

  const BuyerTopBar({
    super.key,
    required this.title,
    required this.onNotificationTap,
    this.unreadCount = 0,
    this.onSettingsTap,
    this.enableMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
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
              // SAGANA icon — identical implementation to AdminTopBar's,
              // opens the Navigation Drawer when enableMenu is set.
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
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_outlined, color: cs.primary, size: 26),
                    onPressed: onNotificationTap,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IgnorePointer(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed,
                            shape: BoxShape.circle,
                            border: Border.all(color: sagana.glassBackground, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (onSettingsTap != null)
                IconButton(
                  icon: Icon(Icons.settings_outlined, color: cs.primary, size: 26),
                  onPressed: onSettingsTap,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
