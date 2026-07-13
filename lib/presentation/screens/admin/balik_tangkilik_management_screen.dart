import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/balik_tangkilik_model.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/balik_tangkilik_repository.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

/// Balik-Tangkilik Management — Admin.
/// Pushed above the shell. Route: /admin/balik-tangkilik
///
/// Three internal tabs (Settings / Distribution / History) live inside
/// this one screen — these are NOT shell-level navigation, just a local
/// TabBar, so nothing in app_router.dart needs to know about them. All
/// three are now functional; this completes the Balik-Tangkilik module.
class BalikTangkilikManagementScreen extends StatefulWidget {
  const BalikTangkilikManagementScreen({super.key});

  @override
  State<BalikTangkilikManagementScreen> createState() =>
      _BalikTangkilikManagementScreenState();
}

class _BalikTangkilikManagementScreenState
    extends State<BalikTangkilikManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs, sagana),
          _buildTabBar(context, l10n, cs),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _SettingsTab(),
                _DistributionTab(),
                _HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.reportsBalikTangkilikManagement,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: TabBar(
        controller: _tabController,
        labelColor: AppConstants.primaryGreen,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: AppConstants.primaryGreen,
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
        tabs: [
          Tab(text: l10n.balikTangkilikSettingsTab),
          Tab(text: l10n.balikTangkilikDistributionTab),
          Tab(text: l10n.balikTangkilikHistoryTab),
        ],
      ),
    );
  }
}

// ─── Shared row widget (used by Distribution + History drill-down) ─────────

class _MemberAmountRow extends StatelessWidget {
  final String farmerName;
  final String memberId;
  final String? subtitle;
  final double totalAmount;
  final double balikTangkilikAmount;
  final double interestAmount;
  final bool isPaid;

  const _MemberAmountRow({
    required this.farmerName,
    required this.memberId,
    this.subtitle,
    required this.totalAmount,
    required this.balikTangkilikAmount,
    required this.interestAmount,
    required this.isPaid,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmerName,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle ?? memberId,
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(currency.format(totalAmount), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
                  if (isPaid)
                    Text('PAID', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.successGreen)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            children: [
              Expanded(child: _stat('Balik-Tangkilik', currency.format(balikTangkilikAmount), cs)),
              Expanded(child: _stat('Interest', currency.format(interestAmount), cs)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface)),
      ],
    );
  }
}

