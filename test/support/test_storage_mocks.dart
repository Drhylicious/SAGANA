import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only stand-ins for the device storage plugins that Supabase reads at
/// startup. Without them, Supabase.initialize never completes under the test
/// binding, and any test that starts the app hangs. The app itself is not
/// changed.
void mockStorageChannels() {
  void mock(String channel, Map<String, Object?> results) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(channel),
          (call) async => results[call.method] ?? results['*'],
        );
  }

  mock('plugins.flutter.io/path_provider', {'*': '/tmp/sagana_test'});
  mock('plugins.flutter.io/shared_preferences', {
    'getAll': <String, Object>{},
    '*': null,
  });
}
