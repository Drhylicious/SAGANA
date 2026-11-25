import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _deviceInfoChannel = MethodChannel(
  'com.sp3cooperative.sagana/device_info',
);

Future<String> resolvePlatformDeviceName() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final name = await _deviceInfoChannel.invokeMethod<String>(
        'getDeviceName',
      );
      final trimmed = name?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    } on MissingPluginException {
      // Tests and non-Android embeds fall back cleanly below.
    } catch (_) {
      // Fall back to a safe platform label.
    }
    return 'Android device';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'iOS device';
    case TargetPlatform.windows:
      return 'Windows device';
    case TargetPlatform.macOS:
      return 'Mac device';
    case TargetPlatform.linux:
      return 'Linux device';
    case TargetPlatform.fuchsia:
      return 'Fuchsia device';
    case TargetPlatform.android:
      return 'Android device';
  }
}
