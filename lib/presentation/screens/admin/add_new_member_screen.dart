import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/add_member_repository.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

/// Fixed ₱2,000 per capital share (Phase B / Decision D2).
const double _kShareValuePerUnit = 2000;

// Gender labels are shared with the Register screen's translations
// (registerGenderMale/Female/PreferNotToSay) rather than duplicated here.
Map<String, String> _kGenderOptions(AppLocalizations l10n) => {
      'male': l10n.registerGenderMale,
      'female': l10n.registerGenderFemale,
      'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
    };

class AddNewMemberScreen extends StatefulWidget {
  const AddNewMemberScreen({super.key});

  @override
  State<AddNewMemberScreen> createState() => _AddNewMemberScreenState();
}

class _AddNewMemberScreenState extends State<AddNewMemberScreen> {
  final _repo    = AddMemberRepository();
  final _cropRepo = CropRepository();
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ────────────────────────────────────────────────────────────
  final _usernameCtrl    = TextEditingController();
  final _passwordCtrl    = TextEditingController();
  final _fullNameCtrl    = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _memberIdCtrl    = TextEditingController();
  final _initialContributionCtrl = TextEditingController();

  // ── Form state ─────────────────────────────────────────────────────────────
  String? _selectedPurok;
  DateTime? _dateOfBirth;
  String? _gender; // key of _kGenderOptions
  bool    _obscurePassword = true;
  final List<String> _selectedCrops = [];

  // Active crop_master catalog (Issue 4e) — replaces the old hardcoded list.
  List<Map<String, dynamic>> _catalogCrops = [];

  // Registry auto-fill (Issue 4a)
  Timer? _nameDebounce;
  bool _isCheckingRegistry = false;
  bool _registryChecked = false;
  bool _isOfficialMember = false;
  String? _registryId;

