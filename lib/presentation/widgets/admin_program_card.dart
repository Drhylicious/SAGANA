import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/program_model.dart';

/// How strongly a completed program is drawn (about 60%), so it reads as closed.
const double kCompletedProgramOpacity = 0.6;

/// The Manager / Officer program card (Program Management).
///
/// Layout: photo header with status, then what the program is (purpose,
/// benefit, the item it distributes), the figures that matter (members,
/// budget), an "Incomplete" notice when required details are missing, and one
/// action row — Members, History, Edit, Delete.
class AdminProgramCard extends StatelessWidget {
  final CooperativeProgram program;
  final Color accent;
  final IconData icon;
  final String statusLabel;
  final Color statusColor;
  final String memberCountLabel;
  /// Tapping the card: the read-only details of the program.
  final VoidCallback? onTap;
  final VoidCallback onMembers;
  final VoidCallback onHistory;
  final VoidCallback onEdit;
  // Mark as Completed. Green when everything is finished, grey while the program
  // still has unfinished work (tapping it then lists what is left).
  final VoidCallback onComplete;
  final ProgramCompletionStatus? completion;
  final VoidCallback? onProducts;

  const AdminProgramCard({
    super.key,
    required this.program,
    required this.accent,
    required this.icon,
    required this.statusLabel,
    required this.statusColor,
    required this.memberCountLabel,
    this.onTap,
    required this.onMembers,
    required this.onHistory,
    required this.onEdit,
    required this.onComplete,
    this.completion,
    this.onProducts,
  });

