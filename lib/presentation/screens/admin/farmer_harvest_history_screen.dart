import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../widgets/harvest_log_widgets.dart';

class AdminFarmerHarvestHistoryScreen extends StatefulWidget {
  const AdminFarmerHarvestHistoryScreen({super.key, this.farmerId});

  final String? farmerId;

  @override
  State<AdminFarmerHarvestHistoryScreen> createState() => _AdminFarmerHarvestHistoryScreenState();
}

class _AdminFarmerHarvestHistoryScreenState extends State<AdminFarmerHarvestHistoryScreen> {
  final _repo = HarvestRepository();

  List<HarvestModel> _harvests = [];
  Map<String, double> _stats = {'total_yield': 0, 'synced_percent': 100};
  String _activeCrop = 'All';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.farmerId == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllHarvestsForFarmer(widget.farmerId!),
      _repo.fetchHistoryStatsForFarmer(widget.farmerId!),
    ]);
    if (!mounted) return;
    setState(() {
      _harvests = results[0] as List<HarvestModel>;
      _stats = results[1] as Map<String, double>;
      _isLoading = false;
    });
  }

  List<String> get _cropOptions =>
      ['All', ..._harvests.map((h) => h.cropName).toSet()];

  List<HarvestModel> get _filtered => _harvests.where((h) {
        final matchesCrop = _activeCrop == 'All' || h.cropName == _activeCrop;
        final matchesSearch = _searchQuery.isEmpty ||
            h.cropName.toLowerCase().contains(_searchQuery.toLowerCase());
        return matchesCrop && matchesSearch;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(l10n.farmerHarvestHistoryTitle,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 18, color: cs.onSurface)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.farmerId == null
                  ? Center(child: Text(l10n.farmerHarvestHistoryNoFarmerSelected))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: l10n.farmerHarvestHistorySearchHint,
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              filled: true,
                              fillColor: sagana.cardBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                          const SizedBox(height: 14),
                          HarvestSummaryStats(stats: _stats, isLoading: _isLoading),
                          const SizedBox(height: 14),
                          if (!_isLoading)
                            HarvestCropChips(
                              options: _cropOptions,
                              active: _activeCrop,
                              onSelected: (c) => setState(() => _activeCrop = c),
                            ),
                          const SizedBox(height: 16),
                          if (_isLoading)
                            const Center(child: Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: CircularProgressIndicator(color: AppConstants.primaryGreen),
                            ))
                          else if (_filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text(l10n.farmerHarvestHistoryNoRecords,
                                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
                              ),
                            )
                          else
                            ..._filtered.map((h) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: HarvestLogEntry(harvest: h),
                                )),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}