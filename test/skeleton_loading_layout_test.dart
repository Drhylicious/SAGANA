import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/widgets/skeleton.dart';

void main() {
  // SkeletonList contains a LayoutBuilder, which cannot report intrinsic
  // dimensions. SliverFillRemaining(hasScrollBody: false) asks for them, so
  // that pairing throws in debug builds (and left the mouse tracker stuck,
  // flooding the log with mouse_tracker.dart:199). The loading state of the
  // Pending Applicant screen must use the default, which does not.
  testWidgets('a skeleton loading state lays out inside SliverFillRemaining', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: 64)),
              SliverFillRemaining(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SkeletonList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonList), findsOneWidget);
  });
}
