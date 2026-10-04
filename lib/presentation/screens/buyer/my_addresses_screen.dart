import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

/// My Addresses — a peer to Edit Profile/Recent Activity off the drawer,
/// shared by Buyer and Farmer (farmer-as-buyer uses the same address book,
/// same convention as the shared Buyer marketplace/checkout code). Reached
/// by push, not a bottom-nav tab root, so this uses the plain AppBar shell
/// (matching BuyerRecentActivityScreen) rather than the drawer+top-bar
/// shell the four root tabs use.
class MyAddressesScreen extends StatefulWidget {
  const MyAddressesScreen({super.key});

  @override
  State<MyAddressesScreen> createState() => _MyAddressesScreenState();
}

class _MyAddressesScreenState extends State<MyAddressesScreen> {
  final _repo = BuyerAddressRepository();
  bool _isLoading = true;
  List<BuyerAddressModel> _addresses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final addresses = await _repo.fetchAddresses();
    if (!mounted) return;
    setState(() {
      _addresses = addresses;
      _isLoading = false;
    });
  }

  Future<void> _addOrEdit([BuyerAddressModel? existing]) async {
    final saved = await context.push<bool>(
      AppRoutes.addEditAddress,
      extra: existing,
    );
    if (saved == true) _load();
  }

  Future<void> _setDefault(BuyerAddressModel address) async {
    await _repo.setDefaultAddress(address.id);
    _load();
  }

  Future<void> _delete(BuyerAddressModel address) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _DeleteAddressConfirmDialog(label: address.label),
    );
    if (confirmed != true || !mounted) return;
    await _repo.deleteAddress(address.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.buyerAddressDeleted)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        // Same circular back button FarmerTopBar renders (40x40 circle,
        // card-background fill, primary-tinted border) — the plain
        // BackButton this replaced didn't match Edit Farm Details' header.
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sagana.cardBackground,
                border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
              ),
              child: Icon(Icons.arrow_back_rounded, color: cs.primary),
            ),
          ),
        ),
        title: Text(
          l10n.buyerAddressesTitle,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppConstants.primaryGreen,
          ),
        ),
        // Matches FarmerTopBar's own divider color exactly (cs.outline at
        // 20% alpha) — sagana.glassBorder (tried first) is meant for the
        // blurred-glass header style and reads as nearly invisible against
        // a plain opaque AppBar like this one.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: cs.outline.withValues(alpha: 0.20),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        backgroundColor: AppConstants.primaryGreen,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          l10n.buyerAddressesAddNew,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _addresses.isEmpty
                  ? _buildEmptyState(l10n)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        16,
                        AppConstants.spacingSafeH,
                        96,
                      ),
                      itemCount: _addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _AddressTile(
                        address: _addresses[i],
                        onEdit: () => _addOrEdit(_addresses[i]),
                        onSetDefault: () => _setDefault(_addresses[i]),
                        onDelete: () => _delete(_addresses[i]),
                      ),
                    ),
            ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingSafeH,
        vertical: 80,
      ),
      children: [
        Icon(
          Icons.location_off_outlined,
          size: 48,
          color: AppConstants.outline.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.buyerAddressesEmptyTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.buyerAddressesEmptyBody,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AddressTile extends StatelessWidget {
  final BuyerAddressModel address;
  final VoidCallback onEdit;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const _AddressTile({
    required this.address,
    required this.onEdit,
    required this.onSetDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
        boxShadow: AppConstants.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name / Phone on one row, address underneath, then
                // Label • Default underneath that — same general shape as
                // a standard delivery-address summary, not the previous
                // label-badge-first stack.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        address.recipientName?.trim().isNotEmpty == true
                            ? address.recipientName!
                            : address.label,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.onSurface,
                        ),
                      ),
                    ),
                    if (address.contactNumber != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        address.contactNumber!,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  address.addressLine,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppConstants.onSurface,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      address.label,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                    if (address.isDefault) ...[
                      Text(
                        '  •  ',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        l10n.buyerAddressesDefaultBadge,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.successGreen,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppConstants.onSurfaceVariant,
            ),
            onSelected: (value) {
              switch (value) {
                case 'default':
                  onSetDefault();
                  break;
                case 'edit':
                  onEdit();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (!address.isDefault)
                PopupMenuItem(
                  value: 'default',
                  child: Text(l10n.buyerAddressesSetDefault),
                ),
              PopupMenuItem(
                value: 'edit',
                child: Text(l10n.buyerAddressesEdit),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(l10n.buyerAddressesDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeleteAddressConfirmDialog extends StatelessWidget {
  final String label;
  const _DeleteAddressConfirmDialog({required this.label});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: AppConstants.cardBorder,
          boxShadow: AppConstants.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.buyerAddressesDeleteConfirmTitle,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.buyerAddressesDeleteConfirmBody(label),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: l10n.buyerAddressesDelete,
                    height: 44,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
