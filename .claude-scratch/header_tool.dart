// Converts secondary-screen headers to SubPageTopBar.
// Handles two shapes: a glass header (ClipRect(... BackdropFilter ...)) that
// is replaced in place, and an AppBar whose body is wrapped in a Column.
// Anything it can't convert safely is reported and left for manual work.
import 'dart:io';

void main(List<String> args) {
  var changed = 0;
  for (final path in args) {
    final file = File(path);
    final original = file.readAsStringSync();
    final crlf = original.contains('\r\n');
    var text = original.replaceAll('\r\n', '\n');
    final report = <String>[];

    text = convertGlass(text, report);
    for (var i = 0; i < 4; i++) {
      text = convertAppBar(text, report);
    }
    text = convertRowHeader(text, report);

    if (text != original.replaceAll('\r\n', '\n')) {
      final out = crlf ? text.replaceAll('\n', '\r\n') : text;
      file.writeAsStringSync(out);
      changed++;
    }
    final status = report.isEmpty ? 'ok' : report.join('; ');
    stdout.writeln('$path: $status');
  }
  stdout.writeln('files changed: $changed');
}

// ─── Lexing helpers ────────────────────────────────────────────────────────

/// Index of the bracket that closes the one at [open], skipping strings and
/// comments. Returns -1 if unbalanced.
int matchClose(String s, int open) {
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      final nl = s.indexOf('\n', i);
      i = nl < 0 ? s.length : nl;
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
      continue;
    }
    if (c == "'" || c == '"') {
      i = _skipString(s, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

int _skipString(String s, int i) {
  final quote = s[i];
  // Raw strings ignore escapes; both are handled the same way here, which is
  // enough for the code in this app (raw strings aren't used near headers).
  var j = i + 1;
  while (j < s.length) {
    if (s[j] == '\\') {
      j += 2;
      continue;
    }
    if (s[j] == quote) return j + 1;
    if (s[j] == '\n') return j;
    j++;
  }
  return j;
}

/// Splits the arguments of a call at top-level commas.
List<String> splitArgs(String inner) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  var i = 0;
  while (i < inner.length) {
    final c = inner[i];
    if (c == '/' && i + 1 < inner.length && inner[i + 1] == '/') {
      final nl = inner.indexOf('\n', i);
      i = nl < 0 ? inner.length : nl;
      continue;
    }
    if (c == "'" || c == '"') {
      i = _skipString(inner, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      out.add(inner.substring(start, i).trim());
      start = i + 1;
    }
    i++;
  }
  final last = inner.substring(start).trim();
  if (last.isNotEmpty) out.add(last);
  return out.where((a) => a.isNotEmpty).toList();
}

/// Inner text of the call whose '(' is at [open].
String innerOf(String s, int open) {
  final close = matchClose(s, open);
  return s.substring(open + 1, close);
}

String _collapse(String v) => v.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The value after `name:` in an argument list, or null.
String? namedArg(String inner, String name) {
  for (final a in splitArgs(inner)) {
    if (a.startsWith('$name:')) return _collapse(a.substring(name.length + 1));
  }
  return null;
}

/// The first `Text(` call within [block]: its title argument.
String? firstTextTitle(String block) {
  final m = RegExp(r'(?<![A-Za-z_])Text\(').firstMatch(block);
  if (m == null) return null;
  final open = m.end - 1;
  final args = splitArgs(innerOf(block, open));
  if (args.isEmpty) return null;
  return _collapse(args.first);
}

// ─── Glass header ───────────────────────────────────────────────────────────

String convertGlass(String text, List<String> report) {
  final start = text.indexOf('ClipRect(');
  if (start < 0) return text;
  final open = start + 'ClipRect'.length;
  final close = matchClose(text, open);
  if (close < 0) return text;
  final block = text.substring(start, close + 1);
  if (!block.contains('BackdropFilter(') || !block.contains('SubPageBackButton(')) {
    return text;
  }

  // A lone IconButton on the right becomes the trailing action. Any other
  // icon-bearing widget means the header needs a manual pass.
  final iconButtons = RegExp(r'(?<![A-Za-z_])IconButton\(').allMatches(block).toList();
  final looseIcons = RegExp(r'(?<![A-Za-z_])Icon\(').allMatches(block).length;
  String? trailing;
  if (iconButtons.length > 1 || looseIcons > iconButtons.length) {
    report.add('glass header has several actions, skipped');
    return text;
  }
  if (iconButtons.length == 1) {
    final ibStart = iconButtons.first.start;
    final ibClose = matchClose(block, block.indexOf('(', ibStart));
    trailing = _collapse(block.substring(ibStart, ibClose + 1));
  }

  final backCall = block.indexOf('SubPageBackButton(');
  final back = namedArg(innerOf(block, block.indexOf('(', backCall)), 'onPressed');
  final title = firstTextTitle(block);
  if (back == null || title == null) {
    report.add('glass header missing back or title, skipped');
    return text;
  }
  final trailingArg = trailing == null ? '' : ', trailing: $trailing';
  final replacement = 'SubPageTopBar(title: $title, onBack: $back$trailingArg)';
  report.add('glass -> SubPageTopBar');
  return text.substring(0, start) + replacement + text.substring(close + 1);
}

// ─── Row header ─────────────────────────────────────────────────────────────
// A header built as a Row holding SubPageBackButton, wrapped by single-child
// containers. The outermost such wrapper is replaced in place.

const _wrapperNames = {
  'Padding', 'Container', 'SizedBox', 'WebSafeBlurContainer', 'SafeArea',
  'ClipRect', 'ClipRRect', 'DecoratedBox', 'Align', 'Center',
};

String convertRowHeader(String text, List<String> report) {
  final backAt = text.indexOf('SubPageBackButton(');
  if (backAt < 0) return text;
  final rowStarts = RegExp(r'(?<![A-Za-z_])Row\(')
      .allMatches(text.substring(0, backAt))
      .toList();
  if (rowStarts.isEmpty) return text;
  final rowName = rowStarts.last.start;
  final rowOpen = text.indexOf('(', rowName);
  final rowClose = matchClose(text, rowOpen);
  if (rowClose < backAt) return text;

  final enclosing = <({int start, int end, String name})>[];
  for (final c in RegExp(r'(?<![A-Za-z_])([A-Za-z_]\w*)\(').allMatches(text)) {
    if (c.start >= rowName) continue;
    final close = matchClose(text, c.end - 1);
    if (close > rowClose) {
      enclosing.add((start: c.start, end: close, name: c.group(1)!));
    }
  }
  enclosing.sort((a, b) => b.start.compareTo(a.start));

  ({int start, int end, String name})? outer;
  for (final e in enclosing) {
    if (_wrapperNames.contains(e.name)) {
      outer = e;
    } else {
      break;
    }
  }
  if (outer == null) {
    report.add('row header has no wrapper, skipped');
    return text;
  }

  final rowText = text.substring(rowName, rowClose + 1);
  final backCall = rowText.indexOf('SubPageBackButton(');
  final back = namedArg(innerOf(rowText, rowText.indexOf('(', backCall)), 'onPressed');
  final title = firstTextTitle(rowText);
  if (back == null || title == null) {
    report.add('row header missing back or title, skipped');
    return text;
  }
  final iconButtons = RegExp(r'(?<![A-Za-z_])IconButton\(').allMatches(rowText).toList();
  final looseIcons = RegExp(r'(?<![A-Za-z_])Icon\(').allMatches(rowText).length;
  if (iconButtons.length > 1 || looseIcons > iconButtons.length) {
    report.add('row header has several actions, skipped');
    return text;
  }
  String? trailing;
  if (iconButtons.length == 1) {
    final ib = iconButtons.first.start;
    final ibClose = matchClose(rowText, rowText.indexOf('(', ib));
    trailing = rowText.substring(ib, ibClose + 1).trim();
  }
  final trailingArg = trailing == null ? '' : ', trailing: $trailing';
  final replacement = 'SubPageTopBar(title: $title, onBack: $back$trailingArg)';
  report.add('row -> SubPageTopBar (${outer.name})');
  return text.substring(0, outer.start) + replacement + text.substring(outer.end + 1);
}

// ─── AppBar header ──────────────────────────────────────────────────────────

String convertAppBar(String text, List<String> report) {
  final at = text.indexOf('appBar: AppBar(');
  if (at < 0) return text;
  final appBarOpen = text.indexOf('(', at + 'appBar: AppBar'.length);
  final appBarClose = matchClose(text, appBarOpen);
  final appBarInner = text.substring(appBarOpen + 1, appBarClose);

  String? trailing;
  if (appBarInner.contains('actions:')) {
    final actions = namedArg(appBarInner, 'actions');
    if (actions == null || !actions.startsWith('[') || !actions.endsWith(']')) {
      report.add('appbar actions not understood, skipped');
      return text;
    }
    final items = splitArgs(actions.substring(1, actions.length - 1));
    if (items.length != 1) {
      report.add('appbar has several actions, skipped');
      return text;
    }
    if (items.first.startsWith('if ') || items.first.startsWith('if(')) {
      report.add('appbar conditional action, skipped');
      return text;
    }
    trailing = items.first.trim();
  }
  final titleArg = namedArg(appBarInner, 'title');
  if (titleArg != null && !titleArg.startsWith('Text(')) {
    report.add('appbar title not a plain Text, skipped');
    return text;
  }
  final titleValue = titleArg == null
      ? "''"
      : _collapse(splitArgs(
          titleArg.substring(titleArg.indexOf('(') + 1, titleArg.lastIndexOf(')')),
        ).first);

  final leading = namedArg(appBarInner, 'leading')?.replaceFirst('const ', '');
  String? back;
  if (leading == null) {
    back = '() => Navigator.of(context).pop()';
  } else if (leading.startsWith('BackButton')) {
    back = '() => Navigator.of(context).pop()';
  } else if (leading.startsWith('SubPageBackButton(')) {
    back = namedArg(innerOf(leading, leading.indexOf('(')), 'onPressed');
  } else if (leading.startsWith('IconButton')) {
    back = namedArg(innerOf(leading, leading.indexOf('(')), 'onPressed');
  } else if (leading.contains('GestureDetector(')) {
    final tap = RegExp(r'onTap:\s*([^,]+?),\s*child:').firstMatch(leading);
    back = tap == null ? null : _collapse(tap.group(1)!);
  }
  if (back == null) {
    report.add('appbar leading not understood, skipped');
    return text;
  }

  // Find the Scaffold that owns this AppBar: the nearest 'Scaffold(' before it.
  final scaffoldAt = text.lastIndexOf('Scaffold(', at);
  if (scaffoldAt < 0) {
    report.add('no Scaffold for appbar, skipped');
    return text;
  }
  final scaffoldOpen = scaffoldAt + 'Scaffold'.length;
  final scaffoldClose = matchClose(text, scaffoldOpen);

  // Remove the appBar argument (with its trailing comma and line break).
  var removeEnd = appBarClose + 1;
  if (removeEnd < text.length && text[removeEnd] == ',') removeEnd++;
  var removeStart = at;
  while (removeStart > 0 && (text[removeStart - 1] == ' ')) {
    removeStart--;
  }
  if (removeStart > 0 && text[removeStart - 1] == '\n') {
    // drop the whole line
  } else {
    removeStart = at;
  }
  var edited = text.substring(0, removeStart) + text.substring(removeEnd);

  // Re-find the Scaffold after the removal and wrap its body.
  final sAt = edited.lastIndexOf('Scaffold(', removeStart);
  final sOpen = sAt + 'Scaffold'.length;
  final sClose = matchClose(edited, sOpen);
  final sInner = edited.substring(sOpen + 1, sClose);
  final bodyMatch = RegExp(r'(?:^|\n)(\s*)body:\s*').firstMatch(sInner);
  if (bodyMatch == null) {
    report.add('scaffold has no body, skipped');
    return text;
  }
  // Body value runs to the next top-level comma of the Scaffold argument list.
  final valueStart = sOpen + 1 + bodyMatch.end;
  var depth = 0;
  var k = valueStart;
  var end = -1;
  while (k < sClose) {
    final c = edited[k];
    if (c == "'" || c == '"') {
      k = _skipString(edited, k);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      end = k;
      break;
    }
    k++;
  }
  if (end < 0) end = sClose;
  final bodyValue = edited.substring(valueStart, end).trim();
  final trailingArg = trailing == null ? '' : ', trailing: $trailing';
  final wrapped = 'Column(\n'
      '        children: [\n'
      '          SubPageTopBar(title: $titleValue, onBack: $back$trailingArg),\n'
      '          Expanded(child: $bodyValue),\n'
      '        ],\n'
      '      )';
  edited = edited.substring(0, valueStart) + wrapped + edited.substring(end);

  report.add('appbar -> SubPageTopBar + Column body');
  return edited;
}
