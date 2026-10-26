import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/member_title_row.dart';

import 'support/ignore_font_errors.dart';

/// Name | status | menu on one line, vertically centred, on every card.

Widget _badge(String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: Colors.amber.withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(99),
  ),
  // The real badge's size (9 pt); the test font is much wider than the app's.
  child: Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
    style: const TextStyle(fontSize: 9),
  ),
);

Widget _menu() => const SizedBox(width: 36, height: 36, child: Icon(Icons.more_vert_rounded, size: 22));

Future<void> _pump(WidgetTester tester, {required List<(String, String)> cards, double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 52, height: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MemberTitleRow(name: c.$1, badge: _badge(c.$2), menu: _menu()),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

Rect _r(WidgetTester t, String key, int i) =>
    t.getRect(find.byKey(ValueKey(key)).at(i));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('name, status and menu share one line: name left, status toward the right, menu at the far edge, centred together', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, cards: const [('Ellen Angela Rosal', 'PENDING')]);
      final name = _r(tester, 'member-card-name', 0);
      final badge = _r(tester, 'member-card-badge', 0);
      final menu = _r(tester, 'member-card-menu', 0);
      expect(name.left, lessThan(badge.left));
      expect(badge.right, lessThan(menu.left));
      // One line: the three centres coincide.
      expect((name.center.dy - badge.center.dy).abs(), lessThan(1.5));
      expect((badge.center.dy - menu.center.dy).abs(), lessThan(1.5));
      // The row is as tall as the menu's tap target, no taller: the card stays short.
      expect(menu.height, MemberTitleRow.rowHeight);
      // The menu is the right-most thing: its edge is the row's edge.
      final row = tester.getRect(find.byType(MemberTitleRow).first);
      expect((menu.right - row.right).abs(), lessThan(0.5));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the same layout on every status: identical menu position, row height and badge position', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(
        tester,
        cards: const [
          ('Aldrin Requiz', 'ACTIVE'),
          ('Genroj Laguna', 'PENDING'),
          ('Kei Amane', 'INACTIVE'),
          ('Miku Nakano', 'SUSPENDED'),
          ('Itsuki Nakano', 'DISAPPROVED'),
        ],
      );
      final menus = [for (var i = 0; i < 5; i++) _r(tester, 'member-card-menu', i)];
      final rows = [for (var i = 0; i < 5; i++) tester.getRect(find.byType(MemberTitleRow).at(i))];
      for (var i = 1; i < 5; i++) {
        expect((menus[i].left - menus[0].left).abs(), lessThan(0.5), reason: 'menu x, card $i');
        expect((rows[i].height - rows[0].height).abs(), lessThan(0.5), reason: 'row height, card $i');
      }
      // Each badge hugs its own text: a short label is a short badge.
      final active = _r(tester, 'member-card-badge', 0);
      final disapproved = _r(tester, 'member-card-badge', 4);
      expect(active.width, lessThan(disapproved.width));
      // ...and sits right before the menu on every card (right-aligned group).
      for (var i = 0; i < 5; i++) {
        expect(_r(tester, 'member-card-menu', i).left - _r(tester, 'member-card-badge', i).right, lessThan(4));
      }
    });
  });

  testWidgets('the badge stays compact: a very long label is capped and cut, never allowed to crowd the name', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(
        tester,
        cards: const [('Maria Concepcion Alessandra', 'NAKABINBING NA APLIKANTE NG PAMAYANAN')],
        width: 320,
      );
      final badge = _r(tester, 'member-card-badge', 0);
      expect(badge.width, lessThanOrEqualTo(MemberTitleRow.maxBadgeWidth));
      expect(_r(tester, 'member-card-name', 0).width, greaterThan(40));
      expect(tester.takeException(), isNull);
    });
  });

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('a very long name wraps inside its own space at ${width.toInt()} px: it never overlaps the badge or the menu', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          cards: const [
            ('Maria Concepcion Alessandra Dela Cruz-Villanueva de los Santos III', 'PENDING'),
            ('Jo', 'ACTIVE'),
          ],
          width: width,
        );
        final name = _r(tester, 'member-card-name', 0);
        final badge = _r(tester, 'member-card-badge', 0);
        final menu = _r(tester, 'member-card-menu', 0);
        expect(name.right, lessThanOrEqualTo(badge.left), reason: 'no overlap with the badge');
        expect(badge.right, lessThanOrEqualTo(menu.left + 0.5), reason: 'no overlap with the menu');
        // At most two lines, and the badge/menu stay centred on the (taller) name block.
        final oneLine = _r(tester, 'member-card-name', 1).height;
        expect(name.height, lessThanOrEqualTo(oneLine * 2 + 1));
        expect((badge.center.dy - name.center.dy).abs(), lessThan(1.5));
        expect((menu.center.dy - name.center.dy).abs(), lessThan(1.5));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
