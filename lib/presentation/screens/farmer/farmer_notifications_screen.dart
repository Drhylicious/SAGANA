import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../widgets/shared_widgets.dart';

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
  NotificationFilter _activeFilter = NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final items = await _repo.fetchNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = items;
      _isLoading = false;
    });
  }

  List<NotificationModel> get _filtered =>
      _notifications.where(_activeFilter.matches).toList();

  int get _unreadCount => _notifications.where((n) => n.isUnread).length;

  Future<void> _markAllRead() async {
    await _repo.markAllAsRead();
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
    });
  }

  Future<void> _markRead(String id) async {
    await _repo.markAsRead(id);
    setState(() {
      _notifications = _notifications
          .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
          .toList();
    });
  }

  Future<void> _delete(String id) async {
    await _repo.deleteNotification(id);
    setState(() => _notifications.removeWhere((n) => n.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadNotifications,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Notifications',
                                      style: GoogleFonts.poppins(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: AppConstants.onSurface,
                                      ),
                                    ),
                                    if (_unreadCount > 0)
                                      Text(
                                        '$_unreadCount unread',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppConstants.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                                if (_unreadCount > 0)
                                  GestureDetector(
                                    onTap: _markAllRead,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppConstants.primaryGreen
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(
                                          AppConstants.radiusFull,
                                        ),
                                        border: Border.all(
                                          color: AppConstants.primaryGreen
                                              .withValues(alpha: 0.20),
                                        ),
                                      ),
                                      child: Text(
                                        'Mark all read',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppConstants.primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 34,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: NotificationFilter.values.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final f = NotificationFilter.values[i];
                                  final active = _activeFilter == f;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _activeFilter = f),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? cs.primary
                                            : sagana.cardBackground,
                                        borderRadius: BorderRadius.circular(
                                          AppConstants.radiusFull,
                                        ),
                                        border: Border.all(
                                          color: active
                                              ? cs.primary
                                              : cs.outline.withValues(
                                                  alpha: 0.25,
                                                ),
                                        ),
                                      ),
                                      child: Text(
                                        f.label,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: active
                                              ? cs.onPrimary
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_filtered.isEmpty)
                              _EmptyState(filter: _activeFilter)
                            else
                              ..._buildGrouped(),
                          ],
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              onBack: () => Navigator.of(context).pop(),
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGrouped() {
    final now = DateTime.now();
    final items = _filtered;
    final today = items.where((n) => _isToday(n.createdAt, now)).toList();
    final yesterday = items
        .where((n) => _isYesterday(n.createdAt, now))
        .toList();
    final older = items
        .where(
          (n) => !_isToday(n.createdAt, now) && !_isYesterday(n.createdAt, now),
        )
        .toList();

    final widgets = <Widget>[];

    void addGroup(String label, List<NotificationModel> group) {
      if (group.isEmpty) return;
      widgets.add(_GroupLabel(label: label));
      for (final n in group) {
        widgets.add(
          _NotifCard(
            item: n,
            onTap: () => _markRead(n.id),
            onDelete: () => _delete(n.id),
          ),
        );
        widgets.add(const SizedBox(height: 8));
      }
    }

    addGroup('Today', today);
    addGroup('Yesterday', yesterday);
    addGroup('Earlier', older);
    return widgets;
  }

  bool _isToday(DateTime dt, DateTime now) =>
      dt.year == now.year && dt.month == now.month && dt.day == now.day;

  bool _isYesterday(DateTime dt, DateTime now) {
    final y = now.subtract(const Duration(days: 1));
    return dt.year == y.year && dt.month == y.month && dt.day == y.day;
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppConstants.outline,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final NotificationModel item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotifCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _config(item.type);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppConstants.errorRed.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppConstants.errorRed,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: item.isRead
                ? sagana.cardBackground.withValues(alpha: 0.85)
                : cs.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: item.isRead
                  ? cs.outlineVariant.withValues(alpha: 0.30)
                  : cs.primary.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cfg.color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(cfg.icon, color: cfg.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: item.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: AppConstants.onSurface,
                            ),
                          ),
                        ),
                        if (item.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppConstants.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.timeAgo,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: cs.outline,
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
  }

  _IconConfig _config(NotificationType type) {
    switch (type) {
      case NotificationType.order:
        return const _IconConfig(
          Icons.shopping_bag_outlined,
          AppConstants.buyerBlue,
        );
      case NotificationType.listing:
        return const _IconConfig(
          Icons.storefront_outlined,
          AppConstants.primaryGreen,
        );
      case NotificationType.loan:
        return const _IconConfig(
          Icons.eco_outlined,
          AppConstants.tertiaryContainer,
        );
      case NotificationType.price:
        return const _IconConfig(Icons.show_chart_rounded, AppConstants.amber);
      case NotificationType.sync:
        return const _IconConfig(Icons.sync_rounded, AppConstants.successGreen);
      case NotificationType.system:
        return const _IconConfig(
          Icons.info_outline_rounded,
          AppConstants.onSurfaceVariant,
        );
    }
  }
}

class _IconConfig {
  final IconData icon;
  final Color color;
  const _IconConfig(this.icon, this.color);
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
