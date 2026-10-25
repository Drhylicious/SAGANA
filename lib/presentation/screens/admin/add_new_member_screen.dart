import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../core/utils/person_name.dart';
import '../../../core/utils/temp_password.dart';
import '../../../data/repositories/add_member_repository.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/account_form_widgets.dart';
import '../../widgets/person_name_fields.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/username_availability_field.dart';

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
  final _surnameCtrl     = TextEditingController();
  final _firstNameCtrl   = TextEditingController();
  final _middleInitialCtrl = TextEditingController();
  String? _suffix; // Jr., Sr., II, III, IV or V; null = none
  final _emailCtrl = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _initialContributionCtrl = TextEditingController();

  // ── Form state ─────────────────────────────────────────────────────────────
  DateTime? _dateOfBirth;
  String? _gender; // key of _kGenderOptions
  bool    _obscurePassword = true;
  final List<String> _selectedCrops = [];

  // Active crop_master catalog (Issue 4e) — replaces the old hardcoded list.
  List<Map<String, dynamic>> _catalogCrops = [];

  // Username availability, reported by UsernameAvailabilityField.
  UsernameStatus? _usernameStatus;
  bool _usernameChecking = false;

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
    _loadCropCatalog();
  }

  Future<void> _loadCropCatalog() async {
    final catalog = await _cropRepo.fetchCropCatalog();
    if (mounted) setState(() => _catalogCrops = catalog);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _surnameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleInitialCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _initialContributionCtrl.dispose();
    super.dispose();
  }

  // ── Password generation ─────────────────────────────────────────────────────

  void _generatePassword() {
    setState(() {
      _passwordCtrl.text = generateTemporaryPassword();
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
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
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
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.4,
                    children: available.map((entry) {
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
                              color: cs.outline.withValues(alpha: 0.20),
                            ),
                                borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                              ),
                              child: Text(
                                crop,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                              ),
                            ),
                          );
                    }).toList(),
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
    // Date of birth and gender are required form fields: validate() above has
    // already shown their inline errors. The age check is a safety net.
    final dob = _dateOfBirth;
    if (dob == null || _gender == null) return;
    if (!AppUtils.isAtLeast18(dob)) {
      _showSnack(l10n.addMemberAgeRequirement);
      return;
    }
    // The username must be confirmed free. A check that could not run
    // (UsernameStatus.error) is not a verdict: the database decides.
    if (_usernameChecking || _usernameStatus == null) {
      _showSnack(l10n.registerCheckingUsername);
      return;
    }
    if (_usernameStatus == UsernameStatus.taken) {
      _showSnack(l10n.registerUsernameTaken);
      return;
    }

    final initialContribution =
        double.tryParse(
          _initialContributionCtrl.text.trim().replaceAll(',', ''),
        ) ??
            0;

    setState(() => _isSaving = true);

    final result = await _repo.createMember(
      username:            normalizeUsername(_usernameCtrl.text),
      password:            _passwordCtrl.text.trim(),
      surname:             _surnameCtrl.text,
      firstName:           _firstNameCtrl.text,
      middleInitial:       _middleInitialCtrl.text,
      suffix:              _suffix,
      phoneNumber:         _phoneCtrl.text.trim(),
      contactEmail: _emailCtrl.text.trim(),
      dateOfBirth:         _dateOfBirth,
      gender:              _gender,
      shareValuePerUnit:   _kShareValuePerUnit,
      initialContribution: initialContribution,
      initialCrops:        _selectedCrops,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      _showSnack(
        l10n.addMemberCreatedSuccess(PersonName.compose(
          firstName: _firstNameCtrl.text,
          middleInitial: _middleInitialCtrl.text,
          surname: _surnameCtrl.text,
          suffix: _suffix,
        )),
        isSuccess: true,
      );
      context.pop(true);
    } else if (result.isPartial) {
      _showSnack(
        l10n.addMemberPartialIssue(
          result.failedStep ?? '',
          result.message ?? '',
        ),
      );
      // Member account exists — still pop back so admin sees them in the list
      context.pop(true);
    } else {
      final msg = result.message ?? l10n.addMemberCreateFailed;
      if (msg.toLowerCase().contains('username') &&
          msg.toLowerCase().contains('already taken')) {
        // Someone took the username between the availability check and Save.
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
        backgroundColor: isSuccess
            ? AppConstants.midGreen
            : AppConstants.charcoal,
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

      body: Column(
        children: [
          SubPageTopBar(title: l10n.addMemberTitle, onBack: () => context.pop()),
          Expanded(child: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
                      // ── Manager notice ──────────────────────────────────
                      ManagerNoticeCard(
                        title: l10n.addMemberAdminNoticeTitle,
                        body: l10n.addMemberAdminNoticeBody,
                      ),
                      const SizedBox(height: 20),

                      // ── Account Credentials ─────────────────────────────
                      AccountFormSection(
                        icon: Icons.lock_person_rounded,
                        title: l10n.addMemberSectionCredentials,
                        cs: cs,
                        sagana: sagana,
                        children: [
                          AccountFieldLabel(label: l10n.addMemberUsernameLabel, cs: cs),
                          UsernameAvailabilityField(
                            controller: _usernameCtrl,
                            decorationBuilder: (suffix) => InputDecoration(
                              hintText: l10n.registerUsernameHint,
                              suffixIcon: suffix,
                            ),
                            onStatusChanged: (status, checking) {
                              if (!mounted) return;
                              setState(() {
                                _usernameStatus = status;
                                _usernameChecking = checking;
                              });
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              l10n.addMemberUsernameHelp,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AccountFieldLabel(label: l10n.addMemberPasswordLabel, cs: cs),
                          TemporaryPasswordField(
                            controller: _passwordCtrl,
                            obscure: _obscurePassword,
                            onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            onGenerate: _generatePassword,
                            requiredMessage: l10n.addMemberPasswordRequired,
                            tooShortMessage: l10n.addMemberPasswordTooShort,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Personal Information ─────────────────────────────
                      AccountFormSection(
                        icon: Icons.person_rounded,
                        title: l10n.addMemberSectionPersonal,
                        cs: cs,
                        sagana: sagana,
                        children: [
                          PersonNameFields(
                            style: PersonNameFieldsStyle.form,
                            surnameController: _surnameCtrl,
                            firstNameController: _firstNameCtrl,
                            middleInitialController: _middleInitialCtrl,
                            suffix: _suffix,
                            onSuffixChanged: (v) => setState(() => _suffix = v),
                          ),
                          const SizedBox(height: 14),
                          // Email above Phone (every account form).
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AccountFieldLabel(label: l10n.addMemberEmailLabel, cs: cs),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  hintText: 'name@example.com',
                                ),
                                validator: (v) {
                                  final t = v?.trim() ?? '';
                                  if (t.isEmpty) return null;
                                  if (!isValidEmailFormat(t)) {
                                    return l10n.addMemberEmailInvalid;
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AccountFieldLabel(label: l10n.addMemberPhoneLabel, cs: cs),
                              TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: '09XX XXX XXXX',
                                ),
                                validator: (v) {
                                  final t = v?.trim() ?? '';
                                  if (t.isEmpty) return null;
                                  if (normalizePhilippineMobile(t) == null) {
                                    return l10n.addMemberPhoneInvalid;
                                  }
                                  return null;
                                },
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
                                    AccountFieldLabel(
                                      label: '${l10n.addMemberDobLabel} *',
                                      cs: cs,
                                    ),
                                    AccountDateOfBirthField(
                                      value: _dateOfBirth,
                                      onChanged: (d) =>
                                          setState(() => _dateOfBirth = d),
                                      hint: l10n.addMemberSelectHint,
                                      requiredMessage: l10n.addMemberDobRequired,
                                      underAgeMessage: l10n.addMemberAgeRequirement,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AccountFieldLabel(
                                      label: '${l10n.addMemberGenderLabel} *',
                                      cs: cs,
                                    ),
                                    AccountGenderField(
                                      value: _gender,
                                      options: _kGenderOptions(l10n),
                                      onChanged: (v) => setState(() => _gender = v),
                                      hint: l10n.addMemberSelectHint,
                                      requiredMessage: l10n.addMemberGenderRequired,
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
                      AccountFormSection(
                        icon: Icons.badge_rounded,
                        title: l10n.addMemberSectionMembership,
                        cs: cs,
                        sagana: sagana,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AccountFieldLabel(
                              label: l10n.addMemberShareValueLabel,
                              cs: cs,
                            ),
                                    TextFormField(
                                      key: const ValueKey('share-value-fixed'),
                                      readOnly: true,
                                      enabled: false,
                              initialValue: _kShareValuePerUnit.toStringAsFixed(
                                0,
                              ),
                              style: TextStyle(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AccountFieldLabel(
                                        label: l10n.addMemberInitialContributionLabel,
                              cs: cs,
                            ),
                                    TextFormField(
                                      controller: _initialContributionCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*'),
                                      ),
                              ],
                              decoration: const InputDecoration(hintText: '0'),
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
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Initial Crops ──────────────────────────────────────
                      AccountFormSection(
                        icon: Icons.eco_rounded,
                        title: l10n.addMemberSectionCrops,
                        cs: cs,
                        sagana: sagana,
                        trailing: GestureDetector(
                          onTap: _showCropDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                        Icon(Icons.add_rounded, size: 14, color: cs.primary),
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
                    constraints: const BoxConstraints(minHeight: 50),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: cs.outline.withValues(alpha: 0.20),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                            ),
                            child: _selectedCrops.isEmpty
                                ? Center(
                                    child: Text(
                                      l10n.addMemberNoCropsYet,
                                      style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.outline,
                              ),
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _selectedCrops
                                .map(
                                  (crop) => Container(
                                    padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 7,
                                              ),
                                              decoration: BoxDecoration(
                                      color: AppConstants.primaryContainer
                                                    .withValues(alpha: 0.20),
                                      borderRadius: BorderRadius.circular(
                                        AppConstants.radiusFull,
                                      ),
                                              ),
                                              child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    crop,
                                          style: GoogleFonts.inter(
                                                      fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  GestureDetector(
                                                    onTap: () => setState(
                                            () => _selectedCrops.remove(crop),
                                          ),
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      size: 14,
                                            color: cs.primary.withValues(
                                              alpha: 0.60,
                                            ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                  ),
                                )
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
    );
  }
}
