import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/map_attribution_links.dart';
import '../../../core/constants/osm_config.dart';

const _defaultCenter = LatLng(13.6302, 121.9392);
const _defaultZoom = 15.0;
const _pinZoom = 16.5;

/// Full-screen version of Edit Farm Details' inline map preview, for
/// precisely placing/reviewing the farm pin on a larger surface. Always
/// pops with the current pin state (whether reached via the back arrow or
/// the "Use This Location" button) so the caller can unconditionally
/// apply the result without needing to distinguish "cancelled" from
/// "confirmed" — a tap anywhere on the map already commits the new pin
/// position live, same as the collapsed in-page map does today.
class FarmLocationFullMapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const FarmLocationFullMapScreen({super.key, this.initialLocation});

  @override
  State<FarmLocationFullMapScreen> createState() =>
      _FarmLocationFullMapScreenState();
}

class _FarmLocationFullMapScreenState extends State<FarmLocationFullMapScreen> {
  final _mapCtrl = fm.MapController();
  LatLng? _pinnedLocation;

  @override
  void initState() {
    super.initState();
    _pinnedLocation = widget.initialLocation;
  }

  void _onMapTap(fm.TapPosition _, LatLng point) {
    setState(() => _pinnedLocation = point);
  }

  void _done() => Navigator.of(context).pop(_pinnedLocation);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppConstants.offWhite,
        foregroundColor: AppConstants.charcoal,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _done,
        ),
        title: Text(
          'Farm Location',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      body: Stack(
        children: [
          fm.FlutterMap(
            mapController: _mapCtrl,
            options: fm.MapOptions(
              initialCenter: _pinnedLocation ?? _defaultCenter,
              initialZoom: _pinnedLocation != null ? _pinZoom : _defaultZoom,
              onTap: _onMapTap,
            ),
            children: [
              const OsmMapAttribution(),
              fm.TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sp3coop.sagana',
                tileProvider: fm.NetworkTileProvider(
                  headers: {'User-Agent': kOsmTileUserAgent},
                ),
                // See edit_farm_details_screen.dart's identical callback —
                // flutter_map cancels in-flight tile requests for tiles
                // scrolled out of view mid-pan/zoom; expected, not a
                // real failure.
                errorTileCallback: (tile, error, stackTrace) {},
              ),
              if (_pinnedLocation != null)
                fm.MarkerLayer(
                  markers: [
                    fm.Marker(
                      point: _pinnedLocation!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 44,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                'Tap anywhere on the map to place your farm pin',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _done,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use This Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
