import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/broadcast_model.dart';
import '../../../data/repositories/broadcast_repository.dart';

String recipientTypeLabel(AppLocalizations l10n, RecipientType type) {
  switch (type) {
    case RecipientType.allMembers:       return l10n.recipientTypeAllMembers;
    case RecipientType.allBuyers:        return l10n.recipientTypeAllBuyers;
    case RecipientType.outstandingLoans: return l10n.recipientTypeOutstandingLoans;
    case RecipientType.specificCrop:     return l10n.recipientTypeSpecificCrop;
    case RecipientType.specificFarmer:   return l10n.recipientTypeSpecificFarmer;
    case RecipientType.specificBuyer:    return l10n.recipientTypeSpecificBuyer;
  }
}

String broadcastCategoryLabel(AppLocalizations l10n, BroadcastCategory cat) {
  switch (cat) {
    case BroadcastCategory.meeting:   return l10n.broadcastCategoryMeeting;
    case BroadcastCategory.financial: return l10n.broadcastCategoryFinancial;
    case BroadcastCategory.harvest:   return l10n.broadcastCategoryHarvest;
    case BroadcastCategory.update:    return l10n.broadcastCategoryUpdate;
    case BroadcastCategory.general:   return l10n.broadcastCategoryGeneral;
  }
}

class BroadcastHistoryScreen extends StatefulWidget {
  const BroadcastHistoryScreen({super.key});

  @override
  State<BroadcastHistoryScreen> createState() => _BroadcastHistoryScreenState();
}

class _BroadcastHistoryScreenState extends State<BroadcastHistoryScreen> {
  final _repo = BroadcastRepository();
  final _searchCtrl = TextEditingController();

  List<BroadcastModel> _items = [];
  bool _isLoading = true;
  BroadcastCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await _repo.fetchBroadcastHistory();
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  List<BroadcastModel> get _filteredItems {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _items.where((item) {
      final matchesCategory =
          _selectedCategory == null || item.category == _selectedCategory;
      final matchesQuery =
          query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.body.toLowerCase().contains(query) ||
          item.recipientLabel.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l10n.broadcastHistoryTitle,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.broadcastHistorySearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: sagana.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusLg,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<BroadcastCategory?>(
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: l10n.broadcastHistoryCategoryLabel,
                    filled: true,
                    fillColor: sagana.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusLg,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<BroadcastCategory?>(
                      value: null,
                      child: Text(l10n.broadcastHistoryAllCategories),
                    ),
                    ...BroadcastCategory.values.map(
                      (cat) => DropdownMenuItem<BroadcastCategory?>(
                        value: cat,
                        child: Text(broadcastCategoryLabel(l10n, cat)),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppConstants.primaryGreen,
                    ),
                  )
                : _filteredItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        l10n.broadcastHistoryNoResults,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _filteredItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final timeLabel = item.isPending
                          ? l10n.broadcastScheduledFor(
                              formatBroadcastSchedule(item.scheduledAt!),
                              item.recipientCount,
                            )
                          : _formatTime(l10n, item.sentAt!);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: sagana.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg,
                          ),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppConstants.primaryGreen.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusFull,
                                    ),
                                  ),
                                  child: Text(
                                    item.category.label.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: AppConstants.primaryGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.people_alt_rounded,
                                  size: 14,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${item.recipientCount} • ${item.recipientLabel}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  timeLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: cs.outline,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(AppLocalizations l10n, DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inDays > 0) {
      return l10n.buyerNotifTimeDaysAgo(diff.inDays);
    }
    if (diff.inHours > 0) {
      return l10n.buyerNotifTimeHoursAgo(diff.inHours);
    }
    if (diff.inMinutes > 0) {
      return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
    }
    return l10n.broadcastJustNow;
  }
}
