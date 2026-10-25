import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app and the database meet at five function calls. A parameter named one
/// way in Dart and another in SQL only fails at runtime ("function not found"),
/// so this reads both sides from disk and compares them.
void main() {
  final sql = File('supabase_schema/supabase_schema_coop_offer_negotiation.sql').readAsStringSync();
  final dart = File('lib/data/repositories/cooperative_offer_repository.dart').readAsStringSync();

  Set<String> sqlParams(String function) {
    final m = RegExp(
      r'CREATE OR REPLACE FUNCTION public\.' + function + r'\(([^)]*)\)',
      dotAll: true,
    ).firstMatch(sql);
    expect(m, isNotNull, reason: '$function is not defined in the migration');
    return RegExp(r'\bp_[a-z_]+').allMatches(m!.group(1)!).map((x) => x.group(0)!).toSet();
  }

  Set<String> dartParams(String function) {
    final m = RegExp(
      r"rpc\(\s*'" + function + r"',\s*params:\s*\{([^}]*)\}",
      dotAll: true,
    ).firstMatch(dart);
    expect(m, isNotNull, reason: '$function is not called from the repository');
    return RegExp(r"'(p_[a-z_]+)'").allMatches(m!.group(1)!).map((x) => x.group(1)!).toSet();
  }

  for (final fn in [
    'offer_batch_to_cooperative',
    'counter_cooperative_offer',
    'accept_cooperative_offer',
    'decline_cooperative_offer',
    'cancel_cooperative_offer',
  ]) {
    test('$fn: Dart sends exactly the parameters the SQL function takes', () {
      expect(dartParams(fn), sqlParams(fn));
    });
  }

  test('the removed settle-at-any-amount function is not called any more', () {
    expect(dart.contains('confirm_cooperative_offer'), isFalse);
  });

  test('the columns the app reads exist in the migration', () {
    final select = RegExp(r"static const String selectColumns =\s*((?:\s*'[^']*'\s*)+);").firstMatch(
      File('lib/data/models/cooperative_offer_model.dart').readAsStringSync(),
    );
    expect(select, isNotNull);
    final cols = RegExp(r"'([^']*)'")
        .allMatches(select!.group(1)!)
        .expand((m) => m.group(1)!.split(','))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty);
    // Columns added by this migration; the rest pre-date it.
    for (final added in ['asking_price_per_kg', 'current_price_per_kg', 'agreed_price_per_kg', 'last_proposed_by', 'negotiation_round']) {
      expect(cols, contains(added));
      expect(sql, contains(added));
    }
  });

  test('notification links point at routes the app registers', () {
    final routes = File('lib/routes/app_routes.dart').readAsStringSync();
    expect(sql, contains("'/farmer/profile/cooperative-offers'"));
    expect(routes, contains("'/farmer/profile/cooperative-offers'"));
    expect(sql, contains("'/admin/marketplace/offer-to-cooperative'"));
    expect(routes, contains("'/admin/marketplace/offer-to-cooperative'"));
  });
}
