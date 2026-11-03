import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/guest_mode_service.dart';
import '../widgets/farmer_bottom_nav.dart';
import '../widgets/guest_navigation_drawer.dart';
import 'role_drawers.dart';
import 'shell_scaffold.dart';

/// Hosts the 5 farmer tab navigators with a shared bottom nav bar and the
/// Farmer's one navigation drawer.
class FarmerShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const FarmerShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    AppTheme.applySystemOverlay(context);

    return ShellScaffold(
      drawer: ListenableBuilder(
        listenable: GuestModeService.instance,
        builder: (_, __) => GuestModeService.active
            ? const GuestNavigationDrawer(role: GuestRole.farmer)
            : const FarmerShellDrawer(),
      ),
      body: navigationShell,
      bottomNavigationBar: FarmerBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
