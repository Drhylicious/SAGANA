import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

/// One request the app sent to Supabase.
class RecordedRequest {
  RecordedRequest(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final String body;

  String get path => url.path;

  /// 'GET /rest/v1/account_creation_requests'
  String get key => '$method $path';

  Object? get json => body.isEmpty ? null : jsonDecode(body);

  Map<String, dynamic> get jsonMap =>
      Map<String, dynamic>.from((json as Map?) ?? const {});

  @override
  String toString() => '$key ${url.query} $body';
}

/// A non-success answer, shaped like PostgREST's error body.
class FakeError {
  const FakeError(this.status, this.message, {this.code = 'P0001'});

  final int status;
  final String message;
  final String code;
}

/// Stands in for the network under supabase_flutter, so the REAL repositories,
/// services and screens run and the test can read exactly what they sent.
/// Pass it to `Supabase.initialize(httpClient: ...)`.
///
/// Routes are matched on 'METHOD /path'. A handler returns the JSON body (a
/// Map, List, bool, String...) or a [FakeError]. Unmatched calls get `[]` for
/// reads and `null` for writes.
class FakeSupabaseHttp extends http.BaseClient {
  final List<RecordedRequest> requests = [];
  final Map<String, Object? Function(RecordedRequest)> routes = {};

  void on(String key, Object? Function(RecordedRequest) handler) =>
      routes[key] = handler;

  /// Every recorded request whose key starts with [key].
  List<RecordedRequest> calls(String key) =>
      requests.where((r) => r.key.startsWith(key)).toList();

  void reset() {
    requests.clear();
    routes.clear();
    _installDefaults();
  }

  FakeSupabaseHttp() {
    _installDefaults();
  }

  void _installDefaults() {
    // The reachability probe behind ConnectivityService and ServerOnly.
    on('POST /rest/v1/rpc/ping', (_) => true);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final rec = RecordedRequest(request.method, request.url, body);
    requests.add(rec);

    Object? result;
    final handler = routes[rec.key];
    if (handler != null) {
      result = handler(rec);
    } else {
      result = request.method == 'GET' ? <Object?>[] : null;
    }

    var status = 200;
    Object? payload = result;
    if (result is FakeError) {
      status = result.status;
      payload = {
        'code': result.code,
        'message': result.message,
        'details': null,
        'hint': null,
      };
    }
    final bytes = utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      contentLength: bytes.length,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

/// Makes `ConnectivityService.checkConnectivity()` report Wi-Fi.
void mockConnectivityOnline() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? 'wifi' : null,
      );
}
