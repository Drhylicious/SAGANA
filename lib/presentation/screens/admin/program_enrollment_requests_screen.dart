import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/program_enrollment_request_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../widgets/management_modal.dart';

/// Admin's Program Enrollment Requests review queue — mirrors
/// DaAmadEnrollmentScreen's shape exactly (Pending/Reviewed tabs,
/// Approve/Decline via a review modal), applied to the new farmer-
/// initiated Program enrollment workflow (Full Workflow) instead of
/// Market Linking.
class ProgramEnrollmentRequestsScreen extends StatefulWidget {
  const ProgramEnrollmentRequestsScreen({super.key});

  @override
  State<ProgramEnrollmentRequestsScreen> createState() =>
      _ProgramEnrollmentRequestsScreenState();
}

class _ProgramEnrollmentRequestsScreenState
    extends State<ProgramEnrollmentRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = ProgramRepository();
  late final TabController _tabController;

  bool _isLoading = true;
  List<ProgramEnrollmentRequest> _pending = [];
  List<ProgramEnrollmentRequest> _reviewed = [];

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
      _repo.fetchPendingEnrollmentRequests(),
      _repo.fetchReviewedEnrollmentRequests(),
    ]);
    if (!mounted) return;
    setState(() {
      _pending = results[0];
      _reviewed = results[1];
      _isLoading = false;
    });
  }

  void _showReviewModal(ProgramEnrollmentRequest item) {
    final notesCtrl = TextEditingController();
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> respond(bool approve) async {
              if (!approve && notesCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason.'),
                    backgroundColor: AppConstants.errorRed,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setSheet(() => isSaving = true);
              final ok = await _repo.respondToEnrollmentRequest(
                id: item.id,
                approve: approve,
                notes: notesCtrl.text.trim().isEmpty
                    ? null
                    : notesCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? (approve ? 'Request approved.' : 'Request declined.')
                        : 'Failed. Please try again.',
                  ),
                  backgroundColor: ok
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: item.farmerName ?? 'Farmer',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Requesting enrollment in ${item.programName}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Approving enrolls this farmer into the program immediately — the same result as enrolling them manually from Program Management.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (required if declining)',
                      hintText: 'Reason shown to the farmer if declined',
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
                      child: const Text('Decline'),
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
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
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
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Enrollment Requests',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
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
                        color: AppConstants.primaryGreen,
                      ),
                    )
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

  Widget _buildList(
    List<ProgramEnrollmentRequest> items,
    ColorScheme cs,
    SaganaColors sagana, {
    required bool isPending,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'No pending requests.' : 'No reviewed requests yet.',
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
          final statusColor = item.isApproved
              ? AppConstants.successGreen
              : item.isRejected
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
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.farmerName ?? 'Farmer',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          item.programName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (!isPending &&
                            item.adminNotes != null &&
                            item.adminNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '"${item.adminNotes}"',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isPending)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        item.status.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
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
