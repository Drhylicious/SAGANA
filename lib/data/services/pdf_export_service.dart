import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/admin_reports_model.dart';
import '../models/export_model.dart';
import '../repositories/admin_loan_repository.dart';
import '../repositories/admin_reports_repository.dart';
import 'csv_export_service.dart' show ReportExportService;
import 'hive_service.dart';
import 'report_pdf_serializers.dart';

/// PDF counterpart to CsvExportService (Phase 15). Same orchestration
/// pattern exactly — calls the SAME repository methods each report
/// screen and CsvExportService already use, builds a PDF document via
/// report_pdf_serializers.dart, writes it to the same local exports
/// directory, and records it in the same Hive-backed export history
/// (tagged format: 'pdf' so Export Center can tell the two apart).
class PdfExportService implements ReportExportService {
  final _reportsRepo = AdminReportsRepository();
  final _loanRepo = AdminLoanRepository();

  /// Generates one PDF file per selected module. Throws on failure — same
  /// reasoning as CsvExportService: a silently empty result would look
  /// like "nothing to export" rather than "something went wrong."
  @override
  Future<List<String>> generateExports({
    required Set<ReportModuleType> modules,
    required ReportPeriod period,
    required int contributionYear,
  }) async {
    if (modules.isEmpty) return [];

    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${dir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }

    final paths = <String>[];
    for (final module in modules) {
      final doc = await _buildDocument(module, period, contributionYear);
      final bytes = await doc.save();
      final periodLabel = module.usesYear ? '$contributionYear' : period.label;
      final fileName = _fileNameFor(module, periodLabel);
      final file = File('${exportsDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await HiveService.addExportHistoryEntry(
        ExportHistoryEntry(
          id: 'export_${DateTime.now().millisecondsSinceEpoch}_${module.name}_pdf',
          fileName: fileName,
          filePath: file.path,
          moduleLabels: [module.label],
          periodLabel: periodLabel,
          generatedAt: DateTime.now(),
          format: 'pdf',
        ).toMap(),
      );

      paths.add(file.path);
    }
    return paths;
  }

  Future<pw.Document> _buildDocument(
    ReportModuleType module,
    ReportPeriod period,
    int contributionYear,
  ) async {
    switch (module) {
      case ReportModuleType.sales:
        return buildSalesReportPdf(
          await _reportsRepo.fetchSalesReport(period),
        );
      case ReportModuleType.harvest:
        final results = await Future.wait([
          _reportsRepo.fetchHarvestReport(period),
          _reportsRepo.fetchInventoryReport(),
        ]);
        return buildHarvestReportPdf(
          results[0] as HarvestReportData,
          results[1] as InventoryReportData,
        );
      case ReportModuleType.expense:
        return buildExpenseReportPdf(
          await _reportsRepo.fetchExpenseReport(period),
        );
      case ReportModuleType.loan:
        final loans = await _loanRepo.fetchAllLoans(
          issuedAfter: period.startDate,
          issuedBefore: period.range().endDate,
        );
        return buildLoanReportPdf(loans);
      case ReportModuleType.memberContribution:
        return buildMemberContributionReportPdf(
          await _reportsRepo.fetchMemberContributionReport(contributionYear),
        );
      case ReportModuleType.coopStock:
        return buildCoopStockReportPdf(
          await _reportsRepo.fetchCoopStockReport(),
        );
    }
  }

  String _fileNameFor(ReportModuleType module, String periodLabel) {
    final safeModule = module.label.replaceAll(' ', '_');
    final safePeriod = periodLabel.replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'SAGANA_${safeModule}_${safePeriod}_$timestamp.pdf';
  }
}
