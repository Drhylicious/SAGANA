import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/temp_password.dart';
import 'package:sagana/presentation/widgets/password_requirements.dart';

/// One password rule for every role (Buyer, Farmer, Manager, Officer) wherever a password is chosen:
/// 8+ characters, an uppercase letter, a number and a special character.
void main() {
  test('accepts a password that has all four parts', () {
    for (final p in ['Abcdef1!', 'Sagana@2026', 'Test@12345', 'Pa55word#', 'Ñandu9Z-x']) {
      expect(isPasswordValid(p), isTrue, reason: p);
    }
  });

  test('refuses a password that is missing any one part', () {
    expect(isPasswordValid('Abc1!'), isFalse, reason: 'too short');
    expect(isPasswordValid('abcdefg1!'), isFalse, reason: 'no uppercase');
    expect(isPasswordValid('Abcdefgh!'), isFalse, reason: 'no number');
    expect(isPasswordValid('Abcdefg12'), isFalse, reason: 'no special character');
    expect(isPasswordValid('Abcd 123'), isFalse, reason: 'a space is not a special character');
    expect(isPasswordValid(''), isFalse);
  });

  test('the generated temporary password for a Manager-created account always meets the rule', () {
    final r = Random(7);
    for (var i = 0; i < 3000; i++) {
      final p = generateAccountPassword(random: i.isEven ? null : r);
      expect(p.length, 10);
      expect(isPasswordValid(p), isTrue, reason: p);
    }
  });

  test('every screen that chooses a password uses the one shared rule', () {
    final files = {
      'lib/presentation/widgets/password_requirements.dart': 'isPasswordValid',
      'lib/presentation/widgets/account_form_widgets.dart': 'isPasswordValid(v)',
      'lib/presentation/widgets/change_password_dialog.dart': 'isPasswordValid(',
      'lib/presentation/screens/auth/register_screen.dart': 'validatePasswordMinLength',
      'lib/presentation/widgets/set_password_form.dart': 'validatePasswordMinLength',
      'lib/presentation/screens/admin/add_new_member_screen.dart': 'generateAccountPassword',
      'lib/presentation/screens/admin/create_officer_account_screen.dart': 'generateAccountPassword',
    };
    files.forEach((path, needle) {
      expect(File(path).readAsStringSync(), contains(needle), reason: path);
    });
  });
}
