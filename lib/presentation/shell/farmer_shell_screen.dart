import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/farmer_bottom_nav.dart';

/// Hosts the 5 farmer tab navigators with a shared bottom nav bar.
class FarmerShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const FarmerShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    AppTheme.applySystemOverlay(context);

    return Scaffold(
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
