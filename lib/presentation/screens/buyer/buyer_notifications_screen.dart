import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/notification_day_groups.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';

// Buyer-local time-ago formatter — deliberately not modifying
// NotificationModel.timeAgo since that getter is shared across
// Admin/Farmer/Buyer notification screens. Mirrors its exact branching
// logic, just localized, using the model's public createdAt field.
String _buyerNotifTimeAgo(DateTime createdAt, AppLocalizations l10n) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 60) return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.buyerNotifTimeHoursAgo(diff.inHours);
  if (diff.inDays == 1) return l10n.buyerNotifTimeYesterday;
  return l10n.buyerNotifTimeDaysAgo(diff.inDays);
}

class BuyerNotificationsScreen extends StatefulWidget {
  const BuyerNotificationsScreen({super.key});

  @override
  State<BuyerNotificationsScreen> createState() =>
      _BuyerNotificationsScreenState();
}

class _BuyerNotificationsScreenState extends State<BuyerNotificationsScreen> {
  final _repository = NotificationRepository();

  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  List<NotificationModel> _all = [];

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final notifications = await _repository.fetchNotifications();
    if (!mounted) return;
    setState(() {
      _all = notifications;
      _isLoading = false;
    });
  }

  bool _offlineBlocked() {
    if (_isOnline) return false;
    AppToast.show(context, AppLocalizations.of(context).offlineBuyerBody);
    return true;
  }

  Future<void> _markAsRead(NotificationModel n) async {
    if (n.isRead || _offlineBlocked()) return;
    setState(() {
      final index = _all.indexWhere((x) => x.id == n.id);
      if (index != -1) _all[index] = n.copyWith(isRead: true);
    });
    await _repository.markAsRead(n.id, queueWhenOffline: false);
  }

  Future<void> _onNotifTap(NotificationModel n) async {
    await _markAsRead(n);
    if (!mounted) return;
    if (n.routeOnTap != null) {
      if (n.routeExtra != null) {
        context.push(n.routeOnTap!, extra: n.routeExtra);
      } else {
        context.push(n.routeOnTap!);
      }
    }
  }

  Future<void> _delete(NotificationModel n) async {
    if (_offlineBlocked()) return;
    setState(() => _all.removeWhere((x) => x.id == n.id));
    await _repository.deleteNotification(n.id, queueWhenOffline: false);
  }

  Future<void> _markAllRead() async {
    if (_offlineBlocked()) return;
    setState(() {
      _all = _all.map((n) => n.copyWith(isRead: true)).toList();
    });
    await _repository.markAllAsRead(queueWhenOffline: false);
  }

  Future<void> _clearAll() async {
    if (_offlineBlocked()) return;
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _ClearAllConfirmDialog(),
    );
    if (confirmed != true) return;
    setState(() => _all = []);
    await _repository.deleteAllNotifications(queueWhenOffline: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final hasUnread = _all.any((n) => n.isUnread);

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.sectionNotifications,
            onBack: () => Navigator.of(context).pop(),
            trailing: _all.isNotEmpty
                ? PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: AppConstants.primaryGreen,
                    ),
                    onSelected: (value) {
                      if (value == 'read_all') _markAllRead();
                      if (value == 'clear_all') _clearAll();
                    },
                    itemBuilder: (context) => [
                      if (hasUnread)
                        PopupMenuItem(
                          value: 'read_all',
                          child: Text(l10n.buyerNotifMenuMarkAllRead),
                        ),
                      PopupMenuItem(
                        value: 'clear_all',
                        child: Text(l10n.buyerNotifMenuClearAll),
                      ),
                    ],
                  )
                : null,
          ),
          CachedDataNotice(
            screen: 'notifications',
            isOnline: _isOnline,
            offlineMessage: l10n.offlineBuyerBody,
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : _all.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        8,
                        AppConstants.spacingSafeH,
                        32,
                      ),
                      children: notificationGroupChildren<NotificationModel>(
                        items: _all,
                        timeOf: (n) => n.createdAt,
                        l10n: l10n,
                        buildItem: (n) => Dismissible(
                          key: ValueKey(n.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: AppConstants.errorRed,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusLg,
                              ),
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => _delete(n),
                          child: _NotificationTile(
                            notification: n,
                            onTap: () => _onNotifTap(n),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: AppConstants.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.buyerNotifEmptyTitle,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.buyerNotifEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  const _NotificationTile({required this.notification, required this.onTap});

  IconData get _icon {
    switch (notification.type) {
      case NotificationType.order:
        return Icons.receipt_long_rounded;
      case NotificationType.listing:
        return Icons.storefront_rounded;
      case NotificationType.price:
        return Icons.trending_up_rounded;
      case NotificationType.loan:
        return Icons.account_balance_wallet_rounded;
      case NotificationType.sync:
        return Icons.sync_rounded;
      case NotificationType.system:
      case NotificationType.listingSubmitted:
      case NotificationType.loanOverdue:
      case NotificationType.memberPending:
      case NotificationType.memberRegistered:
      case NotificationType.memberUpdated:
      case NotificationType.memberApproved:
      case NotificationType.memberRejected:
      case NotificationType.lowStock:
      case NotificationType.stockDepleted:
      case NotificationType.cropRequest:
      case NotificationType.cooperativeOffer:
      case NotificationType.program:
      case NotificationType.capital:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isUnread
              ? AppConstants.primaryGreen.withValues(alpha: 0.05)
              : context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: notification.isUnread
              ? Border.all(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, size: 18, color: AppConstants.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: notification.isUnread
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buyerNotifTimeAgo(notification.createdAt, l10n),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppConstants.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (notification.isUnread)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppConstants.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClearAllConfirmDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.buyerNotifClearDialogTitle,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.buyerNotifClearDialogMessage,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.errorRed,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      l10n.buyerNotifDialogClearAll,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
