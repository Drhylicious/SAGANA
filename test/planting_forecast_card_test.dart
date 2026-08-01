import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/widgets/planting_forecast_card.dart';

void main() {
  testWidgets('planting forecast header stays within bounds on narrow width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: const PlantingForecastSectionHeader(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
