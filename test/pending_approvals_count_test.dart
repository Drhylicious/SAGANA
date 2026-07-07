import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/screens/admin/pending_approvals_screen.dart';

void main() {
  group('PendingApprovalsScreen view-all label', () {
    test('includes the actual pending count when listings exist', () {
      expect(
        PendingApprovalsScreen.buildViewAllLabel(3),
        'View All 3 Pending Listings',
      );
    });

    test('falls back to a generic label when the pending count is zero', () {
      expect(PendingApprovalsScreen.buildViewAllLabel(0), 'View All Listings');
    });
  });
}
