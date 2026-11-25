import 'dart:js_interop';

@JS('navigator.userAgent')
external String get _navigatorUserAgent;

Future<String> resolvePlatformDeviceName() async {
  try {
    return describeBrowserUserAgent(_navigatorUserAgent);
  } catch (_) {
    return 'Web browser';
  }
}

/// Converts a browser User-Agent string into a short readable device label
/// (e.g. `"Chrome on Windows"` or `"Safari on iPhone"`).
String describeBrowserUserAgent(String ua) {
  final lower = ua.toLowerCase();
  String browser;
  if (lower.contains('edg/') || lower.contains('edga/') || lower.contains('edgios/')) {
    browser = 'Edge';
  } else if (lower.contains('opr/') || lower.contains('opera')) {
    browser = 'Opera';
  } else if (lower.contains('firefox/') || lower.contains('fxios/')) {
    browser = 'Firefox';
  } else if (lower.contains('chrome/') || lower.contains('crios/')) {
    browser = 'Chrome';
  } else if (lower.contains('safari/')) {
    browser = 'Safari';
  } else {
    browser = 'Web browser';
  }

  String os = '';
  if (lower.contains('iphone')) {
    os = 'iPhone';
  } else if (lower.contains('ipad')) {
    os = 'iPad';
  } else if (lower.contains('android')) {
    os = 'Android';
  } else if (lower.contains('windows')) {
    os = 'Windows';
  } else if (lower.contains('macintosh') || lower.contains('mac os')) {
    os = 'macOS';
  } else if (lower.contains('linux')) {
    os = 'Linux';
  }

  if (os.isEmpty) return browser;
  if (browser == 'Web browser') return 'Browser on $os';
  return '$browser on $os';
}
