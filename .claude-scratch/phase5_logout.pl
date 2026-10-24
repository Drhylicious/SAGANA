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

my $from = "    await _userBox.delete('pending_acknowledgement');\n  }\n";
my $n = () = $t =~ /\Q$from\E/g;
die "logout block: expected 1, got $n\n" unless $n == 1;
my $to = "    await _userBox.delete('pending_acknowledgement');\n"
       . "    // Per-user caches: cleared on logout. Unsynced queues are not touched here.\n"
       . "    await (await EncryptedBox.open(AppConstants.hiveBoxCart)).clear();\n"
       . "    await (await EncryptedBox.open(AppConstants.hiveBoxExportHistory)).clear();\n"
       . "  }\n";
$t =~ s/\Q$from\E/$to/;

$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "logout clears per-user caches\n";
