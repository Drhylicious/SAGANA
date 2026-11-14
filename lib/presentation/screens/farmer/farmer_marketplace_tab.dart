import '../../../core/l10n/localized_labels.dart';
import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/models/cooperative_product_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/guest_mode_service.dart';
import '../../widgets/listing_filter_modal.dart'
    show ListingStatusFilterChip, MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/guest_prompt.dart';
import '../../widgets/product_card.dart';
import '../../../core/utils/order_status.dart'
    show kOrderSourceCooperative, kOrderSourceMarketplace;
import '../../widgets/skeleton.dart';

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
  final _programRepo = FarmerProgramRepository();
  final _cartService = CartService();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  List<BuyerListingModel> _allListings = [];
  // Cooperative Products (Product Sales programs): shown here, with the listings, to Farmers only.
  List<CooperativeProduct> _allProducts = [];
  // null = both sources.
  String? _sourceFilter;
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
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
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
    // A guest has no account and the database shows Cooperative Products to Farmers only.
    final products = GuestModeService.active
        ? <CooperativeProduct>[]
        : await _programRepo.fetchCooperativeProducts();
    if (!mounted) return;
    setState(() {
      _allListings = listings;
      _allProducts = products;
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
    final cats = <String>{
      for (final l in _allListings)
        if (_sourceFilter != kOrderSourceCooperative && l.category != null)
          l.category!,
      for (final p in _allProducts)
        if (_sourceFilter != kOrderSourceMarketplace &&
            p.category.trim().isNotEmpty)
          p.category.trim(),
    }.toList()..sort();
    return ['All', ...cats];
  }

  bool get _showListings => _sourceFilter != kOrderSourceCooperative;
  bool get _showProducts => _sourceFilter != kOrderSourceMarketplace;

  List<CooperativeProduct> get _filteredProducts {
    if (!_showProducts) return const [];
    return _allProducts.where((p) {
      final matchesCategory =
          _selectedCategory == 'All' || p.category.trim() == _selectedCategory;
      final matchesSearch =
          _searchQuery.isEmpty ||
          p.itemName.toLowerCase().contains(_searchQuery) ||
          p.programName.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<BuyerListingModel> get _filteredListings {
    if (!_showListings) return const [];
    return _allListings.where((l) {
      final matchesCategory =
          _selectedCategory == 'All' || l.category == _selectedCategory;
      final matchesSearch =
          _searchQuery.isEmpty ||
          l.cropName.toLowerCase().contains(_searchQuery) ||
          (l.variety?.toLowerCase().contains(_searchQuery) ?? false);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<void> _openCart() async {
    if (GuestModeService.active) {
      context.promptFarmer(
        (l) => l.guestCartTitle,
        (l) => l.guestCartMessage,
        icon: Icons.shopping_cart_outlined,
      );
      return;
    }
    await context.push(AppRoutes.farmerMarketplaceCart);
    _loadCartCount();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredListings;
    final products = _filteredProducts;
    final nothingAtAll = _allListings.isEmpty && _allProducts.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildHeader(l10n),
        ),
        // Only when Cooperative Products exist: which source to browse.
        if (_allProducts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildSourceChips(l10n),
        ],
        if (!nothingAtAll) ...[
          const SizedBox(height: 14),
          _buildCategoryChips(),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  ),
                )
              : nothingAtAll
              ? _buildEmptyState(l10n, isFilterEmpty: false)
              : (filtered.isEmpty && products.isEmpty)
              ? _buildEmptyState(l10n, isFilterEmpty: true)
              : _buildGrid(l10n, filtered, products),
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
              fillColor: context.saganaColors.cardBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const Key('myOrdersShortcut'),
          tooltip: AppLocalizations.of(context).uoMyOrdersShortcut,
          icon: Icon(
            Icons.receipt_long_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
          onPressed: () async {
            await context.push(AppRoutes.farmerMyOrders);
            _loadCartCount();
          },
        ),
        _CartIconButton(count: _cartCount, onTap: _openCart),
      ],
    );
  }

  Widget _buildCategoryChips() {
    final cats = _availableCategories;
    if (cats.length <= 1) return const SizedBox.shrink();

    // The standard "Label (n)" chips. A count is the number of items of that
    // category in the source(s) now shown (listings and Cooperative Products).
    int countOf(String cat) {
      var n = 0;
      if (_showListings) {
        n += _allListings
            .where((l) => cat == 'All' || l.category == cat)
            .length;
      }
      if (_showProducts) {
        n += _allProducts
            .where((p) => cat == 'All' || p.category.trim() == cat)
            .length;
      }
      return n;
    }

    return MarketplaceFilterBar<String>(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      selected: _selectedCategory,
      onSelected: (cat) => setState(() => _selectedCategory = cat),
      options: [
        for (final cat in cats)
          MarketplaceFilterOption(
            value: cat,
            label: localizeBuiltinLabel(AppLocalizations.of(context), cat),
            count: countOf(cat),
            color: AppConstants.primaryGreen,
          ),
      ],
    );
  }

  // Marketplace listings first, then Cooperative Products: the same card, the same grid.
  Widget _buildGrid(
    AppLocalizations l10n,
    List<BuyerListingModel> listings,
    List<CooperativeProduct> products,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      // No automatic status-bar padding: this list sits inside a bigger scroll view.
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      // Same grid as every other product screen (see ProductCard).
      gridDelegate: ProductCard.gridDelegate,
      itemCount: listings.length + products.length,
      itemBuilder: (context, i) {
        if (i < listings.length) {
          return _ListingCard(
            listing: listings[i],
            isOwn:
                listings[i].farmerId != null &&
                listings[i].farmerId == _currentUserId,
            onReturn: _loadCartCount,
          );
        }
        return _CooperativeProductCard(
          product: products[i - listings.length],
          onReturn: () {
            _loadCartCount();
            _load();
          },
        );
      },
    );
  }

  Widget _buildSourceChips(AppLocalizations l10n) {
    // The standard "Label (n)" chip; the count is what that source holds.
    Widget chip(String? value, String label) {
      final count = switch (value) {
        kOrderSourceMarketplace => _allListings.length,
        kOrderSourceCooperative => _allProducts.length,
        _ => _allListings.length + _allProducts.length,
      };
      return ListingStatusFilterChip(
        key: Key('source_${value ?? 'all'}'),
        label: label,
        count: count,
        active: _sourceFilter == value,
        color: AppConstants.programPurple,
        cs: Theme.of(context).colorScheme,
        onTap: () => setState(() {
          _sourceFilter = value;
          _selectedCategory = 'All';
        }),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          chip(null, l10n.cpFilterAll),
          const SizedBox(width: 8),
          chip(kOrderSourceMarketplace, l10n.cpFilterMarketplace),
          const SizedBox(width: 8),
          chip(kOrderSourceCooperative, l10n.cpFilterCooperative),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    AppLocalizations l10n, {
    required bool isFilterEmpty,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 56,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isFilterEmpty
                  ? l10n.buyerBrowseNoResultsTitle
                  : l10n.buyerBrowseEmptyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isFilterEmpty
                  ? l10n.buyerBrowseNoResultsBody
                  : l10n.buyerBrowseEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Card — the shared ProductCard (same card as Buyer Browse and the
// Product Sales catalog), plus this tab's own "YOURS" badge for a farmer's own
// approved listing. Tapping still opens Listing Details, where the purchase is
// blocked for an own listing (and by place_order() in the database).
// ─────────────────────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  final BuyerListingModel listing;
  final bool isOwn;
  final VoidCallback? onReturn;
  const _ListingCard({
    required this.listing,
    required this.isOwn,
    this.onReturn,
  });

  void _open(BuildContext context) async {
    await context.push(
      AppRoutes.farmerMarketplaceListingDetail,
      extra: listing.id,
    );
    onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final soldOut = listing.isSoldOut;

    final String? badge = isOwn
        ? l10n.farmerBrowseOwnListingBadge
        : soldOut
        ? l10n.buyerBrowseSoldOut
        : listing.isLowStock
        ? l10n.buyerBrowseLowStock
        : null;
    final Color badgeColor = isOwn
        ? AppConstants.primaryGreen
        : soldOut
        ? AppConstants.errorRed
        : AppConstants.warningAmber;

    return ProductCard(
      name: listing.displayName,
      imageUrl: listing.listingPhotoUrl,
      priceText: formatPricePerUnit(listing.pricePerKg, listing.unit),
      buyersText: l10n.catBuyers(listing.buyers),
      marketTypeText:
          '${l10n.uoSourceMarketplace} · ${listing.marketTypeLabel}',
      availableText:
          '${formatQuantityUnit(listing.displayAvailableKg, listing.unit)} ${l10n.buyerBrowseAvailableSuffix}',
      soldText: l10n.buyerBrowseUnitsSold(
        formatQuantityUnit(listing.soldKg, listing.unit),
      ),
      soldOut: soldOut,
      badgeLabel: badge,
      badgeColor: badgeColor,
      onTap: () => _open(context),
    );
  }
}

/// A Cooperative Product: the same shared card, labelled so it is never mistaken for a
/// Marketplace listing, with the member price when the Farmer is an enrolled member.
class _CooperativeProductCard extends StatelessWidget {
  final CooperativeProduct product;
  final VoidCallback? onReturn;
  const _CooperativeProductCard({required this.product, this.onReturn});

  Future<void> _open(BuildContext context) async {
    await context.push(AppRoutes.farmerCooperativeProduct, extra: product);
    onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = product;
    final String? hint = p.memberPriceApplies
        ? l10n.prodRegularPrice(formatPesos(p.regularPrice))
        : p.hasMemberDiscount
        ? l10n.cpMemberPriceHint(formatPesos(p.memberPrice))
        : null;
    return ProductCard(
      key: Key('coopProduct_${p.productId}'),
      name: p.itemName,
      imageUrl: p.imageUrl,
      placeholderIcon: Icons.inventory_2_outlined,
      priceText: formatPricePerUnit(p.payPrice, p.unit),
      priceColor: p.memberPriceApplies
          ? AppConstants.successGreen
          : AppConstants.primaryGreen,
      hintText: hint,
      hintColor: p.memberPriceApplies ? null : AppConstants.programPurple,
      buyersText: l10n.catBuyers(p.buyers),
      marketTypeText: '${l10n.cpSourceLabel} · ${p.programName}',
      availableText:
          '${formatQuantityUnit(p.availableToSell, p.unit)} ${l10n.buyerBrowseAvailableSuffix}',
      soldText: l10n.buyerBrowseUnitsSold(
        formatQuantityUnit(p.soldQuantity, p.unit),
      ),
      soldOut: p.isOutOfStock,
      badgeLabel: p.isOutOfStock ? l10n.buyerBrowseSoldOut : null,
      badgeColor: AppConstants.errorRed,
      onTap: () => _open(context),
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
          icon: Icon(
            Icons.shopping_cart_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 26,
          ),
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
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
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
