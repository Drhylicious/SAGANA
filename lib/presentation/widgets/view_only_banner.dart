import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/staff_permission_service.dart';
import 'app_toast.dart';
import 'staff_access_matrix.dart' show staffModuleLabel;

/// True when the signed-in staff member may take management actions in
/// [module]. The Manager always may. This only decides what the app SHOWS: the
/// database refuses the write anyway.
bool canManageModule(StaffModule module) =>
    StaffPermissions.instance.canManage(module);

/// Guard for the start of a handler that changes data: returns true when the
/// signed-in staff member may manage [module]; otherwise tells them why not and
/// returns false (`if (!requireManage(context, m)) return;`).
bool requireManage(BuildContext context, StaffModule module) {
  if (canManageModule(module)) return true;
  showViewOnlyMessage(context);
  return false;
}

/// Tells a View Only Officer why a management action is unavailable. Call it
/// from a tap handler that is not disabled, or wherever a database refusal for
/// view-only access is caught.
void showViewOnlyMessage(BuildContext context) {
  AppToast.show(
    context,
    AppLocalizations.of(context).staffViewOnlyAction,
    isError: true,
  );
}

/// Rebuilds [builder] whenever the signed-in staff member's access changes, so
/// buttons enable or disable the moment the Manager edits the permission.
class StaffAccessBuilder extends StatelessWidget {
  const StaffAccessBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, StaffPermissions access) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: StaffPermissions.instance,
    builder: (context, _) => builder(context, StaffPermissions.instance),
  );
}

/// A slim strip shown above the bottom navigation while the signed-in Officer
/// only has View Only access to [module] ("Members · View Only"). Tapping it
/// explains what View Only means. Renders nothing for the Manager or for an
/// Officer who manages the module.
class ViewOnlyStrip extends StatelessWidget {
  const ViewOnlyStrip({super.key, required this.module});

  final StaffModule module;

  @override
  Widget build(BuildContext context) {
    return StaffAccessBuilder(
      builder: (context, access) {
        if (access.canManage(module)) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: AppConstants.warningAmber.withValues(alpha: 0.16),
          child: InkWell(
            onTap: () => AppToast.show(context, l10n.staffViewOnlyBanner),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 15,
                    color: AppConstants.snackbarWarning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${staffModuleLabel(l10n, module)} · ${l10n.staffAccessView}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A one-line notice shown at the top of a module's screens while the signed-in
/// Officer only has View Only access to [module]. Renders nothing otherwise.
class ViewOnlyBanner extends StatelessWidget {
  const ViewOnlyBanner({super.key, required this.module});

  final StaffModule module;

  @override
  Widget build(BuildContext context) {
    return StaffAccessBuilder(
      builder: (context, access) {
        if (access.canManage(module)) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppConstants.warningAmber.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: AppConstants.warningAmber.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: AppConstants.snackbarWarning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).staffViewOnlyBanner,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
