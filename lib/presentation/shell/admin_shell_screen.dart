import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/staff_permission_service.dart';
import '../widgets/admin_bottom_nav.dart';
import '../widgets/view_only_banner.dart';
import 'role_drawers.dart';
import 'shell_scaffold.dart';

/// Hosts the admin tab navigators with a shared bottom nav bar and the one
/// navigation drawer Manager and Officer share.
///
/// Branches (fixed): 0 Dashboard · 1 Members · 2 Marketplace · 3 Loans ·
/// 4 Reports. The Manager and every Officer see all five tabs; an Officer's
/// per-module level (View Only / Manage) only changes what the screens let
/// them do. While an Officer is on a tab whose module is View Only, a slim
/// strip above the navigation bar says so.
class AdminShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdminShellScreen({super.key, required this.navigationShell});

  // Branch index -> the permission module of that tab.
  static const _branchModules = [
    StaffModule.dashboard,
    StaffModule.members,
    StaffModule.marketplace,
    StaffModule.loans,
    StaffModule.reports,
  ];

  @override
  Widget build(BuildContext context) {
    AppTheme.applySystemOverlay(context);

    final index = navigationShell.currentIndex;
    final module = index >= 0 && index < _branchModules.length
        ? _branchModules[index]
        : StaffModule.dashboard;

    return ShellScaffold(
      drawer: const AdminShellDrawer(),
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ViewOnlyStrip(module: module),
          AdminBottomNav(
            currentIndex: index,
            onTap: (i) => navigationShell.goBranch(
              i,
              initialLocation: i == navigationShell.currentIndex,
            ),
          ),
        ],
      ),
    );
  }
}
