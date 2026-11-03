import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/models/listing_edit_request_model.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/listing_status_badge.dart';
import '../../widgets/shared_widgets.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/app_toast.dart';

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
  State<FarmerListingDetailScreen> createState() =>
      _FarmerListingDetailScreenState();
}

class _FarmerListingDetailScreenState extends State<FarmerListingDetailScreen> {
  final _listingRepo = ListingRepository();
  final _inventoryRepo = InventoryRepository();

  InventoryBatchModel? _batch;
  bool _isLoadingBatch = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  bool _isSubmitting = false;
  // What the listing's orders are really worth (each order keeps the price it
  // was placed at, so this can differ from quantity x the current price).
  double? _orderedAmount;

  /// This listing's edit requests, newest first. While one is pending the listing
  /// stays published exactly as it is.
  List<ListingEditRequest> _requests = [];

  ListingEditRequest? get _pendingRequest {
    for (final r in _requests) {
      if (r.isPending) return r;
    }
    return null;
  }

  /// The latest decision, when it was a disapproval and nothing is waiting.
  ListingEditRequest? get _lastRejected {
    if (_pendingRequest != null || _requests.isEmpty) return null;
    return _requests.first.isRejected ? _requests.first : null;
  }

  late MarketplaceListingModel _listing;

  @override
  void initState() {
    super.initState();
    _listing = widget.listing;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadBatch();
    _loadOrderedAmount();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final requests = await _listingRepo.fetchMyEditRequests(_listing.id);
    if (!mounted) return;
    setState(() => _requests = requests);
  }

