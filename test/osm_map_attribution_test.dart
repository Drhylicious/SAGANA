import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/constants/osm_config.dart';
import 'package:sagana/presentation/widgets/map_attribution_links.dart';

void main() {
  // The error reported a 288 x 152 map area. The label must fit in it without
  // a RenderFlex overflow.
  testWidgets('OSM attribution label fits a narrow map without overflow', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 288,
              height: 152,
              child: Stack(children: [OsmMapAttribution()]),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(kOsmAttribution), findsOneWidget);
  });
}
