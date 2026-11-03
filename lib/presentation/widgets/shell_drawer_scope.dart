import 'package:flutter/material.dart';

/// Lets a primary tab open the role's ONE navigation drawer.
///
/// The drawer belongs to the tab shell (see ShellScaffold), not to each tab's
/// own Scaffold. A drawer inside a tab's Scaffold only covers that tab's area,
/// so the bottom navigation stays tappable while it is open: switching tabs then
/// leaves it open on the tab you left (out of sight), and it reappears when you
/// come back. A shell-level drawer covers the whole screen, bottom navigation
/// included, and the same drawer is reachable from every primary tab.
class ShellDrawerScope extends InheritedWidget {
  final VoidCallback openDrawer;

  const ShellDrawerScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  static ShellDrawerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellDrawerScope>();

  @override
  bool updateShouldNotify(ShellDrawerScope oldWidget) => false;
}

/// Opens the navigation drawer from a primary tab's top bar: the shell's drawer
/// when the screen sits in a shell, otherwise the nearest Scaffold's own drawer.
void openNavigationDrawer(BuildContext context) {
  final scope = ShellDrawerScope.maybeOf(context);
  if (scope != null) {
    scope.openDrawer();
  } else {
    Scaffold.maybeOf(context)?.openDrawer();
  }
}
