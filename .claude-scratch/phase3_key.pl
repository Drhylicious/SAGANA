use utf8;
use strict;
use warnings;

my $file = 'lib/presentation/screens/admin/notification_broadcast_screen.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my @swaps = (
  [ "  String? _pendingSendKey;\n",
    "  String? _pendingSendKey;\n  String? _pendingSendFingerprint;\n" ],
  [ "    _pendingSendKey ??= BroadcastRepository.newClientKey();\n",
    "    // A changed message or audience is a new send, so it gets a new key.\n    final fingerprint = '\$title|\$body|\${_category.value}|\${_recipientType.value}|\$_currentRecipientFilter|\${_scheduleEnabled ? _scheduledAt : null}';\n    if (_pendingSendKey == null || _pendingSendFingerprint != fingerprint) {\n      _pendingSendKey = BroadcastRepository.newClientKey();\n      _pendingSendFingerprint = fingerprint;\n    }\n" ],
);
for my $s (@swaps) {
    my ($from, $to) = @$s;
    my $n = () = $t =~ /\Q$from\E/g;
    die "expected 1 match, got $n for: " . substr($from, 0, 60) . "\n" unless $n == 1;
    $t =~ s/\Q$from\E/$to/;
}
$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "updated key handling\n";
