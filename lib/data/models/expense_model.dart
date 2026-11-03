import 'package:flutter/material.dart';

// ─── Period Filter ────────────────────────────────────────────────────────────

// Declaration order is the display order of the filter chips
// (ExpensePeriod.values, used directly by _PeriodFilter) — All Time first.
// "This Quarter" is the calendar quarter, the same period the Manager's
// reports and Farmer Analytics use, so a farmer's expense total matches what
// the Manager sees for the same period.
enum ExpensePeriod { allTime, thisMonth, thisQuarter, thisYear }

extension ExpensePeriodExt on ExpensePeriod {
  String get label {
    switch (this) {
      case ExpensePeriod.thisMonth:
        return 'This Month';
      case ExpensePeriod.thisQuarter:
        return 'This Quarter';
      case ExpensePeriod.thisYear:
        return 'This Year';
      case ExpensePeriod.allTime:
        return 'All Time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case ExpensePeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case ExpensePeriod.thisQuarter:
        return DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
      case ExpensePeriod.thisYear:
        return DateTime(now.year, 1, 1);
      case ExpensePeriod.allTime:
        return null;
    }
  }
}

// ─── Expense Categories ───────────────────────────────────────────────────────
// Category names come from CategoryRepository.fetchExpenseCategories()
// (expense_categories lookup table, supabase_schema_expense_categories.sql)
// instead of a hardcoded list — a farmer can add a new one inline from the
// Add Expense dropdown. The icon and colours below are picked by what the
// category's NAME says (case-insensitive), so a category added later
// ("Pesticide", "Fuel", "Animal Feeds") gets a fitting icon with no code change,
// and anything unrecognised falls back to a neutral receipt icon. Every icon is
// a rounded Material icon so the whole set reads as one family. Expenses carry
// no photo: the category icon is the only picture a record has.

class _CategoryStyle {
  final IconData icon;
  final Color color;
  final Color background;
  const _CategoryStyle(this.icon, this.color, this.background);
}

const _CategoryStyle _kFallbackStyle = _CategoryStyle(
  Icons.receipt_long_rounded,
  Color(0xFF546E7A),
  Color(0xFFDCE6EC),
);

/// (words that identify the category, its style). First match wins.
const List<(List<String>, _CategoryStyle)> _kCategoryStyles = [
  (
    ['fertilizer', 'fertiliser', 'compost', 'manure', 'abono'],
    _CategoryStyle(Icons.compost_rounded, Color(0xFF00450D), Color(0xFFACF4A4)),
  ),
  (
    ['pesticide', 'herbicide', 'insecticide', 'chemical', 'spray', 'fungicide'],
    _CategoryStyle(Icons.bug_report_rounded, Color(0xFFB71C1C), Color(0xFFFFCDD2)),
  ),
  (
    ['seed', 'seedling', 'planting'],
    _CategoryStyle(Icons.spa_rounded, Color(0xFF2E7D32), Color(0xFFC8E6C9)),
  ),
  (
    ['labor', 'labour', 'worker', 'wage', 'hired'],
    _CategoryStyle(Icons.engineering_rounded, Color(0xFF835400), Color(0xFFFFDDB5)),
  ),
  (
    ['tool', 'equipment', 'machine', 'implement'],
    _CategoryStyle(Icons.handyman_rounded, Color(0xFFE65100), Color(0xFFFFCCBC)),
  ),
  (
    ['irrigation', 'water'],
    _CategoryStyle(Icons.water_drop_rounded, Color(0xFF01579B), Color(0xFFB3E5FC)),
  ),
  (
    ['transport', 'delivery', 'hauling', 'freight', 'fare'],
    _CategoryStyle(Icons.local_shipping_rounded, Color(0xFF4A148C), Color(0xFFE1BEE7)),
  ),
  (
    ['feed', 'livestock', 'animal', 'poultry'],
    _CategoryStyle(Icons.pets_rounded, Color(0xFF6D4C41), Color(0xFFD7CCC8)),
  ),
  (
    ['fuel', 'gas', 'diesel', 'gasoline', 'oil'],
    _CategoryStyle(Icons.local_gas_station_rounded, Color(0xFFC62828), Color(0xFFFFCDD2)),
  ),
  (
    ['rent', 'land', 'lease'],
    _CategoryStyle(Icons.landscape_rounded, Color(0xFF558B2F), Color(0xFFDCEDC8)),
  ),
  (
    ['repair', 'maintenance'],
    _CategoryStyle(Icons.build_circle_rounded, Color(0xFF455A64), Color(0xFFCFD8DC)),
  ),
  (
    ['packag', 'sack', 'packing'],
    _CategoryStyle(Icons.inventory_2_rounded, Color(0xFF8D6E63), Color(0xFFEFEBE9)),
  ),
  (
    ['electric', 'utility', 'utilities', 'power'],
    _CategoryStyle(Icons.bolt_rounded, Color(0xFFF9A825), Color(0xFFFFF3C4)),
  ),
];

_CategoryStyle _styleFor(String category) {
  // Matched on whole words (a word may START with a keyword: "Fertilizers",
  // "Rental"), so "Soil prep" is not mistaken for "oil" and "Current" for "rent".
  final tokens = category
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return _kFallbackStyle;
  for (final (words, style) in _kCategoryStyles) {
    if (words.any((w) => tokens.any((t) => t.startsWith(w)))) return style;
  }
  return _kFallbackStyle;
}

IconData categoryIcon(String category) => _styleFor(category).icon;

Color categoryColor(String category) => _styleFor(category).color;

Color categoryBgColor(String category) => _styleFor(category).background;

// ─── Expense Model ────────────────────────────────────────────────────────────

class ExpenseModel {
  final String id;
  final String farmerId;
  final String?
  name; // nullable — absent on rows created before this field existed
  final String category;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final bool isSubsidy;
  final String? notes;
  final DateTime createdAt;
  final bool isSynced; // NEW — Phase 2 / U2, mirrors HarvestModel.isSynced

  const ExpenseModel({
    required this.id,
    required this.farmerId,
    this.name,
    required this.category,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.isSubsidy,
    this.notes,
    required this.createdAt,
    this.isSynced = true,
  });

  IconData get icon => categoryIcon(category);
  Color get color => categoryColor(category);
  Color get bgColor => categoryBgColor(category);

  // Falls back to the category for expenses recorded before the Name
  // field existed, so older rows still show a sensible title.
  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : category;

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      name: map['name'] as String?,
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