// ─── Settings tab (validated, unchanged) ────────────────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _repo = BalikTangkilikRepository();
  final _totalCoopSalesController = TextEditingController();
  final _distributableSurplusController = TextEditingController();
  final _interestRateController = TextEditingController();

  late int _year;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _afsFinalized = false;
  double _liveTotalSales = 0;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _load();
  }

  @override
  void dispose() {
    _totalCoopSalesController.dispose();
    _distributableSurplusController.dispose();
    _interestRateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchYearSettings(_year),
      _repo.fetchLiveTotalCoopSales(_year),
    ]);
    if (!mounted) return;

    final settings = results[0] as CoopAnnualTotal?;
    _liveTotalSales = results[1] as double;

    if (settings != null) {
      _totalCoopSalesController.text = settings.totalCoopSales.toStringAsFixed(2);
      _distributableSurplusController.text = settings.distributableSurplus.toStringAsFixed(2);
      _interestRateController.text = settings.interestRatePercent.toStringAsFixed(2);
      _afsFinalized = settings.afsFinalized;
    } else {
      _totalCoopSalesController.text = _liveTotalSales.toStringAsFixed(2);
      _distributableSurplusController.text = '0.00';
      _interestRateController.text = '7.00';
      _afsFinalized = false;
    }

    setState(() => _isLoading = false);
  }

  void _setYear(int year) {
    setState(() => _year = year);
    _load();
  }

  void _useLiveTotal() {
    setState(() => _totalCoopSalesController.text = _liveTotalSales.toStringAsFixed(2));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final totalCoopSales = double.tryParse(_totalCoopSalesController.text.trim());
    final distributableSurplus = double.tryParse(_distributableSurplusController.text.trim());
    final interestRate = double.tryParse(_interestRateController.text.trim());

    if (totalCoopSales == null || totalCoopSales < 0 ||
        distributableSurplus == null || distributableSurplus < 0 ||
        interestRate == null || interestRate < 0) {
      _showSnack(l10n.balikTangkilikInvalidValues, isError: true);
      return;
    }

    if (_afsFinalized && distributableSurplus <= 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.balikTangkilikZeroPoolWarningTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Text(l10n.balikTangkilikZeroPoolWarningMessage, style: GoogleFonts.inter(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.issueLoanCancel)),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.balikTangkilikContinueAnyway, style: const TextStyle(color: AppConstants.errorRed)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);
    try {
      await _repo.saveYearSettings(
        year: _year,
        totalCoopSales: totalCoopSales,
        distributableSurplus: distributableSurplus,
        interestRatePercent: interestRate,
        afsFinalized: _afsFinalized,
      );
      if (!mounted) return;
      _showSnack(l10n.balikTangkilikSettingsSaved(_year));
    } catch (_) {
      if (!mounted) return;
      _showSnack(l10n.balikTangkilikSaveError, isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? AppConstants.errorRed : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        AppConstants.spacingGutter,
        AppConstants.spacingSafeH,
        32,
      ),
      children: [
        _buildYearChips(cs),
        const SizedBox(height: AppConstants.spacingSectionV),
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(l10n.balikTangkilikTotalCoopSales, cs),
              _numberField(_totalCoopSalesController, cs, sagana),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.balikTangkilikLiveTotalHint(currency.format(_liveTotalSales)),
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: _useLiveTotal,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                    child: Text(
                      l10n.balikTangkilikUseThisValue,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikPoolAmount, cs),
              _numberField(_distributableSurplusController, cs, sagana),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikPoolHint,
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikInterestRate, cs),
              _numberField(_interestRateController, cs, sagana, suffix: '%'),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikInterestHint,
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            color: _afsFinalized ? AppConstants.successGreen.withValues(alpha: 0.08) : sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: _afsFinalized ? AppConstants.successGreen.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.balikTangkilikAfsFinalized,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.balikTangkilikAfsFinalizedHint,
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _afsFinalized,
                onChanged: (v) => setState(() => _afsFinalized = v),
                activeThumbColor: AppConstants.successGreen,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        PrimaryButton(
          label: l10n.balikTangkilikSaveSettings,
          isLoading: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildYearChips(ColorScheme cs) {
    final currentYear = DateTime.now().year;
    final years = List.generate(5, (i) => currentYear - i);

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: years.map((y) {
          final active = _year == y;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$y', style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setYear(y),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _fieldLabel(String label, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    ColorScheme cs,
    SaganaColors sagana, {
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
      decoration: InputDecoration(
        prefixText: suffix == null ? '₱ ' : null,
        suffixText: suffix,
        isDense: true,
        filled: true,
        fillColor: sagana.cardBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
      ),
    );
  }
}

// ─── Distribution tab (validated, unchanged) ────────────────────────────────

class _DistributionTab extends StatefulWidget {
  const _DistributionTab();

  @override
  State<_DistributionTab> createState() => _DistributionTabState();
}

class _DistributionTabState extends State<_DistributionTab> {
  final _repo = BalikTangkilikRepository();

  late int _year;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isDistributing = false;
  BalikTangkilikYearSummary _summary = BalikTangkilikYearSummary.empty(DateTime.now().year);

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final summary = await _repo.fetchDistributionPreview(_year);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _isLoading = false;
    });
  }

  void _setYear(int year) {
    setState(() => _year = year);
    _load();
  }

  Future<void> _refreshEstimates() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isRefreshing = true);
    try {
      await _repo.refreshEstimates(_year);
      await _load();
      if (!mounted) return;
      _showSnack(l10n.balikTangkilikEstimatesRefreshed);
    } catch (_) {
      if (!mounted) return;
      _showSnack(l10n.balikTangkilikRefreshError, isError: true);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _confirmAndDistribute() async {
    final l10n = AppLocalizations.of(context);
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: AlertDialog(
        title: Text(l10n.balikTangkilikConfirmTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.balikTangkilikConfirmMessage(
                _year,
                _summary.contributingMemberCount,
                currency.format(_summary.totalEstimatedPayout),
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppConstants.errorRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.balikTangkilikIrreversibleWarning,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppConstants.errorRed),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.issueLoanCancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.balikTangkilikConfirmDistribute,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDistributing = true);
    try {
      await _repo.recordDistribution(_year);
      await _load();
      if (!mounted) return;
      _showSnack(l10n.balikTangkilikDistributionSuccess(currency.format(_summary.totalActualPayout)));
    } on StateError catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack(l10n.balikTangkilikDistributionError, isError: true);
    } finally {
      if (mounted) setState(() => _isDistributing = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? AppConstants.errorRed : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          32,
        ),
        children: [
          _buildYearChips(cs),
          const SizedBox(height: AppConstants.spacingGutter),
          if (!_summary.afsFinalized) _buildBlockingBanner(l10n.balikTangkilikAfsNotFinalizedWarning),
          if (_summary.afsFinalized && _summary.isDistributed) _buildDistributedBanner(l10n),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildSummaryCard(context, l10n, currency),
          const SizedBox(height: AppConstants.spacingGutter),
          OutlinedButton.icon(
            onPressed: (_summary.isDistributed || _isRefreshing || _isDistributing) ? null : _refreshEstimates,
            icon: _isRefreshing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(l10n.balikTangkilikRefreshEstimates),
          ),
          const SizedBox(height: AppConstants.spacingSectionV),
          Text(l10n.balikTangkilikMemberBreakdown, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingSm),
          if (_summary.rows.isEmpty)
            _buildEmptyState(l10n.reportsNoSearchResults, cs)
          else
            ..._summary.rows.map((r) => _MemberAmountRow(
                  farmerName: r.farmerName,
                  memberId: r.memberId,
                  subtitle: '${r.memberId} • ${r.sharePercent.toStringAsFixed(1)}% share',
                  totalAmount: r.isPaid ? r.actualTotal : r.estimatedTotal,
                  balikTangkilikAmount: r.isPaid ? (r.actualBalikTangkilik ?? 0) : r.estimatedBalikTangkilik,
                  interestAmount: r.isPaid ? (r.actualInterest ?? 0) : r.estimatedInterest,
                  isPaid: r.isPaid,
                )),
          const SizedBox(height: AppConstants.spacingSectionV),
          PrimaryButton(
            label: _summary.isDistributed
                ? l10n.balikTangkilikAlreadyDistributed(_year)
                : l10n.balikTangkilikRecordDistribution,
            isLoading: _isDistributing,
            onPressed: (!_summary.afsFinalized || _summary.isDistributed) ? null : _confirmAndDistribute,
          ),
        ],
      ),
    );
  }

  Widget _buildYearChips(ColorScheme cs) {
    final currentYear = DateTime.now().year;
    final years = List.generate(5, (i) => currentYear - i);
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: years.map((y) {
          final active = _year == y;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$y', style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setYear(y),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBlockingBanner(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.warningAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: AppConstants.warningAmber),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(child: Text(message, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.warningAmber))),
        ],
      ),
    );
  }

  Widget _buildDistributedBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: AppConstants.successGreen),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              l10n.balikTangkilikAlreadyDistributedBanner(_year),
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.successGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, AppLocalizations l10n, NumberFormat currency) {
    final displayTotal = _summary.isDistributed ? _summary.totalActualPayout : _summary.totalEstimatedPayout;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _summary.isDistributed
                ? l10n.balikTangkilikTotalDistributed(_year)
                : l10n.balikTangkilikTotalEstimated(_year),
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
          ),
          Text(
            currency.format(displayTotal),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 24, color: Colors.white),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(child: _summaryStat(l10n.balikTangkilikPoolAmount, currency.format(_summary.distributableSurplus))),
              Expanded(child: _summaryStat(l10n.balikTangkilikInterestRate, '${_summary.interestRatePercent.toStringAsFixed(2)}%')),
              Expanded(child: _summaryStat(l10n.reportsContributingMembers, '${_summary.contributingMemberCount} / ${_summary.rows.length}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9, color: Colors.white70)),
        Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
      ],
    );
  }

  Widget _buildEmptyState(String message, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}

