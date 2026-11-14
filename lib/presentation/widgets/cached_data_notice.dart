import 'package:flutter/widgets.dart';

/// Compatibility for existing screen call sites. Connectivity and saved-data
/// explanations now belong to ConnectivityOverlay, never the page layout.
/// This widget does not change caching, refresh, or synchronization behavior.
class CachedDataNotice extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