  static String fieldLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'name':
        return l10n.programMgmtFieldName;
      case 'type':
        return l10n.programMgmtFieldType;
      case 'photo':
        return l10n.programMgmtFieldPhoto;
      case 'description':
        return l10n.programMgmtFieldDescription;
      case 'budget':
        return l10n.programMgmtFieldBudget;
      case 'item':
        return l10n.programMgmtFieldItem;
      case 'sources':
        return l10n.programMgmtFieldSources;
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);
    final p = program;
    final hasPhoto = p.imageUrl != null && p.imageUrl!.isNotEmpty;
    final missing = p.missingFields;

    // A completed program is dimmed so it reads as closed beside the active ones.
    final dimmed = p.status == 'completed';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Photo header ────────────────────────────────────────────
          SizedBox(
            height: 124,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: dimmed ? kCompletedProgramOpacity : 1,
                  child: hasPhoto
                      ? Image.network(
                          p.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _PhotoPlaceholder(color: accent, icon: icon),
                        )
                      : _PhotoPlaceholder(color: accent, icon: icon),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _Pill(
                    label: statusLabel,
                    color: statusColor,
                    solid: true,
                  ),
                ),
                if (p.isIncomplete)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _Pill(
                      label: l10n.programMgmtIncompleteBadge,
                      color: AppConstants.warningAmber,
                      solid: true,
                      icon: Icons.error_outline_rounded,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Everything about the program is dimmed once it is completed; the status badge above
                // and the buttons below keep full strength so they stay easy to read and press.
                Opacity(
                  key: Key('programBody_${p.id}'),
                  opacity: dimmed ? kCompletedProgramOpacity : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      p.programName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Type · creation date (MM/DD/YY). Who created it is in the Accountability Log.
                      '${p.programType.isEmpty ? l10n.programMgmtCustomProgram : p.programType} · ${programCardDate(p)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Pill(
                          label: p.isSalesProgram
                              ? l10n.reportsProductSalesShort
                              : l10n.programMgmtFilterDistribution,
                          color: p.isSalesProgram
                              ? AppConstants.successGreen
                              : AppConstants.buyerBlue,
                        ),
                        if (p.hasMemberDiscount)
                          _Pill(
                            label: l10n.programMgmtMemberDiscountChip(
                              _pct(p.memberDiscountPercent),
                            ),
                            color: AppConstants.successGreen,
                          ),
                        if (p.hasCooperativeShare)
                          _Pill(
                            label:
                                'Return Percentage (${_pct(p.cooperativeSharePercent)}%)',
                            color: AppConstants.buyerBlue,
                          ),
                      ],
                    ),
                    if (p.description != null &&
                        p.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        p.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (!p.isSalesProgram) ...[
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.inventory_2_outlined,
                        // The categories it distributes from; an older program that still
                        // has one configured item keeps showing it.
                        text: p.sourceCategories.isNotEmpty
                            ? l10n.programMgmtDistributesFromLine(
                                p.sourceCategories.join(', '),
                              )
                            : p.distributionItemName != null
                            ? l10n.programMgmtDistributesLine(
                                p.distributionItemName!,
                              )
                            : l10n.programMgmtNoSourceSet,
                        trailing: p.sourceCategories.isEmpty &&
                                p.distributionItemName != null &&
                                p.distributionItemStock != null
                            ? l10n.programMgmtStockLine(
                                _qty(p.distributionItemStock!),
                                p.distributionItemUnit ?? '',
                              )
                            : null,
                        muted: p.sourceCategories.isEmpty &&
                            p.distributionItemName == null,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoRow(
                            icon: Icons.people_rounded,
                            text: memberCountLabel,
                          ),
                        ),
                        if (p.budget != null)
                          Expanded(
                            child: _InfoRow(
                              icon: Icons.account_balance_rounded,
                              text: l10n.programMgmtBudgetSuffix(
                                p.budget!.toStringAsFixed(0),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (missing.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppConstants.warningAmber.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          border: Border.all(
                            color: AppConstants.warningAmber.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: AppConstants.warningAmber,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.programMgmtMissingList(
                                  missing
                                      .map((k) => fieldLabel(l10n, k))
                                      .join(', '),
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: onEdit,
                              child: Text(
                                l10n.programMgmtCompleteAction,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.warningAmber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.group_rounded,
                        label: l10n.programMgmtManageMembersAction,
                        color: cs.primary,
                        filled: true,
                        onTap: onMembers,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.history_rounded,
                        label: l10n.programMgmtHistoryAction,
                        color: AppConstants.buyerBlue,
                        filled: false,
                        onTap: onHistory,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconAction(
                      icon: Icons.edit_rounded,
                      tooltip: l10n.programMgmtEditAction,
                      color: cs.onSurfaceVariant,
                      onTap: onEdit,
                    ),
                    if (p.status != 'completed') ...[
                      const SizedBox(width: 6),
                      _IconAction(
                        icon: Icons.check_circle_outline_rounded,
                        tooltip: (completion?.isReady ?? false)
                            ? l10n.programMgmtCompleteReady
                            : l10n.programMgmtCompleteNotReady,
                        color: (completion?.isReady ?? false)
                            ? AppConstants.successGreen
                            : cs.outline.withValues(alpha: 0.7),
                        onTap: onComplete,
                      ),
                    ],
                  ],
                ),
                if (onProducts != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _ActionButton(
                      icon: Icons.storefront_rounded,
                      label: l10n.programMgmtManageProductsAction,
                      color: AppConstants.successGreen,
                      filled: false,
                      onTap: onProducts!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// MM/DD/YY of the day the program was created (an older row without it falls back to
  /// its season year).
  static String programCardDate(CooperativeProgram p) {
    final d = p.createdAt;
    if (d == null) return '${p.seasonYear}';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${two(d.year % 100)}';
  }

  static String _pct(double v) => formatQuantity(v); // up to 2 decimals, as the database keeps them

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _PhotoPlaceholder extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _PhotoPlaceholder({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(icon, size: 40, color: color.withValues(alpha: 0.7)),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool solid;
  final IconData? icon;
  const _Pill({
    required this.label,
    required this.color,
    this.solid = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? trailing;
  final bool muted;
  const _InfoRow({
    required this.icon,
    required this.text,
    this.trailing,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: muted ? FontWeight.w400 : FontWeight.w500,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              color: muted ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            maxLines: 1,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: filled ? 0.10 : 0.0),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: color.withValues(alpha: filled ? 0.0 : 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
