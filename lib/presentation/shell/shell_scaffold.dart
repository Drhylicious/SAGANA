import 'package:flutter/material.dart';
import '../widgets/shell_drawer_scope.dart';

/// The Scaffold every role's tab shell uses: the tab content, the bottom
/// navigation, and the role's single navigation [drawer].
///
/// The drawer is owned here, once, so it is the same drawer on every primary tab
/// and it covers the bottom navigation while it is open (see ShellDrawerScope).
class ShellScaffold extends StatefulWidget {
  final Widget body;
  final Widget bottomNavigationBar;
  final Widget drawer;

  /// Called when the drawer opens or closes (for example to refresh the profile
  /// shown in it).
  final ValueChanged<bool>? onDrawerChanged;

  const ShellScaffold({
    super.key,
    required this.body,
    required this.bottomNavigationBar,
    required this.drawer,
    this.onDrawerChanged,
  });

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: widget.drawer,
      onDrawerChanged: widget.onDrawerChanged,
      body: ShellDrawerScope(
        openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        child: widget.body,
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }
}
