import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

/// Read-only view of a farmer's own DA-AMAD Market Linking enrollment(s).
/// No actions of any kind — buyer name/contact and any inventory-batch tie
/// are deliberately never shown here; that's admin-side bookkeeping, not
/// something the farmer needs to see.
class MyMarketLinkingScreen extends StatefulWidget {
  const MyMarketLinkingScreen({super.key});

  @override
  State<MyMarketLinkingScreen> createState() => _MyMarketLinkingScreenState();
}

class _MyMarketLinkingScreenState extends State<MyMarketLinkingScreen> {
  final _repo = MarketLinkingRepository();
  List<MarketLinkingModel> _entries = [];
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    // fetchAll() is RLS-scoped to the caller's own rows for a farmer
    // account — no farmerId filter needed or possible from this side.
    final entries = await _repo.fetchAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Column(
        children: [
          _TopBar(title: 'My Market Linking', onBack: () => context.pop()),
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — your market linking records may not be up to date."),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                : _entries.isEmpty
                    ? Center(
                        child: Text('No enrollments yet.',
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    : RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (_, i) => _EnrollmentCard(entry: _entries[i], cs: cs, sagana: sagana),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentCard extends StatelessWidget {
  final MarketLinkingModel entry;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _EnrollmentCard({required this.entry, required this.cs, required this.sagana});

  static const _stages = ['Submitted', 'Buyer Found', 'Completed'];

  int get _stageIndex {
    switch (entry.status) {
      case MarketLinkingStatus.buyerFound: return 1;
      case MarketLinkingStatus.completed: return 2;
      default: return 0;
    }
  }

  Color get _statusColor {
    switch (entry.status) {
      case MarketLinkingStatus.submitted: return AppConstants.warningAmber;
      case MarketLinkingStatus.buyerFound: return AppConstants.buyerBlue;
      case MarketLinkingStatus.completed: return AppConstants.successGreen;
      case MarketLinkingStatus.cancelled: return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = entry.status == MarketLinkingStatus.cancelled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${entry.cropName} Program — DA-AMAD',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(entry.status.label.toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: _statusColor)),
              ),
            ],
          ),
          Text('${entry.seasonYear} Season',
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),

          if (!isCancelled)
            Row(
              children: List.generate(_stages.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final passed = (i ~/ 2) < _stageIndex;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: passed ? _statusColor.withValues(alpha: 0.4) : cs.outline.withValues(alpha: 0.15),
                    ),
                  );
                }
                final dotIndex = i ~/ 2;
                final reached = dotIndex <= _stageIndex;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reached ? _statusColor : cs.outline.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_stages[dotIndex],
                        style: GoogleFonts.inter(
                          fontSize: 9, fontWeight: FontWeight.w600,
                          color: reached ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.6),
                        )),
                  ],
                );
              }),
            ),

          const SizedBox(height: 14),
          Row(
            children: [
              if (entry.volumeKg != null) ...[
                Icon(Icons.scale_outlined, size: 13, color: cs.outline),
                const SizedBox(width: 4),
                Text('${entry.volumeKg!.toStringAsFixed(0)} kg committed',
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
              // Price shown only once there's a real match — never before,
              // since there's nothing real to show pre-match. Buyer name
              // and contact are deliberately never shown to the farmer.
              if (entry.pricePerKg != null &&
                  (entry.status == MarketLinkingStatus.buyerFound ||
                      entry.status == MarketLinkingStatus.completed)) ...[
                const SizedBox(width: 12),
                Icon(Icons.payments_outlined, size: 13, color: cs.outline),
                const SizedBox(width: 4),
                Text('₱${entry.pricePerKg!.toStringAsFixed(2)}/kg',
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
              ],
            ],
          ),

          // Buyer's requested quantity — distinct from "kg committed"
          // above (the farmer's own volume at enrollment) and only
          // meaningful once a buyer has actually been matched. Previously
          // captured but never shown to the farmer.
          if (entry.requestedVolumeKg != null &&
              (entry.status == MarketLinkingStatus.buyerFound ||
                  entry.status == MarketLinkingStatus.completed)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 13, color: cs.outline),
                const SizedBox(width: 4),
                Text('Buyer wants ${entry.requestedVolumeKg!.toStringAsFixed(0)} kg',
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],

          if (isCancelled) ...[
            const SizedBox(height: 10),
            Text('This enrollment was cancelled.',
                style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// Same blurred-glass pattern used across this session's admin detail screens
// — copied rather than shared, same file-scoped convention.

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
