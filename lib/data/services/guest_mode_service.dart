import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'market_types_service.dart';

/// Which kind of guest exploration is active.
enum GuestRole { buyer, farmer }

/// Signed-out "Explore as Buyer" / "Explore as Farmer" state.
///
/// Held in memory only: Guest Mode never creates a Supabase session, never
/// writes to Hive and never writes a database record. A restart (or a web
/// reload) returns to the Welcome screen.
class GuestModeService extends ChangeNotifier {
  GuestModeService._();
  static final GuestModeService instance = GuestModeService._();

  GuestRole? _role;

  /// The chosen exploration mode, or null when not exploring as a guest.
  GuestRole? get role => _role;

  static bool get _hasSession {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false; // Supabase not initialised (tests): no session.
    }
  }

  /// True only while exploring AND signed out; a real session always wins.
  bool get isGuest => _role != null && !_hasSession;
  bool get isGuestBuyer => isGuest && _role == GuestRole.buyer;
  bool get isGuestFarmer => isGuest && _role == GuestRole.farmer;

  /// Shorthand for screens that only need the yes/no answer.
  static bool get active => instance.isGuest;

  void enter(GuestRole role) {
    if (_role == role) return;
    _role = role;
    // The public market-type labels (Buyer-visible only) for badges and prices.
    unawaited(MarketTypes.instance.loadPublic());
    notifyListeners();
  }

  /// Leaves Guest Mode (after sign-in, sign-out, or "back to Welcome").
  void exit() {
    if (_role == null) return;
    _role = null;
    notifyListeners();
  }
}
