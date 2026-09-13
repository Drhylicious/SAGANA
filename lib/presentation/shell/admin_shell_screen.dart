import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/hive_service.dart';
import '../widgets/admin_bottom_nav.dart';

/// Hosts the admin tab navigators with a shared bottom nav bar.
///
/// Branches (fixed): 0 Dashboard · 1 Members · 2 Marketplace · 3 Loans ·
/// 4 Reports. An Officer (Issue 6 / Decision D19) does NOT get the Members
/// tab — the branch still exists but its nav button is hidden and the
/// visible index is mapped around branch 1.
class AdminShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdminShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    AppTheme.applySystemOverlay(context);

    final hideMembers = HiveService.isOfficer;
    final visibleBranches =
        hideMembers ? const [0, 2, 3, 4] : const [0, 1, 2, 3, 4];

    var displayIndex = visibleBranches.indexOf(navigationShell.currentIndex);
    if (displayIndex < 0) displayIndex = 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AdminBottomNav(
        hideMembers: hideMembers,
        currentIndex: displayIndex,
        onTap: (index) {
          final branch = visibleBranches[index];
          navigationShell.goBranch(
            branch,
            initialLocation: branch == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}
