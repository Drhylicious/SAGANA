import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/harvest_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Crop Filter Chips
// ─────────────────────────────────────────────────────────────────────────────

class HarvestCropChips extends StatelessWidget {
  final List<String> options;
  final String active;
  final ValueChanged<String> onSelected;

  const HarvestCropChips({
    super.key,
    required this.options,
    required this.active,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((crop) {
          final isActive = crop == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(crop),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer.withValues(alpha: 0.12)
                      : sagana.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: isActive
                      ? Border.all(
                          color: AppConstants.primaryContainer.withValues(
                            alpha: 0.30,
                          ),
                        )
                      : null,
                ),
                child: Text(
                  crop,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? AppConstants.primaryContainer
                        : cs.onSurfaceVariant,
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

// ─────────────────────────────────────────────────────────────────────────────
// Summary Stats
// ─────────────────────────────────────────────────────────────────────────────

class HarvestSummaryStats extends StatelessWidget {
  final Map<String, double> stats;
  final bool isLoading;

  const HarvestSummaryStats({
    super.key,
    required this.stats,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: l10n.harvestSummaryTotalLabel,
            value: isLoading ? '—' : _fmtYield(stats['total_yield'] ?? 0),
            unit: 'kg',
            valueColor: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: l10n.reportsSynced,
            value: isLoading
                ? '—'
                : (stats['synced_percent'] ?? 100).toStringAsFixed(0),
            unit: '%',
            valueColor: AppConstants.successGreen,
          ),
        ),
      ],
    );
  }

  String _fmtYield(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: sagana.glassBorder),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log Entry
// ─────────────────────────────────────────────────────────────────────────────

class HarvestLogEntry extends StatelessWidget {
  final HarvestModel harvest;
  // Was never wired to any crop lookup at all — this row always showed the
  // generic leaf icon regardless of whether the crop actually had a photo
  // (the harvest detail sheet, which does receive the crop, showed the
  // real photo correctly — the bug was specifically this list row).
  // Optional and defaults to null so existing callers that don't pass a
  // crop lookup keep their current icon-only appearance unchanged.
  final String? imageUrl;
  const HarvestLogEntry({super.key, required this.harvest, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);
    // Solid card recipe (matches Admin's All Listings / Loan Item Catalog
    // cards) — replaces the previous near-invisible glass style
    // (sagana.glassBackground at ~70% white on an off-white screen
    // background read as "no visible container" in practice). Shared by
    // both Farmer Harvest History and Admin's harvest screens
    // (harvest_report_screen.dart, farmer_harvest_history_screen.dart),
    // which also reuse this widget.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Container(
              width: 48,
              height: 48,
              color: AppConstants.primaryGreen.withValues(alpha: 0.10),
              child: imageUrl != null
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.eco_rounded,
                        color: AppConstants.primaryGreen,
                        size: 24,
                      ),
                    )
                  : const Icon(
                      Icons.eco_rounded,
                      color: AppConstants.primaryGreen,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  harvest.variety != null && harvest.variety!.isNotEmpty
                      ? '${harvest.cropName} (${harvest.variety})'
                      : harvest.cropName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  harvest.batchNumber != null
                      ? 'Batch #${harvest.batchNumber} • ${harvest.quantityKg.toStringAsFixed(0)}kg'
                      : '${harvest.quantityKg.toStringAsFixed(0)}kg',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      (harvest.isSynced
                              ? AppConstants.successGreen
                              : AppConstants.warningAmber)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      harvest.isSynced
                          ? Icons.check_circle_rounded
                          : Icons.sync_rounded,
                      size: 11,
                      color: harvest.isSynced
                          ? AppConstants.successGreen
                          : AppConstants.warningAmber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      harvest.isSynced
                          ? l10n.reportsSynced
                          : l10n.adminDashKpiPending,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: harvest.isSynced
                            ? AppConstants.successGreen
                            : AppConstants.warningAmber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                DateFormat('MMM d, h:mm a').format(harvest.harvestDate),
                style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
