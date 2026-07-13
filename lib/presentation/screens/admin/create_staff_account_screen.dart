import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';

class CreateStaffAccountScreen extends StatefulWidget {
  const CreateStaffAccountScreen({super.key});

  @override
  State<CreateStaffAccountScreen> createState() =>
      _CreateStaffAccountScreenState();
}

class _CreateStaffAccountScreenState extends State<CreateStaffAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController();

  String? _selectedSitio;
  bool _isSaving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _positionCtrl.dispose();
    _employeeIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client.rpc('create_staff_account', params: {
        'p_username': _usernameCtrl.text.trim(),
        'p_password': _passwordCtrl.text,
        'p_full_name': _fullNameCtrl.text.trim(),
        'p_phone_number': _phoneCtrl.text.trim(),
        'p_sitio': _selectedSitio,
        'p_position': _positionCtrl.text.trim(),
        'p_employee_id': _employeeIdCtrl.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Staff account created successfully.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.successGreen,
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PostgrestException ? e.message : 'Unable to create staff account.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.charcoal,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Create Staff Account',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
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
                  'Create an internal staff login for cooperative operations.',
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Account Details',
                cs: cs,
                sagana: sagana,
                children: [
                  _FieldLabel(label: 'SAGANA Username', cs: cs),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(hintText: 'STF-0001'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Username is required' : null,
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: 'Temporary Password', cs: cs),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: cs.outline,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) =>
                        (value == null || value.length < 8) ? 'Minimum 8 characters' : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Staff Information',
                cs: cs,
                sagana: sagana,
                children: [
                  _FieldLabel(label: 'Full Name', cs: cs),
                  TextFormField(
                    controller: _fullNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'e.g. Maria Santos'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Full name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: 'Phone Number', cs: cs),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: '09XX XXX XXXX'),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: 'Sitio / Purok', cs: cs),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSitio,
                    decoration: const InputDecoration(hintText: 'Select sitio'),
                    items: AppConstants.payanasSitios
                        .map((site) => DropdownMenuItem(value: site, child: Text(site)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedSitio = value),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: 'Position', cs: cs),
                  TextFormField(
                    controller: _positionCtrl,
                    decoration: const InputDecoration(hintText: 'Operations Staff'),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: 'Employee ID', cs: cs),
                  TextFormField(
                    controller: _employeeIdCtrl,
                    decoration: const InputDecoration(hintText: 'EMP-001'),
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
            onPressed: _isSaving ? null : _submit,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_add_alt_1_rounded),
            label: Text(_isSaving ? 'Creating account...' : 'Create Staff Account'),
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
          Text(
            title,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
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
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      ),
    );
  }
}
