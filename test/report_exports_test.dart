import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_loan_model.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/data/services/report_csv_serializers.dart';
import 'package:sagana/data/services/report_pdf_serializers.dart';

SalesTransactionRow _sale(String type) => SalesTransactionRow(
  id: '1',
  farmerName: 'Juan Dela Cruz',
  cropType: 'palay',
  cropName: 'Palay',
  quantityKg: 100,
  amount: 2500,
  saleDate: DateTime(2026, 10, 5),
  referenceNo: 'ORD-20261005-0001',
  sellingType: type,
);

HarvestReportData _harvest() => HarvestReportData(
  totalYieldKg: 120,
  harvestCount: 1,
  unsyncedCount: 0,
  monthlyTrend: const [],
  cropBreakdown: const [],
  harvests: [
    HarvestReportRow(
      id: 'h1',
      farmerId: 'f1',
      farmerName: 'Juan Dela Cruz',
      cropName: 'Palay',
      quantityKg: 120,
      harvestDate: DateTime(2026, 10, 2),
      isSynced: true,
      batchNumber: 'B-001',
    ),
  ],
  soldKgInPeriod: 0,
);

InventoryReportData _inventory() => InventoryReportData(
  totalAvailableKg: 30,
  totalReservedKg: 50,
  totalSoldKg: 20,
  lowStockCount: 0,
  cropBreakdown: const [],
  batches: [
    InventoryReportRow(
      batchId: 'b1',
      farmerId: 'f1',
      farmerName: 'Juan Dela Cruz',
      cropName: 'Palay',
      batchNumber: 'B-001',
      quantityKg: 100,
      availableKg: 30,
      reservedKg: 50,
      soldKg: 20,
      status: 'low_stock',
      createdAt: DateTime(2026, 10, 2),
    ),
  ],
);

AdminLoanSummary _loan(String status) => AdminLoanSummary(
  id: 'l1',
  farmerId: 'f1',
  farmerName: 'Juan Dela Cruz',
  referenceNo: 'LRN-20261001-0001',
  issuedDate: DateTime(2026, 10, 1),
  totalValue: 1000,
  amountPaid: 400,
  status: status,
  monthlyPayment: 100,
  itemNames: const ['Fertilizer'],
);

void main() {
  group('CSV exports', () {
    test('Sales names the channel in words under a "Selling Channel" column',
        () {
      final csv = serializeSalesReportCsv(
        SalesReportData(
          totalRevenue: 2500,
          totalQuantityKg: 100,
          transactionCount: 1,
          monthlyTrend: const [],
          transactions: [_sale('da_amad_market_linking')],
        ),
      );
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('Selling Channel,'));
      expect(lines[1], startsWith('DA-AMAD Market Linking,'));
      expect(csv, isNot(contains('da_amad_market_linking')));
    });

    test('Harvest no longer exports the always-true Synced column, and shows '
        'committed stock', () {
      final csv = serializeHarvestReportCsv(_harvest(), _inventory());
      expect(csv, isNot(contains('Synced')));
      expect(csv, contains('Batch Number'));
      expect(csv, contains('Committed (kg)'));
      expect(csv, isNot(contains('Reserved')));
      expect(csv, contains('Low Stock')); // not the raw "low_stock"
      expect(csv, isNot(contains('low_stock')));
    });

    test('Loan shows the status as a word', () {
      final csv = serializeLoanReportCsv([_loan('overdue')]);
      expect(csv.trim().split('\n')[1], endsWith(',Overdue'));
    });

    test('the header block says what the file covers and its totals', () {
      final header = csvExportHeader(
        reportName: 'Sales Report',
        scopeText: 'This Month (Oct 1, 2026 to Oct 31, 2026)',
        generatedAt: DateTime(2026, 10, 25, 14, 3),
        summary: const [('Total Revenue (PHP)', '2500.00')],
      );
      final lines = header.split('\n');
      expect(lines[0], 'Report,Sales Report');
      expect(lines[1], contains('This Month'));
      expect(lines[2], 'Generated,2026-10-25 14:03');
      expect(lines[3], 'Total Revenue (PHP),2500.00');
      expect(header.endsWith('\n\n'), isTrue, reason: 'blank line before table');
    });
  });

  group('PDF exports', () {
    test('every report type builds a non-empty PDF', () async {
      final docs = [
        await buildSalesReportPdf(
          SalesReportData(
            totalRevenue: 2500,
            totalQuantityKg: 100,
            transactionCount: 1,
            monthlyTrend: const [],
            transactions: [_sale('marketplace')],
          ),
          scopeText: 'This Month',
        ),
        await buildHarvestReportPdf(
          _harvest(),
          _inventory(),
          scopeText: 'This Month',
        ),
        await buildLoanReportPdf([_loan('active')], scopeText: 'This Month'),
        await buildCoopStockReportPdf(
          CoopStockReportData.empty,
          scopeText: 'Current stock',
        ),
      ];
      for (final doc in docs) {
        expect((await doc.save()).length, greaterThan(500));
      }
    });
  });
}
