import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Copies an already-generated report to public Android Downloads. Generation,
/// export history and sharing continue to use the original private file.
class ReportDownloadService {
  static const channel = MethodChannel('com.sp3cooperative.sagana/downloads');

  Future<String> save(String sourcePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformException(code: 'unsupported_platform');
    }
    try {
      final name = await channel.invokeMethod<String>('saveReport', {
        'sourcePath': sourcePath,
      });
      if (name == null || name.isEmpty) {
        throw PlatformException(code: 'save_failed');
      }
      return name;
    } on MissingPluginException {
      throw PlatformException(code: 'unsupported_platform');
    }
  }
}
