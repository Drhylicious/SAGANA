// One-off: removes the listed keys (and their "@key" metadata) from an ARB file,
// keeping every other line byte-for-byte. Verifies the result is valid JSON.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final arbPath = args[0];
  final keys = File(args[1])
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toSet();

  final lines = File(arbPath).readAsLinesSync();
  final entry = RegExp(r'^  "(@?)([A-Za-z0-9_]+)":');
  final out = <String>[];
  var removed = 0;

  int netBraces(String s) {
    var depth = 0;
    var inString = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      }
    }
    return depth;
  }

  var i = 0;
  while (i < lines.length) {
    final m = entry.firstMatch(lines[i]);
    if (m != null && keys.contains(m.group(2))) {
      var depth = netBraces(lines[i]);
      i++;
      while (depth > 0 && i < lines.length) {
        depth += netBraces(lines[i]);
        i++;
      }
      removed++;
      continue;
    }
    out.add(lines[i]);
    i++;
  }

  // If the final entry was removed, the new last entry must not end in a comma.
  for (var j = out.length - 1; j >= 0; j--) {
    final t = out[j].trimRight();
    if (t == '}' || t.isEmpty) continue;
    if (t.endsWith(',')) out[j] = t.substring(0, t.length - 1);
    break;
  }

  final text = '${out.join('\n')}\n';
  jsonDecode(text); // throws if the file is no longer valid JSON
  File(arbPath).writeAsStringSync(text);
  stdout.writeln('$arbPath: removed $removed entries');
}
