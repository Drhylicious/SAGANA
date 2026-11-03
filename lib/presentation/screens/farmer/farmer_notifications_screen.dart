import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/notification_day_groups.dart';
import '../../widgets/notification_ui.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/skeleton.dart';

class FarmerNotificationsScreen extends StatefulWidget {
  const FarmerNotificationsScreen({super.key});

  @override
  State<FarmerNotificationsScreen> createState() =>
      _FarmerNotificationsScreenState();
}

class _FarmerNotificationsScreenState extends State<FarmerNotificationsScreen> {
  final _repo = NotificationRepository();

  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _isOnline = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final items =
          await _repo.fetchNotifications().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }


  int get _unreadCount => _notifications.where((n) => n.isUnread).length;

  Future<void> _markAllRead() async {
    await _repo.markAllAsRead();
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
    });
    AppEventService.instance.notify();
  }

  Future<void> _markAllUnread() async {
    await _repo.markAllAsUnread();
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: false))
          .toList();
    });
    AppEventService.instance.notify();
  }

  /// Long-press: flips one notification between read and unread.
  Future<void> _toggleRead(NotificationModel n) async {
    final nowRead = !n.isRead;
    if (nowRead) {
      await _repo.markAsRead(n.id);
    } else {
      await _repo.markAsUnread(n.id);
    }
    setState(() {
      _notifications = _notifications
          .map((x) => x.id == n.id ? x.copyWith(isRead: nowRead) : x)
          .toList();
    });
    AppEventService.instance.notify();
  }

  Future<void> _markRead(String id) async {
    await _repo.markAsRead(id);
    setState(() {
      _notifications = _notifications
          .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
          .toList();
    });
    AppEventService.instance.notify();
  }

  Future<void> _onNotifTap(NotificationModel n) async {
    await _markRead(n.id);
    if (!mounted) return;
    if (n.routeOnTap != null) {
      if (n.routeExtra != null) {
        context.push(n.routeOnTap!, extra: n.routeExtra);
      } else {
        context.push(n.routeOnTap!);
      }
    }
  }

  Future<void> _delete(String id) async {
    await _repo.deleteNotification(id);
    setState(() => _notifications.removeWhere((n) => n.id == id));
    AppEventService.instance.notify();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.sectionNotifications,
            onBack: () => Navigator.of(context).pop(),
            trailing: _notifications.isEmpty
                ? null
                : NotificationMenuButton(
                    hasUnread: _unreadCount > 0,
                    hasRead: _notifications.any((n) => n.isRead),
                    onMarkAllRead: _markAllRead,
                    onMarkAllUnread: _markAllUnread,
                  ),
          ),
          const Divider(height: 1),
          CachedDataNotice(
            screen: 'notifications',
            isOnline: _isOnline,
            offlineMessage:
                AppLocalizations.of(context).offlineNotifications,
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _loadNotifications,
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : _loadFailed
                  ? _NotificationsLoadError(
                      onRetry: _loadNotifications,
                      isOnline: _isOnline,
                    )
                  : _notifications.isEmpty
                  ? ListView(
                      children: [
                        _EmptyState(filter: NotificationFilter.all),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      children: notificationGroupChildren<NotificationModel>(
                        items: _notifications,
                        timeOf: (n) => n.createdAt,
                        l10n: l10n,
                        buildItem: (n) => NotificationCard(
                          item: n,
                          timeLabel: notificationTimeLabel(l10n, n.createdAt),
                          onTap: () => _onNotifTap(n),
                          onLongPress: () => showNotificationReadSheet(
                            context,
                            isRead: n.isRead,
                            onToggle: () => _toggleRead(n),
                          ),
                          onDelete: () => _delete(n.id),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NotificationFilter filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: AppConstants.outline.withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(
            filter == NotificationFilter.all
                ? 'No notifications yet'
                : 'No ${filter.label} notifications',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You\'re all caught up!',
            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Load Error — shown when fetchNotifications() fails or times
// out. Message/icon distinguish "you're offline" from a genuine load
// failure, matching FarmerProfileScreen's _ProfileLoadError pattern.
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationsLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final bool isOnline;
  const _NotificationsLoadError({required this.onRetry, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOnline ? Icons.error_outline_rounded : Icons.wifi_off_rounded,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
            const SizedBox(height: 12),
            Text(
              isOnline ? 'Could not load your notifications' : 'You\'re offline',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 4),
              Text(
                'Your notifications will load once you\'re back online.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}