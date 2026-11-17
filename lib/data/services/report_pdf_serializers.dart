import '../../core/utils/item_type_utils.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/quantity_utils.dart';
import '../models/admin_analytics_model.dart';
import '../models/admin_loan_model.dart';
import '../models/admin_reports_model.dart';
import '../models/export_model.dart';
import 'report_csv_serializers.dart' show analyticsTrendLabel;

/// PDF serialization for each report type — the PDF counterpart to
/// report_csv_serializers.dart (Phase 15). Deliberately mirrors that
/// file's exact column sets and row content for every report, so a PDF
/// and CSV export of the same report/period always show the same data,
/// just in a different format. No fetching, no file I/O — pure document
/// building, kept separate from the orchestration layer for the same
/// reason report_csv_serializers.dart is separate from CsvExportService.

final _dateFmt = DateFormat('yyyy-MM-dd');

/// The pdf package's default fonts (Helvetica family, used unless a
/// custom font is registered) only cover WinAnsi/Latin-1 — an em dash
/// (—, U+2014) has no glyph and renders blank/missing. The rest of the
/// app consistently uses "—" as the placeholder for a missing value
/// (farmer name, etc. — see fetchFarmerInfoMap's fallbacks), so every
/// string reaching a PDF page is routed through this first.
/// Confirmed via a runtime smoke test during Phase 15 verification,
/// not just a theoretical concern.
String _safe(String s) => s.replaceAll('—', '-').replaceAll('–', '-');

List<String> _safeRow(List<String> row) => row.map(_safe).toList();

/// Puts what the file covers (period, year or "as of" date) in front of the
/// headline totals. Null for the Member Contribution Report, whose export keeps
/// its original subtitle.
String _withScope(String? scopeText, String text) =>
    scopeText == null ? text : '$scopeText — $text';

final _numFmt = NumberFormat('#,##0.00');

/// A number with thousands separators and two decimals, for reading on paper
/// (the CSV keeps plain numbers so a spreadsheet can add them up).
String _n(num v) => _numFmt.format(v);

pw.Document _buildDocument({
  required String title,
  required String subtitle,
  required List<pw.Widget> sections,
  // Wide tables (many columns) are laid out on a landscape page so each column
  // stays readable.
  bool landscape = false,
}) {
  final generated = DateFormat('MMM d, yyyy h:mm a').format(DateTime.now());
  final doc = pw.Document(title: _safe('SAGANA - $title'), author: 'SAGANA');
  doc.addPage(
    pw.MultiPage(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
      header: (context) => context.pageNumber == 1
          // First page: brand line, the report name and what it covers.
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SAGANA',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                    letterSpacing: 2,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  _safe(title),
                  style: const pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    _safe(subtitle),
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
            )
          // Later pages: a slim reminder of which report this is.
          : pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      _safe(title),
                      style: const pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green900,
                      ),
                    ),
                    pw.Text(
                      'SAGANA',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                pw.Divider(color: PdfColors.grey400, height: 10),
              ],
            ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated $generated',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
      build: (context) => sections,
    ),
  );
  return doc;
}

final _numericCell = RegExp(r'^-?[\d,]*\.?\d+( [A-Za-z]+)?$');

pw.Widget _table(List<String> headers, List<List<String>> rows) {
  if (rows.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 12),
      child: pw.Text(
        'No records to show.',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
      ),
    );
  }
  final safeRows = rows.map(_safeRow).toList();
  // A column whose every filled cell is a number is right-aligned, so the
  // figures line up under their heading.
  final alignments = <int, pw.Alignment>{
    for (var c = 0; c < headers.length; c++)
      c: () {
        final cells = [
          for (final r in safeRows)
            if (c < r.length && r[c].trim().isNotEmpty) r[c].trim(),
        ];
        return cells.isNotEmpty && cells.every(_numericCell.hasMatch)
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft;
      }(),
  };
  return pw.TableHelper.fromTextArray(
    headers: _safeRow(headers),
    data: safeRows,
    headerStyle: const pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 8,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
    headerAlignments: alignments,
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellAlignments: alignments,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
    oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
  );
}

