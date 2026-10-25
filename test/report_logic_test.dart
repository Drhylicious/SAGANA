import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_analytics_model.dart';
import 'package:sagana/data/models/admin_loan_model.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/data/models/export_model.dart';

AdminLoanSummary _loan(
  String status,
  double total,
  double paid, {
  String id = 'l',
}) => AdminLoanSummary(
  id: id,
  farmerId: 'f',
  farmerName: 'Farmer',
  referenceNo: 'LRN-1',
  issuedDate: DateTime(2026, 10, 1),
  totalValue: total,
  amountPaid: paid,
  status: status,
  monthlyPayment: 0,
  itemNames: const [],
);

void main() {
  group('LoanPeriodSummary', () {
    test('adds up the loans in the list and counts each status', () {
      final summary = LoanPeriodSummary.fromLoans([
        _loan('active', 1000, 250),
        _loan('overdue', 500, 100),
        _loan('paid', 300, 300),
      ]);
      expect(summary.loanCount, 3);
      expect(summary.activeCount, 1);
      expect(summary.overdueCount, 1);
      expect(summary.paidCount, 1);
      expect(summary.totalIssued, 1800);
      expect(summary.totalCollected, 650);
      expect(summary.totalOutstanding, 1150); // 750 + 400, paid loan owes 0
      expect(summary.overdueBalance, 400);
      expect(summary.repaymentRatePercent, closeTo(36.11, 0.01));
    });

    test('an empty period is neutral, not healthy-looking', () {
      final summary = LoanPeriodSummary.fromLoans(const []);
      expect(summary.hasActivity, isFalse);
      expect(summary.repaymentRatePercent, 0);
      expect(summary.totalOutstanding, 0);
    });

    test('is healthy while overdue loans are at most 20% of outstanding', () {
      final healthy = LoanPeriodSummary.fromLoans([
        for (var i = 0; i < 4; i++) _loan('active', 100, 0, id: 'a$i'),
        _loan('overdue', 100, 0),
      ]);
      expect(healthy.isHealthy, isTrue); // 1 of 5 = 20%

      final attention = LoanPeriodSummary.fromLoans([
        _loan('active', 100, 0),
        _loan('overdue', 100, 0),
      ]);
      expect(attention.isHealthy, isFalse); // 1 of 2 = 50%
    });

    test('a fully repaid loan never goes past 100%', () {
      final summary = LoanPeriodSummary.fromLoans([_loan('paid', 100, 150)]);
      expect(summary.repaymentRatePercent, 100);
    });
  });

  group('classifyParticipation', () {
    test('the three tiers always add up to the member total', () {
      final tiers = classifyParticipation(
        memberIds: ['a', 'b', 'c', 'd'],
        harvestedIds: {'a', 'b'},
        listedIds: {'b', 'c'},
      );
      expect(tiers.harvested, {'a', 'b'});
      expect(tiers.listedOnly, {'c'}); // b harvested too, so counted once
      expect(tiers.inactive, ['d']);
      expect(
        tiers.harvested.length + tiers.listedOnly.length + tiers.inactive.length,
        4,
      );
    });

    test('people who are not active members are never counted', () {
      final tiers = classifyParticipation(
        memberIds: ['a'],
        harvestedIds: {'a', 'former-member'},
        listedIds: {'another-former-member'},
      );
      expect(tiers.harvested, {'a'});
      expect(tiers.listedOnly, isEmpty);
      expect(tiers.inactive, isEmpty);
    });
  });

  group('committedBatchKg', () {
    test('is what is left after available and sold stock', () {
      expect(
        committedBatchKg(quantityKg: 100, availableKg: 30, soldKg: 20),
        50,
      );
    });

    test('is zero for an untouched or sold-out batch, never negative', () {
      expect(committedBatchKg(quantityKg: 100, availableKg: 100, soldKg: 0), 0);
      expect(committedBatchKg(quantityKg: 100, availableKg: 0, soldKg: 100), 0);
      expect(committedBatchKg(quantityKg: 100, availableKg: 60, soldKg: 60), 0);
    });
  });

  group('selling channel wording', () {
    test('uses one set of names everywhere', () {
      expect(sellingChannelLabel('offer_to_cooperative'), 'Offer to Cooperative');
      expect(sellingChannelLabel('marketplace'), 'Marketplace');
      expect(sellingChannelLabel('informal_sale'), 'Informal Sale');
      expect(
        sellingChannelLabel('da_amad_market_linking'),
        'DA-AMAD Market Linking',
      );
    });

    test('a DA-AMAD sale has no market type, even from an old offline snapshot',
        () {
      final row = SalesTransactionRow.fromMap({
        'id': '1',
        'farmerName': 'F',
        'cropType': 'ginger',
        'cropName': 'Ginger',
        'quantityKg': 10,
        'amount': 100,
        'saleDate': '2026-10-01T00:00:00.000',
        'referenceNo': null,
        'sellingType': 'da_amad_market_linking',
        'marketType': 'DA-AMAD Market',
        'buyerName': null,
        'orderStatus': null,
      });
      expect(row.marketType, isNull);
    });
  });

  group('export scope', () {
    test('Cooperative Stock is a snapshot and Patronage uses a year', () {
      expect(ReportModuleType.coopStock.usesReportPeriod, isFalse);
      expect(ReportModuleType.coopStock.isSnapshot, isTrue);
      expect(ReportModuleType.memberContribution.usesReportPeriod, isFalse);
      expect(ReportModuleType.memberContribution.usesYear, isTrue);
      for (final m in [
        ReportModuleType.sales,
        ReportModuleType.harvest,
        ReportModuleType.expense,
        ReportModuleType.loan,
      ]) {
        expect(m.usesReportPeriod, isTrue, reason: m.name);
      }
    });

    test('exportScopeText names the period with its dates', () {
      final now = DateTime(2026, 10, 25);
      expect(
        exportScopeText(
          ReportModuleType.sales,
          ReportPeriod.thisMonth,
          2026,
          now: now,
        ),
        startsWith('This Month ('),
      );
      expect(
        exportScopeText(
          ReportModuleType.sales,
          ReportPeriod.allTime,
          2026,
          now: now,
        ),
        'All Time (all dates)',
      );
      expect(
        exportScopeText(
          ReportModuleType.memberContribution,
          ReportPeriod.thisMonth,
          2025,
          now: now,
        ),
        'Year 2025',
      );
      expect(
        exportScopeText(
          ReportModuleType.coopStock,
          ReportPeriod.thisMonth,
          2026,
          now: now,
        ),
        'Current stock as of Oct 25, 2026',
      );
    });

    test('status values are written as words, not database codes', () {
      expect(batchStatusExportLabel('low_stock'), 'Low Stock');
      expect(batchStatusExportLabel('reserved'), 'Committed');
      expect(batchStatusExportLabel('sold_out'), 'Sold Out');
      expect(loanStatusExportLabel('overdue'), 'Overdue');
      expect(loanStatusExportLabel('paid'), 'Paid');
    });
  });
}
