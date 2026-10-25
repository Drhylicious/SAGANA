import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/admin_loan_model.dart';
import '../models/admin_reports_model.dart';
import '../models/export_model.dart';
import '../repositories/admin_loan_repository.dart';
import '../repositories/admin_reports_repository.dart';
import 'hive_service.dart';
import 'report_csv_serializers.dart';

/// Shared shape for CsvExportService and PdfExportService (Phase 15) —
/// lets Export Center pick either at runtime via one variable rather than
/// branching on format everywhere it calls generateExports().
abstract class ReportExportService {
  Future<List<String>> generateExports({
    required Set<ReportModuleType> modules,
    required ReportPeriod period,
    required int contributionYear,
  });
}

/// Orchestrates CSV export generation: calls the SAME repository methods
/// each report screen already uses, serializes the typed result, writes
/// it to a local file, and records it in Hive-backed export history.
/// No new data-fetching or business logic — this is purely a
/// serialization + file-writing layer, per the agreed scope.
///
/// Depends on repositories directly (same precedent as SyncService
/// depending on AdminLoanRepository) rather than requiring the screen to
/// pre-fetch everything and hand it over — keeps the screen thin.
class CsvExportService implements ReportExportService {
  final _reportsRepo = AdminReportsRepository();
  final _loanRepo = AdminLoanRepository();

  /// Generates one CSV file per selected module, writes each to local
  /// storage, records each in export history, and returns the file paths
  /// for the caller to share. Throws on failure — the caller decides how
  /// to surface that; silently returning an empty list would look like
  /// "nothing to export" rather than "something went wrong."
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
      final csv = await _serialize(module, period, contributionYear);
      final periodLabel = module.usesYear
          ? '$contributionYear'
          : module.isSnapshot
          ? 'Current'
          : period.label;
      final fileName = _fileNameFor(module, periodLabel);
      final file = File('${exportsDir.path}/$fileName');
      await file.writeAsString(csv);

      await HiveService.addExportHistoryEntry(
        ExportHistoryEntry(
          id: 'export_${DateTime.now().millisecondsSinceEpoch}_${module.name}_csv',
          fileName: fileName,
          filePath: file.path,
          moduleLabels: [module.label],
          periodLabel: periodLabel,
          generatedAt: DateTime.now(),
          format: 'csv',
        ).toMap(),
      );

      paths.add(file.path);
    }
    return paths;
  }

  Future<String> _serialize(
    ReportModuleType module,
    ReportPeriod period,
    int contributionYear,
  ) async {
    // Every export except the Member Patronage Report starts with a short
    // block saying what it covers and its headline totals. The Member
    // Patronage export is deliberately left exactly as it was.
    String withHeader(String body, List<(String, String)> summary) =>
        csvExportHeader(
          reportName: module.label,
          scopeText: exportScopeText(module, period, contributionYear),
          generatedAt: DateTime.now(),
          summary: summary,
        ) +
        body;

    switch (module) {
      case ReportModuleType.sales:
        final data = await _reportsRepo.fetchSalesReport(period);
        return withHeader(serializeSalesReportCsv(data), [
          ('Total Revenue (PHP)', data.totalRevenue.toStringAsFixed(2)),
          ('Total Quantity (kg)', data.totalQuantityKg.toStringAsFixed(2)),
          ('Transactions', '${data.transactionCount}'),
        ]);
      case ReportModuleType.harvest:
        final results = await Future.wait([
          _reportsRepo.fetchHarvestReport(period),
          _reportsRepo.fetchInventoryReport(),
        ]);
        final harvest = results[0] as HarvestReportData;
        return withHeader(
          serializeHarvestReportCsv(harvest, results[1] as InventoryReportData),
          [
            ('Total Yield (kg)', harvest.totalYieldKg.toStringAsFixed(2)),
            ('Harvest Entries', '${harvest.harvestCount}'),
          ],
        );
      case ReportModuleType.expense:
        final data = await _reportsRepo.fetchExpenseReport(period);
        return withHeader(serializeExpenseReportCsv(data), [
          (
            'Paid by Farmers (PHP)',
            data.totalFarmerFundedAmount.toStringAsFixed(2),
          ),
          ('Subsidized Entries', '${data.subsidizedCount}'),
          ('Total Entries', '${data.totalEntryCount}'),
        ]);
      case ReportModuleType.loan:
        final loans = await _loanRepo.fetchAllLoans(
          issuedAfter: period.startDate,
          issuedBefore: period.range().endDate,
        );
        final summary = LoanPeriodSummary.fromLoans(loans);
        return withHeader(serializeLoanReportCsv(loans), [
          ('Loans Issued', '${summary.loanCount}'),
          ('Total Value Issued (PHP)', summary.totalIssued.toStringAsFixed(2)),
          ('Collected (PHP)', summary.totalCollected.toStringAsFixed(2)),
          ('Balance (PHP)', summary.totalOutstanding.toStringAsFixed(2)),
        ]);
      case ReportModuleType.memberContribution:
        return serializeMemberContributionReportCsv(
          await _reportsRepo.fetchMemberContributionReport(contributionYear),
        );
      case ReportModuleType.coopStock:
        final data = await _reportsRepo.fetchCoopStockReport();
        return withHeader(serializeCoopStockReportCsv(data), [
          ('Total Items', '${data.totalItems}'),
          ('Low Stock Items', '${data.lowStockCount}'),
        ]);
    }
  }

  String _fileNameFor(ReportModuleType module, String periodLabel) {
    final safeModule = module.label.replaceAll(' ', '_');
    final safePeriod = periodLabel.replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'SAGANA_${safeModule}_${safePeriod}_$timestamp.csv';
  }
}