import 'dart:async';

/// Test sandboxes have no internet, and the app's text uses Google Fonts. The
/// font download fails in the background as an uncaught asynchronous error, and
/// Flutter's test framework fails whichever test is running, even though the
/// failure has nothing to do with what the test checks.
///
/// Runs [body] in its own error zone that ignores those font errors only.
/// Every other error, and every failed `expect`, still fails the test.
Future<void> runIgnoringFontErrors(Future<void> Function() body) {
  final done = Completer<void>();

  bool isFontNoise(Object error) {
    final text = error.toString();
    return text.contains('GoogleFonts') ||
        text.contains('google_fonts') ||
        text.contains('Failed to load font');
  }

  runZonedGuarded(
    () async {
      try {
        await body();
        if (!done.isCompleted) done.complete();
      } catch (e, st) {
        if (!done.isCompleted) done.completeError(e, st);
      }
    },
    (error, stack) {
      if (isFontNoise(error)) return;
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  return done.future;
}
