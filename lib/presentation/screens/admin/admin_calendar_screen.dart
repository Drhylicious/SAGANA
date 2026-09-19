import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

class AdminCalendarScreen extends StatefulWidget {
  const AdminCalendarScreen({super.key});

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  final _repo = AdminDashboardRepository();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  List<CalendarEvent> _events = [];
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _selectedDay = DateTime.now();
    _loadEvents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    final events = await _repo.fetchCalendarEvents(
      year: _month.year,
      month: _month.month,
    );
    if (!mounted) return;
    setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  Future<void> _changeMonth(int delta) async {
    final next = DateTime(_month.year, _month.month + delta);
    setState(() {
      _month = next;
      _selectedDay = null;
    });
    await _loadEvents();
  }

  List<CalendarEvent> get _eventsForSelectedDay {
    if (_selectedDay == null) return [];
    return _events.where((e) =>
      e.date.year == _selectedDay!.year &&
      e.date.month == _selectedDay!.month &&
      e.date.day == _selectedDay!.day,
    ).toList();
  }

  Map<int, Set<CalendarEventType>> get _eventMap {
    final map = <int, Set<CalendarEventType>>{};
    for (final e in _events) {
      if (e.date.year == _month.year && e.date.month == _month.month) {
        map.putIfAbsent(e.date.day, () => {}).add(e.type);
      }
    }
    return map;
  }

  void _onDayTap(int day) {
    setState(() {
      _selectedDay = DateTime(_month.year, _month.month, day);
    });
  }

  void _onEventTap(CalendarEvent event) {
    switch (event.type) {
      case CalendarEventType.loanDue:
        if (event.referenceId != null) {
          context.push(AppRoutes.loanDetails, extra: event.referenceId);
        } else {
          context.push(AppRoutes.loanDashboard);
        }
      case CalendarEventType.bodMeeting:
        context.go(AppRoutes.loanDashboard);
      case CalendarEventType.harvest:
        context.go(AppRoutes.farmerManagement);
      case CalendarEventType.announcement:
        context.push(AppRoutes.announcementDashboard);
      case CalendarEventType.program:
        context.push(AppRoutes.programManagement);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<String> _monthNames(AppLocalizations l10n) => [
    l10n.adminCalMonthJan, l10n.adminCalMonthFeb, l10n.adminCalMonthMar,
    l10n.adminCalMonthApr, l10n.adminCalMonthMay, l10n.adminCalMonthJun,
    l10n.adminCalMonthJul, l10n.adminCalMonthAug, l10n.adminCalMonthSep,
    l10n.adminCalMonthOct, l10n.adminCalMonthNov, l10n.adminCalMonthDec,
  ];
  List<String> _dayLabels(AppLocalizations l10n) => [
    l10n.adminCalWeekdayShortSun, l10n.adminCalWeekdayShortMon,
    l10n.adminCalWeekdayShortTue, l10n.adminCalWeekdayShortWed,
    l10n.adminCalWeekdayShortThu, l10n.adminCalWeekdayShortFri,
    l10n.adminCalWeekdayShortSat,
  ];

  Color _eventColor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bodMeeting:   return AppConstants.successGreen;
      case CalendarEventType.loanDue:      return AppConstants.errorRed;
      case CalendarEventType.harvest:      return AppConstants.warningAmber;
      case CalendarEventType.announcement: return AppConstants.buyerBlue;
      case CalendarEventType.program:      return AppConstants.programPurple;
    }
  }

