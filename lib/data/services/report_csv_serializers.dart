import '../../core/utils/item_type_utils.dart';
import 'package:intl/intl.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/admin_analytics_model.dart';
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

/// A text that starts with = + @ (or a minus that is not a number) would be read as a
/// formula when the file is opened in a spreadsheet. A leading apostrophe keeps it text.
String _neutralize(Object? value, String str) {
  if (value is! String || str.isEmpty) return str;
  final c = str[0];
  final isMinusText = c == '-' && double.tryParse(str) == null;
  return (c == '=' || c == '+' || c == '@' || isMinusText) ? "'$str" : str;
}

String _escape(Object? value) {
  final str = _neutralize(value, value?.toString() ?? '');
  if (str.contains(',') || str.contains('"') || str.contains('\n')) {
    return '"${str.replaceAll('"', '""')}"';
  }
  return str;
}

String _row(List<Object?> values) => values.map(_escape).join(',');

final _dateFmt = DateFormat('yyyy-MM-dd');

/// A short block placed above the table of every exported file (except the
/// Member Contribution Report, whose export is left as it was): the report name,
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

/// The Sales Report file. With [products] it has the two sections of the screen, each under its
/// own title: Marketplace Sales (every selling channel) and Cooperative Product Sales.
String serializeSalesReportCsv(SalesReportData data, [ProductSalesReportData? products]) {
  final buffer = StringBuffer();
  if (products != null) buffer.writeln(_row(['Marketplace Sales']));
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
      'Buyer',
      'Order Status',
    ]),
  );
  for (final t in data.transactions) {
    buffer.writeln(
      _row([
        sellingChannelLabel(t.sellingType),
        t.marketType ?? '',
        t.farmerName,
        t.cropType,
        t.fromProgram ? '${t.cropName} (Cooperative Program)' : t.cropName,
        exportQuantity(t.quantityKg, t.unit),
        t.amount.toStringAsFixed(2),
        _dateFmt.format(t.saleDate),
        t.referenceNo ?? '',
        t.buyerName ?? '',
        t.orderStatus ?? '',
      ]),
    );
  }
  if (products != null) {
    buffer.writeln();
    buffer.writeln(_row(['Cooperative Product Sales']));
    buffer.writeln(
      _row(['Member Name', 'Product', 'Program', 'Quantity', 'Amount (PHP)', 'Completed Date', 'Order Number']),
    );
    for (final r in products.rows) {
      buffer.writeln(
        _row([
          r.farmerName,
          r.itemName,
          r.programName ?? '',
          exportQuantity(r.quantity, r.unit),
          r.amount.toStringAsFixed(2),
          _dateFmt.format(r.saleDate),
          r.orderNumber,
        ]),
      );
    }
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
      'Rotten/Lost (kg)',
      'Status',
      'Condition',
      'Shelf Life',
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
        exportQuantity(b.spoiledKg, b.unit),
        batchStatusExportLabel(b.status),
        b.conditionLabel,
        b.shelfLifeExportLabel,
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
    _row([
      'Date',
      'Farmer Name',
      'Crop',
      'Category',
      'Quantity (kg)',
      'Batch Number',
      'Rotten/Lost (kg)',
    ]),
  );
  for (final h in data.harvests) {
    buffer.writeln(
      _row([
        _dateFmt.format(h.harvestDate),
        h.farmerName,
        h.cropName,
        h.cropCategory,
        exportQuantity(h.quantityKg, h.unit),
        formatBatchNumber(h.batchNumber),
        exportQuantity(h.spoiledKg, h.unit),
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
      'Expense Name',
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
        e.name,
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
      'Monthly Payment (PHP)',
      'Next Payment Date',
      'From Program',
      'Notes',
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
        l.monthlyPayment.toStringAsFixed(2),
        l.nextPaymentDate == null ? '' : _dateFmt.format(l.nextPaymentDate!),
        l.sourceProgramName ?? '',
        l.notes ?? '',
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
      // Total Capital Share = Monthly Contribution + Cooperative Purchase + Offer
      // to Cooperative. The balance, where it started the year, and what was added.
      'Total Capital Share (PHP)',
      'Capital Share at Start of Year (PHP)',
      'Added in Year (PHP)',
      'Monthly Contribution Added (PHP)',
      'Cooperative Purchase Added (PHP)',
      'Offer to Cooperative Added (PHP)',
      // What the Monthly Contribution is made of.
      'Monthly Payments Received (PHP)',
      'Paid Toward Months (PHP)',
      'Earlier Payments Not Assigned to a Month (PHP)',
      'Starting Capital Dated in the Year (PHP)',
      'Corrections and Other Entries (PHP)',
      'Full Shares',
      'Remaining for Next Share (PHP)',
      // The monthly obligation: shown, never added to the Capital Share.
      'Monthly Obligation Due (PHP)',
      'Monthly Obligation Unpaid (PHP)',
      'Months Paid',
      'Months Partial',
      'Months Unpaid',
      'Months Overdue',
      'Months Waived',
      // The completed transactions the two percentage credits come from.
      'Cooperative Purchases Made (PHP)',
      'Purchases Credited From (PHP)',
      'Cooperative Purchase Rate Used (%)',
      'Completed Offers - Sale Value (PHP)',
      'Offers Credited From (PHP)',
      'Offer to Cooperative Rate Used (%)',
    ]),
  );
  String rate(double credited, double base) =>
      base > 0 ? (credited / base * 100).toStringAsFixed(2) : '';
  for (final r in data.rows) {
    buffer.writeln(
      _row([
        r.farmerName,
        r.capitalBalance.toStringAsFixed(2),
        r.capitalAtYearStart.toStringAsFixed(2),
        r.capitalAddedInYear.toStringAsFixed(2),
        r.memberPaidInYear.toStringAsFixed(2),
        r.purchaseCredited.toStringAsFixed(2),
        r.offersCredited.toStringAsFixed(2),
        r.monthlyContributions.toStringAsFixed(2),
        (r.monthlyContributions - r.monthlyUnassigned).toStringAsFixed(2),
        r.monthlyUnassigned.toStringAsFixed(2),
        r.startingCapital.toStringAsFixed(2),
        r.otherCapitalAdded.toStringAsFixed(2),
        r.capitalShares,
        r.remainingForNextShare.toStringAsFixed(2),
        r.monthlyDue.toStringAsFixed(2),
        r.monthlyBalance.toStringAsFixed(2),
        r.monthsPaid,
        r.monthsPartial,
        r.monthsUnpaid,
        r.monthsOverdue,
        r.monthsWaived,
        r.programPurchasesAmount.toStringAsFixed(2),
        r.purchaseShareBase.toStringAsFixed(2),
        rate(r.purchaseShareCredited, r.purchaseShareBase),
        r.totalAmount.toStringAsFixed(2),
        r.offerShareBase.toStringAsFixed(2),
        rate(r.offerShareCredited, r.offerShareBase),
      ]),
    );
  }
  return buffer.toString();
}

