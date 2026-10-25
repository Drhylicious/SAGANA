import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/quantity_utils.dart';
import 'app_dropdown_field.dart';

/// The shared height of the Quantity input and the Unit dropdown, so the two
/// sit as one balanced row. 50 is what the Unit dropdown measures (48 for its
/// arrow box plus its 1px border).
const double kQuantityUnitFieldHeight = 50;

/// Quantity | Unit, side by side — the harvest quantity input.
///
/// Each field owns its label, its border and its own message directly
/// underneath it, so an error under Quantity never moves or stretches the Unit
/// field next to it (both columns are top-aligned). The quantity is a plain
/// decimal (0.45, 1.25, 10.75 — at most 2 decimals) with no unit baked into
/// it; the unit is chosen from the cooperative's unit list.
///
/// Must sit inside a [Form]: both fields register with it, so
/// `formKey.currentState!.validate()` shows the message of whichever is wrong.
class QuantityUnitField extends StatelessWidget {
  final TextEditingController controller;

  /// The unit names to choose from (the cooperative's units list).
  final List<String> units;
  final String? selectedUnit;

  /// True when the unit is fixed (a crop sold through one channel, in kg): the
  /// dropdown shows it but cannot change it.
  final bool unitLocked;
  final ValueChanged<String?> onUnitChanged;

  /// Shows a "+ Unit" row at the end of the dropdown, which asks for a new unit
  /// and returns its name (null if cancelled). Never offered while the unit is
  /// locked. [addUnitLabel] is the row's text.
  final Future<String?> Function()? onAddUnit;
  final String? addUnitLabel;

  const QuantityUnitField({
    super.key,
    required this.controller,
    required this.units,
    required this.selectedUnit,
    required this.unitLocked,
    required this.onUnitChanged,
    this.onAddUnit,
    this.addUnitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Quantity*'),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('quantityField'),
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                // The whole new value is checked on every edit: digits and one
                // point, at most 2 decimals.
                inputFormatters: const [DecimalInputFormatter()],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textAlignVertical: TextAlignVertical.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
                decoration: InputDecoration(
                  // Same height as the Unit dropdown beside it.
                  constraints: const BoxConstraints(
                    minHeight: kQuantityUnitFieldHeight,
                    maxHeight: kQuantityUnitFieldHeight,
                  ),
                  hintText: '0.00',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppConstants.outline.withValues(alpha: 0.60),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 0,
                  ),
                  errorMaxLines: 2,
                  errorStyle: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: cs.error,
                  ),
                  border: border(cs.outline.withValues(alpha: 0.4)),
                  enabledBorder: border(cs.outline.withValues(alpha: 0.4)),
                  focusedBorder: border(cs.primary, width: 1.5),
                  errorBorder: border(cs.error),
                  focusedErrorBorder: border(cs.error, width: 1.5),
                ),
                validator: (v) => quantityErrorText(v),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Unit*'),
              const SizedBox(height: 8),
              AppDropdownField<String>(
                key: const Key('unitField'),
                value: selectedUnit,
                hintText: 'Select unit',
                items: units,
                itemLabel: (u) => u,
                onChanged: unitLocked ? (_) {} : onUnitChanged,
                validator: (u) => u == null ? 'Unit is required' : null,
                // "+ Unit", the same compact row Price Management uses.
                addNewLabel: unitLocked || onAddUnit == null ? null : addUnitLabel,
                addNewShowIcon: false,
                onAddNew: unitLocked ? null : onAddUnit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppConstants.onSurfaceVariant,
        ),
      ),
    );
  }
}
