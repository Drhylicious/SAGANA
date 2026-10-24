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
  [ "  bool _isSending  = false;\n",
    "  bool _isSending  = false;\n  // Kept across retries of the same send attempt so a repeated request is not sent twice.\n  String? _pendingSendKey;\n" ],

  [ "    setState(() => _isSending = true);\n    try {\n      final count = await _repo.sendBroadcast(\n        title:           title,",
    "    setState(() => _isSending = true);\n    _pendingSendKey ??= BroadcastRepository.newClientKey();\n    try {\n      final count = await _repo.sendBroadcast(\n        clientKey:       _pendingSendKey,\n        title:           title," ],

  [ "      if (!mounted) return;\n      setState(() => _isSending = false);\n\n      final recipientNoun",
    "      if (!mounted) return;\n      _pendingSendKey = null;\n      setState(() => _isSending = false);\n\n      final recipientNoun" ],

  [ "    } catch (e) {\n      debugPrint('NotificationBroadcastScreen._send failed: \$e');\n      setState(() => _isSending = false);\n      _showSnack(l10n.broadcastSendFailed);\n    }",
    "    } on BroadcastNoRecipientsException {\n      // Nothing matched, so nothing was sent. Clear the key: the next attempt is new.\n      _pendingSendKey = null;\n      setState(() => _isSending = false);\n      _showSnack(l10n.broadcastNoRecipients);\n    } catch (e) {\n      debugPrint('NotificationBroadcastScreen._send failed: \$e');\n      setState(() => _isSending = false);\n      _showSnack(l10n.broadcastSendFailed);\n    }" ],
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
print "updated screen\n";

# Localized copy for the no-recipients case (English and Tagalog).
for my $pair ([ 'lib/core/l10n/app_en.arb', 'Nothing was sent. No recipients match this selection.' ],
              [ 'lib/core/l10n/app_tl.arb', 'Walang naipadala. Walang tatanggap na tumutugma sa pinili.' ]) {
    my ($arb, $text) = @$pair;
    my $ai;
    open($ai, '<:encoding(UTF-8)', $arb) or die "$arb: $!";
    my $a = do { local $/; <$ai> };
    close($ai);
    $a =~ s/\r\n/\n/g;
    $a =~ s/\s*\}\s*\z//;
    $a .= ",\n  \"broadcastNoRecipients\": \"$text\"\n}\n";
    my $ao;
    open($ao, '>:encoding(UTF-8)', $arb) or die "$arb: $!";
    print {$ao} $a;
    close($ao);
    print "appended to $arb\n";
}