Future<pw.Document> buildSalesReportPdf(
  SalesReportData data, {
  String? scopeText,
  ProductSalesReportData? products,
}) async {
  final rows = data.transactions
      .map(
        (t) => [
          sellingChannelLabel(t.sellingType),
          t.marketType ?? '',
          t.farmerName,
          t.fromProgram ? '${t.cropName} (Cooperative Program)' : t.cropName,
          exportQuantity(t.quantityKg, t.unit),
          _n(t.amount),
          _dateFmt.format(t.saleDate),
          t.referenceNo ?? '',
          t.buyerName ?? '',
          t.orderStatus ?? '',
        ],
      )
      .toList();
  final marketplaceTable = _table([
    'Selling Channel',
    'Market Type',
    'Farmer',
    'Crop',
    'Qty (kg)',
    'Amount (PHP)',
    'Date',
    'Reference',
    'Buyer',
    'Status',
  ], rows);
  if (products == null) {
    return _buildDocument(
      landscape: true,
      title: 'Sales Report',
      subtitle: _withScope(
        scopeText,
        'Total Revenue: PHP ${_n(data.totalRevenue)} — ${data.transactionCount} transactions',
      ),
      sections: [marketplaceTable],
    );
  }
  // Two sections, as on the screen: Marketplace Sales, then Cooperative Product Sales.
  final productRows = products.rows
      .map(
        (r) => [
          r.farmerName,
          r.itemName,
          r.programName ?? '',
          exportQuantity(r.quantity, r.unit),
          _n(r.amount),
          _dateFmt.format(r.saleDate),
          r.orderNumber,
        ],
      )
      .toList();
  return _buildDocument(
    landscape: true,
    title: 'Sales Report',
    subtitle: _withScope(
      scopeText,
      'Marketplace Sales: PHP ${_n(data.totalRevenue)} (${data.transactionCount} transactions) — '
      'Cooperative Product Sales: PHP ${_n(products.summary.amount)} (${products.summary.orders} orders)',
    ),
    sections: [
      _heading('Marketplace Sales'),
      marketplaceTable,
      _heading('Cooperative Product Sales'),
      _table([
        'Member',
        'Product',
        'Program',
        'Qty',
        'Amount (PHP)',
        'Completed',
        'Order #',
      ], productRows),
    ],
  );
}

Future<pw.Document> buildHarvestReportPdf(
  HarvestReportData data,
  InventoryReportData batches, {
  String? scopeText,
}) async {
  final harvestRows = data.harvests
      .map(
        (h) => [
            _dateFmt.format(h.harvestDate),
            h.farmerName,
            h.cropName,
            h.cropCategory,
            exportQuantity(h.quantityKg, h.unit),
            formatBatchNumber(h.batchNumber),
            exportQuantity(h.spoiledKg, h.unit),
        ],
      )
      .toList();
  // Batches & Stock is printed as two tables so each stays readable on a
  // portrait page: the quantities, then the status and condition. Both start
  // with Farmer, Crop and Batch # so a row can be matched across them.
  final batchQuantityRows = batches.batches
      .map(
        (b) => [
          b.farmerName,
          b.cropName,
          formatBatchNumber(b.batchNumber),
          exportQuantity(b.quantityKg, b.unit),
          exportQuantity(b.availableKg, b.unit),
          exportQuantity(b.reservedKg, b.unit),
          exportQuantity(b.soldKg, b.unit),
          exportQuantity(b.spoiledKg, b.unit),
        ],
      )
      .toList();
  final batchConditionRows = batches.batches
      .map(
        (b) => [
          b.farmerName,
          b.cropName,
          formatBatchNumber(b.batchNumber),
          batchStatusExportLabel(b.status),
          b.conditionLabel,
          b.shelfLifeExportLabel,
        ],
      )
      .toList();
  return _buildDocument(
    title: 'Harvest Report',
    subtitle: _withScope(
      scopeText,
      'Total Yield: ${_n(data.totalYieldKg)} kg — ${data.harvestCount} harvests'
      ' · Rotten/Lost: ${_n(batches.totalSpoiledKg)} kg'
      '${data.programReceivedCount > 0 ? ' · Received from programs (not harvest): ${_n(data.programReceivedKg)} kg' : ''}',
    ),
    sections: [
      _heading('Harvest Activity'),
      _table([
        'Date',
        'Farmer',
        'Crop',
        'Category',
        'Qty (kg)',
        'Batch #',
        'Rotten/Lost (kg)',
      ], harvestRows),
      _heading('Batches & Stock: Quantities'),
      _table([
        'Farmer',
        'Crop',
        'Batch #',
        'Harvested (kg)',
        'Available (kg)',
        'Committed (kg)',
        'Sold (kg)',
        'Rotten/Lost (kg)',
      ], batchQuantityRows),
      _heading('Batches & Stock: Status and Condition'),
      _table([
        'Farmer',
        'Crop',
        'Batch #',
        'Status',
        'Condition',
        'Shelf Life',
      ], batchConditionRows),
    ],
  );
}

