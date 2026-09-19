import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../data/services/pdf_export_service.dart';
import '../../../data/services/hive_service.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/shared_widgets.dart';

/// Export Center — Admin.
/// Pushed above the shell. Route: /admin/export
///
/// Both PDF and CSV are offered side by side (Phase 15) — the admin picks
/// per export via the Format selector. Purely an orchestration and
/// serialization layer either way — every fetch here goes through the
/// exact same repository methods each report screen already uses;
/// nothing new is computed here.
class ExportCenterScreen extends StatefulWidget {
  final ExportCenterArgs? args;

  const ExportCenterScreen({super.key, this.args});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  final _csvService = CsvExportService();
  final _pdfService = PdfExportService();
  final _reportsRepo = AdminReportsRepository();

  final Set<ReportModuleType> _selectedModules = {};
  ReportPeriod _period = ReportPeriod.thisMonth;
  late int _contributionYear;
  String _format = 'pdf';
  bool _isGenerating = false;
  List<ExportHistoryEntry> _history = [];
  List<int> _availableContributionYears = [DateTime.now().year];

  bool get _needsYearSelector =>
      _selectedModules.contains(ReportModuleType.memberContribution);

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
      if (_selectedModules.contains(module)) {
        _selectedModules.remove(module);
      } else {
        _selectedModules.add(module);
      }
    });
  }

  void _applyPreset(CompliancePreset preset) {
    setState(() {
      _selectedModules.clear();
      _selectedModules.addAll(preset.modules);
    });
  }

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedModules.isEmpty) {
      _showSnack(l10n.exportSelectAtLeastOne, isError: true);
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final ReportExportService service = _format == 'pdf' ? _pdfService : _csvService;
      final paths = await service.generateExports(
        modules: _selectedModules,
        period: _period,
        contributionYear: _contributionYear,
      );
      _loadHistory();
      if (!mounted) return;
      _showSnack(l10n.exportGenerated(paths.length));

      if (paths.isNotEmpty) {
        await Share.shareXFiles(paths.map((p) => XFile(p)).toList());
      }
    } catch (e, st) {
      debugPrint('[ExportCenter] generateExports failed: $e\n$st');
      if (!mounted) return;
      _showSnack(l10n.exportGenerateError, isError: true);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _reshare(ExportHistoryEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final file = File(entry.filePath);
    if (!await file.exists()) {
      _showSnack(l10n.exportFileMissing, isError: true);
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs, sagana),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                AppConstants.spacingGutter,
                AppConstants.spacingSafeH,
                32,
              ),
              children: [
                _buildPresets(context, l10n, cs, sagana),
                const SizedBox(height: AppConstants.spacingSectionV),
                Text(l10n.exportSelectReports, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                const SizedBox(height: AppConstants.spacingSm),
                _buildModuleGrid(context, cs, sagana),
                const SizedBox(height: AppConstants.spacingSectionV),
                Text(l10n.exportFormatLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                const SizedBox(height: AppConstants.spacingSm),
                _buildFormatChips(cs),
                const SizedBox(height: AppConstants.spacingSectionV),
                Text(l10n.exportPeriod, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                const SizedBox(height: AppConstants.spacingSm),
                _buildPeriodChips(l10n, cs),
                if (_needsYearSelector) ...[
                  const SizedBox(height: AppConstants.spacingMd),
                  Text(
                    l10n.exportYearForContributionReport,
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppConstants.spacingSm),
                  YearFilterSelector(
                    selectedYear: _contributionYear,
                    onYearSelected: (y) => setState(() => _contributionYear = y),
                    years: _availableContributionYears,
                    selectedColor: AppConstants.buyerBlue,
                  ),
                ],
                const SizedBox(height: AppConstants.spacingSectionV),
                ReportEmptyState(
                  message: _selectedModules.isEmpty
                      ? l10n.exportSummaryEmpty
                      : l10n.exportSummary(_selectedModules.length),
                ),
                const SizedBox(height: AppConstants.spacingGutter),
                PrimaryButton(
                  label: l10n.exportGenerateButton,
                  isLoading: _isGenerating,
                  onPressed: _generate,
                ),
                const SizedBox(height: AppConstants.spacingSectionV),
                Text(l10n.exportRecentExports, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                const SizedBox(height: AppConstants.spacingSm),
                if (_history.isEmpty)
                  ReportEmptyState(message: l10n.exportNoHistoryYet)
                else
                  ..._history.map((e) => _buildHistoryRow(e, l10n, cs, sagana)),
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
                  l10n.reportsExportCenter,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresets(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Row(
      children: [
        Expanded(child: _presetCard(CompliancePreset.cda, cs, sagana)),
        const SizedBox(width: AppConstants.spacingMd),
        Expanded(child: _presetCard(CompliancePreset.da, cs, sagana)),
      ],
    );
  }

  Widget _presetCard(CompliancePreset preset, ColorScheme cs, SaganaColors sagana) {
    return GestureDetector(
      onTap: () => _applyPreset(preset),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preset.label, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(preset.description, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleGrid(BuildContext context, ColorScheme cs, SaganaColors sagana) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppConstants.spacingMd,
      crossAxisSpacing: AppConstants.spacingMd,
      childAspectRatio: 1.5,
      children: ReportModuleType.values.map((m) => _moduleCard(m, cs, sagana)).toList(),
    );
  }

  Widget _moduleCard(ReportModuleType module, ColorScheme cs, SaganaColors sagana) {
    final selected = _selectedModules.contains(module);
    return GestureDetector(
      onTap: () => _toggleModule(module),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryGreen.withValues(alpha: 0.08) : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: selected ? AppConstants.primaryGreen : cs.outline.withValues(alpha: 0.10),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(module.icon, color: AppConstants.primaryGreen, size: 20),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: AppConstants.primaryGreen, size: 18),
              ],
            ),
            Text(
              module.label,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatChips(ColorScheme cs) {
    final options = <String, (String, IconData)>{
      'pdf': ('PDF', Icons.picture_as_pdf_rounded),
      'csv': ('CSV', Icons.table_chart_rounded),
    };
    return Row(
      children: options.entries.map((entry) {
        final active = _format == entry.key;
        final (label, icon) = entry.value;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(icon, size: 15, color: active ? Colors.white : cs.onSurfaceVariant),
            label: Text(label, style: GoogleFonts.inter(fontSize: 12)),
            selected: active,
            onSelected: (_) => setState(() => _format = entry.key),
            selectedColor: AppConstants.primaryGreen,
            labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPeriodChips(AppLocalizations l10n, ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: reportPeriodChipOrder.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(reportPeriodLabel(l10n, p), style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => setState(() => _period = p),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryRow(
    ExportHistoryEntry entry,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(
            entry.format == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.table_chart_rounded,
            color: AppConstants.primaryGreen,
            size: 20,
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.moduleLabels.join(', '),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.periodLabel} • ${DateFormat('MMM d, h:mm a').format(entry.generatedAt)}',
                  style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            color: AppConstants.primaryGreen,
            onPressed: () => _reshare(entry),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: AppConstants.errorRed,
            onPressed: () => _deleteHistoryEntry(entry),
          ),
        ],
      ),
    );
  }
}