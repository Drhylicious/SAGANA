import 'package:supabase_flutter/supabase_flutter.dart';

/// The two percentages that decide how much of a completed transaction is added
/// to a member's Capital Share (one row, capital_share_rates):
///  - [purchasePercent]: Cooperative Purchase, of the net amount paid on a
///    completed order of a member enrolled in the Product Sales program;
///  - [offerPercent]: Offer to Cooperative, of the sale value of a successful,
///    completed offer.
/// Monthly Contribution has no percentage. A rate applies to transactions
/// completed after it is saved; every credit already made keeps the rate it was
/// made with (the database copies it onto the credit).
class CapitalShareRates {
  final double purchasePercent;
  final double offerPercent;
  const CapitalShareRates({
    required this.purchasePercent,
    required this.offerPercent,
  });

  factory CapitalShareRates.fromMap(Map<String, dynamic> m) =>
      CapitalShareRates(
        purchasePercent: (m['purchase_percent'] as num?)?.toDouble() ?? 0,
        offerPercent: (m['offer_percent'] as num?)?.toDouble() ?? 0,
      );
}

/// One change of the percentages (capital_share_rate_versions). Version 1 is the
/// first rates; every later version is a change. A credit remembers the version it
/// was made under, so "newly credited" is the latest version and "previous" is
/// every earlier one.
class CapitalShareRateVersion {
  final int version;
  final double purchasePercent;
  final double offerPercent;
  final DateTime changedAt;
  const CapitalShareRateVersion({
    required this.version,
    required this.purchasePercent,
    required this.offerPercent,
    required this.changedAt,
  });

  factory CapitalShareRateVersion.fromMap(Map<String, dynamic> m) =>
      CapitalShareRateVersion(
        version: (m['version'] as num).toInt(),
        purchasePercent: (m['purchase_percent'] as num?)?.toDouble() ?? 0,
        offerPercent: (m['offer_percent'] as num?)?.toDouble() ?? 0,
        changedAt: DateTime.parse(m['changed_at'] as String).toLocal(),
      );
}

class CapitalShareRatesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// A percentage typed by the person: 0 to 100 with up to two decimals. Null
  /// when it is empty or not a valid percentage.
  static double? parsePercent(String input) {
    final text = input.trim();
    if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)) return null;
    final v = double.parse(text);
    return v >= 0 && v <= 100 ? v : null;
  }

  /// The saved percentages. Throws when they cannot be read (the screen says so),
  /// because a made-up default would look like a saved setting.
  Future<CapitalShareRates> fetch() async {
    final row = await _client
        .from('capital_share_rates')
        .select('purchase_percent, offer_percent')
        .eq('id', 1)
        .single();
    return CapitalShareRates.fromMap(row);
  }

  /// Every version of the percentages, oldest first. Empty when the history table
  /// does not exist yet (the Capital Share rates script is not run).
  Future<List<CapitalShareRateVersion>> fetchVersions() async {
    try {
      final rows = await _client
          .from('capital_share_rate_versions')
          .select('version, purchase_percent, offer_percent, changed_at')
          .order('version', ascending: true);
      return rows.map(CapitalShareRateVersion.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Saves both percentages. Needs a connection; throws on failure so the screen
  /// can say why (the database refuses a value outside 0-100, and a View Only
  /// Officer).
  Future<void> save({
    required double purchasePercent,
    required double offerPercent,
  }) async {
    await _client
        .from('capital_share_rates')
        .update({
          'purchase_percent': purchasePercent,
          'offer_percent': offerPercent,
        })
        .eq('id', 1);
  }
}
