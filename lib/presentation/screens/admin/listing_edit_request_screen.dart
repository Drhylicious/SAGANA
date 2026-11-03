import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/listing_edit_request_model.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/edit_request_widgets.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// A Farmer's request to change a PUBLISHED listing, for a Manager / Officer to
/// decide. The listing stays published exactly as it is until then: this screen
/// shows what is published now beside what the Farmer asks for, then approves
/// (the change is applied) or disapproves (a reason is required and goes to the
/// Farmer; only the request is rejected).
class ListingEditRequestScreen extends StatefulWidget {
  final String requestId;
  const ListingEditRequestScreen({super.key, required this.requestId});

  @override
  State<ListingEditRequestScreen> createState() => _ListingEditRequestScreenState();
}

class _ListingEditRequestScreenState extends State<ListingEditRequestScreen> {
  final _repo = AdminListingRepository();
  ListingEditRequest? _request;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    final r = await _repo.fetchEditRequestById(widget.requestId);
    if (!mounted) return;
    setState(() {
      _request = r;
      _loading = false;
    });
  }

  String _error(Object e, String fallback) =>
      e is PostgrestException && e.message.isNotEmpty ? e.message : fallback;

  Future<void> _approve() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l = AppLocalizations.of(context);
    var saving = false;
    await showManagementModal(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ManagementModalShell(
          title: l.leApproveTitle,
          body: Text(l.leApproveBody),
          footer: ManagementModalActions(
            primaryLabel: l.leApproveAction,
            isLoading: saving,
            onPrimary: () async {
              setSheet(() => saving = true);
              setState(() => _busy = true);
              String? error;
              try {
                await _repo.approveEditRequest(widget.requestId);
              } catch (e) {
                error = _error(e, l.leDecisionFailed);
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              setState(() => _busy = false);
              if (error == null) {
                AppToast.show(context, l.leApprovedToast);
                context.pop(true);
              } else {
                AppToast.show(context, error, isError: true);
                _load();
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _disapprove() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l = AppLocalizations.of(context);
    final reasonCtrl = TextEditingController();
    var saving = false;
    await showManagementModal(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ManagementModalShell(
          title: l.leDisapproveTitle,
          body: TextFormField(
            controller: reasonCtrl,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(hintText: l.leDisapproveHint),
          ),
          footer: ManagementModalActions(
            primaryLabel: l.leDisapproveConfirm,
            isDestructive: true,
            isLoading: saving,
            onPrimary: () async {
              // A message shown over a dialog must render in front of it.
              if (reasonCtrl.text.trim().isEmpty) {
                AppToast.show(ctx, l.leReasonRequired, isError: true);
                return;
              }
              setSheet(() => saving = true);
              setState(() => _busy = true);
              String? error;
              try {
                await _repo.rejectEditRequest(
                  requestId: widget.requestId,
                  reason: reasonCtrl.text,
                );
              } catch (e) {
                error = _error(e, l.leDecisionFailed);
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              setState(() => _busy = false);
              if (error == null) {
                AppToast.show(context, l.leDisapprovedToast);
                context.pop(true);
              } else {
                AppToast.show(context, error, isError: true);
                _load();
              }
            },
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = _request;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(title: l.leEditRequestTitle, onBack: () => context.pop()),
          Expanded(
            child: _loading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                : r == null
                    ? Center(child: Text(l.listingReviewNotFound))
                    : RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            _Header(request: r),
                            const SizedBox(height: 14),
                            if (r.isPending) ...[
                              EditRequestNotice(text: l.leStaysPublished),
                              const SizedBox(height: 14),
                            ],
                            EditRequestComparison(request: r),
                            const SizedBox(height: 14),
                            _Context(request: r),
                            if (!r.isPending) ...[
                              const SizedBox(height: 14),
                              _Decision(request: r),
                            ],
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: () => context.push(
                                AppRoutes.adminListingHistory,
                                extra: {'listingId': r.listingId, 'title': r.cropName},
                              ),
                              icon: const Icon(Icons.history_rounded, size: 18),
                              label: Text(l.leViewHistory),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: (r != null && r.isPending)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _disapprove,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.errorRed,
                          side: const BorderSide(color: AppConstants.errorRed),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(l.leDisapproveAction),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _busy ? null : _approve,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(l.leApproveAction),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

// ─── Pieces (also used by the Pending Approvals list) ───────────────────────

class _Header extends StatelessWidget {
  final ListingEditRequest request;
  const _Header({required this.request});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final name = (request.variety ?? '').trim().isEmpty
        ? request.cropName
        : '${request.cropName} — ${request.variety}';
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_jm();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(context),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.primaryContainer,
            child: Text(
              request.farmerName.isEmpty ? 'F' : request.farmerName[0].toUpperCase(),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppConstants.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  request.farmerName,
                  style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurface),
                ),
                Text(
                  l.leRequestedOn(when.format(request.createdAt)),
                  style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          EditRequestStatusChip(status: request.status),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
    border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
  );
}

/// What is published now beside what the Farmer asks for. A field that is not
/// being changed says so, so the Manager sees at a glance what actually differs.
class EditRequestComparison extends StatelessWidget {
  final ListingEditRequest request;
  const EditRequestComparison({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = request;
    final unit = r.unit;
    final qtyChanged = (r.shownQuantity * 100).round() != (r.proposedQuantity * 100).round();
    final priceChanged = (r.shownPrice * 100).round() != (r.proposedPrice * 100).round();
    final descChanged = (r.shownDescription ?? '').trim() != r.proposedDescription.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.leRequestedChanges,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _ValueRow(
            label: l.editListingFieldQuantity(unitOrDefault(unit)),
            current: formatQuantityUnit(r.shownQuantity, unit),
            proposed: qtyChanged ? formatQuantityUnit(r.proposedQuantity, unit) : null,
          ),
          _ValueRow(
            label: l.editListingFieldPrice,
            current: formatPricePerUnit(r.shownPrice, unit),
            proposed: priceChanged ? formatPricePerUnit(r.proposedPrice, unit) : null,
          ),
          _TextRow(
            label: l.editListingFieldDescription,
            current: r.shownDescription ?? '',
            proposed: descChanged ? r.proposedDescription : null,
          ),
          _PhotoRow(
            label: l.editListingFieldPhoto,
            current: r.shownPhotoUrl,
            proposed: r.proposedPhotoUrl,
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String current;
  final String? proposed; // null = not changed
  const _ValueRow({required this.label, required this.current, required this.proposed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final changed = proposed != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: changed
            ? AppConstants.primaryGreen.withValues(alpha: 0.06)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (!changed)
            Row(
              children: [
                Text(
                  current,
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  l.leNoChange,
                  style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _Side(caption: l.leCurrent, value: current, muted: true)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppConstants.primaryGreen),
                ),
                Expanded(child: _Side(caption: l.leProposed, value: proposed!, muted: false)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final String caption;
  final String value;
  final bool muted;
  const _Side({required this.caption, required this.value, required this.muted});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: GoogleFonts.inter(fontSize: 10.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: muted ? cs.onSurfaceVariant : AppConstants.primaryGreen,
            decoration: muted ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }
}

class _TextRow extends StatelessWidget {
  final String label;
  final String current;
  final String? proposed;
  const _TextRow({required this.label, required this.current, required this.proposed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final changed = proposed != null;
    Widget block(String caption, String text, {required bool highlight}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: highlight
            ? AppConstants.primaryGreen.withValues(alpha: 0.06)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: GoogleFonts.inter(fontSize: 10.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            text.isEmpty ? '—' : text,
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: cs.onSurface),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
          if (!changed)
            block(l.leNoChange, current, highlight: false)
          else ...[
            block(l.leCurrent, current, highlight: false),
            block(l.leProposed, proposed!, highlight: true),
          ],
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final String label;
  final String? current;
  final String? proposed;
  const _PhotoRow({required this.label, required this.current, required this.proposed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    Widget photo(String caption, String? url) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: GoogleFonts.inter(fontSize: 10.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: (url == null || url.isEmpty)
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.eco_outlined, color: cs.outline),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined, color: cs.outline),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (proposed == null)
          Row(
            children: [
              Expanded(child: Row(children: [photo(l.leCurrent, current)])),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 20),
                  child: Text(
                    l.lePhotoUnchanged,
                    style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              photo(l.leCurrent, current),
              const SizedBox(width: 10),
              photo(l.lePhotoChanged, proposed),
            ],
          ),
      ],
    );
  }
}

class _Context extends StatelessWidget {
  final ListingEditRequest request;
  const _Context({required this.request});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final ordered = request.orderedSoFar;
    final free = request.batchAvailable;
    final lines = <String>[
      if (ordered != null && ordered > 0)
        l.editListingOrdered(formatQuantityUnit(ordered, request.unit)),
      if (free != null && request.proposedQuantity > request.shownQuantity)
        l.leBatchFree(formatQuantityUnit(free, request.unit)),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line, style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurface)),
            ),
        ],
      ),
    );
  }
}

class _Decision extends StatelessWidget {
  final ListingEditRequest request;
  const _Decision({required this.request});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final when = request.reviewedAt == null
        ? ''
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
              .add_jm()
              .format(request.reviewedAt!);
    final by = (request.reviewerName ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EditRequestStatusChip(status: request.status),
              const SizedBox(width: 8),
              Text(when, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ],
          ),
          if (by.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(l.leDecidedBy(by), style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurface)),
          ],
          if ((request.reviewReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              request.reviewReason!.trim(),
              style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: cs.onSurface),
            ),
          ],
        ],
      ),
    );
  }
}
