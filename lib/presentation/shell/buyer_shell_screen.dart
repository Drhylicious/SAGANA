import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/buyer_profile_model.dart';
import '../../data/repositories/buyer_profile_repository.dart';
import '../../data/services/guest_mode_service.dart';
import '../widgets/buyer_bottom_nav.dart';
import '../widgets/guest_navigation_drawer.dart';
import 'role_drawers.dart';
import 'shell_scaffold.dart';

/// Shell for the Buyer role's 4-tab bottom navigation
/// (Browse / Orders / Prices / Account). Mirrors FarmerShellScreen and
/// AdminShellScreen's StatefulShellRoute structure, and owns the Buyer's one
/// navigation drawer.
class BuyerShellScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const BuyerShellScreen({super.key, required this.navigationShell});

  @override
  State<BuyerShellScreen> createState() => _BuyerShellScreenState();
}

class _BuyerShellScreenState extends State<BuyerShellScreen> {
  final _profileRepo = BuyerProfileRepository();
  BuyerProfileModel? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    GuestModeService.instance.addListener(_onGuestModeChanged);
  }

  @override
  void dispose() {
    GuestModeService.instance.removeListener(_onGuestModeChanged);
    super.dispose();
  }

  // Guest Mode ending (the visitor logged in) swaps the guest drawer for the
  // Buyer's own and loads their profile.
  void _onGuestModeChanged() {
    if (!mounted) return;
    _loadProfile();
    setState(() {});
  }

  // The drawer shows the Buyer's name, photo and contact details. Loaded when the
  // shell starts and again whenever the drawer opens, so an edit made on Edit
  // Profile is reflected the next time it is opened.
  Future<void> _loadProfile() async {
    // A signed-out guest has no profile to load.
    if (GuestModeService.active) return;
    final profile = await _profileRepo.fetchProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      // Tapping the already-active tab pops back to its root.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      drawer: GuestModeService.active
          ? const GuestNavigationDrawer(role: GuestRole.buyer)
          : BuyerShellDrawer(profile: _profile),
      onDrawerChanged: (open) {
        if (open) _loadProfile();
      },
      body: widget.navigationShell,
      bottomNavigationBar: BuyerBottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}