  bool _isSaving  = false;
  bool _isOnline  = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _fullNameCtrl.addListener(_onFullNameChanged);
    _loadSuggestions();
    _loadCropCatalog();
  }

  Future<void> _loadSuggestions() async {
    final suggestedMemberId = await _repo.suggestNextMemberId();
    final suggestedUsername = await _repo.suggestNextUsername();
    if (mounted) {
      setState(() {
        _memberIdCtrl.text = suggestedMemberId;
        _usernameCtrl.text = suggestedUsername;
      });
    }
  }

  Future<void> _loadCropCatalog() async {
    final catalog = await _cropRepo.fetchCropCatalog();
    if (mounted) setState(() => _catalogCrops = catalog);
  }

  // ── Registry auto-fill lookup — debounced (Issue 4a) ───────────────────────

  void _onFullNameChanged() {
    final name = _fullNameCtrl.text.trim();
    if (_registryChecked || _isOfficialMember) {
      setState(() {
        _registryChecked = false;
        _isOfficialMember = false;
        _registryId = null;
      });
    }
    if (name.length < 3) return;
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 600), () {
      _checkRegistry(name);
    });
  }

  Future<void> _checkRegistry(String name) async {
    if (!mounted) return;
    setState(() => _isCheckingRegistry = true);
    final result = await AuthService.checkSp3Registry(name);
    if (!mounted) return;
    setState(() {
      _isCheckingRegistry = false;
      _registryChecked = true;
      if (result != null && !result.alreadyRegistered) {
        _isOfficialMember = true;
        _registryId = result.registryId;
        if (result.phone != null && _phoneCtrl.text.trim().isEmpty) {
          _phoneCtrl.text = result.phone!;
        }
        final mappedPurok = _mapPurok(result.suggestedPurok);
        if (mappedPurok != null) _selectedPurok = mappedPurok;
      } else {
        _isOfficialMember = false;
        _registryId = null;
      }
    });
  }

  String? _mapPurok(String? suggested) {
    if (suggested == null) return null;
    String norm(String s) => s
        .replaceAll(RegExp(r'[–—–-]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    final target = norm(suggested);
    for (final p in AppConstants.payanasPuroks) {
      if (norm(p) == target) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _fullNameCtrl.removeListener(_onFullNameChanged);
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _memberIdCtrl.dispose();
    _initialContributionCtrl.dispose();
    super.dispose();
  }

  // ── Password generation ─────────────────────────────────────────────────────

  void _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rand  = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    for (int i = 0; i < 10; i++) {
      buffer.write(chars[(rand + i * 17) % chars.length]);
    }
    setState(() {
      _passwordCtrl.text = buffer.toString();
      _obscurePassword   = false;
    });
  }

  // ── Crop selection ────────────────────────────────────────────────────────

  void _showCropDialog() {
    final l10n = AppLocalizations.of(context);
    final available = _catalogCrops
        .where((c) => !_selectedCrops.contains(c['crop_name'] as String))
        .toList();
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          title: Text(
            l10n.addMemberSelectCropTitle,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: cs.primary),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: available.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _catalogCrops.isEmpty
                          ? l10n.addMemberNoCatalogCrops
                          : l10n.addMemberAllCropsAdded,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  )
                : GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.4,
                    children: available
                        .map((entry) {
                          final crop = entry['crop_name'] as String;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedCrops.add(crop));
                              Navigator.pop(ctx);
                            },
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: cs.outline.withValues(alpha: 0.20)),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusMd),
                              ),
                              child: Text(
                                crop,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.addMemberClose),
            ),
          ],
        );
      },
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPurok == null) {
      _showSnack(l10n.addMemberSelectPurok);
      return;
    }
    if (_dateOfBirth != null &&
        _dateOfBirth!.isAfter(
            DateTime(DateTime.now().year - 18, DateTime.now().month,
                DateTime.now().day))) {
      _showSnack(l10n.addMemberAgeRequirement);
      return;
    }

    final initialContribution =
        double.tryParse(_initialContributionCtrl.text.trim().replaceAll(',', '')) ??
            0;

    setState(() => _isSaving = true);

    final result = await _repo.createMember(
      username:            _usernameCtrl.text.trim(),
      password:            _passwordCtrl.text.trim(),
      fullName:            _fullNameCtrl.text.trim(),
      phoneNumber:         _phoneCtrl.text.trim(),
      purok:               _selectedPurok!,
      dateOfBirth:         _dateOfBirth,
      gender:              _gender,
      shareValuePerUnit:   _kShareValuePerUnit,
      initialContribution: initialContribution,
      initialCrops:        _selectedCrops,
      registryId:          _registryId,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      _showSnack(
        l10n.addMemberCreatedSuccess(_fullNameCtrl.text.trim()),
        isSuccess: true,
      );
      context.pop(true);
    } else if (result.isPartial) {
      _showSnack(
        l10n.addMemberPartialIssue(
            result.failedStep ?? '', result.message ?? ''),
      );
      // Member account exists — still pop back so admin sees them in the list
      context.pop(true);
    } else {
      final msg = result.message ?? l10n.addMemberCreateFailed;
      if (msg.toLowerCase().contains('already taken') ||
          msg.toLowerCase().contains('already exists')) {
        // Suggestion collided with a username created since it was
        // fetched — refresh it rather than leaving the Admin stuck on a
        // dead value with no way to recover except backing out entirely.
        final fresh = await _repo.suggestNextUsername();
        if (mounted) setState(() => _usernameCtrl.text = fresh);
        _showSnack(l10n.addMemberUsernameTakenRetry);
      } else {
        _showSnack(msg);
      }
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor:
            isSuccess ? AppConstants.successGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;
    final l10n   = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    children: [

                      // ── Admin notice ────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.06),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusLg),
                          border: Border(
                            left: BorderSide(color: cs.primary, width: 4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: cs.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.addMemberAdminNoticeTitle,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.addMemberAdminNoticeBody,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Account Credentials ─────────────────────────────
                      _FormSection(
                        icon: Icons.lock_person_rounded,
                        title: l10n.addMemberSectionCredentials,
                        cs: cs,
                        sagana: sagana,
                        children: [
                          _FieldLabel(label: l10n.addMemberUsernameLabel, cs: cs),
                          TextFormField(
                            controller: _usernameCtrl,
                            readOnly: true,
                            style: TextStyle(color: cs.onSurfaceVariant),
                            decoration: const InputDecoration(
                              hintText: 'SP3-0001',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return l10n.addMemberUsernameRequired;
                              }
                              return null;
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              l10n.addMemberUsernameHelp,
                              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _FieldLabel(label: l10n.addMemberPasswordLabel, cs: cs),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                      color: cs.outline,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: 8),
                                    child: GestureDetector(
                                      onTap: _generatePassword,
                                      child: Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: cs.primary
                                                .withValues(alpha: 0.30),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(
                                                  AppConstants.radiusSm),
                                        ),
                                        child: Text(
                                          'AUTO',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l10n.addMemberPasswordRequired;
                              }
                              if (v.length < 8) {
                                return l10n.addMemberPasswordTooShort;
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Personal Information ─────────────────────────────
                      _FormSection(
                        icon: Icons.person_rounded,
                        title: l10n.addMemberSectionPersonal,
                        cs: cs,
                        sagana: sagana,
                        children: [
                          _FieldLabel(label: l10n.addMemberFullNameLabel, cs: cs),
                          TextFormField(
                            controller: _fullNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              hintText: l10n.addMemberFullNameHint,
                              suffixIcon: _isCheckingRegistry
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? l10n.addMemberFullNameRequired
                                    : null,
                          ),
                          if (_registryChecked) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (_isOfficialMember
                                        ? AppConstants.successGreen
                                        : AppConstants.warningAmber)
                                    .withValues(alpha: 0.10),
                                borderRadius:
                                    BorderRadius.circular(AppConstants.radiusMd),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isOfficialMember
                                        ? Icons.verified_rounded
                                        : Icons.info_outline_rounded,
                                    size: 16,
                                    color: _isOfficialMember
                                        ? AppConstants.successGreen
                                        : AppConstants.warningAmber,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _isOfficialMember
                                          ? l10n.addMemberRegistryMatch
                                          : l10n.addMemberRegistryNoMatch,
                                      style: GoogleFonts.inter(
                                          fontSize: 11, color: cs.onSurface),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: l10n.addMemberPhoneLabel, cs: cs),
                                    TextFormField(
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        hintText: '09XX XXX XXXX',
                                      ),
                                      validator: (v) {
                                        final t = v?.trim() ?? '';
                                        if (t.isEmpty) return null;
                                        if (!RegExp(r'^09\d{9}$').hasMatch(t)) {
                                          return l10n.addMemberPhoneInvalid;
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: l10n.addMemberPurokLabel, cs: cs),
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedPurok,
                                      isExpanded: true,
                                      hint: Text(
                                        l10n.addMemberSelectHint,
                                        style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: cs.outline),
                                      ),
                                      items: AppConstants.payanasPuroks
                                          .map((s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(
                                                  s,
                                                  style: GoogleFonts.inter(
                                                      fontSize: 13),
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (v) => setState(
                                          () => _selectedPurok = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: l10n.addMemberDobLabel, cs: cs),
                                    InkWell(
                                      onTap: () async {
                                        final now = DateTime.now();
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _dateOfBirth ??
                                              DateTime(now.year - 25),
                                          firstDate: DateTime(1930),
                                          lastDate: DateTime(
                                              now.year - 18, now.month, now.day),
                                        );
                                        if (picked != null) {
                                          setState(() => _dateOfBirth = picked);
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: const InputDecoration(),
                                        child: Text(
                                          _dateOfBirth == null
                                              ? l10n.addMemberSelectHint
                                              : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: _dateOfBirth == null
                                                ? cs.outline
                                                : cs.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(label: l10n.addMemberGenderLabel, cs: cs),
                                    DropdownButtonFormField<String>(
                                      initialValue: _gender,
                                      isExpanded: true,
                                      hint: Text(l10n.addMemberSelectHint,
                                          style: GoogleFonts.inter(
                                              fontSize: 13, color: cs.outline)),
                                      items: _kGenderOptions(l10n).entries
                                          .map((e) => DropdownMenuItem(
                                                value: e.key,
                                                child: Text(e.value,
                                                    style: GoogleFonts.inter(
                                                        fontSize: 13)),
                                              ))
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _gender = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Cooperative Membership ────────────────────────────
                      _FormSection(
                        icon: Icons.badge_rounded,
                        title: l10n.addMemberSectionMembership,
                        cs: cs,
                        sagana: sagana,
                        children: [
                          _FieldLabel(label: l10n.addMemberMemberIdLabel, cs: cs),
                          TextFormField(
                            controller: _memberIdCtrl,
                            readOnly: true,
                            style: TextStyle(color: cs.onSurfaceVariant),
                            decoration: const InputDecoration(
                              hintText: 'SP3-2026-001',
                              suffixIcon: Icon(Icons.lock_outline_rounded,
                                  size: 16),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              l10n.addMemberMemberIdHelp,
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: l10n.addMemberShareValueLabel, cs: cs),
                                    TextFormField(
                                      key: const ValueKey('share-value-fixed'),
                                      readOnly: true,
                                      enabled: false,
                                      initialValue: _kShareValuePerUnit
                                          .toStringAsFixed(0),
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: l10n.addMemberInitialContributionLabel,
                                        cs: cs),
                                    TextFormField(
                                      controller: _initialContributionCtrl,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d*')),
                                      ],
                                      decoration: const InputDecoration(
                                        hintText: '0',
                                      ),
                                      validator: (v) {
                                        if (v != null &&
                                            v.isNotEmpty &&
                                            double.tryParse(v) == null) {
                                          return l10n.addMemberInvalidNumber;
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              l10n.addMemberContributionHelp,
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Initial Crops ──────────────────────────────────────
                      _FormSection(
                        icon: Icons.eco_rounded,
                        title: l10n.addMemberSectionCrops,
                        cs: cs,
                        sagana: sagana,
                        trailing: GestureDetector(
                          onTap: _showCropDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.addMemberAddCrop,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            constraints:
                                const BoxConstraints(minHeight: 50),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: cs.outline.withValues(alpha: 0.20),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd),
                            ),
                            child: _selectedCrops.isEmpty
                                ? Center(
                                    child: Text(
                                      l10n.addMemberNoCropsYet,
                                      style: GoogleFonts.inter(
                                          fontSize: 12, color: cs.outline),
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _selectedCrops
                                        .map((crop) => Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                horizontal: 12,
                                                vertical: 7,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppConstants
                                                    .primaryContainer
                                                    .withValues(alpha: 0.20),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppConstants
                                                            .radiusFull),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    crop,
                                                    style: GoogleFonts
                                                        .inter(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  GestureDetector(
                                                    onTap: () => setState(
                                                        () =>
                                                            _selectedCrops
                                                                .remove(
                                                                    crop)),
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      size: 14,
                                                      color: cs.primary
                                                          .withValues(
                                                              alpha: 0.60),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              onBack: () => context.pop(),
              onSave: _isSaving ? null : _save,
              cs: cs,
              sagana: sagana,
              l10n: l10n,
            ),
          ),

          // ── Bottom action ────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor
                    .withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(
                      color: cs.outline.withValues(alpha: 0.10)),
                ),
              ),
              child: PrimaryButton(
                label: !_isOnline
                    ? l10n.addMemberOffline
                    : (_isSaving
                        ? l10n.addMemberCreating
                        : l10n.addMemberCreateButton),
                isLoading: _isSaving,
                onPressed: (!_isOnline || _isSaving) ? null : _save,
                icon: Icons.person_add_alt_1_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;

  const _TopAppBar({
    required this.onBack,
    required this.onSave,
    required this.cs,
    required this.sagana,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
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
                child: Text(
                  l10n.addMemberTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSave,
                child: Text(
                  l10n.addMemberSave,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onSave != null
                        ? cs.primary
                        : cs.outline.withValues(alpha: 0.50),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Section Card
// ─────────────────────────────────────────────────────────────────────────────

class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final ColorScheme cs;
  final SaganaColors sagana;
  final Widget? trailing;

  const _FormSection({
    required this.icon,
    required this.title,
    required this.children,
    required this.cs,
    required this.sagana,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;

  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
