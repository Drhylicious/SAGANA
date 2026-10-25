import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/quantity_utils.dart';
import 'package:sagana/data/models/admin_reports_model.dart';

/// The four selling channels with decimal quantities and prices: the money
/// arithmetic, the Sales Report combination, and source-level contracts that
/// keep the Farmer and Manager sides reading the same data. The database half
/// (stock, totals, statuses) is exercised by
/// supabase_schema/supabase_schema_selling_channels_test.sql.
String read(String path) => File(path).readAsStringSync();

SalesTransactionRow row(
  String channel,
  String id,
  double qty,
  double amount, {
  String unit = 'kg',
  DateTime? at,
}) => SalesTransactionRow(
  id: id,
  farmerName: 'Farmer',
  cropType: 'zz',
  cropName: 'Zz Test Crop',
  quantityKg: qty,
  unit: unit,
  amount: amount,
  saleDate: at ?? DateTime(2026, 10, 25),
  sellingType: channel,
);

void main() {
  group('moneyOf rounds to the centavo exactly like the database', () {
    test('the figures used in the end-to-end SQL test', () {
      expect(moneyOf(1.25, 12.50), 15.63); // 15.625
      expect(moneyOf(0.45, 12.50), 5.63); // 5.625
      expect(moneyOf(2.55, 12.50), 31.88); // 31.875
      expect(moneyOf(2.50, 75.25), 188.13); // 188.125
      expect(moneyOf(3.45, 45.50), 156.98); // 156.975
    });

    test('plain cases and the binary-float traps', () {
      expect(moneyOf(10.75, 125.75), 1351.81); // 1351.8125
      expect(moneyOf(0.1, 3), 0.3);
      expect(moneyOf(4.25, 12.50), 53.13); // 53.125
      expect(moneyOf(1, 12.50), 12.5);
      expect(moneyOf(0.01, 0.01), 0.0); // 0.0001
      expect(moneyOf(0.45, 0.45), 0.2); // 0.2025
    });
  });

  group('Sales Report combines all four channels', () {
    final offers = [row('offer_to_cooperative', 'o1', 2.50, 188.13)];
    final market = [
      row('marketplace', 'm1', 1.25, 15.63, unit: 'sack'),
      row('marketplace', 'm2', 0.45, 5.63, unit: 'sack'),
      row('marketplace', 'm3', 2.55, 31.88, unit: 'sack'),
    ];
    final informal = [
      row('informal_sale', 'i1', 1.25, 125.75),
      row('informal_sale', 'i2', 2.75, 99.99),
    ];
    final daAmad = [row('da_amad_market_linking', 'd1', 3.45, 156.98)];

    final report = buildSalesReportData(
      offerRows: offers,
      marketplaceRows: market,
      informalRows: informal,
      daAmadRows: daAmad,
    );

    test('revenue is the sum of the sales, to the centavo', () {
      expect(report.totalRevenue, 623.99);
      expect(report.transactionCount, 7);
    });

    test('each sale is counted once, under its own channel', () {
      expect(report.transactions.map((t) => t.id).toSet().length, 7);
      final byChannel = {for (final c in report.channelTotals) c.sellingType: c};
      expect(byChannel['marketplace']!.amount, 53.14);
      expect(byChannel['marketplace']!.transactionCount, 3);
      expect(byChannel['offer_to_cooperative']!.amount, 188.13);
      expect(byChannel['offer_to_cooperative']!.transactionCount, 1);
      expect(byChannel['informal_sale']!.amount, 225.74);
      expect(byChannel['informal_sale']!.transactionCount, 2);
      expect(byChannel['da_amad_market_linking']!.amount, 156.98);
      expect(byChannel['da_amad_market_linking']!.transactionCount, 1);
      expect(
        byChannel.values.fold<double>(0, (s, c) => s + c.amount).toStringAsFixed(2),
        '623.99',
      );
    });

    test('the kg total never adds sacks to kilograms', () {
      // 2.50 + 1.25 + 2.75 + 3.45 kg; the 4.25 sacks are sales and revenue,
      // but not kilograms.
      expect(report.totalQuantityKg, 9.95);
      final byChannel = {for (final c in report.channelTotals) c.sellingType: c};
      expect(byChannel['marketplace']!.quantityKg, 0);
      expect(byChannel['informal_sale']!.quantityKg, 4.0);
    });

    test('a channel with no sales is still shown, at zero', () {
      final r = buildSalesReportData(
        offerRows: const [],
        marketplaceRows: market,
        informalRows: const [],
        daAmadRows: const [],
      );
      expect(r.channelTotals.map((c) => c.sellingType), [
        'offer_to_cooperative',
        'marketplace',
        'informal_sale',
        'da_amad_market_linking',
      ]);
      expect(r.channelTotals.first.amount, 0);
      expect(r.channelTotals.first.transactionCount, 0);
    });

    test('sums of centavos do not drift (0.1 + 0.2 style)', () {
      final r = buildSalesReportData(
        offerRows: const [],
        marketplaceRows: const [],
        informalRows: [
          row('informal_sale', 'a', 0.1, 0.10),
          row('informal_sale', 'b', 0.2, 0.20),
        ],
        daAmadRows: const [],
      );
      expect(r.totalRevenue, 0.3);
      expect(r.totalQuantityKg, 0.3);
    });

    test('the monthly trend buckets by month', () {
      final r = buildSalesReportData(
        offerRows: const [],
        marketplaceRows: [
          row('marketplace', 'a', 1, 10.10, at: DateTime(2026, 9, 3)),
          row('marketplace', 'b', 1, 20.20, at: DateTime(2026, 10, 3)),
          row('marketplace', 'c', 1, 5.05, at: DateTime(2026, 10, 28)),
        ],
        informalRows: const [],
        daAmadRows: const [],
      );
      expect(r.monthlyTrend, [10.10, 25.25]);
    });
  });

  group('Farmer and Manager read the same DA-AMAD rule', () {
    test('both use confirmed, then requested, then enrolled volume', () {
      for (final f in [
        'lib/data/repositories/admin_reports_repository.dart',
        'lib/data/repositories/farmer_transaction_repository.dart',
        'lib/data/repositories/dashboard_repository.dart',
      ]) {
        final src = read(f);
        expect(src, contains('confirmed_volume_kg'), reason: f);
        expect(src, contains('requested_volume_kg'), reason: f);
      }
    });

    test('both compute the amount with the centavo-exact helper', () {
      expect(read('lib/data/repositories/admin_reports_repository.dart'),
          contains('moneyOf(qty, pricePerKg)'));
      expect(read('lib/data/repositories/farmer_transaction_repository.dart'),
          contains('moneyOf(qty, pricePerKg)'));
      expect(read('lib/data/repositories/dashboard_repository.dart'),
          contains('moneyOf(quantityKg, pricePerKg)'));
    });

    test('the Sales Report is built by the tested function', () {
      expect(read('lib/data/repositories/admin_reports_repository.dart'),
          contains('return buildSalesReportData('));
    });
  });

  group('DA-AMAD screens keep their decimals', () {
    test('no volume is rounded to a whole number', () {
      for (final f in [
        'lib/presentation/screens/admin/market_linking_screen.dart',
        'lib/presentation/screens/farmer/my_market_linking_screen.dart',
      ]) {
        final src = read(f);
        expect(RegExp(r'[vV]olumeKg!?\)?\.toStringAsFixed\(0\)').hasMatch(src),
            isFalse, reason: f);
        expect(src.contains('FilteringTextInputFormatter.allow(RegExp(r\'^\\d*\\.?\\d*\'))'),
            isFalse, reason: '$f still allows unlimited decimals');
      }
    });

    test('a buyer needs a price and a quantity before it can be saved', () {
      final src = read('lib/presentation/screens/admin/market_linking_screen.dart');
      expect(src, contains('parseDecimal(_priceCtrl.text)'));
      expect(src, contains('parseDecimal(_requestedVolumeCtrl.text)'));
      expect(src, contains('l10n.marketLinkPriceRequired'));
    });
  });

  group('the integrity migration', () {
    final sql = read('supabase_schema/supabase_schema_selling_channels_integrity.sql');

    test('recomputes sold_kg from the real sales, for all four channels', () {
      expect(sql, contains('CREATE OR REPLACE FUNCTION public.reconcile_batch_sold'));
      expect(sql, contains("o.status = 'completed'"));
      expect(sql, contains('FROM informal_sales i'));
      expect(sql, contains("c.status = 'confirmed'"));
      expect(sql, contains("m.status = 'completed'"));
      for (final trg in [
        'trg_orders_reconcile',
        'trg_informal_sales_reconcile',
        'trg_coop_offers_reconcile',
        'trg_market_linking_reconcile',
      ]) {
        expect(sql, contains('CREATE TRIGGER $trg'));
      }
    });

    test('sets the value, never adds to it', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.reconcile_batch_sold'));
      expect(fn.contains('sold_kg = sold_kg +'), isFalse);
      expect(fn, contains('SET sold_kg = v_sold'));
    });

    test('Ginger exclusivity and every existing row are left alone', () {
      final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      expect(code.contains('enforce_selling_channel'), isFalse);
      expect(RegExp(r'DELETE\s+FROM|DROP\s+(TABLE|COLUMN)', caseSensitive: false).hasMatch(code), isFalse);
      // The only UPDATEs are on inventory_batches: the reservation helper and
      // reconcile_batch_sold. No order, sale or program row is rewritten.
      final updates = RegExp(r'UPDATE\s+(public\.)?(\w+)\s+SET', caseSensitive: false)
          .allMatches(code)
          .map((m) => m.group(2))
          .toList();
      expect(updates, ['inventory_batches', 'inventory_batches']);
    });

    test('reservation checks owner, positive quantity and 2 decimals', () {
      expect(sql, contains('v_farmer_id <> auth.uid()'));
      expect(sql, contains('p_quantity <> round(p_quantity, 2)'));
      expect(sql, contains('IF p_quantity IS NULL OR p_quantity <= 0'));
    });

    test('DA-AMAD sale needs a price; Ginger submission needs a valid volume', () {
      expect(sql, contains('guard_market_linking_sale'));
      expect(sql, contains('p_volume_kg > v_available'));
      expect(sql, contains('p_volume_kg <> round(p_volume_kg, 2)'));
    });
  });

  group('the end-to-end SQL test covers every channel', () {
    final sql = read('supabase_schema/supabase_schema_selling_channels_test.sql');
    test('all four channels and both reading sides', () {
      for (final call in [
        'create_listing_with_reservation',
        'approve_listing',
        'place_order',
        'complete_order',
        'offer_batch_to_cooperative',
        'accept_cooperative_offer',
        'record_informal_sale',
        'submit_ginger_for_sale',
        'complete_market_linking',
      ]) {
        expect(sql, contains(call), reason: call);
      }
      expect(sql, contains("'Manager'"));
      expect(sql, contains("'Farmer'"));
      expect(sql, contains('FAILED CHECKS'));
    });
  });
}
