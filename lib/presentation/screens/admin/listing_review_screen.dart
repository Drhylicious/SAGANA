import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../routes/app_routes.dart';

class ListingReviewScreen extends StatefulWidget {
  final String listingId;
  const ListingReviewScreen({super.key, required this.listingId});

  @override
  State<ListingReviewScreen> createState() => _ListingReviewScreenState();
}

class _ListingReviewScreenState extends State<ListingReviewScreen> {
  final _repo = AdminListingRepository();

  AdminListingModel? _listing;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final listing = await _repo.fetchListingById(widget.listingId);
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _isLoading = false;
    });
  }

  // ── Decision actions ────────────────────────────────────────────────────────

  Future<void> _approve() async {
    setState(() => _isSaving = true);
    try {
      await _repo.approveListing(widget.listingId);
      if (!mounted) return;
      _showSnack('Listing approved and published.', isSuccess: true);
      context.pop(true);
    } catch (_) {
      setState(() => _isSaving = false);
      _showSnack('Failed to approve. Please try again.');
    }
  }

  void _showRequestChangesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteSheet(
        title: 'Request Changes',
        hint: 'Describe what the farmer needs to fix...',
        actionLabel: 'Send Request',
        actionColor: AppConstants.warningAmber,
        onConfirm: (note) async {
          Navigator.pop(context);
          setState(() => _isSaving = true);
          try {
            await _repo.requestChanges(
              listingId: widget.listingId,
              notes: note,
            );
            if (!mounted) return;
            _showSnack(
              'Changes requested. Farmer has been notified.',
              isSuccess: true,
            );
            context.pop(true);
          } catch (_) {
            setState(() => _isSaving = false);
            _showSnack('Failed to send request. Please try again.');
          }
        },
      ),
    );
  }

  void _showRejectSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteSheet(
        title: 'Reject Submission',
        hint: 'Provide a reason for rejection...',
        actionLabel: 'Confirm Rejection',
        actionColor: AppConstants.errorRed,
        onConfirm: (reason) async {
          Navigator.pop(context);
          setState(() => _isSaving = true);
          try {
            await _repo.rejectListing(
              listingId: widget.listingId,
              reason: reason,
            );
            if (!mounted) return;
            _showSnack('Listing rejected.', isSuccess: false);
            context.pop(true);
          } catch (_) {
            setState(() => _isSaving = false);
            _showSnack('Failed to reject. Please try again.');
          }
        },
      ),
    );
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isSuccess
            ? AppConstants.successGreen
            : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryGreen),
        ),
      );
    }

    if (_listing == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: BackButton(color: cs.primary),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: cs.outline),
              const SizedBox(height: 12),
              Text(
                'Listing not found',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final listing = _listing!;
    final isPending = listing.isPending;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── Scrollable content ──────────────────────────────────────
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  children: [
                    // ── Hero / listing overview ───────────────────────
                    _HeroSection(listing: listing, cs: cs, sagana: sagana),
                    const SizedBox(height: 20),

                    // ── Pricing Analysis ──────────────────────────────
                    _SectionCard(
                      icon: Icons.payments_outlined,
                      title: 'Pricing Analysis',
                      cs: cs,
                      sagana: sagana,
                      child: _PricingAnalysis(listing: listing, cs: cs),
                    ),
                    const SizedBox(height: 14),

                    // ── Inventory Validation ──────────────────────────
                    _SectionCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Inventory Validation',
                      cs: cs,
                      sagana: sagana,
                      child: _InventoryValidation(listing: listing, cs: cs),
                    ),
                    const SizedBox(height: 14),

                    // ── Farmer Context ────────────────────────────────
                    _SectionCard(
                      icon: Icons.person_outlined,
                      title: 'Farmer Context',
                      cs: cs,
                      sagana: sagana,
                      child: _FarmerContext(listing: listing, cs: cs),
                    ),

                    // ── Existing admin notes (if any) ─────────────────
                    if (listing.adminNotes != null &&
                        listing.adminNotes!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SectionCard(
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Admin Notes',
                        cs: cs,
                        sagana: sagana,
                        child: _AdminNotesCard(
                          notes: listing.adminNotes!,
                          cs: cs,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              title: 'Listing Review',
              status: listing.statusLabel,
              isPending: isPending,
              onBack: () => context.pop(false),
              sagana: sagana,
              cs: cs,
            ),
          ),

          // ── Fixed footer actions (only for pending listings) ────────
          if (isPending)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _ReviewFooter(
                isSaving: _isSaving,
                onApprove: _approve,
                onRequestChanges: _showRequestChangesSheet,
                onReject: _showRejectSheet,
                cs: cs,
                sagana: sagana,
              ),
            )
          else
            // Read-only footer for non-pending listings
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _ReadOnlyFooter(listing: listing, cs: cs, sagana: sagana),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final String title;
  final String status;
  final bool isPending;
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({
    required this.title,
    required this.status,
    required this.isPending,
    required this.onBack,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              _StatusBadge(label: status, isPending: isPending, cs: cs),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => context.push(AppRoutes.marketLinking),
                icon: const Icon(Icons.link_rounded, size: 16),
                label: Text(
                  'Market Linking',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isPending;
  final ColorScheme cs;
  const _StatusBadge({
    required this.label,
    required this.isPending,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPending
        ? AppConstants.warningAmber
        : AppConstants.successGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Section
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _HeroSection({
    required this.listing,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusLg),
            ),
            child: Stack(
              children: [
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: listing.listingPhotoUrl != null
                      ? Image.network(
                          listing.listingPhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _PhotoFallback(cs: cs),
                        )
                      : _PhotoFallback(cs: cs),
                ),
                // Grade badge overlay
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      'Grade A',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.variety != null
                      ? '${listing.cropName} — ${listing.variety}'
                      : listing.cropName,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${listing.cropName}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      listing.submittedLabel,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Farmer avatar + name
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.primaryContainer,
                      ),
                      child: Center(
                        child: Text(
                          listing.farmerName.isNotEmpty
                              ? listing.farmerName[0].toUpperCase()
                              : 'F',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      listing.farmerName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• Batch #${listing.id.substring(0, 8).toUpperCase()}',
                      style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  final ColorScheme cs;
  const _PhotoFallback({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.eco_outlined,
          size: 48,
          color: cs.outline.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pricing Analysis
// ─────────────────────────────────────────────────────────────────────────────

class _PricingAnalysis extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  const _PricingAnalysis({required this.listing, required this.cs});

  @override
  Widget build(BuildContext context) {
    final hasRef = listing.marketRefPricePerKg != null;
    final pct = listing.priceDiffPercent;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PriceBox(
                label: "Farmer's Asking",
                price: listing.pricePerKg,
                cs: cs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PriceBox(
                label: hasRef ? 'Market Ref (DA)' : 'No Market Ref',
                price: listing.marketRefPricePerKg,
                cs: cs,
                muted: !hasRef,
              ),
            ),
          ],
        ),
        if (hasRef && pct != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: listing.isPriceWithinMarketRange
                  ? AppConstants.successGreen.withValues(alpha: 0.08)
                  : AppConstants.errorRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: listing.isPriceWithinMarketRange
                    ? AppConstants.successGreen.withValues(alpha: 0.25)
                    : AppConstants.errorRed.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  listing.isPriceWithinMarketRange
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: listing.isPriceWithinMarketRange
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    listing.isPriceWithinMarketRange
                        ? 'Within market range'
                        : 'Price deviates significantly from market',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: listing.isPriceWithinMarketRange
                          ? AppConstants.successGreen
                          : AppConstants.errorRed,
                    ),
                  ),
                ),
                Text(
                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: listing.isPriceWithinMarketRange
                        ? AppConstants.successGreen
                        : AppConstants.errorRed,
                  ),
                ),
              ],
            ),
          ),
        ] else if (!hasRef) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Text(
              'No market reference price available for ${listing.cropName}. '
              'Add a price record in Price Management.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PriceBox extends StatelessWidget {
  final String label;
  final double? price;
  final ColorScheme cs;
  final bool muted;
  const _PriceBox({
    required this.label,
    this.price,
    required this.cs,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
          ),
          const SizedBox(height: 4),
          price != null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₱${price!.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: muted ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                    Text(
                      '/kg',
                      style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
                    ),
                  ],
                )
              : Text(
                  '—',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.outline,
                  ),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inventory Validation
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryValidation extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  const _InventoryValidation({required this.listing, required this.cs});

  @override
  Widget build(BuildContext context) {
    final hasBatch = listing.batchAvailableKg != null;
    final hasWarning = listing.hasStockWarning;

    return Column(
      children: [
        _ValidationRow(
          label: 'Listing Quantity',
          value: '${listing.volumeKg.toStringAsFixed(0)} kg',
          cs: cs,
          valueColor: cs.onSurface,
        ),
        const SizedBox(height: 8),
        _ValidationRow(
          label: 'Batch Available',
          value: hasBatch
              ? '${listing.batchAvailableKg!.toStringAsFixed(0)} kg'
              : 'No batch linked',
          cs: cs,
          valueColor: hasWarning
              ? cs.error
              : (hasBatch ? AppConstants.successGreen : cs.outline),
        ),
        if (hasBatch) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: hasWarning
                  ? 1.0
                  : (listing.volumeKg / listing.batchAvailableKg!).clamp(
                      0.0,
                      1.0,
                    ),
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                hasWarning ? cs.error : AppConstants.successGreen,
              ),
            ),
          ),
        ],
        if (hasWarning) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: cs.error.withValues(alpha: 0.20)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Listing quantity exceeds batch stock by '
                    '${listing.stockSurplus.toStringAsFixed(0)} kg',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (hasBatch) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: AppConstants.successGreen.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppConstants.successGreen,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Quantity is within available batch stock',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.successGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!hasBatch) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.warningAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Text(
              'No inventory batch is linked to this listing. '
              'The farmer may not have recorded a harvest batch.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ValidationRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final Color valueColor;
  const _ValidationRow({
    required this.label,
    required this.value,
    required this.cs,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Context
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerContext extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  const _FarmerContext({required this.listing, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Submission stats
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCell(
                      value: '${listing.farmerTotalSubmissions}',
                      label: 'Submissions',
                      color: cs.onSurface,
                      cs: cs,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
                  Expanded(
                    child: _StatCell(
                      value: '${listing.farmerApprovedCount}',
                      label: 'Approved',
                      color: AppConstants.successGreen,
                      cs: cs,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
                  Expanded(
                    child: _StatCell(
                      value: '${listing.farmerRejectedCount}',
                      label: 'Rejected',
                      color: cs.error,
                      cs: cs,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Approval Rate',
                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
                  ),
                  Text(
                    '${listing.farmerApprovalRate}%',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Outstanding loan
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: listing.farmerOutstandingLoan > 0
                ? cs.errorContainer.withValues(alpha: 0.20)
                : AppConstants.successGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: listing.farmerOutstandingLoan > 0
                  ? cs.error.withValues(alpha: 0.20)
                  : AppConstants.successGreen.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Outstanding Loan',
                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
              ),
              Text(
                listing.farmerOutstandingLoan > 0
                    ? '₱${listing.farmerOutstandingLoan.toStringAsFixed(2)}'
                    : 'No loans',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: listing.farmerOutstandingLoan > 0
                      ? cs.error
                      : AppConstants.successGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final ColorScheme cs;
  const _StatCell({
    required this.value,
    required this.label,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Notes Card
// ─────────────────────────────────────────────────────────────────────────────

class _AdminNotesCard extends StatelessWidget {
  final String notes;
  final ColorScheme cs;
  const _AdminNotesCard({required this.notes, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        notes,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Review Footer (for pending listings)
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewFooter extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onApprove;
  final VoidCallback onRequestChanges;
  final VoidCallback onReject;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ReviewFooter({
    required this.isSaving,
    required this.onApprove,
    required this.onRequestChanges,
    required this.onReject,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(top: BorderSide(color: sagana.glassBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Request Changes
                  Expanded(
                    child: GestureDetector(
                      onTap: isSaving ? null : onRequestChanges,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppConstants.warningAmber),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 16,
                              color: AppConstants.warningAmber,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Request Changes',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppConstants.warningAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Approve
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: isSaving ? null : onApprove,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: isSaving
                              ? AppConstants.successGreen.withValues(
                                  alpha: 0.50,
                                )
                              : AppConstants.successGreen,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppConstants.successGreen.withValues(
                                alpha: 0.25,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: isSaving
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Approve Listing',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Reject (full width, text button style)
              GestureDetector(
                onTap: isSaving ? null : onReject,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cancel_outlined, size: 16, color: cs.error),
                      const SizedBox(width: 6),
                      Text(
                        'Reject Submission',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.error,
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Read-Only Footer (for approved / changes_required / sold listings)
// ─────────────────────────────────────────────────────────────────────────────

class _ReadOnlyFooter extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ReadOnlyFooter({
    required this.listing,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(top: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(
                    listing.status,
                    cs,
                  ).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _statusIcon(listing.status),
                      size: 16,
                      color: _statusColor(listing.status, cs),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      listing.statusLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(listing.status, cs),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This listing is ${listing.statusLabel.toLowerCase()} — no action needed.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s, ColorScheme cs) {
    switch (s) {
      case 'approved':
        return AppConstants.successGreen;
      case 'changes_required':
        return AppConstants.warningAmber;
      case 'sold':
        return cs.onSurfaceVariant;
      default:
        return cs.outline;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'approved':
        return Icons.check_circle_outline_rounded;
      case 'changes_required':
        return Icons.edit_note_rounded;
      case 'sold':
        return Icons.sell_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Note Bottom Sheet (shared for Request Changes + Reject)
// ─────────────────────────────────────────────────────────────────────────────

class _NoteSheet extends StatefulWidget {
  final String title;
  final String hint;
  final String actionLabel;
  final Color actionColor;
  final Future<void> Function(String note) onConfirm;

  const _NoteSheet({
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.actionColor,
    required this.onConfirm,
  });

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _ctrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ctrl,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              contentPadding: const EdgeInsets.all(14),
            ),
            style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: cs.outline.withValues(alpha: 0.30),
                      ),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () async {
                          if (_ctrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a note.'),
                              ),
                            );
                            return;
                          }
                          setState(() => _isSaving = true);
                          await widget.onConfirm(_ctrl.text.trim());
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _isSaving
                          ? widget.actionColor.withValues(alpha: 0.50)
                          : widget.actionColor,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: _isSaving
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            widget.actionLabel,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
