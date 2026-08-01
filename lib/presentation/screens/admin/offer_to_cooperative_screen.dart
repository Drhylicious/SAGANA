import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../widgets/management_modal.dart';

class OfferToCooperativeScreen extends StatefulWidget {
  const OfferToCooperativeScreen({super.key});

  @override
  State<OfferToCooperativeScreen> createState() => _OfferToCooperativeScreenState();
}

class _OfferToCooperativeScreenState extends State<OfferToCooperativeScreen> {
  final _repo = CooperativeOfferRepository();
  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final offers = await _repo.fetchPendingOffers();
    if (!mounted) return;
    setState(() { _offers = offers; _isLoading = false; });
  }

  void _showReviewModal(Map<String, dynamic> offer) {
    final qtyCtrl = TextEditingController(text: (offer['offered_quantity_kg'] as num).toStringAsFixed(0));
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> respond(bool confirm) async {
            if (confirm && !formKey.currentState!.validate()) return;
            setSheet(() => isSaving = true);
            try {
              if (confirm) {
                await _repo.confirmCooperativeOffer(
                  offerId: offer['id'] as String,
                  confirmedQuantityKg: double.parse(qtyCtrl.text),
                  confirmedAmount: double.parse(amountCtrl.text),
                  adminNotes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                );
              } else {
                await _repo.declineCooperativeOffer(
                  offerId: offer['id'] as String,
                  adminNotes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                );
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _load();
            } catch (_) {
              setSheet(() => isSaving = false);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('Failed. Please try again.'),
                backgroundColor: AppConstants.errorRed,
              ));
            }
          }

          return ManagementModalShell(
            title: '${offer['crop_name']} Offer',
            subtitle: offer['farmer_name'] as String,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Offered: ${(offer['offered_quantity_kg'] as num).toStringAsFixed(0)} kg',
                      style: GoogleFonts.inter(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(labelText: 'Confirmed Quantity (kg) *'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a valid quantity' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Amount Paid (₱) *', prefixText: '₱ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a valid amount' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            footer: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: isSaving ? null : () => respond(false),
                style: OutlinedButton.styleFrom(foregroundColor: AppConstants.errorRed, side: const BorderSide(color: AppConstants.errorRed)),
                child: const Text('Decline'),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: isSaving ? null : () => respond(true),
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Confirm Purchase'),
              )),
            ]),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
            child: Row(children: [
              IconButton(icon: Icon(Icons.arrow_back_rounded, color: cs.primary), onPressed: () => context.pop()),
              Expanded(child: Text('Offer to Cooperative',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: cs.onSurface))),
            ]),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                : _offers.isEmpty
                    ? Center(child: Text('No pending offers', style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          itemCount: _offers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final o = _offers[i];
                            return GestureDetector(
                              onTap: () => _showReviewModal(o),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                                  border: Border(left: BorderSide(color: AppConstants.warningAmber, width: 4)),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
                                ),
                                child: Row(children: [
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${o['crop_name']}', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                                      Text(o['farmer_name'] as String, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                                    ],
                                  )),
                                  Text('${(o['offered_quantity_kg'] as num).toStringAsFixed(0)} kg',
                                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}