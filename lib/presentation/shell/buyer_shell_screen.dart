import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/buyer_bottom_nav.dart';

/// Shell for the Buyer role's 4-tab bottom navigation
/// (Browse / Orders / Prices / Account). Mirrors FarmerShellScreen and
/// AdminShellScreen's StatefulShellRoute structure.
class BuyerShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const BuyerShellScreen({super.key, required this.navigationShell});

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the already-active tab pops back to its root.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BuyerBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}
