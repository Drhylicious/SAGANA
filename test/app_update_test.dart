import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/data/models/app_release_model.dart';
import 'package:sagana/data/services/app_update_service.dart';

AppRelease _release({int build = 5, int min = 1}) => AppRelease(
  versionName: '1.0.4',
  buildNumber: build,
  minSupportedBuild: min,
  landingUrl: AppConstants.updatePageUrl,
);

void main() {
  group('AppUpdateService.evaluate (build numbers, not version text)', () {
    test('same build is up to date', () {
      expect(
        AppUpdateService.evaluate(installedBuild: 5, release: _release()),
        AppUpdateKind.none,
      );
    });

    test('newer installed build than the release is up to date', () {
      expect(
        AppUpdateService.evaluate(installedBuild: 9, release: _release()),
        AppUpdateKind.none,
      );
    });

    test('older build with min_supported_build 1 is an optional update', () {
      expect(
        AppUpdateService.evaluate(installedBuild: 3, release: _release()),
        AppUpdateKind.optional,
      );
    });

    test('build below min_supported_build is a required update', () {
      expect(
        AppUpdateService.evaluate(
          installedBuild: 3,
          release: _release(build: 5, min: 4),
        ),
        AppUpdateKind.required,
      );
    });

    test('build equal to min_supported_build is still only optional', () {
      expect(
        AppUpdateService.evaluate(
          installedBuild: 4,
          release: _release(build: 5, min: 4),
        ),
        AppUpdateKind.optional,
      );
    });

    test('build 10 is newer than build 9 (numeric, not text, comparison)', () {
      expect(
        AppUpdateService.evaluate(
          installedBuild: 9,
          release: _release(build: 10),
        ),
        AppUpdateKind.optional,
      );
    });
  });

  group('optional-update reminder', () {
    final now = DateTime(2026, 11, 17, 12);
    test('shown when never dismissed', () {
      expect(AppUpdateService.shouldShowOptional(now: now), isTrue);
    });
    test('hidden while "Later" is still in effect', () {
      expect(
        AppUpdateService.shouldShowOptional(
          remindAt: now.add(const Duration(hours: 5)),
          now: now,
        ),
        isFalse,
      );
    });
    test('shown again once the reminder time has passed', () {
      expect(
        AppUpdateService.shouldShowOptional(
          remindAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('AppRelease.tryParse', () {
    test(
      'reads a full row and picks notes by language with English fallback',
      () {
        final r = AppRelease.tryParse({
          'version_name': '1.0.4',
          'build_number': 5,
          'min_supported_build': 2,
          'notes_en': 'Fixes.',
          'notes_tl': null,
          'landing_url': 'https://sagana-landing.vercel.app/get',
        })!;
        expect(r.buildNumber, 5);
        expect(r.minSupportedBuild, 2);
        expect(r.notesFor('en'), 'Fixes.');
        expect(r.notesFor('tl'), 'Fixes.');
      },
    );

    test('returns null for no release or an unusable row', () {
      expect(AppRelease.tryParse(null), isNull);
      expect(
        AppRelease.tryParse({'version_name': '1.0', 'build_number': 0}),
        isNull,
      );
      expect(AppRelease.tryParse({'build_number': 3}), isNull);
    });

    test(
      'only https addresses are opened; others fall back to the permanent page',
      () {
        expect(
          AppRelease.safeLandingUrl('http://evil.example/get'),
          AppConstants.updatePageUrl,
        );
        expect(
          AppRelease.safeLandingUrl('javascript:alert(1)'),
          AppConstants.updatePageUrl,
        );
        expect(AppRelease.safeLandingUrl(null), AppConstants.updatePageUrl);
        expect(
          AppRelease.safeLandingUrl('https://example.org/x'),
          'https://example.org/x',
        );
      },
    );
  });
}
