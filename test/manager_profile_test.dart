import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_profile_model.dart';

/// Manager / Officer profile card: Email Address, then Phone Number, straight
/// from the account (nothing fixed in the app), and no department line.

AdminProfileModel _p({String email = 'mgr@sagana.local', String? contact, String? phone}) =>
    AdminProfileModel(
      userId: 'u1',
      email: email,
      fullName: 'Rosa M. Dela Cruz',
      contactEmail: contact,
      phoneNumber: phone,
    );

void main() {
  group('displayEmail comes from the account', () {
    test('the contact email on the profile wins', () {
      expect(_p(contact: ' rosa@coop.ph ', email: 'x@gmail.com').displayEmail, 'rosa@coop.ph');
    });
    test('without one, a real sign-in email is shown', () {
      expect(_p(email: 'manager@gmail.com').displayEmail, 'manager@gmail.com');
    });
    test('a generated sign-in address is never shown as an email', () {
      expect(_p(email: 'OFF-0001@sagana.local').displayEmail, isNull);
      expect(_p(email: 'mgr@sagana.local', contact: '  ').displayEmail, isNull);
    });
    test('another account gets its own values: nothing is fixed to one person', () {
      final a = _p(contact: 'a@one.ph', phone: '09170000001');
      final b = _p(contact: 'b@two.ph', phone: '09170000002');
      expect(a.displayEmail, 'a@one.ph');
      expect(b.displayEmail, 'b@two.ph');
      expect(a.phoneNumber, isNot(b.phoneNumber));
    });
    test('copyWith keeps the contact email', () {
      expect(_p(contact: 'rosa@coop.ph').copyWith(phoneNumber: '0917').displayEmail, 'rosa@coop.ph');
    });
  });

  group('Manager profile screen', () {
    final src = File('lib/presentation/screens/admin/admin_profile_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final hero = src.substring(src.indexOf('Widget _buildHeroCard'), src.indexOf('Widget _heroRow'));

    test('Email Address, then Phone Number directly below, then Manager Since', () {
      final email = hero.indexOf('l10n.emailAddress');
      final phone = hero.indexOf('l10n.adminProfilePhoneNumber');
      final since = hero.indexOf('l10n.adminProfileAdminSince');
      expect(email, isNonNegative);
      expect(email, lessThan(phone));
      expect(phone, lessThan(since));
      expect(hero, contains('profile.displayEmail'));
      expect(hero, contains('profile.phoneNumber'));
    });

    test('no department subtitle under the role badge', () {
      expect(src, isNot(contains('profile.department')));
    });

    test('the role, email and phone are read from the profile, not written in the app', () {
      expect(hero, isNot(contains('@gmail.com')));
      expect(hero, isNot(contains('09')));
      expect(hero, contains('profile.position'));
    });
  });

  test('the repository reads the contact email and phone from user_information', () {
    final repo = File('lib/data/repositories/admin_profile_repository.dart').readAsStringSync();
    expect(repo, contains("contactEmail: infoRow['contact_email'] as String?"));
    expect(repo, contains("phoneNumber: infoRow['phone_number'] as String?"));
  });
}
