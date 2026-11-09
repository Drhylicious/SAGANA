import 'dart:io';

import 'package:flutter/services.dart';

/// Tests normally draw every letter as a solid block (the Ahem test font), so line
/// lengths and wrapping say nothing about a real phone. When a normal system font is on
/// the machine this registers it under the names SAGANA's text styles ask for (Inter and
/// Poppins, as google_fonts names them), so the text takes realistic room.
///
/// Segoe UI stands in for Inter and Poppins. It is close in width, a little narrower, so
/// the layout tests also run at a larger text scale as a margin. It is NOT the real font
/// and this is NOT a physical device. Returns false (and registers nothing) when no
/// stand-in font file is found, in which case the layout checks still run with Ahem.
Future<bool> loadStandInFonts() async {
  final candidates = <String>[
    'C:/Windows/Fonts',
    '/usr/share/fonts/truetype/dejavu',
    '/System/Library/Fonts/Supplemental',
  ];
  String? regular;
  String? bold;
  for (final dir in candidates) {
    final r = ['segoeui.ttf', 'DejaVuSans.ttf', 'Arial.ttf'].map((n) => '$dir/$n').firstWhere((p) => File(p).existsSync(), orElse: () => '');
    if (r.isEmpty) continue;
    regular = r;
    final b = ['segoeuib.ttf', 'DejaVuSans-Bold.ttf', 'Arial Bold.ttf'].map((n) => '$dir/$n').firstWhere((p) => File(p).existsSync(), orElse: () => r);
    bold = b;
    break;
  }
  if (regular == null || bold == null) return false;

  Future<void> register(String family, String path) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await loader.load();
  }

  for (final family in ['Inter', 'Poppins']) {
    await register('${family}_regular', regular);
    await register('${family}_500', regular);
    await register('${family}_600', bold);
    await register('${family}_700', bold);
  }
  return true;
}
