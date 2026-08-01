import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/management_modal.dart';

// ─── Model ─────────────────────────────────────────────────────────────────

class CropRequestItem {
  final String id;
  final String farmerId;
  final String farmerName;
  final String requestedName;
  final String category;
  final String cropType;
  final String status;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const CropRequestItem({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.requestedName,
    required this.category,
    required this.cropType,
    required this.status,
    this.adminNotes,
    required this.createdAt,
    this.reviewedAt,
  });
}

// ─── Repository ────────────────────────────────────────────────────────────

class _CropRequestRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<CropRequestItem>> fetchByStatus(String status) async {
    try {
      final rows = await _client
          .from('crop_requests')
          .select(
              'id, farmer_id, requested_name, category, crop_type, status, admin_notes, created_at, reviewed_at')
          .eq('status', status)
          .order('created_at', ascending: status == 'pending');

      if (rows.isEmpty) return [];

      final farmerIds =
          rows.map((r) => r['farmer_id'] as String).toSet().toList();

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);

      final namesByUserId = <String, String>{
        for (final info in infoRows)
          info['user_id'] as String: info['full_name'] as String? ?? 'Unknown',
      };

      return rows.map((r) {
        final farmerId = r['farmer_id'] as String;
        return CropRequestItem(
          id: r['id'] as String,
          farmerId: farmerId,
          farmerName: namesByUserId[farmerId] ?? 'Unknown',
          requestedName: r['requested_name'] as String,
          category: r['category'] as String? ?? 'Other',
          cropType: r['crop_type'] as String? ?? 'open_market',
          status: r['status'] as String,
          adminNotes: r['admin_notes'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
          reviewedAt: r['reviewed_at'] != null
              ? DateTime.tryParse(r['reviewed_at'] as String)
              : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> approve(String requestId, {String? notes, required String cropType}) async {
    try {
      await _client.rpc('approve_crop_request', params: {
        'p_request_id': requestId,
        if (notes != null && notes.isNotEmpty) 'p_admin_notes': notes,
        'p_crop_type': cropType,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reject(String requestId, String notes) async {
    try {
      await _client.rpc('reject_crop_request', params: {
        'p_request_id': requestId,
        'p_admin_notes': notes,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────

/// Crop Request Approval — Admin.
/// Pushed above the shell. Route: /admin/crops/requests
class CropRequestApprovalScreen extends StatefulWidget {
  const CropRequestApprovalScreen({super.key});

  @override
  State<CropRequestApprovalScreen> createState() =>
      _CropRequestApprovalScreenState();
}

class _CropRequestApprovalScreenState extends State<CropRequestApprovalScreen>
    with SingleTickerProviderStateMixin {
  final _repo = _CropRequestRepository();
  late final TabController _tabController;

  bool _isLoading = true;
  List<CropRequestItem> _pending = [];
  List<CropRequestItem> _reviewed = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchByStatus('pending'),
      _repo.fetchByStatus('approved'),
    ]);
    final rejected = await _repo.fetchByStatus('rejected');
    if (!mounted) return;
    setState(() {
      _pending = results[0];
      _reviewed = [...results[1], ...rejected]
        ..sort((a, b) =>
            (b.reviewedAt ?? b.createdAt).compareTo(a.reviewedAt ?? a.createdAt));
      _isLoading = false;
    });
  }

  void _showReviewModal(CropRequestItem item) {
    final notesCtrl = TextEditingController();
    String selectedCropType = item.cropType;
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> respond(bool approve) async {
            if (!approve && notesCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('Please provide a reason so the farmer understands.'),
                backgroundColor: AppConstants.errorRed,
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }
            setSheet(() => isSaving = true);
            final ok = approve
                ? await _repo.approve(item.id,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    cropType: selectedCropType)
                : await _repo.reject(item.id, notesCtrl.text.trim());
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
              content: Text(ok
                  ? (approve
                      ? 'Crop approved and added to the catalog'
                      : 'Request declined')
                  : 'Failed. Try again.'),
              backgroundColor:
                  ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: item.requestedName,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.farmerName} · ${item.category}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Approving adds this crop to the official catalog immediately — every farmer '
                  'will be able to select it going forward.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedCropType,
                  decoration: const InputDecoration(
                    labelText: 'Crop Type *',
                    helperText: 'Farmer-suggested — confirm or change before approving',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'sp3_cooperative', child: Text('Cooperative Crop (SP3 Buying)')),
                    DropdownMenuItem(value: 'da_amad_market', child: Text('DA-AMAD Reference Crop')),
                    DropdownMenuItem(value: 'open_market', child: Text('Open Market Crop')),
                  ],
                  onChanged: (v) => setSheet(() => selectedCropType = v!),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (required if declining)',
                    hintText: 'Reason the farmer will see, or approval notes',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isSaving ? null : () => respond(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.errorRed,
                      side: const BorderSide(color: AppConstants.errorRed),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : () => respond(true),
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text('Crop Requests',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: cs.onSurface)),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppConstants.primaryGreen,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: AppConstants.primaryGreen,
              tabs: [
                Tab(text: 'Pending (${_pending.length})'),
                const Tab(text: 'Reviewed'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_pending, cs, sagana, isPending: true),
                        _buildList(_reviewed, cs, sagana, isPending: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<CropRequestItem> items, ColorScheme cs, SaganaColors sagana,
      {required bool isPending}) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'No pending crop requests' : 'No reviewed requests yet',
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final item = items[i];
          final statusColor = item.status == 'approved'
              ? AppConstants.successGreen
              : item.status == 'rejected'
                  ? AppConstants.errorRed
                  : AppConstants.amber;
          return GestureDetector(
            onTap: isPending ? () => _showReviewModal(item) : null,
            child: Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border(left: BorderSide(color: statusColor, width: 4)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.requestedName,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: cs.onSurface)),
                        Text('${item.farmerName} · ${item.category}',
                            style:
                                GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                        if (!isPending &&
                            item.adminNotes != null &&
                            item.adminNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('"${item.adminNotes}"',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: cs.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                  if (isPending)
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant)
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      ),
                      child: Text(item.status.toUpperCase(),
                          style: GoogleFonts.inter(
                              fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}