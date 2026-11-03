import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/guest_mode_service.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/farmer_top_bar.dart';
import '../../widgets/guest_prompt.dart';
import '../../widgets/shared_widgets.dart';

/// Wraps a tab screen so it is rebuilt from scratch when Guest Mode starts or
/// ends. The tab shells keep every visited tab alive; without this, a tab
/// opened as a guest would keep showing guest data after the visitor logs in.
/// [guest], when given, replaces the screen while exploring as a guest.
class GuestAware extends StatelessWidget {
  final Widget Function() signedIn;
  final Widget Function(GuestRole role)? guest;

  const GuestAware({super.key, required this.signedIn, this.guest});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GuestModeService.instance,
      builder: (context, _) {
        final mode = GuestModeService.instance;
        if (mode.isGuest && guest != null) {
          return KeyedSubtree(
            key: const ValueKey('guest'),
            child: guest!(mode.role!),
          );
        }
        return KeyedSubtree(
          key: ValueKey(mode.isGuest ? 'guest' : 'member'),
          child: signedIn(),
        );
      },
    );
  }
}

/// Shared body for the two signed-out Profile tabs and the Buyer Orders empty
/// state: an icon, a title, a message, then the supplied actions.
class _GuestBody extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  const _GuestBody({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          88,
          AppConstants.spacingSafeH,
          32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: AppConstants.primaryGreen),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile tab for a signed-out visitor (Buyer or Farmer exploration). It does
/// not redirect: opening Profile just shows this.
class GuestProfileScreen extends StatelessWidget {
  final GuestRole role;
  const GuestProfileScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isBuyer = role == GuestRole.buyer;
    void notifications() => context.promptGuest(
      (l) => l.guestNotificationsTitle,
      (l) => l.guestNotificationsMessage,
      icon: Icons.notifications_none_rounded,
    );

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          _GuestBody(
            icon: Icons.person_outline_rounded,
            title: l10n.guestProfileTitle,
            message: l10n.guestProfileMessage,
            actions: [
              const GuestAuthButtons(),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => switchGuestMode(
                  context,
                  isBuyer ? GuestRole.farmer : GuestRole.buyer,
                ),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  isBuyer ? l10n.guestSwitchToFarmer : l10n.guestSwitchToBuyer,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: isBuyer
                ? BuyerTopBar(
                    title: l10n.account,
                    onNotificationTap: notifications,
                    enableMenu: true,
                  )
                : FarmerTopBar(
                    title: l10n.navProfile,
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: notifications,
                    enableMenu: true,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Buyer Orders tab for a signed-out visitor: an empty state, never a popup.
class GuestOrdersScreen extends StatelessWidget {
  const GuestOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          _GuestBody(
            icon: Icons.receipt_long_rounded,
            title: l10n.guestOrdersTitle,
            message: l10n.guestOrdersMessage,
            actions: const [GuestAuthButtons()],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: BuyerTopBar(
              title: l10n.buyerNavOrders,
              onNotificationTap: () => context.promptGuest(
                (l) => l.guestNotificationsTitle,
                (l) => l.guestNotificationsMessage,
                icon: Icons.notifications_none_rounded,
              ),
              enableMenu: true,
            ),
          ),
        ],
      ),
    );
  }
}
