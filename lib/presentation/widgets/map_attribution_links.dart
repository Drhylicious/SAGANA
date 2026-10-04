import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/osm_config.dart';

/// Visible attribution for the address screens: the OpenStreetMap copyright
/// (map and search data) and, where geocoding results are shown, the required
/// "Search by LocationIQ.com" link. Both links open in the external browser.
class MapAttributionLinks extends StatelessWidget {
  final bool showLocationIq;
  final Color? color;

  const MapAttributionLinks({
    super.key,
    this.showLocationIq = true,
    this.color,
  });

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      fontSize: 10,
      color: color ?? AppConstants.onSurfaceVariant,
      decoration: TextDecoration.underline,
    );
    final separatorStyle = style.copyWith(decoration: TextDecoration.none);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 0,
      children: [
        _AttributionLink(
          label: kOsmAttribution,
          style: style,
          onTap: () => _open(kOpenStreetMapCopyrightUrl),
        ),
        if (showLocationIq) ...[
          Text('·', style: separatorStyle),
          _AttributionLink(
            label: kLocationIqAttributionText,
            style: style,
            onTap: () => _open(kLocationIqUrl),
          ),
        ],
      ],
    );
  }
}

/// Tappable attribution text with a padded touch area, so the small link text
/// is easy to hit without making the line taller.
class _AttributionLink extends StatelessWidget {
  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  const _AttributionLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label, style: style),
      ),
    );
  }
}

/// Compact OpenStreetMap attribution for small maps (the farm-details and
/// Supply Chain previews). Unlike flutter_map's SimpleAttributionWidget, it
/// shrinks to the space it's given and truncates long text, so it cannot
/// overflow a narrow map. Always visible, bottom-right, not behind a toggle.
class OsmMapAttribution extends StatelessWidget {
  const OsmMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          color: Colors.white.withValues(alpha: 0.8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            kOsmAttribution,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 9, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}
