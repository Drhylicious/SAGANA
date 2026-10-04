import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_loan_model.dart';

void main() {
  group('Admin loan standing (amount known)', () {
    test('below the minimum: not eligible, amount is shown', () {
      const s = FarmerLoanStanding(
        outstandingBalance: 0,
        hasOverdueLoan: false,
        capitalContribution: 1000,
        minimumCapitalRequired: 2000,
      );
      expect(s.meetsCapitalEligibility, isFalse);
      expect(s.showsCapitalAmount, isTrue);
    });

    test('at or above the minimum: eligible', () {
      const s = FarmerLoanStanding(
        outstandingBalance: 0,
        hasOverdueLoan: false,
        capitalContribution: 2000,
        minimumCapitalRequired: 2000,
      );
      expect(s.meetsCapitalEligibility, isTrue);
    });
  });

  group('Officer loan standing (amount hidden)', () {
    test('not eligible from the database check: amount is not shown', () {
      const s = FarmerLoanStanding(
        outstandingBalance: 0,
        hasOverdueLoan: false,
        minimumCapitalRequired: 2000,
        capitalEligibleOverride: false,
      );
      expect(s.meetsCapitalEligibility, isFalse);
      expect(s.showsCapitalAmount, isFalse);
      expect(s.capitalContribution, 0);
    });

    test('eligible from the database check: allowed to issue', () {
      const s = FarmerLoanStanding(
        outstandingBalance: 0,
        hasOverdueLoan: false,
        minimumCapitalRequired: 2000,
        capitalEligibleOverride: true,
      );
      expect(s.meetsCapitalEligibility, isTrue);
      expect(s.showsCapitalAmount, isFalse);
    });
  });
}
