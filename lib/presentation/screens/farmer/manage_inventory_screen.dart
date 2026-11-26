import '../../../core/l10n/localized_labels.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/utils/listing_order.dart' show stableGroupSort;
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/repositories/informal_sale_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/channel_only_badge.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/crop_photo_capture.dart';
import '../../widgets/shared_widgets.dart';

import '../../widgets/management_modal.dart';
import '../../widgets/stock_widgets.dart';
import '../../widgets/coop_offer_widgets.dart' show coopKg, coopPeso;
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../data/services/server_only.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/shelf_life_widgets.dart';
import '../../../data/models/shelf_life_model.dart';
import '../../../data/repositories/shelf_life_repository.dart';
import '../../widgets/feature_restriction_notice.dart';
import '../../../data/models/member_restriction.dart';
import '../../../data/services/feature_restriction_service.dart';

/// The second set of filter chips: where each batch stands against its shelf
/// life, including what was reported as rotten (a loss).
enum _ConditionFilter { all, good, needsCheck, rotten }

class ManageInventoryScreen extends StatefulWidget {
  /// A batch to open the produce check for as soon as the list has loaded (the
  /// shelf-life notifications carry it).
  final String? checkBatchId;

  const ManageInventoryScreen({super.key, this.checkBatchId});

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen> {
  final _repo = InventoryRepository();
  final _cropRepo = CropRepository();
  final _offerRepo = CooperativeOfferRepository();
  final _marketLinkingRepo = MarketLinkingRepository();
  final _searchController = TextEditingController();

  List<InventoryBatchModel> _allBatches = [];
  List<InventoryBatchModel> _filtered = [];
  Map<String, double> _summary = {'available': 0, 'reserved': 0, 'sold': 0};
  Map<String, FarmerCropModel> _cropsById = {};
  bool _hasCrops =
      true; // assume true until loaded, avoids an empty-state flash
  Set<String> _pendingOfferBatchIds = {};
  Set<String> _activeMarketLinkingBatchIds = {};
  DaAmadEnrollmentStatus? _gingerEnrollmentStatus; // null = never enrolled

  String _activeStatusFilter = _StatusFilterRow.all;
  _ConditionFilter _conditionFilter = _ConditionFilter.all;
  final _shelfRepo = ShelfLifeRepository();
  // The produce check asked for by a notification is opened once.
  bool _openedRequestedCheck = false;
  bool _isLoading = true;
  bool _isOnline = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onHarvestRecorded);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onHarvestRecorded);
    _searchController.dispose();
    super.dispose();
  }

  void _onHarvestRecorded() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // Bring shelf-life state up to date first (reminder, expiry-day discount,
    // unavailable listings). The database also does this on a schedule; this
    // call is harmless when there is nothing to do, and does nothing offline.
    await _shelfRepo.process();
    final results = await Future.wait([
      _repo.fetchBatches(),
      _repo.fetchSummary(),
      _cropRepo.fetchCrops(),
      _offerRepo.fetchBatchIdsWithPendingOffers(),
      _marketLinkingRepo.fetchMyActiveSubmissionBatchIds(),
      _marketLinkingRepo.fetchMyEnrollment(),
    ]);
    if (!mounted) return;
    final crops = results[2] as List<FarmerCropModel>;
    setState(() {
      _allBatches = results[0] as List<InventoryBatchModel>;
      _summary = results[1] as Map<String, double>;
      _hasCrops = crops.isNotEmpty;
      _cropsById = {for (final c in crops) c.id: c};
      _pendingOfferBatchIds = results[3] as Set<String>;
      _activeMarketLinkingBatchIds = results[4] as Set<String>;
      _gingerEnrollmentStatus = (results[5] as DaAmadEnrollmentModel?)?.status;
      _applyFilters();
      _isLoading = false;
    });
    _openRequestedCheck();
  }

  /// Opens the produce check a shelf-life notification pointed at.
  void _openRequestedCheck() {
    // "batchId", or "batchId|good" / "batchId|rotten" when the Farmer tapped
    // one of the notification's two answers.
    final requested = widget.checkBatchId;
    if (requested == null || _openedRequestedCheck) return;
    _openedRequestedCheck = true;
    final parts = requested.split('|');
    final answer = parts.length > 1 ? parts[1] : null;
    final match = _allBatches.where((b) => b.id == parts.first);
    if (match.isEmpty || match.first.isFinalizedRotten) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkProduce(match.first, answer: answer);
    });
  }

  Future<void> _checkProduce(
    InventoryBatchModel batch, {
    String? answer,
  }) async {
    if (!_isOnline) {
      PostActionFeedback.error(
        context,
        AppLocalizations.of(
          context,
        ).enhThisActionRequiresAnInternetConnectionPleaseTry,
      );
      return;
    }
    final changed = await showShelfLifeCheckSheet(
      context,
      batch: batch,
      answer: answer,
    );
    if (changed && mounted) _loadData();
  }

  bool _matchesStatus(InventoryBatchModel b, String filter) {
    switch (filter) {
      case _StatusFilterRow.available:
        return b.status == 'available';
      case _StatusFilterRow.reserved:
        return b.status == 'reserved' && !b.isFinalizedRotten;
      // Folds 'withdrawn' into "Sold" — both represent inventory no longer
      // available to dispose of. A batch emptied by a rotten report is a loss,
      // not a sale: it is under the Rotten chip instead.
      case _StatusFilterRow.sold:
        return (b.isSoldOut || b.isWithdrawn) && !b.isFinalizedRotten;
      case _StatusFilterRow.lowStock:
        return b.status == 'low_stock';
      default:
        return true;
    }
  }

  bool _matchesCondition(InventoryBatchModel b, _ConditionFilter filter) {
    final hasStock = b.availableKg > 0 || b.reservedKg > 0;
    switch (filter) {
      case _ConditionFilter.all:
        return true;
      case _ConditionFilter.rotten:
        return b.hasLoss;
      case _ConditionFilter.needsCheck:
        return b.hasCheckableStock && (b.shelfLife?.needsCheck ?? false);
      case _ConditionFilter.good:
        return hasStock &&
            !b.hasLoss &&
            !(b.shelfLife?.needsCheck ?? false);
    }
  }

  int _statusCount(String filter) =>
      _allBatches.where((b) => _matchesStatus(b, filter)).length;

  int _conditionCount(_ConditionFilter filter) =>
      _allBatches.where((b) => _matchesCondition(b, filter)).length;

  void _setConditionFilter(_ConditionFilter filter) {
    setState(() {
      _conditionFilter = filter;
      _applyFilters();
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilters();
    });
  }

  void _setStatusFilter(String filter) {
    setState(() {
      _activeStatusFilter = filter;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    // The batches arrive newest first. That order is kept, and only whole
    // groups move: batches that can still be sold stay on top, and the ones
    // that cannot (Sold Out, Rotten/Lost) go to the bottom, newest first too.
    _filtered = stableGroupSort(
      _allBatches.where((b) {
        if (!_matchesStatus(b, _activeStatusFilter)) return false;
        if (!_matchesCondition(b, _conditionFilter)) return false;

        if (q.isEmpty) return true;
        return b.cropName.toLowerCase().contains(q) ||
            b.batchNumber.toLowerCase().contains(q);
      }),
      (b) => (b.isSoldOut || b.isWithdrawn || b.isLost) ? 1 : 0,
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _showUpdateQuantityDialog(InventoryBatchModel batch) {
    final controller = TextEditingController(
      text: formatQuantity(batch.availableKg),
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          AppLocalizations.of(context).enhUpdateQuantity,
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${batch.cropName} • ${formatBatchNumber(batch.batchNumber)}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [DecimalInputFormatter(max: batch.availableKg)],
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                ).enhAvailableQuantity((unitOrDefault(batch.unit)).toString()),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(
                context,
              ).enhTotalBatchQuantityYouCanOnlyDecreaseThis(
                (formatQuantityUnit(batch.quantityKg, batch.unit)).toString(),
              ),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
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
              final maxAvailable = batch.availableKg;
              final raw = controller.text.trim();
              // 0 is allowed here on purpose (it empties the batch); every
              // other value must be a valid decimal within the stock on hand.
              final isZero =
                  raw.isNotEmpty &&
                  raw != '.' &&
                  RegExp(r'^0*\.?0*$').hasMatch(raw);
              final newQty = isZero
                  ? 0.0
                  : parseDecimal(raw, max: maxAvailable);
              if (newQty == null) {
                PostActionFeedback.error(
                  context,
                  AppLocalizations.of(
                    context,
                  ).enhEnterAValueBetweenAndIncreasingBeyondThe(
                    (formatQuantityUnit(maxAvailable, batch.unit)).toString(),
                  ),
                );
                return;
              }
              if (!_isOnline) {
                Navigator.pop(context);
                PostActionFeedback.error(
                  context,
                  AppLocalizations.of(
                    context,
                  ).enhUpdatingQuantityRequiresAnInternetConnectionPleaseTry,
                );
                return;
              }
              Navigator.pop(context);
              await _repo.updateQuantity(batch.id, roundQuantity(newQty));
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text(
              AppLocalizations.of(context).save,
              style: GoogleFonts.poppins(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Marketplace, Offer to Cooperative and Market Linking need the Farmer's own
  /// camera photo of the crop. Returns the batch ready to sell (with the photo
  /// the Farmer just took, if it was missing), or null if they did not add one.
  /// Informal Sale never goes through this.
  Future<InventoryBatchModel?> _withSellingPhoto(
    InventoryBatchModel batch,
    String why,
  ) async {
    if (batch.hasPhoto) return batch;
    final rosterPhoto = _cropsById[batch.cropId]?.displayImageUrl;
    if (rosterPhoto != null && rosterPhoto.isNotEmpty) {
      return batch.withPhoto(rosterPhoto);
    }
    final url = await requireCropPhotoToSell(
      context,
      repo: _cropRepo,
      cropId: batch.cropId,
      cropName: batch.cropName,
      why: why,
    );
    if (url == null || !mounted) return null;
    _loadData();
    return batch.withPhoto(url);
  }

  Future<void> _handleBatchAction(InventoryBatchModel batch) async {
    // Reported as rotten: nothing can be sold, the card only leads to history.
    if (batch.isFinalizedRotten) {
      context.pushRoute(AppRoutes.harvestHistory, extra: batch.cropName);
      return;
    }
    // Recorded past its shelf life or expired and not confirmed yet: no selling
    // channel (Marketplace, Offer to Cooperative, Informal Sale, DA-AMAD Market
    // Linking) takes it until the Farmer confirms the produce. The database
    // refuses it as well.
    final isExpired = batch.shelfLife?.stage == ShelfLifeStage.expired;
    if (batch.isOnShelfLifeHold || (isExpired && batch.availableKg > 0)) {
      await _checkProduce(batch);
      return;
    }

    // Ginger (DA-AMAD-exclusive) batches never go through the generic
    // Marketplace/Cooperative/Informal disposal flow below — Market
    // Linking is their only path. Intercepted here, before the
    // isAvailable branching: a submission reserves only the quantity
    // submitted, so the batch can still read as 'available' (with the rest of
    // its stock) while a request is open, and would otherwise fall into the
    // wrong branch.

    if (batch.exclusiveChannel == AppConstants.channelDaAmad) {
      if (_activeMarketLinkingBatchIds.contains(batch.id)) {
        context.pushRoute(AppRoutes.myMarketLinking);
      } else if (_gingerEnrollmentStatus != DaAmadEnrollmentStatus.approved) {
        // Not yet an approved Market Linking participant — route to the
        // enrollment flow instead of the sale dialog. Covers "never
        // enrolled," "pending," and "rejected" alike; MyMarketLinkingScreen
        // shows the right state for each on its own.
        context.pushRoute(AppRoutes.myMarketLinking).then((_) => _loadData());
      } else {
        if (!_isOnline) {
          PostActionFeedback.error(
            context,
            AppLocalizations.of(
              context,
            ).enhThisActionRequiresAnInternetConnectionPleaseTry,
          );
          return;
        }
        if (!await ensureFeatureAvailable(context, RestrictableFeature.gingerDaAmad)) return;
        if (!mounted) return;
        final ready = await _withSellingPhoto(
          batch,
          AppLocalizations.of(context).enhSubmitThisBatchForMarketLinking,
        );
        if (ready == null || !mounted) return;
        final result = await showSubmitToSellDialog(context, batch: ready);
        if (result == true) _loadData();
      }
      return;
    }

    if (!batch.isAvailable) {
      // Reserved batches now branch on which disposal path actually
      // claimed them, rather than assuming 'reserved' always means a
      // marketplace listing — a batch offered to the cooperative and
      // awaiting confirmation has nothing relevant on My Listings.
      if (batch.isReserved && _pendingOfferBatchIds.contains(batch.id)) {
        _showPendingOfferStatus(batch);
      } else if (batch.isReserved) {
        context.goTab(AppRoutes.myListings);
      } else {
        context.pushRoute(AppRoutes.harvestHistory, extra: batch.cropName);
      }
      return;
    }

    // Marketplace/Cooperative/Informal all depend on live server state
    // (available_kg at call time, market price, row locks) — unlike
    // Harvest Entry, these are deliberately NOT queued for offline replay.
    // Block with a clear message instead of letting the RPC fail silently.
    if (!_isOnline) {
      PostActionFeedback.error(
        context,
        AppLocalizations.of(
          context,
        ).enhThisActionRequiresAnInternetConnectionPleaseTry,
      );
      return;
    }

    final action = await showDisposalActionSheet(
      context,
      cropName: batch.cropName,
      availableKg: batch.availableKg,
      unit: batch.unit,
      // Produce received from a Free Distribution program cannot be offered back to the cooperative.
      isCoopEligible: batch.isCoopEligible && !batch.fromProgram,
      exclusiveChannel: batch.exclusiveChannel,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case DisposalAction.marketplace:
        if (!await ensureFeatureAvailable(context, RestrictableFeature.marketplaceListing)) return;
        if (!mounted) return;
        final ready = await _withSellingPhoto(
          batch,
          AppLocalizations.of(context).enhListThisOnTheMarketplace,
        );
        if (ready == null || !mounted) return;
        final result = await context.pushRoute(
          AppRoutes.createListing,
          extra: ready,
        );
        if (result == true) _loadData();
        break;
      case DisposalAction.cooperative:
        if (!await ensureFeatureAvailable(context, RestrictableFeature.coopOffer)) return;
        if (!mounted) return;
        final ready = await _withSellingPhoto(
          batch,
          AppLocalizations.of(context).enhOfferThisToTheCooperative,
        );
        if (ready == null || !mounted) return;
        final result = await showOfferToCooperativeDialog(
          context,
          batch: ready,
        );
        if (result == true) _loadData();
        break;
      case DisposalAction.informal:
        if (!await ensureFeatureAvailable(context, RestrictableFeature.informalSale)) return;
        if (!mounted) return;
        final result = await showRecordInformalSaleDialog(
          context,
          batch: batch,
        );
        if (result == true) _loadData();
        break;
    }
  }

  // A batch with an open cooperative offer: show where the negotiation stands
  // (and let the Farmer answer a counteroffer) rather than a static message.
  Future<void> _showPendingOfferStatus(InventoryBatchModel batch) async {
    final offerId = await _offerRepo.fetchPendingOfferIdForBatch(batch.id);
    if (!mounted) return;
    if (offerId == null) {
      await context.pushRoute(AppRoutes.farmerCoopOffers);
    } else {
      await context.pushRoute(AppRoutes.farmerCoopOfferDetail, extra: offerId);
    }
    if (mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const TopBarSpacer(height: 72),
                    CachedDataNotice(
                      screen: 'inventory_batches',
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(
                        context,
                      ).offlineInventoryActions,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        onRefresh: _loadData,
                        child: ListView(
                          // No FAB or bottom nav under this pushed (non-tab)
                          // screen to clear — 100px of bottom padding was
                          // leaving genuinely dead space at the end of the
                          // scroll, not reserved space for anything.
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            // Summary metrics
                            _SummaryMetrics(
                              summary: _summary,
                              isLoading: _isLoading,
                            ),
                            const SizedBox(height: 20),

                            // Search bar
                            _SearchBar(controller: _searchController),
                            const SizedBox(height: 12),

                            // Status filter chips (replaces the old binary
                            // Show-Sold toggle)
                            // The same "Label (n)" chips the Manager / Officer
                            // screens use (MarketplaceFilterBar).
                            MarketplaceFilterBar<String>(
                              selected: _activeStatusFilter,
                              onSelected: _setStatusFilter,
                              options: [
                                for (final option in _StatusFilterRow.options)
                                  MarketplaceFilterOption(
                                    value: option,
                                    label: localizeBuiltinLabel(
                                      AppLocalizations.of(context),
                                      option,
                                    ),
                                    count: _statusCount(option),
                                    color: AppConstants.primaryGreen,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Second set: the condition of the produce, with
                            // what was reported as rotten (a loss).
                            MarketplaceFilterBar<_ConditionFilter>(
                              selected: _conditionFilter,
                              onSelected: _setConditionFilter,
                              options: [
                                MarketplaceFilterOption(
                                  value: _ConditionFilter.all,
                                  label: AppLocalizations.of(
                                    context,
                                  ).shelfFilterAllConditions,
                                  count: _conditionCount(_ConditionFilter.all),
                                  color: AppConstants.primaryGreen,
                                ),
                                MarketplaceFilterOption(
                                  value: _ConditionFilter.good,
                                  label: AppLocalizations.of(
                                    context,
                                  ).shelfFilterGood,
                                  count: _conditionCount(_ConditionFilter.good),
                                  color: AppConstants.successGreen,
                                ),
                                MarketplaceFilterOption(
                                  value: _ConditionFilter.needsCheck,
                                  label: AppLocalizations.of(
                                    context,
                                  ).shelfFilterNeedsCheck,
                                  count: _conditionCount(
                                    _ConditionFilter.needsCheck,
                                  ),
                                  color: AppConstants.warningAmber,
                                ),
                                MarketplaceFilterOption(
                                  value: _ConditionFilter.rotten,
                                  label: AppLocalizations.of(
                                    context,
                                  ).shelfFilterRotten,
                                  count: _conditionCount(
                                    _ConditionFilter.rotten,
                                  ),
                                  color: AppConstants.errorRed,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Section title
                            Text(
                              AppLocalizations.of(
                                context,
                              ).reportsInventoryBatches,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Batch list
                            if (_isLoading)
                              ...List.generate(
                                3,
                                (_) => const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: SkeletonBlock(height: 120),
                                ),
                              )
                            else if (_filtered.isEmpty)
                              _InventoryEmptyState(
                                hasCrops: _hasCrops,
                                hasFilter:
                                    _searchQuery.isNotEmpty ||
                                    _activeStatusFilter !=
                                        _StatusFilterRow.all ||
                                    _conditionFilter != _ConditionFilter.all,
                                onGoToMyCrops: () =>
                                    context.pushRoute(AppRoutes.cropListing),
                                onRecordHarvest: () => context.pushRoute(
                                  AppRoutes.selectCropForHarvest,
                                ),
                              )
                            else
                              ..._filtered.map(
                                (b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _BatchCard(
                                    batch: b,
                                    crop: _cropsById[b.cropId],
                                    hasPendingOffer: _pendingOfferBatchIds
                                        .contains(b.id),
                                    hasActiveMarketLinking:
                                        _activeMarketLinkingBatchIds.contains(
                                          b.id,
                                        ),
                                    gingerEnrollmentApproved:
                                        _gingerEnrollmentStatus ==
                                        DaAmadEnrollmentStatus.approved,
                                    onUpdateQuantity: () =>
                                        _showUpdateQuantityDialog(b),
                                    onViewHarvestRecord: () =>
                                        context.pushRoute(
                                          AppRoutes.harvestHistory,
                                          extra: b.cropName,
                                        ),
                                    onActionTap: () => _handleBatchAction(b),
                                    onCheckProduce: () => _checkProduce(b),
                                    onViewStockHistory: () =>
                                        showStockHistorySheet(
                                          context,
                                          batch: b,
                                        ),
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
                    title: AppLocalizations.of(context).enhManageInventory,
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

// ─────────────────────────────────────────────────────────────────────────────
// Summary Metrics — built on the shared ReportIconStatCard (the same KPI
// tile Admin's Reports module uses), per the redesign's request to match
// Admin's KPI card pattern rather than this screen's own bespoke style.
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryMetrics extends StatelessWidget {
  final Map<String, double> summary;
  final bool isLoading;

  const _SummaryMetrics({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    // The three cards are kg totals. Batches measured in another unit (sack,
    // piece ...) are not added to them: SAGANA never adds different units.
    final otherUnits = (summary['other_unit_batches'] ?? 0).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cards(context),
        if (!isLoading && otherUnits > 0) _otherUnitsNote(context, otherUnits),
      ],
    );
  }

  Widget _otherUnitsNote(BuildContext context, int count) => Padding(
    padding: const EdgeInsets.only(top: 8, left: 4),
    child: Text(
      count == 1
          ? AppLocalizations.of(context).enhOtherUnitBatchExcluded
          : AppLocalizations.of(
              context,
            ).enhOtherUnitBatchesExcluded((count).toString()),
      style: GoogleFonts.inter(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _cards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.check_circle_outline_rounded,
            accent: AppConstants.successGreen,
            label: AppLocalizations.of(context).reportsAvailable,
            value: isLoading ? '—' : '${_fmt(summary['available'] ?? 0)} kg',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.hourglass_top_rounded,
            accent: AppConstants.warningAmber,
            label: AppLocalizations.of(context).reportsReserved,
            value: isLoading ? '—' : '${_fmt(summary['reserved'] ?? 0)} kg',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.sell_outlined,
            accent: AppConstants.primaryGreen,
            label: AppLocalizations.of(context).reportsSold,
            value: isLoading ? '—' : '${_fmt(summary['sold'] ?? 0)} kg',
          ),
        ),
      ],
    );
  }

  String _fmt(double v) => formatQuantity(v);
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
      style: GoogleFonts.inter(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).enhSearchBatchOrCrop,
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
        filled: true,
        fillColor: context.saganaColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Filter Row — replaces the old binary Show-Sold toggle with real
// filter chips over InventoryBatchModel.status, same visual pattern as
// CropCategoryChips elsewhere in this redesign round.
// ─────────────────────────────────────────────────────────────────────────────

/// The stock-status filter values. The chips themselves are the shared
/// MarketplaceFilterBar ("Label (n)"), the same row the Manager / Officer
/// screens use, so the design is identical everywhere.
abstract final class _StatusFilterRow {
  static const all = 'All';
  static const available = 'Available';
  static const reserved = 'Reserved';
  static const sold = 'Sold';
  static const lowStock = 'Low Stock';
  static const options = [all, available, reserved, sold, lowStock];
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Card
// ─────────────────────────────────────────────────────────────────────────────

/// Icon+label row for a PopupMenuItem — matches Admin Inventory
/// Management's own menu-row pattern (admin_inventory_screen.dart's
/// _menuRow), used as the reference for how this screen's 3-dot menu
/// should behave.
Widget _batchMenuRow(IconData icon, String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Flexible(child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: color))),
    ],
  );
}

class _BatchCard extends StatelessWidget {
  final InventoryBatchModel batch;
  final FarmerCropModel? crop;
  final bool hasPendingOffer;
  final bool hasActiveMarketLinking;
  final bool gingerEnrollmentApproved;
  final VoidCallback onUpdateQuantity;
  final VoidCallback onViewHarvestRecord;
  final VoidCallback onActionTap;
  final VoidCallback onCheckProduce;
  final VoidCallback onViewStockHistory;

  const _BatchCard({
    required this.batch,
    this.crop,
    this.hasPendingOffer = false,
    this.hasActiveMarketLinking = false,
    this.gingerEnrollmentApproved = false,
    required this.onUpdateQuantity,
    required this.onViewHarvestRecord,
    required this.onActionTap,
    required this.onCheckProduce,
    required this.onViewStockHistory,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(context, batch.status);
    final l10n = AppLocalizations.of(context);
    final shelf = batch.shelfLife;
    final hasCheckable = batch.hasCheckableStock;
    final isRottenLost = batch.isFinalizedRotten;
    // Something is left (and not finalized rotten) and the Farmer should look at it now.
    final needsCheck = hasCheckable && (shelf?.needsCheck ?? false);

    // A batch reported as rotten is greyed out: it is a record, not stock.
    return Opacity(
      opacity: isRottenLost ? 0.55 : 1,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                context
                    .adaptiveSurface(
                      batch.isSoldOut || isRottenLost
                          ? const Color(0xFFF1F5F9)
                          : Colors.white,
                    )
                    .withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BatchCropImage(crop: crop, category: crop?.category ?? ''),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              batch.cropName,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (isRottenLost)
                              ShelfLifeTag(
                                label: l10n.shelfTagRottenLost,
                                color: Theme.of(context).colorScheme.outline,
                              )
                            else
                              _StatusBadge(status: batch.status),
                            if (batch.isOnShelfLifeHold && !isRottenLost)
                              ShelfLifeTag(
                                label: l10n.shelfTagOnHold,
                                color: AppConstants.errorRed,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // The long batch number may take two lines on a
                        // narrow phone rather than overflowing.
                        Text(
                          formatBatchNumber(batch.batchNumber),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (batch.exclusiveChannel != null) ...[
                          const SizedBox(height: 6),
                          ChannelOnlyBadge(channel: batch.exclusiveChannel),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'check':
                          onCheckProduce();
                          break;
                        case 'update':
                          onUpdateQuantity();
                          break;
                        case 'history':
                          onViewHarvestRecord();
                          break;
                        case 'stock':
                          onViewStockHistory();
                          break;
                      }
                    },
                    // "Delete Batch" removed — a batch can already carry
                    // real selling/transaction history (listings, coop
                    // offers, informal sales, market linking), and
                    // deleting it would erase that record. Historical
                    // records are preserved, not deletable, same
                    // reasoning already applied to Crop Roster's crops.
                    itemBuilder: (context) => [
                      // Confirm it is still good (and set how long), or report
                      // it as rotten. Offered only while unspoiled stock remains.
                      if (hasCheckable)
                        PopupMenuItem(
                          value: 'check',
                          child: _batchMenuRow(
                            Icons.fact_check_outlined,
                            l10n.shelfCheckMenu,
                            Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      if (!batch.isSoldOut && !isRottenLost)
                        PopupMenuItem(
                          value: 'update',
                          child: _batchMenuRow(
                            Icons.edit_outlined,
                            AppLocalizations.of(context).enhUpdateQuantity,
                            Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'stock',
                        child: _batchMenuRow(
                          Icons.swap_vert_rounded,
                          AppLocalizations.of(context).stockHistoryButton,
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'history',
                        child: _batchMenuRow(
                          Icons.receipt_long_outlined,
                          AppLocalizations.of(context).enhViewHarvestRecord,
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stock progress
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      AppLocalizations.of(context).enhStockOf(
                        (formatQuantity(batch.availableKg)).toString(),
                        (formatQuantityUnit(
                          batch.quantityKg,
                          batch.unit,
                        )).toString(),
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  Text(
                    '${(batch.stockPercent * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusInfo.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: batch.stockPercent,
                  minHeight: 8,
                  backgroundColor: context.adaptiveSurface(
                    const Color(0xFFD5ECF8),
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(statusInfo.accent),
                ),
              ),
              const SizedBox(height: 10),
              // Available / Reserved / Sold (/ Adjusted): the same four figures
              // the database keeps, so this card, the Harvest tab and the
              // Manager's reports always agree.
              StockFiguresRow(batch: batch),
              // Shelf life of THIS harvest (each batch counts down on its own),
              // and what was reported as rotten.
              if (shelf != null && (shelf.isTracked || shelf.hasLoss)) ...[
                const SizedBox(height: 10),
                if (shelf.isTracked && hasCheckable)
                  ShelfLifeLine(shelfLife: shelf),
                if (shelf.hasLoss) ...[
                  if (shelf.isTracked && hasCheckable) const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.shelfLossLine(
                            formatQuantityUnit(shelf.spoiledKg, batch.unit),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (needsCheck) ...[
                const SizedBox(height: 10),
                ShelfLifeNote(
                  text: batch.isOnShelfLifeHold
                      ? l10n.shelfHoldNote
                      : shelf!.stage == ShelfLifeStage.expired
                      ? l10n.shelfExpiredNote
                      : l10n.shelfNearNote(batch.cropName),
                  color: shelfLifeColor(context, shelf!.stage),
                  icon: Icons.fact_check_outlined,
                  action: TextButton(
                    onPressed: onCheckProduce,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text(l10n.shelfCheckNow),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Footer
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).enhHARVESTDATE,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: Theme.of(context).colorScheme.outline,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          batch.harvestDate != null
                              ? DateFormat(
                                  'MMM d, yyyy',
                                ).format(batch.harvestDate!)
                              : DateFormat(
                                  'MMM d, yyyy',
                                ).format(batch.createdAt),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    _ActionButton(
                      // A rotten batch only leads to its history; a batch on
                      // hold (or expired with available stock) must be confirmed
                      // before anything else.
                      status: isRottenLost ? 'lost' : batch.status,
                      overrideLabel:
                          (batch.isOnShelfLifeHold ||
                                  (shelf?.stage == ShelfLifeStage.expired &&
                                      batch.availableKg > 0)) &&
                              !isRottenLost
                          ? l10n.shelfCheckNow
                          : null,
                      hasPendingOffer: hasPendingOffer,
                      isDaAmadExclusive:
                          batch.exclusiveChannel == AppConstants.channelDaAmad,
                      hasActiveMarketLinking: hasActiveMarketLinking,
                      gingerEnrollmentApproved: gingerEnrollmentApproved,
                      onTap: onActionTap,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  _StatusInfo _statusInfo(BuildContext context, String status) {
    switch (status) {
      case 'available':
        return _StatusInfo(accent: AppConstants.successGreen);
      case 'low_stock':
        return _StatusInfo(accent: AppConstants.warningAmber);
      case 'reserved':
        return _StatusInfo(accent: AppConstants.warningAmber);
      case 'sold_out':
        return _StatusInfo(accent: Theme.of(context).colorScheme.outline);
      default:
        return _StatusInfo(accent: Theme.of(context).colorScheme.outline);
    }
  }
}

class _StatusInfo {
  final Color accent;
  _StatusInfo({required this.accent});
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Crop Image — the shared-image system: Crop Roster's Edit Crop
// (Revision D) is the one place a farmer sets a crop's photo, and every
// other context (this card, Record New Harvest, Harvest History) reads
// the exact same FarmerCropModel.displayImageUrl, never a separate copy.
// Neutral background (matching Crop Roster/Select Crop's own fallback),
// not status-tinted, so a real photo isn't fighting an amber/green box
// behind it.
// ─────────────────────────────────────────────────────────────────────────────

class _BatchCropImage extends StatelessWidget {
  final FarmerCropModel? crop;
  final String category;

  const _BatchCropImage({required this.crop, required this.category});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: crop?.hasDisplayImage == true
          ? Image.network(
              crop!.displayImageUrl!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _BatchCropFallbackIcon(category: category),
            )
          : _BatchCropFallbackIcon(category: category),
    );
  }
}

class _BatchCropFallbackIcon extends StatelessWidget {
  final String category;
  const _BatchCropFallbackIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: context.adaptiveSurface(const Color(0xFFDBF1FE))),
      child: Icon(
        FarmerCropModel.iconForCategory(category),
        color: Theme.of(context).colorScheme.primary,
        size: 28,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (status) {
      case 'available':
        label = 'AVAILABLE';
        color = AppConstants.successGreen;
        break;
      case 'low_stock':
        label = AppLocalizations.of(context).reportsLowStockBadge;
        color = AppConstants.warningAmber;
        break;
      case 'reserved':
        label = 'RESERVED';
        color = AppConstants.warningAmber;
        break;
      case 'sold_out':
        label = AppLocalizations.of(context).enhSOLDOUT;
        color = Theme.of(context).colorScheme.outline;
        break;
      case 'withdrawn':
        label = 'WITHDRAWN';
        color = AppConstants.errorRed;
        break;
      default:
        label = status.toUpperCase();
        color = Theme.of(context).colorScheme.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String status;
  final bool hasPendingOffer;
  final bool isDaAmadExclusive;
  final bool hasActiveMarketLinking;
  final bool gingerEnrollmentApproved;
  final VoidCallback onTap;

  /// Replaces the usual label (a batch on shelf-life hold reads "Check Now").
  final String? overrideLabel;

  const _ActionButton({
    required this.status,
    this.overrideLabel,
    this.hasPendingOffer = false,
    this.isDaAmadExclusive = false,
    this.hasActiveMarketLinking = false,
    this.gingerEnrollmentApproved = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    bool isOutlined = false;
    if (overrideLabel != null) {
      label = overrideLabel!;
    } else if (isDaAmadExclusive &&
        (status == 'available' || status == 'low_stock')) {
      // Ginger's only path — never "Create Listing", which would imply
      // the Marketplace/Cooperative/Informal flow that doesn't apply here.
      // A farmer who isn't an approved Market Linking participant yet is
      // guided to enroll first, rather than straight to a sale dialog
      // that would just fail server-side.
      label = hasActiveMarketLinking
          ? AppLocalizations.of(context).enhSeeProgress
          : gingerEnrollmentApproved
          ? AppLocalizations.of(context).enhSubmitToSell
          : AppLocalizations.of(context).enhJoinToSell;
    } else {
      switch (status) {
        case 'available':
        case 'low_stock':
          label = AppLocalizations.of(context).enhCreateListing;
          break;
        case 'reserved':
          // Not "View Order" — a reserved batch with no pending cooperative
          // offer means it's tied to a Marketplace listing, not an order;
          // this switches to the My Listings tab, there's no per-order
          // screen in this path.
          label = hasPendingOffer
              ? AppLocalizations.of(context).enhOfferStatus
              : AppLocalizations.of(context).enhViewListing;
          break;
        default:
          label = AppLocalizations.of(context).enhViewHistory;
          isOutlined = true;
      }
    }

    // Fixed width (not IntrinsicWidth) — this button's label changes with
    // batch status ("Create Listing" / "View Listing" / "Offer Status" /
    // "Submit to Sell" / "See Progress" / "View History"), and hugging each
    // label's own text made the button visibly change size card-to-card.
    // Sized to fit the longest label; text stays on one line, shrinking
    // to fit if needed rather than wrapping and changing card height.
    const buttonWidth = 136.0;

    if (isOutlined) {
      return SizedBox(
        width: buttonWidth,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.outline,
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.poppins(fontSize: 12),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: buttonWidth,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          elevation: 0,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// _BatchActionSheet and _MenuOption removed — the batch action menu is now
// a PopupMenuButton rendered directly in _BatchCard's header (see
// _batchMenuRow above), matching Admin Inventory Management's own 3-dot
// menu pattern instead of the app's centered ManagementModalShell dialog.

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryEmptyState extends StatelessWidget {
  final bool hasCrops;
  final bool hasFilter;
  final VoidCallback onGoToMyCrops;
  final VoidCallback onRecordHarvest;

  const _InventoryEmptyState({
    required this.hasCrops,
    required this.hasFilter,
    required this.onGoToMyCrops,
    required this.onRecordHarvest,
  });

  @override
  Widget build(BuildContext context) {
    // Filtered-to-empty takes priority over the two onboarding cases —
    // a farmer who filtered their own real inventory to nothing isn't
    // missing crops or harvests, they just need to adjust the filter.
    if (hasFilter) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: context.adaptiveSurface(AppConstants.infoBlueBg),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.filter_alt_off_rounded,
                size: 40,
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).enhNoMatchingBatches,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(
                context,
              ).enhTryADifferentSearchOrAdjustYourFilters,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Tier 1 — no crops at all yet.
    if (!hasCrops) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.eco_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).enhYouDonTHaveAnyCropsYet,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).enhAddACropBeforeYouCanBuildUp,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onGoToMyCrops,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text(
                AppLocalizations.of(context).enhGoToCropRoster,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Tier 2 — has crops, but no harvests recorded yet.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: context.adaptiveSurface(AppConstants.infoBlueBg),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context).enhNoInventoryYet,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(
              context,
            ).enhRecordAHarvestToStartBuildingYourInventory,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onRecordHarvest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
            ),
            child: Text(
              AppLocalizations.of(context).enhRecordNewHarvest,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Submit to Sell Dialog (Ginger / Market Linking)
// Ginger's only disposal path — submits a farmer-initiated Market Linking
// request tied to this specific batch (supabase_schema_market_linking_
// farmer_requests.sql), pending admin approval. Mirrors
// _OfferToCooperativeDialog's shape (volume input, pre-filled from
// available stock).
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showSubmitToSellDialog(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _SubmitToSellDialog(batch: batch),
  );
}

class _SubmitToSellDialog extends StatefulWidget {
  final InventoryBatchModel batch;
  const _SubmitToSellDialog({required this.batch});

  @override
  State<_SubmitToSellDialog> createState() => _SubmitToSellDialogState();
}

class _SubmitToSellDialogState extends State<_SubmitToSellDialog> {
  late final TextEditingController _qtyController;
  final _repo = MarketLinkingRepository();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: formatQuantity(widget.batch.availableKg),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = quantityErrorText(
      _qtyController.text,
      max: widget.batch.availableKg,
      unit: widget.batch.unit,
    );
    final qty = parseDecimal(
      _qtyController.text,
      max: widget.batch.availableKg,
    );
    if (error != null || qty == null) {
      setState(
        () => _error = error ?? AppLocalizations.of(context).retQtyInvalid,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await _repo.submitGingerForSale(
        inventoryBatchId: widget.batch.id,
        volumeKg: roundQuantity(qty),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = restrictionMessageOf(e) ??
              (isPhotoRequiredError(e)
                  ? AppLocalizations.of(context).enhTakeAPhotoOfYourActualCropIn
                  : AppLocalizations.of(context).enhCouldNotSubmitPleaseTryAgain);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagementModalShell(
      title: AppLocalizations.of(context).enhSubmitToSell,
      subtitle: AppLocalizations.of(context).enhSPWillReviewThisAndFindADA,

      body: TextField(
        controller: _qtyController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [DecimalInputFormatter(max: widget.batch.availableKg)],
        decoration: InputDecoration(
          labelText: AppLocalizations.of(
            context,
          ).enhQuantityToSubmit((unitOrDefault(widget.batch.unit)).toString()),
          errorText: _error,
        ),
      ),
      footer: ManagementModalActions(
        primaryLabel: AppLocalizations.of(context).enhSubmitRequest,
        isLoading: _isSubmitting,
        onPrimary: _submit,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offer to Cooperative Dialog
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showOfferToCooperativeDialog(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _OfferToCooperativeDialog(batch: batch),
  );
}

class _OfferToCooperativeDialog extends StatefulWidget {
  final InventoryBatchModel batch;
  const _OfferToCooperativeDialog({required this.batch});

  @override
  State<_OfferToCooperativeDialog> createState() =>
      _OfferToCooperativeDialogState();
}

class _OfferToCooperativeDialogState extends State<_OfferToCooperativeDialog> {
  late final TextEditingController _qtyController;
  final _priceController = TextEditingController();
  final _repo = CooperativeOfferRepository();
  bool _isSubmitting = false;
  String? _qtyError;
  String? _priceError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: formatQuantity(widget.batch.availableKg),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final unit = unitOrDefault(widget.batch.unit);
    final qty = parseDecimal(
      _qtyController.text,
      max: widget.batch.availableKg,
    );
    final price = parseDecimal(_priceController.text);

    setState(() {
      _qtyError = quantityErrorText(
        _qtyController.text,
        max: widget.batch.availableKg,
        unit: widget.batch.unit,
      );
      _priceError = price == null ? l10n.coopOfferAskingRequired(unit) : null;
      _submitError = null;
    });
    if (_qtyError != null || _priceError != null) return;

    setState(() => _isSubmitting = true);
    try {
      await _repo.offerToCooperative(
        batch: widget.batch,
        quantityKg: roundQuantity(qty!),
        askingPricePerKg: roundQuantity(price!),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          // The database's own explanation when it wrote one for people (for
          // example the batch is not eligible); otherwise a generic line.
          _submitError =
              readableDatabaseMessage(e) ??
              (e is ServerOnlyException
                  ? e.toString()
                  : AppLocalizations.of(
                      context,
                    ).enhCouldNotSubmitOfferPleaseTryAgain);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final unit = unitOrDefault(widget.batch.unit);
    final enteredQty = double.tryParse(_qtyController.text.trim());
    final enteredPrice = double.tryParse(_priceController.text.trim());
    final exceedsAvailable =
        enteredQty != null && enteredQty > widget.batch.availableKg;

    return ManagementModalShell(
      title: AppLocalizations.of(context).sellingTypeOfferToCooperative,
      subtitle: l10n.coopOfferDialogSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel(
            label: AppLocalizations.of(
              context,
            ).enhQuantityToOffer((unit).toString()),
            cs: cs,
          ),
          TextFormField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: '0.00', errorText: _qtyError),
          ),
          const SizedBox(height: 4),
          Text(
            exceedsAvailable
                ? AppLocalizations.of(
                    context,
                  ).enhOnlyAvailableReduceTheQuantity(
                    (formatQuantityUnit(
                      widget.batch.availableKg,
                      widget.batch.unit,
                    )).toString(),
                  )
                : AppLocalizations.of(context).enhAvailable(
                    (formatQuantityUnit(
                      widget.batch.availableKg,
                      widget.batch.unit,
                    )).toString(),
                  ),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: exceedsAvailable ? FontWeight.w600 : FontWeight.w400,
              color: exceedsAvailable
                  ? AppConstants.errorRed
                  : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _FieldLabel(label: l10n.coopOfferAskingLabel(unit), cs: cs),
          TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter(maxWholeDigits: 6)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixText: '₱ ',
              hintText: '0.00',
              errorText: _priceError,
            ),
          ),
          if (enteredQty != null &&
              enteredQty > 0 &&
              enteredPrice != null &&
              enteredPrice > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.coopTotalPreview(
                coopKg(enteredQty, widget.batch.unit),
                coopPeso(moneyOf(enteredQty, enteredPrice)),
              ),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(
              _submitError!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.errorRed,
              ),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: AppLocalizations.of(context).enhSubmitOffer,
        isLoading: _isSubmitting,
        onPrimary: _submit,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Record Informal Sale Dialog
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showRecordInformalSaleDialog(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _RecordInformalSaleDialog(batch: batch),
  );
}

class _RecordInformalSaleDialog extends StatefulWidget {
  final InventoryBatchModel batch;
  const _RecordInformalSaleDialog({required this.batch});

  @override
  State<_RecordInformalSaleDialog> createState() =>
      _RecordInformalSaleDialogState();
}

class _RecordInformalSaleDialogState extends State<_RecordInformalSaleDialog> {
  late final TextEditingController _qtyController;
  final _buyerController = TextEditingController();
  final _amountController = TextEditingController();
  final _repo = InformalSaleRepository();
  bool _isSubmitting = false;
  String? _qtyError;
  String? _buyerError;
  String? _amountError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: formatQuantity(widget.batch.availableKg),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _buyerController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = parseDecimal(
      _qtyController.text,
      max: widget.batch.availableKg,
    );
    final buyer = _buyerController.text.trim();
    final amount = parseDecimal(_amountController.text);

    setState(() {
      _qtyError = quantityErrorText(
        _qtyController.text,
        max: widget.batch.availableKg,
        unit: widget.batch.unit,
      );
      _buyerError = buyer.isEmpty
          ? AppLocalizations.of(context).enhBuyerNameIsRequired
          : null;
      _amountError = amount == null
          ? priceErrorText(
              _amountController.text,
              label: AppLocalizations.of(context).enhAmountReceived,
            )
          : null;
      _submitError = null;
    });
    if (_qtyError != null || _buyerError != null || _amountError != null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _repo.recordInformalSale(
        batch: widget.batch,
        quantityKg: roundQuantity(qty!),
        buyerName: buyer,
        amount: roundQuantity(amount!),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = restrictionMessageOf(e) ??
              AppLocalizations.of(context).enhCouldNotRecordSalePleaseTryAgain;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unit = unitOrDefault(widget.batch.unit);
    final enteredQty = double.tryParse(_qtyController.text.trim());
    final exceedsAvailable =
        enteredQty != null && enteredQty > widget.batch.availableKg;

    return ManagementModalShell(
      title: AppLocalizations.of(context).enhRecordInformalSale,
      subtitle: AppLocalizations.of(context).enhForASaleMadeOutsideTheAppTo,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel(
            label: AppLocalizations.of(
              context,
            ).enhQuantitySold((unit).toString()),
            cs: cs,
          ),
          TextFormField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: '0.00', errorText: _qtyError),
          ),
          const SizedBox(height: 4),
          Text(
            exceedsAvailable
                ? AppLocalizations.of(
                    context,
                  ).enhOnlyAvailableReduceTheQuantity(
                    (formatQuantityUnit(
                      widget.batch.availableKg,
                      widget.batch.unit,
                    )).toString(),
                  )
                : AppLocalizations.of(context).enhAvailable(
                    (formatQuantityUnit(
                      widget.batch.availableKg,
                      widget.batch.unit,
                    )).toString(),
                  ),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: exceedsAvailable ? FontWeight.w600 : FontWeight.w400,
              color: exceedsAvailable
                  ? AppConstants.errorRed
                  : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: AppLocalizations.of(context).enhBuyerName, cs: cs),
          TextFormField(
            controller: _buyerController,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).enhWhoBoughtIt,
              errorText: _buyerError,
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(
            label: AppLocalizations.of(context).enhAmountReceived355,
            cs: cs,
          ),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter()],
            decoration: InputDecoration(
              prefixText: '₱ ',
              hintText: '0.00',
              errorText: _amountError,
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(
              _submitError!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.errorRed,
              ),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: AppLocalizations.of(context).save,
        isLoading: _isSubmitting,
        onPrimary: _submit,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;

  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
