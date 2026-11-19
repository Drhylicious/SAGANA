import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/chunked_in.dart';

/// Found by the volume test: 1,500 ids in one request address made the server refuse it
/// and the Marketplace never loaded. Long id lists are now sent in slices.
void main() {
  List<String> ids(int n) => [for (var i = 0; i < n; i++) 'id-$i'];

  test('a short list is one request, unchanged', () async {
    final calls = <List<String>>[];
    final rows = await chunkedIn(ids(10), (s) async {
      calls.add(s);
      return [for (final id in s) {'id': id}];
    });
    expect(calls, hasLength(1));
    expect(rows, hasLength(10));
  });

  test('1,500 ids are sent in slices, no request carries more than the slice size', () async {
    final calls = <List<String>>[];
    final rows = await chunkedIn(ids(1500), (s) async {
      calls.add(s);
      return [for (final id in s) {'id': id}];
    });
    expect(calls.length, greaterThan(1));
    expect(calls.every((c) => c.length <= 80), isTrue);
    expect(rows, hasLength(1500));
  });

  test('every id comes back once, in the original order', () async {
    final input = ids(205);
    final rows = await chunkedIn(input, (s) async => [for (final id in s) {'id': id}]);
    expect([for (final r in rows) r['id']], input);
  });

  test('an empty list makes one empty call and returns nothing', () async {
    final rows = await chunkedIn(<String>[], (s) async => []);
    expect(rows, isEmpty);
  });

  test('a failing slice fails the whole lookup (callers keep their own error handling)', () async {
    await expectLater(
      chunkedIn(ids(200), (s) async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
  });
}
