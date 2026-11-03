import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/buyer_address_model.dart';
import '../../data/models/farmer_profile_model.dart';
import '../../data/models/notification_model.dart';
import 'member_profile_cards.dart';
import 'notification_day_groups.dart';
import 'notification_ui.dart';
import 'sagana_logo_mark.dart';
import 'shared_widgets.dart';
import 'skeleton.dart';

/// The three tabs a Pending Applicant sees (Home, Notifications, Profile). Plain
/// widgets that are given their data, so the screen only has to load it.

// ─────────────────────────────────────────────────────────────────────────────
// Top bar: SAGANA logo | title. The same height, spacing and bottom line on all
// three tabs.
// ─────────────────────────────────────────────────────────────────────────────

const double _kTopBarHeight = 64;

class _TopBarContent extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _TopBarContent({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        const SaganaLogoMark(key: ValueKey('pending-top-bar-logo')),
        const SaganaLogoDivider(),
        Expanded(
          child: Text(
            title,
            key: const ValueKey('pending-top-bar-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

BoxDecoration _topBarDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: context.saganaColors.navBarBackground,
    border: Border(
      bottom: BorderSide(color: cs.outline.withValues(alpha: 0.20)),
    ),
  );
}

/// The top bar for the tabs that do not scroll under it (Notifications, Profile).
class PendingTopBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const PendingTopBar({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      height: _kTopBarHeight + topPadding,
      padding: EdgeInsets.only(top: topPadding, left: 20, right: 12),
      decoration: _topBarDecoration(context),
      child: _TopBarContent(title: title, trailing: trailing),
    );
  }
}

/// The same bar, pinned at the top of the Home tab's scroll view.
class PendingTopBarDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final double topPadding;

  const PendingTopBarDelegate({required this.title, required this.topPadding});

  @override
  double get minExtent => _kTopBarHeight + topPadding;
  @override
  double get maxExtent => _kTopBarHeight + topPadding;
  @override
  bool shouldRebuild(covariant PendingTopBarDelegate old) =>
      old.title != title || old.topPadding != topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: _kTopBarHeight + topPadding,
      padding: EdgeInsets.only(top: topPadding, left: 20, right: 12),
      decoration: _topBarDecoration(context),
      child: _TopBarContent(title: title),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home — application status and progress
// ─────────────────────────────────────────────────────────────────────────────

class PendingHomeView extends StatelessWidget {
  /// First name for the greeting (the whole name's first word when the name is
  /// not stored in parts).
  final String firstName;
  final String username;
  final bool isOnline;
  final String status; // draft | pending | rejected | active
  final bool pendingAcknowledgement;
  final String? rejectionReason;
  final bool isBusy;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onAcknowledge;
  final Future<void> Function() onEditDetails;

  const PendingHomeView({
    super.key,
    required this.firstName,
    required this.username,
    required this.isOnline,
    required this.status,
    required this.pendingAcknowledgement,
    required this.rejectionReason,
    required this.isBusy,
    required this.onSubmit,
    required this.onAcknowledge,
    required this.onEditDetails,
  });

  bool get _isApproved => status == 'active' && pendingAcknowledgement;
  bool get _isRejected => status == 'rejected';
  bool get _isDraft => status == 'draft';

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: PendingTopBarDelegate(
            title: l10n.pendingHomeTitle,
            topPadding: MediaQuery.of(context).padding.top,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _welcomeBanner(l10n),
              const SizedBox(height: 16),
              if (!isOnline) ...[
                OfflineStatusCard(message: l10n.pendingOfflineBanner),
                const SizedBox(height: 16),
              ],
              _statusCard(context, cs, sagana),
              const SizedBox(height: 16),
              _ContactCard(cs: cs, sagana: sagana),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _welcomeBanner(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppConstants.primaryGreen, AppConstants.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.agriculture_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pendingWelcome(firstName),
                      key: const ValueKey('pending-welcome'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.cooperativeName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.80),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _isApproved
                ? l10n.pendingBannerApproved
                : _isRejected
                ? l10n.pendingBannerRejected
                : _isDraft
                ? l10n.pendingBannerDraft
                : l10n.pendingBannerPending,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.90),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── Status-driven action card ──────────────────────────────────────────────

  Widget _statusCard(
    BuildContext context,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final l10n = AppLocalizations.of(context);
    final Color accent;
    final String badge;
    final IconData icon;
    if (_isApproved) {
      accent = AppConstants.successGreen;
      badge = l10n.pendingBadgeApproved;
      icon = Icons.verified_rounded;
    } else if (_isRejected) {
      accent = AppConstants.errorRed;
      badge = l10n.pendingBadgeRejected;
      icon = Icons.error_outline_rounded;
    } else if (_isDraft) {
      accent = AppConstants.buyerBlue;
      badge = l10n.pendingBadgeDraft;
      icon = Icons.edit_note_rounded;
    } else {
      accent = AppConstants.warningAmber;
      badge = l10n.pendingBadgePending;
      icon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pendingApplicationStatusTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    if (username.isNotEmpty)
                      Text(
                        l10n.pendingYourUsername(username),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('pending-status-badge'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 16),

          if (_isApproved) ...[
            Text(
              l10n.pendingApprovedMessage(firstName),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            _fullButton(
              key: const ValueKey('pending-continue'),
              label: l10n.pendingContinueButton,
              icon: Icons.arrow_forward_rounded,
              color: AppConstants.successGreen,
              busy: isBusy,
              onTap: onAcknowledge,
            ),
          ] else if (_isRejected) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: AppConstants.errorRed.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pendingRejectedReasonTitle,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppConstants.errorRed,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rejectionReason?.trim().isNotEmpty == true
                        ? rejectionReason!.trim()
                        : l10n.pendingNoReasonProvided,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.pendingResubmitHint,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _outlineButton(
              key: const ValueKey('pending-edit-details'),
              label: l10n.pendingReviewEditButton,
              icon: Icons.edit_outlined,
              onTap: onEditDetails,
            ),
            const SizedBox(height: 10),
            _fullButton(
              key: const ValueKey('pending-resubmit'),
              label: l10n.pendingResubmitButton,
              icon: Icons.send_rounded,
              color: AppConstants.primaryGreen,
              busy: isBusy,
              onTap: onSubmit,
            ),
          ] else if (_isDraft) ...[
            Text(
              l10n.pendingDraftMessage,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            _outlineButton(
              key: const ValueKey('pending-edit-details'),
              label: l10n.pendingReviewEditButton,
              icon: Icons.edit_outlined,
              onTap: onEditDetails,
            ),
            const SizedBox(height: 10),
            _fullButton(
              key: const ValueKey('pending-submit'),
              label: l10n.pendingSubmitButton,
              icon: Icons.send_rounded,
              color: AppConstants.primaryGreen,
              busy: isBusy,
              onTap: onSubmit,
            ),
          ] else ...[
            // pending — progress tracker
            _ProgressStep(
              icon: Icons.check_circle_rounded,
              label: l10n.pendingStepSubmitted,
              sublabel: l10n.pendingStepSubmittedSub,
              isComplete: true,
              isActive: false,
              cs: cs,
            ),
            _ProgressConnector(isComplete: true, cs: cs),
            _ProgressStep(
              icon: Icons.hourglass_top_rounded,
              label: l10n.pendingStepReview,
              sublabel: l10n.pendingStepReviewSub,
              isComplete: false,
              isActive: true,
              cs: cs,
            ),
            _ProgressConnector(isComplete: false, cs: cs),
            _ProgressStep(
              icon: Icons.verified_rounded,
              label: l10n.pendingStepDecision,
              sublabel: l10n.pendingStepDecisionSub,
              isComplete: false,
              isActive: false,
              cs: cs,
            ),
          ],
        ],
      ),
    );
  }

  Widget _fullButton({
    Key? key,
    required String label,
    required IconData icon,
    required Color color,
    required bool busy,
    required Future<void> Function()? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        key: key,
        onPressed: (busy || onTap == null) ? null : () => onTap(),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _outlineButton({
    Key? key,
    required String label,
    required IconData icon,
    required Future<void> Function() onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        key: key,
        onPressed: () => onTap(),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isComplete;
  final bool isActive;
  final ColorScheme cs;

  const _ProgressStep({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isComplete,
    required this.isActive,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final color = isComplete
        ? AppConstants.successGreen
        : isActive
        ? AppConstants.warningAmber
        : cs.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.40)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: (isComplete || isActive)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: (isComplete || isActive)
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  sublabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressConnector extends StatelessWidget {
  final bool isComplete;
  final ColorScheme cs;
  const _ProgressConnector({required this.isComplete, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: Container(
        width: 2,
        height: 16,
        color: isComplete
            ? AppConstants.successGreen.withValues(alpha: 0.40)
            : cs.outline.withValues(alpha: 0.20),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  const _ContactCard({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.cooperativeName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ContactRow(
            icon: Icons.location_on_outlined,
            text: l10n.pendingContactAddress,
            cs: cs,
          ),
          const SizedBox(height: 8),
          _ContactRow(
            icon: Icons.calendar_month_outlined,
            text: l10n.pendingContactBod,
            cs: cs,
          ),
          const SizedBox(height: 8),
          _ContactRow(
            icon: Icons.people_alt_outlined,
            text: l10n.pendingContactMembers,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme cs;
  const _ContactRow({required this.icon, required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications — the same list, grouping and read/unread actions as the other
// roles
// ─────────────────────────────────────────────────────────────────────────────

class PendingNotificationsView extends StatelessWidget {
  final List<NotificationModel> notifications;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final void Function(NotificationModel) onTap;
  final void Function(NotificationModel) onToggleRead;
  final void Function(NotificationModel) onDelete;
  final VoidCallback onMarkAllRead;
  final VoidCallback onMarkAllUnread;

  const PendingNotificationsView({
    super.key,
    required this.notifications,
    required this.isLoading,
    required this.onRefresh,
    required this.onTap,
    required this.onToggleRead,
    required this.onDelete,
    required this.onMarkAllRead,
    required this.onMarkAllUnread,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        PendingTopBar(
          title: l10n.pendingNotificationsTitle,
          trailing: notifications.isEmpty
              ? null
              : NotificationMenuButton(
                  hasUnread: notifications.any((n) => n.isUnread),
                  hasRead: notifications.any((n) => n.isRead),
                  onMarkAllRead: onMarkAllRead,
                  onMarkAllUnread: onMarkAllUnread,
                ),
        ),
        Expanded(
          child: isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
              : RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: onRefresh,
                  child: notifications.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_none_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.pendingNoNotifications,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                    ),
                                    child: Text(
                                      l10n.pendingNoNotificationsSub,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: notificationGroupChildren<NotificationModel>(
                            items: notifications,
                            timeOf: (n) => n.createdAt,
                            l10n: l10n,
                            buildItem: (n) => NotificationCard(
                              item: n,
                              timeLabel: notificationTimeLabel(
                                l10n,
                                n.createdAt,
                              ),
                              onTap: () => onTap(n),
                              onLongPress: () => showNotificationReadSheet(
                                context,
                                isRead: n.isRead,
                                onToggle: () => onToggleRead(n),
                              ),
                              onDelete: () => onDelete(n),
                            ),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile — laid out like Manager > Members > Member Details
// ─────────────────────────────────────────────────────────────────────────────

class PendingProfileView extends StatelessWidget {
  final FarmerProfileModel profile;

  /// The address entered at registration (the default address), if any.
  final BuyerAddressModel? address;

  /// The status pill under the photo: wording and colour.
  final String statusLabel;
  final Color statusColor;
  final bool isLoading;
  final VoidCallback onSignOut;

  const PendingProfileView({
    super.key,
    required this.profile,
    required this.address,
    required this.statusLabel,
    required this.statusColor,
    required this.isLoading,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        PendingTopBar(title: l10n.pendingProfileTitle),
        Expanded(
          child: isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Photo, status, name, then Email | Phone and Date of
                      // Birth | Gender: the identity card of Member Details.
                      MemberIdentityCard(
                        profile: profile,
                        statusLabel: statusLabel,
                        statusColor: statusColor,
                        detailsTitle: l10n.pendingPersonalInfoTitle,
                      ),
                      const SizedBox(height: 16),
                      // The complete address as one piece, as entered at signup.
                      MemberResidentialAddressCard(
                        addresses: address == null ? const [] : [address!],
                        title: l10n.pendingAddressInfoTitle,
                        compact: true,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.pendingLockedFeatures,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          key: const ValueKey('pending-sign-out'),
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: Text(
                            l10n.pendingSignOut,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
