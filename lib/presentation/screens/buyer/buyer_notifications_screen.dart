import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../widgets/app_dialog.dart';

class BuyerNotificationsScreen extends StatefulWidget {
  const BuyerNotificationsScreen({super.key});

  @override
  State<BuyerNotificationsScreen> createState() => _BuyerNotificationsScreenState();
}

class _BuyerNotificationsScreenState extends State<BuyerNotificationsScreen> {
  final _repository = NotificationRepository();

  bool _isLoading = true;
  List<NotificationModel> _all = [];
  NotificationFilter _selectedFilter = NotificationFilter.all;

  // Buyer-relevant filters only — Loans is structurally never populated
  // for this role, so it's left off the chip row entirely.
  static const _buyerFilters = [
    NotificationFilter.all,
    NotificationFilter.orders,
    NotificationFilter.listings,
    NotificationFilter.prices,
  ];

  @override
  void initState() {
    super.initState();
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

  List<NotificationModel> get _filtered =>
      _all.where((n) => _selectedFilter.matches(n)).toList();

  Future<void> _markAsRead(NotificationModel n) async {
    if (n.isRead) return;
    setState(() {
      final index = _all.indexWhere((x) => x.id == n.id);
      if (index != -1) _all[index] = n.copyWith(isRead: true);
    });
    await _repository.markAsRead(n.id);
  }

  Future<void> _delete(NotificationModel n) async {
    setState(() => _all.removeWhere((x) => x.id == n.id));
    await _repository.deleteNotification(n.id);
  }

  Future<void> _markAllRead() async {
    setState(() {
      _all = _all.map((n) => n.copyWith(isRead: true)).toList();
    });
    await _repository.markAllAsRead();
  }

  Future<void> _clearAll() async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _ClearAllConfirmDialog(),
    );
    if (confirmed != true) return;
    setState(() => _all = []);
    await _repository.deleteAllNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final filtered = _filtered;
    final hasUnread = _all.any((n) => n.isUnread);

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text('Notifications',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
        actions: [
          if (_all.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppConstants.primaryGreen),
              onSelected: (value) {
                if (value == 'read_all') _markAllRead();
                if (value == 'clear_all') _clearAll();
              },
              itemBuilder: (context) => [
                if (hasUnread)
                  const PopupMenuItem(value: 'read_all', child: Text('Mark all as read')),
                const PopupMenuItem(value: 'clear_all', child: Text('Clear all')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH, vertical: 6),
              itemCount: _buyerFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final filter = _buyerFilters[i];
                final isSelected = filter == _selectedFilter;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = filter),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppConstants.primaryGreen : Colors.white,
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      border: Border.all(color: isSelected ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.25)),
                    ),
                    alignment: Alignment.center,
                    child: Text(filter.label,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : AppConstants.onSurfaceVariant)),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 32),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final n = filtered[i];
                            return Dismissible(
                              key: ValueKey(n.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: AppConstants.errorRed,
                                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                                ),
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                              ),
                              onDismissed: (_) => _delete(n),
                              child: _NotificationTile(notification: n, onTap: () => _markAsRead(n)),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 56, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No notifications', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('You\'ll see order and marketplace updates here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
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
      case NotificationType.order: return Icons.receipt_long_rounded;
      case NotificationType.listing: return Icons.storefront_rounded;
      case NotificationType.price: return Icons.trending_up_rounded;
      case NotificationType.loan: return Icons.account_balance_wallet_rounded;
      case NotificationType.sync: return Icons.sync_rounded;
      case NotificationType.system: return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isUnread ? AppConstants.primaryGreen.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: notification.isUnread ? Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.2)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppConstants.primaryGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(_icon, size: 18, color: AppConstants.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: notification.isUnread ? FontWeight.w700 : FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(notification.body,
                      style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(notification.timeAgo,
                      style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant.withValues(alpha: 0.7))),
                ],
              ),
            ),
            if (notification.isUnread)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8, height: 8,
                decoration: const BoxDecoration(color: AppConstants.primaryGreen, shape: BoxShape.circle),
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
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Clear All Notifications?', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('This cannot be undone.',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorRed),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Clear All', style: TextStyle(color: Colors.white)),
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