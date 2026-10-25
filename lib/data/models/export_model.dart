import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_reports_model.dart';

/// English wording of what an exported file covers, written into the file
/// itself (the filename alone is not enough once a file is shared on). A year
/// report names its year, a snapshot report says it is "as of" today, and every
/// other report names the period and its dates.
String exportScopeText(
  ReportModuleType module,
  ReportPeriod period,
  int contributionYear, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final dayFmt = DateFormat('MMM d, yyyy');
  if (module.usesYear) return 'Year $contributionYear';
  if (module.isSnapshot) return 'Current stock as of ${dayFmt.format(today)}';
  final range = period.range();
  if (range.startDate == null || range.endDate == null) {
    return '${period.label} (all dates)';
  }
  return '${period.label} (${dayFmt.format(range.startDate!)} to '
      '${dayFmt.format(range.endDate!)})';
}

/// English labels for batch and loan status values, shared by the CSV and PDF
/// exports so a file never shows a raw database value like `low_stock`.
String batchStatusExportLabel(String status) {
  switch (status) {
    case 'available':
      return 'Available';
    case 'low_stock':
      return 'Low Stock';
    case 'reserved':
      return 'Committed';
    case 'sold_out':
      return 'Sold Out';
    case 'withdrawn':
      return 'Withdrawn';
    default:
      return status;
  }
}

String loanStatusExportLabel(String status) {
  switch (status) {
    case 'active':
      return 'Active';
    case 'overdue':
      return 'Overdue';
    case 'paid':
      return 'Paid';
    default:
      return status;
  }
}

/// The report types Export Center can generate. Deliberately mirrors the
/// six existing report screens exactly — Export Center doesn't fetch or
/// compute anything new, it only orchestrates and serializes what those
/// screens' repositories already produce. There is no standalone
/// "Inventory Report" module — that data (inventory_batches) has no
/// on-screen report of its own; it's the second tab of Harvest Report, so
/// its export lives inside [harvest]'s CSV instead of as a separate card.
enum ReportModuleType {
  sales,
  harvest,
  expense,
  loan,
  memberContribution,
  coopStock,
}

extension ReportModuleTypeExt on ReportModuleType {
  String get label {
    switch (this) {
      case ReportModuleType.sales:
        return 'Sales Report';
      case ReportModuleType.harvest:
        return 'Harvest Report';
      case ReportModuleType.expense:
        return 'Expense Report';
      case ReportModuleType.loan:
        return 'Loan Report';
      case ReportModuleType.memberContribution:
        return 'Member Patronage Report';
      case ReportModuleType.coopStock:
        return 'Cooperative Stock Report';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportModuleType.sales:
        return Icons.point_of_sale_rounded;
      case ReportModuleType.harvest:
        return Icons.agriculture_rounded;
      case ReportModuleType.expense:
        return Icons.receipt_long_rounded;
      case ReportModuleType.loan:
        return Icons.request_page_rounded;
      case ReportModuleType.memberContribution:
        return Icons.groups_rounded;
      case ReportModuleType.coopStock:
        return Icons.warehouse_rounded;
    }
  }

  /// Member Patronage Report is year-scoped and Cooperative Stock is a current
  /// snapshot, so neither is ReportPeriod-scoped.
  bool get usesReportPeriod =>
      this != ReportModuleType.memberContribution &&
      this != ReportModuleType.coopStock;

  bool get usesYear => this == ReportModuleType.memberContribution;

  /// True for a report that shows the stock as it is right now.
  bool get isSnapshot => this == ReportModuleType.coopStock;
}

enum CompliancePreset { cda, da }

extension CompliancePresetExt on CompliancePreset {
  String get label {
    switch (this) {
      case CompliancePreset.cda:
        return 'CDA Submission';
      case CompliancePreset.da:
        return 'DA Submission';
    }
  }

  String get description {
    switch (this) {
      case CompliancePreset.cda:
        return 'Sales, Loan, and Member Contribution reports';
      case CompliancePreset.da:
        return 'Harvest report (includes batches & stock)';
    }
  }

  Set<ReportModuleType> get modules {
    switch (this) {
      case CompliancePreset.cda:
        return {
          ReportModuleType.sales,
          ReportModuleType.loan,
          ReportModuleType.memberContribution,
        };
      case CompliancePreset.da:
        return {ReportModuleType.harvest};
    }
  }
}

/// Arguments for opening Export Center pre-scoped from an existing report
/// screen's export button — one of [period] or [contributionYear] applies,
/// depending on the module.
class ExportCenterArgs {
  final ReportModuleType? preselectedModule;
  final ReportPeriod? period;
  final int? contributionYear;

  const ExportCenterArgs({
    this.preselectedModule,
    this.period,
    this.contributionYear,
  });
}

/// One row in Recent Exports — persisted to Hive, device-local only.
class ExportHistoryEntry {
  final String id;
  final String fileName;
  final String filePath;
  final List<String> moduleLabels;
  final String periodLabel;
  final DateTime generatedAt;

  /// 'csv' | 'pdf' (Phase 15 — both formats are now offered side by side).
  /// Defaults to 'csv' when reading an entry created before this field
  /// existed, so old export-history rows don't break.
  final String format;

  const ExportHistoryEntry({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.moduleLabels,
    required this.periodLabel,
    required this.generatedAt,
    this.format = 'csv',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'moduleLabels': moduleLabels,
        'periodLabel': periodLabel,
        'generatedAt': generatedAt.toIso8601String(),
        'format': format,
      };

  factory ExportHistoryEntry.fromMap(Map<dynamic, dynamic> map) {
    return ExportHistoryEntry(
      id: map['id'] as String,
      fileName: map['fileName'] as String,
      filePath: map['filePath'] as String,
      moduleLabels: List<String>.from(map['moduleLabels'] as List? ?? []),
      periodLabel: map['periodLabel'] as String? ?? '',
      generatedAt: DateTime.parse(map['generatedAt'] as String),
      format: map['format'] as String? ?? 'csv',
    );
  }
}