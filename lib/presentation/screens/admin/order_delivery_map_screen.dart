import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/osm_config.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/map_attribution_links.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Read-only view of an order's saved delivery pinpoint, for Admin and
/// Officer. The pin is the buyer's coordinates captured when the order was
/// placed. There is no tap handler, no confirm action and no drag, so the
/// location cannot be changed from here. Pan and zoom only, to inspect it.
class OrderDeliveryMapScreen extends StatefulWidget {
  final LatLng point;
  const OrderDeliveryMapScreen({super.key, required this.point});

  @override
  State<OrderDeliveryMapScreen> createState() => _OrderDeliveryMapScreenState();
}

class _OrderDeliveryMapScreenState extends State<OrderDeliveryMapScreen> {
  final _mapCtrl = fm.MapController();

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
                initialCenter: widget.point,
                initialZoom: 16.5,
                interactionOptions: const fm.InteractionOptions(
                  flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
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
                fm.MarkerLayer(
                  markers: [
                    fm.Marker(
                      point: widget.point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppConstants.errorRed,
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
                    child: SubPageTopBar(title: l10n.orderDetailDeliveryPinTitle, onBack: () => Navigator.of(context).pop()),
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
                _ZoomButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 6),
                _ZoomButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),
          // Right edge stops short of the zoom buttons, so the credit wraps
          // instead of running underneath them.
          Positioned(
            left: 12,
            right: 72,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: Colors.white.withValues(alpha: 0.75),
                child: const MapAttributionLinks(color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

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
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: AppConstants.primaryGreen),
      ),
    );
  }
}
