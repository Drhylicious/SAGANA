import 'package:flutter/material.dart';
import 'admin_reports_model.dart';

/// The six report types Export Center can generate. Deliberately mirrors
/// the six existing report screens exactly — Export Center doesn't fetch
/// or compute anything new, it only orchestrates and serializes what
/// those screens' repositories already produce.
enum ReportModuleType {
  sales,
  inventory,
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
      case ReportModuleType.inventory:
        return 'Inventory Report';
      case ReportModuleType.harvest:
        return 'Harvest Report';
      case ReportModuleType.expense:
        return 'Expense Report';
      case ReportModuleType.loan:
        return 'Loan Report';
      case ReportModuleType.memberContribution:
        return 'Member Contribution Report';
      case ReportModuleType.coopStock:
        return 'Cooperative Stock Report';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportModuleType.sales:
        return Icons.point_of_sale_rounded;
      case ReportModuleType.inventory:
        return Icons.inventory_2_rounded;
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

  /// Inventory Report is a point-in-time snapshot, not scoped to a date
  /// range — same reasoning as its own screen (no ReportPeriod filter).
  bool get usesReportPeriod => this != ReportModuleType.inventory && this != ReportModuleType.memberContribution;

  /// Member Contribution Report is year-scoped, not ReportPeriod-scoped.
  bool get usesYear => this == ReportModuleType.memberContribution;
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
        return 'Harvest and Inventory reports';
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
        return {ReportModuleType.harvest, ReportModuleType.inventory};
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

  const ExportHistoryEntry({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.moduleLabels,
    required this.periodLabel,
    required this.generatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'moduleLabels': moduleLabels,
        'periodLabel': periodLabel,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory ExportHistoryEntry.fromMap(Map<dynamic, dynamic> map) {
    return ExportHistoryEntry(
      id: map['id'] as String,
      fileName: map['fileName'] as String,
      filePath: map['filePath'] as String,
      moduleLabels: List<String>.from(map['moduleLabels'] as List? ?? []),
      periodLabel: map['periodLabel'] as String? ?? '',
      generatedAt: DateTime.parse(map['generatedAt'] as String),
    );
  }
}