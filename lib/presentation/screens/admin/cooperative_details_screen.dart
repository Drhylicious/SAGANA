import 'package:flutter/material.dart';
import '../../navigation/connectivity_page_observer.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/cooperative_delivery_model.dart';
import '../../../data/repositories/cooperative_delivery_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/cooperative_address_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/address_map_widgets.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fixed_farmer_address_fields.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/view_only_banner.dart';

/// True only for the Manager. The cooperative's own details are changed by the Manager alone;
/// an Officer can read them.
bool signedInIsManager() {
  try {
    return HiveService.getUserRole() == 'admin';
  } catch (_) {
    return false;
  }
}

/// The ONE shared record of the cooperative: its name, where customers collect their orders, its
/// location on the map and its contact number. Never a Manager's or an Officer's own details.
///
/// Plain things, nothing else:
///   1. the name (fixed),
///   2. the complete address (fixed to Payanas, shown locked like My Addresses). It is also the
///      official pickup location: checkout and the order screens read this same record,
///   3. the location on the map (where delivery fees are measured from),
///   4. the cooperative's contact number, which the Manager confirms.
/// The Manager edits; an Officer can only view.
class CooperativeDetailsScreen extends StatefulWidget {
  const CooperativeDetailsScreen({super.key});

  @override
  State<CooperativeDetailsScreen> createState() =>
      _CooperativeDetailsScreenState();
}

class _CooperativeDetailsScreenState extends State<CooperativeDetailsScreen> {
  final _repo = CooperativeDeliveryRepository();
  final _contact = TextEditingController();

  CooperativeDetails? _details;
  LatLng? _pin;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _contactError;
  String? _loadError;

  bool get _canEdit => signedInIsManager();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final d = await _repo.fetchDetails();
      if (!mounted) return;
      setState(() {
        _details = d;
        _contact.text = d.contactNumber ?? '';
        _pin = d.hasPin ? LatLng(d.latitude!, d.longitude!) : null;
        _dirty = false;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(AppLocalizations.of(context), e, st);
        _loading = false;
      });
    }
  }

  void _touch() => setState(() => _dirty = true);

  Future<void> _pickPin() async {
    final l10n = AppLocalizations.of(context);
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        settings: RouteSettings(name: ConnectivityPage.cooperativeMap.name),
        fullscreenDialog: true,
        builder: (_) => LocationPinPickerScreen(
          title: l10n.cdPinTitle,
          initialLocation: _pin,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _pin = picked;
        _dirty = true;
      });
    }
  }

  String? _validateContact(AppLocalizations l10n) {
    final text = _contact.text.trim();
    if (text.isEmpty) return null; // an empty number stays "not set"
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return (digits.length < 7 || digits.length > 13)
        ? l10n.cdContactInvalid
        : null;
  }

  Future<void> _save() async {
    if (!signedInIsManager()) return;
    final l10n = AppLocalizations.of(context);
    final err = _validateContact(l10n);
    setState(() => _contactError = err);
    if (err != null || _busy) return;
    setState(() => _busy = true);
    try {
      await _repo.saveDetails(
        latitude: _pin?.latitude,
        longitude: _pin?.longitude,
        contactNumber: _contact.text.trim(),
      );
      if (!mounted) return;
      AppToast.show(context, l10n.cdSaved);
      CooperativeAddressService.instance.invalidate();
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    if (_dirty) {
      AppToast.show(context, l10n.cdUnsaved, isError: true);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.verifyContact();
      if (!mounted) return;
      AppToast.show(context, l10n.cdVerifiedToast);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A small caption under a field, in the same quiet style everywhere.
  Widget _help(String text, ColorScheme cs) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 6),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        height: 1.4,
        color: cs.onSurfaceVariant,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = _details;
    final canEdit = _canEdit;
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.cdTitle, onBack: () => context.pop()),
          const ViewOnlyBanner(module: StaffModule.marketplace),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : d == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _loadError ?? l10n.errGeneric,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      if (!canEdit)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            l10n.cdViewOnly,
                            key: const Key('cdViewOnly'),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      // 1. who it is: the name only
                      AddressSectionCard(
                        title: l10n.cdNameLabel,
                        child: Text(
                          d.cooperativeName,
                          key: const Key('cdName'),
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 2. the complete address: fixed (shown locked, like My Addresses), and also
                      // the official pickup location. Checkout reads this same record.
                      AddressSectionCard(
                        title: l10n.cdCompleteAddressTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              key: const Key('cdAddressNote'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    l10n.cdCompleteAddressNote,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            LockedAreaFields(
                              key: const Key('cdAddressFields'),
                              region: d.regionName,
                              province: d.provinceName,
                              city: d.cityMunicipalityName,
                              barangay: d.barangayName,
                              postalCode: d.postalCode,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 3. where it is on the map
                      AddressSectionCard(
                        title: l10n.cdPinTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 170,
                              child: AddressMapPreview(pin: _pin),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _pin == null
                                  ? l10n.cdPinNotSet
                                  : l10n.cdPinSet(
                                      _pin!.latitude.toStringAsFixed(5),
                                      _pin!.longitude.toStringAsFixed(5),
                                    ),
                              key: const Key('cdPinStatus'),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (canEdit) ...[
                              _help(l10n.cdPinHelp, cs),
                              OutlinedButton.icon(
                                key: const Key('cdSetPin'),
                                onPressed: _busy ? null : _pickPin,
                                icon: const Icon(
                                  Icons.pin_drop_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _pin == null ? l10n.cdSetPin : l10n.cdMovePin,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 4. how to reach it: just the number
                      AddressSectionCard(
                        title: l10n.cdContactTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              key: const Key('cdContact'),
                              controller: _contact,
                              enabled: canEdit && !_busy,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+\-\s()]'),
                                ),
                              ],
                              maxLength: 20,
                              onChanged: (_) => _touch(),
                              decoration: InputDecoration(
                                labelText: l10n.cdContactLabel,
                                counterText: '',
                                errorText: _contactError,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _contactStatus(d, l10n),
                            if (canEdit &&
                                d.hasRealContact &&
                                !d.contactVerified) ...[
                              const SizedBox(height: 8),
                              _help(l10n.cdVerifyHelp, cs),
                              OutlinedButton.icon(
                                key: const Key('cdVerify'),
                                onPressed: _busy ? null : _verify,
                                icon: const Icon(
                                  Icons.verified_outlined,
                                  size: 18,
                                ),
                                label: Text(l10n.cdVerify),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.cdDeliveryResetNote,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (canEdit) ...[
                        const SizedBox(height: 14),
                        PrimaryButton(
                          key: const Key('cdSave'),
                          label: l10n.cdSave,
                          isLoading: _busy,
                          onPressed:
                              (_dirty &&
                                  ConnectivityService.instance.isOnline &&
                                  !_busy)
                              ? _save
                              : null,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Under the number: a yellow warning while it is not set, "not verified" while it is not
  /// confirmed, a green tick once it is.
  Widget _contactStatus(CooperativeDetails d, AppLocalizations l10n) {
    final (text, color, icon) = !d.hasRealContact
        ? (
            l10n.cdContactPlaceholder,
            AppConstants.warningAmber,
            Icons.warning_amber_rounded,
          )
        : d.contactVerified
        ? (
            l10n.cdContactVerified,
            AppConstants.successGreen,
            Icons.verified_rounded,
          )
        : (
            l10n.cdContactNotVerified,
            AppConstants.warningAmber,
            Icons.help_outline_rounded,
          );
    return Container(
      key: const Key('cdContactStatus'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
