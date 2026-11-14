import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/quantity_utils.dart';

/// The order-quantity control shared by Buy Now and the Cart (Buyer and Farmer):
/// `−  [ 10 ]  +`.
///
/// The number is a real text field, so a person can type 5 directly instead of
/// pressing − five times; − and + still move it by [step]. It holds a decimal of
/// at most 2 places, never above [max] (the stock left), and never below [min].
///
/// It reports every valid value AS IT IS TYPED through [onChanged], so whoever
/// owns the quantity (a total, the Buy Now button, the saved cart line) is never
/// a keystroke behind. A half-typed value (empty, `0`, `0.`) is simply not
/// reported; when the field loses focus or is submitted it is tidied to the last
/// valid value. The unit is not part of the control: the screen shows it.
class QuantityStepper extends StatefulWidget {
  final double value;

  /// Smallest accepted quantity (0.01 — the database accepts anything above 0).
  final double min;

  /// Largest accepted quantity: what is left to buy.
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  /// False greys the control out and makes the number read-only.
  final bool enabled;

  /// Asked before a change is accepted (buttons and typing). Returning false
  /// puts the old number back and calls [onBlocked] — used for "changes need a
  /// connection".
  final bool Function()? allowChange;
  final VoidCallback? onBlocked;

  /// Cart size (small filled buttons) instead of the Buy Now pill.
  final bool compact;

  const QuantityStepper({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0.01,
    this.step = 1,
    this.enabled = true,
    this.allowChange,
    this.onBlocked,
    this.compact = false,
  });

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  late double _current;

  // Below 0.01 left, the only quantity left is whatever is left.
  double get _min => widget.max < widget.min ? widget.max : widget.min;

  double _clamp(double v) {
    final hi = widget.max < 0 ? 0.0 : widget.max;
    final lo = _min < 0 ? 0.0 : _min;
    return roundQuantity(v.clamp(lo, hi < lo ? lo : hi).toDouble());
  }

  @override
  void initState() {
    super.initState();
    _current = _clamp(widget.value);
    _controller = TextEditingController(text: formatQuantity(_current));
    _focus = FocusNode()
      ..addListener(() {
        if (!_focus.hasFocus) _commit();
      });
  }

  @override
  void didUpdateWidget(covariant QuantityStepper old) {
    super.didUpdateWidget(old);
    // The owner changed the quantity itself (for example the stock left dropped):
    // show it. A value we just reported equals _current and changes nothing.
    final next = _clamp(widget.value);
    if (next != _current) {
      _current = next;
      _setText(next);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setText(double v) {
    final text = formatQuantity(v);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  bool _permitted() {
    final ok = widget.allowChange?.call() ?? true;
    if (!ok) {
      // Put the old number back and tell the owner why nothing changed.
      _setText(_current);
      widget.onBlocked?.call();
    }
    return ok;
  }

  void _step(double delta) {
    if (!widget.enabled || !_permitted()) return;
    final next = _clamp(_current + delta);
    if (next == _current) return;
    _current = next;
    _setText(next);
    widget.onChanged(next);
  }

  void _typed(String text) {
    final parsed = double.tryParse(text.trim());
    // Half-typed (empty, "0", "0."): not a quantity yet, so nothing is reported.
    if (parsed == null || parsed < _min || parsed > widget.max + 1e-9) return;
    if (!_permitted()) return;
    final next = roundQuantity(parsed);
    if (next == _current) return;
    _current = next;
    widget.onChanged(next);
  }

  // Focus left or Done pressed: tidy the text ("5." -> "5") or restore the last
  // valid number when what is typed is not a quantity.
  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed < _min) {
      _setText(_current);
      return;
    }
    final next = _clamp(parsed);
    _setText(next);
    if (next != _current && _permitted()) {
      _current = next;
      widget.onChanged(next);
    }
  }

  Widget _field() {
    final compact = widget.compact;
    return SizedBox(
      width: compact ? 52 : 56,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        inputFormatters: [DecimalInputFormatter(max: widget.max)],
        onChanged: _typed,
        onSubmitted: (_) => _commit(),
        // Tapping the number selects it all, so typing 5 replaces 10.
        onTap: () => _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        ),
        style: GoogleFonts.poppins(
          fontSize: compact ? 13 : 16,
          fontWeight: FontWeight.w700,
          color: widget.enabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _button(IconData icon, double delta) {
    final compact = widget.compact;
    final canUse =
        widget.enabled &&
        (delta < 0 ? _current > _min + 1e-9 : _current < widget.max - 1e-9);
    final size = compact ? 26.0 : 32.0;
    final child = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: compact
          ? BoxDecoration(
              color: canUse
                  ? context.saganaColors.scaffoldBackground
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Icon(
        icon,
        size: compact ? 14 : 16,
        color: canUse
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // A disabled button still answers a tap while it only refuses (offline).
      onTap: widget.enabled ? () => _step(delta) : null,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.remove, -widget.step),
        _field(),
        _button(Icons.add, widget.step),
      ],
    );
    if (widget.compact) {
      // The number sits in its own thin box so it reads as something to type in.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove, -widget.step),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppConstants.primaryGreen.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _field(),
          ),
          _button(Icons.add, widget.step),
        ],
      );
    }
    // Buy Now: one shared bordered pill around − number + (as before).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: row,
    );
  }
}
