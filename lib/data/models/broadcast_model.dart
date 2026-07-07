// ─── Broadcast Category ───────────────────────────────────────────────────────

enum BroadcastCategory { meeting, financial, harvest, update, general }

extension BroadcastCategoryExt on BroadcastCategory {
  String get value {
    switch (this) {
      case BroadcastCategory.meeting:   return 'meeting';
      case BroadcastCategory.financial: return 'financial';
      case BroadcastCategory.harvest:   return 'harvest';
      case BroadcastCategory.update:    return 'update';
      case BroadcastCategory.general:   return 'general';
    }
  }

  String get label {
    switch (this) {
      case BroadcastCategory.meeting:   return 'Meeting';
      case BroadcastCategory.financial: return 'Financial';
      case BroadcastCategory.harvest:   return 'Harvest';
      case BroadcastCategory.update:    return 'Update';
      case BroadcastCategory.general:   return 'General';
    }
  }

  static BroadcastCategory fromString(String? v) {
    switch (v) {
      case 'meeting':   return BroadcastCategory.meeting;
      case 'financial': return BroadcastCategory.financial;
      case 'harvest':   return BroadcastCategory.harvest;
      case 'update':    return BroadcastCategory.update;
      default:          return BroadcastCategory.general;
    }
  }
}

// ─── Recipient Type ───────────────────────────────────────────────────────────

enum RecipientType { allMembers, outstandingLoans, specificCrop, specificFarmer }

extension RecipientTypeExt on RecipientType {
  String get value {
    switch (this) {
      case RecipientType.allMembers:       return 'all_members';
      case RecipientType.outstandingLoans: return 'outstanding_loans';
      case RecipientType.specificCrop:     return 'specific_crop';
      case RecipientType.specificFarmer:   return 'specific_farmer';
    }
  }

  String get label {
    switch (this) {
      case RecipientType.allMembers:       return 'All Members';
      case RecipientType.outstandingLoans: return 'Outstanding Loans';
      case RecipientType.specificCrop:     return 'Specific Crop';
      case RecipientType.specificFarmer:   return 'Specific Farmer';
    }
  }

  static RecipientType fromString(String? v) {
    switch (v) {
      case 'outstanding_loans': return RecipientType.outstandingLoans;
      case 'specific_crop':     return RecipientType.specificCrop;
      case 'specific_farmer':   return RecipientType.specificFarmer;
      default:                  return RecipientType.allMembers;
    }
  }
}

// ─── Broadcast Log Model ──────────────────────────────────────────────────────

class BroadcastModel {
  final String id;
  final String title;
  final String body;
  final BroadcastCategory category;
  final RecipientType recipientType;
  final String? recipientFilter; // crop name or farmer_id
  final int recipientCount;
  final DateTime? scheduledAt;
  final DateTime sentAt;
  final String? createdBy;
  final DateTime createdAt;

  const BroadcastModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.recipientType,
    this.recipientFilter,
    required this.recipientCount,
    this.scheduledAt,
    required this.sentAt,
    this.createdBy,
    required this.createdAt,
  });

  bool get isScheduled => scheduledAt != null;

  String get recipientLabel {
    switch (recipientType) {
      case RecipientType.outstandingLoans:
        return 'Outstanding Loans';
      case RecipientType.specificCrop:
        return recipientFilter != null
            ? '${recipientFilter!} Farmers'
            : 'Specific Crop';
      case RecipientType.specificFarmer:
        return 'Specific Farmer';
      default:
        return 'All Members';
    }
  }

  factory BroadcastModel.fromMap(Map<String, dynamic> map) {
    return BroadcastModel(
      id:              map['id'] as String,
      title:           map['title'] as String,
      body:            map['body'] as String,
      category:        BroadcastCategoryExt.fromString(
                           map['category'] as String?),
      recipientType:   RecipientTypeExt.fromString(
                           map['recipient_type'] as String?),
      recipientFilter: map['recipient_filter'] as String?,
      recipientCount:  map['recipient_count'] as int? ?? 0,
      scheduledAt:     map['scheduled_at'] != null
                           ? DateTime.parse(map['scheduled_at'] as String)
                           : null,
      sentAt:          DateTime.parse(map['sent_at'] as String),
      createdBy:       map['created_by'] as String?,
      createdAt:       DateTime.parse(map['created_at'] as String),
    );
  }
}

// ─── Broadcast Template ───────────────────────────────────────────────────────

class BroadcastTemplate {
  final String title;
  final String body;
  final BroadcastCategory category;
  final RecipientType recipientType;

  const BroadcastTemplate({
    required this.title,
    required this.body,
    required this.category,
    required this.recipientType,
  });
}

/// Predefined SP3 broadcast templates
const List<BroadcastTemplate> kBroadcastTemplates = [
  BroadcastTemplate(
    title: 'BOD Meeting This Saturday',
    body: 'Magandang araw! Ipinapaalalang mayroon tayong BOD Meeting ngayong Sabado '
        'sa ating cooperative office. Ang mga miyembro na may natatanggap na utang '
        'ay hinihiling na magdala ng kanilang bayad. Maraming salamat!',
    category: BroadcastCategory.meeting,
    recipientType: RecipientType.allMembers,
  ),
  BroadcastTemplate(
    title: 'Loan Payment Reminder',
    body: 'Paalala: Ang inyong loan payment ay dapat na bayaran bago mag-Sabado. '
        'Pakipunta sa ating opisina para sa inyong bayad. Salamat sa inyong '
        'patuloy na pakikilahok sa SP3 Cooperative.',
    category: BroadcastCategory.financial,
    recipientType: RecipientType.outstandingLoans,
  ),
  BroadcastTemplate(
    title: 'Price Update Notice',
    body: 'Abiso: Ang presyo ng ating mga produkto ay na-update na ng SP3 Admin. '
        'Pakitingnan ang inyong Analytics tab para sa pinakabagong presyo. '
        'Para sa katanungan, makipag-ugnayan sa ating opisina.',
    category: BroadcastCategory.update,
    recipientType: RecipientType.allMembers,
  ),
];
