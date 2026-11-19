import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Found by the Chrome text-size test (text at 150% and 200%): fixed-size boxes squeezed their contents.
/// These screens now grow with the phone's text size.
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('Manager Loans: the four number cards get taller with the text size, so the numbers keep their size', () {
    final src = read('lib/presentation/screens/admin/loan_dashboard_screen.dart');
    expect(src, contains('MediaQuery.textScalerOf(context).scale(1.0)'));
    expect(src, contains('childAspectRatio:'));
    expect(src, isNot(contains('childAspectRatio: 1.5,')));
    expect(src, contains('final stacked = MediaQuery.textScalerOf(context).scale(1.0) > 1.2;'));
  });

  test('Buyer My Orders and Manager Loan History: the status chip rows grow with the text size', () {
    expect(read('lib/presentation/screens/buyer/my_orders_screen.dart'),
        contains('34 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0)'));
    expect(read('lib/presentation/screens/admin/loan_history_screen.dart'),
        contains('38 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0)'));
  });

  test('Farmer Listings: the Marketplace / Listing switch keeps each word on one line, and the shared filter bar grows with the text', () {
    final tabs = read('lib/presentation/screens/farmer/my_listings_screen.dart');
    expect(tabs, contains('fit: BoxFit.scaleDown'));
    expect(read('lib/presentation/widgets/listing_filter_modal.dart'),
        contains('34 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0)'));
  });
}
