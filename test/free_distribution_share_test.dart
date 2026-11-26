import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/presentation/screens/farmer/my_programs_screen.dart';

void main() {
  group('Free Distribution Cooperative Share models', () {
    test('CooperativeProgram parses cooperative_share_percent', () {
      final freeDist = CooperativeProgram.fromMap({
        'id': 'p1',
        'program_name': 'Pechay Distribution',
        'program_type': 'Crop',
        'program_purpose': 'distribution',
        'cooperative_share_percent': 10,
      });
      expect(freeDist.cooperativeSharePercent, 10);
      expect(freeDist.hasCooperativeShare, isTrue);

      final zeroShare = CooperativeProgram.fromMap({
        'id': 'p2',
        'program_name': 'Seed Distribution',
        'program_type': 'Seeds',
        'program_purpose': 'distribution',
      });
      expect(zeroShare.cooperativeSharePercent, 0);
      expect(zeroShare.hasCooperativeShare, isFalse);

      final sales = CooperativeProgram.fromMap({
        'id': 'p3',
        'program_name': 'Coop Store',
        'program_type': 'Store',
        'program_purpose': 'sales',
        'cooperative_share_percent': 10,
      });
      expect(sales.hasCooperativeShare, isFalse);
    });

    test('ProgramDistributionSummary and ProgramSaleShare parse fields', () {
      final summary = ProgramDistributionSummary.fromMap({
        'distributed_qty': 10,
        'sold_qty': 6,
        'unsold_qty': 0,
        'rotten_qty': 4,
        'total_owed': 60,
        'total_paid': 0,
        'total_unpaid': 60,
        'shares': [
          {
            'id': 's1',
            'program_id': 'p1',
            'program_member_id': 'pm1',
            'farmer_id': 'f1',
            'farmer_name': 'Juan Dela Cruz',
            'batch_id': 'b1',
            'crop_name': 'Pechay',
            'unit': 'kg',
            'sale_channel': 'marketplace',
            'quantity_sold': 6,
            'gross_amount': 600,
            'share_percent': 10,
            'amount_owed': 60,
            'status': 'unpaid',
            'created_at': '2026-11-26T00:00:00Z',
          },
        ],
      });

      expect(summary.distributedQty, 10);
      expect(summary.soldQty, 6);
      expect(summary.unsoldQty, 0);
      expect(summary.rottenQty, 4);
      expect(summary.totalOwed, 60);
      expect(summary.totalUnpaid, 60);
      expect(summary.shares, hasLength(1));
      expect(summary.shares.first.isPaid, isFalse);
      expect(summary.shares.first.saleChannel, 'marketplace');
    });

    test('FarmerDistributionSummary parses all 6 tracking metrics', () {
      final fd = FarmerDistributionSummary.fromMap({
        'to_distribute_count': 1,
        'distributed_count': 2,
        'completed_count': 1,
        'distributed_qty': 15,
        'sold_qty': 9,
        'unsold_qty': 2,
        'rotten_qty': 4,
        'total_owed': 90,
        'total_paid': 50,
        'total_unpaid': 40,
      });
      expect(fd.toDistributeCount, 1);
      expect(fd.distributedCount, 2);
      expect(fd.completedCount, 1);
      expect(fd.distributedQty, 15);
      expect(fd.soldQty, 9);
      expect(fd.unsoldQty, 2);
      expect(fd.rottenQty, 4);
      expect(fd.totalOwed, 90);
      expect(fd.totalPaid, 50);
      expect(fd.totalUnpaid, 40);
    });
  });

  group('Free Distribution Share SQL contract', () {
    final sql = File(
      'supabase_schema/supabase_schema_free_distribution_share.sql',
    ).readAsStringSync();

    test('defines cooperative_share_percent and program_sale_shares', () {
      expect(sql, contains('cooperative_share_percent'));
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.program_sale_shares'));
      expect(sql, contains('uq_program_sale_shares_source'));
    });

    test('hooks all 3 selling channels and blocks Offer to Cooperative', () {
      expect(sql, contains('trg_order_program_share'));
      expect(sql, contains('trg_informal_sale_program_share'));
      expect(sql, contains('trg_market_linking_sale_program_share'));
      expect(sql, contains('trg_block_program_received_coop_offer'));
    });

    test('gates record_program_share_payment under dashboard manage', () {
      expect(sql, contains("has_module_access('dashboard', 'manage')"));
      expect(sql, contains("VALUES ('rpc', 'record_program_share_payment', 'dashboard')"));
    });

    test('skips share creation when cooperative_share_percent is 0%', () {
      expect(sql, contains('AND COALESCE(cp.cooperative_share_percent, 0) > 0'));
    });
  });

  group('Farmer MyProgramCard share visibility', () {
    Widget wrap(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    final entry = MyProgramEntry(
      id: 'pm1',
      programId: 'p1',
      programName: 'Pechay Free Distribution',
      programType: 'Crop',
      programPurpose: 'distribution',
      programStatus: 'active',
      enrollmentStatus: 'active',
      enrolledAt: DateTime(2026, 11, 1),
      quantityGiven: 10,
      distributedAt: DateTime(2026, 11, 2),
      itemName: 'Pechay',
      itemUnit: 'kg',
    );

    testWidgets('0% Free Distribution shows no Coop Share line', (tester) async {
      await tester.pumpWidget(
        wrap(
          MyProgramCard(
            entry: entry,
            readOnly: true,
            formatDate: (d) => '${d.year}-${d.month}-${d.day}',
            statusLabel: (s) => s,
          ),
        ),
      );
      expect(find.textContaining('Coop Share'), findsNothing);
    });

    testWidgets('Scenario A & Partial Sale show Unpaid/Paid Coop Share on MyProgramCard', (tester) async {
      final share = ProgramSaleShare.fromMap({
        'id': 's1',
        'program_id': 'p1',
        'program_member_id': 'pm1',
        'farmer_id': 'f1',
        'batch_id': 'b1',
        'crop_name': 'Pechay',
        'unit': 'kg',
        'sale_channel': 'marketplace',
        'quantity_sold': 6,
        'gross_amount': 600,
        'share_percent': 10,
        'amount_owed': 60,
        'status': 'unpaid',
        'created_at': '2026-11-26T00:00:00Z',
      });

      await tester.pumpWidget(
        wrap(
          MyProgramCard(
            entry: entry,
            shares: [share],
            readOnly: true,
            formatDate: (d) => '${d.year}-${d.month}-${d.day}',
            statusLabel: (s) => s,
          ),
        ),
      );
      expect(find.textContaining('Coop Share (10% on 6 kg): ₱60.00 · Unpaid'), findsOneWidget);
    });
  });
}
