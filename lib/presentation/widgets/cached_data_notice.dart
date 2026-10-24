import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_utils.dart';
import '../../data/services/offline_cache.dart';
import 'shared_widgets.dart';

/// Notice for a list screen that can show saved data.
///
/// When the screen is showing its saved snapshot, it says when that was
/// saved. When the device is offline and there is no snapshot, it shows
/// [offlineMessage] instead. Otherwise it shows nothing.
///
/// A screen that loads more than one data set passes the others in
/// [otherScreens]. The notice then counts all of them: it shows once, and
/// the time it gives is the oldest saved snapshot among those served.
class CachedDataNotice extends StatelessWidget {
  /// The OfflineCache screen key the list was loaded with.
  final String screen;
  final List<String> otherScreens;
  final bool isOnline;
  final String offlineMessage;

  const CachedDataNotice({
    super.key,
    required this.screen,
    this.otherScreens = const [],
    required this.isOnline,
    required this.offlineMessage,
  });

  @override
  Widget build(BuildContext context) {
    final served = [
      screen,
      ...otherScreens,
    ].where(OfflineCache.servedFromCache).toList();
    if (served.isNotEmpty) {
      final l10n = AppLocalizations.of(context);
      final savedTimes =
          served.map(OfflineCache.savedAt).whereType<DateTime>().toList()
            ..sort();
      final when = savedTimes.isEmpty
          ? ''
          : AppUtils.formatRelativeTime(savedTimes.first, l10n);
      return OfflineStatusCard(
        message: l10n.offlineCachedNotice(when),
        showWhenOnline: true,
      );
    }
    if (!isOnline) return OfflineStatusCard(message: offlineMessage);
    return const SizedBox.shrink();
  }
}
