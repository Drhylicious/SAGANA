import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/broadcast_model.dart';
import '../../../data/repositories/broadcast_repository.dart';
import '../../../data/services/connectivity_service.dart';

class NotificationBroadcastScreen extends StatefulWidget {
  const NotificationBroadcastScreen({super.key});

  @override
  State<NotificationBroadcastScreen> createState() =>
      _NotificationBroadcastScreenState();
}

class _NotificationBroadcastScreenState
    extends State<NotificationBroadcastScreen> {
  final _repo        = BroadcastRepository();
  final _titleCtrl   = TextEditingController();
  final _bodyCtrl    = TextEditingController();
  final _scrollCtrl  = ScrollController();

  // ── Form state ─────────────────────────────────────────────────────────────
  RecipientType       _recipientType   = RecipientType.allMembers;
  BroadcastCategory   _category        = BroadcastCategory.meeting;
  String?             _cropFilter;
  String?             _farmerFilter;
  bool                _scheduleEnabled = false;
  DateTime?           _scheduledAt;

  // ── Dynamic data ───────────────────────────────────────────────────────────
  int                        _recipientCount = 0;
  List<BroadcastModel>       _history        = [];
  List<String>               _cropNames      = [];
  List<Map<String, String>>  _farmers        = [];

  // ── Screen state ───────────────────────────────────────────────────────────
  bool _isLoading  = true;
  bool _isSending  = false;
  bool _isOnline   = true;

  static const int _maxTitle = 60;
  static const int _maxBody  = 300;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _titleCtrl.addListener(() => setState(() {}));
    _bodyCtrl.addListener(()  => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchRecentBroadcasts(),
      _repo.fetchCropNames(),
      _repo.fetchFarmersList(),
      _repo.previewRecipientCount(type: _recipientType),
    ]);
    if (!mounted) return;
    setState(() {
      _history        = results[0] as List<BroadcastModel>;
      _cropNames      = results[1] as List<String>;
      _farmers        = results[2] as List<Map<String, String>>;
      _recipientCount = results[3] as int;
      _isLoading      = false;
    });
  }

  Future<void> _refreshRecipientCount() async {
    final count = await _repo.previewRecipientCount(
      type:   _recipientType,
      filter: _recipientType == RecipientType.specificCrop
          ? _cropFilter
          : _farmerFilter,
    );
    if (mounted) setState(() => _recipientCount = count);
  }

  // ── Template sheet ─────────────────────────────────────────────────────────

  void _showTemplateSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateSheet(
        templates: kBroadcastTemplates,
        onSelected: (tpl) {
          setState(() {
            _titleCtrl.text = tpl.title;
            _bodyCtrl.text  = tpl.body;
            _category       = tpl.category;
            _recipientType  = tpl.recipientType;
          });
          _refreshRecipientCount();
        },
        sagana: context.saganaColors,
        cs: Theme.of(context).colorScheme,
      ),
    );
  }

  // ── Schedule picker ────────────────────────────────────────────────────────

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      );
    });
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body  = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showSnack('Please fill in the title and message body.');
      return;
    }
    if (_recipientType == RecipientType.specificCrop &&
        (_cropFilter == null || _cropFilter!.isEmpty)) {
      _showSnack('Please select a crop for the specific crop filter.');
      return;
    }
    if (_recipientType == RecipientType.specificFarmer &&
        (_farmerFilter == null || _farmerFilter!.isEmpty)) {
      _showSnack('Please select a farmer to send to.');
      return;
    }

    setState(() => _isSending = true);
    try {
      final count = await _repo.sendBroadcast(
        title:           title,
        body:            body,
        category:        _category,
        recipientType:   _recipientType,
        recipientFilter: _recipientType == RecipientType.specificCrop
            ? _cropFilter
            : _recipientType == RecipientType.specificFarmer
                ? _farmerFilter
                : null,
        scheduledAt: _scheduleEnabled ? _scheduledAt : null,
      );

      if (!mounted) return;
      setState(() => _isSending = false);

      _showSnack(
        _scheduleEnabled && _scheduledAt != null
            ? 'Scheduled for ${_formatScheduleLabel(_scheduledAt!)} • $count recipients'
            : 'Sent to $count member${count == 1 ? '' : 's'} successfully.',
        isSuccess: true,
      );

      // Reset form
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _recipientType  = RecipientType.allMembers;
        _category       = BroadcastCategory.meeting;
        _scheduleEnabled = false;
        _scheduledAt    = null;
      });
      _refreshRecipientCount();
      _loadAll();
    } catch (_) {
      setState(() => _isSending = false);
      _showSnack('Failed to send. Please try again.');
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor:
            isSuccess ? AppConstants.successGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  String _formatScheduleLabel(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    final h   = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen,
                        ),
                      )
                    : ListView(
                        controller: _scrollCtrl,
                        padding:
                            const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [

                          // ── Compose section header ──────────────────────
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.broadcastCompose,
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              GestureDetector(
                                onTap: _showTemplateSheet,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.history_edu_rounded,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.broadcastUseTemplate,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // ── Compose form card ───────────────────────────
                          _ComposeCard(
                            titleCtrl:       _titleCtrl,
                            bodyCtrl:        _bodyCtrl,
                            recipientType:   _recipientType,
                            category:        _category,
                            recipientCount:  _recipientCount,
                            cropFilter:      _cropFilter,
                            farmerFilter:    _farmerFilter,
                            cropNames:       _cropNames,
                            farmers:         _farmers,
                            maxTitle:        _maxTitle,
                            maxBody:         _maxBody,
                            cs:              cs,
                            sagana:          sagana,
                            onRecipientChanged: (type) {
                              setState(() {
                                _recipientType = type;
                                _cropFilter    = null;
                                _farmerFilter  = null;
                              });
                              _refreshRecipientCount();
                            },
                            onCategoryChanged: (cat) =>
                                setState(() => _category = cat),
                            onCropFilterChanged: (crop) {
                              setState(() => _cropFilter = crop);
                              _refreshRecipientCount();
                            },
                            onFarmerFilterChanged: (id) {
                              setState(() => _farmerFilter = id);
                              _refreshRecipientCount();
                            },
                          ),
                          const SizedBox(height: 16),

                          // ── Live preview ────────────────────────────────
                          _SectionLabel(
                            label: l10n.broadcastPreview,
                            cs: cs,
                          ),
                          const SizedBox(height: 8),
                          _LivePreview(
                            title: _titleCtrl.text.isEmpty
                                ? 'Notification Title'
                                : _titleCtrl.text,
                            body: _bodyCtrl.text.isEmpty
                                ? 'Your message will appear here...'
                                : _bodyCtrl.text,
                            cs: cs,
                            sagana: sagana,
                          ),
                          const SizedBox(height: 16),

                          // ── Schedule toggle ─────────────────────────────
                          _ScheduleRow(
                            enabled:     _scheduleEnabled,
                            scheduledAt: _scheduledAt,
                            sagana:      sagana,
                            cs:          cs,
                            l10n:        l10n,
                            onToggle: (v) {
                              setState(() {
                                _scheduleEnabled = v;
                                if (v && _scheduledAt == null) _pickSchedule();
                              });
                            },
                            onPickTime: _pickSchedule,
                            formatLabel: _formatScheduleLabel,
                          ),
                          const SizedBox(height: 16),

                          // ── Send button ─────────────────────────────────
                          _SendButton(
                            recipientCount: _recipientCount,
                            isSending:      _isSending,
                            isOnline:       _isOnline,
                            isScheduled:    _scheduleEnabled,
                            scheduledAt:    _scheduledAt,
                            onSend:         _send,
                            cs:             cs,
                            formatLabel:    _formatScheduleLabel,
                          ),
                          const SizedBox(height: 24),

                          // ── Recent broadcasts ───────────────────────────
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.broadcastRecent,
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_history.isEmpty)
                            _EmptyHistory(cs: cs)
                          else
                            ..._history
                                .take(10)
                                .map((b) => Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 10),
                                      child: _BroadcastHistoryCard(
                                        broadcast: b,
                                        cs:        cs,
                                        sagana:    sagana,
                                      ),
                                    )),
                        ],
                      ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              title: l10n.broadcastTitle,
              onBack: () => context.pop(),
              cs: cs,
              sagana: sagana,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _TopAppBar({
    required this.title,
    required this.onBack,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(
              bottom: BorderSide(color: sagana.glassBorder),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compose Card
// ─────────────────────────────────────────────────────────────────────────────

class _ComposeCard extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final RecipientType recipientType;
  final BroadcastCategory category;
  final int recipientCount;
  final String? cropFilter;
  final String? farmerFilter;
  final List<String> cropNames;
  final List<Map<String, String>> farmers;
  final int maxTitle;
  final int maxBody;
  final ColorScheme cs;
  final SaganaColors sagana;
  final ValueChanged<RecipientType> onRecipientChanged;
  final ValueChanged<BroadcastCategory> onCategoryChanged;
  final ValueChanged<String?> onCropFilterChanged;
  final ValueChanged<String?> onFarmerFilterChanged;

  const _ComposeCard({
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.recipientType,
    required this.category,
    required this.recipientCount,
    required this.cropFilter,
    required this.farmerFilter,
    required this.cropNames,
    required this.farmers,
    required this.maxTitle,
    required this.maxBody,
    required this.cs,
    required this.sagana,
    required this.onRecipientChanged,
    required this.onCategoryChanged,
    required this.onCropFilterChanged,
    required this.onFarmerFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Recipients ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recipients',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              Text(
                'Sending to: $recipientCount member${recipientCount == 1 ? '' : 's'}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<RecipientType>(
            value: recipientType,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            style: GoogleFonts.inter(
                fontSize: 14, color: cs.onSurface),
            items: RecipientType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onRecipientChanged(v);
            },
          ),

          // ── Crop filter (visible only for specificCrop) ───────────────
          if (recipientType == RecipientType.specificCrop) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: cropFilter,
              hint: Text('Select crop',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: cs.outline)),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              style: GoogleFonts.inter(
                  fontSize: 14, color: cs.onSurface),
              items: cropNames
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: onCropFilterChanged,
            ),
          ],

          // ── Farmer filter (visible only for specificFarmer) ───────────
          if (recipientType == RecipientType.specificFarmer) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: farmerFilter,
              hint: Text('Select farmer',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: cs.outline)),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              style: GoogleFonts.inter(
                  fontSize: 14, color: cs.onSurface),
              items: farmers
                  .map((f) => DropdownMenuItem(
                        value: f['id'],
                        child: Text(f['name'] ?? ''),
                      ))
                  .toList(),
              onChanged: onFarmerFilterChanged,
            ),
          ],
          const SizedBox(height: 16),

          // ── Category chips ────────────────────────────────────────────
          Text(
            'Category',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: BroadcastCategory.values.map((cat) {
                final active = category == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onCategoryChanged(cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _categoryIcon(cat),
                            size: 14,
                            color: active
                                ? Colors.white
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cat.label,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: active
                                  ? Colors.white
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Title field ───────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notification Title',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              Text(
                '${titleCtrl.text.length}/$maxTitle',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: titleCtrl.text.length > maxTitle
                      ? cs.error
                      : cs.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: titleCtrl,
            maxLength: maxTitle,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                const SizedBox.shrink(),
            decoration: InputDecoration(
              hintText: 'Enter title...',
              hintStyle: GoogleFonts.inter(
                  fontSize: 14, color: cs.outline),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            style: GoogleFonts.inter(
                fontSize: 14, color: cs.onSurface),
          ),
          const SizedBox(height: 14),

          // ── Body field ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Message Body',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              Text(
                '${bodyCtrl.text.length}/$maxBody',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: bodyCtrl.text.length > maxBody
                      ? cs.error
                      : cs.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: bodyCtrl,
            maxLength: maxBody,
            maxLines: 5,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                const SizedBox.shrink(),
            decoration: InputDecoration(
              hintText: 'Enter message...',
              hintStyle: GoogleFonts.inter(
                  fontSize: 14, color: cs.outline),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            style: GoogleFonts.inter(
                fontSize: 14, color: cs.onSurface),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(BroadcastCategory cat) {
    switch (cat) {
      case BroadcastCategory.meeting:   return Icons.calendar_today_rounded;
      case BroadcastCategory.financial: return Icons.payments_outlined;
      case BroadcastCategory.harvest:   return Icons.eco_outlined;
      case BroadcastCategory.update:    return Icons.sync_rounded;
      case BroadcastCategory.general:   return Icons.campaign_outlined;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Preview
// ─────────────────────────────────────────────────────────────────────────────

class _LivePreview extends StatelessWidget {
  final String title;
  final String body;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _LivePreview({
    required this.title,
    required this.body,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppConstants.primaryContainer, AppConstants.primaryGreen],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIVE PREVIEW',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 12),
          // Phone notification bubble
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                    color: AppConstants.primaryGreen,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      'SG',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SAGANA',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppConstants.primaryGreen,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Just now',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppConstants.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.onSurfaceVariant,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Row
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleRow extends StatelessWidget {
  final bool enabled;
  final DateTime? scheduledAt;
  final SaganaColors sagana;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;
  final String Function(DateTime) formatLabel;

  const _ScheduleRow({
    required this.enabled,
    required this.scheduledAt,
    required this.sagana,
    required this.cs,
    required this.l10n,
    required this.onToggle,
    required this.onPickTime,
    required this.formatLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.secondaryContainer
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: AppConstants.amber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.broadcastSchedule,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      enabled && scheduledAt != null
                          ? formatLabel(scheduledAt!)
                          : l10n.broadcastScheduleSub,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: enabled && scheduledAt != null
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
                activeColor: AppConstants.primaryGreen,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onPickTime,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      scheduledAt != null
                          ? formatLabel(scheduledAt!)
                          : 'Tap to pick date & time',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: scheduledAt != null
                            ? cs.onSurface
                            : cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Send Button
// ─────────────────────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  final int recipientCount;
  final bool isSending;
  final bool isOnline;
  final bool isScheduled;
  final DateTime? scheduledAt;
  final VoidCallback onSend;
  final ColorScheme cs;
  final String Function(DateTime) formatLabel;

  const _SendButton({
    required this.recipientCount,
    required this.isSending,
    required this.isOnline,
    required this.isScheduled,
    required this.scheduledAt,
    required this.onSend,
    required this.cs,
    required this.formatLabel,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = isOnline && !isSending;
    final label   = isScheduled && scheduledAt != null
        ? 'Schedule for ${formatLabel(scheduledAt!)}'
        : 'Send to $recipientCount Member${recipientCount == 1 ? '' : 's'}';

    return GestureDetector(
      onTap: canSend ? onSend : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: canSend
              ? const LinearGradient(
                  colors: [
                    AppConstants.primaryGreen,
                    AppConstants.successGreen,
                  ],
                )
              : null,
          color: canSend ? null : cs.outline.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: canSend
              ? [
                  BoxShadow(
                    color: AppConstants.primaryGreen
                        .withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: isSending
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              )
            : Text(
                !isOnline ? 'Offline — Cannot Send' : label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Broadcast History Card
// ─────────────────────────────────────────────────────────────────────────────

class _BroadcastHistoryCard extends StatelessWidget {
  final BroadcastModel broadcast;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _BroadcastHistoryCard({
    required this.broadcast,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final cfg   = _categoryConfig(broadcast.category, cs);
    final time  = _timeLabel(broadcast.sentAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cfg.bg,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Icon(cfg.icon, color: cfg.fg, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        broadcast.title,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cfg.bg,
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull),
                      ),
                      child: Text(
                        broadcast.category.label.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: cfg.fg,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Recipients: ${broadcast.recipientLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      time,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.outline,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.done_all_rounded,
                          size: 14,
                          color: AppConstants.successGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${broadcast.recipientCount} delivered',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.successGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _CategoryConfig _categoryConfig(
      BroadcastCategory cat, ColorScheme cs) {
    switch (cat) {
      case BroadcastCategory.meeting:
        return _CategoryConfig(
          icon: Icons.calendar_today_rounded,
          bg: AppConstants.primaryGreen.withValues(alpha: 0.10),
          fg: AppConstants.primaryGreen,
        );
      case BroadcastCategory.financial:
        return _CategoryConfig(
          icon: Icons.payments_rounded,
          bg: cs.errorContainer.withValues(alpha: 0.30),
          fg: cs.error,
        );
      case BroadcastCategory.harvest:
        return _CategoryConfig(
          icon: Icons.eco_rounded,
          bg: AppConstants.primaryContainer.withValues(alpha: 0.20),
          fg: AppConstants.primaryGreen,
        );
      case BroadcastCategory.update:
        return _CategoryConfig(
          icon: Icons.sync_rounded,
          bg: AppConstants.buyerBlue.withValues(alpha: 0.10),
          fg: AppConstants.buyerBlue,
        );
      case BroadcastCategory.general:
        return _CategoryConfig(
          icon: Icons.campaign_rounded,
          bg: AppConstants.amber.withValues(alpha: 0.15),
          fg: AppConstants.amber,
        );
    }
  }

  String _timeLabel(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return 'Today, ${_hhmm(dt)}';
    if (diff.inDays == 0)    return 'Today, ${_hhmm(dt)}';
    if (diff.inDays == 1)    return 'Yesterday, ${_hhmm(dt)}';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${_hhmm(dt)}';
  }

  String _hhmm(DateTime dt) {
    final h   = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
            : dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }
}

class _CategoryConfig {
  final IconData icon;
  final Color bg;
  final Color fg;
  const _CategoryConfig(
      {required this.icon, required this.bg, required this.fg});
}

// ─────────────────────────────────────────────────────────────────────────────
// Template Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TemplateSheet extends StatelessWidget {
  final List<BroadcastTemplate> templates;
  final ValueChanged<BroadcastTemplate> onSelected;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TemplateSheet({
    required this.templates,
    required this.onSelected,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.30),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Quick Templates',
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a template to pre-fill the compose form',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ...templates.map((tpl) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(tpl);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLg),
                      border: Border.all(
                        color: cs.outline.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _templateIcon(tpl.category),
                            color: cs.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tpl.title,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                tpl.category.label,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: cs.outline, size: 18),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  IconData _templateIcon(BroadcastCategory cat) {
    switch (cat) {
      case BroadcastCategory.meeting:   return Icons.calendar_today_rounded;
      case BroadcastCategory.financial: return Icons.payments_outlined;
      case BroadcastCategory.harvest:   return Icons.eco_outlined;
      case BroadcastCategory.update:    return Icons.sync_rounded;
      case BroadcastCategory.general:   return Icons.campaign_outlined;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _SectionLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty history state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyHistory({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.campaign_outlined,
                size: 40,
                color: cs.outline.withValues(alpha: 0.40)),
            const SizedBox(height: 10),
            Text(
              'No broadcasts yet',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
