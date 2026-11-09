import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/cooperative_delivery_model.dart';
import '../../../data/repositories/cooperative_delivery_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/address_map_widgets.dart' show AddressSectionCard;
import '../../widgets/app_toast.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/view_only_banner.dart';
import 'cooperative_details_screen.dart' show signedInIsManager;

/// One editable row of the fee table. The start of a band is never typed: it is where the
/// previous band ends (the first one starts at 0), so a gap or an overlap cannot be entered.
class _BandRow {
  final TextEditingController upTo;
  final TextEditingController fee;
  _BandRow({String upTo = '', String fee = ''})
      : upTo = TextEditingController(text: upTo),
        fee = TextEditingController(text: fee);
  void dispose() {
    upTo.dispose();
    fee.dispose();
  }
}

/// Delivery Settings. Three things, nothing else:
///   1. Pickup: ON / OFF
///   2. Delivery: ON / OFF (while it is OFF, what it still needs is listed right under the switch;
///      once everything is in place and verified the list disappears and the switch can be used)
///   3. Delivery fees by distance
/// Pickup and Delivery are switched separately, and at least one stays on. The Manager edits; an
/// Officer can only look. No rate is ever pre-filled or assumed: the table starts empty.
class DeliverySettingsScreen extends StatefulWidget {
  const DeliverySettingsScreen({super.key});

  @override
  State<DeliverySettingsScreen> createState() => _DeliverySettingsScreenState();
}

class _DeliverySettingsScreenState extends State<DeliverySettingsScreen> {
  final _repo = CooperativeDeliveryRepository();
  DeliveryStatus _status = DeliveryStatus.off;
  List<DeliveryFeeBand> _saved = [];
  final List<_BandRow> _rows = [];
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  BandsProblem? _problem;
  String? _loadError;

