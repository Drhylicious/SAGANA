// Buyer's own activity model — not a shared/generic one. Farmer
// (ActivityItem/ActivityType in dashboard_summary_model.dart) and Admin
// (AdminActivityItem/AdminActivityType in admin_dashboard_model.dart)
// each already have their own independent model with role-specific
// categories (harvest/listing/loan/cropRequest for Farmer; a broader set
// for Admin) — there is no shared activity architecture anywhere in this
// codebase to reuse. This follows that same per-role convention rather
// than deviating from it.

enum BuyerActivityType { order, profile }

class BuyerActivityItem {
  final String id;
  final BuyerActivityType type;
  final String title;
  final String subtitle;
  final String? valueLabel;
  final String? statusLabel;
  final DateTime timestamp;

  // Raw order status ('pending'/'approved'/'completed'/'cancelled'),
  // populated only for order-type items. Added so consuming widgets can
  // render a localized title/status instead of relying on this model's
  // title/statusLabel fields, which the repository still populates with
  // English as a defensive fallback but which fixed widgets no longer read
  // for order-type items.
  final String? orderStatus;

  const BuyerActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.valueLabel,
    this.statusLabel,
    required this.timestamp,
    this.orderStatus,
  });
}
