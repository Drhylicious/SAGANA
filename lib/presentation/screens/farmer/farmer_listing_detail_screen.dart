import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

// Phase 12 — replaces the old single-purpose (Live-only) preview with a
// single, parameterized, status-aware screen: "View Live" and every listing
// card tap now route here regardless of status, per the approved redesign
// (rather than six independent screens per status). Owner-management only —
// never shows a purchase CTA. The Purchase-mode equivalent (a farmer buying
// another farmer's listing) is the Buyer ListingDetailsScreen reused with
// isFarmerContext: true (Phase 9); this screen and that one are deliberately
// separate because their action sets don't overlap at all.
class FarmerListingDetailScreen extends StatefulWidget {
  final MarketplaceListingModel listing;
  const FarmerListingDetailScreen({super.key, required this.listing});

  @override
  State<FarmerListingDetailScreen> createState() => _FarmerListingDetailScreenState();
}

class _FarmerListingDetailScreenState extends State<FarmerListingDetailScreen> {
  final _listingRepo = ListingRepository();
  final _inventoryRepo = InventoryRepository();

  InventoryBatchModel? _batch;
  bool _isLoadingBatch = true;
  bool _isSubmitting = false;

  MarketplaceListingModel get _listing => widget.listing;

  @override
  void initState() {
    super.initState();
    _loadBatch();
  }

  // Market Type / Batch Number / Category live on InventoryBatchModel, not
  // MarketplaceListingModel — same batch-lookup precedent as Create Listing.
  Future<void> _loadBatch() async {
    final batchId = _listing.inventoryBatchId;
    if (batchId == null) {
      setState(() => _isLoadingBatch = false);
      return;
    }
    final batch = await _inventoryRepo.fetchBatchById(batchId);
    if (!mounted) return;
    setState(() {
      _batch = batch;
      _isLoadingBatch = false;
    });
  }

