import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';

/// "₱50.00 / sack" normally — but ProgramProduct.unit can come back empty
/// if the linked inventory item couldn't be read (e.g. an RLS gap, as
/// happened once — see supabase_schema_program_product_sales_inventory_rls_fix.sql).
/// Rather than a dangling "₱50.00 / " in that case, drop the separator
/// entirely so a data gap reads as merely incomplete, not visibly broken.
String _priceUnitLabel(ProgramProduct product) {
  final price = '₱${product.unitPrice.toStringAsFixed(2)}';
  return product.unit.isEmpty ? price : '$price / ${product.unit}';
}

String _stockLabel(ProgramProduct product) {
  final qty = product.quantityOnHand.toStringAsFixed(0);
  return product.unit.isEmpty ? '$qty in stock' : '$qty ${product.unit} in stock';
}

// Full-width hero image, not a small squeezed thumbnail — used wherever a
// single product/purchase is shown in detail (the purchase sheet and the
// purchase-details view), matching the "give the image enough space"
// feedback applied across every other image spot in this feature. Works on
// smaller phone screens since AspectRatio scales with the sheet's own width.
Widget _heroImage(String? imageUrl, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return ClipRRect(
    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
    child: AspectRatio(
      aspectRatio: 16 / 10,
      child: (imageUrl != null && imageUrl.isNotEmpty)
          ? Image.network(
              imageUrl,
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

/// Farmer-side product catalog for a 'sales'-purpose Program — reached by
/// tapping a sales-program entry in MyProgramsScreen. Only ever reachable
/// for a program the farmer is actively enrolled in (My Programs only
/// lists the farmer's own enrollments to begin with, and program_products'
/// RLS independently re-enforces the same enrolled-and-active gate).
class ProgramProductCatalogScreen extends StatefulWidget {
  final String programId;
  final String programName;

  const ProgramProductCatalogScreen({
    super.key,
    required this.programId,
    required this.programName,
  });

  @override
  State<ProgramProductCatalogScreen> createState() =>
      _ProgramProductCatalogScreenState();
}

class _ProgramProductCatalogScreenState
    extends State<ProgramProductCatalogScreen> with SingleTickerProviderStateMixin {
  final _repo = FarmerProgramRepository();
  late final TabController _tabController;
  List<ProgramProduct> _products = [];
  List<ProgramPurchase> _myPurchases = [];
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
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
      _repo.fetchAvailableProducts(widget.programId),
      _repo.fetchMyPurchases(widget.programId),
    ]);
    if (!mounted) return;
    setState(() {
      _products = (results[0] as List<ProgramProduct>).where((p) => p.isAvailable).toList();
      _myPurchases = results[1] as List<ProgramPurchase>;
      _isLoading = false;
    });
  }

  // Cancellation lives in its own dialog (reason required, X top-left to
  // close without cancelling) rather than a plain yes/no confirm — matches
  // the admin's cancel-purchase-review flow, and the DB's
  // cancel_program_purchase(p_purchase_id, p_reason) has no default for
  // p_reason so a reason must always be supplied.
  String _formatPurchaseDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // Same read-only details pattern used on the Admin side
  // (program_purchase_review_screen.dart's _showPurchaseDetailsSheet) —
  // reachable for a purchase at any status (pending, paid, cancelled).
  void _showPurchaseDetailsSheet(ProgramPurchase purchase) {
    final statusColor = purchase.status == 'paid'
        ? AppConstants.successGreen
        : purchase.status == 'cancelled'
            ? AppConstants.errorRed
            : AppConstants.amber;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return ManagementModalShell(
          title: purchase.itemName,
          subtitle: purchase.programName,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _heroImage(purchase.imageUrl, ctx),
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
              const SizedBox(height: 6),
              _purchaseDetailRow('Quantity', '${purchase.quantity.toStringAsFixed(1)} ${purchase.unit}'),
              _purchaseDetailRow('Unit Price', '₱${purchase.unitPrice.toStringAsFixed(2)}'),
              _purchaseDetailRow('Total', '₱${purchase.totalAmount.toStringAsFixed(2)}', emphasize: true),
              _purchaseDetailRow('Requested', _formatPurchaseDate(purchase.requestedAt)),
              if (purchase.confirmedAt != null)
                _purchaseDetailRow('Confirmed', _formatPurchaseDate(purchase.confirmedAt!)),
              if (purchase.cancelledAt != null)
                _purchaseDetailRow('Cancelled', _formatPurchaseDate(purchase.cancelledAt!)),
              if (purchase.cancelReason != null && purchase.cancelReason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Cancellation reason',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('"${purchase.cancelReason}"',
                    style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: AppConstants.onSurface)),
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

  Widget _purchaseDetailRow(String label, String value, {bool emphasize = false}) {
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

  Future<void> _cancelPurchase(ProgramPurchase purchase) async {
    final reason = await _showCancelReasonDialog(purchase);
    if (reason == null) return;
    final ok = await _repo.cancelMyPurchase(purchase.id, reason);
    if (ok) {
      _load();
    } else {
      _showSnack('Could not cancel this request.', isError: true);
    }
  }

  Future<String?> _showCancelReasonDialog(ProgramPurchase purchase) {
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
                    child: Text('Cancel Request',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('Please provide a reason for cancelling your request for ${purchase.itemName}.',
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
                        hintText: 'e.g. Changed my mind',
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

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  void _showPurchaseSheet(ProgramProduct product) {
    final qtyCtrl = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;
          double quantity = 1;

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final qty = double.tryParse(qtyCtrl.text.trim());
            if (qty == null || qty <= 0) return;
            setSheet(() => isSaving = true);
            try {
              await _repo.requestPurchase(
                programId: widget.programId,
                productId: product.id,
                quantity: qty,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _showSnack(
                  'Purchase request submitted — the cooperative will confirm it once payment is received.');
              _load();
            } catch (_) {
              if (!ctx.mounted) return;
              setSheet(() => isSaving = false);
              _showSnack(
                  'Could not submit this request — it may be out of stock or no longer available.',
                  isError: true);
            }
          }

          return ManagementModalShell(
            title: product.itemName,
            subtitle: _priceUnitLabel(product),
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _heroImage(product.imageUrl, ctx),
                  const SizedBox(height: 14),
                  Text(
                    _stockLabel(product),
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: qtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Quantity *',
                      suffixText: product.unit,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (v) => setSheet(() => quantity = double.tryParse(v) ?? 0),
                    validator: (v) {
                      final q = double.tryParse(v ?? '');
                      if (q == null || q <= 0) return 'Enter a valid quantity';
                      if (q > product.quantityOnHand) return 'Not enough stock available';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total',
                            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                        Text(
                          '₱${(product.unitPrice * quantity).toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This submits a request — it becomes final only once the '
                    'cooperative confirms your payment.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? 'Submitting…' : 'Request Purchase',
              isLoading: isSaving,
              onPrimary: _isOnline ? submit : null,
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              if (!_isOnline)
                const OfflineBanner(
                    message: "You're offline — purchase requests can't be submitted right now."),
              TabBar(
                controller: _tabController,
                labelColor: AppConstants.primaryGreen,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: AppConstants.primaryGreen,
                tabs: const [
                  Tab(text: 'Products'),
                  Tab(text: 'My Purchases'),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildProductsTab(),
                          _buildPurchasesTab(),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: widget.programName,
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

  Widget _buildProductsTab() {
    return RefreshIndicator(
      color: AppConstants.primaryGreen,
      onRefresh: _load,
      child: _products.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 48, color: AppConstants.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No products available right now.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              itemCount: _products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final product = _products[i];
                return _ProductCard(
                  product: product,
                  onTap: () => _showPurchaseSheet(product),
                );
              },
            ),
    );
  }

  Widget _buildPurchasesTab() {
    return RefreshIndicator(
      color: AppConstants.primaryGreen,
      onRefresh: _load,
      child: _myPurchases.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 48, color: AppConstants.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      "You haven't requested any purchases yet.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              itemCount: _myPurchases.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final purchase = _myPurchases[i];
                return _PurchaseCard(
                  purchase: purchase,
                  onCancel: purchase.isPending ? () => _cancelPurchase(purchase) : null,
                  onTap: () => _showPurchaseDetailsSheet(purchase),
                );
              },
            ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  final ProgramPurchase purchase;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  const _PurchaseCard({required this.purchase, this.onCancel, this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = purchase.status == 'paid'
        ? AppConstants.successGreen
        : purchase.status == 'cancelled'
            ? AppConstants.errorRed
            : AppConstants.amber;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(left: BorderSide(color: statusColor, width: 4)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Purchased item's photo — same source as the Products tab
              // (cooperative_inventory via program_products), sized to
              // actually be visible in a list row rather than a tiny icon.
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: (purchase.imageUrl != null && purchase.imageUrl!.isNotEmpty)
                      ? Image.network(
                          purchase.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                            child: const Icon(Icons.storefront_rounded,
                                color: AppConstants.primaryGreen, size: 24),
                          ),
                        )
                      : Container(
                          color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                          child: const Icon(Icons.storefront_rounded,
                              color: AppConstants.primaryGreen, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(purchase.itemName,
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text(purchase.status.toUpperCase(),
                              style: GoogleFonts.inter(
                                  fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${purchase.quantity.toStringAsFixed(1)} ${purchase.unit} · ₱${purchase.totalAmount.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (purchase.status == 'cancelled' &&
              purchase.cancelReason != null &&
              purchase.cancelReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('"${purchase.cancelReason}"',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant)),
            ),
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppConstants.errorRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Center(
                  child: Text('Cancel Request',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppConstants.errorRed)),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProgramProduct product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
          boxShadow: [
            BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            Container(
              // Matches the 68x68 rounded-square size used consistently
              // across Inventory/Program/Loan Catalog list rows — was
              // 44x44, smaller than that established standard.
              width: 68, height: 68,
              decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
              clipBehavior: Clip.antiAlias,
              // The actual product's photo (from Inventory Management, via
              // the existing cooperative_inventory join) — not a separate
              // upload, per the cross-module image reuse rule.
              child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                  ? Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.storefront_rounded, color: AppConstants.primaryGreen, size: 28),
                    )
                  : const Icon(Icons.storefront_rounded, color: AppConstants.primaryGreen, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.itemName,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${_priceUnitLabel(product)} · ${product.quantityOnHand.toStringAsFixed(0)} in stock',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppConstants.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
