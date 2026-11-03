import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../routes/app_routes.dart';

/// The Members screens are open to the Manager and to every Officer. What an
/// Officer may do there is decided by their Members level (View Only or
/// Manage); see StaffPermissions.
void pushFarmerDetails(BuildContext context, Object? farmerId) {
  context.push(AppRoutes.farmerDetails, extra: farmerId);
}

void goMembersList(BuildContext context) {
  context.go(AppRoutes.farmerManagement);
}

/// Kept for the callers that guard a tap that opens a Members screen. Members
/// is no longer Manager-only, so this is always true.
bool get membersAccessAllowed => true;
