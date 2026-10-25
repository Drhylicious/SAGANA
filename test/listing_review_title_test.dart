import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));

  test('the title is "<crop> Review" for any crop', () {
    expect(en.listingReviewCropTitle('Peanut'), 'Peanut Review');
    expect(en.listingReviewCropTitle('Potato'), 'Potato Review');
    expect(en.listingReviewCropTitle('Palay'), 'Palay Review');
    // A crop nobody has thought of yet works the same way.
    expect(en.listingReviewCropTitle('Dragon Fruit'), 'Dragon Fruit Review');
  });

  test('Tagalog has its own wording and still names the crop', () {
    final t = tl.listingReviewCropTitle('Peanut');
    expect(t, contains('Peanut'));
    expect(t, isNot('Peanut Review'));
  });

  test('the screen takes the crop from the listing, not from a hardcoded list', () {
    final src = File('lib/presentation/screens/admin/listing_review_screen.dart').readAsStringSync();
    expect(src, contains('listingReviewCropTitle('));
    expect(src, contains('listing.canonicalCropName ?? listing.cropName'));
    // The generic title is no longer used for the top bar.
    expect(src.contains('l10n.listingReviewTitle'), isFalse);
    for (final crop in ['Peanut', 'Potato', 'Palay', 'Ginger']) {
      expect(src.contains("'$crop'"), isFalse, reason: 'crop name "$crop" is hardcoded');
    }
  });
}
