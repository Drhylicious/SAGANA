import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/psgc_models.dart';
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/repositories/psgc_repository.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/auth_visuals.dart';
import '../../widgets/psgc_address_fields.dart';

/// Dedicated screen for an applicant to review and edit the personal and
/// address information they submitted. Each card edits in place, so the
/// address fields get the full width of the screen.
class PendingReviewDetailsScreen extends StatefulWidget {
  const PendingReviewDetailsScreen({super.key});

  @override
  State<PendingReviewDetailsScreen> createState() =>
      _PendingReviewDetailsScreenState();
}

class _PendingReviewDetailsScreenState
    extends State<PendingReviewDetailsScreen> {
  final _profileRepo = FarmerProfileRepository();
  final _addressRepo = BuyerAddressRepository();

  // Personal information
  final _personalKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _dob;
  String? _gender;
  bool _editingPersonal = false;
  bool _savingPersonal = false;
  String? _personalError;

  // Address information
  final _addressDraft = AddressStructureDraft();
  BuyerAddressModel? _address;
  PsgcHierarchy? _psgc;
  bool _isPsgcLoading = false;
  bool _editingAddress = false;
  bool _savingAddress = false;
  String? _addressError;

  FarmerProfileModel? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressDraft.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final profile = await _profileRepo.fetchProfile();
    final address = await _addressRepo.fetchDefaultAddress();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _address = address;
      _loading = false;
    });
  }

  void _toast(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: ok ? AppConstants.successGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> _genders(AppLocalizations l10n) => {
    'male': l10n.registerGenderMale,
    'female': l10n.registerGenderFemale,
    'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
  };

  // ── Personal information ───────────────────────────────────────────────────

  void _startPersonalEdit() {
    final p = _profile;
    _nameCtrl.text = p?.fullName ?? '';
    _phoneCtrl.text = p?.phoneNumber ?? '';
    _emailCtrl.text = p?.contactEmail ?? '';
    setState(() {
      _dob = p?.dateOfBirth;
      _gender = p?.gender;
      _personalError = null;
      _editingPersonal = true;
    });
  }

  void _cancelPersonal() {
    setState(() {
      _editingPersonal = false;
      _personalError = null;
    });
  }

  Future<void> _savePersonal() async {
    final l10n = AppLocalizations.of(context);
    if (!(_personalKey.currentState?.validate() ?? false)) return;
    if (_dob != null && !AppUtils.isAtLeast18(_dob!)) {
      setState(() => _personalError = l10n.pendingAgeError);
      return;
    }
    setState(() {
      _savingPersonal = true;
      _personalError = null;
    });
    try {
      await _profileRepo.updateApplicantDetails(
        fullName: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim(),
        dateOfBirth: _dob,
        gender: _gender,
      );
      await _reload();
      if (!mounted) return;
      setState(() {
        _savingPersonal = false;
        _editingPersonal = false;
      });
      _toast(l10n.pendingDetailsUpdatedToast, ok: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPersonal = false;
        _personalError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Address information ────────────────────────────────────────────────────

  Future<void> _startAddressEdit() async {
    setState(() {
      _editingAddress = true;
      _addressError = null;
    });
    if (_psgc == null) {
      setState(() => _isPsgcLoading = true);
      final hierarchy = await PsgcRepository.load();
      if (!mounted) return;
      setState(() {
        // An empty hierarchy means the asset failed to load; leave _psgc null
        // so the next edit retries.
        if (hierarchy.regions.isNotEmpty) _psgc = hierarchy;
        _isPsgcLoading = false;
      });
    }
    final psgc = _psgc;
    final address = _address;
    if (psgc != null && address != null) {
      _addressDraft.loadFrom(address, psgc);
    }
    if (mounted) setState(() {});
  }

  void _cancelAddress() {
    setState(() {
      _editingAddress = false;
      _addressError = null;
    });
  }

  Future<void> _saveAddress() async {
    final l10n = AppLocalizations.of(context);
    if (_addressDraft.postalCtrl.text.isNotEmpty && !_addressDraft.postalValid) {
      setState(() => _addressError = l10n.registerPostalInvalid);
      return;
    }
    if (!_addressDraft.isComplete) {
      setState(() => _addressError = l10n.buyerAddressStructureRequired);
      return;
    }
    setState(() {
      _savingAddress = true;
      _addressError = null;
    });
    final fullName = _profile?.fullName ?? '';
    final phone = _profile?.phoneNumber;
    final structure = _addressDraft.toStructure();
    final addressLine = _addressDraft.composeLine();
    try {
      final existing = _address;
      if (existing != null) {
        await _addressRepo.updateAddress(
          id: existing.id,
          label: existing.label,
          recipientName: fullName,
          contactNumber: phone,
          addressLine: addressLine,
          latitude: existing.latitude,
          longitude: existing.longitude,
          notes: existing.notes,
          structure: structure,
          // The whole structure is replaced, so a cleared optional field is
          // saved as NULL.
          replaceStructure: true,
        );
      } else {
        await _addressRepo.addAddress(
          label: 'Home',
          recipientName: fullName,
          contactNumber: phone,
          addressLine: addressLine,
          structure: structure,
          isDefault: true,
        );
      }
      await _reload();
      if (!mounted) return;
      setState(() {
        _savingAddress = false;
        _editingAddress = false;
      });
      _toast(l10n.pendingDetailsUpdatedToast, ok: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingAddress = false;
        _addressError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Same header height, background, and divider as the three tabs.
          Container(
            height: 64 + topPadding,
            padding: EdgeInsets.only(top: topPadding, left: 8, right: 20),
            decoration: BoxDecoration(
              color: sagana.navBarBackground,
              border: Border(
                bottom: BorderSide(color: cs.outline.withValues(alpha: 0.20)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: cs.onSurface,
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.pendingReviewEditButton,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppConstants.primaryGreen,
                      strokeWidth: 2,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    children: [
                      _card(
                        cs: cs,
                        sagana: sagana,
                        title: l10n.pendingPersonalInfoTitle,
                        trailing: _editingPersonal
                            ? null
                            : _editButton(
                                l10n.buyerAddressesEdit,
                                _startPersonalEdit,
                              ),
                        child: _editingPersonal
                            ? _personalForm(l10n, cs)
                            : _personalView(l10n, cs),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        cs: cs,
                        sagana: sagana,
                        title: l10n.pendingAddressInfoTitle,
                        trailing: _editingAddress
                            ? null
                            : _editButton(
                                l10n.buyerAddressesEdit,
                                _startAddressEdit,
                              ),
                        child: _editingAddress
                            ? _addressForm(l10n, cs)
                            : _addressView(l10n, cs),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required ColorScheme cs,
    required SaganaColors sagana,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _editButton(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppConstants.primaryGreen,
        ),
      ),
    );
  }

  Widget _infoRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personalView(AppLocalizations l10n, ColorScheme cs) {
    final p = _profile;
    final dob = p?.dateOfBirth;
    final gender = p?.gender;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(cs, l10n.pendingFullNameLabel, p?.fullName ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.emailAddress, p?.contactEmail ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.pendingPhoneLabel, p?.phoneNumber ?? l10n.pendingNotSet),
        _infoRow(
          cs,
          l10n.pendingDobLabel,
          dob == null ? l10n.pendingNotSet : _formatDate(dob),
        ),
        _infoRow(
          cs,
          l10n.addMemberGenderLabel,
          switch (gender) {
            'male' => l10n.registerGenderMale,
            'female' => l10n.registerGenderFemale,
            'prefer_not_to_say' => l10n.registerGenderPreferNotToSay,
            _ => l10n.pendingNotSet,
          },
        ),
      ],
    );
  }

  Widget _personalForm(AppLocalizations l10n, ColorScheme cs) {
    return Form(
      key: _personalKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: authFieldDecoration(
              label: l10n.pendingFullNameLabel,
              icon: Icons.person_outline_rounded,
            ),
            validator: (v) => (v == null || v.trim().length < 2)
                ? l10n.pendingFullNameRequired
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: authFieldDecoration(
              label: l10n.pendingPhoneOptionalLabel,
              icon: Icons.phone_outlined,
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return null;
              return RegExp(r'^09\d{9}$').hasMatch(t)
                  ? null
                  : l10n.pendingPhoneInvalid;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: authFieldDecoration(
              label: l10n.pendingEmailOptionalLabel,
              icon: Icons.mail_outline_rounded,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await AppUtils.pickDateOfBirth(
                context,
                initialDate: _dob,
              );
              if (picked == null) return;
              if (!AppUtils.isAtLeast18(picked)) {
                if (!mounted) return;
                await AppUtils.showUnder18Dialog(context);
                return;
              }
              setState(() => _dob = picked);
            },
            child: InputDecorator(
              decoration: authFieldDecoration(
                label: l10n.pendingDobLabel,
                icon: Icons.cake_outlined,
              ),
              child: Text(
                _dob == null ? l10n.pendingSelectHint : _formatDate(_dob!),
                style: GoogleFonts.inter(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppDropdownField<String>(
            value: _gender,
            hintText: l10n.pendingSelectHint,
            labelText: l10n.pendingGenderOptionalLabel,
            items: _genders(l10n).keys.toList(),
            itemLabel: (key) => _genders(l10n)[key]!,
            onChanged: (v) => setState(() => _gender = v),
          ),
          if (_personalError != null) ...[
            const SizedBox(height: 10),
            Text(
              _personalError!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.errorRed,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _editActions(
            l10n: l10n,
            saving: _savingPersonal,
            onCancel: _cancelPersonal,
            onSave: _savePersonal,
          ),
        ],
      ),
    );
  }

  Widget _addressView(AppLocalizations l10n, ColorScheme cs) {
    final a = _address;
    if (a == null) {
      return Text(
        l10n.pendingNoAddressYet,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a.addressLine,
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 14),
        _infoRow(cs, l10n.registerRegionLabel, a.regionName ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerProvinceLabel, a.provinceName ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerCityLabel, a.cityMunicipalityName ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerBarangayLabel, a.barangayName ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerPostalLabel, a.postalCode ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerStreetLabel, a.street ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerBuildingLabel, a.building ?? l10n.pendingNotSet),
        _infoRow(cs, l10n.registerHouseNoLabel, a.houseNo ?? l10n.pendingNotSet),
      ],
    );
  }

  Widget _addressForm(AppLocalizations l10n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PsgcAddressFields(
          draft: _addressDraft,
          hierarchy: _psgc,
          isLoading: _isPsgcLoading,
          onChanged: () => setState(() {}),
        ),
        if (_addressError != null) ...[
          const SizedBox(height: 10),
          Text(
            _addressError!,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppConstants.errorRed,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _editActions(
          l10n: l10n,
          saving: _savingAddress,
          onCancel: _cancelAddress,
          onSave: _saveAddress,
        ),
      ],
    );
  }

  Widget _editActions({
    required AppLocalizations l10n,
    required bool saving,
    required VoidCallback onCancel,
    required Future<void> Function() onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: saving ? null : onCancel,
            child: Text(l10n.pendingCancel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: saving ? null : () => onSave(),
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.pendingSave),
          ),
        ),
      ],
    );
  }
}
