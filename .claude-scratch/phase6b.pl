use utf8;
use strict;
use warnings;

my $file = 'lib/data/services/hive_service.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

sub rep {
    my ($re, $to, $expect, $label) = @_;
    my $n = () = $t =~ /$re/g;
    die "$label: expected $expect, got $n\n" unless $n == $expect;
    $t =~ s/$re/$to/g;
}

# Stamp every new record with its creator.
rep(qr/    await _loanQueueBox\.put\(localId, payload\);\n/, "    await _loanQueueBox.put(localId, _owned(payload));\n", 2, 'loan saves');
rep(qr/    await _harvestQueueBox\.put\(localId, payload\);\n/, "    await _harvestQueueBox.put(localId, _owned(payload));\n", 1, 'harvest save');
rep(qr/    await _expenseQueueBox\.put\(localId, payload\);\n/, "    await _expenseQueueBox.put(localId, _owned(payload));\n", 1, 'expense save');

# Readers return only the signed-in user's records.
rep(qr/(  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingHarvests\(\) \{\n).*?\n  \}\n/s,
    "$1    return _ownedEntries(_harvestQueueBox);\n  }\n", 1, 'getPendingHarvests');
rep(qr/(  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingExpenses\(\) \{\n).*?\n  \}\n/s,
    "$1    return _ownedEntries(_expenseQueueBox);\n  }\n", 1, 'getPendingExpenses');
rep(qr/(  static List<MapEntry<String, Map<dynamic, dynamic>>> _getPendingByPrefix\(\n    String prefix,\n  \) \{\n).*?\n  \}\n/s,
    "$1    return _ownedEntries(_loanQueueBox)\n        .where((entry) => entry.key.startsWith(prefix))\n        .toList();\n  }\n", 1, '_getPendingByPrefix');

# Counts follow the same rule.
rep(qr/static int getPendingHarvestCount\(\) => _harvestQueueBox\.length;/, 'static int getPendingHarvestCount() => getPendingHarvests().length;', 1, 'harvest count');
rep(qr/static int getPendingExpenseCount\(\) => _expenseQueueBox\.length;/, 'static int getPendingExpenseCount() => getPendingExpenses().length;', 1, 'expense count');
rep(qr/static int getUnsyncedCount\(\) =>\n      _harvestQueueBox\.length \+ _expenseQueueBox\.length;/, "static int getUnsyncedCount() =>\n      getPendingHarvestCount() + getPendingExpenseCount();", 1, 'unsynced count');

# Ownership helpers, placed before the loan queue removal function.
my $helpers = <<'DART';
  // ─── Record ownership ───────────────────────────────────────────────────────
  // Every queued record is stamped with the user who created it. Reads, counts,
  // and sync only return the signed-in user's records, so another user on the
  // same device sees none of them. Records written before ownership existed
  // belong to the last user who signed out, or to the first user to sign in
  // when no earlier user is recorded.

  static const String _ownerKey = '_owner_id';

  static String? _legacyOwnerId() => _userBox.get('last_user_id') as String?;

  static Map<String, dynamic> _owned(Map<String, dynamic> payload) {
    final owner = getUserId();
    if (owner == null) {
      throw StateError('Sign in before saving offline records.');
    }
    return {...payload, _ownerKey: owner};
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> _ownedEntries(Box box) {
    final me = getUserId();
    if (me == null) return const [];
    final result = <MapEntry<String, Map<dynamic, dynamic>>>[];
    for (final key in box.keys) {
      final value = Map<dynamic, dynamic>.from(box.get(key) as Map);
      final owner = (value[_ownerKey] as String?) ?? _legacyOwnerId();
      if (owner != me) continue;
      value.remove(_ownerKey);
      result.add(MapEntry(key as String, value));
    }
    return result;
  }

DART
my $anchor = "  static Future<void> removePendingQueueItem(String localId) async {";
my $an = () = $t =~ /\Q$anchor\E/g;
die "anchor: $an\n" unless $an == 1;
$t =~ s/\Q$anchor\E/$helpers$anchor/;

# Record which user last signed out, so their queued records stay theirs.
rep(qr/(    await _userBox\.put\(AppConstants\.hiveKeyUserId, userId\);\n)/,
    "$1    if (_userBox.get('last_user_id') == null) {\n      await _userBox.put('last_user_id', userId);\n    }\n", 1, 'saveUserSession');
rep(qr/(  static Future<void> clearUserSession\(\) async \{\n)/,
    "$1    final signingOut = getUserId();\n    if (signingOut != null) {\n      await _userBox.put('last_user_id', signingOut);\n    }\n", 1, 'clearUserSession');

$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "record ownership applied\n";
