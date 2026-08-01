import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/animated_pressable.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/shared_widgets.dart';

class MarketplaceBrowseScreen extends StatefulWidget {
  const MarketplaceBrowseScreen({super.key});

  @override
  State<MarketplaceBrowseScreen> createState() =>
      _MarketplaceBrowseScreenState();
}

class _MarketplaceBrowseScreenState extends State<MarketplaceBrowseScreen> {
  final _repository = BuyerMarketplaceRepository();
  final _cartService = CartService();
  final _notificationRepo = NotificationRepository();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  List<BuyerListingModel> _allListings = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  int _cartCount = 0;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCartCount();
    _loadUnreadCount();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  Future<void> _loadCartCount() async {
    final count = await _cartService.itemCount();
    if (!mounted) return;
    setState(() => _cartCount = count);
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationRepo.fetchUnreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
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

  // Only categories actually present among current listings — never a
  // filter chip that's guaranteed to return zero results.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final filtered = _filteredListings;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader(l10n)),
                        if (_allListings.isNotEmpty) ...[
                          SliverToBoxAdapter(child: _buildPriceTicker()),
                          SliverToBoxAdapter(child: _buildCategoryChips()),
                        ],
                        if (_isLoading)
                          const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_allListings.isEmpty)
                          SliverFillRemaining(child: _buildEmptyState(l10n, isFilterEmpty: false))
                        else if (filtered.isEmpty)
                          SliverFillRemaining(child: _buildEmptyState(l10n, isFilterEmpty: true))
                        else
                          _buildGrid(filtered),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: BuyerTopBar(
              title: l10n.buyerBrowseTitle,
              unreadCount: _unreadCount,
              onNotificationTap: () => context.push(AppRoutes.buyerNotifications),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 12),
      child: Row(
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
          _CartIconButton(
            count: _cartCount,
            onTap: () async {
              await context.push(AppRoutes.buyerCart);
              _loadCartCount();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPriceTicker() {
    final priced = _allListings.where((l) => l.marketRefPricePerKg != null).toList();
    final cropsShown = <String>{};
    final tickerItems = <BuyerListingModel>[];
    for (final l in priced) {
      if (cropsShown.add(l.cropName)) tickerItems.add(l);
    }
    if (tickerItems.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
        itemCount: tickerItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final l = tickerItems[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              '${l.cropName} · ₱${l.marketRefPricePerKg!.toStringAsFixed(2)}/kg',
              style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: AppConstants.primaryGreen,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChips() {
    final cats = _availableCategories;
    if (cats.length <= 1) return const SizedBox(height: 12);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
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
      ),
    );
  }

  Widget _buildGrid(List<BuyerListingModel> listings) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH, 4, AppConstants.spacingSafeH, 100,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ListingCard(listing: listings[i], onReturn: _loadCartCount),
          childCount: listings.length,
        ),
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
              isFilterEmpty
                  ? l10n.buyerBrowseNoResultsTitle
                  : l10n.buyerBrowseEmptyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              isFilterEmpty
                  ? l10n.buyerBrowseNoResultsBody
                  : l10n.buyerBrowseEmptyBody,
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
// Listing Card
// ─────────────────────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  final BuyerListingModel listing;
  final VoidCallback? onReturn;
  const _ListingCard({required this.listing, this.onReturn});

  void _open(BuildContext context) async {
    await context.push(AppRoutes.listingDetails, extra: listing.id);
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo + badges ──────────────────────────────────────────
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
                    if (soldOut)
                      Positioned(
                        top: 8, left: 8,
                        child: _Badge(
                          label: l10n.buyerBrowseSoldOut,
                          color: AppConstants.errorRed,
                        ),
                      )
                    else if (listing.isLowStock)
                      Positioned(
                        top: 8, left: 8,
                        child: _Badge(
                          label: l10n.buyerBrowseLowStock,
                          color: AppConstants.warningAmber,
                        ),
                      ),
                    if (listing.qualityGrade != null)
                      Positioned(
                        top: 8, right: 8,
                        child: _Badge(
                          label: listing.qualityGrade!,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                  ],
                ),
              ),
              // ── Details ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${listing.displayAvailableKg.toStringAsFixed(0)} kg ${l10n.buyerBrowseAvailableSuffix}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                    ),
                    if (!listing.isPriceWithinMarketRange) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 12, color: AppConstants.warningAmber),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              l10n.buyerBrowseAboveMarketRange,
                              style: GoogleFonts.inter(fontSize: 10, color: AppConstants.warningAmber),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: soldOut ? l10n.buyerBrowseSoldOut : l10n.buyerBrowseOrderNow,
                        height: 34,
                        onPressed: soldOut ? null : () => _open(context),
                      ),
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