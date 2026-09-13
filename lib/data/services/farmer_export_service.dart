import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/admin_reports_model.dart';
import '../models/export_model.dart';
import '../repositories/contribution_repository.dart';
import '../repositories/harvest_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/loan_repository.dart';
import 'report_csv_serializers.dart';

/// Farmer-scoped equivalent of CsvExportService (Phase 7 — Farmer Download
/// Records). Mirrors its structure exactly: calls the SAME farmer-scoped
/// repository methods, reuses the SAME report_csv_serializers.dart
/// functions unchanged, writes files the same way. The one deliberate
/// difference: no export-history logging here — HiveService's export
/// history box is a single unscoped box shared across every account on
/// the device, and adding farmer entries to it would leak one farmer's
/// download history to the next account on a shared device. That's a
/// separate, explicitly-scoped fix if a "Recent Downloads" list is wanted
/// later; this phase does not touch HiveService's export history at all.
///
/// Always exports all 5 farmer-relevant modules (Sales, Harvest, Expense,
/// Loan, Member Contribution) for the given period — confirmed scope,
/// no module picker, unlike Admin's Export Center.
class FarmerExportService {
  final _contributionRepo = ContributionRepository();
  final _harvestRepo = HarvestRepository();
  final _expenseRepo = ExpenseRepository();
  final _loanRepo = LoanRepository();

  /// Generates one CSV file per module, writes each to local storage, and
  /// returns the file paths for the caller to share. Throws on failure —
  /// same reasoning as CsvExportService: silent empty-list return would
  /// look like "nothing to export" rather than "something went wrong."
  Future<List<String>> generateMyExports(ReportPeriod period) async {
    final window = period.range();
    final start = window.startDate;
    final end = window.endDate;
    // Member Contribution / Balik-Tangkilik is inherently annual — always
    // the current calendar year, independent of the selected period,
    // matching My Contribution screen's own current-year default.
    final contributionYear = DateTime.now().year;

    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${dir.path}/my_records');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }

    final modules = <ReportModuleType>[
      ReportModuleType.sales,
      ReportModuleType.harvest,
      ReportModuleType.expense,
      ReportModuleType.loan,
      ReportModuleType.memberContribution,
    ];

    final paths = <String>[];
    for (final module in modules) {
      final csv = await _serialize(module, start, end, contributionYear);
      final periodLabel =
          module == ReportModuleType.memberContribution
              ? '$contributionYear'
              : period.label;
      final fileName = _fileNameFor(module, periodLabel);
      final file = File('${exportsDir.path}/$fileName');
      await file.writeAsString(csv);
      paths.add(file.path);
    }
    return paths;
  }

  Future<String> _serialize(
    ReportModuleType module,
    DateTime? start,
    DateTime? end,
    int contributionYear,
  ) async {
    switch (module) {
      case ReportModuleType.sales:
        return serializeSalesReportCsv(
          await _contributionRepo.fetchMySalesForExport(start: start, end: end),
        );
      case ReportModuleType.harvest:
        return serializeHarvestReportCsv(
          await _harvestRepo.fetchMyHarvestForExport(start: start, end: end),
        );
      case ReportModuleType.expense:
        return serializeExpenseReportCsv(
          await _expenseRepo.fetchMyExpensesForExport(start: start, end: end),
        );
      case ReportModuleType.loan:
        final loans = await _loanRepo.fetchMyLoansForExport(
          start: start,
          end: end,
        );
        return serializeLoanReportCsv(loans);
      case ReportModuleType.memberContribution:
        return serializeMemberContributionReportCsv(
          await _contributionRepo
              .fetchMyContributionForExport(contributionYear),
        );
      case ReportModuleType.inventory:
      case ReportModuleType.coopStock:
        // Not farmer-relevant (confirmed Phase 0.3) — never included in
        // the fixed `modules` list above, so this branch is unreachable.
        throw StateError('$module is not a Farmer Download Records module.');
    }
  }

  String _fileNameFor(ReportModuleType module, String periodLabel) {
    final safeModule = module.label.replaceAll(' ', '_');
    final safePeriod = periodLabel.replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'MyRecords_${safeModule}_${safePeriod}_$timestamp.csv';
  }
}
