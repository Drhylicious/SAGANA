import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sagana/presentation/shell/shell_scaffold.dart';
import 'package:sagana/presentation/widgets/shell_drawer_scope.dart';

/// A primary tab: no drawer of its own, a "menu" button that opens the shell's.
class _Tab extends StatelessWidget {
  final String name;
  const _Tab(this.name);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (c) => TextButton(
        onPressed: () => openNavigationDrawer(c),
        child: Text('menu-$name'),
      ),
    ),
  );
}

GoRouter _router({List<String> tabs = const ['A', 'B', 'C']}) => GoRouter(
  initialLocation: '/${tabs.first}',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => ShellScaffold(
        drawer: const Drawer(child: Text('the-drawer')),
        body: shell,
        bottomNavigationBar: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              TextButton(
                onPressed: () => shell.goBranch(i),
                child: Text('tab-${tabs[i]}'),
              ),
          ],
        ),
      ),
      branches: [
        for (final t in tabs)
          StatefulShellBranch(
            routes: [GoRoute(path: '/$t', builder: (c, s) => _Tab(t))],
          ),
      ],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

bool _drawerShown(WidgetTester tester) =>
    find.text('the-drawer').hitTestable().evaluate().isNotEmpty;

void main() {
  group('one drawer for every primary tab', () {
    testWidgets('the same drawer opens from each tab', (tester) async {
      await _pump(tester, _router());

      for (final tab in ['A', 'B', 'C']) {
        await tester.tap(find.text('tab-$tab'));
        await tester.pumpAndSettle();
        expect(_drawerShown(tester), isFalse);

        await tester.tap(find.text('menu-$tab'));
        await tester.pumpAndSettle();
        expect(_drawerShown(tester), isTrue, reason: 'tab $tab');

        // Close it again by tapping the scrim.
        await tester.tapAt(const Offset(780, 300));
        await tester.pumpAndSettle();
        expect(_drawerShown(tester), isFalse);
      }
    });

    testWidgets('an open drawer covers the bottom navigation', (tester) async {
      await _pump(tester, _router());
      await tester.tap(find.text('menu-A'));
      await tester.pumpAndSettle();

      // The tabs can no longer be tapped, so the drawer cannot be left open
      // behind a tab switch.
      expect(find.text('tab-B').hitTestable().evaluate(), isEmpty);
    });

    testWidgets('back closes the drawer and stays on the tab', (tester) async {
      await _pump(tester, _router());
      await tester.tap(find.text('tab-B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('menu-B'));
      await tester.pumpAndSettle();
      expect(_drawerShown(tester), isTrue);

      // The system back button.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(_drawerShown(tester), isFalse);
      expect(find.text('menu-B'), findsOneWidget); // still on tab B
    });

    testWidgets('switching tabs never leaves a drawer behind', (tester) async {
      await _pump(tester, _router());
      await tester.tap(find.text('menu-A'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(780, 300)); // close
      await tester.pumpAndSettle();

      await tester.tap(find.text('tab-B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab-A'));
      await tester.pumpAndSettle();

      expect(_drawerShown(tester), isFalse);
    });

    testWidgets('a screen outside a shell falls back to its own drawer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: const Drawer(child: Text('the-drawer')),
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => openNavigationDrawer(c),
                child: const Text('menu'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(_drawerShown(tester), isTrue);
    });
  });

  group('every role is wired the same way (source)', () {
    String read(String path) => File(path).readAsStringSync();

    test('each role shell owns its drawer through ShellScaffold', () {
      for (final shell in ['farmer', 'admin', 'buyer']) {
        final src = read('lib/presentation/shell/${shell}_shell_screen.dart');
        expect(src, contains('ShellScaffold('), reason: shell);
        expect(src, contains('drawer:'), reason: shell);
      }
      // Manager and Officer use the one Admin shell.
      expect(
        read('lib/presentation/shell/admin_shell_screen.dart'),
        contains('AdminShellDrawer'),
      );
    });

    test('top bars open the shell drawer, not the nearest Scaffold', () {
      for (final bar in ['farmer', 'admin', 'buyer']) {
        final src = read('lib/presentation/widgets/${bar}_top_bar.dart');
        expect(src, contains('openNavigationDrawer(context)'), reason: bar);
        expect(src, isNot(contains('Scaffold.of(context).openDrawer()')));
      }
    });

    test('no primary tab declares a drawer of its own', () {
      const tabs = [
        'farmer/farmer_dashboard_screen',
        'farmer/harvest_hub_screen',
        'farmer/my_listings_screen',
        'farmer/farmer_analytics_screen',
        'farmer/farmer_profile_screen',
        'admin/admin_dashboard_screen',
        'admin/farmer_management_screen',
        'admin/marketplace_dashboard_screen',
        'admin/loan_dashboard_screen',
        'admin/operational_reports_screen',
        'buyer/marketplace_browse_screen',
        'buyer/my_orders_screen',
        'buyer/price_monitoring_screen',
        'buyer/buyer_account_screen',
      ];
      for (final tab in tabs) {
        final src = read('lib/presentation/screens/$tab.dart');
        expect(src, isNot(contains('drawer:')), reason: tab);
        expect(src, isNot(contains('AppNavigationDrawer(')), reason: tab);
      }
    });

    test('every primary tab still has the menu enabled on its top bar', () {
      const tabs = [
        'farmer/farmer_dashboard_screen',
        'farmer/harvest_hub_screen',
        'farmer/my_listings_screen',
        'farmer/farmer_analytics_screen',
        'farmer/farmer_profile_screen',
        'admin/admin_dashboard_screen',
        'admin/farmer_management_screen',
        'admin/marketplace_dashboard_screen',
        'admin/loan_dashboard_screen',
        'admin/operational_reports_screen',
        'buyer/marketplace_browse_screen',
        'buyer/my_orders_screen',
        'buyer/price_monitoring_screen',
        'buyer/buyer_account_screen',
      ];
      for (final tab in tabs) {
        final src = read('lib/presentation/screens/$tab.dart');
        expect(src, contains('enableMenu: true'), reason: tab);
      }
    });
  });
}
