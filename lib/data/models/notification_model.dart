// ─── Notification Type ────────────────────────────────────────────────────────
//
// Mirrors the full `notifications_type_check` CHECK constraint vocabulary.
// The 8 types below `system` are, as of this fix, only ever inserted for
// admin_profiles recipients — no farmer-directed insert anywhere in the
// schema currently produces them. Included for correctness/exhaustiveness
// rather than any current farmer-facing need.

enum NotificationType {
  order,
  listing,
  loan,
  price,
  sync,
  system,
  listingSubmitted,
  loanOverdue,
  memberPending,
  memberRegistered,
  memberUpdated,
  memberApproved,
  memberRejected,
  lowStock,
  stockDepleted,
  cropRequest,
  cooperativeOffer,
  program,
}

extension NotificationTypeExt on NotificationType {
  String get value {
    switch (this) {
      case NotificationType.order:             return 'order';
      case NotificationType.listing:            return 'listing';
      case NotificationType.loan:               return 'loan';
      case NotificationType.price:              return 'price';
      case NotificationType.sync:               return 'sync';
      case NotificationType.system:             return 'system';
      case NotificationType.listingSubmitted:   return 'listing_submitted';
      case NotificationType.loanOverdue:        return 'loan_overdue';
      case NotificationType.memberPending:      return 'member_pending';
      case NotificationType.memberRegistered:   return 'member_registered';
      case NotificationType.memberUpdated:      return 'member_updated';
      case NotificationType.memberApproved:     return 'member_approved';
      case NotificationType.memberRejected:     return 'member_rejected';
      case NotificationType.lowStock:           return 'low_stock';
      case NotificationType.stockDepleted:      return 'stock_depleted';
      case NotificationType.cropRequest:        return 'crop_request';
      case NotificationType.cooperativeOffer:   return 'cooperative_offer';
      case NotificationType.program:            return 'program';
    }
  }

  static NotificationType fromString(String? value) {
    switch (value) {
      case 'order':              return NotificationType.order;
      case 'listing':             return NotificationType.listing;
      case 'loan':                return NotificationType.loan;
      case 'price':               return NotificationType.price;
      case 'sync':                return NotificationType.sync;
      case 'listing_submitted':   return NotificationType.listingSubmitted;
      case 'loan_overdue':        return NotificationType.loanOverdue;
      case 'member_pending':      return NotificationType.memberPending;
      case 'member_registered':   return NotificationType.memberRegistered;
      case 'member_updated':      return NotificationType.memberUpdated;
      case 'member_approved':     return NotificationType.memberApproved;
      case 'member_rejected':     return NotificationType.memberRejected;
      case 'low_stock':           return NotificationType.lowStock;
      case 'stock_depleted':      return NotificationType.stockDepleted;
      case 'crop_request':        return NotificationType.cropRequest;
      case 'cooperative_offer':   return NotificationType.cooperativeOffer;
      case 'program':             return NotificationType.program;
      default:                    return NotificationType.system;
    }
  }
}

// ─── Notification Filter ──────────────────────────────────────────────────────

// Redesigned per the Notification Filter Chip review (Item 1, Option A):
// 6 of 10 farmer-facing notification sources previously inserted with
// type = 'system', which had no matching chip — those notifications were
// only ever visible under "All". Every type now has its own precise chip.
enum NotificationFilter {
  all,
  orders,
  listings,
  cropRequests,
  cooperativeOffers,
  loans,
  programs,
  prices,
}

extension NotificationFilterExt on NotificationFilter {
  String get label {
    switch (this) {
      case NotificationFilter.all:               return 'All';
      case NotificationFilter.orders:             return 'Orders';
      case NotificationFilter.listings:           return 'Listings';
      case NotificationFilter.cropRequests:       return 'Crop Requests';
      case NotificationFilter.cooperativeOffers:  return 'Cooperative Offers';
      case NotificationFilter.loans:              return 'Loans';
      case NotificationFilter.programs:           return 'Programs';
      case NotificationFilter.prices:             return 'Prices';
    }
  }

  bool matches(NotificationModel n) {
    switch (this) {
      case NotificationFilter.all:
        return true;
      case NotificationFilter.orders:
        return n.type == NotificationType.order;
      case NotificationFilter.listings:
        return n.type == NotificationType.listing;
      case NotificationFilter.cropRequests:
        return n.type == NotificationType.cropRequest;
      case NotificationFilter.cooperativeOffers:
        return n.type == NotificationType.cooperativeOffer;
      case NotificationFilter.loans:
        return n.type == NotificationType.loan;
      case NotificationFilter.programs:
        return n.type == NotificationType.program;
      case NotificationFilter.prices:
        return n.type == NotificationType.price;
    }
  }
}

// ─── Notification Model ───────────────────────────────────────────────────────

class NotificationModel {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
  });

  // ─── Computed helpers ─────────────────────────────────────────────────────

  bool get isUnread => !isRead;

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours  < 24)   return '${diff.inHours}h ago';
    if (diff.inDays   == 1)   return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  // ─── Serialization ────────────────────────────────────────────────────────

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id:        map['id'] as String,
      userId:    map['user_id'] as String,
      type:      NotificationTypeExt.fromString(map['type'] as String?),
      title:     map['title'] as String,
      body:      map['body'] as String,
      isRead:    map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id':         id,
      'user_id':    userId,
      'type':       type.value,
      'title':      title,
      'body':       body,
      'is_read':    isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id:        id,
      userId:    userId,
      type:      type,
      title:     title,
      body:      body,
      isRead:    isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}