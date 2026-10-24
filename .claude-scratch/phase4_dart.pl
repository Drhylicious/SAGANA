use utf8;
use strict;
use warnings;

my $file = 'lib/data/repositories/balik_tangkilik_repository.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my $re = qr/    \/\/ Notification delivery is best-effort, unlike the write above.*?      await NotificationRepository\(\)\.createNotifications\(notifDrafts\);\n    \} catch \(_\) \{\}\n/s;
my $n = () = $t =~ /$re/g;
die "notice block: expected 1, got $n\n" unless $n == 1;
$t =~ s/$re/    \/\/ The farmer's payout notice is written by the database\n    \/\/ (trg_notify_balik_distributed) when the payout date is set above.\n/;

$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "removed device payout notice\n";