// ─── History tab (NEW) ───────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _repo = BalikTangkilikRepository();

  bool _isLoading = true;
  List<DistributionHistoryYear> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final history = await _repo.fetchDistributionHistory();
    if (!mounted) return;
    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  void _openYearDetail(DistributionHistoryYear year) {
    AppBottomSheet.show(
      context: context,
      builder: (_) => _HistoryYearDetailSheet(year: year, repo: _repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          32,
        ),
        children: [
          Text(l10n.balikTangkilikHistoryTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingSm),
          if (_history.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingGutter),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Text(
                l10n.balikTangkilikNoHistoryYet,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            )
          else
            ..._history.map((year) => GestureDetector(
                  onTap: () => _openYearDetail(year),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
                    padding: const EdgeInsets.all(AppConstants.spacingMd),
                    decoration: BoxDecoration(
                      color: sagana.cardBackground,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppConstants.primaryContainer,
                            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${year.year}',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.balikTangkilikYearLogTitle(year.year),
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                              ),
                              Text(
                                l10n.balikTangkilikYearLogSubtitle(year.memberCount),
                                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currency.format(year.totalDistributed),
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: AppConstants.successGreen),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _HistoryYearDetailSheet extends StatefulWidget {
  final DistributionHistoryYear year;
  final BalikTangkilikRepository repo;

  const _HistoryYearDetailSheet({required this.year, required this.repo});

  @override
  State<_HistoryYearDetailSheet> createState() => _HistoryYearDetailSheetState();
}

class _HistoryYearDetailSheetState extends State<_HistoryYearDetailSheet> {
  bool _isLoading = true;
  List<MemberDistributionRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await widget.repo.fetchDistributionPreview(widget.year.year);
    if (!mounted) return;
    setState(() {
      _rows = summary.rows.where((r) => r.isPaid).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.balikTangkilikYearLogTitle(widget.year.year),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            l10n.balikTangkilikNoHistoryYet,
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final r = _rows[index];
                            return _MemberAmountRow(
                              farmerName: r.farmerName,
                              memberId: r.memberId,
                              subtitle: '${r.memberId} • ${r.sharePercent.toStringAsFixed(1)}% share',
                              totalAmount: r.actualTotal,
                              balikTangkilikAmount: r.actualBalikTangkilik ?? 0,
                              interestAmount: r.actualInterest ?? 0,
                              isPaid: true,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}