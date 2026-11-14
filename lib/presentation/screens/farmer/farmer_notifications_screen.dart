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
import '../../../routes/app_routes.dart';
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
  final _selection = NotificationSelection();

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
      final items = await _repo.fetchNotifications().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _selection.clear();
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

  /// Tap: selects/unselects while selecting; otherwise marks it read and goes
  /// to the screen the notification is about.
  Future<void> _onNotifTap(NotificationModel n) async {
    if (_selection.isActive) {
      setState(() => _selection.toggle(n.id));
      return;
    }
    if (n.isUnread) {
      setState(() {
        _notifications = _notifications
            .map((x) => x.id == n.id ? x.copyWith(isRead: true) : x)
            .toList();
      });
      await _repo.markAsRead(n.id);
      AppEventService.instance.notify();
    }
    if (!mounted) return;
    if (n.routeOnTap != null) {
      if (n.routeExtra != null) {
        context.push(n.routeOnTap!, extra: n.routeExtra);
      } else {
        context.push(n.routeOnTap!);
      }
    }
  }

  /// The crop a shelf-life notice is about, read from its title ("Check Your
  /// Pechay"). Null for any other notification.
  String? _shelfLifeCrop(NotificationModel n) {
    const prefix = 'Check Your ';
    if (n.routeOnTap != AppRoutes.manageInventory || n.routeExtra == null) {
      return null;
    }
    if (!n.title.startsWith(prefix)) return null;
    final crop = n.title.substring(prefix.length).trim();
    return crop.isEmpty ? null : crop;
  }

  /// The two answers a "check your produce" notice offers. Each opens Manage
  /// Inventory on that batch, already on the chosen answer.
  List<NotificationAction> _shelfLifeActions(
    AppLocalizations l10n,
    NotificationModel n,
  ) {
    final crop = _shelfLifeCrop(n);
    if (crop == null) return const [];
    Future<void> open(String answer) async {
      if (n.isUnread) {
        setState(() {
          _notifications = _notifications
              .map((x) => x.id == n.id ? x.copyWith(isRead: true) : x)
              .toList();
        });
        await _repo.markAsRead(n.id);
        AppEventService.instance.notify();
      }
      if (!mounted) return;
      context.push(AppRoutes.manageInventory, extra: '${n.routeExtra}|$answer');
    }

    return [
      NotificationAction(
        label: l10n.shelfActionStillOkay(crop),
        onTap: () => open('good'),
      ),
      NotificationAction(
        label: l10n.shelfActionRotten(crop),
        onTap: () => open('rotten'),
        destructive: true,
      ),
    ];
  }

  /// Applies the one menu action (Mark as Read / Mark as Unread) to the
  /// selected notifications, then leaves selection mode.
  Future<void> _applyToSelection() async {
    final markRead = _selection.offersMarkRead(_notifications);
    final ids = _selection.picked(_notifications).map((n) => n.id).toSet();
    setState(() {
      _notifications = _notifications
          .map((n) => ids.contains(n.id) ? n.copyWith(isRead: markRead) : n)
          .toList();
      _selection.clear();
    });
    await Future.wait(
      ids.map((id) => markRead ? _repo.markAsRead(id) : _repo.markAsUnread(id)),
    );
    AppEventService.instance.notify();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return PopScope(
      canPop: !_selection.isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selection.clear);
      },
      child: Scaffold(
        backgroundColor: sagana.scaffoldBackground,
        body: Column(
          children: [
            SubPageTopBar(
              title: notificationTopBarTitle(
                l10n,
                l10n.sectionNotifications,
                _selection,
              ),
              onBack: () => _selection.isActive
                  ? setState(_selection.clear)
                  : Navigator.of(context).pop(),
              trailing: _selection.isActive
                  ? NotificationSelectionMenu(
                      markRead: _selection.offersMarkRead(_notifications),
                      onApply: _applyToSelection,
                    )
                  : null,
            ),
            const Divider(height: 1),
            CachedDataNotice(
              screen: 'notifications',
              isOnline: _isOnline,
              offlineMessage: l10n.offlineNotifications,
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
                        children: const [
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
                            selected: _selection.contains(n.id),
                            timeLabel: notificationTimeLabel(l10n, n.createdAt),
                            onTap: () => _onNotifTap(n),
                            actions: _shelfLifeActions(l10n, n),
                            onLongPress: () {
                              if (_selection.isActive) return;
                              setState(() => _selection.toggle(n.id));
                            },
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
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
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(
            filter == NotificationFilter.all
                ? AppLocalizations.of(context).pendingNoNotifications
                : AppLocalizations.of(
                    context,
                  ).enhNoNotifications((filter.label).toString()),
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).enhYouReAllCaughtUp,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
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
  const _NotificationsLoadError({
    required this.onRetry,
    required this.isOnline,
  });

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
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.60),
            ),
            const SizedBox(height: 12),
            Text(
              isOnline
                  ? AppLocalizations.of(
                      context,
                    ).enhCouldNotLoadYourNotifications
                  : AppLocalizations.of(context).youAreOffline,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(
                  context,
                ).enhYourNotificationsWillLoadOnceYouReBack,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                AppLocalizations.of(context).retry,
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
