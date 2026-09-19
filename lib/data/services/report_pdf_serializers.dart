import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/admin_loan_model.dart';
import '../models/admin_reports_model.dart';

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
/// (farmer name, member ID, etc. — see fetchFarmerInfoMap's fallbacks),
/// so every string reaching a PDF page is routed through this first.
/// Confirmed via a runtime smoke test during Phase 15 verification,
/// not just a theoretical concern.
String _safe(String s) => s.replaceAll('—', '-').replaceAll('–', '-');

List<String> _safeRow(List<String> row) => row.map(_safe).toList();

pw.Document _buildDocument({
  required String title,
  required String subtitle,
  required List<pw.Widget> sections,
}) {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _safe('SAGANA — $title'),
            style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
          ),
          pw.Text(
            _safe(subtitle),
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Divider(color: PdfColors.grey400, height: 16),
        ],
      ),
      build: (context) => sections,
    ),
  );
  return doc;
}

pw.Widget _table(List<String> headers, List<List<String>> rows) {
  if (rows.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 12),
      child: pw.Text('No records for this period.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
    );
  }
  return pw.TableHelper.fromTextArray(
    headers: _safeRow(headers),
    data: rows.map(_safeRow).toList(),
    headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
    cellStyle: const pw.TextStyle(fontSize: 7.5),
    cellAlignment: pw.Alignment.centerLeft,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
    rowDecoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.3)),
    ),
  );
}

Future<pw.Document> buildSalesReportPdf(SalesReportData data) async {
  final rows = data.transactions
      .map((t) => [
            t.sellingType,
            t.marketType ?? '',
            t.farmerName,
            t.memberId,
            t.cropName,
            t.quantityKg.toStringAsFixed(2),
            t.amount.toStringAsFixed(2),
            _dateFmt.format(t.saleDate),
            t.referenceNo ?? '',
          ])
      .toList();
  return _buildDocument(
    title: 'Sales Report',
    subtitle: 'Total Revenue: PHP ${data.totalRevenue.toStringAsFixed(2)} — ${data.transactionCount} transactions',
    sections: [
      _table(
        ['Selling Type', 'Market Type', 'Farmer', 'Member ID', 'Crop', 'Qty (kg)', 'Amount (PHP)', 'Date', 'Reference'],
        rows,
      ),
    ],
  );
}

Future<pw.Document> buildHarvestReportPdf(
  HarvestReportData data,
  InventoryReportData batches,
) async {
  final harvestRows = data.harvests
      .map((h) => [
            _dateFmt.format(h.harvestDate),
            h.farmerName,
            h.memberId,
            h.cropName,
            h.quantityKg.toStringAsFixed(2),
            h.submittedToCooperative ? 'Yes' : 'No',
            h.isSynced ? 'Yes' : 'No',
          ])
      .toList();
  final batchRows = batches.batches
      .map((b) => [
            b.farmerName,
            b.memberId,
            b.cropName,
            b.batchNumber,
            b.availableKg.toStringAsFixed(2),
            b.reservedKg.toStringAsFixed(2),
            b.soldKg.toStringAsFixed(2),
            b.status,
          ])
      .toList();
  return _buildDocument(
    title: 'Harvest Report',
    subtitle: 'Total Yield: ${data.totalYieldKg.toStringAsFixed(2)} kg — ${data.harvestCount} harvests',
    sections: [
      pw.Text('Harvest Activity', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 6),
      _table(['Date', 'Farmer', 'Member ID', 'Crop', 'Qty (kg)', 'To Coop', 'Synced'], harvestRows),
      pw.SizedBox(height: 16),
      pw.Text('Batches & Stock', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 6),
      _table(['Farmer', 'Member ID', 'Crop', 'Batch #', 'Available (kg)', 'Reserved (kg)', 'Sold (kg)', 'Status'], batchRows),
    ],
  );
}

Future<pw.Document> buildExpenseReportPdf(ExpenseReportData data) async {
  final rows = data.expenses
      .map((e) => [
            _dateFmt.format(e.expenseDate),
            e.farmerName,
            e.memberId,
            e.category,
            e.description,
            e.isSubsidy ? '0.00' : e.amount.toStringAsFixed(2),
            e.isSubsidy ? 'Yes' : 'No',
          ])
      .toList();
  return _buildDocument(
    title: 'Expense Report',
    subtitle: 'Farmer-Funded Total: PHP ${data.totalFarmerFundedAmount.toStringAsFixed(2)} — ${data.totalEntryCount} entries',
    sections: [
      _table(['Date', 'Farmer', 'Member ID', 'Category', 'Description', 'Amount (PHP)', 'Subsidized'], rows),
    ],
  );
}

Future<pw.Document> buildLoanReportPdf(List<AdminLoanSummary> loans) async {
  final rows = loans
      .map((l) => [
            l.referenceNo,
            l.farmerName,
            l.memberId,
            _dateFmt.format(l.issuedDate),
            l.itemNames.join('; '),
            l.totalValue.toStringAsFixed(2),
            l.amountPaid.toStringAsFixed(2),
            l.remainingBalance.toStringAsFixed(2),
            l.status,
          ])
      .toList();
  return _buildDocument(
    title: 'Loan Report',
    subtitle: '${loans.length} loans in this period (status-agnostic — a complete financial record)',
    sections: [
      _table(
        ['Reference', 'Farmer', 'Member ID', 'Issued', 'Items', 'Total (PHP)', 'Paid (PHP)', 'Balance (PHP)', 'Status'],
        rows,
      ),
    ],
  );
}

Future<pw.Document> buildMemberContributionReportPdf(MemberContributionReportData data) async {
  final rows = data.rows
      .map((r) => [
            r.farmerName,
            r.memberId,
            r.palayQtyKg.toStringAsFixed(2),
            r.palayAmount.toStringAsFixed(2),
            r.peanutQtyKg.toStringAsFixed(2),
            r.peanutAmount.toStringAsFixed(2),
            r.otherCropsQtyKg.toStringAsFixed(2),
            r.otherCropsAmount.toStringAsFixed(2),
            r.totalAmount.toStringAsFixed(2),
            r.sharePercent.toStringAsFixed(2),
          ])
      .toList();
  return _buildDocument(
    title: 'Member Patronage Report — ${data.year}',
    subtitle: 'Total Cooperative Sales: PHP ${data.totalCoopSales.toStringAsFixed(2)} — ${data.contributingMemberCount}/${data.memberCount} contributing members',
    sections: [
      _table(
        ['Farmer', 'Member ID', 'Palay (kg)', 'Palay (PHP)', 'Peanut (kg)', 'Peanut (PHP)', 'Other (kg)', 'Other (PHP)', 'Total (PHP)', 'Share (%)'],
        rows,
      ),
    ],
  );
}

Future<pw.Document> buildCoopStockReportPdf(CoopStockReportData data) async {
  final rows = data.items
      .map((i) => [
            i.itemName,
            i.category,
            i.quantityOnHand.toStringAsFixed(2),
            i.unit,
            i.isLowStock ? 'Yes' : 'No',
          ])
      .toList();
  return _buildDocument(
    title: 'Cooperative Stock Report',
    subtitle: '${data.totalItems} items — ${data.lowStockCount} low stock',
    sections: [
      _table(['Item', 'Category', 'On Hand', 'Unit', 'Low Stock'], rows),
    ],
  );
}
