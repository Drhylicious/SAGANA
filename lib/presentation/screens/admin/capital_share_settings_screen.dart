import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/repositories/capital_share_rates_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/address_map_widgets.dart' show AddressSectionCard;
import '../../widgets/app_toast.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/view_only_banner.dart';

/// Capital Share Settings, reached from the Member Contribution Report.
///
/// Total Capital Share = Monthly Contribution + Cooperative Purchase + Offer to
/// Cooperative. Two of the three are a percentage the cooperative sets here:
///  - Cooperative Purchase: of what an enrolled member pays for a completed order;
///  - Offer to Cooperative: of the sale value of a successful, completed offer.
/// Monthly Contribution has no percentage and is shown only so the three are
/// together. The Manager edits; an Officer with Manage on Loans edits too; with
/// View Only the fields are read-only (the database refuses the write anyway).
class CapitalShareSettingsScreen extends StatefulWidget {
  const CapitalShareSettingsScreen({super.key});

  @override
  State<CapitalShareSettingsScreen> createState() =>
      _CapitalShareSettingsScreenState();
}

class _CapitalShareSettingsScreenState
    extends State<CapitalShareSettingsScreen> {
  final _repo = CapitalShareRatesRepository();
  final _purchaseCtrl = TextEditingController();
  final _offerCtrl = TextEditingController();

  CapitalShareRates? _saved;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _purchaseCtrl.dispose();
    _offerCtrl.dispose();
    super.dispose();
  }

  static String _text(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final rates = await _repo.fetch();
      if (!mounted) return;
      setState(() {
        _saved = rates;
        _purchaseCtrl.text = _text(rates.purchasePercent);
        _offerCtrl.text = _text(rates.offerPercent);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  double? get _purchase => CapitalShareRatesRepository.parsePercent(_purchaseCtrl.text);
  double? get _offer => CapitalShareRatesRepository.parsePercent(_offerCtrl.text);

  bool get _valid => _purchase != null && _offer != null;

  bool get _changed {
    final s = _saved;
    if (s == null || !_valid) return false;
    return _purchase != s.purchasePercent || _offer != s.offerPercent;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    try {
      await _repo.save(purchasePercent: _purchase!, offerPercent: _offer!);
      if (!mounted) return;
      setState(() {
        _saved = CapitalShareRates(
          purchasePercent: _purchase!,
          offerPercent: _offer!,
        );
        _saving = false;
      });
      AppToast.show(context, l10n.capSettingsSaved);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(
        context,
        friendlyError(l10n, e, st, l10n.capSettingsSaveError),
        isError: true,
      );
    }
  }

  /// One percentage field with its caption above and its explanation flush left
  /// under it, the same layout as the other settings forms.
  Widget _rateField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool enabled,
    required AppLocalizations l10n,
    required ColorScheme cs,
    required Color accent,
    required IconData icon,
    Key? fieldKey,
  }) {
    final invalid =
        controller.text.trim().isNotEmpty &&
        CapitalShareRatesRepository.parsePercent(controller.text) == null;
    return AddressSectionCard(
      title: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,2}')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.capSettingsPercentField,
                    suffixText: '%',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Flush left under the field (not inset by the field's own padding).
          Text(
            invalid ? l10n.capSettingsRangeError : hint,
            textAlign: TextAlign.start,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.4,
              color: invalid ? cs.error : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final online = ConnectivityService.instance.isOnline;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.capSettingsTitle,
            onBack: () => context.pop(),
          ),
          const ViewOnlyBanner(module: StaffModule.reports),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : _loadFailed
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.capSettingsLoadError, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
                        ],
                      ),
                    ),
                  )
                : StaffAccessBuilder(
                    builder: (context, access) {
                      final canEdit = access.canManage(StaffModule.reports);
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        children: [
                          // The formula, so the three are read together.
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryGreen.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.capSettingsSummaryTitle,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.capSettingsSummaryBody,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Monthly Contribution: no percentage, shown so the three are together.
                          AddressSectionCard(
                            title: l10n.capSettingsMonthlyLabel,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppConstants.amber.withValues(alpha: 0.13),
                                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                  ),
                                  child: const Icon(
                                    Icons.calendar_month_rounded,
                                    size: 18,
                                    color: AppConstants.amber,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    l10n.capSettingsMonthlyHint,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _rateField(
                            fieldKey: const Key('purchaseRate'),
                            label: l10n.capSettingsPurchaseLabel,
                            hint: l10n.capSettingsPurchaseHint,
                            controller: _purchaseCtrl,
                            enabled: canEdit && !_saving,
                            l10n: l10n,
                            cs: cs,
                            accent: AppConstants.buyerBlue,
                            icon: Icons.shopping_bag_rounded,
                          ),
                          const SizedBox(height: 12),
                          _rateField(
                            fieldKey: const Key('offerRate'),
                            label: l10n.capSettingsOfferLabel,
                            hint: l10n.capSettingsOfferHint,
                            controller: _offerCtrl,
                            enabled: canEdit && !_saving,
                            l10n: l10n,
                            cs: cs,
                            accent: AppConstants.primaryGreen,
                            icon: Icons.handshake_rounded,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.capSettingsApplyNote,
                            textAlign: TextAlign.start,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (canEdit) ...[
                            const SizedBox(height: 16),
                            PrimaryButton(
                              key: const Key('saveRates'),
                              label: l10n.capSettingsSave,
                              isLoading: _saving,
                              onPressed: (_changed && online && !_saving) ? _save : null,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
