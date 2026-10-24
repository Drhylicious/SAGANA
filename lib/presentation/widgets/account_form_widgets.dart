import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/app_utils.dart';

// Building blocks shared by the Manager's account-creation forms (Create
// Farmer Account and Create Officer Account), so both screens look and behave
// the same and a change to one is a change to both.

/// The "Manager Notice" panel at the top of a creation form.
class ManagerNoticeCard extends StatelessWidget {
  const ManagerNoticeCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(left: BorderSide(color: cs.primary, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
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
    );
  }
}

/// A titled card that groups related fields (icon, title, optional trailing
/// action such as "Add Crop").
class AccountFormSection extends StatelessWidget {
  const AccountFormSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    required this.cs,
    required this.sagana,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final ColorScheme cs;
  final SaganaColors sagana;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded, not spaceBetween with two unguarded children: some
              // section titles and the trailing pill's label are markedly
              // longer in Tagalog than in English and used to overflow this
              // Row. The title yields first via ellipsis; the trailing pill
              // keeps its natural size.
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// The small label above a field. One line with an ellipsis, so two labels
/// side by side (Date of Birth / Gender) always keep their inputs aligned.
class AccountFieldLabel extends StatelessWidget {
  const AccountFieldLabel({super.key, required this.label, required this.cs});

  final String label;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The temporary-password field: show/hide, an AUTO button that fills in a
/// secure random password, and the 8-character minimum.
class TemporaryPasswordField extends StatelessWidget {
  const TemporaryPasswordField({
    super.key,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onGenerate,
    required this.requiredMessage,
    required this.tooShortMessage,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onGenerate;
  final String requiredMessage;
  final String tooShortMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: '••••••••',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: cs.outline,
              ),
              onPressed: onToggleObscure,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: onGenerate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary.withValues(alpha: 0.30)),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Text(
                    l10n.autoGeneratedBadge,
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
        if (v == null || v.isEmpty) return requiredMessage;
        if (v.length < 8) return tooShortMessage;
        return null;
      },
    );
  }
}

/// Date of Birth for an account the Manager creates. A required form field: it
/// reports its own inline error (red border and message) through the form's
/// validate(), exactly like the text fields beside it.
///
///  * Nothing chosen: [requiredMessage].
///  * A date that makes the person under 18 is refused: the age dialog is
///    shown, the field is cleared and shows [underAgeMessage] until a valid
///    date is chosen.
///
/// [pickDate] replaces the date picker, for tests only.
class AccountDateOfBirthField extends StatefulWidget {
  const AccountDateOfBirthField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.hint,
    required this.requiredMessage,
    required this.underAgeMessage,
    this.pickDate,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String hint;
  final String requiredMessage;
  final String underAgeMessage;
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)?
  pickDate;

  @override
  State<AccountDateOfBirthField> createState() =>
      _AccountDateOfBirthFieldState();
}

class _AccountDateOfBirthFieldState extends State<AccountDateOfBirthField> {
  // The last date offered was under 18 and was refused.
  bool _tooYoung = false;

  String _format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(FormFieldState<DateTime> field) async {
    final picker =
        widget.pickDate ??
        (BuildContext c, DateTime? initial) =>
            AppUtils.pickDateOfBirth(c, initialDate: initial);
    final picked = await picker(context, widget.value);
    if (picked == null || !mounted) return;
    if (!AppUtils.isAtLeast18(picked)) {
      await AppUtils.showUnder18Dialog(context);
      if (!mounted) return;
      setState(() => _tooYoung = true);
      widget.onChanged(null);
      field.didChange(null);
      return;
    }
    setState(() => _tooYoung = false);
    widget.onChanged(picked);
    field.didChange(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FormField<DateTime>(
      initialValue: widget.value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        if (v == null) {
          return _tooYoung ? widget.underAgeMessage : widget.requiredMessage;
        }
        return AppUtils.isAtLeast18(v) ? null : widget.underAgeMessage;
      },
      builder: (field) {
        final value = field.value;
        return InkWell(
          onTap: () => _pick(field),
          child: InputDecorator(
            // errorMaxLines: the field is half a screen wide, so a longer message wraps
            // instead of being cut off with …
            decoration: InputDecoration(errorText: field.errorText, errorMaxLines: 3),
            child: Text(
              value == null ? widget.hint : _format(value),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: value == null ? cs.outline : cs.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Gender for an account the Manager creates. A required dropdown with its own
/// message ([requiredMessage]), shown with a red border like any other required
/// field.
class AccountGenderField extends StatelessWidget {
  const AccountGenderField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.hint,
    required this.requiredMessage,
  });

  final String? value;

  /// Stored value → label.
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
  final String hint;
  final String requiredMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: const InputDecoration(errorMaxLines: 3),
      hint: Text(
        hint,
        style: GoogleFonts.inter(fontSize: 13, color: cs.outline),
      ),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: GoogleFonts.inter(fontSize: 13)),
            ),
          )
          .toList(),
      validator: (v) => v == null ? requiredMessage : null,
      onChanged: onChanged,
    );
  }
}
