import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/theme/sagana_colors.dart';
import 'package:sagana/presentation/screens/admin/farmer_management_screen.dart';

void main() {
  testWidgets('farmer management header stays within bounds on narrow width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: FarmerManagementHeader(
                title: 'Very long farmer management title that should fit safely',
                memberCount: 12,
                onFilterTap: () {},
                onAddTap: () {},
                colorScheme: const ColorScheme.light(),
                saganaColors: SaganaColors.light,
                showFilterBadge: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
