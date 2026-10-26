import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/members_controls.dart';

import 'support/ignore_font_errors.dart';

/// Manager → Members controls: Add | Manage on row 1, Search | Filter on row 2,
/// status chips on row 3 (one line, scrolls sideways).

class _Host extends StatefulWidget {
  final String add;
  final String manage;
  final bool filterActive;
  final List<String> events;
  const _Host({
    this.add = 'Add Member',
    this.manage = 'Manage Accounts',
    this.filterActive = false,
    required this.events,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final search = TextEditingController();
  int selected = 0;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const names = ['All', 'Active', 'Inactive', 'Suspended', 'Pending', 'Disapproved'];
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: MembersControls(
          addLabel: widget.add,
          manageLabel: widget.manage,
          onAddTap: () => widget.events.add('add'),
          onManageTap: () => widget.events.add('manage'),
          searchController: search,
          searchHint: 'Search farmer name...',
          onFilterTap: () => widget.events.add('filter'),
          filterActive: widget.filterActive,
          chips: [
            for (var i = 0; i < names.length; i++)
              MembersStatusChip(
                label: names[i],
                count: i + 1,
                color: i == 0 ? cs.primary : Colors.green,
                selected: selected == i,
                onTap: () {
                  widget.events.add('chip:${names[i]}');
                  setState(() => selected = i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Host host, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: host,
    ),
  );
  await tester.pump();
}

Rect _r(WidgetTester t, String key) => t.getRect(find.byKey(ValueKey(key)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('row order: Add | Manage, then Search | Filter, then the chips', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, _Host(events: []));
      final add = _r(tester, 'members-add');
      final manage = _r(tester, 'members-manage');
      final search = _r(tester, 'members-search');
      final filter = _r(tester, 'members-filter');
      final chips = _r(tester, 'members-chips');

      // Row 1: one line, Add first, same size.
      expect((add.top - manage.top).abs(), lessThan(1));
      expect(add.right, lessThan(manage.left));
      expect((add.width - manage.width).abs(), lessThan(1));
      expect((add.height - manage.height).abs(), lessThan(1));
      // Row 2 is below row 1: the search field first, then the filter button.
      expect(search.top, greaterThan(add.bottom));
      expect((search.center.dy - filter.center.dy).abs(), lessThan(1));
      expect(search.right, lessThan(filter.left));
      // Same height, the filter is a square matching the field.
      expect((search.height - filter.height).abs(), lessThan(1));
      expect((filter.width - filter.height).abs(), lessThan(1));
      // Row 3 is below row 2.
      expect(chips.top, greaterThan(search.bottom));
      // Both rows span the same width, left and right edges aligned.
      expect((add.left - search.left).abs(), lessThan(1));
      expect((manage.right - filter.right).abs(), lessThan(1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('there is no "N Members" count pill', (tester) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, _Host(events: []));
      expect(find.textContaining(RegExp(r'\d+ Members')), findsNothing);
    });
  });

  testWidgets('the four actions work: Add, Manage, Filter, and each chip', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      final events = <String>[];
      await _pump(tester, _Host(events: events));
      await tester.tap(find.byKey(const ValueKey('members-add')));
      await tester.tap(find.byKey(const ValueKey('members-manage')));
      await tester.tap(find.byKey(const ValueKey('members-filter')));
      await tester.tap(find.textContaining('Active:').first);
      expect(events, ['add', 'manage', 'filter', 'chip:Active']);
    });
  });

  testWidgets('the chips stay on one line and scroll sideways to reach the last one', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      final events = <String>[];
      await _pump(tester, _Host(events: events), width: 320);
      final chipsBox = _r(tester, 'members-chips');
      // One row: every visible chip shares the strip's height.
      expect(chipsBox.height, MembersControls.chipHeight);
      // The last chip is off screen until scrolled.
      expect(find.textContaining('Disapproved:').hitTestable(), findsNothing);
      // A long flick: the test font is wider than the real one.
      await tester.drag(find.byKey(const ValueKey('members-chips')), const Offset(-3000, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Disapproved:').hitTestable(), findsOneWidget);
      await tester.tap(find.textContaining('Disapproved:'));
      expect(events, ['chip:Disapproved']);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('only the tapped chip is selected', (tester) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, _Host(events: []));
      Color border(String label) {
        final box = tester.widget<Container>(
          find.ancestor(of: find.textContaining('$label:'), matching: find.byType(Container)).first,
        );
        return ((box.decoration as BoxDecoration).border as Border).top.color;
      }

      final unselected = border('Inactive');
      expect(border('All'), isNot(unselected));
      await tester.ensureVisible(find.textContaining('Inactive:'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Inactive:'));
      await tester.pump();
      expect(border('Inactive'), isNot(unselected));
      // Back to the start of the strip: "All" is no longer the selected one.
      await tester.drag(find.byKey(const ValueKey('members-chips')), const Offset(3000, 0));
      await tester.pumpAndSettle();
      expect(border('All'), unselected);
    });
  });

  testWidgets('search: typing shows a clear button, which empties the field', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, _Host(events: []));
      expect(find.byKey(const ValueKey('members-search-clear')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('members-search')), 'aldrin');
      await tester.pump();
      expect(find.byKey(const ValueKey('members-search-clear')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('members-search-clear')));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('members-search'))).controller!.text,
        '',
      );
    });
  });

  testWidgets('the filter button shows a dot only while a filter is applied', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, _Host(events: []));
      expect(find.byKey(const ValueKey('members-filter-dot')), findsNothing);
      await _pump(tester, _Host(events: [], filterActive: true));
      expect(find.byKey(const ValueKey('members-filter-dot')), findsOneWidget);
    });
  });

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('no overflow at ${width.toInt()} px, even with long Tagalog labels', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          _Host(
            events: [],
            add: 'Magdagdag ng Miyembro',
            manage: 'Pamahalaan ang mga Account',
            filterActive: true,
          ),
          width: width,
        );
        expect(tester.takeException(), isNull);
        final add = _r(tester, 'members-add');
        final manage = _r(tester, 'members-manage');
        expect(manage.right, lessThanOrEqualTo(width - 20 + 0.5));
        expect(add.left, greaterThanOrEqualTo(20 - 0.5));
        expect((add.width - manage.width).abs(), lessThan(1));
      });
    });
  }

  group('Members screen', () {
    final src = File('lib/presentation/screens/admin/farmer_management_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('uses the new controls and no longer shows the member count', () {
      expect(src, contains('MembersControls('));
      expect(src, isNot(contains('farmerMgmtMembersCount')));
      expect(src, isNot(contains('FarmerManagementHeader')));
    });

    test('Add Member and Manage Accounts still open the same screens', () {
      expect(src, contains('onAddTap: _showAddMemberTypeSheet'));
      expect(src, contains('AppRoutes.manageAdminAccounts'));
      expect(src, contains('onFilterTap: _showFilterSheet'));
      expect(src, contains('_setStatusFilter('));
    });

    test('the controls are pinned above the list (outside the scrolling list)', () {
      final controls = src.indexOf('MembersControls(');
      final list = src.indexOf('RefreshIndicator(');
      expect(controls, isNonNegative);
      expect(controls, lessThan(list));
    });

    test('member card: name, status and menu are ONE line (MemberTitleRow), contact lines beneath', () {
      final row = src.indexOf('MemberTitleRow(');
      final name = src.indexOf('name: farmer.fullName', row);
      final badge = src.indexOf('badge: _StatusBadge(status: farmer.memberStatus', row);
      final menu = src.indexOf('menu: SizedBox(', row);
      final contact = src.indexOf('farmer.contactLines', row);
      expect(row, isNonNegative);
      expect(name, greaterThan(row));
      expect(badge, greaterThan(name));
      expect(menu, greaterThan(badge));
      expect(contact, greaterThan(menu), reason: 'the contact lines come after the title row');
      // The badge is no longer stacked under the name.
      expect(
        RegExp(r'SizedBox\(height: 5\),\s*_StatusBadge').hasMatch(src),
        isFalse,
      );
      // One popup menu per card, and it is inside the title row.
      expect('PopupMenuButton<String>('.allMatches(src.substring(src.indexOf('class _FarmerCard'))).length, 1);
    });
  });
}
