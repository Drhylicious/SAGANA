class MemberSalesTransaction {
  final String id;
  final String farmerId;
  final String cropName;
  final String cropType; // 'palay' | 'peanut'
  final double quantityKg;

  /// The unit [quantityKg] is measured in (the sale's own unit; the field keeps
  /// its old name). A sale from before units existed is kg.
  final String unit;
  final double amount;
  final DateTime saleDate;
  final String? referenceNo;

  const MemberSalesTransaction({
    required this.id,
    required this.farmerId,
    required this.cropName,
    required this.cropType,
    required this.quantityKg,
    this.unit = 'kg',
    required this.amount,
    required this.saleDate,
    this.referenceNo,
  });

  factory MemberSalesTransaction.fromMap(Map<String, dynamic> map) {
    return MemberSalesTransaction(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      cropName: map['crop_name'] as String,
      cropType: map['crop_type'] as String? ?? 'palay',
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      unit: (map['unit'] as String?)?.trim().isNotEmpty == true
          ? (map['unit'] as String).trim()
          : 'kg',
      amount: (map['amount'] as num).toDouble(),
      saleDate: DateTime.parse(map['sale_date'] as String),
      referenceNo: map['reference_no'] as String?,
    );
  }
}

class CapitalSharesModel {
  final String farmerId;

  /// Completed whole shares — trigger-maintained as
  /// floor(totalContribution / shareValuePerUnit). Only fully-paid
  /// ₱2,000 increments count (Decision D1f).
  final int totalShares;

  /// Fixed by the BOD. ₱2,000 per share as of Phase B.
  final double shareValuePerUnit;

  /// Authoritative running ₱ total of all recorded capital
  /// contributions (from capital_contribution_events). Loan eligibility
  /// is checked against this, not [totalShares].
  final double totalContribution;

  const CapitalSharesModel({
    required this.farmerId,
    required this.totalShares,
    required this.shareValuePerUnit,
    this.totalContribution = 0,
  });

  /// Value of the completed whole shares only (interest-on-capital base).
  double get investmentValue => totalShares * shareValuePerUnit;

  /// ₱ still needed to complete the next whole share.
  double get amountToNextShare {
    if (shareValuePerUnit <= 0) return 0;
    final remainder = totalContribution % shareValuePerUnit;
    return remainder == 0 ? 0 : shareValuePerUnit - remainder;
  }

  factory CapitalSharesModel.fromMap(Map<String, dynamic> map) {
    return CapitalSharesModel(
      farmerId: map['farmer_id'] as String,
      totalShares: map['total_shares'] as int? ?? 0,
      shareValuePerUnit: (map['share_value_per_unit'] as num? ?? 2000)
          .toDouble(),
      totalContribution: (map['total_contribution'] as num? ?? 0).toDouble(),
    );
  }
}

/// One row of the capital-contribution ledger
/// (capital_contribution_events).
class CapitalContributionEvent {
  final String id;
  final String farmerId;
  final double amount;
  final String
  source; // member_payment | patronage_capital | manual_adjustment | opening_balance
  final String? note;
  final DateTime createdAt;

  /// Who recorded the entry (for a reversal: who reversed it), and their name
  /// when the staff screen could look it up. Null for system entries.
  final String? recordedBy;
  final String? recordedByName;

  /// Set on a reversal: the entry it cancels, and the reason given.
  final String? reversesEventId;
  final String? reversalReason;

  /// The month a monthly contribution payment is for (first of that month), and the
  /// date it was paid. Null on every other kind of entry.
  final DateTime? contributionMonth;
  final DateTime? paymentDate;

  /// Starting Capital only: the date the member actually held this capital (can
  /// be a past year). Null = the day it was recorded. A cancellation carries the
  /// date of the entry it cancels.
  final DateTime? effectiveDate;

  const CapitalContributionEvent({
    required this.id,
    required this.farmerId,
    required this.amount,
    required this.source,
    required this.createdAt,
    this.note,
    this.recordedBy,
    this.recordedByName,
    this.reversesEventId,
    this.reversalReason,
    this.contributionMonth,
    this.paymentDate,
    this.effectiveDate,
  });

  /// The day this entry counts for in the reports: its own date when it has one,
  /// otherwise the day it was recorded.
  DateTime get countsOn {
    final d = effectiveDate;
    if (d != null) return d;
    final c = createdAt.toLocal();
    return DateTime(c.year, c.month, c.day);
  }

  bool get isReversal => reversesEventId != null;

  /// An older payout that was added to capital (source patronage_capital) is a
  /// permanent part of the Capital Share and is not reversed from the ledger.
  /// A reversal itself is never reversed.
  bool get canBeReversed => !isReversal && source != 'patronage_capital';

  factory CapitalContributionEvent.fromMap(
    Map<String, dynamic> map, {
    String? recordedByName,
  }) {
    return CapitalContributionEvent(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      source: map['source'] as String? ?? 'member_payment',
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      recordedBy: map['recorded_by'] as String?,
      recordedByName: recordedByName,
      reversesEventId: map['reverses_event_id'] as String?,
      reversalReason: map['reversal_reason'] as String?,
      contributionMonth: map['contribution_month'] == null
          ? null
          : DateTime.parse(map['contribution_month'] as String),
      paymentDate: map['payment_date'] == null
          ? null
          : DateTime.parse(map['payment_date'] as String),
      effectiveDate: map['effective_date'] == null
          ? null
          : DateTime.parse(map['effective_date'] as String),
    );
  }
}
