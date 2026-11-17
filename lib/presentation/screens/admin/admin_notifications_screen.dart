import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../widgets/skeleton.dart';
import '../../../data/services/app_event_service.dart';
import '../../widgets/notification_day_groups.dart';
import '../../widgets/notification_ui.dart';
import '../../widgets/sub_page_top_bar.dart';

// Manager and Officer share this screen. It uses the same model, card,
// grouping and selection behaviour as the Farmer and Buyer screens.

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _repo = NotificationRepository();
  final _selection = NotificationSelection();

  List<NotificationModel> _all = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await _repo.fetchNotifications();
    if (!mounted) return;
    setState(() {
      _all = result;
      _selection.clear();
      _isLoading = false;
    });
  }

  /// Tap: selects/unselects while selecting; otherwise marks it read and goes
  /// to the screen the notification is about.
  Future<void> _onNotifTap(NotificationModel notif) async {
    if (_selection.isActive) {
      setState(() => _selection.toggle(notif.id));
      return;
    }
    if (notif.isUnread) {
      setState(() {
        _all = _all
            .map((n) => n.id == notif.id ? n.copyWith(isRead: true) : n)
            .toList();
      });
      await _repo.markAsRead(notif.id);
      AppEventService.instance.notify();
    }
    if (!mounted) return;
    if (notif.routeOnTap != null) {
      if (notif.routeExtra != null) {
        context.push(notif.routeOnTap!, extra: notif.routeExtra);
      } else {
        context.push(notif.routeOnTap!);
      }
    }
  }

  /// Applies the one menu action (Mark as Read / Mark as Unread) to the
  /// selected notifications, then leaves selection mode.
  Future<void> _applyToSelection() async {
    final markRead = _selection.offersMarkRead(_all);
    final ids = _selection.picked(_all).map((n) => n.id).toSet();
    setState(() {
      _all = _all
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
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: !_selection.isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selection.clear);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            SubPageTopBar(
              title: notificationTopBarTitle(
                l10n,
                l10n.pendingNotificationsTitle,
                _selection,
              ),
              onBack: () => _selection.isActive
                  ? setState(_selection.clear)
                  : context.pop(),
              trailing: _selection.isActive
                  ? NotificationSelectionMenu(
                      markRead: _selection.offersMarkRead(_all),
                      onApply: _applyToSelection,
                    )
                  : null,
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : RefreshIndicator(
                      color: Theme.of(context).colorScheme.primary,
                      onRefresh: _load,
                      child: _all.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 100),
                                Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.notifications_none_rounded,
                                        size: 48,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.buyerNotifEmptyTitle,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                32,
                              ),
                              children:
                                  notificationGroupChildren<NotificationModel>(
                                    items: _all,
                                    timeOf: (n) => n.createdAt,
                                    l10n: l10n,
                                    buildItem: (n) => NotificationCard(
                                      item: n,
                                      selected: _selection.contains(n.id),
                                      timeLabel: notificationTimeLabel(
                                        l10n,
                                        n.createdAt,
                                      ),
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
}
