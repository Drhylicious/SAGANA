import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/notification_day_groups.dart';
import '../../widgets/notification_ui.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';

class BuyerNotificationsScreen extends StatefulWidget {
  const BuyerNotificationsScreen({super.key});

  @override
  State<BuyerNotificationsScreen> createState() =>
      _BuyerNotificationsScreenState();
}

class _BuyerNotificationsScreenState extends State<BuyerNotificationsScreen> {
  final _repository = NotificationRepository();
  final _selection = NotificationSelection();

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
      _selection.clear();
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
    AppEventService.instance.notify();
  }

  /// Tap: selects/unselects while selecting; otherwise marks it read and goes
  /// to the screen the notification is about.
  Future<void> _onNotifTap(NotificationModel n) async {
    if (_selection.isActive) {
      setState(() => _selection.toggle(n.id));
      return;
    }
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

  /// Applies the one menu action (Mark as Read / Mark as Unread) to the
  /// selected notifications, then leaves selection mode.
  Future<void> _applyToSelection() async {
    if (_offlineBlocked()) return;
    final markRead = _selection.offersMarkRead(_all);
    final ids = _selection.picked(_all).map((n) => n.id).toSet();
    setState(() {
      _all = _all
          .map((n) => ids.contains(n.id) ? n.copyWith(isRead: markRead) : n)
          .toList();
      _selection.clear();
    });
    await Future.wait(
      ids.map(
        (id) => markRead
            ? _repository.markAsRead(id, queueWhenOffline: false)
            : _repository.markAsUnread(id, queueWhenOffline: false),
      ),
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
                      markRead: _selection.offersMarkRead(_all),
                      onApply: _applyToSelection,
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
                          buildItem: (n) => NotificationCard(
                            item: n,
                            selected: _selection.contains(n.id),
                            timeLabel: notificationTimeLabel(l10n, n.createdAt),
                            onTap: () => _onNotifTap(n),
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
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
