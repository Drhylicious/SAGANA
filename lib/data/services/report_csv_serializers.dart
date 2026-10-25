import 'package:intl/intl.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/admin_loan_model.dart';
import '../models/admin_reports_model.dart';
import '../models/export_model.dart';

/// Pure CSV serialization for each report type — no fetching, no file
/// I/O, no dependencies beyond the report models themselves. Kept
/// separate from CsvExportService so the actual formatting logic is
/// independently reviewable/testable from the file-writing/history-
/// tracking side effects.
///
/// No `csv` package dependency — this is deliberately just comma-joining
/// with quote-escaping, per the "no additional dependencies" scope call.

String _escape(Object? value) {
  final str = value?.toString() ?? '';
  if (str.contains(',') || str.contains('"') || str.contains('\n')) {
    return '"${str.replaceAll('"', '""')}"';
  }
  return str;
}

String _row(List<Object?> values) => values.map(_escape).join(',');

final _dateFmt = DateFormat('yyyy-MM-dd');

/// A short block placed above the table of every exported file (except the
/// Member Patronage Report, whose export is left as it was): the report name,
/// what it covers, when it was generated, and its headline totals. Without it a
/// shared file does not say which period it describes.
String csvExportHeader({
  required String reportName,
  required String scopeText,
  required DateTime generatedAt,
  List<(String, String)> summary = const [],
}) {
  final buffer = StringBuffer();
  buffer.writeln(_row(['Report', reportName]));
  buffer.writeln(_row(['Covers', scopeText]));
  buffer.writeln(
    _row(['Generated', DateFormat('yyyy-MM-dd HH:mm').format(generatedAt)]),
  );
  for (final (label, value) in summary) {
    buffer.writeln(_row([label, value]));
  }
  buffer.writeln();
  return buffer.toString();
}

String serializeSalesReportCsv(SalesReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Selling Channel',
      'Market Type',
      'Farmer Name',
      'Crop Type',
      'Crop Name',
      'Quantity (kg)',
      'Amount (PHP)',
      'Sale Date',
      'Reference No',
    ]),
  );
  for (final t in data.transactions) {
    buffer.writeln(
      _row([
        sellingChannelLabel(t.sellingType),
        t.marketType ?? '',
        t.farmerName,
        t.cropType,
        t.cropName,
        exportQuantity(t.quantityKg, t.unit),
        t.amount.toStringAsFixed(2),
        _dateFmt.format(t.saleDate),
        t.referenceNo ?? '',
      ]),
    );
  }
  return buffer.toString();
}

String _serializeInventoryBatchesCsv(InventoryReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Farmer Name',
      'Crop',
      'Batch Number',
      'Harvested (kg)',
      'Available (kg)',
      'Committed (kg)',
      'Sold (kg)',
      'Status',
    ]),
  );
  for (final b in data.batches) {
    buffer.writeln(
      _row([
        b.farmerName,
        b.cropName,
        formatBatchNumber(b.batchNumber),
        exportQuantity(b.quantityKg, b.unit),
        exportQuantity(b.availableKg, b.unit),
        exportQuantity(b.reservedKg, b.unit),
        exportQuantity(b.soldKg, b.unit),
        batchStatusExportLabel(b.status),
      ]),
    );
  }
  return buffer.toString();
}

/// Harvest Report's export — two sections in one file, matching the
/// screen's own two tabs (Activity & Trends / Batches & Stock) over their
/// two deliberately-separate data sources. Folds in what used to be a
/// standalone "Inventory Report" export module — that module duplicated
/// this exact inventory_batches data with no on-screen report of its own,
/// so it's no longer offered as a separate Export Center selection.
String serializeHarvestReportCsv(
  HarvestReportData data,
  InventoryReportData batches,
) {
  final buffer = StringBuffer();
  buffer.writeln(_row(['Harvest Activity']));
  buffer.writeln(
    _row(['Date', 'Farmer Name', 'Crop', 'Quantity (kg)', 'Batch Number']),
  );
  for (final h in data.harvests) {
    buffer.writeln(
      _row([
        _dateFmt.format(h.harvestDate),
        h.farmerName,
        h.cropName,
        exportQuantity(h.quantityKg, h.unit),
        formatBatchNumber(h.batchNumber),
      ]),
    );
  }
  buffer.writeln();
  buffer.writeln(_row(['Batches & Stock']));
  buffer.write(_serializeInventoryBatchesCsv(batches));
  return buffer.toString();
}

String serializeExpenseReportCsv(ExpenseReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Date',
      'Farmer Name',
      'Category',
      'Description',
      'Amount (PHP)',
      'Subsidized',
    ]),
  );
  for (final e in data.expenses) {
    buffer.writeln(
      _row([
        _dateFmt.format(e.expenseDate),
        e.farmerName,
        e.category,
        e.description,
        e.isSubsidy ? '0.00' : e.amount.toStringAsFixed(2),
        e.isSubsidy ? 'Yes' : 'No',
      ]),
    );
  }
  return buffer.toString();
}

String serializeLoanReportCsv(List<AdminLoanSummary> loans) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Reference No',
      'Farmer Name',
      'Issued Date',
      'Items',
      'Total Value (PHP)',
      'Amount Paid (PHP)',
      'Remaining Balance (PHP)',
      'Status',
    ]),
  );
  for (final l in loans) {
    buffer.writeln(
      _row([
        l.referenceNo,
        l.farmerName,
        _dateFmt.format(l.issuedDate),
        l.itemNames.join('; '),
        l.totalValue.toStringAsFixed(2),
        l.amountPaid.toStringAsFixed(2),
        l.remainingBalance.toStringAsFixed(2),
        loanStatusExportLabel(l.status),
      ]),
    );
  }
  return buffer.toString();
}

String serializeMemberContributionReportCsv(MemberContributionReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Farmer Name',
      'Palay Qty (kg)',
      'Palay Amount (PHP)',
      'Peanut Qty (kg)',
      'Peanut Amount (PHP)',
      'Other Crops Qty (kg)',
      'Other Crops Amount (PHP)',
      'Total Amount (PHP)',
      'Share (%)',
    ]),
  );
  for (final r in data.rows) {
    buffer.writeln(
      _row([
        r.farmerName,
        r.palayQtyKg.toStringAsFixed(2),
        r.palayAmount.toStringAsFixed(2),
        r.peanutQtyKg.toStringAsFixed(2),
        r.peanutAmount.toStringAsFixed(2),
        r.otherCropsQtyKg.toStringAsFixed(2),
        r.otherCropsAmount.toStringAsFixed(2),
        r.totalAmount.toStringAsFixed(2),
        r.sharePercent.toStringAsFixed(2),
      ]),
    );
  }
  return buffer.toString();
}

String serializeCoopStockReportCsv(CoopStockReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row(['Item Name', 'Category', 'On Hand', 'Unit', 'Low Stock']),
  );
  for (final item in data.items) {
    buffer.writeln(
      _row([
        item.itemName,
        item.category,
        item.quantityOnHand.toStringAsFixed(2),
        item.unit,
        item.isLowStock ? 'Yes' : 'No',
      ]),
    );
  }
  return buffer.toString();
}
