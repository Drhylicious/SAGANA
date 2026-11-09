import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The sorting rule of the whole system, for all four roles: a list of records shows the newest
/// first. This guards it at the data layer. Any database read that orders by a date and is NOT
/// newest first has to be named below with the reason; a new one fails this test until it is
/// either made newest first or added here on purpose.
///
/// The reasons that are allowed:
///  - a work QUEUE staff must clear: oldest first (first in, first out),
///  - a TIMELINE or history read top to bottom (oldest first inside one record),
///  - a CHART, drawn left to right in time,
///  - a DUE-DATE queue: the earliest due date first.
const _allowed = <String, String>{
  "account_management_repository.dart|.order('requested_at')":
      'queue: password-help requests, oldest first',
  "admin_loan_repository.dart|.order('next_payment_date', ascending: true)":
      'due-date queue: earliest due first',
  "analytics_repository.dart|.order('recorded_at', ascending: true)":
      'chart: price history left to right',
  "cooperative_offer_repository.dart|.order('created_at', ascending: true)":
      'timeline: the rounds of one offer',
  "market_linking_repository.dart|.order('completed_at', ascending: true)":
      'timeline: the sales of one request',
  "price_management_repository.dart|.order('recorded_at', ascending: true)":
      'chart: price history left to right',
  "program_repository.dart|.order('submitted_at', ascending: status == 'pending')":
      'queue: pending join requests oldest first, decided ones newest first',
  "program_repository.dart|.order('created_at')":
      "catalog: a program's products, shown by availability then name",
  "workflow_event_repository.dart|.order('created_at', ascending: true)":
      'timeline: the history of one record',
};

void main() {
  final dateColumn = RegExp(
    r"(created|requested|submitted|offered|recorded|completed|received|reviewed|sent|enrolled|expense|harvest|sale|payment|next_payment)_?(at|date)?",
  );

  test(
    'every date-ordered read in the data layer is newest first, or is a named exception',
    () {
      final found = <String>{};
      final offenders = <String>[];
      for (final e in Directory('lib/data').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final name = e.path.split(RegExp(r'[\\/]')).last;
        for (final m in RegExp(
          r"\.order\(\s*'(\w+)'[^)]*\)",
        ).allMatches(e.readAsStringSync())) {
          final call = m.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
          final column = m.group(1)!;
          if (!dateColumn.hasMatch(column) || column == 'id') continue;
          if (call.contains('ascending: false')) continue;
          final key = '$name|$call';
          found.add(key);
          if (!_allowed.containsKey(key)) offenders.add(key);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'not newest first and not a named exception:\n${offenders.join('\n')}',
      );
      // An exception that no longer exists should be deleted from the list above.
      final stale = _allowed.keys.where((k) => !found.contains(k)).toList();
      expect(
        stale,
        isEmpty,
        reason: 'listed but no longer in the code: $stale',
      );
    },
  );

  test('the work queues are oldest first, everything else newest first', () {
    String read(String p) =>
        File(p).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      read('lib/data/models/staff_order_row.dart'),
      contains('oldestFirst(result, (r) => r.createdAt)'),
    );
    expect(
      read('lib/core/utils/listing_order.dart'),
      contains('...oldestFirst(grouped.sublist(0, end)'),
    );
    expect(
      read('lib/data/repositories/farmer_program_repository.dart'),
      contains("order('created_at', ascending: false)"),
    );
    // The merged order lists are newest first before any queue filter is applied.
    expect(
      read('lib/data/models/staff_order_row.dart'),
      contains('b.createdAt.compareTo(a.createdAt)'),
    );
    expect(
      read('lib/data/models/consumer_order_row.dart'),
      contains('compareTo'),
    );
  });
}
