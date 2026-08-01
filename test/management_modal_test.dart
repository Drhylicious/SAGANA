import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';

void main() {
  testWidgets('ManagementModalShell renders ListTile content without assertion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showManagementModal<String>(
                    context: context,
                    builder: (_) => const ManagementModalShell(
                      title: 'Inventory action',
                      body: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(title: Text('Sell through Marketplace')),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open modal'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open modal'));
    await tester.pumpAndSettle();

    expect(find.text('Sell through Marketplace'), findsOneWidget);
  });
}
