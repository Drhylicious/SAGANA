import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/services/auth_service.dart';
import 'package:sagana/presentation/widgets/username_availability_field.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
);

void main() {
  late TextEditingController controller;
  late List<String> asked;
  late List<(UsernameStatus?, bool)> reported;

  Widget field(Future<UsernameStatus> Function(String) checker) {
    return Form(
      child: UsernameAvailabilityField(
        controller: controller,
        debounce: const Duration(milliseconds: 50),
        checker: checker,
        decorationBuilder: (suffix) => InputDecoration(suffixIcon: suffix),
        onStatusChanged: (s, c) => reported.add((s, c)),
      ),
    );
  }

  setUp(() {
    controller = TextEditingController();
    asked = [];
    reported = [];
  });
  tearDown(() => controller.dispose());

  testWidgets('shows a spinner while checking, then "available"', (tester) async {
    await tester.pumpWidget(
      _host(
        field((u) async {
          asked.add(u);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return UsernameStatus.available;
        }),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Drhylicious');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(asked, isEmpty, reason: 'the check is debounced');

    await tester.pump(const Duration(milliseconds: 60)); // debounce fires
    expect(asked, ['drhylicious'], reason: 'normalized before it is checked');

    await tester.pump(const Duration(milliseconds: 150)); // answer arrives
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Username is available.'), findsOneWidget);
    expect(reported.last, (UsernameStatus.available, false));
  });

  testWidgets('shows "already taken" when the database says so', (tester) async {
    await tester.pumpWidget(_host(field((u) async => UsernameStatus.taken)));

    await tester.enterText(find.byType(TextFormField), 'jdelacruz');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(find.text('This username is already taken.'), findsOneWidget);
    expect(find.text('Username is available.'), findsNothing);
    expect(reported.last, (UsernameStatus.taken, false));
  });

  testWidgets('does not ask the database about an invalid username', (
    tester,
  ) async {
    await tester.pumpWidget(_host(field((u) async {
      asked.add(u);
      return UsernameStatus.available;
    })));

    await tester.enterText(find.byType(TextFormField), 'has space');
    await tester.pump(const Duration(milliseconds: 200));

    expect(asked, isEmpty);
    expect(reported.last, (UsernameStatus.invalid, false));
  });

  testWidgets('a check that cannot run does not block (status: error)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(field((u) async => UsernameStatus.error)));

    await tester.enterText(find.byType(TextFormField), 'validname');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(reported.last, (UsernameStatus.error, false));
    expect(find.text('This username is already taken.'), findsNothing);
  });

  testWidgets('an answer for an old value is discarded', (tester) async {
    await tester.pumpWidget(
      _host(
        field((u) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return u == 'firstname' ? UsernameStatus.taken : UsernameStatus.available;
        }),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'firstname');
    await tester.pump(const Duration(milliseconds: 60)); // first check starts
    await tester.enterText(find.byType(TextFormField), 'secondname');
    await tester.pump(const Duration(milliseconds: 200)); // first answer lands
    await tester.pump(const Duration(milliseconds: 200)); // second answer lands

    expect(find.text('This username is already taken.'), findsNothing);
    expect(reported.last, (UsernameStatus.available, false));
  });
}
