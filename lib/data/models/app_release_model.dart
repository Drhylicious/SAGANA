import '../../core/constants/app_constants.dart';

/// The newest published SAGANA build, as returned by `latest_app_release()`.
class AppRelease {
  final String versionName;
  final int buildNumber;

  /// Apps with a build number below this must update before they can be used.
  final int minSupportedBuild;
  final String? notesEn;
  final String? notesTl;
  final String landingUrl;

  const AppRelease({
    required this.versionName,
    required this.buildNumber,
    required this.minSupportedBuild,
    this.notesEn,
    this.notesTl,
    required this.landingUrl,
  });

  /// Null when the row is missing the fields the comparison needs.
  static AppRelease? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final build = (raw['build_number'] as num?)?.toInt();
    final version = (raw['version_name'] as String?)?.trim();
    if (build == null || build <= 0 || version == null || version.isEmpty) {
      return null;
    }
    final min = (raw['min_supported_build'] as num?)?.toInt() ?? 1;
    return AppRelease(
      versionName: version,
      buildNumber: build,
      minSupportedBuild: min,
      notesEn: _clean(raw['notes_en']),
      notesTl: _clean(raw['notes_tl']),
      landingUrl: safeLandingUrl(raw['landing_url']),
    );
  }

  /// "What's new" in the reader's language, falling back to English.
  String? notesFor(String languageCode) =>
      languageCode == 'tl' ? (notesTl ?? notesEn) : (notesEn ?? notesTl);

  /// Only an https address is ever opened; anything else falls back to the
  /// permanent download page.
  static String safeLandingUrl(Object? raw) {
    final text = raw is String ? raw.trim() : '';
    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return text;
    }
    return AppConstants.updatePageUrl;
  }

  static String? _clean(Object? v) {
    final s = v is String ? v.trim() : '';
    return s.isEmpty ? null : s;
  }
}
