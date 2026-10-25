import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/farmer_registration_address.dart';
import '../../core/constants/osm_config.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import 'map_attribution_links.dart';
import 'shared_widgets.dart';
import 'sub_page_top_bar.dart';

/// Where the address maps open when nothing is pinned yet: Barangay Payanas,
/// Torrijos. Shared by My Addresses (Add / Edit) and Farm Details so both use
/// the same view.
const kAddressMapCenter = LatLng(
  FarmerRegistrationAddress.mapCenterLatitude,
  FarmerRegistrationAddress.mapCenterLongitude,
);
const kAddressMapZoom = 15.0;
const kAddressMapPinZoom = 16.5;

/// The titled white card used for each section of the address screens
/// (My Addresses Add / Edit and Farm Details).
class AddressSectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const AddressSectionCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
        boxShadow: AppConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// The "View Full Map" link that opens the full-screen picker.
class ViewFullMapLink extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const ViewFullMapLink({super.key, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.open_in_full_rounded,
            size: 14,
            color: AppConstants.primaryGreen,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppConstants.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small static map under the address: not a picker (drag, pinch and tap
/// are off), so an already-confirmed pin cannot be moved by accident. "View Full
/// Map" is how a pin is set or changed.
class AddressMapPreview extends StatelessWidget {
  final fm.MapController? controller;
  final LatLng? pin;
  final Color pinColor;
  const AddressMapPreview({
    super.key,
    required this.pin,
    this.controller,
    this.pinColor = AppConstants.errorRed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: SizedBox(
        height: 180,
        child: fm.FlutterMap(
          mapController: controller,
          options: fm.MapOptions(
            initialCenter: pin ?? kAddressMapCenter,
            initialZoom: pin != null ? kAddressMapPinZoom : kAddressMapZoom,
            interactionOptions: const fm.InteractionOptions(
              flags: fm.InteractiveFlag.none,
            ),
          ),
          children: [
            fm.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sp3coop.sagana',
              tileProvider: fm.NetworkTileProvider(
                headers: {'User-Agent': kOsmTileUserAgent},
              ),
              errorTileCallback: (tile, error, stackTrace) {},
            ),
            if (pin != null)
              fm.MarkerLayer(
                markers: [
                  fm.Marker(
                    point: pin!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: Icon(
                      Icons.location_on_rounded,
                      color: pinColor,
                      size: 36,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen map to place a pin: black background, a back button overlay,
/// zoom buttons and a confirm button. Pops the chosen point on confirm and
/// nothing on back, so the caller keeps its current pin.
class LocationPinPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final String title;
  final Color pinColor;
  const LocationPinPickerScreen({
    super.key,
    required this.title,
    this.initialLocation,
    this.pinColor = AppConstants.errorRed,
  });

  @override
  State<LocationPinPickerScreen> createState() =>
      _LocationPinPickerScreenState();
}

class _LocationPinPickerScreenState extends State<LocationPinPickerScreen> {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: fm.FlutterMap(
              mapController: _mapCtrl,
              options: fm.MapOptions(
                initialCenter: _pinnedLocation ?? kAddressMapCenter,
                initialZoom: _pinnedLocation != null
                    ? kAddressMapPinZoom
                    : kAddressMapZoom,
                onTap: _onMapTap,
              ),
              children: [
                fm.TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.sp3coop.sagana',
                  tileProvider: fm.NetworkTileProvider(
                    headers: {'User-Agent': kOsmTileUserAgent},
                  ),
                  errorTileCallback: (tile, error, stackTrace) {},
                ),
                if (_pinnedLocation != null)
                  fm.MarkerLayer(
                    markers: [
                      fm.Marker(
                        point: _pinnedLocation!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.location_on_rounded,
                          color: widget.pinColor,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: SubPageTopBar(
                      title: widget.title,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 100,
            child: Column(
              children: [
                _FullMapButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 6),
                _FullMapButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),
          // Right edge stops short of the zoom buttons (about 48 px wide plus
          // margin), so the credit wraps instead of running underneath them.
          Positioned(
            left: 12,
            right: 72,
            bottom: 96,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: Colors.white.withValues(alpha: 0.75),
                child: const MapAttributionLinks(color: Colors.black87),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: PrimaryButton(
                label: _pinnedLocation != null
                    ? l10n.buyerAddressConfirmLocation
                    : l10n.buyerAddressTapToPlacePin,
                onPressed: _pinnedLocation != null
                    ? () => Navigator.of(context).pop(_pinnedLocation)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullMapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FullMapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppConstants.primaryGreen),
      ),
    );
  }
}
