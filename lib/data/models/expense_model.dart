import 'package:flutter/material.dart';

// ─── Period Filter ────────────────────────────────────────────────────────────

enum ExpensePeriod { thisMonth, thisSeason, thisYear, allTime }

extension ExpensePeriodExt on ExpensePeriod {
  String get label {
    switch (this) {
      case ExpensePeriod.thisMonth: return 'This Month';
      case ExpensePeriod.thisSeason: return 'This Season';
      case ExpensePeriod.thisYear: return 'This Year';
      case ExpensePeriod.allTime: return 'All Time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case ExpensePeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case ExpensePeriod.thisSeason:
        return now.subtract(const Duration(days: 90));
      case ExpensePeriod.thisYear:
        return DateTime(now.year, 1, 1);
      case ExpensePeriod.allTime:
        return null;
    }
  }
}

// ─── Expense Categories ───────────────────────────────────────────────────────

const List<String> expenseCategories = [
  'Fertilizer',
  'Labor',
  'Seeds',
  'Tools',
  'Irrigation',
  'Transport',
  'Other',
];

IconData categoryIcon(String category) {
  switch (category) {
    case 'Fertilizer': return Icons.science_rounded;
    case 'Labor': return Icons.groups_rounded;
    case 'Seeds': return Icons.eco_rounded;
    case 'Tools': return Icons.build_rounded;
    case 'Irrigation': return Icons.water_drop_rounded;
    case 'Transport': return Icons.local_shipping_rounded;
    default: return Icons.category_rounded;
  }
}

Color categoryColor(String category) {
  switch (category) {
    case 'Fertilizer': return const Color(0xFF00450D);   // primary green
    case 'Labor': return const Color(0xFF835400);         // secondary amber
    case 'Seeds': return const Color(0xFF00460E);         // tertiary
    case 'Tools': return const Color(0xFFE65100);         // orange
    case 'Irrigation': return const Color(0xFF01579B);    // blue
    case 'Transport': return const Color(0xFF4A148C);     // purple
    default: return const Color(0xFF717A6D);              // outline
  }
}

Color categoryBgColor(String category) {
  switch (category) {
    case 'Fertilizer': return const Color(0xFFACF4A4);
    case 'Labor': return const Color(0xFFFFDDB5);
    case 'Seeds': return const Color(0xFF98F994);
    case 'Tools': return const Color(0xFFFFCCBC);
    case 'Irrigation': return const Color(0xFFB3E5FC);
    case 'Transport': return const Color(0xFFE1BEE7);
    default: return const Color(0xFFCFE6F2);
  }
}

// ─── Expense Model ────────────────────────────────────────────────────────────

class ExpenseModel {
  final String id;
  final String farmerId;
  final String category;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final bool isSubsidy;
  final String? notes;
  final DateTime createdAt;

  const ExpenseModel({
    required this.id,
    required this.farmerId,
    required this.category,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.isSubsidy,
    this.notes,
    required this.createdAt,
  });

  IconData get icon => categoryIcon(category);
  Color get color => categoryColor(category);
  Color get bgColor => categoryBgColor(category);

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      category: map['category'] as String? ?? 'Other',
      description: map['description'] as String,
      amount: (map['amount'] as num).toDouble(),
      expenseDate: DateTime.parse(map['expense_date'] as String),
      isSubsidy: map['is_subsidy'] as bool? ?? false,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

// ─── Category Breakdown ───────────────────────────────────────────────────────

class CategoryBreakdown {
  final String category;
  final double total;
  final double percentOfMax;
  final bool hasSubsidy;

  const CategoryBreakdown({
    required this.category,
    required this.total,
    required this.percentOfMax,
    required this.hasSubsidy,
  });
}