  Future<void> _loadOrderedAmount() async {
    final amounts = await _listingRepo.fetchOrderedAmounts();
    if (!mounted) return;
    setState(() => _orderedAmount = amounts[_listing.id]);
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
        content: Text(
          "This action requires an internet connection. Please try again once you're back online.",
        ),
        backgroundColor: AppConstants.snackbarWarning,
      ),
    );
    return false;
  }

  // Edit Listing: quantity, asking price, description and photo of a Pending
  // Approval or Available listing. On return the listing and its batch are read
  // again, because the edit may have changed the quantity left.
  Future<void> _openEdit() async {
    if (!_requireOnline()) return;
    final saved = await context.pushRoute<bool>(
      AppRoutes.editListing,
      extra: _listing,
    );
    if (saved != true || !mounted) return;
    final fresh = await _listingRepo.fetchListing(_listing.id);
    if (!mounted) return;
    if (fresh != null) setState(() => _listing = fresh);
    _loadBatch();
    _loadOrderedAmount();
    _loadRequests();
  }

  Future<void> _cancelRequest(ListingEditRequest request) async {
    final l = AppLocalizations.of(context);
    if (!_requireOnline()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Text(l.leCancelRequestTitle, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(l.leCancelRequestBody, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorRed, foregroundColor: Colors.white),
            child: Text(l.leCancelRequest),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _listingRepo.cancelEditRequest(request.id);
      if (!mounted) return;
      AppToast.show(context, l.leRequestCancelled);
      _loadRequests();
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, l.leRequestFailed, isError: true);
    }
  }

  void _openHistory() {
    context.pushRoute(
      AppRoutes.farmerListingHistory,
      extra: {'listingId': _listing.id, 'title': _listing.displayName},
    );
  }

  Future<void> _confirmWithdraw() async {
    if (!_requireOnline()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Withdraw Listing?',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${_listing.displayName} will be removed from the marketplace. You can create a new listing for this batch later.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Delete Listing?',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete the listing for ${_listing.displayName}. This action cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
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
              TopBarSpacer(height: 72),
              CachedDataNotice(
                screen: 'batch_${_listing.inventoryBatchId}',
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(
                  context,
                ).offlineListingActions,
              ),
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
                      if (listing.description != null &&
                          listing.description!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildDescription(listing),
                      ],
                      const SizedBox(height: 24),
                      _buildCommonInfo(listing),
                      const SizedBox(height: 20),
                      _buildStatusSection(context, listing),
                      const SizedBox(height: 16),
                      _historyButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
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
            ? Image.network(
                _listing.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
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
        const Icon(
          Icons.eco_rounded,
          color: AppConstants.primaryGreen,
          size: 40,
        ),
        const SizedBox(height: 8),
        Text(
          'No photo available',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _buildHeader(BuildContext context, MarketplaceListingModel listing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            listing.displayName,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
        ),
        ListingStatusBadge.forListing(
          context,
          status: listing.status,
          remainingKg: listing.remainingKg,
        ),
      ],
    );
  }

  Widget _buildPrice(MarketplaceListingModel listing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '₱${listing.pricePerKg.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppConstants.primaryGreen,
          ),
        ),
        Text(
          '/${unitOrDefault(listing.unit)}',
          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline),
        ),
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
          Text(
            'Product Details',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            listing.description!,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
              height: 1.5,
            ),
          ),
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
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              children: [
                _DetailRow(
                  label: 'Available Volume',
                  value: formatQuantityUnit(listing.remainingKg, listing.unit),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Original Volume',
                  value: formatQuantityUnit(listing.volumeKg, listing.unit),
                ),
                if (_batch != null) ...[
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Market Type',
                    value: marketTypeLabelFor(_batch!.cropType),
                  ),
                  if (_batch!.category != null) ...[
                    const SizedBox(height: 12),
                    _DetailRow(label: 'Category', value: _batch!.category!),
                  ],
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Batch Number',
                    value: formatBatchNumber(_batch!.batchNumber),
                  ),
                ],
                if (listing.submittedAt != null) ...[
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Submitted',
                    value:
                        '${listing.submittedAt!.month}/${listing.submittedAt!.day}/${listing.submittedAt!.year}',
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
  Widget _buildStatusSection(
    BuildContext context,
    MarketplaceListingModel listing,
  ) {
    if (listing.isPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusStepper.forListingStatus(listing.status),
          const SizedBox(height: 20),
          _actionButton(
            AppLocalizations.of(context).editListingAction,
            AppConstants.primaryGreen,
            onTap: ConnectivityService.instance.isOnline ? _openEdit : null,
          ),
          const SizedBox(height: 12),
          _actionButton(
            'Withdraw Listing',
            AppConstants.errorRed,
            outlined: true,
            onTap: ConnectivityService.instance.isOnline
                ? _confirmWithdraw
                : null,
          ),
        ],
      );
    }

    if (listing.isAvailable) {
      // No Withdraw action here, by explicit product direction — once a
      // listing is approved and visible to buyers, it may already have
      // an in-progress order against it (or a buyer viewing/cart-ing
      // it); pulling it out from under that risks the same kind of
      // inconsistency the reservation model prevents everywhere else.
      // withdraw_listing() enforces this server-side too (pending_review
      // only), so this isn't just a UI restriction — see
      // supabase_schema_withdraw_listing_pending_only_guard.sql.
      //
      // Editing IS allowed (quantity, price, description, photo): the database
      // keeps the stock and the existing orders consistent, and the Manager is
      // notified. See supabase_schema_farmer_listing_edit.sql.
      final pending = _pendingRequest;
      final rejected = _lastRejected;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _approvedNotice(),
          const SizedBox(height: 16),
          if (pending != null) ...[
            _pendingRequestCard(pending),
          ] else ...[
            if (rejected != null) ...[
              _rejectedRequestCard(rejected),
              const SizedBox(height: 16),
            ],
            _actionButton(
              AppLocalizations.of(context).leRequestTitle,
              AppConstants.primaryGreen,
              onTap: ConnectivityService.instance.isOnline ? _openEdit : null,
            ),
          ],
        ],
      );
    }

    if (listing.isRejected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.adminNotes != null && listing.adminNotes!.isNotEmpty) ...[
            Text(
              'Rejection Reason',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppConstants.errorRed,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              listing.adminNotes!,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
          ],
          _actionButton(
            'Delete Listing',
            AppConstants.errorRed,
            outlined: true,
            onTap: _confirmDelete,
          ),
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
                const Icon(
                  Icons.history_rounded,
                  size: 15,
                  color: AppConstants.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  'Removed on ${listing.updatedAt!.month}/${listing.updatedAt!.day}/${listing.updatedAt!.year}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppConstants.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _actionButton(
            'Delete Listing',
            AppConstants.errorRed,
            outlined: true,
            onTap: _confirmDelete,
          ),
        ],
      );
    }

    if (listing.isSoldOut) {
      return _soldOutSummary(listing);
    }

    return const SizedBox.shrink();
  }

  Widget _pendingRequestCard(ListingEditRequest r) {
    final l = AppLocalizations.of(context);
    final unit = r.unit;
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: AppConstants.onSurface)),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.warningAmber.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 18, color: AppConstants.warningAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.lePendingBannerTitle,
                  style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.lePendingBannerBody,
            style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          if (r.changesQuantity)
            line(l.wfDetailQuantity(formatQuantityUnit(r.originalQuantity, unit), formatQuantityUnit(r.proposedQuantity, unit))),
          if (r.changesPrice)
            line(l.wfDetailPrice(formatPricePerUnit(r.originalPrice, unit), formatPricePerUnit(r.proposedPrice, unit))),
          if (r.changesDescription) line(l.wfDetailDescription),
          if (r.changesPhoto) line(l.wfDetailPhoto),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => _cancelRequest(r),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.errorRed,
                side: BorderSide(color: AppConstants.errorRed.withValues(alpha: 0.5)),
              ),
              child: Text(l.leCancelRequest),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rejectedRequestCard(ListingEditRequest r) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, size: 18, color: AppConstants.errorRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.leRejectedBannerTitle,
                  style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if ((r.reviewReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l.leRejectedReason(r.reviewReason!.trim()),
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: AppConstants.onSurface),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyButton() {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openHistory,
        icon: const Icon(Icons.history_rounded, size: 18),
        label: Text(l.leViewHistory),
      ),
    );
  }

  Widget _approvedNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppConstants.successGreen,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This listing is approved and available for purchase on the marketplace.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.successGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Nothing left to buy — no actions, per the approved design. A listing stored
  // as sold is final; an approved one with nothing left still has orders in
  // progress, so its amount is not final yet.
  Widget _soldOutSummary(MarketplaceListingModel listing) {
    final realized =
        _orderedAmount ??
        moneyOf(listing.volumeKg - listing.remainingKg, listing.pricePerKg);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.onSurfaceVariant.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            listing.isSold ? 'Final Realized Amount' : 'Total Ordered Amount',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatPesos(realized),
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    Color color, {
    bool outlined = false,
    VoidCallback? onTap,
  }) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _isSubmitting ? null : onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.50)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppConstants.charcoal,
            ),
          ),
        ),
      ],
    );
  }
}
