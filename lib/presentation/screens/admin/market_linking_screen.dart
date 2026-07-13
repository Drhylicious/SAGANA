import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

class MarketLinkingScreen extends StatefulWidget {
  const MarketLinkingScreen({super.key});

  @override
  State<MarketLinkingScreen> createState() => _MarketLinkingScreenState();
}

class _MarketLinkingScreenState extends State<MarketLinkingScreen> {
  final _repo = MarketLinkingRepository();

  List<MarketLinkingModel> _entries = [];
  bool _isLoading = true;
  bool _isOnline = true;
  MarketLinkingStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await _repo.fetchAll(statusFilter: _statusFilter?.value);
    if (!mounted) return;
    setState(() {
      _entries = data;
      _isLoading = false;
    });
  }

  void _onFilterChanged(MarketLinkingStatus? status) {
    setState(() => _statusFilter = status);
    _load();
  }

  // counts
  int get _submittedCount =>
      _entries.where((e) => e.status == MarketLinkingStatus.submitted).length;
  int get _buyerFoundCount =>
      _entries.where((e) => e.status == MarketLinkingStatus.buyerFound).length;
  int get _completedCount =>
      _entries.where((e) => e.status == MarketLinkingStatus.completed).length;

  void _showStatusSheet(MarketLinkingModel entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _UpdateStatusSheet(entry: entry, repo: _repo, onSaved: _load),
    );
  }

  void _showEnrollSheet() async {
    final farmers = await _repo.fetchUnenrolledGingerFarmers();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EnrollFarmerSheet(farmers: farmers, repo: _repo, onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              // Filter chips
              _FilterBar(
                selected: _statusFilter,
                onChanged: _onFilterChanged,
                cs: cs,
                sagana: sagana,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
                          children: [
                            // Summary banner
                            _SummaryBanner(
                              submitted: _submittedCount,
                              buyerFound: _buyerFoundCount,
                              completed: _completedCount,
                              cs: cs,
                              sagana: sagana,
                            ),
                            const SizedBox(height: 16),

                            // DA-AMAD info card
                            _DaAmadInfoCard(cs: cs),
                            const SizedBox(height: 16),

                            if (_entries.isEmpty)
                              _EmptyState(
                                hasFilter: _statusFilter != null,
                                cs: cs,
                                onEnroll: _isOnline ? _showEnrollSheet : null,
                              )
                            else ...[
                              ..._entries.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _EntryCard(
                                    entry: e,
                                    cs: cs,
                                    sagana: sagana,
                                    onUpdateStatus: _isOnline
                                        ? () => _showStatusSheet(e)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ],
          ),

          // Top App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              onBack: () => context.pop(),
              onEnroll: _isOnline ? _showEnrollSheet : null,
              sagana: sagana,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
class _TopAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onEnroll;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopAppBar({
    required this.onBack,
    this.onEnroll,
    required this.sagana,
    required this.cs,
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
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Market Linking',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      'Ginger Program — DA-AMAD',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEnroll != null)
                GestureDetector(
                  onTap: onEnroll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.tertiaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          size: 16,
                          color: AppConstants.onTertiaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Enroll',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.push(AppRoutes.buyerManagement),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_alt_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Buyers',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Filter Bar ───────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final MarketLinkingStatus? selected;
  final ValueChanged<MarketLinkingStatus?> onChanged;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _FilterBar({
    required this.selected,
    required this.onChanged,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: sagana.cardBackground,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _Chip(
              label: 'All',
              active: selected == null,
              color: cs.primary,
              onTap: () => onChanged(null),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Submitted',
              active: selected == MarketLinkingStatus.submitted,
              color: AppConstants.warningAmber,
              onTap: () => onChanged(MarketLinkingStatus.submitted),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Buyer Found',
              active: selected == MarketLinkingStatus.buyerFound,
              color: AppConstants.buyerBlue,
              onTap: () => onChanged(MarketLinkingStatus.buyerFound),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Completed',
              active: selected == MarketLinkingStatus.completed,
              color: AppConstants.successGreen,
              onTap: () => onChanged(MarketLinkingStatus.completed),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Cancelled',
              active: selected == MarketLinkingStatus.cancelled,
              color: cs.outline,
              onTap: () => onChanged(MarketLinkingStatus.cancelled),
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _Chip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

// ─── Summary Banner ───────────────────────────────────────────────────────────
class _SummaryBanner extends StatelessWidget {
  final int submitted, buyerFound, completed;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _SummaryBanner({
    required this.submitted,
    required this.buyerFound,
    required this.completed,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppConstants.tertiaryContainer,
            AppConstants.primaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SumStat(
            value: '$submitted',
            label: 'Enrolled',
            color: Colors.white70,
          ),
          _Divider(),
          _SumStat(
            value: '$buyerFound',
            label: 'Buyer Found',
            color: Colors.white70,
          ),
          _Divider(),
          _SumStat(
            value: '$completed',
            label: 'Completed',
            color: Colors.white70,
          ),
        ],
      ),
    );
  }
}

class _SumStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _SumStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: color)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: Colors.white.withValues(alpha: 0.25),
  );
}

// ─── DA-AMAD Info Card ────────────────────────────────────────────────────────
class _DaAmadInfoCard extends StatelessWidget {
  final ColorScheme cs;
  const _DaAmadInfoCard({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.tertiaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.onTertiaryContainer.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🌿', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DA-AMAD Ginger Market Linking',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Links SP3 Ginger farmers directly to DA-AMAD institutional '
                  'buyers for premium export pricing. Farmers enrolled here '
                  'bypass the open marketplace for their Ginger harvest.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
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

// ─── Entry Card ───────────────────────────────────────────────────────────────
class _EntryCard extends StatelessWidget {
  final MarketLinkingModel entry;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback? onUpdateStatus;
  const _EntryCard({
    required this.entry,
    required this.cs,
    required this.sagana,
    this.onUpdateStatus,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(entry.status, cs);

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(
          left: BorderSide(color: statusColor, width: 4),
          top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
          right: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.tertiaryContainer.withValues(
                      alpha: 0.15,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      entry.initials,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.tertiaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.farmerName,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      if (entry.sitio != null)
                        Text(
                          entry.sitio!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    entry.status.label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details row
          if (entry.volumeKg != null || entry.buyerName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  if (entry.volumeKg != null) ...[
                    Icon(Icons.scale_outlined, size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.volumeKg!.toStringAsFixed(0)} kg',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (entry.pricePerKg != null) ...[
                    Icon(Icons.payments_outlined, size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Text(
                      '₱${entry.pricePerKg!.toStringAsFixed(2)}/kg',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (entry.buyerName != null) ...[
                    Icon(Icons.handshake_outlined, size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.buyerName!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          if (entry.notes != null && entry.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Text(
                  entry.notes!,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),

          // Action row
          if (entry.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onUpdateStatus,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: onUpdateStatus != null
                              ? AppConstants.tertiaryContainer
                              : cs.outline.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.update_rounded,
                              size: 15,
                              color: onUpdateStatus != null
                                  ? AppConstants.onTertiaryContainer
                                  : cs.outline,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Update Status',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: onUpdateStatus != null
                                    ? AppConstants.onTertiaryContainer
                                    : cs.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (entry.status == MarketLinkingStatus.buyerFound) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: onUpdateStatus,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppConstants.primaryGreen,
                                AppConstants.successGreen,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.handshake_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Confirm Sale',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(MarketLinkingStatus s, ColorScheme cs) {
    switch (s) {
      case MarketLinkingStatus.submitted:
        return AppConstants.warningAmber;
      case MarketLinkingStatus.buyerFound:
        return AppConstants.buyerBlue;
      case MarketLinkingStatus.completed:
        return AppConstants.successGreen;
      case MarketLinkingStatus.cancelled:
        return cs.outline;
    }
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final ColorScheme cs;
  final VoidCallback? onEnroll;
  const _EmptyState({required this.hasFilter, required this.cs, this.onEnroll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Text('🌿', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          Text(
            hasFilter
                ? 'No farmers match this status'
                : 'No Ginger farmers enrolled yet',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilter
                ? 'Try a different filter'
                : 'Tap Enroll to add Ginger farmers to the DA-AMAD program',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (onEnroll != null && !hasFilter) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onEnroll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(
                  'Enroll Farmer',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.onTertiaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Update Status Bottom Sheet ───────────────────────────────────────────────
class _UpdateStatusSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final MarketLinkingRepository repo;
  final VoidCallback onSaved;
  const _UpdateStatusSheet({
    required this.entry,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  late MarketLinkingStatus _selectedStatus;
  final _buyerNameCtrl = TextEditingController();
  final _buyerContactCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.entry.status;
    _buyerNameCtrl.text = widget.entry.buyerName ?? '';
    _buyerContactCtrl.text = widget.entry.buyerContact ?? '';
    _priceCtrl.text = widget.entry.pricePerKg?.toStringAsFixed(2) ?? '';
    _notesCtrl.text = widget.entry.notes ?? '';
  }

  @override
  void dispose() {
    _buyerNameCtrl.dispose();
    _buyerContactCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.repo.updateStatus(
        id: widget.entry.id,
        newStatus: _selectedStatus,
        buyerName: _buyerNameCtrl.text.trim().isEmpty
            ? null
            : _buyerNameCtrl.text.trim(),
        buyerContact: _buyerContactCtrl.text.trim().isEmpty
            ? null
            : _buyerContactCtrl.text.trim(),
        pricePerKg: double.tryParse(_priceCtrl.text.trim()),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
      child: SingleChildScrollView(
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
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Update Status — ${widget.entry.farmerName}',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),

            // Status selector
            _FieldLabel(label: 'New Status', cs: cs),
            Row(
              children: MarketLinkingStatus.values
                  .where((s) => s != MarketLinkingStatus.submitted)
                  .map(
                    (s) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedStatus = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedStatus == s
                                  ? _statusColor(s, cs)
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: Text(
                              s.label,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _selectedStatus == s
                                    ? Colors.white
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),

            // Buyer info (if buyer_found or completed)
            if (_selectedStatus == MarketLinkingStatus.buyerFound ||
                _selectedStatus == MarketLinkingStatus.completed) ...[
              _FieldLabel(label: 'Buyer Name', cs: cs),
              TextFormField(
                controller: _buyerNameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. DA-AMAD Collector, Marinduque',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                ),
              ),
              const SizedBox(height: 12),
              _FieldLabel(label: 'Agreed Price (₱/kg)', cs: cs),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  hintText: '0.00',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Notes
            _FieldLabel(label: 'Notes (optional)', cs: cs),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Additional notes or cancellation reason...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
            ),
            const SizedBox(height: 20),

            // Save button
            GestureDetector(
              onTap: _isSaving ? null : _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: _isSaving
                      ? cs.primary.withValues(alpha: 0.50)
                      : cs.primary,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: _isSaving
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        'Save Changes',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(MarketLinkingStatus s, ColorScheme cs) {
    switch (s) {
      case MarketLinkingStatus.buyerFound:
        return AppConstants.buyerBlue;
      case MarketLinkingStatus.completed:
        return AppConstants.successGreen;
      case MarketLinkingStatus.cancelled:
        return cs.outline;
      default:
        return AppConstants.warningAmber;
    }
  }
}

// ─── Enroll Farmer Sheet ──────────────────────────────────────────────────────
class _EnrollFarmerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> farmers;
  final MarketLinkingRepository repo;
  final VoidCallback onSaved;
  const _EnrollFarmerSheet({
    required this.farmers,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_EnrollFarmerSheet> createState() => _EnrollFarmerSheetState();
}

class _EnrollFarmerSheetState extends State<_EnrollFarmerSheet> {
  String? _selectedFarmerId;
  final _volumeCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _volumeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    if (_selectedFarmerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a farmer.')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.enrollFarmer(
        farmerId: _selectedFarmerId!,
        volumeKg: double.tryParse(_volumeCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to enroll. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
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
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Enroll Ginger Farmer',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          _FieldLabel(label: 'Select Farmer', cs: cs),
          widget.farmers.isEmpty
              ? Text(
                  'All Ginger farmers are already enrolled this season.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                )
              : DropdownButtonFormField<String>(
                  initialValue: _selectedFarmerId,
                  hint: Text(
                    'Select a Ginger farmer',
                    style: GoogleFonts.inter(fontSize: 14, color: cs.outline),
                  ),
                  items: widget.farmers
                      .map(
                        (f) => DropdownMenuItem(
                          value: f['id'] as String,
                          child: Text(
                            '${f['name']}'
                            '${f['sitio'] != null ? ' — ${f['sitio']}' : ''}',
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedFarmerId = v),
                ),
          const SizedBox(height: 14),

          _FieldLabel(label: 'Committed Volume (kg) — optional', cs: cs),
          TextFormField(
            controller: _volumeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'e.g. 500',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 20),

          if (widget.farmers.isNotEmpty)
            GestureDetector(
              onTap: _isSaving ? null : _enroll,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: _isSaving
                      ? AppConstants.tertiaryContainer.withValues(alpha: 0.50)
                      : AppConstants.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: _isSaving
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        'Enroll in DA-AMAD Program',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.onTertiaryContainer,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: cs.onSurfaceVariant,
      ),
    ),
  );
}
