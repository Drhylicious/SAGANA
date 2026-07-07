import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/theme/app_theme.dart';

class _OverlayProbe extends StatefulWidget {
  const _OverlayProbe();

  @override
  State<_OverlayProbe> createState() => _OverlayProbeState();
}

class _OverlayProbeState extends State<_OverlayProbe> {
  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('applySystemOverlay can be called from initState safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const _OverlayProbe(),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
