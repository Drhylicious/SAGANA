class LoanItemModel {
  final String id;
  final String loanId;
  final String itemName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double lineTotal;

  const LoanItemModel({
    required this.id,
    required this.loanId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
  });

  /// e.g. "Rice Seeds (RC-222) x 5 Bags"
  String get displayLabel =>
      '$itemName x ${quantity % 1 == 0 ? quantity.toStringAsFixed(0) : quantity.toStringAsFixed(1)} ${_pluralUnit(quantity)}';

  String _pluralUnit(double qty) =>
      qty == 1 ? unit : '${unit}s';

  factory LoanItemModel.fromMap(Map<String, dynamic> map) {
    return LoanItemModel(
      id: map['id'] as String,
      loanId: map['loan_id'] as String,
      itemName: map['item_name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String? ?? 'bag',
      unitPrice: (map['unit_price'] as num).toDouble(),
      lineTotal: (map['line_total'] as num).toDouble(),
    );
  }
}

class LoanPaymentModel {
  final String id;
  final String loanId;
  final DateTime paymentDate;
  final double amountPaid;
  final double runningBalance;
  final String? notes;
  final String? recordedBy; // NEW — auth.users id of the admin who recorded this

  const LoanPaymentModel({
    required this.id,
    required this.loanId,
    required this.paymentDate,
    required this.amountPaid,
    required this.runningBalance,
    this.notes,
    this.recordedBy,
  });

  factory LoanPaymentModel.fromMap(Map<String, dynamic> map) {
    return LoanPaymentModel(
      id: map['id'] as String,
      loanId: map['loan_id'] as String,
      paymentDate: DateTime.parse(map['payment_date'] as String),
      amountPaid: (map['amount_paid'] as num).toDouble(),
      runningBalance: (map['running_balance'] as num).toDouble(),
      notes: map['notes'] as String?,
      recordedBy: map['recorded_by'] as String?,
    );
  }
}

class LoanModel {
  final String id;
  final String farmerId;
  final String referenceNo;
  final DateTime issuedDate;
  final double totalValue;
  final double amountPaid;
  final String status; // active | overdue | paid
  final String? notes;
  final DateTime? nextPaymentDate; // NEW
  final double monthlyPayment; // NEW
  final List<LoanItemModel> items;
  final List<LoanPaymentModel> payments;

  const LoanModel({
    required this.id,
    required this.farmerId,
    required this.referenceNo,
    required this.issuedDate,
    required this.totalValue,
    required this.amountPaid,
    required this.status,
    this.notes,
    this.nextPaymentDate,
    this.monthlyPayment = 0,
    required this.items,
    required this.payments,
  });

  double get remainingBalance =>
      (totalValue - amountPaid).clamp(0, double.infinity);

  double get repaidPercent =>
      totalValue > 0 ? (amountPaid / totalValue).clamp(0.0, 1.0) : 0.0;

  bool get isOverdue => status == 'overdue';
  bool get isActive => status == 'active';
  bool get isPaid => status == 'paid';

  factory LoanModel.fromMap(Map<String, dynamic> map) {
    final itemRows = (map['farmer_loan_items'] as List?) ?? [];
    final paymentRows = (map['farmer_loan_payments'] as List?) ?? [];

    return LoanModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      referenceNo: map['reference_no'] as String,
      issuedDate: DateTime.parse(map['issued_date'] as String),
      totalValue: (map['total_value'] as num).toDouble(),
      amountPaid: (map['amount_paid'] as num? ?? 0).toDouble(),
      status: map['status'] as String? ?? 'active',
      notes: map['notes'] as String?,
      nextPaymentDate: map['next_payment_date'] != null
          ? DateTime.tryParse(map['next_payment_date'] as String)
          : null,
      monthlyPayment: (map['monthly_payment'] as num? ?? 0).toDouble(),
      items: itemRows
          .map((r) => LoanItemModel.fromMap(r as Map<String, dynamic>))
          .toList(),
      payments: paymentRows
          .map((r) => LoanPaymentModel.fromMap(r as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate)),
    );
  }
}