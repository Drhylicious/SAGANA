import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/data/models/cart_item_model.dart';
import 'package:sagana/presentation/widgets/quantity_stepper.dart';

import 'support/ignore_font_errors.dart';

String _read(String path) => File(path).readAsStringSync();

/// Hosts a stepper that, like a real screen, keeps the value it reports.
class _Host extends StatefulWidget {
  final double initial;
  final double max;
  final bool compact;
  final bool enabled;
  final bool Function()? allowChange;
  final VoidCallback? onBlocked;
  final List<double> reported;

  const _Host({
    required this.reported,
    this.initial = 10,
    this.max = 50,
    this.compact = false,
    this.enabled = true,
    this.allowChange,
    this.onBlocked,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late double value = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QuantityStepper(
              value: value,
              max: widget.max,
              compact: widget.compact,
              enabled: widget.enabled,
              allowChange: widget.allowChange,
              onBlocked: widget.onBlocked,
              onChanged: (v) {
                widget.reported.add(v);
                setState(() => value = v);
              },
            ),
            Text('value=$value', key: const Key('shown')),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Finder field() => find.byType(TextField);
  String text(WidgetTester t) => t.widget<TextField>(field()).controller!.text;

  group('QuantityStepper', () {
    testWidgets(
      'the number can be typed directly: 10 -> 5 without pressing -',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final reported = <double>[];
          await tester.pumpWidget(_Host(reported: reported));
          await tester.enterText(field(), '5');
          await tester.pump();
          expect(reported.last, 5);
          expect(find.text('value=5.0'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'the owner has the typed value at once (no wait for focus loss)',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final reported = <double>[];
          await tester.pumpWidget(_Host(reported: reported));
          await tester.enterText(field(), '3.5');
          await tester.pump();
          expect(reported.last, 3.5);
        });
      },
    );

    testWidgets('- and + still adjust by one and show the new number', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(_Host(reported: reported));
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
        expect(reported.last, 9);
        expect(text(tester), '9');
        await tester.tap(find.byIcon(Icons.add));
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(reported.last, 11);
        expect(text(tester), '11');
      });
    });

