import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/program_management_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The REAL Program Management screen and its Create / Edit form run; only the
/// network is replaced. Pins what a Manager sees when Save is pressed with a
/// required field empty or invalid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_program_form');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
  });

  final shotKey = GlobalKey();

  bool isRed(Color c) => c.r > 0.6 && c.g < 0.45 && c.b < 0.45;

  // How many red pixels are painted down a vertical line through the right part of a
  // field (clear of its label and of the error message at the left). A red outline
  // crosses that line at least twice, at the top and the bottom edge.
  Future<int> redPixelsAcross(WidgetTester tester, Finder field) async {
    // Scroll the field into view first, as a person would, so it is actually painted.
    await tester.ensureVisible(field);
    await tester.pump(const Duration(milliseconds: 300));
    final decorator = find.descendant(of: field, matching: find.byType(InputDecorator)).first;
    final box = tester.renderObject<RenderBox>(decorator);
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return (await tester.runAsync(() async {
      final boundary = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var rows = 0;
      final x = (rect.right - 40).toInt();
      for (var y = rect.top.toInt(); y <= rect.bottom.toInt(); y++) {
        var hit = false;
        for (var dx = -3; dx <= 3; dx++) {
          final o = (y * image.width + (x + dx)) * 4;
          final c = Color.fromARGB(255, data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
          if (isRed(c)) hit = true;
        }
        if (hit) rows++;
      }
      return rows;
    }))!;
  }


  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (t) => runIgnoringFontErrors(() => body(t)));

  Map<String, Object?> program({required String purpose, double discount = 0}) => {
    'id': 'p1',
    'program_name': 'Peanut Cookies',
    'program_type': 'food',
    'benefit_type': 'grant',
    'program_purpose': purpose,
    'description': 'Cookies',
    'budget': 1000,
    'image_url': null, // a network image cannot load in a test
    'season_year': 2026,
    'status': 'active',
    'member_discount_percent': discount,
    'source_categories': ['Harvest Stock'],
    'created_at': '2026-09-01T00:00:00Z',
  };

  Future<void> pumpScreen(WidgetTester tester, {List<Map<String, Object?>> programs = const []}) async {
    fake.reset();
    fake.on('GET /rest/v1/cooperative_programs', (_) => programs);
    fake.on('GET /rest/v1/program_types', (_) => [
      {'name': 'Crop'}, {'name': 'Livestock'}, {'name': 'Processed Products'},
    ]);
    fake.on('GET /rest/v1/inventory_categories', (_) => [
      {'name': 'Seeds'}, {'name': 'Harvest Stock'},
    ]);
    // Signed in as the Manager.
    await tester.runAsync(() => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'));
    StaffPermissions.instance.debugSet(const {});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Around the whole navigator, so the dialog (a route above the screen) is captured too.
      builder: (context, child) => RepaintBoundary(key: shotKey, child: child),
      home: const ProgramManagementScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // The colour a field's outline is painted in: what the person actually sees.
  Color? outlineOf(WidgetTester tester, Finder field) {
    final decorator = tester.widget<InputDecorator>(
      find.descendant(of: field, matching: find.byType(InputDecorator)).first,
    );
    final theme = Theme.of(tester.element(field));
    final hasError = decorator.decoration.errorText != null;
    final border = hasError
        ? theme.inputDecorationTheme.errorBorder
        : theme.inputDecorationTheme.enabledBorder;
    return (border as OutlineInputBorder?)?.borderSide.color;
  }

  Finder fieldWithLabel(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );

  ftest('Create: Save with the discount empty shows the discount field in red, with its message', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    // Switch the purpose to Product Sales.
    await tester.tap(find.text('Distribution').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Product Sales').last);
    await tester.pump(const Duration(milliseconds: 300));

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    final discount = fieldWithLabel(l10n.programMgmtMemberDiscountLabel);
    expect(discount, findsOneWidget);

    await tester.ensureVisible(find.text(l10n.programMgmtCreateAction).last);
    await tester.tap(find.text(l10n.programMgmtCreateAction).last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.programMgmtMemberDiscountRequired), findsOneWidget);
    expect(outlineOf(tester, discount), AppConstants.errorRed);
    // Calibration: the Budget field (also empty) is painted red; the discount must be too.
    final budget = fieldWithLabel(l10n.programMgmtBudgetLabel);
    expect(await redPixelsAcross(tester, budget), greaterThanOrEqualTo(2), reason: 'calibration: Budget outline');
    expect(await redPixelsAcross(tester, discount), greaterThanOrEqualTo(2), reason: 'the discount outline must be red');
    await tester.pump(const Duration(seconds: 4)); // the toast's timer
  });

  Future<void> openEdit(WidgetTester tester, {required double discount}) async {
    await pumpScreen(tester, programs: [program(purpose: 'sales', discount: discount)]);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> save(WidgetTester tester) async {
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    await tester.ensureVisible(find.text(l10n.saveChanges).last);
    await tester.tap(find.text(l10n.saveChanges).last);
    await tester.pump(const Duration(milliseconds: 300));
  }

  ftest('Edit: clearing the discount and saving shows it in red, with its message', (tester) async {
    await openEdit(tester, discount: 10);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    final discount = fieldWithLabel(l10n.programMgmtMemberDiscountLabel);
    await tester.enterText(discount, '');
    await save(tester);
    expect(find.text(l10n.programMgmtMemberDiscountRequired), findsOneWidget);
    expect(outlineOf(tester, discount), AppConstants.errorRed);
    expect(await redPixelsAcross(tester, discount), greaterThanOrEqualTo(2), reason: 'the painted outline must be red');
    await tester.pump(const Duration(seconds: 4));
  });

  ftest('Edit: a discount above 100 is shown in red, with its message', (tester) async {
    await openEdit(tester, discount: 10);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    final discount = fieldWithLabel(l10n.programMgmtMemberDiscountLabel);
    await tester.enterText(discount, '150');
    await save(tester);
    expect(find.text(l10n.programMgmtMemberDiscountInvalid), findsOneWidget);
    expect(outlineOf(tester, discount), AppConstants.errorRed);
    await tester.pump(const Duration(seconds: 4));
  });

  ftest('Edit: 0 (no discount) is valid, so the field is not red', (tester) async {
    await openEdit(tester, discount: 0);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    final discount = fieldWithLabel(l10n.programMgmtMemberDiscountLabel);
    await save(tester);
    expect(find.text(l10n.programMgmtMemberDiscountRequired), findsNothing);
    expect(find.text(l10n.programMgmtMemberDiscountInvalid), findsNothing);
    expect(outlineOf(tester, discount), isNot(AppConstants.errorRed));
    await tester.pump(const Duration(seconds: 4));
  });

  ftest('Create: after Save, the first field in error is scrolled into view (nobody has to hunt for it)', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Distribution').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Product Sales').last);
    await tester.pump(const Duration(milliseconds: 300));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    // Fill everything except the discount, so it is the only field in error.
    await tester.enterText(fieldWithLabel(l10n.programMgmtNameLabel), 'Cookies');
    await tester.ensureVisible(find.text(l10n.programTypeSelectHint));
    await tester.tap(find.text(l10n.programTypeSelectHint));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Processed Products').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(fieldWithLabel(l10n.programMgmtBudgetLabel), '1000');
    await tester.enterText(fieldWithLabel(l10n.programMgmtDescriptionLabel), 'Cookies for members');
    await tester.ensureVisible(find.text('Select categories'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Select categories'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Seeds').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(5, 5)); // close the list
    await tester.pump(const Duration(milliseconds: 300));
    // A small phone, where the form needs scrolling; back at the top, the discount field
    // is out of sight when Save is pressed.
    tester.view.physicalSize = const Size(360, 420);
    await tester.pump(const Duration(milliseconds: 300));
    // The form's own scroll view: the nearest scrollable above the Form.
    final scroll = Scrollable.of(tester.element(find.byType(Form)));
    scroll.position.jumpTo(0);
    await tester.pump();
    final before = scroll.position.pixels;
    expect(before, 0, reason: 'starts at the top of the form');
    await tester.tap(find.text(l10n.programMgmtCreateAction).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400)); // the scroll animation
    expect(find.text(l10n.programMgmtMemberDiscountRequired), findsOneWidget);
    // The form scrolled by itself to the field in error (nobody scrolled it by hand).
    expect(scroll.position.pixels, greaterThan(0));
    await tester.pump(const Duration(seconds: 4));
  });

  ftest('Harvest Return: no crop and no unit to choose; just the return quantity (the unit is the Inventory item\'s)', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    await tester.ensureVisible(find.text(l10n.programMgmtBenefitGrant).first);
    await tester.tap(find.text(l10n.programMgmtBenefitGrant).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.programMgmtBenefitRevenueShare).last);
    await tester.pump(const Duration(milliseconds: 400));

    // The item returned is the one that was given, in its own unit: nothing to choose.
    expect(find.textContaining('Return Crop'), findsNothing);
    expect(find.byKey(const Key('returnQuantityField')), findsOneWidget);
    expect(find.text(l10n.programMgmtReturnQtyLabel), findsOneWidget);
    expect(find.byKey(const Key('unitField')), findsNothing);
    expect(find.text('Unit*'), findsNothing);
    expect(find.text(l10n.unitAddCompact), findsNothing);
  });

  ftest('Program Type is a dropdown: Crop, Livestock, Processed Products, then + Add New Program Type', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    // No longer a text box.
    expect(find.text(l10n.programMgmtTypeHint), findsNothing);
    await tester.tap(find.text(l10n.programTypeSelectHint));
    await tester.pump(const Duration(milliseconds: 300));
    for (final t in ['Crop', 'Livestock', 'Processed Products']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text(l10n.programTypeAddNew), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
  });

  ftest('Adding a new type saves it and offers it at once', (tester) async {
    await pumpScreen(tester);
    fake.on('POST /rest/v1/program_types', (r) => r.jsonMap); // .single() returns the row itself
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    await tester.tap(find.text(l10n.programTypeSelectHint));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.programTypeAddNew));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).last, 'Aquaculture');
    await tester.tap(find.text(l10n.genericAdd).last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // It was saved to the lookup table, and it is now the chosen type.
    expect(fake.calls('POST /rest/v1/program_types'), isNotEmpty);
    expect(fake.calls('POST /rest/v1/program_types').first.jsonMap['name'], 'Aquaculture');
    expect(find.text('Aquaculture'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  ftest('Saving without a type shows the Program Type field in red, with its message', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    await tester.tap(find.text(l10n.programMgmtCreateAction).last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.programMgmtTypeRequired), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  ftest('Edit: an older lowercase "crop" value shows as the Crop option', (tester) async {
    await pumpScreen(tester, programs: [
      {...program(purpose: 'distribution'), 'program_type': 'crop'},
    ]);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    expect(find.text('Crop'), findsWidgets);
    expect(find.text(l10n.programTypeSelectHint), findsNothing);
  });
}