Future<pw.Document> buildExpenseReportPdf(
  ExpenseReportData data, {
  String? scopeText,
}) async {
  final rows = data.expenses
      .map(
        (e) => [
          _dateFmt.format(e.expenseDate),
          e.farmerName,
          e.name,
          e.category,
          e.description,
          e.isSubsidy ? '0.00' : _n(e.amount),
          e.isSubsidy ? 'Yes' : 'No',
        ],
      )
      .toList();
  return _buildDocument(
    title: 'Expense Report',
    subtitle: _withScope(
      scopeText,
      'Paid by Farmers: PHP ${_n(data.totalFarmerFundedAmount)} — ${data.totalEntryCount} entries',
    ),
    sections: [
      _table([
        'Date',
        'Farmer',
        'Expense',
        'Category',
        'Description',
        'Amount (PHP)',
        'Subsidized',
      ], rows),
    ],
  );
}

Future<pw.Document> buildLoanReportPdf(
  List<AdminLoanSummary> loans, {
  String? scopeText,
}) async {
  final summary = LoanPeriodSummary.fromLoans(loans);
  final rows = loans
      .map(
        (l) => [
          l.referenceNo,
          l.farmerName,
          _dateFmt.format(l.issuedDate),
          l.itemNames.join('; '),
          _n(l.totalValue),
          _n(l.amountPaid),
          _n(l.remainingBalance),
          loanStatusExportLabel(l.status),
          _n(l.monthlyPayment),
          l.nextPaymentDate == null ? '' : _dateFmt.format(l.nextPaymentDate!),
          l.sourceProgramName ?? '',
          l.notes ?? '',
        ],
      )
      .toList();
  return _buildDocument(
    landscape: true,
    title: 'Loan Report',
    subtitle: _withScope(
      scopeText,
      '${loans.length} loans issued — Total PHP ${_n(summary.totalIssued)}, '
      'Paid PHP ${_n(summary.totalCollected)}, '
      'Balance PHP ${_n(summary.totalOutstanding)}',
    ),
    sections: [
      _table([
        'Reference',
        'Farmer',
        'Issued',
        'Items',
        'Total (PHP)',
        'Paid (PHP)',
        'Balance (PHP)',
        'Status',
        'Monthly (PHP)',
        'Next Payment',
        'From Program',
        'Notes',
      ], rows),
    ],
  );
}

Future<pw.Document> buildMemberContributionReportPdf(
  MemberContributionReportData data, {
  String? scopeText,
}) async {
  final rows = data.rows
      .map(
        (r) => [
          r.farmerName,
          _n(r.capitalBalance),
          _n(r.capitalAtYearStart),
          _n(r.capitalAddedInYear),
          _n(r.memberPaidInYear),
          _n(r.purchaseCredited),
          _n(r.offersCredited),
          '${r.capitalShares}',
          _n(r.remainingForNextShare),
          _n(r.monthlyDue),
          _n(r.monthlyBalance),
          '${r.monthsPaid}/${r.monthsPartial}/${r.monthsUnpaid}/${r.monthsOverdue}/${r.monthsWaived}',
          _n(r.programPurchasesAmount),
          _n(r.totalAmount),
        ],
      )
      .toList();
  return _buildDocument(
    landscape: true,
    title: 'Member Contribution Report — ${data.year}',
    subtitle: _withScope(
      scopeText,
      'Total Capital Share: PHP ${_n(data.totalCapital)} — added in ${data.year}: PHP ${_n(data.totalCapitalAdded)} '
      '(Monthly Contribution ${_n(data.totalMemberPaid)}, '
      'Cooperative Purchase ${_n(data.totalPurchaseCredited)}, '
      'Offer to Cooperative ${_n(data.totalOffersCredited)}) — '
      '${data.contributingMemberCount}/${data.memberCount} members contributed',
    ),
    sections: [
      _table([
        'Farmer',
        'Total Capital Share (PHP)',
        'At Start of Year (PHP)',
        'Added in Year (PHP)',
        'Monthly Contribution (PHP)',
        'Cooperative Purchase (PHP)',
        'Offer to Cooperative (PHP)',
        'Full Shares',
        'Remaining for Next Share (PHP)',
        'Monthly Due, Not Counted (PHP)',
        'Monthly Unpaid, Not Counted (PHP)',
        'Months Paid/Partial/Unpaid/Overdue/Waived',
        'Purchases Made (reference)',
        'Completed Offers (reference)',
      ], rows),
    ],
  );
}

