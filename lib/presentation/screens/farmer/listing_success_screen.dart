import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';
import '../../../data/services/connectivity_service.dart';

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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // Read via the constructor — GoRouter's extra is delivered here, not
    // through ModalRoute.settings.arguments (that mechanism requires raw
    // Navigator.push(..., settings: RouteSettings(...)), which is not how
    // this screen is reached now that create_listing_screen.dart navigates
    // here via context.pushReplacementRoute).
    if (widget.initialArg is MarketplaceListingModel) {
      _listing = widget.initialArg as MarketplaceListingModel;
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

  double get _estimatedRevenue =>
      (_listing?.volumeKg ?? 0) * (_listing?.pricePerKg ?? 0);

  void _viewMyListings() {
    // Use GoRouter helper to navigate (replaces Navigator.named usage).
    context.goTab(AppRoutes.myListings);
  }

  void _createAnother() {
    context.pushReplacementRoute(AppRoutes.createListing);
  }

  void _confirmWithdraw() {
    if (_listing == null) return;
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You're offline — withdrawing this listing requires an internet connection.",
          ),
          backgroundColor: AppConstants.warningAmber,
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
        title: Text('Withdraw Submission?',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'This listing will be withdrawn before it has even been reviewed. You can create a new listing for this batch later.',
          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
            ),
            child: Text('Withdraw', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_listing == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen)),
      );
    }

    final listing = _listing!;

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              if (!_isOnline)
                const OfflineBanner(message: "You're offline — withdrawing or other listing actions require an internet connection."),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 220),
                  child: Column(
                    children: [
                      // Header
                      FadeTransition(
                        opacity: _headerAnim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_headerAnim),
                          child: _HeaderSection(),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Summary card
                      FadeTransition(
                        opacity: _cardAnim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_cardAnim),
                          child: _SummaryCard(listing: listing, estimatedRevenue: _estimatedRevenue),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Info banner
                      FadeTransition(
                        opacity: _bannerAnim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_bannerAnim),
                          child: const _InfoBanner(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(top: 0, left: 0, right: 0, child: FarmerTopBar(title: 'Submission Success', profilePhotoUrl: null, onProfileTap: () {}, onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications), onSettingsTap: null,)),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: FadeTransition(
              opacity: _footerAnim,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(_footerAnim),
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
          width: 64, height: 64,
          decoration: const BoxDecoration(color: AppConstants.primaryContainer, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),
        Text('Listing Submitted!',
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppConstants.charcoal)),
        const SizedBox(height: 6),
        SizedBox(
          width: 260,
          child: Text(
            'Awaiting administrative approval from SP3 Cooperative.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 15, color: AppConstants.onSurfaceVariant),
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
  final double estimatedRevenue;

  const _SummaryCard({required this.listing, required this.estimatedRevenue});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [BoxShadow(color: AppConstants.infoBlueFg.withValues(alpha: 0.05), blurRadius: 16)],
      ),
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
                    Text(listing.cropName,
                        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                    if (listing.variety != null && listing.variety!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(listing.variety!,
                            style: GoogleFonts.poppins(fontSize: 14, color: AppConstants.onSurfaceVariant.withValues(alpha: 0.80))),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text('PENDING REVIEW',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.warningAmber, letterSpacing: 0.5)),
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
              color: AppConstants.infoBlueBg,
              child: listing.photoUrl != null
                  ? Image.network(
                      listing.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _emojiFallback(),
                    )
                  : _emojiFallback(),
            ),
          ),
          const SizedBox(height: 20),

          // Quantity row
          _SummaryRow(label: 'Quantity', value: '${listing.volumeKg.toStringAsFixed(0)} kg'),
          const SizedBox(height: 12),
          _SummaryRow(label: 'Price per Unit', value: '₱${listing.pricePerKg.toStringAsFixed(2)}/kg'),
          const SizedBox(height: 20),

          // Estimated revenue
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.10)),
            ),
            child: Column(
              children: [
                Text('ESTIMATED TOTAL REVENUE',
                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen.withValues(alpha: 0.70), letterSpacing: 1.0)),
                const SizedBox(height: 6),
                Text('₱${estimatedRevenue.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiFallback() {
    final emoji = _emojiForCrop(listing.cropName);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 6),
          Text('No photo available', style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline)),
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
        border: Border(bottom: BorderSide(color: AppConstants.outline.withValues(alpha: 0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppConstants.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: AppConstants.onSurface)),
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
        color: const Color(0xFFE6F6FF),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: const Color(0xFFD5ECF8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, color: AppConstants.primaryGreen, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'You will be notified via the app once your listing is approved or if additional information is required.',
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant, height: 1.5),
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
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppConstants.primaryGreen, AppConstants.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
              child: ElevatedButton(
                onPressed: isWithdrawing ? null : onViewListings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
                ),
                child: Text('View My Listings',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
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
                foregroundColor: AppConstants.primaryGreen,
                side: const BorderSide(color: AppConstants.primaryGreen, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
              ),
              child: Text('+ Create Another Listing',
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: isWithdrawing ? null : onWithdraw,
            child: isWithdrawing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.errorRed))
                : Text('Withdraw Submission',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
  }
}
