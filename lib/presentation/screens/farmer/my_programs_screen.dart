import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

class MyProgramsScreen extends StatefulWidget {
  const MyProgramsScreen({super.key});

  @override
  State<MyProgramsScreen> createState() => _MyProgramsScreenState();
}

class _MyProgramsScreenState extends State<MyProgramsScreen> {
  final _repo = FarmerProfileRepository();
  List<MyProgramEntry> _programs = [];
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
    final programs = await _repo.fetchMyPrograms();
    if (!mounted) return;
    setState(() {
      _programs = programs;
      _isLoading = false;
    });
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'withdrawn': return 'Withdrawn';
      case 'completed': return 'Completed';
      default: return 'Active';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              if (!_isOnline)
                const OfflineBanner(message: "You're offline — your program enrollment details may not be up to date."),
              const SizedBox(height: 4),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                      : _programs.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 80),
                              Center(
                                child: Text(
                                  'You are not enrolled in any programs yet.\n'
                                  'Go back to Programs to browse and request one.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                              itemCount: _programs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) => _ProgramCard(
                                entry: _programs[i],
                                formatDate: _formatDate,
                                statusLabel: _statusLabel,
                              ),
                            ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: 'My Programs',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final MyProgramEntry entry;
  final String Function(DateTime) formatDate;
  final String Function(String) statusLabel;

  const _ProgramCard({
    required this.entry,
    required this.formatDate,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = entry.isSalesProgram ? AppConstants.successGreen : AppConstants.programPurple;
    // A single BoxDecoration can't mix a borderRadius with a non-uniform
    // Border (different colors per side) — Flutter throws "A borderRadius
    // can only be given on borders with uniform colors." at paint time.
    // This card only rounds its right corners (border: uniform, radius-
    // safe) and sits beside a separate colored stripe widget, added at
    // the return GestureDetector(...) below.
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppConstants.radiusLg)),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48, height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                clipBehavior: Clip.antiAlias,
                child: (entry.programImageUrl != null && entry.programImageUrl!.isNotEmpty)
                    ? Image.network(
                        entry.programImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          entry.isSalesProgram ? Icons.storefront_rounded : Icons.volunteer_activism_rounded,
                          color: accent,
                          size: 22,
                        ),
                      )
                    : Icon(
                        entry.isSalesProgram ? Icons.storefront_rounded : Icons.volunteer_activism_rounded,
                        color: accent,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.programName,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      entry.isSalesProgram ? 'Sales Program' : 'Distribution Program',
                      style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(statusLabel(entry.enrollmentStatus),
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                            color: accent)),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppConstants.outline),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 12),
          if (entry.isSalesProgram) ...[
            Text('Tap for program details & available products',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          ] else if (!entry.isDistributed)
            Text('Awaiting distribution',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The actual distributed item's photo (from Inventory
                // Management, via the existing cooperative_inventory join)
                // — not a separate upload, per the cross-module image reuse
                // rule.
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (entry.itemImageUrl != null && entry.itemImageUrl!.isNotEmpty)
                      ? Image.network(
                          entry.itemImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.inventory_2_outlined,
                              size: 16,
                              color: AppConstants.primaryGreen),
                        )
                      : const Icon(Icons.inventory_2_outlined,
                          size: 16, color: AppConstants.primaryGreen),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Received ${entry.quantityGiven?.toStringAsFixed(1)}'
                    '${entry.itemUnit != null ? ' ${entry.itemUnit}' : ''}'
                    '${entry.itemName != null ? ' ${entry.itemName}' : ''} on ${formatDate(entry.distributedAt!)}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurface),
                  ),
                ),
              ],
            ),
            if (entry.isRevenueShare) ...[
              const SizedBox(height: 6),
              if (entry.isSettled)
                Text(
                  'Returned ₱${entry.amountReturned?.toStringAsFixed(2)} on ${formatDate(entry.settledAt!)}',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppConstants.successGreen),
                )
              else
                Text(
                  entry.expectedReturnPercent != null
                      ? 'A ${entry.expectedReturnPercent}% return is due to the cooperative once sold.'
                      : 'A return is due to the cooperative once sold.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.warningAmber),
                ),
            ],
          ],
        ],
      ),
    );

    // Every enrolled program now opens Program Details (Full Workflow) —
    // previously only sales-purpose active programs were tappable at all;
    // a distribution/benefit program row did nothing on tap.
    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.programDetails,
        extra: {'entry': entry},
      ),
      // IntrinsicHeight, not a bare Row — CrossAxisAlignment.stretch tries
      // to stretch children to the Row's own height, but inside a
      // ListView.separated item that height is unbounded (0..Infinity),
      // which crashes with "BoxConstraints forces an infinite height."
      // IntrinsicHeight measures the tallest child first and constrains
      // the Row to that real height instead.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppConstants.radiusLg)),
              ),
            ),
            Expanded(child: card),
          ],
        ),
      ),
    );
  }
}