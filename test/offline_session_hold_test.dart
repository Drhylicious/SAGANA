// Offline session hold: an expired sign-in token must not hide saved pages
// while there is no connection, and the held session must never reach the
// server once the connection is back.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sagana/data/repositories/crop_repository.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/offline_read_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart' show mockConnectivityOnline;
import 'support/test_storage_mocks.dart';

String _jwt(String sub, DateTime expires) {
  String part(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': sub, 'role': 'authenticated', 'exp': expires.millisecondsSinceEpoch ~/ 1000})}.'
      'signature';
}

Map<String, Object?> _session(String token, String refresh) => {
  'access_token': token,
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': refresh,
  'user': {
    'id': 'u1',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'f@example.com',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-01-01T00:00:00Z',
  },
};

/// The network. Offline, every request fails the way a dropped connection does.
class _Net extends http.BaseClient {
  bool offline = false;
  List<Map<String, Object?>> rows = [];
  String nextToken = '';
  final List<String> restBearers = [];
  int refreshCalls = 0;
  int restCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw http.ClientException('offline', request.url);
    http.StreamedResponse json(Object? body) => http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
    final path = request.url.path;
    if (path.endsWith('/auth/v1/token')) {
      refreshCalls++;
      return json(_session(nextToken, 'r2'));
    }
    if (path.endsWith('/auth/v1/health')) return json({'ok': true});
    if (path.startsWith('/rest/v1/')) {
      restCalls++;
      restBearers.add(
        (request.headers['Authorization'] ?? request.headers['authorization'])!
            .split(' ')
            .last,
      );
      return json(rows);
    }
    return json(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final net = _Net();

  bool isHeld(String jwt) {
    final payload = jwt.split('.')[1];
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
            as Map;
    return claims['sagana_offline_hold'] == true;
  }

  setUpAll(() async {
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_session_hold');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    await HiveService.init();
    await HiveService.saveUserSession(
      userId: 'u1',
      email: 'f@example.com',
      role: 'farmer',
    );
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
      httpClient: OfflineReadClient(inner: net),
    );
  });

  test('saved pages still open offline after the sign-in token expired, '
      'and the held session is replaced before anything is sent', () async {
    final client = Supabase.instance.client;
    const hour = Duration(hours: 1);

    // Online with a valid token: the page loads and is saved.
    await client.auth.setInitialSession(
      jsonEncode(_session(_jwt('u1', DateTime.now().add(hour)), 'r1')),
    );
    net.rows = [
      {'id': 1},
    ];
    expect(await client.from('harvest_records').select(), [
      {'id': 1},
    ]);

    // The connection drops and the token runs out.
    net.offline = true;
    await client.auth.setInitialSession(
      jsonEncode(_session(_jwt('u1', DateTime.now().subtract(hour)), 'r1')),
    );
    final watch = Stopwatch()..start();
    expect(
      await client.from('harvest_records').select(),
      [
        {'id': 1},
      ],
      reason: 'the saved copy is shown',
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(isHeld(client.auth.currentSession!.accessToken), isTrue);

    // A page never opened before has nothing saved; a write is refused as a
    // connection failure (so the queueing code can keep it).
    await expectLater(
      client.from('expenses').select(),
      throwsA(isA<http.ClientException>()),
    );
    await expectLater(
      client.from('expenses').insert({'amount': 1}),
      throwsA(isA<http.ClientException>()),
    );

    // Back online: a real token is fetched first; the held one is never sent.
    net.offline = false;
    net.nextToken = _jwt('u1', DateTime.now().add(hour));
    net.rows = [
      {'id': 2},
    ];
    net.restBearers.clear();
    expect(await client.from('harvest_records').select(), [
      {'id': 2},
    ]);
    expect(net.refreshCalls, 1);
    expect(net.restBearers, [net.nextToken]);
    expect(net.restBearers.any(isHeld), isFalse);
    expect(isHeld(client.auth.currentSession!.accessToken), isFalse);
  });

  test(
    'offline, an approved crop from the saved Crop Roster can be picked '
    'for a new harvest (the approved list has no separate saved copy)',
    () async {
      Map<String, Object?> crop(String id, String name, String? masterId) => {
        'id': id,
        'farmer_id': 'u1',
        'crop_name': name,
        'category': 'Vegetable',
        'crop_master_id': masterId,
        'created_at': '2026-11-01T00:00:00Z',
        'harvest_records': [
          {'count': 0},
        ],
        'crop_requests': <Object?>[],
        'crop_master': masterId == null
            ? null
            : {'crop_type': 'public', 'exclusive_channel': null},
      };
      final repo = CropRepository();

      // Online, the Farmer only opens the Crop Roster.
      net.offline = false;
      net.rows = [crop('c1', 'Tomato', 'm1'), crop('c2', 'Okra', null)];
      expect((await repo.fetchCrops()).map((c) => c.cropName), [
        'Tomato',
        'Okra',
      ]);

      // Offline, Record New Harvest asks for the approved crops.
      net.offline = true;
      final approved = await repo.fetchCrops(approvedOnly: true);
      expect(approved.map((c) => c.cropName), ['Tomato']);
      expect(approved.single.isPendingApproval, isFalse);
      net.offline = false;
    },
  );

  test('a crop added offline shows in the roster and is usable for a harvest, '
      'then is sent once on sync', () async {
    final repo = CropRepository();
    net.offline = false;
    net.rows = [];
    await repo.fetchCrops(); // the roster is saved once
    net.offline = true;
    final added = await repo.addCrop(
      cropName: 'Ginger',
      category: 'Root & Spice Crop',
      cropMasterId: 'm9',
    );
    final offlineList = await repo.fetchCrops(approvedOnly: true);
    expect(offlineList.map((c) => c.id), [added.id]);
    expect(offlineList.single.isPendingApproval, isFalse);
    expect(
      HiveService.getOfflineActions().where(
        (a) => a.value['kind'] == 'crop_add',
      ),
      hasLength(1),
    );
    net.offline = false;
    for (final a in HiveService.getOfflineActions()) {
      await HiveService.removeOfflineAction(a.key);
    }
  });
}
