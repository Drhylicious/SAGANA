import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// A text field drawn exactly like [AppDropdownField], so a form that mixes both reads as one column:
/// the label sits above the field (small, grey), and the field is a 48px-high box with 8px corners,
/// a 1px border and 14px padding. Used by the Add / Edit Inventory Item and New Program sheets.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.readOnly = false,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.prefixText,
    this.suffixText,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final bool readOnly;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? prefixText;
  final String? suffixText;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: width),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          validator: validator,
          style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            prefixText: prefixText,
            suffixText: suffixText,
            isDense: true,
            constraints: const BoxConstraints(minHeight: 48),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: border(cs.outline.withValues(alpha: 0.4)),
            enabledBorder: border(cs.outline.withValues(alpha: 0.4)),
            focusedBorder: border(cs.primary, 1.5),
            errorBorder: border(cs.error),
            focusedErrorBorder: border(cs.error, 1.5),
          ),
        ),
      ],
    );
  }
}
