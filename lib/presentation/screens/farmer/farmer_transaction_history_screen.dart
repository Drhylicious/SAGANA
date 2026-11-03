import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_transaction_model.dart';
import '../../../data/repositories/farmer_transaction_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/listing_filter_modal.dart' show ListingMarketBadge;
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../core/l10n/app_localizations.dart';

/// Farmer's own transaction history, across all 4 selling channels —
/// distinct from Admin's Sales Report, which aggregates every farmer-
/// member. Read-only: nothing here can be edited or actioned, same as
/// Harvest History's own "View Details".
class FarmerTransactionHistoryScreen extends StatefulWidget {
  const FarmerTransactionHistoryScreen({super.key});

  @override
  State<FarmerTransactionHistoryScreen> createState() =>
      _FarmerTransactionHistoryScreenState();
}

class _FarmerTransactionHistoryScreenState
    extends State<FarmerTransactionHistoryScreen> {
  final _repo = FarmerTransactionRepository();
  final _searchController = TextEditingController();

  List<FarmerTransactionModel> _all = [];
  List<FarmerTransactionModel> _filtered = [];

  String _activeType = _TypeChips.all;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = true;

  static const _sellingTypes = [
    'offer_to_cooperative',
    'marketplace',
    'informal_sale',
    'da_amad_market_linking',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final transactions = await _repo.fetchMyTransactions();
    if (!mounted) return;
    setState(() {
      _all = transactions;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilters();
    });
  }

  void _setType(String type) {
    setState(() {
      _activeType = type;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _all.where((t) {
      if (_activeType != _TypeChips.all && t.sellingType != _activeType) {
        return false;
      }
      if (q.isEmpty) return true;
      return t.cropName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    TopBarSpacer(height: 72),
                    // The crop image lookup runs first on every load, so it
                    // stands in for the whole history's cache state.
                    CachedDataNotice(
                      screen: 'transactions_crop_images',
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(context).offlineTransactions,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadData,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            _SearchBar(controller: _searchController),
                            const SizedBox(height: 12),
                            _TypeChips(
                              types: _sellingTypes,
                              active: _activeType,
                              onSelected: _setType,
                            ),
                            const SizedBox(height: 20),
                            if (_isLoading)
                              ...List.generate(
                                4,
                                (_) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: SkeletonList(count: 4, rowHeight: 80),
                                ),
                              )
                            else if (_filtered.isEmpty)
                              _EmptyState(
                                hasFilter: _searchQuery.isNotEmpty ||
                                    _activeType != _TypeChips.all,
                              )
                            else
                              ..._filtered.map(
                                (t) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GestureDetector(
                                    onTap: () => _showTransactionDetails(context, t),
                                    child: _TransactionTile(transaction: t),
                                  ),
                                ),
                              ),
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
                    title: 'Transaction History',
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showTransactionDetails(BuildContext context, FarmerTransactionModel t) {
  showManagementModal<void>(
    context: context,
    builder: (_) => _TransactionDetailsSheet(transaction: t),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).txnSearchHint,
        hintStyle: GoogleFonts.inter(
            fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.60)),
        prefixIcon: const Icon(Icons.search_rounded, color: AppConstants.outline),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selling Type Chips — All + the 4 channels. Same visual pattern as
// CropCategoryChips (crop_category_chips.dart), kept as its own copy since
// it filters by selling type, not crop category.
// ─────────────────────────────────────────────────────────────────────────────

class _TypeChips extends StatelessWidget {
  static const String all = 'All';

  final List<String> types;
  final String active;
  final ValueChanged<String> onSelected;

  const _TypeChips({
    required this.types,
    required this.active,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final options = [all, ...types];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((type) {
          final isActive = type == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer.withValues(alpha: 0.12)
                      : sagana.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: isActive
                      ? Border.all(
                          color: AppConstants.primaryContainer.withValues(alpha: 0.30))
                      : null,
                ),
                child: Text(
                  type == all ? all : sellingTypeLabel(type),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive ? AppConstants.primaryContainer : cs.onSurfaceVariant,
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
// Transaction Tile
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final FarmerTransactionModel transaction;
  const _TransactionTile({required this.transaction});

  static const _iconByType = {
    'offer_to_cooperative': Icons.storefront_rounded,
    'marketplace': Icons.shopping_cart_rounded,
    'informal_sale': Icons.handshake_rounded,
    'da_amad_market_linking': Icons.eco_rounded,
  };

  static const _colorByType = {
    'offer_to_cooperative': AppConstants.primaryGreen,
    'marketplace': AppConstants.buyerBlue,
    'informal_sale': AppConstants.amber,
    'da_amad_market_linking': AppConstants.successGreen,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final color = _colorByType[transaction.sellingType] ?? AppConstants.outline;
    final icon = _iconByType[transaction.sellingType] ?? Icons.receipt_outlined;

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
          // The repository already resolves cropImageUrl (farmer_crops'
          // own photo, falling back to the crop_master catalog photo) —
          // this tile just never rendered it, always showing the generic
          // per-channel icon instead regardless of whether a real photo
          // was available.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Container(
              width: 48,
              height: 48,
              color: color.withValues(alpha: 0.10),
              child: transaction.cropImageUrl != null
                  ? Image.network(
                      transaction.cropImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(icon, color: color, size: 24),
                    )
                  : Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.cropName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${sellingTypeLabel(transaction.sellingType)} • ${formatQuantityUnit(transaction.quantityKg, transaction.unit)}',
                  style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                // The crop's market type (Public / Cooperative) and category
                // (Vegetable, Fruit, ...), on every channel.
                if (transaction.marketType != null ||
                    (transaction.cropCategory ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (transaction.marketType != null)
                        ListingMarketBadge(marketType: transaction.marketType),
                      if ((transaction.cropCategory ?? '').isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text(
                            transaction.cropCategory!,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${transaction.amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.successGreen,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                DateFormat('MMM d, yyyy').format(transaction.transactionDate),
                style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction Details — read-only. A Market Linking sale shows its agreed price
// and the buyer saved on it (name, contact number, email), the same buyer the
// Farmer sees on the request in Market Linking.

// ─────────────────────────────────────────────────────────────────────────────

class _TransactionDetailsSheet extends StatelessWidget {
  final FarmerTransactionModel transaction;
  const _TransactionDetailsSheet({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = transaction;
    final money = NumberFormat('#,##0.00');
    final dateTime = DateFormat('MMM d, yyyy · h:mm a');
    final isCoop = t.sellingType == 'offer_to_cooperative';

    // Every row is shown only when it has something to say (no empty
    // placeholders), in a fixed order: what was sold, how, and to whom.
    final rows = <MapEntry<String, String>>[
      MapEntry(l10n.rptSellingChannel, sellingTypeLabel(t.sellingType)),
      if (t.marketType != null)
        MapEntry(l10n.rptMarketType, MarketTypeDisplay.label(l10n, t.marketType)),
      if ((t.cropCategory ?? '').isNotEmpty)
        MapEntry(l10n.txnCropCategory, t.cropCategory!),
      MapEntry(l10n.rptQuantity, formatQuantityUnit(t.quantityKg, t.unit)),
      if (t.pricePerKg != null)
        MapEntry(
          t.sellingType == 'marketplace' ? l10n.txnPrice : l10n.mlkDetailAgreedPrice,
          formatPricePerUnit(t.pricePerKg!, t.unit),
        ),
      MapEntry(l10n.rptAmount, '₱${money.format(t.amount)}'),
      MapEntry(
        l10n.txnCompletedOn,
        // A cooperative sale and a Market Linking sale carry a day, not a clock
        // time worth showing; the others keep the time they were completed.
        isCoop
            ? DateFormat('MMM d, yyyy').format(t.transactionDate)
            : dateTime.format(t.transactionDate),
      ),
      if (t.deliveredAt != null)
        MapEntry(l10n.txnDeliveredOn, DateFormat('MMM d, yyyy').format(t.deliveredAt!)),
      if ((t.referenceNo ?? '').isNotEmpty) MapEntry(l10n.rptReferenceNo, t.referenceNo!),
      if ((t.batchNumber ?? '').isNotEmpty)
        MapEntry(l10n.txnHarvestBatch, formatBatchNumber(t.batchNumber)),
      if (t.orderStatus != null)
        MapEntry(l10n.rptOrderStatus, adminOrderStatusLabel(l10n, t.orderStatus!)),
      if ((t.fulfillmentMethod ?? '').isNotEmpty)
        MapEntry(
          l10n.txnFulfillment,
          t.fulfillmentMethod == 'delivery' ? l10n.txnDelivery : l10n.txnPickup,
        ),
      // Who bought: an external buyer, or the Cooperative itself.
      if (isCoop)
        MapEntry(l10n.rptSoldTo, AppConstants.cooperativeName)
      else if ((t.buyerName ?? '').trim().isNotEmpty)
        MapEntry(l10n.rptSoldTo, t.buyerName!.trim()),
      if ((t.buyerContact ?? '').trim().isNotEmpty)
        MapEntry(l10n.mlkDetailBuyerContact, t.buyerContact!.trim()),
      if ((t.buyerEmail ?? '').trim().isNotEmpty)
        MapEntry(l10n.mlkDetailBuyerEmail, t.buyerEmail!.trim()),
    ];

    return ManagementModalShell(
      title: t.cropName,
      subtitle: sellingTypeLabel(t.sellingType),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.cropImageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Image.network(
                t.cropImageUrl!,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < rows.length; i++)
            _DetailRow(
              label: rows[i].key,
              value: rows[i].value,
              isLast: i == rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {

  final String label;
  final String value;
  final bool isLast;
  const _DetailRow({required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_outlined,
                size: 40, color: AppConstants.outline.withValues(alpha: 0.60)),
          ),
          const SizedBox(height: 20),
          Text(
            hasFilter
                ? AppLocalizations.of(context).txnNoMatchTitle
                : AppLocalizations.of(context).txnEmptyTitle,
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppConstants.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? AppLocalizations.of(context).txnNoMatchBody
                : AppLocalizations.of(context).txnEmptyBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────


