import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';

/// Shared Recent Activity building blocks used by the Farmer, Buyer, Admin
/// and Officer activity screens. Each role supplies its own data and labels;
/// the look (search, chips, date groups, cards, badges, empty state) is the
/// same everywhere.

/// Colour family for the status badge. Callers decide the tone from their own
/// data, not from the label text, so the colour survives translation.
enum RecentActivityTone { neutral, success, warning, alert }

/// Colour family for the leading icon circle.
enum RecentActivityIconTone { primary, accent, neutral, alert, info }

class RecentActivityFilterOption<T> {
  final T value;
  final String label;

  const RecentActivityFilterOption({required this.value, required this.label});
}

class RecentActivitySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const RecentActivitySearchBar({
    super.key,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppConstants.outline,
        ),
        suffixIcon: value.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: controller.clear,
              ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      ),
    );
  }
}

class RecentActivityFilterChips<T> extends StatelessWidget {
  final List<RecentActivityFilterOption<T>> options;
  final T active;
  final ValueChanged<T> onSelected;

  const RecentActivityFilterChips({
    super.key,
    required this.options,
    required this.active,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((option) {
          final isActive = option.value == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryGreen
                      : Colors.white.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                    color: isActive
                        ? AppConstants.primaryGreen
                        : Colors.white.withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF455A64).withValues(alpha: 0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  option.label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Colors.white
                        : AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Uppercase section label ("TODAY", "YESTERDAY", a date) above a group.
class RecentActivityDateHeader extends StatelessWidget {
  final String label;
  final EdgeInsets padding;

  const RecentActivityDateHeader({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.only(bottom: 10, top: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppConstants.outline,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class RecentActivityDateGroup extends StatelessWidget {
  final String label;
  final List<Widget> cards;

  const RecentActivityDateGroup({
    super.key,
    required this.label,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecentActivityDateHeader(label: label),
        ...cards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: card,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class RecentActivityCard extends StatelessWidget {
  final IconData icon;
  final RecentActivityIconTone iconTone;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String? valueLabel;
  final String? statusLabel;
  final RecentActivityTone statusTone;
  final bool isAlert;
  // Replaces the tone icon when a card needs its own artwork (e.g. a product photo).
  final Widget? leading;
  // Overrides the tone colour for the icon and status badge (module colours).
  final Color? accentColor;
  // Navigable rows show a chevron and respond to taps.
  final VoidCallback? onTap;

  const RecentActivityCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.iconTone = RecentActivityIconTone.primary,
    this.valueLabel,
    this.statusLabel,
    this.statusTone = RecentActivityTone.neutral,
    this.isAlert = false,
    this.leading,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading ??
                  RecentActivityIcon(
                    icon: icon,
                    tone: iconTone,
                    color: accentColor,
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppConstants.charcoal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          recentActivityTime(timestamp),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _RecentActivityCardBottom(
                      valueLabel: valueLabel,
                      statusLabel: statusLabel,
                      statusTone: statusTone,
                      statusColor: accentColor,
                      isAlert: isAlert,
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppConstants.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// Today shows the clock time; earlier days show the date.
String recentActivityTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final itemDay = DateTime(dt.year, dt.month, dt.day);
  if (itemDay == today) {
    return DateFormat('h:mm a').format(dt);
  }
  return DateFormat('MMM d').format(dt);
}

class _RecentActivityCardBottom extends StatelessWidget {
  final String? valueLabel;
  final String? statusLabel;
  final RecentActivityTone statusTone;
  final Color? statusColor;
  final bool isAlert;

  const _RecentActivityCardBottom({
    required this.valueLabel,
    required this.statusLabel,
    required this.statusTone,
    required this.statusColor,
    required this.isAlert,
  });

  @override
  Widget build(BuildContext context) {
    if (valueLabel == null && statusLabel == null) {
      return const SizedBox.shrink();
    }

    Widget? statusBadge;
    if (statusLabel != null) {
      statusBadge = RecentActivityStatusBadge(
        label: statusLabel!,
        tone: isAlert ? RecentActivityTone.alert : statusTone,
        color: statusColor,
      );
    }

    if (valueLabel == null) {
      return statusBadge!;
    }

    final valueText = Text(
      valueLabel!,
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: isAlert ? AppConstants.errorRed : AppConstants.charcoal,
      ),
    );

    if (statusBadge == null) return valueText;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [valueText, statusBadge],
    );
  }
}

class RecentActivityStatusBadge extends StatelessWidget {
  final String label;
  final RecentActivityTone tone;
  final Color? color;

  const RecentActivityStatusBadge({
    super.key,
    required this.label,
    this.tone = RecentActivityTone.neutral,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ??
        switch (tone) {
          RecentActivityTone.alert => AppConstants.errorRed,
          RecentActivityTone.warning => AppConstants.warningAmber,
          RecentActivityTone.success => AppConstants.successGreen,
          RecentActivityTone.neutral => AppConstants.primaryGreen,
        };
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: badgeColor,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class RecentActivityIcon extends StatelessWidget {
  final IconData icon;
  final RecentActivityIconTone tone;
  final Color? color;

  const RecentActivityIcon({
    super.key,
    required this.icon,
    this.tone = RecentActivityIconTone.primary,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = color != null
        ? (color!.withValues(alpha: 0.12), color!)
        : switch (tone) {
            RecentActivityIconTone.primary => (
                AppConstants.primaryContainer.withValues(alpha: 0.10),
                AppConstants.primaryGreen,
              ),
            RecentActivityIconTone.accent => (
                AppConstants.secondaryContainer.withValues(alpha: 0.10),
                AppConstants.amber,
              ),
            RecentActivityIconTone.neutral => (
                AppConstants.outline.withValues(alpha: 0.10),
                AppConstants.outline,
              ),
            RecentActivityIconTone.info => (
                AppConstants.buyerBlue.withValues(alpha: 0.10),
                AppConstants.buyerBlue,
              ),
            RecentActivityIconTone.alert => (
                AppConstants.errorRed.withValues(alpha: 0.10),
                AppConstants.errorRed,
              ),
          };
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 26, color: fg),
    );
  }
}

class RecentActivityEmptyState extends StatelessWidget {
  final bool hasSearch;
  final String emptyTitle;
  final String emptyHint;
  final String noMatchTitle;
  final String noMatchHint;

  const RecentActivityEmptyState({
    super.key,
    required this.hasSearch,
    required this.emptyTitle,
    required this.emptyHint,
    required this.noMatchTitle,
    required this.noMatchHint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off_rounded : Icons.inbox_outlined,
            size: 56,
            color: AppConstants.outline.withValues(alpha: 0.50),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? noMatchTitle : emptyTitle,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch ? noMatchHint : emptyHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
          ),
        ],
      ),
    );
  }
}

/// Convenience for screens that take their empty-state copy from the
/// generated activity keys.
RecentActivityEmptyState recentActivityEmptyState(
  BuildContext context, {
  required bool hasSearch,
}) {
  final l10n = AppLocalizations.of(context);
  return RecentActivityEmptyState(
    hasSearch: hasSearch,
    emptyTitle: l10n.activityEmptyTitle,
    emptyHint: l10n.activityEmptyHint,
    noMatchTitle: l10n.activityNoMatchTitle,
    noMatchHint: l10n.activityNoMatchHint,
  );
}
