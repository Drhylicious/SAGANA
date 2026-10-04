import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Outcome of asking the device for its current location.
enum DeviceLocationStatus { ok, servicesOff, denied, deniedForever, failed }

/// Current-location lookup for the My Addresses form. Permission is requested
/// only when the user asks for their location; nothing is requested at
/// startup. Manual pin placement is always available when this fails.
class DeviceLocationService {
  DeviceLocationService._();

  static Future<({DeviceLocationStatus status, LatLng? point})>
  current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (status: DeviceLocationStatus.servicesOff, point: null);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return (status: DeviceLocationStatus.deniedForever, point: null);
      }
      if (permission == LocationPermission.denied) {
        return (status: DeviceLocationStatus.denied, point: null);
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return (
        status: DeviceLocationStatus.ok,
        point: LatLng(position.latitude, position.longitude),
      );
    } catch (e) {
      debugPrint('DeviceLocationService.current failed: $e');
      return (status: DeviceLocationStatus.failed, point: null);
    }
  }

  /// Opens the system settings page so a blocked permission can be changed.
  static Future<void> openSettings() => Geolocator.openAppSettings();
}