String serializeCoopStockReportCsv(CoopStockReportData data) {
  final buffer = StringBuffer();
  buffer.writeln(
    _row([
      'Item Name',
      'Category',
      'Item Type',
      'On Hand',
      'Unit',
      'Reorder Level',
      'Unit Cost (PHP)',
      'Last Restocked',
      'Low Stock',
    ]),
  );
  for (final item in data.items) {
    buffer.writeln(
      _row([
        item.itemName,
        item.category,
        itemTypeExportLabel(item.itemType),
        item.quantityOnHand.toStringAsFixed(2),
        item.unit,
        item.reorderLevel.toStringAsFixed(2),
        item.unitCost?.toStringAsFixed(2) ?? '',
        item.lastRestockedAt == null
            ? ''
            : _dateFmt.format(item.lastRestockedAt!),
        item.isLowStock ? 'Yes' : 'No',
      ]),
    );
  }
  return buffer.toString();
}

/// Analytics Dashboard export: its four sections one after another, each with
/// its own heading and column titles.
String serializeAnalyticsCsv(AnalyticsExportData data) {
  final b = StringBuffer();
  final p = data.participation;
  b.writeln(_row(['Member Participation']));
  b.writeln(_row(['Group', 'Members']));
  b.writeln(_row(['Harvested', p.activeHarvestedCount]));
  b.writeln(_row(['Listed Only', p.activeListedCount]));
  b.writeln(_row(['No Activity', p.inactiveCount]));
  b.writeln(_row(['Active Members', p.totalMembers]));
  b.writeln(
    _row([
      'Participation Rate (%)',
      data.participationRatePercent.toStringAsFixed(1),
    ]),
  );
  b.writeln();
  b.writeln(_row(['Members With No Activity']));
  for (final f in p.inactiveFarmers) {
    b.writeln(_row([f.fullName]));
  }
  b.writeln();
  b.writeln(_row(['Top Harvested Crops']));
  b.writeln(_row(['Crop', 'Volume (kg)']));
  for (final c in data.topCrops) {
    b.writeln(_row([c.cropName, c.volumeKg.toStringAsFixed(2)]));
  }
  b.writeln();
  b.writeln(_row(['Price Snapshot']));
  b.writeln(
    _row([
      'Crop',
      'Market Type',
      'Current Price (PHP/kg)',
      'Previous Price (PHP/kg)',
      'Change (%)',
      'Last Updated',
    ]),
  );
  for (final c in data.priceCards) {
    final prev = c.previousPrice;
    final change = prev != null && prev != 0
        ? ((c.currentPrice - prev) / prev * 100).toStringAsFixed(1)
        : '';
    b.writeln(
      _row([
        c.cropName,
        data.marketTypeName(c.priceType),
        c.currentPrice.toStringAsFixed(2),
        prev?.toStringAsFixed(2) ?? '',
        change,
        c.recordedAt == null ? '' : _dateFmt.format(c.recordedAt!),
      ]),
    );
  }
  b.writeln();
  b.writeln(_row(['Planting Forecast']));
  b.writeln(
    _row([
      'Crop',
      'Category',
      'Most Recent Cycle (kg)',
      'Forecast Next Cycle (kg)',
      'Trend',
      'Cycles Recorded',
    ]),
  );
  for (final f in data.forecasts) {
    b.writeln(
      _row([
        f.cropName,
        f.category,
        f.mostRecentCycleKg.toStringAsFixed(2),
        f.hasForecast ? f.forecastNextCycleKg!.toStringAsFixed(2) : '',
        analyticsTrendLabel(f.trend),
        f.cyclesAvailable,
      ]),
    );
  }
  return b.toString();
}

/// English trend wording for exports.
String analyticsTrendLabel(String trend) {
  switch (trend) {
    case 'trending_up':
      return 'Rising';
    case 'trending_down':
      return 'Falling';
    case 'stable':
      return 'Steady';
    default:
      return 'Not enough history';
  }
}
