import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/hive_service.dart';
import '../../routes/app_routes.dart';

/// Members is Admin-only. Officers do not open farmer details or the Members
/// list, so these helpers do nothing for them. Admins are unaffected.
void pushFarmerDetails(BuildContext context, Object? farmerId) {
  if (HiveService.isOfficer) return;
  context.push(AppRoutes.farmerDetails, extra: farmerId);
}

void goMembersList(BuildContext context) {
  if (HiveService.isOfficer) return;
  context.go(AppRoutes.farmerManagement);
}

/// False for Officers. Use it to turn off a tap that would open a Members screen.
bool get membersAccessAllowed => !HiveService.isOfficer;
