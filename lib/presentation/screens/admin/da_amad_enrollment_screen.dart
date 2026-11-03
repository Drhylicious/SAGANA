import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Manager / Officer > Marketplace > Market Linking > Manage Enrollments.
///
/// A farmer applies once to join the DA-AMAD Ginger Market Linking program and
/// the Manager approves or declines. Two sections, switched by tapping their
/// headers or by swiping left / right:
/// - **Pending (n)**: applications waiting for a decision.
/// - **Enrolled (n)**: farmers approved into Market Linking, including farmers
///   who are already in it from before enrollment needed review.
/// A declined application leaves both lists (the farmer is told, and may apply
/// again, which puts a new application in Pending).
class DaAmadEnrollmentScreen extends StatefulWidget {
  const DaAmadEnrollmentScreen({super.key});

  @override
  State<DaAmadEnrollmentScreen> createState() => _DaAmadEnrollmentScreenState();
}

class _DaAmadEnrollmentScreenState extends State<DaAmadEnrollmentScreen>
    with SingleTickerProviderStateMixin {
  final _repo = MarketLinkingRepository();
  late final TabController _tabs;
  TableChangeWatcher? _watcher;

  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  bool _loadFailed = false;
  List<DaAmadEnrollmentModel> _pending = [];
  List<DaAmadEnrollmentModel> _enrolled = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
    // A farmer applying, or another Manager deciding, updates both lists and
    // their counts without a pull-down.
    _watcher = TableChangeWatcher(
      tables: const ['da_amad_enrollments', 'market_linking_programs'],
      onChange: () {
        if (mounted) _load();
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    try {
      final lists = await _repo.fetchEnrollmentQueue();
      if (!mounted) return;
      setState(() {
        _pending = lists.pending;
        _enrolled = lists.enrolled;
        _loadFailed = false;
        _isLoading = false;
        _hasLoadedOnce = true;
      });
    } catch (_) {
      if (!mounted) return;
      // Keep what is already on screen on a failed refresh; only say so when
      // there is nothing to show.
      setState(() {
        _loadFailed = !_hasLoadedOnce;
        _isLoading = false;
      });
    }
  }

  void _showReviewModal(DaAmadEnrollmentModel item) {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final notesCtrl = TextEditingController();
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final l10n = AppLocalizations.of(ctx);
            Future<void> respond(bool approve) async {
              if (!approve && notesCtrl.text.trim().isEmpty) {
                AppToast.show(ctx, l10n.mlEnrollReasonRequired, isError: true);
                return;
              }
              setSheet(() => isSaving = true);
              final ok = await _repo.respondToEnrollment(
                id: item.id,
                approve: approve,
                notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              if (!mounted) return;
              AppToast.show(
                context,
                ok
                    ? (approve ? l10n.mlEnrollApprovedToast : l10n.mlEnrollDeclinedToast)
                    : l10n.adminOrderDetailFailedTryAgain,
                isError: !ok,
              );
            }

            return ManagementModalShell(
              title: item.farmerName,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.mlEnrollModalProgram,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.mlEnrollModalBody,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.mlEnrollNotesLabel,
                      hintText: l10n.mlEnrollNotesHint,
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
                      child: Text(l10n.mlEnrollDecline),
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
                          : Text(l10n.mlEnrollApprove),
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
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(title: l10n.mlEnrollTitle, onBack: () => Navigator.of(context).pop()),
            // Section headers: tap to switch, or swipe the list below. The
            // underline slides with the swipe.
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
                ),
              ),
              child: TabBar(
                controller: _tabs,
                labelColor: AppConstants.primaryGreen,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: AppConstants.primaryGreen,
                indicatorWeight: 3,
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(text: '${l10n.mlEnrollPending} (${_pending.length})'),
                  Tab(text: '${l10n.mlEnrollEnrolled} (${_enrolled.length})'),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildList(l10n, cs, _pending, l10n.mlEnrollEmptyPending),
                        _buildList(l10n, cs, _enrolled, l10n.mlEnrollEmptyEnrolled),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    AppLocalizations l10n,
    ColorScheme cs,
    List<DaAmadEnrollmentModel> items,
    String emptyMessage,
  ) {
    // Always a scrollable, so pulling down reloads from an empty or failed list.
    final Widget content;
    if (_loadFailed || items.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
        children: [
          Icon(
            _loadFailed ? Icons.cloud_off_rounded : Icons.how_to_reg_outlined,
            size: 40,
            color: cs.outline,
          ),
          const SizedBox(height: 12),
          Text(
            _loadFailed ? l10n.mlEnrollLoadFailed : emptyMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      );
    } else {
      content = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => EnrollmentCard(
          item: items[i],
          onReview: items[i].status == DaAmadEnrollmentStatus.pending
              ? () => _showReviewModal(items[i])
              : null,
        ),
      );
    }
    return RefreshIndicator(
      color: AppConstants.primaryGreen,
      onRefresh: _load,
      child: content,
    );
  }
}

/// How an enrollment reads on its card: label, colour and icon. Public so the
/// wording can be tested.
({String label, Color color, IconData icon}) enrollmentStatusView(
  AppLocalizations l10n,
  DaAmadEnrollmentModel e,
) {
  if (e.enrolledWithoutReview) {
    return (
      label: l10n.mlEnrollStatusEnrolled,
      color: AppConstants.successGreen,
      icon: Icons.verified_outlined,
    );
  }
  switch (e.status) {
    case DaAmadEnrollmentStatus.approved:
      return (
        label: l10n.mlEnrollStatusEnrolled,
        color: AppConstants.successGreen,
        icon: Icons.check_circle_rounded,
      );
    case DaAmadEnrollmentStatus.rejected:
      return (
        label: l10n.mlEnrollStatusDeclined,
        color: AppConstants.errorRed,
        icon: Icons.cancel_rounded,
      );
    case DaAmadEnrollmentStatus.pending:
      return (
        label: l10n.mlEnrollStatusPending,
        color: AppConstants.warningAmber,
        icon: Icons.hourglass_top_rounded,
      );
  }
}

/// One farmer's enrollment: who, status, dates, reviewer, and the reason when
/// it was declined. Pending ones carry a Review button.
class EnrollmentCard extends StatelessWidget {
  final DaAmadEnrollmentModel item;
  final VoidCallback? onReview;

  const EnrollmentCard({super.key, required this.item, this.onReview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final view = enrollmentStatusView(l10n, item);
    final fmt = DateFormat('MMM d, yyyy');
    final notes = (item.adminNotes ?? '').trim();
    final declined = item.status == DaAmadEnrollmentStatus.rejected;

    Widget detail(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: cs.outline),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: item.isSuperseded ? 0.8 : 1,
      child: GestureDetector(
        onTap: onReview,
        child: Container(
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: view.color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ProfileAvatar(
                                photoUrl: item.farmerPhotoUrl,
                                displayName: item.farmerName,
                                radius: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.farmerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    Text(
                                      l10n.mlEnrollProgram,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: _StatusPill(view: view)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
                          if (!item.enrolledWithoutReview)
                            detail(
                              Icons.event_outlined,
                              l10n.mlEnrollApplied(fmt.format(item.submittedAt.toLocal())),
                            ),
                          if (item.reviewedAt != null)
                            detail(
                              Icons.fact_check_outlined,
                              [
                                declined
                                    ? l10n.mlEnrollReviewedOn(fmt.format(item.reviewedAt!.toLocal()))
                                    : l10n.mlEnrollApprovedOn(fmt.format(item.reviewedAt!.toLocal())),
                                if ((item.reviewerName ?? '').isNotEmpty)
                                  l10n.mlEnrollReviewedBy(item.reviewerName!),
                              ].join(' '),
                            ),
                          if (item.enrolledWithoutReview)
                            detail(Icons.info_outline_rounded, l10n.mlEnrollEnrolledNote),
                          if (item.requestCount > 0)
                            detail(
                              Icons.local_shipping_outlined,
                              l10n.mlEnrollRequests(item.requestCount),
                            ),
                          if (notes.isNotEmpty)
                            detail(
                              Icons.notes_rounded,
                              declined ? l10n.mlEnrollReason(notes) : l10n.mlEnrollNote(notes),
                            ),
                          if (item.isSuperseded)
                            detail(Icons.history_rounded, l10n.mlEnrollEarlier),
                          if (onReview != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: onReview,
                                icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                                label: Text(l10n.mlEnrollReviewAction),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ({String label, Color color, IconData icon}) view;
  const _StatusPill({required this.view});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: view.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(view.icon, size: 12, color: view.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              view.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: view.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