  bool get _canEdit => signedInIsManager();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final status = await _repo.fetchDeliveryStatus();
      final bands = await _repo.fetchCurrentBands();
      if (!mounted) return;
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll([for (final b in bands) _BandRow(upTo: _num(b.maxKm), fee: _num(b.fee))]);
      setState(() {
        _status = status;
        _saved = bands;
        _dirty = false;
        _problem = null;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(AppLocalizations.of(context), e, st);
        _loading = false;
      });
    }
  }

  /// The bands as typed, each starting where the previous one ends.
  List<DeliveryFeeBand> _typed() {
    final out = <DeliveryFeeBand>[];
    var start = 0.0;
    for (final r in _rows) {
      final end = double.tryParse(r.upTo.text.trim());
      final fee = double.tryParse(r.fee.text.trim());
      if (end == null || fee == null) {
        out.add(DeliveryFeeBand(minKm: start, maxKm: start, fee: -1)); // invalid on purpose
        continue;
      }
      out.add(DeliveryFeeBand(minKm: start, maxKm: end, fee: fee));
      start = end;
    }
    return out;
  }

  void _addBand() => setState(() {
        _rows.add(_BandRow());
        _dirty = true;
      });

  void _removeLast() {
    if (_rows.isEmpty) return;
    setState(() {
      _rows.removeLast().dispose();
      _dirty = true;
    });
  }

  Future<void> _saveBands() async {
    if (!signedInIsManager() || _busy) return;
    final l10n = AppLocalizations.of(context);
    final bands = _typed();
    final problem = checkFeeBands(bands);
    setState(() => _problem = problem);
    if (problem != null) return;
    setState(() => _busy = true);
    try {
      await _repo.saveBands(bands);
      if (!mounted) return;
      AppToast.show(context, l10n.dsBandsSaved);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switch(Future<void> Function() call, String done) async {
    if (!signedInIsManager() || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      AppToast.show(context, done);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final canEdit = _canEdit;
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.dsTitle, onBack: () => context.pop()),
          const ViewOnlyBanner(module: StaffModule.marketplace),
          Expanded(
            child: _loading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_loadError!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        children: [
                          if (!canEdit)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(l10n.cdViewOnly,
                                  key: const Key('dsViewOnly'),
                                  style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
                            ),
                          _pickupCard(l10n, cs, canEdit),
                          const SizedBox(height: 12),
                          _deliveryCard(l10n, cs, canEdit),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(l10n.dsOneMethod, style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant)),
                          ),
                          const SizedBox(height: 12),
                          _bandsCard(l10n, cs, canEdit),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  /// A switch row: the title, one plain sentence about the state, and the switch.
  Widget _switchRow({
    required Key switchKey,
    required Key textKey,
    required String sentence,
    required bool on,
    required VoidCallback? onTap,
    required ColorScheme cs,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            sentence,
            key: textKey,
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: on ? AppConstants.successGreen : cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          key: switchKey,
          value: on,
          activeColor: AppConstants.successGreen,
          onChanged: onTap == null ? null : (_) => onTap(),
        ),
      ],
    );
  }

  bool get _online => ConnectivityService.instance.isOnline;

  Widget _pickupCard(AppLocalizations l10n, ColorScheme cs, bool canEdit) {
    final on = _status.pickupEnabled;
    // Pickup can be switched off only while Delivery is on (at least one method stays on).
    final canToggle = canEdit && !_busy && _online && (!on || _status.enabled);
    return AddressSectionCard(
      title: l10n.dsPickupTitle,
      child: _switchRow(
        switchKey: const Key('dsPickupSwitch'),
        textKey: const Key('dsPickupText'),
        sentence: on ? l10n.dsPickupOn : l10n.dsPickupOff,
        on: on,
        cs: cs,
        onTap: canToggle ? () => _switch(() => _repo.setPickupEnabled(!on), on ? l10n.dsPickupOffToast : l10n.dsPickupOnToast) : null,
      ),
    );
  }

  Widget _deliveryCard(AppLocalizations l10n, ColorScheme cs, bool canEdit) {
    final on = _status.enabled;
    final checklist = DeliveryChecklist.from(_status);
    // The list is shown only while Delivery is off AND something is still missing; once all of it
    // is in place and verified it disappears and the Manager can switch Delivery on.
    final showChecklist = !on && !checklist.complete;
    // On: only when everything is in place. Off: only while Pickup is on.
    final canToggle = canEdit && !_busy && _online && (on ? _status.pickupEnabled : checklist.complete);
    return AddressSectionCard(
      title: l10n.dsSwitchTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            switchKey: const Key('dsSwitch'),
            textKey: const Key('dsSwitchText'),
            sentence: on ? l10n.dsSwitchOn : l10n.dsSwitchOff,
            on: on,
            cs: cs,
            onTap: canToggle ? () => _switch(() => _repo.setDeliveryEnabled(!on), on ? l10n.dsDisabledToast : l10n.dsEnabledToast) : null,
          ),
          if (showChecklist) ...[
            const Divider(height: 22),
            Column(
              key: const Key('dsChecklist'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.dsChecklistTitle, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
                _check('pin', checklist.pinSet, l10n.dsCheckPin, cs),
                _check('contact', checklist.contactReady, l10n.dsCheckContact, cs),
                _check('bands', checklist.bandsSet, l10n.dsCheckBands, cs),
                const SizedBox(height: 2),
                TextButton.icon(
                  key: const Key('dsCompleteDetails'),
                  onPressed: () => context.push(AppRoutes.adminCooperativeDetails).then((_) => _load()),
                  icon: const Icon(Icons.apartment_rounded, size: 18),
                  label: Text(l10n.dsCheckAction),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _check(String key, bool ok, String label, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        key: Key('check_$key'),
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: ok ? AppConstants.successGreen : cs.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: ok ? cs.onSurface : cs.onSurfaceVariant))),
        ],
      ),
    );
  }

  String _problemText(AppLocalizations l10n, BandsProblem p) => switch (p) {
        BandsProblem.empty => l10n.dsBandsProblemEmpty,
        BandsProblem.badRow => l10n.dsBandsProblemRow,
        BandsProblem.notFromZero => l10n.dsBandsProblemZero,
        BandsProblem.gapOrOverlap => l10n.dsBandsProblemGap,
      };

  Widget _bandsCard(AppLocalizations l10n, ColorScheme cs, bool canEdit) {
    final typed = _typed();
    var start = 0.0;
    final rows = <Widget>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final from = start;
      final end = double.tryParse(r.upTo.text.trim());
      if (end != null) start = end;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            key: Key('bandRow_$i'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(l10n.dsBandFrom(_num(from)), style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
              ),
              Expanded(
                child: TextField(
                  key: Key('bandUpTo_$i'),
                  controller: r.upTo,
                  enabled: canEdit && !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(labelText: l10n.dsBandUpTo, isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: Key('bandFee_$i'),
                  controller: r.fee,
                  enabled: canEdit && !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(labelText: l10n.dsBandFee, prefixText: '₱ ', isDense: true),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final farthest = farthestDeliveryKm(_saved);
    return AddressSectionCard(
      title: l10n.dsBandsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dsBandsHelp, style: GoogleFonts.inter(fontSize: 12, height: 1.45, color: cs.onSurfaceVariant)),
          if (_saved.any((b) => b.isDemo))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.dsDemoWarning, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
            ),
          if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(l10n.dsBandsEmpty,
                  key: const Key('bandsEmpty'),
                  style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
            ),
          ...rows,
          if (_saved.isNotEmpty && !_dirty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(l10n.dsFarthest(_num(farthest)),
                  key: const Key('farthest'), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_problemText(l10n, _problem!),
                  key: const Key('bandsProblem'), style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
            ),
          if (canEdit) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('addBand'),
              onPressed: _busy ? null : _addBand,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.dsAddBand),
            ),
            if (_rows.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('removeBand'),
                  onPressed: _busy ? null : _removeLast,
                  child: Text(l10n.dsRemoveBand),
                ),
              ),
            const SizedBox(height: 12),
            PrimaryButton(
              key: const Key('saveBands'),
              label: l10n.dsSaveBands,
              isLoading: _busy,
              onPressed: (_dirty && typed.isNotEmpty && _online && !_busy) ? _saveBands : null,
            ),
          ],
        ],
      ),
    );
  }
}
