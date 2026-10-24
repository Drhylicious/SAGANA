import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/widgets/app_toast.dart';

Widget _host(void Function(BuildContext) onOpen) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('AppToast action is reachable while an AlertDialog is open', (tester) async {
    var actionFired = false;

    await tester.pumpWidget(_host((context) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: ElevatedButton(
            onPressed: () => AppToast.show(
              dialogContext,
              'Enter a value between 0 and 50 kg.',
              isError: true,
              actionLabel: 'Undo',
              onAction: () => actionFired = true,
            ),
            child: const Text('Trigger'),
          ),
        ),
      );
    }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trigger'));
    await tester.pump();

    expect(find.text('Enter a value between 0 and 50 kg.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(actionFired, isTrue, reason: 'Toast must sit above the dialog barrier');

    // Drain AppToast's 3-second dismissal timer so the test doesn't leave it pending.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('SnackBar fired from inside an AlertDialog sits behind the dialog barrier (current behaviour)',
      (tester) async {
    var actionFired = false;

    await tester.pumpWidget(_host((context) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(
                content: const Text('Enter a value between 0 and 50 kg.'),
                action: SnackBarAction(label: 'Undo', onPressed: () => actionFired = true),
              ),
            ),
            child: const Text('Trigger'),
          ),
        ),
      );
    }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trigger'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Enter a value between 0 and 50 kg.'), findsOneWidget);

    // The tap should be absorbed by the dialog barrier, so the SnackBar action never fires.
    await tester.tap(find.text('Undo'), warnIfMissed: false);
    await tester.pump();
    expect(actionFired, isFalse, reason: 'SnackBar is behind the dialog barrier');
  });
}
