import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sagana/main.dart';

void main() {
  testWidgets('SAGANA app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SAGANAApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
