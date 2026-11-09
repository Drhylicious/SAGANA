import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/cooperative_delivery_model.dart';
import '../../data/services/cooperative_address_service.dart';

/// The cooperative's complete address, read from Cooperative Details (never hardcoded).
/// [builder] receives the details once they are known; while they load a quiet placeholder
/// shows, and when they cannot be read (and nothing is remembered) a short "unavailable" line.
class CooperativeAddressBuilder extends StatefulWidget {
  const CooperativeAddressBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, CooperativeDetails details)
  builder;

  @override
  State<CooperativeAddressBuilder> createState() =>
      _CooperativeAddressBuilderState();
}

class _CooperativeAddressBuilderState extends State<CooperativeAddressBuilder> {
  CooperativeDetails? _details;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _details = CooperativeAddressService.instance.cached;
    _load();
  }

  Future<void> _load() async {
    final d = await CooperativeAddressService.instance.load(
      force: _details == null,
    );
    if (!mounted) return;
    setState(() {
      _details = d ?? _details;
      _failed = _details == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    if (d != null) return widget.builder(context, d);
    if (_failed) {
      return Text(
        AppLocalizations.of(context).cdAddressUnavailable,
        key: const Key('coopAddressUnavailable'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Container(
      key: const Key('coopAddressLoading'),
      height: 14,
      width: 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// The address as one text line, optionally led by the cooperative's name.
class CooperativeAddressText extends StatelessWidget {
  const CooperativeAddressText({super.key, this.style, this.withName = false});

  final TextStyle? style;
  final bool withName;

  @override
  Widget build(BuildContext context) {
    return CooperativeAddressBuilder(
      builder: (_, d) => Text(
        withName ? '${d.cooperativeName}, ${d.addressLine}' : d.addressLine,
        key: const Key('coopAddressText'),
        style: style,
      ),
    );
  }
}
