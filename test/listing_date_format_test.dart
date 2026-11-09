import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/app_utils.dart';
import 'package:sagana/data/repositories/admin_listing_repository.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

AdminListingModel _listing(DateTime createdAt) => AdminListingModel.fromMap({
  'id': 'l1',
  'farmer_id': 'f1',
  'crop_name': 'Peanut',
  'volume_kg': 15,
  'price_per_kg': 20,
  'created_at': createdAt.toUtc().toIso8601String(),
});

void main() {
  group('listing dates always carry the year', () {
    test('one format: "Oct 28, 2026"', () {
      expect(
        AppUtils.formatListingDate(DateTime(2026, 10, 28, 12)),
        'Oct 28, 2026',
      );
      expect(
        AppUtils.formatListingDate(DateTime(2026, 1, 5, 12)),
        'Jan 5, 2026',
      );
      expect(
        AppUtils.formatListingDate(DateTime(2025, 12, 31, 12)),
        'Dec 31, 2025',
      );
    });

    test(
      'the staff listing label (All Listings, Pending Approval, Review) has the year once it is a date',
      () {
        final old = DateTime.now().subtract(const Duration(days: 40));
        final label = _listing(old).submittedLabel;
        expect(label, AppUtils.formatListingDate(old));
        expect(label, contains('${old.toLocal().year}'));
        expect(
          RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}$').hasMatch(label),
          isTrue,
          reason: label,
        );
      },
    );

    test(
      'a listing from the last two days still reads "ago" / "Yesterday"',
      () {
        expect(
          _listing(
            DateTime.now().subtract(const Duration(minutes: 5)),
          ).submittedLabel,
          endsWith('m ago'),
        );
        expect(
          _listing(
            DateTime.now().subtract(const Duration(hours: 3)),
          ).submittedLabel,
          endsWith('h ago'),
        );
        expect(
          _listing(
            DateTime.now().subtract(const Duration(hours: 30)),
          ).submittedLabel,
          'Yesterday',
        );
      },
    );

    test(
      'no listing screen builds its own month-day-only or numeric date any more',
      () {
        final repo = _read(
          'lib/data/repositories/admin_listing_repository.dart',
        );
        expect(repo.contains("m[createdAt.month - 1]"), isFalse);
        final detail = _read(
          'lib/presentation/screens/farmer/farmer_listing_detail_screen.dart',
        );
        expect(detail.contains('.month}/'), isFalse); // the old 11/7/2026
        expect(
          detail,
          contains('AppUtils.formatListingDate(listing.submittedAt!)'),
        );
        final mine = _read(
          'lib/presentation/screens/farmer/my_listings_screen.dart',
        );
        expect(mine.contains("DateFormat('MMM d, yyyy')"), isFalse);
        expect(mine, contains('AppUtils.formatListingDate(listing.createdAt)'));
        for (final f in [
          'lib/presentation/screens/buyer/my_orders_screen.dart',
          'lib/presentation/screens/farmer/farmer_orders_screen.dart',
        ]) {
          expect(
            _read(f).contains("'\${m[d.month - 1]} \${d.day}'"),
            isFalse,
            reason: f,
          );
          expect(
            _read(f),
            contains('AppUtils.formatListingDate(d)'),
            reason: f,
          );
        }
      },
    );
  });
}
