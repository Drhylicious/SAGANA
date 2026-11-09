import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_dropdown_field.dart';

/// The cooperative's crops from Crop Management (Crop Master): active crops only, read each time the
/// form opens, so a crop added or approved a moment ago is offered at once. Used where a crop IS the
/// item (an Inventory item of type Seeds & Seedlings or Harvested Produce).
class CropMasterDropdown extends StatefulWidget {
  const CropMasterDropdown({
    super.key,
    required this.value,
    required this.labelText,
    required this.hintText,
    required this.requiredMessage,
    required this.onChanged,
    this.locked = false,
    this.currentName,
  });

  /// The chosen Crop Master id.
  final String? value;
  final String labelText;
  final String hintText;
  final String requiredMessage;

  /// Called with the crop id and its name.
  final void Function(String? id, String? name) onChanged;
  final bool locked;

  /// The name to show for [value] before the list has loaded (an existing item's crop).
  final String? currentName;

  @override
  State<CropMasterDropdown> createState() => _CropMasterDropdownState();
}

class _CropMasterDropdownState extends State<CropMasterDropdown> {
  List<({String id, String name})> _crops = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('crop_master')
          .select('id, crop_name')
          .eq('is_active', true)
          .order('crop_name');
      if (!mounted) return;
      setState(() {
        _crops = [for (final r in rows) (id: r['id'] as String, name: r['crop_name'] as String)];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _name(String id) {
    for (final c in _crops) {
      if (c.id == id) return c.name;
    }
    return widget.currentName ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final ids = _crops.map((c) => c.id).toList();
    final current = widget.value;
    final options = current == null || ids.contains(current) ? ids : [...ids, current];
    return AbsorbPointer(
      absorbing: widget.locked || _loading,
      child: Opacity(
        opacity: widget.locked ? 0.6 : 1,
        child: AppDropdownField<String>(
          key: const Key('cropMasterField'),
          value: current,
          hintText: widget.hintText,
          labelText: widget.labelText,
          items: options,
          itemLabel: _name,
          onChanged: (v) => widget.onChanged(v, v == null ? null : _name(v)),
          validator: (v) => (v == null || v.isEmpty) ? widget.requiredMessage : null,
        ),
      ),
    );
  }
}
