import '../../core/l10n/app_localizations.dart';

/// The seven things a Manager or Officer can stop a Farmer Member from STARTING.
/// A restriction never touches what is already in progress (existing listings,
/// offers, orders, loans, program participation); it only refuses new ones.
///
/// [key] is the value stored in member_restrictions.feature.
enum RestrictableFeature {
  marketplaceListing('marketplace_listing'),
  coopOffer('coop_offer'),
  informalSale('informal_sale'),
  gingerDaAmad('ginger_da_amad'),
  checkout('checkout'),
  loanRequest('loan_request'),
  programJoin('program_join');

  final String key;
  const RestrictableFeature(this.key);

  static RestrictableFeature? fromKey(String? key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Full name, for the Manager's checklist and the Farmer's notice.
  String label(AppLocalizations l10n) => switch (this) {
    marketplaceListing => l10n.restrictFeatureMarketplaceListing,
    coopOffer => l10n.restrictFeatureCoopOffer,
    informalSale => l10n.restrictFeatureInformalSale,
    gingerDaAmad => l10n.restrictFeatureGinger,
    checkout => l10n.restrictFeatureCheckout,
    loanRequest => l10n.restrictFeatureLoan,
    programJoin => l10n.restrictFeatureProgram,
  };

  /// One word, for the small chips on a member's card.
  String chipLabel(AppLocalizations l10n) => switch (this) {
    marketplaceListing => l10n.restrictChipMarketplaceListing,
    coopOffer => l10n.restrictChipCoopOffer,
    informalSale => l10n.restrictChipInformalSale,
    gingerDaAmad => l10n.restrictChipGinger,
    checkout => l10n.restrictChipCheckout,
    loanRequest => l10n.restrictChipLoan,
    programJoin => l10n.restrictChipProgram,
  };
}

/// One restriction row (staff view). `inForce` follows the same rule as the
/// database: active, and not past its end date.
class MemberRestriction {
  final String id;
  final String memberId;
  final RestrictableFeature feature;
  final String reason;
  final String status; // active | lifted | ended | closed
  final DateTime startsAt;
  final DateTime? endsAt;

  const MemberRestriction({
    required this.id,
    required this.memberId,
    required this.feature,
    required this.reason,
    required this.status,
    required this.startsAt,
    this.endsAt,
  });

  bool get inForce =>
      status == 'active' && (endsAt == null || endsAt!.isAfter(DateTime.now()));

  /// Null when the stored feature is not one this build knows.
  static MemberRestriction? fromMap(Map<String, dynamic> m) {
    final feature = RestrictableFeature.fromKey(m['feature'] as String?);
    if (feature == null) return null;
    return MemberRestriction(
      id: m['id'] as String,
      memberId: m['member_id'] as String,
      feature: feature,
      reason: (m['reason'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'active',
      startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
      endsAt: m['ends_at'] == null
          ? null
          : DateTime.parse(m['ends_at'] as String).toLocal(),
    );
  }
}

/// A restriction as the Farmer sees it: no staff names.
class MyRestriction {
  final RestrictableFeature feature;
  final String reason;
  final DateTime startsAt;
  final DateTime? endsAt;

  const MyRestriction({
    required this.feature,
    required this.reason,
    required this.startsAt,
    this.endsAt,
  });

  bool get inForce => endsAt == null || endsAt!.isAfter(DateTime.now());

  static MyRestriction? fromMap(Map<String, dynamic> m) {
    final feature = RestrictableFeature.fromKey(m['feature'] as String?);
    if (feature == null) return null;
    return MyRestriction(
      feature: feature,
      reason: (m['reason'] as String?) ?? '',
      startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
      endsAt: m['ends_at'] == null
          ? null
          : DateTime.parse(m['ends_at'] as String).toLocal(),
    );
  }
}

/// One line of a member's restriction and suspension history (staff view).
class DisciplineEntry {
  /// restriction | suspension | reactivation
  final String kind;
  final RestrictableFeature? feature;
  final String reason;

  /// restriction: active | lifted | ended | closed. suspension / reactivation:
  /// the status the account moved to.
  final String status;
  final DateTime startedAt;
  final DateTime? endsAt;
  final DateTime? endedAt;
  final String? closeReason;
  final String? actorName;
  final String? actorRole;
  final String? endedByName;

  const DisciplineEntry({
    required this.kind,
    this.feature,
    required this.reason,
    required this.status,
    required this.startedAt,
    this.endsAt,
    this.endedAt,
    this.closeReason,
    this.actorName,
    this.actorRole,
    this.endedByName,
  });

  bool get isRestriction => kind == 'restriction';

  factory DisciplineEntry.fromMap(Map<String, dynamic> m) {
    DateTime? when(String key) =>
        m[key] == null ? null : DateTime.parse(m[key] as String).toLocal();
    return DisciplineEntry(
      kind: (m['kind'] as String?) ?? 'restriction',
      feature: RestrictableFeature.fromKey(m['feature'] as String?),
      reason: ((m['reason'] as String?) ?? '').trim(),
      status: (m['status'] as String?) ?? '',
      startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
      endsAt: when('ends_at'),
      endedAt: when('ended_at'),
      closeReason: m['close_reason'] as String?,
      actorName: m['actor_name'] as String?,
      actorRole: m['actor_role'] as String?,
      endedByName: m['ended_by_name'] as String?,
    );
  }
}
