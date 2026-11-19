import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The sign-in lockout (security script 03) refuses the account for 15 minutes after 10 wrong
/// passwords. The login screen must show the friendly "too many attempts" text, not a raw error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the lockout refusal is shown as the friendly too-many-attempts text', () {
    final e = AuthException('Too many failed sign-in attempts. Please wait 15 minutes and try again.');
    final text = AuthService.parseAuthError(e);
    final en = lookupAppLocalizations(const Locale('en'));
    expect(text, en.dlAuthTooMany);
  });

  test('a wrong password is still the plain "incorrect" text', () {
    final text = AuthService.parseAuthError(AuthException('Invalid login credentials'));
    expect(text, lookupAppLocalizations(const Locale('en')).dlAuthIncorrect);
  });

  test('the lockout script keeps its limits: 10 failures, 15 minutes, hook granted only to the auth service', () {
    final sql = File('supabase_schema/supabase_schema_security_03_signin_lockout.sql').readAsStringSync();
    expect(sql, contains('v_limit   constant int := 10'));
    expect(sql, contains("interval '15 minutes'"));
    expect(sql, contains('TO supabase_auth_admin'));
    expect(sql, contains('FROM PUBLIC, anon, authenticated'));
  });
}
