import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cooperative_offer_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';

/// Read-only detail view for a **Approved (confirmed) or Rejected
/// (declined)** cooperative offer — opened when an admin taps one of those
/// two outcomes from OfferToCooperativeScreen, mirroring how
/// OrderDetailScreen opens from OrderManagementScreen (same top-bar/section-
/// card conventions, same repository-owns-the-fetch shape).
///
/// Deliberately NOT reused for a `pending` offer — pending offers keep the
/// existing `_ReviewOfferSheet` review flow unchanged (confirm/decline with
/// the purchase-details form), which this screen has no equivalent for.
/// There is nothing left to *do* to a confirmed or declined offer — both are
/// terminal — so unlike OrderDetailScreen this screen has no bottom action
/// bar at all, only information.
class OfferDetailScreen extends StatefulWidget {
  final String offerId;
  const OfferDetailScreen({super.key, required this.offerId});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  final _repo = CooperativeOfferRepository();
  bool _isLoading = true;
  CooperativeOfferModel? _offer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final offer = await _repo.fetchOfferById(widget.offerId);
    if (!mounted) return;
    setState(() {
      _offer = offer;
      _isLoading = false;
    });
  }

  Color _statusColor(CooperativeOfferModel offer) {
    if (offer.isConfirmed) return AppConstants.successGreen;
    if (offer.isDeclined) return AppConstants.errorRed;
    return AppConstants.warningAmber;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopBar(
            title: _offer != null ? '${_offer!.cropName} Offer' : 'Offer Details',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                : _offer == null
                    ? Center(
                        child: Text('Offer not found',
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    : RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                            _buildStatusCard(_offer!, cs),
                            const SizedBox(height: 16),
                            _buildFarmerCard(_offer!, cs),
                            const SizedBox(height: 16),
                            _buildBatchCard(_offer!, cs),
                            const SizedBox(height: 16),
                            _buildSummaryCard(_offer!, cs),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(CooperativeOfferModel offer, ColorScheme cs) {
    final color = _statusColor(offer);
    final subtitle = offer.isConfirmed
        ? 'Confirmed by SP3 — settlement recorded'
        : 'Declined — reservation released back to the batch';
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(offer.statusLabel.toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('— $subtitle',
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (offer.adminNotes != null && offer.adminNotes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(offer.isDeclined ? 'Reason: ${offer.adminNotes}' : 'Notes: ${offer.adminNotes}',
                style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildFarmerCard(CooperativeOfferModel offer, ColorScheme cs) {
    return _SectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.primaryGreen.withValues(alpha: 0.12),
            backgroundImage: offer.farmerPhotoUrl != null
                ? NetworkImage(offer.farmerPhotoUrl!)
                : null,
            onBackgroundImageError: offer.farmerPhotoUrl != null ? (_, __) {} : null,
            child: offer.farmerPhotoUrl != null
                ? null
                : Text(
                    offer.farmerName.isNotEmpty ? offer.farmerName[0].toUpperCase() : 'F',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.farmerName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
                if (offer.farmerPhone != null)
                  Text(offer.farmerPhone!, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchCard(CooperativeOfferModel offer, ColorScheme cs) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(offer.cropName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          if (offer.batchNumber != null || offer.harvestDate != null || offer.category != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                if (offer.batchNumber != null) _miniField('Batch', '#${offer.batchNumber}', cs),
                if (offer.harvestDate != null) _miniField('Freshness', offer.harvestedLabel, cs),
                if (offer.category != null) _miniField('Category', offer.category!, cs),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniField(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ],
    );
  }

  Widget _buildSummaryCard(CooperativeOfferModel offer, ColorScheme cs) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Offer Summary', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          _summaryRow('Offered Quantity', '${offer.offeredQuantityKg.toStringAsFixed(0)} kg', cs),
          if (offer.isConfirmed) ...[
            _summaryRow('Confirmed Quantity', '${offer.confirmedQuantityKg?.toStringAsFixed(0) ?? '—'} kg', cs),
            Divider(height: 20, color: cs.outline.withValues(alpha: 0.10)),
            _summaryRow('Amount Paid', '₱${offer.confirmedAmount?.toStringAsFixed(2) ?? '—'}', cs, bold: true),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OFFERED', style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: cs.onSurfaceVariant)),
                  Text(_formatDate(offer.offeredAt), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ],
              ),
              if (offer.confirmedAt != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(offer.isConfirmed ? 'CONFIRMED' : 'DECLINED',
                        style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: cs.onSurfaceVariant)),
                    Text(_formatDate(offer.confirmedAt!), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, ColorScheme cs, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  color: bold ? AppConstants.primaryGreen : cs.onSurfaceVariant,
                )),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: bold ? 18 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppConstants.primaryGreen : cs.onSurface,
              )),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// Same blurred-glass pattern as OrderDetailScreen's own _TopBar — copied
// rather than shared, matching this module's established file-scoped
// convention for this exact widget shape.

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

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
                child: Text(title,
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────
// Plain bordered card — same convention as OrderDetailScreen's _SectionCard.

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: child,
    );
  }
}
