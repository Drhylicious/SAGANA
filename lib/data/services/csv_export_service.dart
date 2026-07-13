import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/admin_reports_model.dart';
import '../models/export_model.dart';
import '../repositories/admin_loan_repository.dart';
import '../repositories/admin_reports_repository.dart';
import 'hive_service.dart';
import 'report_csv_serializers.dart';

/// Orchestrates CSV export generation: calls the SAME repository methods
/// each report screen already uses, serializes the typed result, writes
/// it to a local file, and records it in Hive-backed export history.
/// No new data-fetching or business logic — this is purely a
/// serialization + file-writing layer, per the agreed scope.
///
/// Depends on repositories directly (same precedent as SyncService
/// depending on AdminLoanRepository) rather than requiring the screen to
/// pre-fetch everything and hand it over — keeps the screen thin.
class CsvExportService {
  final _reportsRepo = AdminReportsRepository();
  final _loanRepo = AdminLoanRepository();

  /// Generates one CSV file per selected module, writes each to local
  /// storage, records each in export history, and returns the file paths
  /// for the caller to share. Throws on failure — the caller decides how
  /// to surface that; silently returning an empty list would look like
  /// "nothing to export" rather than "something went wrong."
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
      final periodLabel = module.usesYear ? '$contributionYear' : period.label;
      final fileName = _fileNameFor(module, periodLabel);
      final file = File('${exportsDir.path}/$fileName');
      await file.writeAsString(csv);

      await HiveService.addExportHistoryEntry(ExportHistoryEntry(
        id: 'export_${DateTime.now().millisecondsSinceEpoch}_${module.name}',
        fileName: fileName,
        filePath: file.path,
        moduleLabels: [module.label],
        periodLabel: periodLabel,
        generatedAt: DateTime.now(),
      ).toMap());

      paths.add(file.path);
    }
    return paths;
  }

  Future<String> _serialize(
    ReportModuleType module,
    ReportPeriod period,
    int contributionYear,
  ) async {
    switch (module) {
      case ReportModuleType.sales:
        return serializeSalesReportCsv(await _reportsRepo.fetchSalesReport(period));
      case ReportModuleType.inventory:
        return serializeInventoryReportCsv(await _reportsRepo.fetchInventoryReport());
      case ReportModuleType.harvest:
        return serializeHarvestReportCsv(await _reportsRepo.fetchHarvestReport(period));
      case ReportModuleType.expense:
        return serializeExpenseReportCsv(await _reportsRepo.fetchExpenseReport(period));
      case ReportModuleType.loan:
        final loans = await _loanRepo.fetchAllLoans(issuedAfter: period.startDate);
        return serializeLoanReportCsv(loans);
      case ReportModuleType.memberContribution:
        return serializeMemberContributionReportCsv(
          await _reportsRepo.fetchMemberContributionReport(contributionYear),
        );
    }
  }

  String _fileNameFor(ReportModuleType module, String periodLabel) {
    final safeModule = module.label.replaceAll(' ', '_');
    final safePeriod = periodLabel.replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'SAGANA_${safeModule}_${safePeriod}_$timestamp.csv';
  }
}