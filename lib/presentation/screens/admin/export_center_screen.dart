import 'dart:io';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../data/services/pdf_export_service.dart';
import '../../../data/services/report_download_service.dart';
import '../../../data/services/hive_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../../data/models/admin_log_message.dart';

/// Export Center — Admin.
/// Pushed above the shell. Route: /admin/export
///
/// Three steps on one screen — choose reports, choose the period, choose the
/// format — with a bar at the bottom that always says what will be exported and
/// holds the Generate button. Both PDF and CSV are offered; the Manager picks
/// per export. Purely an orchestration and serialization layer either way:
/// every fetch goes through the same repository methods each report screen
/// already uses, so a file always matches what that report shows.
class ExportCenterScreen extends StatefulWidget {
  final ExportCenterArgs? args;

  const ExportCenterScreen({super.key, this.args});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  final _csvService = CsvExportService();
  final _pdfService = PdfExportService();
  final _downloadService = ReportDownloadService();
  final _reportsRepo = AdminReportsRepository();

  final Set<ReportModuleType> _selectedModules = {};
  ReportPeriod _period = ReportPeriod.thisMonth;
  late int _contributionYear;
  String _format = 'pdf';
  bool _isGenerating = false;
  bool _isDownloading = false;
  bool get _isBusy => _isGenerating || _isDownloading;
  List<ExportHistoryEntry> _history = [];
  List<int> _availableContributionYears = [DateTime.now().year];
  // Files made by the most recent Generate, shown in the "Export ready" card.
  List<String> _lastExportPaths = [];

  bool get _needsYearSelector =>
      _selectedModules.contains(ReportModuleType.memberContribution);

  /// Whether the chosen reports use the period at all. With nothing chosen yet
  /// the period stays available, so it can be set before or after picking.
  bool get _periodApplies =>
      _selectedModules.isEmpty ||
      _selectedModules.any((m) => m.usesReportPeriod);

  @override
  void initState() {
    super.initState();
    _contributionYear = widget.args?.contributionYear ?? DateTime.now().year;
    if (widget.args?.period != null) _period = widget.args!.period!;
    if (widget.args?.preselectedModule != null) {
      _selectedModules.add(widget.args!.preselectedModule!);
    }
    _loadHistory();
    _loadAvailableContributionYears();
  }

  Future<void> _loadAvailableContributionYears() async {
    final years = await _reportsRepo.fetchAvailablePatronageYears();
    if (!mounted) return;
    setState(() => _availableContributionYears = years);
  }

  void _loadHistory() {
    final raw = HiveService.getExportHistory();
    setState(() => _history = raw.map(ExportHistoryEntry.fromMap).toList());
  }

  void _toggleModule(ReportModuleType module) {
    setState(() {
      if (!_selectedModules.remove(module)) _selectedModules.add(module);
    });
  }

  void _applyPreset(CompliancePreset preset) {
    setState(() {
      _selectedModules
        ..clear()
        ..addAll(preset.modules);
    });
  }

