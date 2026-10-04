import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
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
import '../../widgets/app_toast.dart';
import '../../widgets/report_summary_widgets.dart';
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
    extends State<BalikTangkilikManagementScreen>
    with SingleTickerProviderStateMixin {
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSm,
          ),
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
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: TabBar(
        controller: _tabController,
        labelColor: AppConstants.primaryGreen,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: AppConstants.primaryGreen,
        labelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
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
  final String? subtitle;
  final double totalAmount;
  final double balikTangkilikAmount;
  final double interestAmount;
  final double purchasePatronageAmount;
  final bool isPaid;

  const _MemberAmountRow({
    required this.farmerName,
    this.subtitle,
    required this.totalAmount,
    required this.balikTangkilikAmount,
    required this.interestAmount,
    this.purchasePatronageAmount = 0,
    required this.isPaid,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

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
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                    Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(totalAmount),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                  if (isPaid)
                    Text(
                      l10n.balikTangkilikPaidBadge,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.successGreen,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            children: [
              Expanded(
                child: _stat(
                  'Balik-Tangkilik',
                  currency.format(balikTangkilikAmount),
                  cs,
                ),
              ),
              Expanded(
                child: _stat('Interest', currency.format(interestAmount), cs),
              ),
              // Option B — only shown when non-zero, so a farmer with no
              // Product Sales Program activity sees no change to this row.
              if (purchasePatronageAmount > 0)
                Expanded(
                  child: _stat(
                    'Purchase Patronage',
                    currency.format(purchasePatronageAmount),
                    cs,
                  ),
                ),
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
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: cs.onSurface,
          ),
        ),
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
  // Option B — Product Sales Program's own parallel settings. Never
  // combined with the sales-side controllers above.
  final _totalProgramSalesController = TextEditingController();
  final _distributableProgramSurplusController = TextEditingController();

  // Balik-Tangkilik is a once-a-year event (per the case study: distributed
  // at the Annual General Assembly, within the first 90 days of the year,
  // after the AFS is finalized) — Settings only ever needs to configure
  // the current cycle. A year selector was removed here (and in
  // Distribution) since History already covers reviewing past years.
  final int _year = DateTime.now().year;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _afsFinalized = false;
  bool _isDistributed = false;
  double _liveTotalSales = 0;
  double _liveTotalProgramSales = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _totalCoopSalesController.dispose();
    _distributableSurplusController.dispose();
    _interestRateController.dispose();
    _totalProgramSalesController.dispose();
    _distributableProgramSurplusController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchYearSettings(_year),
      _repo.fetchLiveTotalCoopSales(_year),
      _repo.fetchDistributionPreview(_year),
      _repo.fetchLiveTotalProgramSales(_year),
    ]);
    if (!mounted) return;

    final settings = results[0] as CoopAnnualTotal?;
    _liveTotalSales = results[1] as double;
    _isDistributed = (results[2] as BalikTangkilikYearSummary).isDistributed;
    _liveTotalProgramSales = results[3] as double;

    if (settings != null) {
      _totalCoopSalesController.text = settings.totalCoopSales.toStringAsFixed(
        2,
      );
      _distributableSurplusController.text = settings.distributableSurplus
          .toStringAsFixed(2);
      _interestRateController.text = settings.interestRatePercent
          .toStringAsFixed(2);
      _afsFinalized = settings.afsFinalized;
      _totalProgramSalesController.text = settings.totalProgramSales
          .toStringAsFixed(2);
      _distributableProgramSurplusController.text = settings
          .distributableProgramSurplus
          .toStringAsFixed(2);
    } else {
      _totalCoopSalesController.text = _liveTotalSales.toStringAsFixed(2);
      _distributableSurplusController.text = '0.00';
      _interestRateController.text = '7.00';
      _afsFinalized = false;
      _totalProgramSalesController.text = _liveTotalProgramSales
          .toStringAsFixed(2);
      _distributableProgramSurplusController.text = '0.00';
    }

    setState(() => _isLoading = false);
  }

  void _useLiveTotal() {
    setState(
      () => _totalCoopSalesController.text = _liveTotalSales.toStringAsFixed(2),
    );
  }

  void _useLiveProgramTotal() {
    setState(
      () => _totalProgramSalesController.text = _liveTotalProgramSales
          .toStringAsFixed(2),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_isDistributed) {
      _showSnack(
        l10n.balikTangkilikAlreadyDistributedBanner(_year),
        isError: true,
      );
      return;
    }
    final totalCoopSales = double.tryParse(
      _totalCoopSalesController.text.trim(),
    );
    final distributableSurplus = double.tryParse(
      _distributableSurplusController.text.trim(),
    );
    final interestRate = double.tryParse(_interestRateController.text.trim());
    // Option B fields default to 0 when left blank (a cooperative may not
    // run a Product Sales program every year) rather than blocking the
    // whole save — but an explicitly-entered negative is still rejected.
    final totalProgramSales =
        double.tryParse(_totalProgramSalesController.text.trim()) ?? 0;
    final distributableProgramSurplus =
        double.tryParse(_distributableProgramSurplusController.text.trim()) ??
        0;

    if (totalCoopSales == null ||
        totalCoopSales < 0 ||
        distributableSurplus == null ||
        distributableSurplus < 0 ||
        interestRate == null ||
        interestRate < 0 ||
        totalProgramSales < 0 ||
        distributableProgramSurplus < 0) {
      _showSnack(l10n.balikTangkilikInvalidValues, isError: true);
      return;
    }

    if (_afsFinalized && distributableSurplus <= 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            l10n.balikTangkilikZeroPoolWarningTitle,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: Text(
            l10n.balikTangkilikZeroPoolWarningMessage,
            style: GoogleFonts.inter(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.issueLoanCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                l10n.balikTangkilikContinueAnyway,
                style: const TextStyle(color: AppConstants.errorRed),
              ),
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
        totalProgramSales: totalProgramSales,
        distributableProgramSurplus: distributableProgramSurplus,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isError
            ? AppConstants.errorRed
            : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

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
              // Matches the Product Sales Program card's icon+title+hint
              // structure below, so both patronage sources follow the
              // same visual hierarchy.
              Row(
                children: [
                  const Icon(
                    Icons.handshake_rounded,
                    size: 16,
                    color: AppConstants.primaryGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.balikTangkilikSalesSectionTitle,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikSalesSectionHint,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikTotalCoopSales, cs),
              _numberField(_totalCoopSalesController, cs, sagana),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.balikTangkilikLiveTotalHint(
                        currency.format(_liveTotalSales),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _useLiveTotal,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: Text(
                      l10n.balikTangkilikUseThisValue,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _totalCoopSalesController,
                builder: (context, value, _) {
                  if (_liveTotalSales <= 0) return const SizedBox.shrink();
                  final entered = double.tryParse(value.text.trim()) ?? 0;
                  final diffPercent =
                      ((entered - _liveTotalSales).abs() / _liveTotalSales) *
                      100;
                  if (diffPercent < 1) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppConstants.warningAmber.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusSm,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppConstants.warningAmber,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.balikTangkilikReconciliationHint(
                                currency.format(entered),
                                currency.format(_liveTotalSales),
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikPoolAmount, cs),
              _numberField(_distributableSurplusController, cs, sagana),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikPoolHint,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikInterestRate, cs),
              _numberField(_interestRateController, cs, sagana, suffix: '%'),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikInterestHint,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        // Option B — Product Sales Program's own settings card, kept
        // visually separate from Cooperative Sales above so the two
        // patronage sources are never confused for one combined pool.
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: AppConstants.buyerBlue.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    size: 16,
                    color: AppConstants.buyerBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.balikTangkilikProgramSectionTitle,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikProgramSectionHint,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikTotalProgramSales, cs),
              _numberField(_totalProgramSalesController, cs, sagana),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.balikTangkilikLiveProgramTotalHint(
                        currency.format(_liveTotalProgramSales),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _useLiveProgramTotal,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: Text(
                      l10n.balikTangkilikUseThisValue,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.buyerBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingGutter),
              _fieldLabel(l10n.balikTangkilikProgramPoolAmount, cs),
              _numberField(_distributableProgramSurplusController, cs, sagana),
              const SizedBox(height: 4),
              Text(
                l10n.balikTangkilikProgramPoolHint,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            color: _afsFinalized
                ? AppConstants.successGreen.withValues(alpha: 0.08)
                : sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: _afsFinalized
                  ? AppConstants.successGreen.withValues(alpha: 0.3)
                  : cs.outline.withValues(alpha: 0.10),
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
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.balikTangkilikAfsFinalizedHint,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
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

  Widget _fieldLabel(String label, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
      ),
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
      inputFormatters: [
        // Digits with at most one decimal point — these are always
        // non-negative amounts/rates, unlike the capital-contribution
        // ledger's manual_adjustment entries which allow a sign.
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: cs.onSurface,
      ),
      decoration: InputDecoration(
        prefixText: suffix == null ? '₱ ' : null,
        suffixText: suffix,
        isDense: true,
        filled: true,
        fillColor: sagana.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        ),
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

  // See _SettingsTabState's _year comment — Balik-Tangkilik is a once-a-
  // year event; Distribution always operates on the current cycle, and
  // History covers reviewing past years.
  final int _year = DateTime.now().year;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isDistributing = false;
  BalikTangkilikYearSummary _summary = BalikTangkilikYearSummary.empty(
    DateTime.now().year,
  );

  @override
  void initState() {
    super.initState();
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
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: AlertDialog(
        title: Text(
          l10n.balikTangkilikConfirmTitle,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
        ),
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
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppConstants.errorRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.balikTangkilikIrreversibleWarning,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.errorRed,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.issueLoanCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.balikTangkilikConfirmDistribute,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
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
      _showSnack(
        l10n.balikTangkilikDistributionSuccess(
          currency.format(_summary.totalActualPayout),
        ),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isError
            ? AppConstants.errorRed
            : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

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
          if (!_summary.afsFinalized)
            _buildBlockingBanner(l10n.balikTangkilikAfsNotFinalizedWarning),
          if (_summary.afsFinalized && _summary.isDistributed)
            _buildDistributedBanner(l10n),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildSummaryCard(context, l10n, currency),
          const SizedBox(height: AppConstants.spacingGutter),
          OutlinedButton.icon(
            onPressed:
                (_summary.isDistributed || _isRefreshing || _isDistributing)
                ? null
                : _refreshEstimates,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(l10n.balikTangkilikRefreshEstimates),
          ),
          const SizedBox(height: AppConstants.spacingSectionV),
          Text(
            l10n.balikTangkilikMemberBreakdown,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          if (_summary.rows.isEmpty)
            ReportEmptyState(message: l10n.reportsNoSearchResults)
          else
            ..._summary.rows.map(
              (r) => _MemberAmountRow(
                  farmerName: r.farmerName,
                subtitle: '${r.sharePercent.toStringAsFixed(1)}% share',
                  totalAmount: r.isPaid ? r.actualTotal : r.estimatedTotal,
                balikTangkilikAmount: r.isPaid
                    ? (r.actualBalikTangkilik ?? 0)
                    : r.estimatedBalikTangkilik,
                interestAmount: r.isPaid
                    ? (r.actualInterest ?? 0)
                    : r.estimatedInterest,
                purchasePatronageAmount: r.isPaid
                    ? (r.actualPurchasePatronage ?? 0)
                    : r.estimatedPurchasePatronage,
                  isPaid: r.isPaid,
              ),
            ),
          const SizedBox(height: AppConstants.spacingSectionV),
          PrimaryButton(
            label: _summary.isDistributed
                ? l10n.balikTangkilikAlreadyDistributed(_year)
                : l10n.balikTangkilikRecordDistribution,
            isLoading: _isDistributing,
            onPressed: (!_summary.afsFinalized || _summary.isDistributed)
                ? null
                : _confirmAndDistribute,
          ),
        ],
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
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: AppConstants.warningAmber,
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.warningAmber,
              ),
            ),
          ),
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
        border: Border.all(
          color: AppConstants.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppConstants.successGreen,
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              l10n.balikTangkilikAlreadyDistributedBanner(_year),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.successGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    AppLocalizations l10n,
    NumberFormat currency,
  ) {
    final displayTotal = _summary.isDistributed
        ? _summary.totalActualPayout
        : _summary.totalEstimatedPayout;
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
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          Text(
            currency.format(displayTotal),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  l10n.balikTangkilikPoolAmount,
                  currency.format(_summary.distributableSurplus),
                ),
              ),
              Expanded(
                child: _summaryStat(
                  l10n.balikTangkilikInterestRate,
                  '${_summary.interestRatePercent.toStringAsFixed(2)}%',
                ),
              ),
              Expanded(
                child: _summaryStat(
                  l10n.reportsContributingMembers,
                  '${_summary.contributingMemberCount} / ${_summary.rows.length}',
                ),
              ),
            ],
          ),
          // Option B — a separate row, only shown when the program pool is
          // actually in use, so a year with no Product Sales activity
          // looks exactly as it did before this feature existed.
          if (_summary.distributableProgramSurplus > 0) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
            const SizedBox(height: AppConstants.spacingSm),
            Row(
              children: [
                Expanded(
                  child: _summaryStat(
                    l10n.balikTangkilikProgramPoolAmount,
                    currency.format(_summary.distributableProgramSurplus),
                  ),
                ),
                Expanded(
                  child: _summaryStat(
                    l10n.balikTangkilikTotalProgramSales,
                    currency.format(_summary.totalProgramSales),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 9, color: Colors.white70),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
      ],
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryYearScreen(year: year, repo: _repo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );

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
          Text(
            l10n.balikTangkilikHistoryTitle,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          if (_history.isEmpty)
            ReportEmptyState(message: l10n.balikTangkilikNoHistoryYet)
          else
            ..._history.map(
              (year) => GestureDetector(
                  onTap: () => _openYearDetail(year),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
                    padding: const EdgeInsets.all(AppConstants.spacingMd),
                    decoration: BoxDecoration(
                      color: sagana.cardBackground,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.10),
                    ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppConstants.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${year.year}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.balikTangkilikYearLogTitle(year.year),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                              ),
                              Text(
                              l10n.balikTangkilikYearLogSubtitle(
                                year.memberCount,
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currency.format(year.totalDistributed),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppConstants.successGreen,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                            ),
                          ],
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

// ─────────────────────────────────────────────────────────────────────────────
// History Year Screen — a full pushed screen (not a bottom sheet), matching
// the rest of Admin's report-style detail screens (see Sales Report's own
// top bar for the pattern this mirrors). Distribution History is a real
// record-review module, not a quick glance, so it gets the same weight as
// every other "drill into one year/one record" screen in this app.
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryYearScreen extends StatefulWidget {
  final DistributionHistoryYear year;
  final BalikTangkilikRepository repo;

  const _HistoryYearScreen({required this.year, required this.repo});

  @override
  State<_HistoryYearScreen> createState() => _HistoryYearScreenState();
}

class _HistoryYearScreenState extends State<_HistoryYearScreen> {
  bool _isLoading = true;
  List<MemberDistributionRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final summary = await widget.repo.fetchDistributionPreview(
      widget.year.year,
    );
    if (!mounted) return;
    setState(() {
      _rows = summary.rows.where((r) => r.isPaid).toList()
        ..sort((a, b) => b.actualTotal.compareTo(a.actualTotal));
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final totalDistributed = _rows.fold<double>(
      0,
      (sum, r) => sum + r.actualTotal,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.balikTangkilikYearLogTitle(widget.year.year),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        32,
                      ),
                      children: [
                        // Year summary card — the same "hero" weight every
                        // other report's landing figure gets.
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(
                            AppConstants.spacingGutter,
                          ),
                          decoration: BoxDecoration(
                            color: sagana.cardBackground,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusLg,
                            ),
                            border: Border.all(
                              color: cs.outline.withValues(alpha: 0.10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppConstants.primaryContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusMd,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${widget.year.year}',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppConstants.spacingMd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Distributed',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      currency.format(totalDistributed),
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                        color: AppConstants.successGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Members',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '${_rows.length}',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        Text(
                          'Member Records',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingSm),
                        if (_rows.isEmpty)
                          ReportEmptyState(
                            message: l10n.balikTangkilikNoHistoryYet,
                          )
                        else
                          ..._rows.map(
                            (r) => _HistoryMemberCard(
                              row: r,
                              year: widget.year.year,
                              repo: widget.repo,
                              onChanged: _load,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// A richer per-farmer card than the compact _MemberAmountRow (still used
// as-is by the Distribution tab, unchanged) — History is a record you sit
// with and review, so the breakdown gets its own clearly-labeled section
// and more generous spacing rather than being packed into a 3-column row.
class _HistoryMemberCard extends StatelessWidget {
  final MemberDistributionRow row;
  final int year;
  final BalikTangkilikRepository repo;
  final VoidCallback onChanged;

  const _HistoryMemberCard({
    required this.row,
    required this.year,
    required this.repo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final r = row;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                      r.farmerName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.sharePercent.toStringAsFixed(1)}% share',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(r.actualTotal),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.successGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      l10n.balikTangkilikPaidBadge,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.successGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            ),
            const SizedBox(height: AppConstants.spacingMd),
          Container(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'Payout Breakdown',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _breakdownStat(
                l10n,
                'Balik-Tangkilik',
                currency.format(r.actualBalikTangkilik ?? 0),
                cs,
              ),
              _breakdownStat(
                l10n,
                'Interest',
                currency.format(r.actualInterest ?? 0),
                cs,
              ),
              if ((r.actualPurchasePatronage ?? 0) > 0)
                _breakdownStat(
                  l10n,
                  'Purchase Patronage',
                  currency.format(r.actualPurchasePatronage ?? 0),
                  cs,
                ),
            ],
          ),
          if (r.payoutDecision != null) ...[
            const SizedBox(height: AppConstants.spacingSm),
            _PayoutDecisionStatus(
              row: r,
              year: year,
              repo: repo,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }

  Widget _breakdownStat(
    AppLocalizations l10n,
    String label,
    String value,
    ColorScheme cs,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payout Decision Status — shown under a paid member's row in the History
// year detail sheet whenever they've submitted a cash/capital choice.
// Confirm/Reject mirror confirm_program_purchase()/decline_cooperative_
// offer()'s existing request-then-confirm shape. Uses AppToast rather than
// ScaffoldMessenger since this widget lives inside a modal sheet
// (showManagementModal) — a plain SnackBar would render behind the sheet.
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutDecisionStatus extends StatefulWidget {
  final MemberDistributionRow row;
  final int year;
  final BalikTangkilikRepository repo;
  final VoidCallback onChanged;

  const _PayoutDecisionStatus({
    required this.row,
    required this.year,
    required this.repo,
    required this.onChanged,
  });

  @override
  State<_PayoutDecisionStatus> createState() => _PayoutDecisionStatusState();
}

class _PayoutDecisionStatusState extends State<_PayoutDecisionStatus> {
  bool _isBusy = false;

  Future<void> _confirm() async {
    final r = widget.row;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final isCash = r.payoutDecision == 'pending_cash';
    final message = isCash
        ? 'Confirm that ${r.farmerName} has received ${currency.format(r.payoutDecisionAmount ?? 0)} in cash?'
        : 'Confirm adding ${currency.format(r.payoutDecisionAmount ?? 0)} to ${r.farmerName}\'s capital share? This cannot be undone.';

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: AlertDialog(
        title: Text(
          'Confirm Payout Decision',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await widget.repo.confirmPayoutDecision(
        farmerId: r.farmerId,
        year: widget.year,
      );
      if (!mounted) return;
      AppToast.show(context, 'Payout decision confirmed for ${r.farmerName}.');
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Could not confirm: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _reject() async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: AlertDialog(
        title: Text(
          'Reject Payout Decision',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'This sends the decision back so ${widget.row.farmerName} can submit a corrected choice. Continue?',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Reject',
              style: TextStyle(color: AppConstants.errorRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await widget.repo.rejectPayoutDecision(
        farmerId: widget.row.farmerId,
        year: widget.year,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        'Payout decision rejected — ${widget.row.farmerName} can resubmit.',
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Could not reject: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final isPending = r.hasPendingPayoutDecision;
    final isCash =
        r.payoutDecision == 'pending_cash' ||
        r.payoutDecision == 'cash_confirmed';
    final amountLabel = currency.format(r.payoutDecisionAmount ?? 0);
    final choiceLabel = isCash
        ? 'Keep as Cash — $amountLabel'
        : 'Add to Capital — $amountLabel';
    final statusColor = isPending
        ? AppConstants.warningAmber
        : AppConstants.successGreen;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPending
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle_rounded,
                size: 14,
                color: statusColor,
              ),
              const SizedBox(width: 6),
            Expanded(
                          child: Text(
                  '${isPending ? "Pending: " : "Confirmed: "}$choiceLabel',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isBusy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.errorRed,
                      side: const BorderSide(color: AppConstants.errorRed),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: Text(
                      'Reject',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isBusy ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: _isBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                          ),
                        )
                        : Text(
                            'Confirm',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
            ),
          ],
        ),
          ],
        ],
      ),
    );
  }
}