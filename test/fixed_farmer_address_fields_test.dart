import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/presentation/widgets/fixed_farmer_address_fields.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('shows the five fixed values, locked, and three editable fields', (
    tester,
  ) async {
    final street = TextEditingController();
    final building = TextEditingController();
    final houseNo = TextEditingController();
    addTearDown(street.dispose);
    addTearDown(building.dispose);
    addTearDown(houseNo.dispose);

    await tester.pumpWidget(
      _host(
        FixedFarmerAddressFields(
          streetController: street,
          buildingController: building,
          houseNoController: houseNo,
        ),
      ),
    );

    // Prefilled the moment the step opens.
    for (final value in [
      'MIMAROPA Region',
      'Marinduque',
      'Torrijos',
      'Payanas',
      '4903',
    ]) {
      expect(find.text(value), findsOneWidget, reason: '$value is prefilled');
    }

    // The five are read-only; the three below them are not.
    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields.length, 8);
    final readOnly = fields.map((f) => f.readOnly).toList();
    expect(readOnly.sublist(0, 5), everyElement(isTrue));
    expect(readOnly.sublist(5), everyElement(isFalse));

    // Typing into a locked field changes nothing.
    await tester.enterText(find.text('Payanas'), 'Elsewhere');
    await tester.pump();
    expect(find.text('Payanas'), findsOneWidget);
    expect(find.text('Elsewhere'), findsNothing);

    // The editable ones take input.
    await tester.enterText(find.byType(TextFormField).at(5), 'Rizal Street');
    await tester.enterText(find.byType(TextFormField).at(7), '12');
    expect(street.text, 'Rizal Street');
    expect(houseNo.text, '12');
  });

  testWidgets('street and house number are required, building is not', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final street = TextEditingController();
    final building = TextEditingController();
    final houseNo = TextEditingController();
    addTearDown(street.dispose);
    addTearDown(building.dispose);
    addTearDown(houseNo.dispose);

    await tester.pumpWidget(
      _host(
        Form(
          key: formKey,
          child: FixedFarmerAddressFields(
            streetController: street,
            buildingController: building,
            houseNoController: houseNo,
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    // Two "required" messages: street and house number. Not building.
    expect(find.text('This field is required.'), findsNWidgets(2));

    street.text = 'Rizal Street';
    houseNo.text = '12';
    expect(formKey.currentState!.validate(), isTrue);
  });
}
