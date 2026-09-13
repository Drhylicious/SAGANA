import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../../data/services/auth_service.dart';

/// Admin → Members → Add Officer Account (Issue 6).
///
/// Every Officer must come from the Officer Registry (Decision D22): typing
/// a name that matches an available registry row auto-fills phone/email and
/// unlocks the form. Employee ID (EMP-###) is generated server-side and
/// shown read-only (Decision D23). There are no per-officer permissions —
/// an Officer gets every Admin module except the Members tab (Decision D12).
class CreateOfficerAccountScreen extends StatefulWidget {
  const CreateOfficerAccountScreen({super.key});

  @override
  State<CreateOfficerAccountScreen> createState() =>
      _CreateOfficerAccountScreenState();
}

class _CreateOfficerAccountScreenState
    extends State<CreateOfficerAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _repo = AccountManagementRepository();

  bool _isSaving = false;
  bool _obscurePassword = true;

  // Temporary password — either auto-generated (AUTO button) or typed by
  // the Admin, matching the Create Farmer Account flow.
  void _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rand = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    for (int i = 0; i < 10; i++) {
      buffer.write(chars[(rand + i * 17) % chars.length]);
    }
    setState(() {
      _passwordCtrl.text = buffer.toString();
      _obscurePassword = false;
    });
  }

  // Registry gate (Decision D22)
  Timer? _debounce;
  bool _checking = false;
  bool _checked = false;
  String? _registryId;      // set only when a matching AVAILABLE row is found
  String? _registryError;   // "already registered" / "not found"
  String _empIdPreview = 'EMP-###';

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _fullNameCtrl.addListener(_onNameChanged);
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final username = await AuthService.suggestNextUsername('OFF');
    String emp = 'EMP-###';
    try {
      final r = await Supabase.instance.client.rpc('generate_employee_id');
      if (r is String && r.isNotEmpty) emp = r;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _usernameCtrl.text = username;
        _empIdPreview = emp;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fullNameCtrl.removeListener(_onNameChanged);
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _positionCtrl.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final name = _fullNameCtrl.text.trim();
    if (_checked || _registryId != null || _registryError != null) {
      setState(() {
        _checked = false;
        _registryId = null;
        _registryError = null;
      });
    }
    if (name.length < 3) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _check(name));
  }

  Future<void> _check(String name) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _checking = true);
    final match = await _repo.checkOfficerRegistry(name);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = true;
      if (match == null) {
        _registryId = null;
        _registryError = l10n.createOfficerNotInRegistry;
      } else if (!match.isAvailable) {
        _registryId = null;
        _registryError = l10n.createOfficerAlreadyHasAccount;
      } else {
        _registryId = match.registryId;
        _registryError = null;
        if (match.phone != null && _phoneCtrl.text.trim().isEmpty) {
          _phoneCtrl.text = match.phone!;
        }
        if (match.email != null && _emailCtrl.text.trim().isEmpty) {
          _emailCtrl.text = match.email!;
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    if (_registryId == null) {
      _toast(_registryError ?? l10n.createOfficerWaitForCheck);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _repo.createOfficerAccount(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _fullNameCtrl.text.trim(),
        registryId: _registryId!,
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        phoneNumber:
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        position:
            _positionCtrl.text.trim().isEmpty ? null : _positionCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.createOfficerCreated,
            style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppConstants.successGreen,
      ));
      context.pop(true);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (message.toLowerCase().contains('already')) {
        await _loadSuggestions();
      }
      if (!mounted) return;
      _toast(message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: AppConstants.charcoal,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final canSubmit = _registryId != null && !_isSaving;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.createOfficerTitle,
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  border: Border(left: BorderSide(color: cs.primary, width: 4)),
                ),
                child: Text(
                  l10n.createOfficerNotice,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: l10n.createOfficerSectionOfficer,
                cs: cs,
                sagana: sagana,
                children: [
                  _FieldLabel(label: l10n.createOfficerFullNameLabel, cs: cs),
                  TextFormField(
                    controller: _fullNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: l10n.createOfficerFullNameHint,
                      suffixIcon: _checking
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : (_registryId != null
                              ? const Icon(Icons.check_circle_rounded,
                                  color: AppConstants.successGreen)
                              : null),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.createOfficerFullNameRequired
                        : null,
                  ),
                  if (_checked && _registryError != null) ...[
                    const SizedBox(height: 8),
                    Text(_registryError!,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppConstants.errorRed)),
                  ],
                  if (_registryId != null) ...[
                    const SizedBox(height: 8),
                    Text(l10n.createOfficerMatched,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.successGreen)),
                  ],
                  const SizedBox(height: 12),
                  _FieldLabel(label: l10n.createOfficerEmailLabel, cs: cs),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration:
                        const InputDecoration(hintText: 'name@example.com'),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: l10n.createOfficerPhoneLabel, cs: cs),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(hintText: '09XX XXX XXXX'),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: l10n.createOfficerPositionLabel, cs: cs),
                  TextFormField(
                    controller: _positionCtrl,
                    decoration:
                        InputDecoration(hintText: l10n.createOfficerPositionHint),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: l10n.createOfficerEmployeeIdLabel, cs: cs),
                  TextFormField(
                    key: ValueKey(_empIdPreview),
                    readOnly: true,
                    enabled: false,
                    initialValue: _empIdPreview,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      l10n.createOfficerEmployeeIdHelp,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: l10n.createOfficerSectionLogin,
                cs: cs,
                sagana: sagana,
                children: [
                  _FieldLabel(label: l10n.createOfficerUsernameLabel, cs: cs),
                  TextFormField(
                    controller: _usernameCtrl,
                    readOnly: true,
                    style: TextStyle(color: cs.onSurfaceVariant),
                    decoration: const InputDecoration(hintText: 'OFF-0001'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.createOfficerUsernameRequired
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(l10n.createOfficerUsernameHelp,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: l10n.createOfficerPasswordLabel, cs: cs),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: l10n.createOfficerPasswordHint,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: cs.outline,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: _generatePassword,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: cs.primary
                                          .withValues(alpha: 0.30)),
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.radiusSm),
                                ),
                                child: Text('AUTO',
                                    style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: cs.primary)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? l10n.createOfficerPasswordTooShort
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: canSubmit ? _submit : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_add_alt_1_rounded),
            label: Text(_isSaving
                ? l10n.createOfficerCreating
                : l10n.createOfficerCreateButton),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _SectionCard({
    required this.title,
    required this.children,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 12),
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
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant)),
    );
  }
}