Future<pw.Document> buildCoopStockReportPdf(
  CoopStockReportData data, {
  String? scopeText,
}) async {
  final rows = data.items
      .map(
        (i) => [
          i.itemName,
          i.category,
          itemTypeExportLabel(i.itemType),
          _n(i.quantityOnHand),
          i.unit,
          _n(i.reorderLevel),
          i.unitCost == null ? '' : _n(i.unitCost!),
          i.lastRestockedAt == null ? '' : _dateFmt.format(i.lastRestockedAt!),
          i.isLowStock ? 'Yes' : 'No',
        ],
      )
      .toList();
  return _buildDocument(
    landscape: true,
    title: 'Cooperative Stock Report',
    subtitle: _withScope(
      scopeText,
      '${data.totalItems} items (${data.seedsItemCount} seeds, ${data.produceItemCount} produce, ${data.nonCropItemCount} non-crop) — ${data.lowStockCount} low stock',
    ),
    sections: [
      _table([
        'Item',
        'Category',
        'Item Type',
        'On Hand',
        'Unit',
        'Reorder Level',
        'Unit Cost (PHP)',
        'Last Restocked',
        'Low Stock',
      ], rows),
    ],
  );
}

pw.Widget _heading(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
  child: pw.Text(
    _safe(text),
    style: const pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 12,
      color: PdfColors.green900,
    ),
  ),
);

Future<pw.Document> buildAnalyticsPdf(
  AnalyticsExportData data, {
  String? scopeText,
}) async {
  final p = data.participation;
  return _buildDocument(
    title: 'Analytics Dashboard',
    subtitle: _withScope(
      scopeText,
      '${p.totalMembers} active members, '
      '${data.participationRatePercent.toStringAsFixed(0)}% took part',
    ),
    sections: [
      _heading('Member Participation'),
      _table(
        ['Group', 'Members'],
        [
          ['Harvested', '${p.activeHarvestedCount}'],
          ['Listed Only', '${p.activeListedCount}'],
          ['No Activity', '${p.inactiveCount}'],
          ['Active Members', '${p.totalMembers}'],
        ],
      ),
      if (p.inactiveFarmers.isNotEmpty) ...[
        _heading('Members With No Activity'),
        _table(['Farmer'], p.inactiveFarmers.map((f) => [f.fullName]).toList()),
      ],
      _heading('Top Harvested Crops'),
      _table([
        'Crop',
        'Volume (kg)',
      ], data.topCrops.map((c) => [c.cropName, _n(c.volumeKg)]).toList()),
      _heading('Price Snapshot'),
      _table(
        [
          'Crop',
          'Market Type',
          'Current (PHP/kg)',
          'Previous (PHP/kg)',
          'Updated',
        ],
        data.priceCards
            .map(
              (c) => [
                c.cropName,
                data.marketTypeName(c.priceType),
                _n(c.currentPrice),
                c.previousPrice?.toStringAsFixed(2) ?? '',
                c.recordedAt == null ? '' : _dateFmt.format(c.recordedAt!),
              ],
            )
            .toList(),
      ),
      _heading('Planting Forecast'),
      _table(
        ['Crop', 'Category', 'Last Cycle (kg)', 'Forecast (kg)', 'Trend'],
        data.forecasts
            .map(
              (f) => [
                f.cropName,
                f.category,
                _n(f.mostRecentCycleKg),
                f.hasForecast ? _n(f.forecastNextCycleKg!) : '',
                analyticsTrendLabel(f.trend),
              ],
            )
            .toList(),
      ),
    ],
  );
}