  IconData _eventIcon(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bodMeeting:   return Icons.groups_rounded;
      case CalendarEventType.loanDue:      return Icons.payments_rounded;
      case CalendarEventType.harvest:      return Icons.agriculture_rounded;
      case CalendarEventType.announcement: return Icons.campaign_rounded;
      case CalendarEventType.program:      return Icons.star_rounded;
    }
  }

  String _eventTypeName(AppLocalizations l10n, CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bodMeeting:   return l10n.adminCalEventBodMeeting;
      case CalendarEventType.loanDue:      return l10n.adminCalEventLoanDue;
      case CalendarEventType.harvest:      return l10n.adminCalEventHarvest;
      case CalendarEventType.announcement: return l10n.adminCalEventAnnouncement;
      case CalendarEventType.program:      return l10n.adminCalEventProgram;
    }
  }

  String _dayLabel(AppLocalizations l10n, DateTime dt) {
    // Short month/day forms reuse the same shared calendar vocabulary.
    final months = _monthNames(l10n);
    final days = _dayLabels(l10n);
    return '${days[(dt.weekday - 1) % 7]}, ${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;
    final eventMap = _eventMap;
    final selectedEvents = _eventsForSelectedDay;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Glass top bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  left: 8,
                  right: 20,
                ),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.adminCalTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!_isOnline)
            Container(
              color: AppConstants.warningAmber,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Text(
                l10n.adminCalOfflineNotice,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal,
                ),
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _loadEvents,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Calendar card ──────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: sagana.cardBackground,
                        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Month navigation
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => _changeMonth(-1),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                  ),
                                  child: Icon(Icons.chevron_left_rounded,
                                      size: 22, color: cs.onSurface),
                                ),
                              ),
                              Column(
                                children: [
                                  Text(
                                    _monthNames(l10n)[_month.month - 1],
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  Text(
                                    '${_month.year}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: () => _changeMonth(1),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                  ),
                                  child: Icon(Icons.chevron_right_rounded,
                                      size: 22, color: cs.onSurface),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Day headers
                          Row(
                            children: _dayLabels(l10n).map((d) => Expanded(
                              child: Center(
                                child: Text(
                                  d,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            )).toList(),
                          ),
                          const SizedBox(height: 8),

                          // Grid
                          if (_isLoading)
                            Container(
                              height: 240,
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(
                                color: AppConstants.primaryGreen,
                                strokeWidth: 2,
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: startWeekday + daysInMonth,
                              itemBuilder: (_, index) {
                                if (index < startWeekday) {
                                  return const SizedBox.shrink();
                                }
                                final day = index - startWeekday + 1;
                                final date = DateTime(_month.year, _month.month, day);
                                final isToday = today.year == date.year &&
                                    today.month == date.month &&
                                    today.day == date.day;
                                final isSelected = _selectedDay != null &&
                                    _selectedDay!.year == date.year &&
                                    _selectedDay!.month == date.month &&
                                    _selectedDay!.day == date.day;
                                final dayEvents = eventMap[day];

                                return GestureDetector(
                                  onTap: () => _onDayTap(day),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? cs.primary
                                              : isToday
                                                  ? cs.primary.withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                          shape: BoxShape.circle,
                                          border: isToday && !isSelected
                                              ? Border.all(color: cs.primary, width: 1.5)
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$day',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: isToday || isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                              color: isSelected
                                                  ? Colors.white
                                                  : cs.onSurface,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (dayEvents != null && dayEvents.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 3),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: dayEvents.take(3).map((type) =>
                                              Container(
                                                width: 5,
                                                height: 5,
                                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                                decoration: BoxDecoration(
                                                  color: _eventColor(type),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ).toList(),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),

                          // Legend
                          const SizedBox(height: 12),
                          Divider(color: cs.outline.withValues(alpha: 0.10)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: CalendarEventType.values.map((type) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _eventColor(type),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _eventTypeName(l10n, type),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            )).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Selected day events ────────────────────────────────
                    Row(
                      children: [
                        Text(
                          _selectedDay != null
                              ? _dayLabel(l10n, _selectedDay!)
                              : l10n.adminCalSelectDay,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        if (selectedEvents.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                            ),
                            child: Text(
                              '${selectedEvents.length}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_selectedDay == null || selectedEvents.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        decoration: BoxDecoration(
                          color: sagana.cardBackground,
                          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.event_available_rounded,
                                size: 32, color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              l10n.adminCalNoEvents,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: sagana.cardBackground,
                          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Column(
                          children: selectedEvents.asMap().entries.map((entry) {
                            final i = entry.key;
                            final event = entry.value;
                            final isLast = i == selectedEvents.length - 1;
                            final color = _eventColor(event.type);
                            final icon = _eventIcon(event.type);
                            final isNavigable = event.type != CalendarEventType.harvest;

                            return Column(
                              children: [
                                GestureDetector(
                                  onTap: isNavigable ? () => _onEventTap(event) : null,
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                          ),
                                          child: Icon(icon, color: color, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    margin: const EdgeInsets.only(right: 6),
                                                    decoration: BoxDecoration(
                                                      color: color,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  Text(
                                                    _eventTypeName(l10n, event.type).toUpperCase(),
                                                    style: GoogleFonts.inter(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w700,
                                                      color: color,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                event.title,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                              if (event.subtitle != null)
                                                Text(
                                                  event.subtitle!,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isNavigable)
                                          Icon(Icons.chevron_right_rounded,
                                              size: 18,
                                              color: cs.onSurfaceVariant),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!isLast)
                                  Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                    color: cs.outline.withValues(alpha: 0.08),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}