import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/animated_pressable.dart';

/// Farmer-as-buyer Marketplace tab (Phase 9) — mirrors Buyer's
/// MarketplaceBrowseScreen body field-for-field (search, dynamic category
/// chips, card layout/copy/l10n, listing grid), reusing the same
/// BuyerMarketplaceRepository/CartService/BuyerListingModel data layer
/// since it's already role-agnostic (place_order() accepts a farmer caller
/// as of Phase 1). Farmers see their own listings here too, marked with an
/// "isOwn" badge computed from the listing's actual farmer_id vs. the
/// current user — tapping one still opens Listing Details (view-only,
/// same as any other card), but the authoritative purchase guard is on the
/// pushed ListingDetailsScreen (isFarmerContext: true) and in
/// place_order() itself, not anything in this file.
///
/// Deliberately not a Scaffold — this is embedded as one of the two
/// segmented-control panes inside MyListingsScreen, which already owns
/// the Scaffold/drawer/top bar/scroll container.
class FarmerMarketplaceTab extends StatefulWidget {
  const FarmerMarketplaceTab({super.key});

  @override
  State<FarmerMarketplaceTab> createState() => _FarmerMarketplaceTabState();
}

class _FarmerMarketplaceTabState extends State<FarmerMarketplaceTab> {
  final _repository = BuyerMarketplaceRepository();
  final _cartService = CartService();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  List<BuyerListingModel> _allListings = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  int _cartCount = 0;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCartCount();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final listings = await _repository.fetchApprovedListings();
    if (!mounted) return;
    setState(() {
      _allListings = listings;
      _isLoading = false;
    });
  }

  Future<void> _loadCartCount() async {
    final count = await _cartService.itemCount();
    if (!mounted) return;
    setState(() => _cartCount = count);
  }

  // Same "only categories actually present" rule as Buyer Browse — never a
  // filter chip guaranteed to return zero results.
  List<String> get _availableCategories {
    final cats = _allListings
        .map((l) => l.category)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return ['All', ...cats];
  }

  List<BuyerListingModel> get _filteredListings {
    return _allListings.where((l) {
      final matchesCategory =
          _selectedCategory == 'All' || l.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          l.cropName.toLowerCase().contains(_searchQuery) ||
          (l.variety?.toLowerCase().contains(_searchQuery) ?? false);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<void> _openCart() async {
    await context.push(AppRoutes.farmerMarketplaceCart);
    _loadCartCount();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredListings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildHeader(l10n),
        ),
        if (_allListings.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildCategoryChips(),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _allListings.isEmpty
                  ? _buildEmptyState(l10n, isFilterEmpty: false)
                  : filtered.isEmpty
                      ? _buildEmptyState(l10n, isFilterEmpty: true)
                      : _buildGrid(l10n, filtered),
        ),
      ],
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: InputDecoration(
              hintText: l10n.buyerBrowseSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _CartIconButton(count: _cartCount, onTap: _openCart),
      ],
    );
  }

  Widget _buildCategoryChips() {
    final cats = _availableCategories;
    if (cats.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = cats[i];
          final isSelected = cat == _selectedCategory;
          return AnimatedPressable(
            onTap: () => setState(() => _selectedCategory = cat),
            scaleDown: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                border: Border.all(
                  color: isSelected
                      ? AppConstants.primaryGreen
                      : AppConstants.outline.withValues(alpha: 0.25),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                cat,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppConstants.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(AppLocalizations l10n, List<BuyerListingModel> listings) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.71,
      ),
      itemCount: listings.length,
      itemBuilder: (context, i) => _ListingCard(
        listing: listings[i],
        isOwn: listings[i].farmerId != null && listings[i].farmerId == _currentUserId,
        onReturn: _loadCartCount,
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, {required bool isFilterEmpty}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 56,
                color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              isFilterEmpty ? l10n.buyerBrowseNoResultsTitle : l10n.buyerBrowseEmptyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              isFilterEmpty ? l10n.buyerBrowseNoResultsBody : l10n.buyerBrowseEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Card — same visual shape as Buyer Browse's _ListingCard, plus the
// disabled/"Your Listing" state for a farmer's own approved listings.
// ─────────────────────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  final BuyerListingModel listing;
  final bool isOwn;
  final VoidCallback? onReturn;
  const _ListingCard({required this.listing, required this.isOwn, this.onReturn});

  void _open(BuildContext context) async {
    await context.push(AppRoutes.farmerMarketplaceListingDetail, extra: listing.id);
    onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final soldOut = listing.isSoldOut;

    return AnimatedPressable(
      onTap: () => _open(context),
      scaleDown: 0.97,
      child: Opacity(
        opacity: soldOut ? 0.55 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: AppConstants.cardBorder,
            boxShadow: AppConstants.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    listing.listingPhotoUrl != null
                        ? Image.network(
                            listing.listingPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppConstants.limeGreen,
                              child: const Icon(Icons.eco_rounded, size: 32),
                            ),
                          )
                        : Container(
                            color: AppConstants.limeGreen,
                            child: const Icon(Icons.eco_rounded, size: 32),
                          ),
                    if (isOwn)
                      Positioned(
                        top: 8, left: 8,
                        child: _Badge(label: l10n.farmerBrowseOwnListingBadge, color: AppConstants.primaryGreen),
                      )
                    else if (soldOut)
                      Positioned(
                        top: 8, left: 8,
                        child: _Badge(label: l10n.buyerBrowseSoldOut, color: AppConstants.errorRed),
                      )
                    else if (listing.isLowStock)
                      Positioned(
                        top: 8, left: 8,
                        child: _Badge(label: l10n.buyerBrowseLowStock, color: AppConstants.warningAmber),
                      ),
                  ],
                ),
              ),
              // Same field order/content as Buyer Browse's own card (Phase —
              // Browse-tab rework): name, then price + cumulative units sold
              // on one row, then market type, then available qty. The
              // farmer-only addition is just the "isOwn" badge above; no
              // extra CTA button here — same tap-anywhere-on-card
              // interaction as Buyer's card, which dropped its own button.
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                            style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: AppConstants.primaryGreen,
                            ),
                          ),
                        ),
                        Text(
                          l10n.buyerBrowseUnitsSold(listing.soldKg.toStringAsFixed(0)),
                          style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      listing.marketTypeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${listing.displayAvailableKg.toStringAsFixed(0)} kg ${l10n.buyerBrowseAvailableSuffix}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartIconButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CartIconButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined, color: AppConstants.primaryGreen, size: 26),
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: 6, right: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppConstants.errorRed,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(count > 9 ? '9+' : '$count',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}
