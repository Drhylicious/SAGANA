import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/notification_day_groups.dart';
import '../../widgets/sub_page_top_bar.dart';

// ── Model ────────────────────────────────────────────────────────────────────

enum AdminNotifCategory { all, actions, members, inventory, system }

class AdminNotif {
  final String id;
  final String title;
  final String body;
  final AdminNotifCategory category;
  final bool isRead;
  final DateTime createdAt;
  final String? routeOnTap;
  final String? routeExtra;

  const AdminNotif({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.isRead,
    required this.createdAt,
    this.routeOnTap,
    this.routeExtra,
  });

  factory AdminNotif.fromNotification(NotificationModel n) {
    AdminNotifCategory cat;
    switch (n.type) {
      case NotificationType.listingSubmitted:
      case NotificationType.loanOverdue:
      case NotificationType.memberPending:
      case NotificationType.cropRequest:
        cat = AdminNotifCategory.actions;
      case NotificationType.memberRegistered:
      case NotificationType.memberUpdated:
        cat = AdminNotifCategory.members;
      case NotificationType.lowStock:
      case NotificationType.stockDepleted:
        cat = AdminNotifCategory.inventory;
      default:
        cat = AdminNotifCategory.system;
    }
    return AdminNotif(
      id: n.id,
      title: n.title,
      body: n.body,
      category: cat,
      isRead: n.isRead,
      createdAt: n.createdAt,
      routeOnTap: n.routeOnTap,
      routeExtra: n.routeExtra,
    );
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _repo = NotificationRepository();

  List<AdminNotif> _all = [];
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
      _all = result.map(AdminNotif.fromNotification).toList();
      _isLoading = false;
    });
  }

  Future<void> _onNotifTap(AdminNotif notif) async {
    await _repo.markAsRead(notif.id);
    if (!mounted) return;
    setState(() {
      final idx = _all.indexWhere((n) => n.id == notif.id);
      if (idx != -1) {
        _all[idx] = AdminNotif(
          id: notif.id,
          title: notif.title,
          body: notif.body,
          category: notif.category,
          isRead: true,
          createdAt: notif.createdAt,
          routeOnTap: notif.routeOnTap,
          routeExtra: notif.routeExtra,
        );
      }
    });
    if (notif.routeOnTap != null) {
      if (notif.routeExtra != null) {
        context.push(notif.routeOnTap!, extra: notif.routeExtra);
      } else {
        context.push(notif.routeOnTap!);
      }
    }
  }

  Future<void> _onNotifDelete(AdminNotif notif) async {
    setState(() => _all.removeWhere((n) => n.id == notif.id));
    await _repo.deleteNotification(notif.id);
  }

  IconData _categoryIcon(AdminNotifCategory cat) {
    switch (cat) {
      case AdminNotifCategory.all:
        return Icons.notifications_rounded;
      case AdminNotifCategory.actions:
        return Icons.priority_high_rounded;
      case AdminNotifCategory.members:
        return Icons.people_rounded;
      case AdminNotifCategory.inventory:
        return Icons.inventory_2_rounded;
      case AdminNotifCategory.system:
        return Icons.settings_rounded;
    }
  }

  Color _categoryColor(AdminNotifCategory cat, ColorScheme cs) {
    switch (cat) {
      case AdminNotifCategory.all:
        return cs.primary;
      case AdminNotifCategory.actions:
        return AppConstants.errorRed;
      case AdminNotifCategory.members:
        return AppConstants.primaryGreen;
      case AdminNotifCategory.inventory:
        return AppConstants.warningAmber;
      case AdminNotifCategory.system:
        return cs.outline;
    }
  }

  String _timeLabel(AppLocalizations l10n, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.broadcastJustNow;
    if (diff.inMinutes < 60)
      return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.buyerNotifTimeHoursAgo(diff.inHours);
    if (diff.inDays == 1) return l10n.buyerNotifTimeYesterday;
    return l10n.buyerNotifTimeDaysAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final filtered = _all;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Top bar
          SubPageTopBar(title: l10n.pendingNotificationsTitle, onBack: () => context.pop()),

          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _load,
                    child: filtered.isEmpty
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
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                            children: notificationGroupChildren<AdminNotif>(
                              items: filtered,
                              timeOf: (n) => n.createdAt,
                              l10n: l10n,
                              itemGap: 0,
                              buildItem: (notif) {
                              final color = _categoryColor(notif.category, cs);
                              final icon = _categoryIcon(notif.category);

                              return Dismissible(
                                key: Key(notif.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: AppConstants.errorRed.withValues(
                                    alpha: 0.10,
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppConstants.errorRed,
                                  ),
                                ),
                                onDismissed: (_) => _onNotifDelete(notif),
                                child: GestureDetector(
                                onTap: () => _onNotifTap(notif),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  color: notif.isRead
                                      ? Colors.transparent
                                      : cs.primary.withValues(alpha: 0.04),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: color.withValues(
                                              alpha: 0.12,
                                            ),
                                          shape: BoxShape.circle,
                                        ),
                                          child: Icon(
                                            icon,
                                            color: color,
                                            size: 20,
                                          ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                              Row(
                                                children: [
                                              Expanded(
                                                child: Text(
                                                  notif.title,
                                                      style:
                                                          GoogleFonts.poppins(
                                                    fontSize: 13,
                                                            fontWeight:
                                                                notif.isRead
                                                                ? FontWeight
                                                                      .w500
                                                                : FontWeight
                                                                      .w700,
                                                    color: cs.onSurface,
                                                  ),
                                                ),
                                              ),
                                              if (!notif.isRead)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                      decoration:
                                                          const BoxDecoration(
                                                    color: AppConstants
                                                        .errorRed,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                  ),
                                                ],
                                                ),
                                            const SizedBox(height: 3),
                                            Text(
                                              notif.body,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant,
                                              ),
                                              maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                                _timeLabel(
                                                  l10n,
                                                  notif.createdAt,
                                                ),
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ),
                              );
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