    testWidgets('typing after pressing a button keeps working', (tester) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(_Host(reported: reported));
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
        await tester.enterText(field(), '2');
        await tester.pump();
        expect(reported.last, 2);
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(reported.last, 3);
      });
    });

    testWidgets('never goes above the stock left, typed or stepped', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(
          _Host(reported: reported, initial: 49, max: 50),
        );
        await tester.tap(find.byIcon(Icons.add));
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(reported.last, 50);
        // Typing past the stock is refused outright: the field keeps 50.
        await tester.enterText(field(), '500');
        await tester.pump();
        expect(text(tester), isNot('500'));
        expect(reported.every((v) => v <= 50), isTrue);
      });
    });

    testWidgets('never goes below 0.01 and accepts 2 decimals, not 3', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(_Host(reported: reported, initial: 1));
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
        expect(reported.last, 0.01);
        await tester.enterText(field(), '0.255');
        await tester.pump();
        expect(text(tester), isNot('0.255'));
      });
    });

    testWidgets('a value below 1 is allowed (0.5 of a unit)', (tester) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(_Host(reported: reported));
        await tester.enterText(field(), '0.5');
        await tester.pump();
        expect(reported.last, 0.5);
      });
    });

    testWidgets(
      'a half-typed value is not reported; leaving the field restores the last good number',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final reported = <double>[];
          await tester.pumpWidget(_Host(reported: reported));
          await tester.tap(field());
          await tester.enterText(field(), '');
          await tester.pump();
          await tester.enterText(field(), '0');
          await tester.pump();
          expect(reported, isEmpty); // nothing half-typed leaked out
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          expect(text(tester), '10');
          expect(find.text('value=10.0'), findsOneWidget);
        });
      },
    );

    testWidgets('leaving the field tidies the text ("5." becomes "5")', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(_Host(reported: reported));
        await tester.tap(field());
        await tester.enterText(field(), '5.');
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(text(tester), '5');
      });
    });

    testWidgets(
      'a refused change (offline) puts the old number back and says why',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final reported = <double>[];
          var blocked = 0;
          await tester.pumpWidget(
            _Host(
              reported: reported,
              allowChange: () => false,
              onBlocked: () => blocked++,
            ),
          );
          await tester.tap(find.byIcon(Icons.add));
          await tester.pump();
          expect(reported, isEmpty);
          expect(text(tester), '10');
          expect(blocked, 1);
          await tester.enterText(field(), '4');
          await tester.pump();
          expect(reported, isEmpty);
          expect(text(tester), '10');
          expect(blocked, 2);
        });
      },
    );

    testWidgets(
      'disabled (a line that cannot be bought): buttons and typing do nothing',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final reported = <double>[];
          await tester.pumpWidget(_Host(reported: reported, enabled: false));
          await tester.tap(find.byIcon(Icons.add));
          await tester.pump();
          expect(reported, isEmpty);
          expect(tester.widget<TextField>(field()).enabled, isFalse);
        });
      },
    );

    testWidgets(
      'the owner can change the number (stock dropped) and it shows',
      (tester) async {
        await runIgnoringFontErrors(() async {
          double value = 10;
          late StateSetter set;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    set = setState;
                    return QuantityStepper(
                      value: value,
                      max: 50,
                      onChanged: (_) {},
                    );
                  },
                ),
              ),
            ),
          );
          set(() => value = 4);
          await tester.pump();
          expect(text(tester), '4');
        });
      },
    );

    for (final compact in [false, true]) {
      testWidgets('fits a narrow row (${compact ? 'cart' : 'Buy Now'} size)', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          tester.view.physicalSize = const Size(320, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _Host(
              reported: const [],
              compact: compact,
              initial: 12345.5,
              max: 99999,
            ),
          );
          expect(tester.takeException(), isNull);
        });
      });
    }
  });

  group('Units: a line keeps its own unit through the cart', () {
    test('the cart line stores and restores the unit', () {
      final item = CartItemModel(
        listingId: 'l1',
        cropName: 'Peanut Cookies',
        pricePerKg: 50,
        unit: 'sack',
        availableKgSnapshot: 90,
        quantityKg: 5,
      );
      final back = CartItemModel.fromMap(item.toMap());
      expect(back.unit, 'sack');
      expect(back.quantityKg, 5);
      // A line saved before units existed is kg.
      final old = item.toMap()..remove('unit');
      expect(CartItemModel.fromMap(old).unit, 'kg');
    });
  });

  group('Buy Now sheet and Cart (source guards)', () {
    // Windows line endings and the formatter's line breaks must not matter.
    String norm(String s) => s.replaceAll('\r\n', '\n');
    String flat(String s) => norm(s).replaceAll(RegExp(r'\s+'), '');
    // The sheet is shared by a Marketplace listing and a Cooperative Product.
    final details = norm(
      _read('lib/presentation/widgets/product_buy_now_sheet.dart'),
    );
    final cart = norm(_read('lib/presentation/screens/buyer/cart_screen.dart'));

    test(
      'Buy Now uses the editable stepper, shows the product unit, and settles typing before checkout',
      () {
        expect(details, contains('QuantityStepper('));
        expect(
          flat(details).replaceAll(',', ''),
          contains('buyerListingOrderQty(unit)'),
        );
        expect(details, contains('primaryFocus?.unfocus()'));
      },
    );

    test('the Buy Now sheet is lifted by the keyboard and can scroll', () {
      expect(details, contains('viewInsetsOf(context).bottom'));
      expect(details, contains('SingleChildScrollView'));
    });

    test(
      'Cart: a quantity change updates that line only (no reload, no skeleton)',
      () {
        final start = cart.indexOf('void _setQuantity(');
        expect(start, greaterThan(0));
        final body = cart.substring(start, cart.indexOf('\n  }\n', start));
        expect(body.contains('_load('), isFalse);
        expect(body.contains('_isLoading'), isFalse);
        expect(body, contains('updateQuantity'));
      },
    );

    test(
      'Cart: only the first load shows the skeleton; reloads after a change are silent',
      () {
        expect(cart, contains('Future<void> _load({bool silent = false})'));
        expect(
          cart,
          contains('if (!silent) setState(() => _isLoading = true);'),
        );
        // Every reload that follows a change is silent.
        expect(
          RegExp(r'\n\s+_load\(\);').allMatches(cart).length,
          1,
        ); // initState only
      },
    );

    test(
      'Cart: the quantity is the editable stepper with the line\'s own unit, kept offline-safe',
      () {
        expect(cart, contains('QuantityStepper('));
        expect(cart, contains('unitOrDefault(item.unit)'));
        expect(cart, contains('allowChange: allowQuantityChange'));
        expect(cart, contains('ConnectivityService.instance.isOnline'));
      },
    );

    test(
      'Cart: a removed line leaves the list at once (a swiped line cannot stay in the tree)',
      () {
        final start = cart.indexOf('Future<void> _removeItem(');
        final body = cart.substring(start, cart.indexOf('\n  }\n', start));
        expect(
          body.indexOf('_items.removeWhere'),
          lessThan(body.indexOf('removeItem(item.listingId)')),
        );
      },
    );
  });
}
