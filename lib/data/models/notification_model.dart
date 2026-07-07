// ─── Notification Type ────────────────────────────────────────────────────────

enum NotificationType { order, listing, loan, price, sync, system }

extension NotificationTypeExt on NotificationType {
  String get value {
    switch (this) {
      case NotificationType.order:   return 'order';
      case NotificationType.listing: return 'listing';
      case NotificationType.loan:    return 'loan';
      case NotificationType.price:   return 'price';
      case NotificationType.sync:    return 'sync';
      case NotificationType.system:  return 'system';
    }
  }

  static NotificationType fromString(String? value) {
    switch (value) {
      case 'order':   return NotificationType.order;
      case 'listing': return NotificationType.listing;
      case 'loan':    return NotificationType.loan;
      case 'price':   return NotificationType.price;
      case 'sync':    return NotificationType.sync;
      default:        return NotificationType.system;
    }
  }
}

// ─── Notification Filter ──────────────────────────────────────────────────────

enum NotificationFilter { all, orders, listings, loans, prices }

extension NotificationFilterExt on NotificationFilter {
  String get label {
    switch (this) {
      case NotificationFilter.all:      return 'All';
      case NotificationFilter.orders:   return 'Orders';
      case NotificationFilter.listings: return 'Listings';
      case NotificationFilter.loans:    return 'Loans';
      case NotificationFilter.prices:   return 'Prices';
    }
  }

  bool matches(NotificationModel n) {
    switch (this) {
      case NotificationFilter.all:      return true;
      case NotificationFilter.orders:   return n.type == NotificationType.order;
      case NotificationFilter.listings: return n.type == NotificationType.listing;
      case NotificationFilter.loans:    return n.type == NotificationType.loan;
      case NotificationFilter.prices:   return n.type == NotificationType.price;
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
