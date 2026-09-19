import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'animated_pressable.dart';
import 'material_list_tile.dart';
import 'web_safe_blur_container.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';

export 'farmer_top_bar.dart';
export 'disposal_action_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GlassCard
// ─────────────────────────────────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? backgroundColor;
  final double blurSigma;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = AppConstants.radiusLg,
    this.backgroundColor,
    this.blurSigma = 20,
  });

  @override
  Widget build(BuildContext context) {
    final sagana =
        Theme.of(context).extension<SaganaColors>() ?? SaganaColors.light;

    // WebSafeBlurContainer only clips as a rectangle (Clip.antiAlias on a
    // ClipRect, not ClipRRect) — GlassCard needs rounded corners on the
    // blur itself, so an outer ClipRRect rounds the final composited
    // result. Nesting a stricter rounded clip outside a looser
    // rectangular one still produces correctly rounded corners.
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: WebSafeBlurContainer(
        blurSigma: blurSigma,
        padding: padding ?? const EdgeInsets.all(AppConstants.spacingGutter),
        decoration: BoxDecoration(
          color: backgroundColor ?? sagana.glassBackground,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: sagana.glassBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PrimaryButton
// ─────────────────────────────────────────────────────────────────────────────

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool useGradient;
  final IconData? icon;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.useGradient = true,
    this.icon,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedPressable(
      onTap: isLoading ? null : onPressed,
      scaleDown: 0.97,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: useGradient && onPressed != null
                ? AppConstants.primaryButtonGradient
                : null,
            color: useGradient ? null : cs.primary,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: cs.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: cs.onPrimary),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppTextField
// ─────────────────────────────────────────────────────────────────────────────

class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextCapitalization textCapitalization;
  final int maxLines;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscureText,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, size: 20, color: cs.outline)
            : null,
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: cs.outline,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConfirmDialog — shared confirm/cancel pattern, used via AppDialog.show<bool>
// from Buyer/Admin/Farmer Settings (clear cache, sign out). Previously three
// near-identical private _ConfirmDialog classes. cancelLabel stays a
// parameter (mirroring confirmLabel) rather than a fixed string, so each
// caller's current behavior carries over unchanged — Admin already localizes
// it (l10n.issueLoanCancel); Buyer/Farmer keep the existing default and can
// move to a localized string later without another widget change.
// ─────────────────────────────────────────────────────────────────────────────

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel))),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: confirmLabel, height: 44, onPressed: () => Navigator.pop(context, true))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OfflineBanner
// ─────────────────────────────────────────────────────────────────────────────

class OfflineBanner extends StatelessWidget {
  // Default message is a safe fallback; callers should pass a
  // screen-accurate message via the `message` parameter.
  final String? message;

  const OfflineBanner({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingGutter,
        vertical: AppConstants.spacingSm,
      ),
      color: AppConstants.warningAmber,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message ?? 'You\'re offline',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PriorityCard
// ─────────────────────────────────────────────────────────────────────────────

enum PrioritySeverity { info, warning, critical }

class PriorityItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final PrioritySeverity severity;
  final VoidCallback onTap;

  const PriorityItem({
    required this.title,
    this.subtitle,
    required this.icon,
    this.severity = PrioritySeverity.info,
    required this.onTap,
  });
}

class PriorityCard extends StatelessWidget {
  final List<PriorityItem> items;
  final String allClearTitle;
  final String allClearMessage;

  const PriorityCard({
    super.key,
    required this.items,
    required this.allClearTitle,
    required this.allClearMessage,
  });

