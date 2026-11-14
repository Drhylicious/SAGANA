import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../routes/app_routes.dart';

/// The Members screens are open to the Manager and to every Officer. What an
/// Officer may do there is decided by their Members level (View Only or
/// Manage); see StaffPermissions.
/// The Harvest tab of Farmer Details (see its TabBar order).
const int kFarmerDetailsHarvestTab = 1;

/// The Farmer Details address for [farmerId]. The id (and the tab) travel in
/// the address itself, so the screen still knows its Farmer after a browser
/// reload or a hot restart; a route "extra" does not survive either.
String farmerDetailsLocation(Object? farmerId, {int tab = 0}) => Uri(
  path: AppRoutes.farmerDetails,
  queryParameters: {
    'id': farmerId?.toString() ?? '',
    if (tab != 0) 'tab': '$tab',
  },
).toString();

/// Opens Farmer Details. [tab] opens it on that tab (0 = Profile, the default).
void pushFarmerDetails(BuildContext context, Object? farmerId, {int tab = 0}) {
  context.push(farmerDetailsLocation(farmerId, tab: tab));
}

void goMembersList(BuildContext context) {
  context.go(AppRoutes.farmerManagement);
}

/// Kept for the callers that guard a tap that opens a Members screen. Members
/// is no longer Manager-only, so this is always true.
bool get membersAccessAllowed => true;
