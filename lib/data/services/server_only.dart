import 'connectivity_service.dart';

/// Thrown instead of writing when an action has to be done on the server.
class ServerOnlyException implements Exception {
  const ServerOnlyException();

  @override
  String toString() =>
      'This needs an internet connection. It cannot be saved on this device.';
}

/// Server-enforced actions (approvals, orders, loan issuance and payments,
/// listing and program decisions, cooperative offers, broadcasts) are never
/// queued offline. The server checks the rules and the current stock, balance,
/// or status when the action is taken, so the decision has to be made then.
///
/// Each guarded repository method calls [ensureOnline] first, so an offline
/// attempt fails before anything is written or queued.
class ServerOnly {
  ServerOnly._();

  static Future<void> ensureOnline() async {
    if (!await ConnectivityService.instance.checkConnectivity()) {
      throw const ServerOnlyException();
    }
  }
}
