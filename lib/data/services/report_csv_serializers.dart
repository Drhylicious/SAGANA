import 'package:intl/intl.dart';
import '../models/admin_loan_model.dart';
import '../models/admin_reports_model.dart';

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

String serializeSalesReportCsv(SalesReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Farmer Name',
      'Member ID',
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
        t.farmerName,
        t.memberId,
        t.cropType,
        t.cropName,
        t.quantityKg.toStringAsFixed(2),
        t.amount.toStringAsFixed(2),
        _dateFmt.format(t.saleDate),
        t.referenceNo ?? '',
      ]),
    );
  }
  return buffer.toString();
}

String serializeInventoryReportCsv(InventoryReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Farmer Name',
      'Member ID',
      'Crop',
      'Batch Number',
      'Quality Grade',
      'Available (kg)',
      'Reserved (kg)',
      'Sold (kg)',
      'Status',
    ]),
  );
  for (final b in data.batches) {
    buffer.writeln(
      _row([
        b.farmerName,
        b.memberId,
        b.cropName,
        b.batchNumber,
        b.qualityGrade,
        b.availableKg.toStringAsFixed(2),
        b.reservedKg.toStringAsFixed(2),
        b.soldKg.toStringAsFixed(2),
        b.status,
      ]),
    );
  }
  return buffer.toString();
}

String serializeHarvestReportCsv(HarvestReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Date',
      'Farmer Name',
      'Member ID',
      'Crop',
      'Quality Grade',
      'Quantity (kg)',
      'Submitted to Coop',
      'Synced',
    ]),
  );
  for (final h in data.harvests) {
    buffer.writeln(
      _row([
        _dateFmt.format(h.harvestDate),
        h.farmerName,
        h.memberId,
        h.cropName,
        h.qualityGrade,
        h.quantityKg.toStringAsFixed(2),
        h.submittedToCooperative ? 'Yes' : 'No',
        h.isSynced ? 'Yes' : 'No',
      ]),
    );
  }
  return buffer.toString();
}

String serializeExpenseReportCsv(ExpenseReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Date',
      'Farmer Name',
      'Member ID',
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
        e.memberId,
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
      'Member ID',
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
        l.memberId,
        _dateFmt.format(l.issuedDate),
        l.itemNames.join('; '),
        l.totalValue.toStringAsFixed(2),
        l.amountPaid.toStringAsFixed(2),
        l.remainingBalance.toStringAsFixed(2),
        l.status,
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
      'Member ID',
      'Palay Qty (kg)',
      'Palay Amount (PHP)',
      'Peanut Qty (kg)',
      'Peanut Amount (PHP)',
      'Total Amount (PHP)',
      'Share (%)',
    ]),
  );
  for (final r in data.rows) {
    buffer.writeln(
      _row([
        r.farmerName,
        r.memberId,
        r.palayQtyKg.toStringAsFixed(2),
        r.palayAmount.toStringAsFixed(2),
        r.peanutQtyKg.toStringAsFixed(2),
        r.peanutAmount.toStringAsFixed(2),
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
