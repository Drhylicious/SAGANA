import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DropdownButtonFormField fits within a narrow container', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                value: 'farmer-id',
                isExpanded: true,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(
                    value: 'farmer-id',
                    child: Text(
                      'A very very very very long farmer name that should fit without overflowing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
