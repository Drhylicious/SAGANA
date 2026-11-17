import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/feature_restriction_notice.dart';
import '../../../data/models/member_restriction.dart';

// Carries the batch-level context (Market Type, Batch Number) that
// MarketplaceListingModel itself doesn't own — those live on
// InventoryBatchModel. create_listing_screen.dart already has the selected
// batch in hand at submission time, so it's passed through here rather
// than re-fetched, keeping the model itself a faithful mirror of its own
// DB row instead of being bloated with joined data it doesn't write.
class ListingSuccessArgs {
  final MarketplaceListingModel listing;
  final String? batchNumber;
  final String? marketType;
  // Phase 11 — same rationale as batchNumber/marketType: category lives on
  // InventoryBatchModel, not MarketplaceListingModel, so it's passed
  // through from the already-in-hand selected batch rather than re-fetched.
  final String? category;

  const ListingSuccessArgs({
    required this.listing,
    this.batchNumber,
    this.marketType,
    this.category,
  });
}

class ListingSuccessScreen extends StatefulWidget {
  final Object? initialArg;

  const ListingSuccessScreen({super.key, this.initialArg});

  @override
  State<ListingSuccessScreen> createState() => _ListingSuccessScreenState();
}

class _ListingSuccessScreenState extends State<ListingSuccessScreen>
    with SingleTickerProviderStateMixin {
  final _repo = ListingRepository();

  MarketplaceListingModel? _listing;
  String? _batchNumber;
  String? _marketType;
  String? _category;
  bool _isWithdrawing = false;

  late final AnimationController _animController;
  late final Animation<double> _headerAnim;
  late final Animation<double> _cardAnim;
  late final Animation<double> _bannerAnim;
  late final Animation<double> _footerAnim;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // Read via the constructor — GoRouter's extra is delivered here, not
    // through ModalRoute.settings.arguments (that mechanism requires raw
    // Navigator.push(..., settings: RouteSettings(...)), which is not how
    // this screen is reached now that create_listing_screen.dart navigates
    // here via context.pushReplacementRoute).
    final arg = widget.initialArg;
    if (arg is ListingSuccessArgs) {
      _listing = arg.listing;
      _batchNumber = arg.batchNumber;
      _marketType = arg.marketType;
      _category = arg.category;
    } else if (arg is MarketplaceListingModel) {
      _listing = arg;
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _headerAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    );
    _cardAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.15, 0.75, curve: Curves.easeOutCubic),
    );
    _bannerAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
    );
    _footerAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
    );

    _animController.forward();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // To the centavo, exactly as the database rounds an order total.
  double get _estimatedRevenue =>
      moneyOf(_listing?.volumeKg ?? 0, _listing?.pricePerKg ?? 0);

  void _viewMyListings() {
    // Use GoRouter helper to navigate (replaces Navigator.named usage).
    context.goTab(AppRoutes.myListings);
  }

  Future<void> _createAnother() async {
    if (!await ensureFeatureAvailable(context, RestrictableFeature.marketplaceListing)) return;
    if (!mounted) return;
    context.pushReplacementRoute(AppRoutes.createListing);
  }

  void _confirmWithdraw() {
    if (_listing == null) return;
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).offlineWithdrawListing),
          backgroundColor: AppConstants.snackbarWarning,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          AppLocalizations.of(context).enhWithdrawSubmission,
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          AppLocalizations.of(context).enhThisListingWillBeWithdrawnBeforeItHas,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context).cancel,
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isWithdrawing = true);
              await _repo.withdrawListing(_listing!.id);
              if (!mounted) return;
              _viewMyListings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text(
              AppLocalizations.of(context).enhWithdraw,
              style: GoogleFonts.poppins(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_listing == null) {
      // Normally unreachable: the route redirects when no listing is passed.
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    final listing = _listing!;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 24),
              if (!_isOnline)
                OfflineStatusCard(
                  message: AppLocalizations.of(context).offlineListingActions,
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 220),
                  child: Column(
                    children: [
                      // Header
                      FadeTransition(
                        opacity: _headerAnim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(_headerAnim),
                          child: _HeaderSection(),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Summary card
                      FadeTransition(
                        opacity: _cardAnim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(_cardAnim),
                          child: _SummaryCard(
                            listing: listing,
                            batchNumber: _batchNumber,
                            marketType: _marketType,
                            category: _category,
                            estimatedRevenue: _estimatedRevenue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Info banner
                      FadeTransition(
                        opacity: _bannerAnim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(_bannerAnim),
                          child: const _InfoBanner(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _footerAnim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.10),
                  end: Offset.zero,
                ).animate(_footerAnim),
                child: _BottomActions(
                  isWithdrawing: _isWithdrawing,
                  onViewListings: _viewMyListings,
                  onCreateAnother: _createAnother,
                  onWithdraw: _confirmWithdraw,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header Section
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppConstants.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context).enhListingSubmitted,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 260,
          child: Text(
            AppLocalizations.of(
              context,
            ).enhAwaitingAdministrativeApprovalFromSPCooperative,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final MarketplaceListingModel listing;
  final String? batchNumber;
  final String? marketType;
  final String? category;
  final double estimatedRevenue;

  const _SummaryCard({
    required this.listing,
    required this.batchNumber,
    required this.marketType,
    required this.category,
    required this.estimatedRevenue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: flatCardDecoration(context),
      child: Column(
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.cropName,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (listing.variety != null && listing.variety!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          listing.variety!,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.80),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  AppLocalizations.of(context).enhPENDINGAPPROVAL,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.warningAmber,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Hero photo
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: Container(
              width: double.infinity,
              height: 160,
              color: context.adaptiveSurface(AppConstants.infoBlueBg),
              child: listing.photoUrl != null
                  ? Image.network(
                      listing.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _emojiFallback(context),
                    )
                  : _emojiFallback(context),
            ),
          ),
          const SizedBox(height: 20),

          // Full recap of what was entered/selected in Create Listing, so
          // the farmer can verify the submission before moving on.
          _SummaryRow(
            label: AppLocalizations.of(context).issueLoanQuantity,
            value: formatQuantityUnit(listing.volumeKg, listing.unit),
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: AppLocalizations.of(context).enhPricePerUnit,
            value: formatPricePerUnit(listing.pricePerKg, listing.unit),
          ),
          if (marketType != null) ...[
            const SizedBox(height: 12),
            _SummaryRow(
              label: AppLocalizations.of(context).priceMarketTypeLabel,
              value: marketTypeLabelFor(marketType),
            ),
          ],
          if (category != null && category!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SummaryRow(
              label: AppLocalizations.of(context).buyerListingCategory,
              value: category!,
            ),
          ],
          if (batchNumber != null && batchNumber!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SummaryRow(
              label: AppLocalizations.of(context).enhBatchNumber,
              value: formatBatchNumber(batchNumber),
            ),
          ],
          if (listing.description != null &&
              listing.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.saganaColors.scaffoldBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.10),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DESCRIPTION',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.70),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    listing.description!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Estimated revenue
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(
                color: AppConstants.primaryGreen.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              children: [
                Text(
                  AppLocalizations.of(context).enhESTIMATEDTOTALREVENUE,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.70),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₱${estimatedRevenue.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiFallback(BuildContext context) {
    final emoji = _emojiForCrop(listing.cropName);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).enhNoPhotoAvailable,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _emojiForCrop(String cropName) {
    final lower = cropName.toLowerCase();
    if (lower.contains('banana')) return '🍌';
    if (lower.contains('peanut') || lower.contains('mani')) return '🥜';
    if (lower.contains('copra') || lower.contains('coconut')) return '🥥';
    if (lower.contains('rice') || lower.contains('palay')) return '🌾';
    if (lower.contains('corn') || lower.contains('mais')) return '🌽';
    if (lower.contains('ginger') || lower.contains('luya')) return '🫚';
    if (lower.contains('mango') || lower.contains('mangga')) return '🥭';
    if (lower.contains('papaya')) return '🍈';
    if (lower.contains('kamote')) return '🍠';
    if (lower.contains('garlic') || lower.contains('bawang')) return '🧄';
    return '🌱';
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info Banner
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.adaptiveSurface(const Color(0xFFE6F6FF)),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: context.adaptiveSurface(const Color(0xFFD5ECF8)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              AppLocalizations.of(context).enhYouWillBeNotifiedViaTheAppOnce,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Actions
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final bool isWithdrawing;
  final VoidCallback onViewListings;
  final VoidCallback onCreateAnother;
  final VoidCallback onWithdraw;

  const _BottomActions({
    required this.isWithdrawing,
    required this.onViewListings,
    required this.onCreateAnother,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppConstants.primaryGreen,
                    AppConstants.primaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
              child: ElevatedButton(
                onPressed: isWithdrawing ? null : onViewListings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).enhViewListing,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton(
              onPressed: isWithdrawing ? null : onCreateAnother,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text(
                AppLocalizations.of(context).enhCreateAnotherListing,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Wrapped in its own red-outlined container so this destructive
          // action reads as clearly separated from the two primary actions
          // above, rather than sitting as a bare text link beneath them.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isWithdrawing ? null : onWithdraw,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.errorRed,
                side: BorderSide(
                  color: AppConstants.errorRed.withValues(alpha: 0.50),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: isWithdrawing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppConstants.errorRed,
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).enhWithdrawSubmission314,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.errorRed,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