  Color _severityColor(PrioritySeverity severity) {
    switch (severity) {
      case PrioritySeverity.critical:
        return AppConstants.errorRed;
      case PrioritySeverity.warning:
        return AppConstants.warningAmber;
      case PrioritySeverity.info:
        return AppConstants.midGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return GlassCard(
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.successGreen,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allClearTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.successGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    allClearMessage,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final isLast = entry.key == items.length - 1;
          final item = entry.value;
          final color = _severityColor(item.severity);

          return AnimatedPressable(
            onTap: item.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppConstants.spacingMd,
                horizontal: AppConstants.spacingSm,
              ),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: cs.outline.withValues(alpha: 0.12),
                        ),
                      ),
              ),
              child: Row(
                children: [
                  Icon(item.icon, color: color, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        if (item.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: cs.outline, size: 20),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QuickActionButton
// ─────────────────────────────────────────────────────────────────────────────

class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedPressable(
        onTap: onTap,
        scaleDown: 0.95,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spacingMd,
          ),
          decoration: BoxDecoration(
            color: AppConstants.primaryContainer.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: AppConstants.primaryGreen.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppConstants.primaryGreen, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StatusStepper — shared listing-pipeline progress indicator
// Used on the Marketplace landing page, Create Listing (preview), and
// Listing Success screens so the same visual thread runs through the flow.
// ─────────────────────────────────────────────────────────────────────────────

class StatusStepper extends StatelessWidget {
  /// Index of the furthest-reached step (inclusive, shown as green).
  /// Pass -1 for "not started yet" (all steps shown as upcoming/grey) —
  /// used on Create Listing as a preview of what's about to happen.
  final int currentStep;
  final List<String> labels;

  const StatusStepper({
    super.key,
    required this.currentStep,
    this.labels = const ['Submitted', 'Under Review', 'Live'],
  });

  /// Maps a marketplace_listings.status value to the right step index,
  /// matching the workflow in supabase_schema_marketplace.sql.
  factory StatusStepper.forListingStatus(String status) {
    return StatusStepper(currentStep: status == 'approved' ? 2 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final lineIndex = i ~/ 2;
          final isDone = lineIndex < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              color: isDone
                  ? AppConstants.primaryGreen
                  : AppConstants.outline.withValues(alpha: 0.20),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final isDone = stepIndex <= currentStep;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? AppConstants.primaryGreen
                    : AppConstants.outline.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              labels[stepIndex],
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isDone
                    ? AppConstants.primaryGreen
                    : AppConstants.outline,
              ),
            ),
          ],
        );
      }),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// SectionLabel — small uppercase header above a grouped settings/profile
// section. Replaces the four near-identical private _SectionLabel classes
// previously duplicated in admin_profile_screen.dart (as a method),
// buyer_account_screen.dart, buyer_edit_profile_screen.dart,
// buyer_settings_screen.dart, and farmer_settings_screen.dart.
// ─────────────────────────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String label;
  final double bottomSpacing;

  const SectionLabel({
    super.key,
    required this.label,
    this.bottomSpacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: bottomSpacing),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SettingsCard / SettingsRow — the grouped-row settings container used by
// every Profile/Settings screen. Replaces admin_profile_screen.dart's
// _settingsCard()/_settingsRow() methods, buyer_settings_screen.dart's
// _SettingsCard/_SettingsRow, and farmer_settings_screen.dart's
// _SettingsCard/_SettingsRow — three previously-independent copies of the
// same UI. SettingsRow is built on the existing MaterialListTile so ripple
// behavior comes from there rather than a fourth reimplementation.
// ─────────────────────────────────────────────────────────────────────────────

class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool showChevron;
  // Overrides the chevron with a custom control (e.g. a Switch) for rows
  // that toggle a setting directly rather than navigating/opening a picker.
  final Widget? trailing;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.titleColor,
    this.showChevron = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MaterialListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: titleColor ?? cs.onSurface),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant))
          : null,
      trailing: trailing ?? (showChevron ? Icon(Icons.chevron_right_rounded, color: cs.outline, size: 18) : null),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.10),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ToggleRow — settings row with a trailing Switch instead of a chevron.
// Currently only Farmer Settings needs this (notification preferences),
// but shared here so Admin/Buyer can adopt the same visual language if
// they gain toggleable preferences later, rather than a role reimplementing it.
// ─────────────────────────────────────────────────────────────────────────────

class ToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SignOutButton — the one Sign Out / Log Out control for all three roles.
// Matches Buyer's existing pill treatment exactly (previously only Buyer
// had this; Admin used a full-width SettingsRow, Farmer TBD per its own
// private widget) so container, spacing, size, and radius are now identical
// everywhere it appears.
// ─────────────────────────────────────────────────────────────────────────────

class SignOutButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const SignOutButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppConstants.errorRed.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout_rounded, color: AppConstants.errorRed, size: 18),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppConstants.errorRed)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBrandingBlock — the SAGANA info/version footer. Consolidates the two
// previously-duplicated copies in farmer_settings_screen.dart and
// buyer_settings_screen.dart into one. Position within each screen is up
// to the caller — Farmer's placement moves to below Sign Out (Buyer's
// position) as part of this same change.
// ─────────────────────────────────────────────────────────────────────────────

class AppBrandingBlock extends StatelessWidget {
  const AppBrandingBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: sagana.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: sagana.cardBackground.withValues(alpha: 0.50)),
        boxShadow: [BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppConstants.primaryGreen, AppConstants.primaryContainer]),
              ),
              child: const Icon(Icons.agriculture_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 12),
            Text('SAGANA', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
            Text(l10n.brandingTagline,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 6),
            Text('v1.0.0', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppConstants.amber, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 14),
            Text(l10n.brandingDevelopedBy,
                textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
            Text(l10n.brandingPartner,
                textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppConstants.onSurface)),
          ],
        ),
      ),
    );
  }
}