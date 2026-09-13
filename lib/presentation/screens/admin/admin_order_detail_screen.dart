import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';

/// Admin-facing order detail — approve / cancel / complete a single order.
/// Rebuilt from scratch after admin_order_detail_screen.dart was found to be
/// an accidental copy of the buyer-facing order_detail_screen.dart (still
/// importing BuyerOrderModel/BuyerOrderRepository, no admin actions at all).
/// This version is AdminOrderModel/AdminOrderRepository end to end, and
/// matches the header/card conventions confirmed against
/// order_management_screen.dart and program_management_screen.dart.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  // When true (opened from Buyer Details' read-only Order History), no
  // Approve/Cancel/Complete action is ever shown, regardless of status —
  // closes the bug where those actions were reachable from inside a
  // buyer's profile. See M-marketplace-4.
  final bool readOnly;
  const OrderDetailScreen({super.key, required this.orderId, this.readOnly = false});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _repo = AdminOrderRepository();
  bool _isLoading = true;
  AdminOrderModel? _order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final order = await _repo.fetchOrderById(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = order;
      _isLoading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return AppConstants.successGreen;
      case 'pending': return AppConstants.warningAmber;
      case 'completed': return AppConstants.primaryGreen;
      case 'cancelled': return AppConstants.errorRed;
      default: return AppConstants.outline;
    }
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _confirmApprove() async {
    await _runAction(
      title: 'Approve Order',
      subtitle: 'The buyer will be notified this order is ready.',
      body: const Text(
        'Approving confirms the cooperative can fulfill this order as listed.',
      ),
      primaryLabel: 'Approve Order',
      isDestructive: false,
      action: () => _repo.approveOrder(widget.orderId),
      successMessage: 'Order approved',
    );
  }

  Future<void> _confirmComplete() async {
    await _runAction(
      title: 'Complete Order',
      subtitle: 'Marks this order as picked up and paid.',
      body: const Text(
        'Use this once the buyer has collected and paid for this order at the cooperative.',
      ),
      primaryLabel: 'Complete Order',
      isDestructive: false,
      action: () => _repo.completeOrder(widget.orderId),
      successMessage: 'Order marked complete',
    );
  }

  // Cancelling requires a reason (unlike Approve/Complete, which reuse the
  // generic _runAction flow) — the buyer sees this reason, so the primary
  // button stays disabled until the admin actually enters one.
  Future<void> _confirmCancel() async {
    final reasonCtrl = TextEditingController();
    bool isSaving = false;
    await showManagementModal(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final hasReason = reasonCtrl.text.trim().isNotEmpty;
        return ManagementModalShell(
          title: 'Cancel Order',
          subtitle: 'This cannot be undone.',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cancelling releases the reserved inventory back to the batch. '
                'The buyer will be notified with the reason below.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                onChanged: (_) => setSheet(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Shown to the buyer',
                ),
              ),
            ],
          ),
          footer: ManagementModalActions(
            primaryLabel: 'Cancel Order',
            isDestructive: true,
            isLoading: isSaving,
            onPrimary: !hasReason
                ? null
                : () async {
                    setSheet(() => isSaving = true);
                    String? error;
                    try {
                      await _repo.cancelOrder(widget.orderId, reason: reasonCtrl.text.trim());
                    } catch (_) {
                      error = 'Failed. Please try again.';
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(error ?? 'Order cancelled'),
                      backgroundColor: error != null ? AppConstants.errorRed : AppConstants.successGreen,
                      behavior: SnackBarBehavior.floating,
                    ));
                    if (error == null) _load();
                  },
          ),
        );
      }),
    );
  }

  /// Shared confirm → call repository → feedback → reload flow for all
  /// three actions, so Approve/Complete/Cancel all look and behave the
  /// same way instead of three one-off implementations.
  Future<void> _runAction({
    required String title,
    required String subtitle,
    required Widget body,
    required String primaryLabel,
    required bool isDestructive,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    bool isSaving = false;
    await showManagementModal(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return ManagementModalShell(
          title: title,
          subtitle: subtitle,
          body: body,
          footer: ManagementModalActions(
            primaryLabel: primaryLabel,
            isDestructive: isDestructive,
            isLoading: isSaving,
            onPrimary: () async {
              setSheet(() => isSaving = true);
              String? error;
              try {
                await action();
              } catch (_) {
                error = 'Failed. Please try again.';
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(error ?? successMessage),
                backgroundColor: error != null ? AppConstants.errorRed : AppConstants.successGreen,
                behavior: SnackBarBehavior.floating,
              ));
              if (error == null) _load();
            },
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopBar(
            title: _order != null ? 'Order #${_order!.orderReference}' : 'Order Details',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                : _order == null
                    ? Center(
                        child: Text('Order not found.',
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    : RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                            _buildStatusCard(_order!, cs),
                            const SizedBox(height: 16),
                            if (!_order!.isCancelled) ...[
                              _buildTimeline(_order!),
                              const SizedBox(height: 16),
                            ],
                            _buildBuyerCard(_order!, cs),
                            const SizedBox(height: 16),
                            _buildProductCard(_order!, cs),
                            const SizedBox(height: 16),
                            _buildSummaryCard(_order!, cs),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // Cancel is only ever offered from 'pending' — once an order is
  // 'approved', logically the only forward action left is Complete (why
  // would you cancel an order the cooperative already committed to
  // fulfilling?). Completed/cancelled orders show no actions at all.
  Widget? _buildBottomBar() {
    if (widget.readOnly) return null;
    final order = _order;
    if (order == null || order.isCompleted || order.isCancelled) return null;

    if (order.isPending) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _confirmCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.errorRed,
                    side: const BorderSide(color: AppConstants.errorRed),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text('Cancel Order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  height: 46,
                  // No icon here: at narrow widths (360px) this button
                  // shares the row with "Cancel Order" and the icon + gap
                  // left too little room for "Approve Order", causing the
                  // label to ellipsis-clip.
                  label: 'Approve Order',
                  onPressed: _confirmApprove,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Approved — Cancel Order is gone, Complete Order gets the full row.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: PrimaryButton(
          height: 46,
          icon: Icons.task_alt_rounded,
          label: 'Complete Order',
          onPressed: _confirmComplete,
        ),
      ),
    );
  }

  Widget _buildStatusCard(AdminOrderModel order, ColorScheme cs) {
    final color = _statusColor(order.status);
    final subtitle = switch (order.status) {
      'pending' => 'Awaiting your review',
      'approved' => 'Approved — awaiting completion',
      'completed' => 'Completed',
      _ => 'Cancelled',
    };
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(order.statusLabel.toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('— $subtitle',
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (order.isCancelled && order.notes != null && order.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Reason: ${order.notes}',
                style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(AdminOrderModel order) {
    const steps = ['Pending', 'Approved', 'Completed'];
    final currentIndex = switch (order.status) {
      'approved' => 1,
      'completed' => 2,
      _ => 0,
    };
    return _SectionCard(
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final lineIndex = i ~/ 2;
            final isDone = lineIndex < currentIndex;
            return Expanded(
              child: Container(
                height: 2,
                color: isDone ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.20),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isDone = stepIndex <= currentIndex;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 4),
              Text(steps[stepIndex],
                  style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    color: isDone ? AppConstants.primaryGreen : AppConstants.outline,
                  )),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildBuyerCard(AdminOrderModel order, ColorScheme cs) {
    return _SectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.buyerBlue.withValues(alpha: 0.12),
            backgroundImage: order.buyerPhotoUrl != null
                ? NetworkImage(order.buyerPhotoUrl!)
                : null,
            onBackgroundImageError: order.buyerPhotoUrl != null ? (_, __) {} : null,
            child: order.buyerPhotoUrl != null
                ? null
                : Text(
                    order.buyerName.isNotEmpty ? order.buyerName[0].toUpperCase() : 'B',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppConstants.buyerBlue),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.buyerName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
                if (order.buyerPhone != null)
                  Text(order.buyerPhone!, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(AdminOrderModel order, ColorScheme cs) {
    return _SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: order.listingPhotoUrl != null
                      ? Image.network(order.listingPhotoUrl!, width: 56, height: 56, fit: BoxFit.cover)
                      : Container(width: 56, height: 56, color: AppConstants.limeGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(order.displayName,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ),
              ],
            ),
          ),
          if (order.batchNumber != null || order.harvestDate != null || order.category != null) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 20,
                runSpacing: 10,
                children: [
                  if (order.batchNumber != null) _miniField('Batch Reference', '#${order.batchNumber}', cs),
                  if (order.harvestDate != null) _miniField('Freshness', order.harvestedLabel, cs),
                  if (order.category != null) _miniField('Category', order.category!, cs),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniField(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ],
    );
  }

  Widget _buildSummaryCard(AdminOrderModel order, ColorScheme cs) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Summary', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          _summaryRow('Quantity', '${order.quantityKg.toStringAsFixed(0)} kg', cs),
          _summaryRow('Price per kg', '₱${order.pricePerKg.toStringAsFixed(2)}', cs),
          Divider(height: 20, color: cs.outline.withValues(alpha: 0.10)),
          _summaryRow('Total Amount', '₱${order.totalPrice.toStringAsFixed(2)}', cs, bold: true),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('REFERENCE', style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: cs.onSurfaceVariant)),
                  Text(order.orderReference, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ORDER DATE', style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: cs.onSurfaceVariant)),
                  Text(_formatDate(order.createdAt), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, ColorScheme cs, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: bold ? AppConstants.primaryGreen : cs.onSurfaceVariant,
              )),
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: bold ? 18 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppConstants.primaryGreen : cs.onSurface,
              )),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// Same blurred-glass pattern as OrderManagementScreen's own _TopAppBar and
// ProgramManagementScreen's inline top bar — copied rather than shared, same
// convention order_management_screen.dart already documents for this exact
// widget shape.

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

// ─── Section Card ─────────────────────────────────────────────────────────────
// Plain bordered card — matches the convention actually used across admin
// screens (program cards in ProgramManagementScreen, list rows in
// CropRequestApprovalScreen, AllListingsScreen, BuyerManagementScreen).
// GlassCard's heavy blur is a buyer-facing look in this codebase, not an
// admin one — deliberately not used here.

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _SectionCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: child,
    );
  }
}