import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/services/report_download_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';

String _read(String path) => File(path).readAsStringSync();

/// The Dart half of "Download saves straight to Downloads": the platform
/// channel, how failures surface, and that Download never opens the share
/// sheet. The Android half (MediaStore) is checked by reading its source here
/// and by a debug build; saving on a real phone needs a physical device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel(Future<Object?>? Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(ReportDownloadService.channel, handler);
  }

  tearDown(() {
    mockChannel(null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('ReportDownloadService', () {
    test('asks the Android side to copy the private file and returns the '
        'name it was saved under', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? seen;
      mockChannel((call) async {
        seen = call;
        return 'SAGANA_Sales_Report_This_Month_20261102_101500 (1).pdf';
      });

      final name = await ReportDownloadService().save('/data/app/report.pdf');

      expect(seen!.method, 'saveReport');
      expect(seen!.arguments, {'sourcePath': '/data/app/report.pdf'});
      // Android may rename to avoid a clash; the caller shows that real name.
      expect(name, endsWith('(1).pdf'));
    });

    test('passes the failure code through, so the screen can explain it',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final code in ['permission_denied', 'file_missing', 'save_failed']) {
        mockChannel((call) async => throw PlatformException(code: code));
        await expectLater(
          ReportDownloadService().save('/x.pdf'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
          reason: code,
        );
      }
    });

    test('an empty answer is a failure, never a success message', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockChannel((call) async => null);
      await expectLater(
        ReportDownloadService().save('/x.pdf'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'save_failed'),
        ),
      );
    });

    test('a build without the native handler reports "unsupported"', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockChannel(null); // no handler registered -> MissingPluginException
      await expectLater(
        ReportDownloadService().save('/x.pdf'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'unsupported_platform',
          ),
        ),
      );
    });

    test('other platforms are unsupported and never reach the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var called = false;
      mockChannel((call) async {
        called = true;
        return 'x.pdf';
      });
      await expectLater(
        ReportDownloadService().save('/x.pdf'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'unsupported_platform',
          ),
        ),
      );
      expect(called, isFalse);
    });
  });

  group('Export Center: Download and Share are separate', () {
    final src = _read('lib/presentation/screens/admin/export_center_screen.dart');

    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, greaterThan(0), reason: signature);
      final end = src.indexOf('\n  }\n', start);
      return src.substring(start, end);
    }

    test('generating never opens the share sheet', () {
      expect(body('Future<void> _generate()'), isNot(contains('Share.')));
      expect(body('Future<void> _download('), isNot(contains('Share.')));
    });

    test('only the Share actions open the share sheet', () {
      expect(body('Future<void> _shareLastExport()'), contains('Share.shareXFiles'));
      expect(body('Future<void> _reshare('), contains('Share.shareXFiles'));
      // Exactly two places, both behind a Share button.
      expect('Share.shareXFiles'.allMatches(src).length, 2);
    });

    test('success is only reported after the file was saved', () {
      final download = body('Future<void> _download(');
      expect(
        download.indexOf('_downloadService.save'),
        lessThan(download.indexOf('PostActionFeedback.success')),
      );
      // Permission, missing file, unsupported platform and storage errors each
      // have their own message.
      for (final key in [
        'exportDownloadPermissionDenied',
        'exportFileMissing',
        'exportDownloadUnsupported',
        'exportDownloadError',
      ]) {
        expect(download, contains(key), reason: key);
      }
    });

    test('every action respects the Officer\'s Reports access', () {
      for (final sig in [
        'Future<void> _generate()',
        'Future<void> _download(',
        'Future<void> _shareLastExport()',
        'Future<void> _reshare(',
      ]) {
        expect(body(sig), contains('StaffModule.reports'), reason: sig);
      }
      expect(src, contains('ViewOnlyStrip(module: StaffModule.reports)'));
      // Nothing is Manager-only: access comes from the shared permission check.
      expect(src, isNot(contains("getUserRole() == 'admin'")));
      expect(src, isNot(contains('isOfficer')));
    });
  });

  group('Reports access', () {
    tearDown(() => StaffPermissions.instance.debugSet(const {}));

    test('an Officer with Reports Manage can export; View Only cannot', () {
      StaffPermissions.instance.debugSet({
        StaffModule.reports: StaffAccess.manage,
      });
      expect(StaffPermissions.instance.canManage(StaffModule.reports), isTrue);

      StaffPermissions.instance.debugSet({
        StaffModule.reports: StaffAccess.view,
      });
      expect(StaffPermissions.instance.canManage(StaffModule.reports), isFalse);

      // Unknown access falls back to View Only, never Manage.
      StaffPermissions.instance.debugSet(const {});
      expect(StaffPermissions.instance.canManage(StaffModule.reports), isFalse);
    });
  });

  group('Android side (source checks)', () {
    const dir = 'android/app/src/main/kotlin/com/sp3cooperative/sagana';
    final store = _read('$dir/ReportDownloadsStore.kt');
    final channel = _read('$dir/ReportDownloadsChannel.kt');
    final activity = _read('$dir/MainActivity.kt');
    final manifest = _read('android/app/src/main/AndroidManifest.xml');

    test('the channel name is the same in Dart and Kotlin', () {
      expect(
        ReportDownloadService.channel.name,
        'com.sp3cooperative.sagana/downloads',
      );
      expect(channel, contains('"com.sp3cooperative.sagana/downloads"'));
      expect(channel, contains('"saveReport"'));
      expect(activity, contains('ReportDownloadsChannel('));
    });

    test('Android 10+ saves through MediaStore with no storage permission', () {
      expect(store, contains('MediaStore.Downloads.EXTERNAL_CONTENT_URI'));
      expect(store, contains('RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS'));
      // The file is hidden from other apps until it is complete, and removed
      // again if copying fails.
      expect(store, contains('IS_PENDING'));
      expect(store, contains('resolver.delete(uri'));
    });

    test('an earlier download is never overwritten', () {
      // Android 10+: a fresh insert gets a unique name. Older Android: the
      // name is reserved atomically and a number is added until it is free.
      expect(store, contains('resolver.insert('));
      expect(store, contains('createNewFile()'));
      expect(store, contains('suffix++'));
    });

    test('only the app\'s own PDF and CSV files can be copied out', () {
      expect(store, contains('Report must be app-owned'));
      expect(store, contains('"application/pdf"'));
      expect(store, contains('"text/csv"'));
    });

    test('older Android asks for write permission only when needed', () {
      expect(
        manifest,
        matches(
          RegExp(
            r'WRITE_EXTERNAL_STORAGE"\s+android:maxSdkVersion="28"',
          ),
        ),
      );
      expect(channel, contains('Build.VERSION.SDK_INT in 23..28'));
      // No share intent anywhere in the native download code.
      expect(channel + store, isNot(contains('ACTION_SEND')));
      expect(channel + store, isNot(contains('createChooser')));
    });
  });
}
