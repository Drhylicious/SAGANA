import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
 

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

  factory AdminNotif.fromMap(Map<String, dynamic> m) {
    final type = m['type'] as String? ?? 'system';
    AdminNotifCategory cat;
    switch (type) {
      case 'listing_submitted':
      case 'loan_overdue':
      case 'member_pending':
      case 'crop_request':
        cat = AdminNotifCategory.actions;
      case 'member_registered':
      case 'member_updated':
        cat = AdminNotifCategory.members;
      case 'low_stock':
      case 'stock_depleted':
        cat = AdminNotifCategory.inventory;
      default:
        cat = AdminNotifCategory.system;
    }
    return AdminNotif(
      id: m['id'] as String,
      title: m['title'] as String,
      body: m['body'] as String,
      category: cat,
      isRead: m['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}

// ── Repository ───────────────────────────────────────────────────────────────

class _AdminNotifRepository {
  final _client = Supabase.instance.client;

  Future<List<AdminNotif>> fetchAll() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];
      final rows = await _client
          .from('notifications')
          .select('id, type, title, body, is_read, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return rows.map((r) => AdminNotif.fromMap(r)).toList();
    } catch (_) { return []; }
  }

  Future<void> markRead(String id) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true}).eq('id', id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (_) {}
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends State<AdminNotificationsScreen> {
  final _repo = _AdminNotifRepository();

  List<AdminNotif> _all = [];
  AdminNotifCategory _selected = AdminNotifCategory.all;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await _repo.fetchAll();
    if (!mounted) return;
    setState(() { _all = result; _isLoading = false; });
  }

  List<AdminNotif> get _filtered {
    if (_selected == AdminNotifCategory.all) return _all;
    return _all.where((n) => n.category == _selected).toList();
  }

  int _unreadCount(AdminNotifCategory cat) {
    final source =
        cat == AdminNotifCategory.all ? _all : _all.where((n) => n.category == cat);
    return source.where((n) => !n.isRead).length;
  }

  Future<void> _onNotifTap(AdminNotif notif) async {
    await _repo.markRead(notif.id);
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

  IconData _categoryIcon(AdminNotifCategory cat) {
    switch (cat) {
      case AdminNotifCategory.all:       return Icons.notifications_rounded;
      case AdminNotifCategory.actions:   return Icons.priority_high_rounded;
      case AdminNotifCategory.members:   return Icons.people_rounded;
      case AdminNotifCategory.inventory: return Icons.inventory_2_rounded;
      case AdminNotifCategory.system:    return Icons.settings_rounded;
    }
  }

  Color _categoryColor(AdminNotifCategory cat, ColorScheme cs) {
    switch (cat) {
      case AdminNotifCategory.all:       return cs.primary;
      case AdminNotifCategory.actions:   return AppConstants.errorRed;
      case AdminNotifCategory.members:   return AppConstants.primaryGreen;
      case AdminNotifCategory.inventory: return AppConstants.warningAmber;
      case AdminNotifCategory.system:    return cs.outline;
    }
  }

  String _categoryLabel(AppLocalizations l10n, AdminNotifCategory cat) {
    switch (cat) {
      case AdminNotifCategory.all:       return l10n.buyerNotifFilterAll;
      case AdminNotifCategory.actions:   return l10n.adminNotifCategoryActions;
      case AdminNotifCategory.members:   return l10n.adminNavMembers;
      case AdminNotifCategory.inventory: return l10n.supplyChainFlowInventory;
      case AdminNotifCategory.system:    return l10n.adminNotifCategorySystem;
    }
  }

  String _timeLabel(AppLocalizations l10n, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.broadcastJustNow;
    if (diff.inMinutes < 60) return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.buyerNotifTimeHoursAgo(diff.inHours);
    if (diff.inDays == 1) return l10n.buyerNotifTimeYesterday;
    return l10n.buyerNotifTimeDaysAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final filtered = _filtered;
    final unreadTotal = _unreadCount(AdminNotifCategory.all);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Top bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    left: 8, right: 8),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border:
                      Border(bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.pendingNotificationsTitle,
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface),
                      ),
                    ),
                    if (unreadTotal > 0)
                      TextButton(
                        onPressed: () async {
                          await _repo.markAllRead();
                          _load();
                        },
                        child: Text(
                          l10n.adminNotifMarkAllRead,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Category tabs
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: AdminNotifCategory.values.map((cat) {
                  final isSelected = _selected == cat;
                  final unread = _unreadCount(cat);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : sagana.cardBackground,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outline.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _categoryLabel(l10n, cat),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.30)
                                      : AppConstants.errorRed,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    unread > 9 ? '9+' : '$unread',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen, strokeWidth: 2))
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Column(children: [
                                Icon(Icons.notifications_none_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(
                                  l10n.buyerNotifEmptyTitle,
                                  style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant),
                                ),
                              ]),
                            ),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 40),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: cs.outline.withValues(alpha: 0.08)),
                            itemBuilder: (_, i) {
                              final notif = filtered[i];
                              final color =
                                  _categoryColor(notif.category, cs);
                              final icon =
                                  _categoryIcon(notif.category);

                              return GestureDetector(
                                onTap: () => _onNotifTap(notif),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  color: notif.isRead
                                      ? Colors.transparent
                                      : cs.primary.withValues(alpha: 0.04),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: color.withValues(
                                              alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(icon,
                                            color: color, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Expanded(
                                                child: Text(
                                                  notif.title,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 13,
                                                    fontWeight: notif.isRead
                                                        ? FontWeight.w500
                                                        : FontWeight.w700,
                                                    color: cs.onSurface,
                                                  ),
                                                ),
                                              ),
                                              if (!notif.isRead)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(
                                                    color: AppConstants
                                                        .errorRed,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                            ]),
                                            const SizedBox(height: 3),
                                            Text(
                                              notif.body,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant,
                                              ),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _timeLabel(l10n, notif.createdAt),
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
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}