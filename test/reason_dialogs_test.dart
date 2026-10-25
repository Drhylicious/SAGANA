import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';
import 'package:sagana/presentation/widgets/reason_dialogs.dart';

import 'support/ignore_font_errors.dart';

/// The two Disapprove steps (reason, then summary), in the standard management
/// modal: Cancel and the main action on one row, the main action off until a
/// reason is typed.

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? reason = 'unset';
  bool? confirmed;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () async {
            final r = await promptReason(
              context: context,
              title: 'Disapprove Ellen Angela Rosal',
              hint: 'Reason for disapproval',
              actionLabel: 'Next',
            );
            setState(() => reason = r);
          },
          child: const Text('open reason'),
        ),
        TextButton(
          onPressed: () async {
            final c = await confirmSummary(
              context: context,
              title: 'Confirm disapproval',
              lines: const ['Applicant: Ellen Angela Rosal', 'Reason: test again'],
              actionLabel: 'Disapprove Application',
              danger: true,
            );
            setState(() => confirmed = c);
          },
          child: const Text('open summary'),
        ),
      ],
    ),
  );
}

Future<_HostState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const _Host(),
    ),
  );
  return tester.state<_HostState>(find.byType(_Host));
}

Finder _next() => find.widgetWithText(ElevatedButton, 'Next');
Finder _cancel() => find.widgetWithText(OutlinedButton, 'Cancel');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Disapprove — step 1, the reason', () {
    testWidgets('Cancel and Next sit on one row, Cancel on the left, balanced', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester);
        await tester.tap(find.text('open reason'));
        await tester.pumpAndSettle();

        expect(find.text('Disapprove Ellen Angela Rosal'), findsOneWidget);
        final cancel = tester.getRect(_cancel());
        final next = tester.getRect(_next());
        // The reported flaw: Cancel sat on its own line far below. Now both are
        // on the same line, the same height, Cancel first.
        expect((cancel.center.dy - next.center.dy).abs(), lessThan(1));
        expect((cancel.height - next.height).abs(), lessThan(1));
        expect(cancel.right, lessThan(next.left));
        // The main action gets the larger share, as in the Suspend flow.
        expect(next.width, greaterThan(cancel.width));
        // Neither button runs past the card.
        final card = tester.getRect(find.byType(ManagementModalShell).first);
        expect(next.right, lessThanOrEqualTo(card.right));
        expect(cancel.left, greaterThanOrEqualTo(card.left));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Next stays off until a reason is typed; blank spaces do not count', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester);
        await tester.tap(find.text('open reason'));
        await tester.pumpAndSettle();
        expect(tester.widget<ElevatedButton>(_next()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), '    ');
        await tester.pump();
        expect(tester.widget<ElevatedButton>(_next()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'test again');
        await tester.pump();
        expect(tester.widget<ElevatedButton>(_next()).onPressed, isNotNull);
      });
    });

    testWidgets('Next returns the trimmed reason', (tester) async {
      await runIgnoringFontErrors(() async {
        final host = await _pump(tester);
        await tester.tap(find.text('open reason'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  test again  ');
        await tester.pump();
        await tester.tap(_next());
        await tester.pumpAndSettle();
        expect(host.reason, 'test again');
      });
    });

    testWidgets('Cancel and the close button return nothing', (tester) async {
      await runIgnoringFontErrors(() async {
        final host = await _pump(tester);
        await tester.tap(find.text('open reason'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'something');
        await tester.pump();
        await tester.tap(_cancel());
        await tester.pumpAndSettle();
        expect(host.reason, isNull);

        await tester.tap(find.text('open reason'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(host.reason, isNull);
      });
    });

    testWidgets('the keyboard does not push the buttons off screen', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.tap(find.text('open reason'));
        await tester.pumpAndSettle();
        expect(tester.getRect(_next()).bottom, lessThanOrEqualTo(740 - 300));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('Disapprove — step 2, the summary', () {
    testWidgets('Back and the red Disapprove Application share one row', (tester) async {
      await runIgnoringFontErrors(() async {
        final host = await _pump(tester);
        await tester.tap(find.text('open summary'));
        await tester.pumpAndSettle();

        final back = find.widgetWithText(OutlinedButton, 'Back');
        final action = find.widgetWithText(ElevatedButton, 'Disapprove Application');
        expect(
          (tester.getRect(back).center.dy - tester.getRect(action).center.dy).abs(),
          lessThan(1),
        );
        expect(tester.getRect(back).right, lessThan(tester.getRect(action).left));
        final style = tester.widget<ElevatedButton>(action).style!;
        expect(style.backgroundColor!.resolve({}), AppConstants.errorRed);
        expect(find.text('Reason: test again'), findsOneWidget);

        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(host.confirmed, isFalse);

        await tester.tap(find.text('open summary'));
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(host.confirmed, isTrue);
      });
    });
  });
}
