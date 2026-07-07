/// AppEventService — lightweight in-process event bus.
///
/// Used to notify listening screens when a significant action occurs
/// so they can refresh their data without requiring a full Navigator
/// rebuild or a shared state management solution.
///
/// Usage — emit:
///   AppEventService.instance.notifyHarvestRecorded();
///   AppEventService.instance.notify();          // generic alias
///
/// Usage — listen (add in initState, remove in dispose):
///   AppEventService.instance.addListener(_onHarvestRecorded);
///   AppEventService.instance.removeListener(_onHarvestRecorded);

class AppEventService {
  AppEventService._();

  static final AppEventService instance = AppEventService._();

  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Notify all registered listeners (generic).
  void notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  /// Named alias — called after a harvest record is successfully saved.
  /// Triggers dashboard and other screens to refresh their data.
  void notifyHarvestRecorded() => notify();
}
