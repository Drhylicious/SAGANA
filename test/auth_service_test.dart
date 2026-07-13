import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/services/auth_service.dart';

void main() {
  group('AuthService.toAuthEmail', () {
    test('converts SAGANA usernames into the auth email format', () {
      expect(AuthService.toAuthEmail('SP3-0001'), 'sp3-0001@sagana.local');
      expect(AuthService.toAuthEmail('STF-1001'), 'stf-1001@sagana.local');
    });

    test('keeps real email addresses unchanged', () {
      expect(AuthService.toAuthEmail('admin@sp3.coop'), 'admin@sp3.coop');
    });
  });
}