  bool _requireOnline() {
    if (ConnectivityService.instance.isOnline) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("This action requires an internet connection. Please try again once you're back online."),
        backgroundColor: AppConstants.warningAmber,
      ),
    );
    return false;
  }

  Future<void> _confirmWithdraw() async {
    if (!_requireOnline()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Text('Withdraw Listing?', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          '${_listing.displayName} will be removed from the marketplace. You can create a new listing for this batch later.',
          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
            ),
            child: Text('Withdraw', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await _listingRepo.withdrawListing(_listing.id);
      if (!mounted) return;
      context.popRoute();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to withdraw. Please try again.')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    if (!_requireOnline()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Text('Delete Listing?', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'This will permanently delete the listing for ${_listing.displayName}. This action cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await _listingRepo.deleteListing(_listing.id);
      if (!mounted) return;
      context.popRoute();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPhoto(),
                      const SizedBox(height: 20),
                      _buildHeader(context, listing),
                      const SizedBox(height: 10),
                      _buildPrice(listing),
                      if (listing.description != null && listing.description!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildDescription(listing),
                      ],
                      const SizedBox(height: 24),
                      _buildCommonInfo(listing),
                      const SizedBox(height: 20),
                      _buildStatusSection(context, listing),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              // Crop name resolved from the Crop Roster (marketplace_listings'
              // canonical_crop_name, via crop_id → crop_master), same source
              // MarketplaceListingModel.displayName uses everywhere else on
              // this screen — never hardcoded per-crop.
              title: '${listing.displayName} Details',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: _listing.photoUrl != null && _listing.photoUrl!.isNotEmpty
            ? Image.network(_listing.photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppConstants.infoBlueBg,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen, size: 40),
            const SizedBox(height: 8),
            Text('No photo available', style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          ],
        ),
      );

  Widget _buildHeader(BuildContext context, MarketplaceListingModel listing) {
    final color = ListingStatusDisplay.color(context, listing.status);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            listing.displayName,
            style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppConstants.charcoal),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Text(_statusLabel(listing.status),
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending_review': return 'PENDING REVIEW';
      case 'approved': return 'LIVE ON MARKET';
      case 'withdrawn': return 'WITHDRAWN';
      case 'rejected': return 'REJECTED';
      case 'sold': return 'SOLD';
      default: return status.toUpperCase();
    }
  }

  Widget _buildPrice(MarketplaceListingModel listing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('₱${listing.pricePerKg.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
        Text('/kg', style: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline)),
      ],
    );
  }

  Widget _buildDescription(MarketplaceListingModel listing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Product Details',
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.charcoal)),
          const SizedBox(height: 8),
          Text(listing.description!,
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }

  // Common info — always shown regardless of status, per the approved
  // Owner-management design: canonical name (header), photo, Market Type,
  // Batch Number, Category, Volume, Price (price/name/photo above).
  Widget _buildCommonInfo(MarketplaceListingModel listing) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: flatCardDecoration(context),
      child: _isLoadingBatch
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : Column(
              children: [
                _DetailRow(label: 'Available Volume', value: '${listing.remainingKg.toStringAsFixed(0)} kg'),
                const SizedBox(height: 12),
                _DetailRow(label: 'Original Volume', value: '${listing.volumeKg.toStringAsFixed(0)} kg'),
                if (_batch != null) ...[
                  const SizedBox(height: 12),
                  _DetailRow(label: 'Market Type', value: marketTypeLabelFor(_batch!.cropType)),
                  if (_batch!.category != null) ...[
                    const SizedBox(height: 12),
                    _DetailRow(label: 'Category', value: _batch!.category!),
                  ],
                  const SizedBox(height: 12),
                  _DetailRow(label: 'Batch Number', value: _batch!.batchNumber),
                ],
                if (listing.submittedAt != null) ...[
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Submitted',
                    value: '${listing.submittedAt!.month}/${listing.submittedAt!.day}/${listing.submittedAt!.year}',
                  ),
                ],
              ],
            ),
    );
  }

  // Status-conditional section + primary action(s), placed at the bottom of
  // the scrollable content rather than a floating bar — consistent with the
  // Buyer Listing Details cart-bar fix (Phase 2), so this isn't
  // reintroducing the same problem in a new screen.
  Widget _buildStatusSection(BuildContext context, MarketplaceListingModel listing) {
    if (listing.isPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusStepper.forListingStatus(listing.status),
          const SizedBox(height: 20),
          _actionButton('Withdraw Listing', AppConstants.errorRed, outlined: true, onTap: _confirmWithdraw),
        ],
      );
    }

    if (listing.isLive) {
      // No Withdraw action here, by explicit product direction — once a
      // listing is approved and visible to buyers, it may already have
      // an in-progress order against it (or a buyer viewing/cart-ing
      // it); pulling it out from under that risks the same kind of
      // inconsistency the reservation model prevents everywhere else.
      // withdraw_listing() enforces this server-side too (pending_review
      // only), so this isn't just a UI restriction — see
      // supabase_schema_withdraw_listing_pending_only_guard.sql.
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppConstants.successGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppConstants.successGreen, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This listing is live and visible to buyers on the marketplace.',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.successGreen),
              ),
            ),
          ],
        ),
      );
    }

    if (listing.isRejected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.adminNotes != null && listing.adminNotes!.isNotEmpty) ...[
            Text('Rejection Reason', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.errorRed)),
            const SizedBox(height: 6),
            Text(listing.adminNotes!, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 20),
          ],
          _actionButton('Delete Listing', AppConstants.errorRed, outlined: true, onTap: _confirmDelete),
        ],
      );
    }

    if (listing.isWithdrawn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.updatedAt != null) ...[
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 15, color: AppConstants.outline),
                const SizedBox(width: 6),
                Text(
                  'Removed on ${listing.updatedAt!.month}/${listing.updatedAt!.day}/${listing.updatedAt!.year}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _actionButton('Delete Listing', AppConstants.errorRed, outlined: true, onTap: _confirmDelete),
        ],
      );
    }

    if (listing.isSold) {
      // Terminal state — no actions, per the approved design.
      final realized = (listing.volumeKg - listing.remainingKg) * listing.pricePerKg;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.mutedBrown.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Final Realized Amount',
                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('₱${realized.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppConstants.mutedBrown)),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _actionButton(String label, Color color, {bool outlined = false, required VoidCallback onTap}) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _isSubmitting ? null : onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.50)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          ),
          child: _isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppConstants.charcoal)),
        ),
      ],
    );
  }
}
