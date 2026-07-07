import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/admin_bottom_nav.dart';

/// Hosts the 5 admin tab navigators with a shared bottom nav bar.
/// Mirrors [FarmerShellScreen] exactly.
class AdminShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdminShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    AppTheme.applySystemOverlay(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AdminBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
