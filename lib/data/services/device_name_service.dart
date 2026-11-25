import 'device_name_stub.dart'
    if (dart.library.js_interop) 'device_name_web.dart';

/// Resolves a concise, human-readable name for the current device so
/// cross-device sign-in notices and Recent Activity entries identify Device B
/// clearly on both Android and Web.
class DeviceNameService {
  DeviceNameService._();

  static Future<String> getDeviceName() => resolvePlatformDeviceName();
}
