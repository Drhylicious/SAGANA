import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import 'profile_avatar.dart';

/// One farmer in a list the Manager picks from: photo (or initials), name, an
/// optional line of context under it and an optional trailing value. Used by
/// Record Payment's farmer list and Issue New Loan's farmer picker, so choosing
/// a farmer looks the same in both.
///
/// [selected] outlines the tile in the primary colour and shows a check;
/// [dimmed] is for a farmer who cannot be chosen (no [onTap]).
class FarmerPickTile extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  const FarmerPickTile({
    super.key,
    required this.name,
    this.photoUrl,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    final tile = Material(
      color: selected
          ? cs.primary.withValues(alpha: 0.06)
          : sagana.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.12),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              ProfileAvatar(photoUrl: photoUrl, displayName: name, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: subtitleColor ?? cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
              ] else if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );

    return dimmed ? Opacity(opacity: 0.6, child: tile) : tile;
  }
}
