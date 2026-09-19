import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';

/// Admin review for Cooperative Product Sales Program purchase requests —
/// see supabase_schema_program_product_sales.sql. Spans every 'sales'
/// program, not just one, since an admin confirming payments wants one
/// place to see all pending requests rather than checking each program
/// separately. Pushed above the shell. Route: /admin/programs/purchases
class ProgramPurchaseReviewScreen extends StatefulWidget {
  const ProgramPurchaseReviewScreen({super.key});

  @override
  State<ProgramPurchaseReviewScreen> createState() =>
      _ProgramPurchaseReviewScreenState();
}

class _ProgramPurchaseReviewScreenState
    extends State<ProgramPurchaseReviewScreen> with SingleTickerProviderStateMixin {
  final _repo = ProgramRepository();
  late final TabController _tabController;

  bool _isLoading = true;
  List<ProgramPurchase> _pending = [];
  List<ProgramPurchase> _history = [];

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
      _repo.fetchPurchasesByStatus('pending'),
      _repo.fetchPurchasesByStatus('paid'),
    ]);
    final cancelled = await _repo.fetchPurchasesByStatus('cancelled');
    if (!mounted) return;
    setState(() {
      _pending = results[0];
      _history = [...results[1], ...cancelled]
        ..sort((a, b) =>
            (b.confirmedAt ?? b.cancelledAt ?? b.requestedAt)
                .compareTo(a.confirmedAt ?? a.cancelledAt ?? a.requestedAt));
      _isLoading = false;
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  void _showReviewSheet(ProgramPurchase purchase) {
    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> confirm() async {
            setSheet(() => isSaving = true);
            bool ok = true;
            try {
              await _repo.confirmPurchase(purchase.id);
            } catch (_) {
              ok = false;
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            _showSnack(
              ok ? 'Payment confirmed — stock updated.' : 'Could not confirm this purchase.',
              isError: !ok,
            );
          }

          Future<void> cancel() async {
            final reason = await _showCancelReasonDialog(ctx);
            if (reason == null) return; // dialog dismissed without cancelling
            if (!ctx.mounted) return;
            setSheet(() => isSaving = true);
            final ok = await _repo.cancelPurchase(purchase.id, reason);
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            _showSnack(
              ok ? 'Purchase cancelled.' : 'Could not cancel this purchase.',
              isError: !ok,
            );
          }

          return ManagementModalShell(
            title: purchase.itemName,
            subtitle: '${purchase.farmerName} · ${purchase.programName}',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _purchaseImage(purchase, Theme.of(ctx).colorScheme),
                const SizedBox(height: 14),
                _reviewRow('Quantity', '${purchase.quantity.toStringAsFixed(1)} ${purchase.unit}'),
                _reviewRow('Unit Price', '₱${purchase.unitPrice.toStringAsFixed(2)}'),
                _reviewRow('Total', '₱${purchase.totalAmount.toStringAsFixed(2)}', emphasize: true),
                const SizedBox(height: 12),
                Text(
                  'Confirming marks this as paid and deducts stock. Only confirm once payment has actually been received.',
                  style: GoogleFonts.inter(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isSaving ? null : cancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.errorRed,
                      side: const BorderSide(color: AppConstants.errorRed),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : confirm,
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm Payment'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // Cancellation now lives in its own dialog (spec: dialog → reason required
  // → confirm-or-close-without-cancelling → X top-left) rather than an
  // always-visible optional text field inside the review sheet — the old
  // field also let admins submit an empty reason, which the DB's
  // cancel_program_purchase(p_purchase_id, p_reason) has no default for and
  // would silently reject.
  Future<String?> _showCancelReasonDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(builder: (dialogCtx, setDialogState) {
          String? errorText;
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('Cancel Purchase',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('Please provide a reason for cancelling this purchase.',
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 14),
                    child: TextField(
                      controller: reasonCtrl,
                      autofocus: true,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Cancellation reason',
                        hintText: 'e.g. Farmer requested cancellation',
                        errorText: errorText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorRed),
                        onPressed: () {
                          final reason = reasonCtrl.text.trim();
                          if (reason.isEmpty) {
                            setDialogState(() => errorText = 'A reason is required to cancel.');
                            return;
                          }
                          Navigator.pop(dialogCtx, reason);
                        },
                        child: const Text('Confirm Cancellation'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // Full-width hero image for the purchase's item, not a small squeezed
  // thumbnail — this is a details view with room to actually show the
  // photo, matching the "give the image enough space" feedback applied
  // across every other image spot in this feature.
  Widget _purchaseImage(ProgramPurchase purchase, ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: (purchase.imageUrl != null && purchase.imageUrl!.isNotEmpty)
            ? Image.network(
                purchase.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.storefront_rounded, size: 40, color: cs.outline.withValues(alpha: 0.4)),
                ),
              )
            : Container(
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.storefront_rounded, size: 40, color: cs.outline.withValues(alpha: 0.4)),
              ),
      ),
    );
  }

  // Read-only counterpart to _showReviewSheet — History purchases (paid or
  // cancelled) have no pending actions, just the same information laid out
  // the same way, matching the tap-to-see-details pattern used for
  // Pending items instead of leaving History rows untappable.
  void _showPurchaseDetailsSheet(ProgramPurchase purchase) {
    final statusColor = purchase.status == 'paid'
        ? AppConstants.successGreen
        : purchase.status == 'cancelled'
            ? AppConstants.errorRed
            : AppConstants.amber;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: purchase.itemName,
          subtitle: '${purchase.farmerName} · ${purchase.programName}',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _purchaseImage(purchase, cs),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Status', style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(purchase.status.toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
                  ),
                ],
              ),
              _reviewRow('Farmer', purchase.farmerName),
              _reviewRow('Quantity', '${purchase.quantity.toStringAsFixed(1)} ${purchase.unit}'),
              _reviewRow('Unit Price', '₱${purchase.unitPrice.toStringAsFixed(2)}'),
              _reviewRow('Total', '₱${purchase.totalAmount.toStringAsFixed(2)}', emphasize: true),
              _reviewRow('Requested', _formatDate(purchase.requestedAt)),
              if (purchase.confirmedAt != null)
                _reviewRow('Confirmed', _formatDate(purchase.confirmedAt!)),
              if (purchase.cancelledAt != null)
                _reviewRow('Cancelled', _formatDate(purchase.cancelledAt!)),
              if (purchase.cancelReason != null && purchase.cancelReason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Cancellation reason', style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('"${purchase.cancelReason}"',
                    style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: cs.onSurface)),
              ],
            ],
          ),
          footer: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _reviewRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: emphasize ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: emphasize ? AppConstants.primaryGreen : AppConstants.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    child: Text('Purchase Requests',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 18, color: cs.onSurface)),
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
                const Tab(text: 'History'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_pending, cs, sagana, isPending: true),
                        _buildList(_history, cs, sagana, isPending: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<ProgramPurchase> items, ColorScheme cs, SaganaColors sagana,
      {required bool isPending}) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'No pending purchase requests.' : 'No purchase history yet.',
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
          final statusColor = item.status == 'paid'
              ? AppConstants.successGreen
              : item.status == 'cancelled'
                  ? AppConstants.errorRed
                  : AppConstants.amber;
          return GestureDetector(
            onTap: isPending ? () => _showReviewSheet(item) : () => _showPurchaseDetailsSheet(item),
            child: Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border(left: BorderSide(color: statusColor, width: 4)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.itemName,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
                        Text('${item.farmerName} · ${item.programName}',
                            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                        Text(
                          '${item.quantity.toStringAsFixed(1)} ${item.unit} · ₱${item.totalAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                        if (!isPending && item.status == 'cancelled' &&
                            item.cancelReason != null && item.cancelReason!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('"${item.cancelReason}"',
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