  Future<void> _generate() async {
    if (_isBusy) return;
    if (!requireManage(context, StaffModule.reports)) return;
    final l10n = AppLocalizations.of(context);
    if (_selectedModules.isEmpty) {
      PostActionFeedback.error(context, l10n.exportSelectAtLeastOne);
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final ReportExportService service = _format == 'pdf'
          ? _pdfService
          : _csvService;
      final paths = await service.generateExports(
        modules: _selectedModules,
        period: _period,
        contributionYear: _contributionYear,
      );
      _loadHistory();
      AdminActivityRepository().log(
        module: 'reports',
        actionType: 'exported',
        message: AdminLogMessage('adminLogExportGenerated', {
          'format': _format.toUpperCase(),
          'count': '${_selectedModules.length}',
        }),
      );
      if (!mounted) return;
      setState(() => _lastExportPaths = paths);
      if (paths.isNotEmpty) {
        await _download(paths);
      }
    } catch (e, st) {
      debugPrint('[ExportCenter] generateExports failed: $e\n$st');
      if (!mounted) return;
      PostActionFeedback.error(context, l10n.exportGenerateError);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _download(List<String> paths) async {
    if (_isDownloading || paths.isEmpty) return;
    if (!requireManage(context, StaffModule.reports)) return;
    final l10n = AppLocalizations.of(context);
    final saved = <String>[];
    setState(() => _isDownloading = true);
    try {
      for (final path in paths) {
        // Access may change while generation or a previous file is in progress.
        if (!canManageModule(StaffModule.reports)) {
          throw PlatformException(code: 'reports_access_denied');
        }
        saved.add(await _downloadService.save(path));
      }
      if (!mounted) return;
      PostActionFeedback.success(context, _savedMessage(l10n, saved));
    } catch (error, stack) {
      debugPrint('[ExportCenter] download failed: $error\n$stack');
      if (!mounted) return;
      final code = error is PlatformException ? error.code : 'save_failed';
      final reason = switch (code) {
        'permission_denied' => l10n.exportDownloadPermissionDenied,
        'file_missing' => l10n.exportFileMissing,
        'unsupported_platform' => l10n.exportDownloadUnsupported,
        'reports_access_denied' => l10n.staffViewOnlyAction,
        _ => l10n.exportDownloadError,
      };
      PostActionFeedback.error(
        context,
        saved.isEmpty ? reason : '${_savedMessage(l10n, saved)} $reason',
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// "Saved to Downloads: name.pdf" for one file, "3 reports saved to
  /// Downloads." for several, so the message never runs off the screen.
  String _savedMessage(AppLocalizations l10n, List<String> saved) =>
      saved.length == 1
      ? l10n.exportDownloadSaved(saved.first)
      : l10n.exportDownloadSavedMany(saved.length);

  Future<void> _shareLastExport() async {
    if (_isBusy || !requireManage(context, StaffModule.reports)) return;
    final existing = _lastExportPaths.where((p) => File(p).existsSync());
    if (existing.isEmpty) {
      PostActionFeedback.error(
        context,
        AppLocalizations.of(context).exportFileMissing,
      );
      return;
    }
    await Share.shareXFiles(existing.map((p) => XFile(p)).toList());
  }

  Future<void> _reshare(ExportHistoryEntry entry) async {
    if (_isBusy || !requireManage(context, StaffModule.reports)) return;
    final l10n = AppLocalizations.of(context);
    final file = File(entry.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      PostActionFeedback.error(context, l10n.exportFileMissing);
      return;
    }
    await Share.shareXFiles([XFile(entry.filePath)]);
  }

  Future<void> _deleteHistoryEntry(ExportHistoryEntry entry) async {
    final file = File(entry.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await HiveService.removeExportHistoryEntry(entry.id);
    _loadHistory();
  }

  // ─── Wording helpers ──────────────────────────────────────────────────────

  String _moduleName(AppLocalizations l10n, ReportModuleType m) {
    switch (m) {
      case ReportModuleType.sales:
        return l10n.reportsSalesReport;
      case ReportModuleType.harvest:
        return l10n.reportsHarvestManagement;
      case ReportModuleType.expense:
        return l10n.reportsExpenseReport;
      case ReportModuleType.loan:
        return l10n.reportsLoanReport;
      case ReportModuleType.memberContribution:
        return l10n.reportsMemberContributionReport;
      case ReportModuleType.coopStock:
        return l10n.reportsCoopStockReport;
    }
  }

  String _moduleDescription(AppLocalizations l10n, ReportModuleType m) {
    switch (m) {
      case ReportModuleType.sales:
        return l10n.rptExportDescSales;
      case ReportModuleType.harvest:
        return l10n.rptExportDescHarvest;
      case ReportModuleType.expense:
        return l10n.rptExportDescExpense;
      case ReportModuleType.loan:
        return l10n.rptExportDescLoan;
      case ReportModuleType.memberContribution:
        return l10n.rptExportDescPatronage;
      case ReportModuleType.coopStock:
        return l10n.rptExportDescCoopStock;
    }
  }

  String _moduleScope(AppLocalizations l10n, ReportModuleType m) => m.usesYear
      ? l10n.rptExportScopeYear
      : m.isSnapshot
      ? l10n.rptExportScopeSnapshot
      : l10n.rptExportScopePeriod;

  /// What the selection covers, in one line, for the summary.
  String _coverageText(AppLocalizations l10n) {
    final parts = <String>[];
    if (_selectedModules.any((m) => m.usesReportPeriod)) {
      parts.add(
        '${reportPeriodLabel(l10n, _period)} (${reportPeriodRangeText(l10n, _period)})',
      );
    }
    if (_needsYearSelector) parts.add('$_contributionYear');
    if (_selectedModules.any((m) => m.isSnapshot)) {
      parts.add(l10n.rptExportScopeSnapshot);
    }
    return parts.join(' · ');
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    // Generating, downloading and sharing need Reports Manage (the Manager
    // always has it). Rebuilding here means the buttons enable or disable the
    // moment the Manager changes an Officer's access.
    return StaffAccessBuilder(
      builder: (context, access) {
        final canManage = access.canManage(StaffModule.reports);
        return _buildScaffold(l10n, cs, sagana, canManage);
      },
    );
  }

  Widget _buildScaffold(
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
    bool canManage,
  ) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.reportsExportCenter,
            onBack: () => context.pop(),
          ),
          const ViewOnlyStrip(module: StaffModule.reports),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingSafeH,
                    AppConstants.spacingGutter,
                    AppConstants.spacingSafeH,
                    AppConstants.spacingSectionV,
                  ),
                  children: [
                    if (_lastExportPaths.isNotEmpty) ...[
                      _buildReadyCard(l10n, cs, canManage),
                      const SizedBox(height: AppConstants.spacingGutter),
                    ],
                    _buildPresets(l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingGutter),
                    _buildReportsCard(l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingGutter),
                    _buildPeriodCard(l10n, cs),
                    const SizedBox(height: AppConstants.spacingGutter),
                    _buildFormatCard(l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildHistory(l10n, cs, sagana, canManage),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomBar(l10n, cs, sagana, canManage),
        ],
      ),
    );
  }

  Widget _stepHeader(
    int step,
    String title,
    ColorScheme cs, {
    Widget? trailing,
  }) {
    // Every step header is the same height whether or not it has a button, so
    // the gap below "1", "2" and "3" is identical.
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppConstants.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$step',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _card(ColorScheme cs, SaganaColors sagana, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }

  Widget _buildReadyCard(
    AppLocalizations l10n,
    ColorScheme cs,
    bool canManage,
  ) {
    final enabled = canManage && !_isBusy;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.successGreen.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppConstants.successGreen,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.rptExportReady,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      l10n.exportGenerated(_lastExportPaths.length),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          // Two separate actions: Download saves straight to the Downloads
          // folder; Share opens the Android share sheet and saves nothing.
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled
                      ? () => _download(_lastExportPaths)
                      : null,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    _isDownloading
                        ? l10n.exportDownloading
                        : l10n.exportDownloadButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? _shareLastExport : null,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(
                    l10n.exportShareButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.primaryGreen,
                    side: BorderSide(
                      color: enabled
                          ? AppConstants.primaryGreen
                          : cs.outline.withValues(alpha: 0.3),
                    ),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresets(
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.rptExportQuickSelect,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Row(
          children: [
            Expanded(child: _presetCard(CompliancePreset.cda, cs, sagana)),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(child: _presetCard(CompliancePreset.da, cs, sagana)),
          ],
        ),
      ],
    );
  }

  Widget _presetCard(
    CompliancePreset preset,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final active = setEquals(_selectedModules, preset.modules);
    return InkWell(
      onTap: () => _applyPreset(preset),
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        constraints: const BoxConstraints(minHeight: 84),
        decoration: BoxDecoration(
          color: active
              ? AppConstants.primaryGreen.withValues(alpha: 0.08)
              : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: active
                ? AppConstants.primaryGreen
                : cs.outline.withValues(alpha: 0.10),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    preset.label,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (active)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppConstants.primaryGreen,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              preset.description,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsCard(
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final allSelected =
        _selectedModules.length == ReportModuleType.values.length;
    return _card(
      cs,
      sagana,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(
            1,
            l10n.exportSelectReports,
            cs,
            trailing: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() {
                if (allSelected) {
                  _selectedModules.clear();
                } else {
                  _selectedModules.addAll(ReportModuleType.values);
                }
              }),
              child: Text(
                allSelected ? l10n.rptExportClear : l10n.rptExportSelectAll,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ...ReportModuleType.values.map(
            (m) => _moduleRow(m, l10n, cs, sagana),
          ),
        ],
      ),
    );
  }

  Widget _moduleRow(
    ReportModuleType module,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final selected = _selectedModules.contains(module);
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingSm),
      child: InkWell(
        onTap: () => _toggleModule(module),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            color: selected
                ? AppConstants.primaryGreen.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected
                  ? AppConstants.primaryGreen
                  : cs.outline.withValues(alpha: 0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(
                  module.icon,
                  color: AppConstants.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _moduleName(l10n, module),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      _moduleDescription(l10n, module),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _moduleScope(l10n, module),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppConstants.primaryGreen
                    : cs.outline.withValues(alpha: 0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodCard(AppLocalizations l10n, ColorScheme cs) {
    final sagana = context.saganaColors;
    final hasSnapshot = _selectedModules.any((m) => m.isSnapshot);
    return _card(
      cs,
      sagana,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(2, l10n.exportPeriod, cs),
          const SizedBox(height: AppConstants.spacingMd),
          if (_periodApplies)
            ReportPeriodFilter(
              period: _period,
              onSelected: (p) => setState(() => _period = p),
            )
          else
            ReportInfoNote(text: l10n.rptExportNoPeriodNeeded),
          if (_needsYearSelector) ...[
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              l10n.exportYearForContributionReport,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Align(
              alignment: Alignment.centerLeft,
              child: YearFilterSelector(
                selectedYear: _contributionYear,
                onYearSelected: (y) => setState(() => _contributionYear = y),
                years: _availableContributionYears,
                selectedColor: AppConstants.buyerBlue,
              ),
            ),
          ],
          if (hasSnapshot && _periodApplies) ...[
            const SizedBox(height: AppConstants.spacingMd),
            ReportInfoNote(text: l10n.rptExportSnapshotNote),
          ],
        ],
      ),
    );
  }

  Widget _buildFormatCard(
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return _card(
      cs,
      sagana,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(3, l10n.exportFormatLabel, cs),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: _formatTile(
                  'pdf',
                  'PDF',
                  l10n.rptExportFormatPdfDesc,
                  Icons.picture_as_pdf_rounded,
                  cs,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: _formatTile(
                  'csv',
                  'CSV',
                  l10n.rptExportFormatCsvDesc,
                  Icons.table_chart_rounded,
                  cs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formatTile(
    String key,
    String label,
    String description,
    IconData icon,
    ColorScheme cs,
  ) {
    final active = _format == key;
    return InkWell(
      onTap: () => setState(() => _format = key),
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        constraints: const BoxConstraints(minHeight: 92),
        decoration: BoxDecoration(
          color: active
              ? AppConstants.primaryGreen.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: active
                ? AppConstants.primaryGreen
                : cs.outline.withValues(alpha: 0.15),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active
                      ? AppConstants.primaryGreen
                      : cs.onSurfaceVariant,
                ),
                const Spacer(),
                if (active)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppConstants.primaryGreen,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Always visible: says exactly what Generate & Download will produce, and
  /// holds the button. Disabled until at least one report is chosen, and for an
  /// Officer who only has View Only access to Reports.
  Widget _buildBottomBar(
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
    bool canManage,
  ) {
    final empty = _selectedModules.isEmpty;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          empty
              ? l10n.exportSummaryEmpty
              : '${l10n.rptExportSelectedCount(_selectedModules.length)} · ${_format.toUpperCase()}',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: cs.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (!empty)
          Text(
            _coverageText(l10n),
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    Widget button(bool expand) => PrimaryButton(
      label: _isDownloading
          ? l10n.exportDownloading
          : _isGenerating
          ? l10n.rptExportGenerating
          : l10n.exportGenerateDownloadButton,
      icon: Icons.file_download_rounded,
      expand: expand,
      height: 48,
      isLoading: _isBusy,
      onPressed: empty || _isBusy || !canManage ? null : _generate,
    );

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                AppConstants.spacingMd,
                AppConstants.spacingSafeH,
                AppConstants.spacingMd,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // "Generate & Download" is a long label, so on a narrow
                  // phone the button gets its own full-width row.
                  if (constraints.maxWidth < 440) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        const SizedBox(height: AppConstants.spacingSm),
                        button(true),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: AppConstants.spacingMd),
                      button(false),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
    bool canManage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.exportRecentExports,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_history.isEmpty)
          ReportEmptyState(message: l10n.exportNoHistoryYet)
        else
          ..._history.map((e) => _buildHistoryRow(e, l10n, cs, sagana, canManage)),
      ],
    );
  }

  Widget _buildHistoryRow(
    ExportHistoryEntry entry,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
    bool canManage,
  ) {
    final isPdf = entry.format == 'pdf';
    final enabled = canManage && !_isBusy;
    final actionStyle = TextButton.styleFrom(
      foregroundColor: AppConstants.primaryGreen,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        AppConstants.spacingSm,
        AppConstants.spacingSm,
      ),
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
              Icon(
                isPdf
                    ? Icons.picture_as_pdf_rounded
                    : Icons.table_chart_rounded,
                color: AppConstants.primaryGreen,
                size: 22,
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.moduleLabels.join(', '),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${entry.format.toUpperCase()} • ${entry.periodLabel} • '
                      '${DateFormat('MMM d, h:mm a').format(entry.generatedAt)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              TextButton.icon(
                onPressed: enabled ? () => _download([entry.filePath]) : null,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text(l10n.exportDownloadButton),
                style: actionStyle,
              ),
              TextButton.icon(
                onPressed: enabled ? () => _reshare(entry) : null,
                icon: const Icon(Icons.ios_share_rounded, size: 16),
                label: Text(l10n.exportShareButton),
                style: actionStyle,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppConstants.errorRed,
                tooltip: l10n.exportDeleteButton,
                visualDensity: VisualDensity.compact,
                onPressed: _isBusy ? null : () => _deleteHistoryEntry(entry),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
