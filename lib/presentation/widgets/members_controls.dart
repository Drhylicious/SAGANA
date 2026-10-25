import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';

/// One status filter chip: label, live count, and whether it is the selected one.
class MembersStatusChip {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const MembersStatusChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });
}

/// The controls at the top of Manager → Members, in three rows:
///   1. Add Member | Manage Accounts   (two equal buttons)
///   2. Search bar | Filter button      (same height, side by side)
///   3. Status chips                    (one line, scrolls sideways, never wraps)
///
/// The screen keeps this block pinned above the list, so search and the status
/// filter stay in reach while the list scrolls.
class MembersControls extends StatelessWidget {
  final String addLabel;
  final String manageLabel;
  final VoidCallback onAddTap;
  final VoidCallback onManageTap;

  final TextEditingController searchController;
  final String searchHint;

  final VoidCallback onFilterTap;

  /// A filter other than the default is applied: the button gets a dot.
  final bool filterActive;

  final List<MembersStatusChip> chips;

  const MembersControls({
    super.key,
    required this.addLabel,
    required this.manageLabel,
    required this.onAddTap,
    required this.onManageTap,
    required this.searchController,
    required this.searchHint,
    required this.onFilterTap,
    required this.filterActive,
    required this.chips,
  });

  /// One height for the search field and the filter button, and one for both
  /// action buttons, so each row reads as a single aligned strip.
  static const double actionHeight = 46;
  static const double fieldHeight = 48;
  static const double chipHeight = 36;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Row 1: Add Member | Manage Accounts ──────────────────────────────
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                key: const ValueKey('members-add'),
                label: addLabel,
                icon: Icons.add_rounded,
                filled: true,
                onTap: onAddTap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                key: const ValueKey('members-manage'),
                label: manageLabel,
                icon: Icons.manage_accounts_rounded,
                filled: false,
                onTap: onManageTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Row 2: Search | Filter ───────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _SearchField(
                controller: searchController,
                hint: searchHint,
              ),
            ),
            const SizedBox(width: 10),
            _FilterButton(onTap: onFilterTap, active: filterActive),
          ],
        ),
        const SizedBox(height: 12),

        // ── Row 3: status chips, one line, horizontal scroll ─────────────────
        SizedBox(
          height: chipHeight,
          child: ListView.separated(
            key: const ValueKey('members-chips'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _StatusChipView(data: chips[i]),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final fg = filled ? cs.onPrimary : cs.primary;
    return Material(
      color: filled ? cs.primary : sagana.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          height: MembersControls.actionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: filled
                ? null
                : Border.all(color: cs.primary.withValues(alpha: 0.45)),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 6),
              // Scales down instead of ellipsizing: a longer translation
              // ("Pamahalaan ang mga Account") still reads in full.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _SearchField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MembersControls.fieldHeight,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          key: const ValueKey('members-search'),
          controller: controller,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    key: const ValueKey('members-search-clear'),
                    icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                    onPressed: controller.clear,
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;

  const _FilterButton({required this.onTap, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Semantics(
      button: true,
      label: 'Filter',
      child: GestureDetector(
        key: const ValueKey('members-filter'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: MembersControls.fieldHeight,
              height: MembersControls.fieldHeight,
              decoration: BoxDecoration(
                color: active
                    ? cs.primary.withValues(alpha: 0.10)
                    : sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: active
                      ? cs.primary.withValues(alpha: 0.55)
                      : cs.outline.withValues(alpha: 0.25),
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 22,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            if (active)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  key: const ValueKey('members-filter-dot'),
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: sagana.cardBackground, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChipView extends StatelessWidget {
  final MembersStatusChip data;

  const _StatusChipView({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final selected = data.selected;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: data.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? data.color.withValues(alpha: 0.14)
                : sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(
              color: selected
                  ? data.color.withValues(alpha: 0.55)
                  : cs.outline.withValues(alpha: 0.18),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: data.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${data.label}: ',
                maxLines: 1,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? data.color : cs.onSurfaceVariant,
                ),
              ),
              Text(
                '${data.count}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? data.color : cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
