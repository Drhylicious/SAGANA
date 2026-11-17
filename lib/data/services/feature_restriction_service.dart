import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_restriction.dart';
import '../repositories/member_restriction_repository.dart';
import 'hive_service.dart';

/// The signed-in Farmer's current feature restrictions.
///
/// This only drives what the screens SHOW (a locked button and its reason). The
/// real stop is in the database: every "start something new" function refuses a
/// restricted farmer with the readable reason, so a stale or empty list here
/// never lets anything through.
class FeatureRestrictionService extends ChangeNotifier {
  FeatureRestrictionService._();
  static final FeatureRestrictionService instance =
      FeatureRestrictionService._();

  final MemberRestrictionRepository _repo = MemberRestrictionRepository();
  List<MyRestriction> _mine = const [];

  /// The restrictions in force, newest first.
  List<MyRestriction> get restrictions =>
      List.unmodifiable(_mine.where((r) => r.inForce));

  /// The restriction in force on [feature], if any.
  MyRestriction? of(RestrictableFeature feature) {
    for (final r in _mine) {
      if (r.feature == feature && r.inForce) return r;
    }
    return null;
  }

  /// Reads the list from the server. Anyone who is not a Farmer has none, so
  /// no request is made for them. A failed read (offline) keeps what was there.
  Future<void> refresh() async {
    if (HiveService.getUserRole() != 'farmer') {
      if (_mine.isNotEmpty) {
        _mine = const [];
        notifyListeners();
      }
      return;
    }
    // Offline this answers at once from the saved copy (OfflineReadClient), so
    // a restart without a connection still shows the Farmer's restrictions.
    try {
      _mine = await _repo.fetchMine().timeout(const Duration(seconds: 6));
      notifyListeners();
    } catch (_) {
      // Offline or slow: the server still enforces every restriction.
    }
  }

  void clear() {
    if (_mine.isEmpty) return;
    _mine = const [];
    notifyListeners();
  }
}

/// The database's refusal message when a restriction stopped an action, or null
/// when [error] is something else. Already a short readable sentence, e.g.
/// "Requesting a loan is restricted: Unpaid or repeatedly missed loan payments
/// (until Dec 5, 2026)."
String? restrictionMessageOf(Object error) {
  if (error is PostgrestException &&
      (error.details?.toString().startsWith('feature_restricted:') ?? false)) {
    return error.message;
  }
  return null;
}
