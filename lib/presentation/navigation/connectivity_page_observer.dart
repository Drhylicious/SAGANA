import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Screens opened with Navigator.push rather than a GoRouter route.
enum ConnectivityPage {
  farmMap,
  addressMap,
  cooperativeMap,
  deliveryMap,
  distributionYear,
}

/// Supplements GoRouter's active leaf with the app's plain page routes.
/// Dialogs and sheets keep the description of the page underneath them.
class ConnectivityPageObserver extends NavigatorObserver {
  final currentPage = ValueNotifier<ConnectivityPage?>(null);
  final _pages = <Route<dynamic>>[];
  bool _disposed = false;

  void _publish() {
    // Navigator can report page changes while it is building. Notify the
    // ancestor overlay after that frame, without changing the navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final name = _pages.isEmpty ? null : _pages.last.settings.name;
      ConnectivityPage? page;
      for (final candidate in ConnectivityPage.values) {
        if (name == candidate.name) {
          page = candidate;
          break;
        }
      }
      currentPage.value = page;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _pages.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (index >= 0) {
      _pages.removeAt(index);
      if (newRoute is PageRoute) _pages.insert(index, newRoute);
    } else if (newRoute is PageRoute) {
      _pages.add(newRoute);
    }
    _publish();
  }

  void dispose() {
    _disposed = true;
    currentPage.dispose();
    _pages.clear();
  }
}
