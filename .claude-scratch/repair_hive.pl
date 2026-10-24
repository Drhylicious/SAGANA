use strict;
use warnings;

my $file = 'lib/data/services/hive_service.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my @fixes = (
  [ "    if (_userBox.get('last_user_id') == null) {\n",
    "    await _userBox.put(AppConstants.hiveKeyUserId, userId);\n" ],
  [ "    final signingOut = getUserId();\n",
    "  static Future<void> clearUserSession() async {\n" ],
  [ "    return _ownedEntries(_loanQueueBox)\n",
    "  static List<MapEntry<String, Map<dynamic, dynamic>>> _getPendingByPrefix(\n    String prefix,\n  ) {\n" ],
  [ "    return _ownedEntries(_harvestQueueBox);\n",
    "  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingHarvests() {\n" ],
  [ "    return _ownedEntries(_expenseQueueBox);\n",
    "  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingExpenses() {\n" ],
);
for my $f (@fixes) {
    my ($anchor, $insert) = @$f;
    my $n = () = $t =~ /\Q$anchor\E/g;
    die "anchor count $n for: " . substr($anchor, 0, 50) . "\n" unless $n == 1;
    my $pos = index($t, $anchor);
    substr($t, $pos, 0) = $insert;
}

$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "repaired\n";
