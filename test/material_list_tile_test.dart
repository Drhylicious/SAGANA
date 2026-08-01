import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/widgets/material_list_tile.dart';

void main() {
  testWidgets('renders a ListTile inside a decorated container without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.white),
            child: MaterialListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Text('F')),
              title: const Text('Farmer Name'),
              subtitle: const Text('SP3-001'),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ListTile), findsOneWidget);
  });
}
