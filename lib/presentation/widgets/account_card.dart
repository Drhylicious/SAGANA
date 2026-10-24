import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/farmer_member_model.dart';
import '../../data/repositories/account_management_repository.dart';
import 'profile_avatar.dart';

/// The words shown on an account's status badge: Active, Inactive or
/// Suspended. The stored status is `active` or `suspended`; Inactive is the
/// derived "active but no activity for 30 days" state, worked out by the same
/// rule the Members list uses (see [AccountEntry.effectiveStatus]).
String accountStatusLabel(AppLocalizations l10n, AccountEntry account) {
  switch (account.effectiveStatus) {
    case MemberStatus.active:
      return l10n.farmerMgmtStatusActiveLabel;
    case MemberStatus.inactive:
      return l10n.analyticsInactive;
    case MemberStatus.suspended:
      return l10n.farmerMgmtStatusSuspendedLabel;
    default:
      final s = account.status;
      return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

Color accountStatusColor(ColorScheme cs, MemberStatus status) {
  switch (status) {
    case MemberStatus.active:
      return AppConstants.successGreen;
    case MemberStatus.suspended:
      return AppConstants.errorRed;
    default:
      return cs.outline;
  }
}

/// One account in Manage Accounts: photo (initials when there is none), full
/// name, a status badge, then the e-mail address and the phone number, each on
/// its own line. A missing e-mail or phone reads "Not set". Nothing is cut off:
/// long names and addresses wrap onto further lines.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.account, required this.onTap});

  final AccountEntry account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final statusColor = accountStatusColor(cs, account.effectiveStatus);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(
              photoUrl: account.profilePhotoUrl,
              displayName: account.name,
              radius: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            account.name,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          accountStatusLabel(l10n, account).toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _ContactLine(
                    icon: Icons.email_outlined,
                    value: account.email,
                    notSet: l10n.pendingNotSet,
                    cs: cs,
                  ),
                  const SizedBox(height: 3),
                  _ContactLine(
                    icon: Icons.phone_outlined,
                    value: account.phone,
                    notSet: l10n.pendingNotSet,
                    cs: cs,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({
    required this.icon,
    required this.value,
    required this.notSet,
    required this.cs,
  });

  final IconData icon;
  final String? value;
  final String notSet;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hasValue ? value!.trim() : notSet,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.35,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
              color: hasValue
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
