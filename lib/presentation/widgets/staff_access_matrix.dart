import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/services/staff_permission_service.dart';

/// Display name of a permission module, in the current language.
String staffModuleLabel(AppLocalizations l10n, StaffModule module) {
  switch (module) {
    case StaffModule.dashboard:
      return l10n.adminNavDashboard;
    case StaffModule.members:
      return l10n.adminNavMembers;
    case StaffModule.marketplace:
      return l10n.navMarketplace;
    case StaffModule.loans:
      return l10n.adminNavLoans;
    case StaffModule.reports:
      return l10n.adminNavReports;
  }
}

String _moduleDescription(AppLocalizations l10n, StaffModule module) {
  switch (module) {
    case StaffModule.dashboard:
      return l10n.staffModuleDashboardDesc;
    case StaffModule.members:
      return l10n.staffModuleMembersDesc;
    case StaffModule.marketplace:
      return l10n.staffModuleMarketplaceDesc;
    case StaffModule.loans:
      return l10n.staffModuleLoansDesc;
    case StaffModule.reports:
      return l10n.staffModuleReportsDesc;
  }
}

IconData _moduleIcon(StaffModule module) {
  switch (module) {
    case StaffModule.dashboard:
      return Icons.dashboard_rounded;
    case StaffModule.members:
      return Icons.groups_rounded;
    case StaffModule.marketplace:
      return Icons.storefront_outlined;
    case StaffModule.loans:
      return Icons.request_quote_outlined;
    case StaffModule.reports:
      return Icons.bar_chart_rounded;
  }
}

/// One row per module with a View Only / Manage selector.
class StaffAccessMatrix extends StatelessWidget {
  const StaffAccessMatrix({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final Map<StaffModule, StaffAccess> value;
  final void Function(StaffModule module, StaffAccess access) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final module in StaffModule.values) ...[
          _Row(
            module: module,
            access: value[module] ?? StaffAccess.view,
            enabled: enabled,
            onChanged: (a) => onChanged(module, a),
          ),
          if (module != StaffModule.values.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.module,
    required this.access,
    required this.enabled,
    required this.onChanged,
  });

  final StaffModule module;
  final StaffAccess access;
  final bool enabled;
  final ValueChanged<StaffAccess> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final manage = access == StaffAccess.manage;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: manage
                ? AppConstants.primaryGreen.withValues(alpha: 0.45)
                : cs.outline.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_moduleIcon(module), size: 20, color: AppConstants.primaryGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    staffModuleLabel(l10n, module),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _moduleDescription(l10n, module),
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<StaffAccess>(
                key: ValueKey('access-${module.key}'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: StaffAccess.view,
                    label: Text(l10n.staffAccessView),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: StaffAccess.manage,
                    label: Text(l10n.staffAccessManage),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                  ),
                ],
                selected: {access},
                onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
