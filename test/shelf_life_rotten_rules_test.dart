import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/shelf_life_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('ShelfLifeNote layout', () {
    testWidgets(
      'gives message full card width and places action below when action is provided',
      (tester) async {
        const message =
            'Past its shelf life: buyers cannot see or buy this listing. '
            'Check the produce and confirm it is still good (needs approval), '
            'or report it as rotten.';

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: ShelfLifeNote(
                    icon: Icons.fact_check_outlined,
                    color: Colors.red,
                    text: message,
                    action: TextButton(
                      onPressed: () {},
                      child: const Text('Inspect in Manage Inventory'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final msgBox = tester.getRect(find.text(message));
        final actionBox = tester.getRect(
          find.text('Inspect in Manage Inventory'),
        );

        // Message should use the wide card area, not a narrow ~1-word column.
        expect(msgBox.width, greaterThan(220));
        // Action should sit below the message rather than beside it.
        expect(actionBox.top, greaterThanOrEqualTo(msgBox.bottom));
      },
    );
  });

  group('Rotten/Lost SQL contract', () {
    test(
      's06 cancels only unfulfilled orders and advises ordering a different product',
      () {
        final sql = File(
          'supabase_schema/supabase_schema_shelf_life_s06_rotten_sync_and_channels.sql',
        ).readAsStringSync();

        expect(
          sql,
          contains(
            "ord.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery')",
          ),
        );
        expect(sql, contains('Please order a different product.'));
        expect(sql, isNot(contains('FROM cooperative_purchase_offers cpo')));
        expect(sql, contains('FROM cooperative_purchase_offers co'));
      },
    );
  });
}
