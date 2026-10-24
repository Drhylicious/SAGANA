use utf8;
use strict;
use warnings;

sub edit_regex {
    my ($file, $re, $to, $label) = @_;
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $t = do { local $/; <$in> };
    close($in);
    my $crlf = $t =~ /\r\n/ ? 1 : 0;
    $t =~ s/\r\n/\n/g;
    my $n = () = $t =~ /$re/g;
    die "$label: expected 1 match, got $n\n" unless $n == 1;
    $t =~ s/$re/$to/;
    $t =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "edited $label\n";
}

# 1. Reference price notice: device insert → RPC call.
edit_regex('lib/data/repositories/price_management_repository.dart',
    qr/    try \{\n      \/\/ Fetch all active farmer AND active buyer.*?      await NotificationRepository\(\)\.createNotifications\(notifDrafts\);\n    \} catch \(_\) \{\n      \/\/ Notification failure is non-fatal — price was already saved\n    \}\n/s,
    "    // The notices are written by the database (notify_price_update), so they\n    // don't depend on the device's permissions. A failure here does not undo the\n    // saved price, but it is logged instead of being silently ignored.\n    try {\n      await _client.rpc(\n        'notify_price_update',\n        params: {\n          'p_crop_name': cropName,\n          'p_new_price': newPrice,\n          'p_unit': unit,\n        },\n      );\n    } catch (e) {\n      debugPrint('PriceManagementRepository.broadcastPriceNotification failed: \$e');\n    }\n",
    'price_management_repository.dart broadcastPriceNotification');

# 2. Capital contribution notice: removed; the database trigger now sends it.
edit_regex('lib/data/repositories/capital_contribution_repository.dart',
    qr/    try \{\n      await NotificationRepository\(\)\.createNotification\(\n.*?    \} catch \(_\) \{\n      \/\/ Notification failure is non-fatal — the contribution was already recorded\.\n    \}\n/s,
    "",
    'capital_contribution_repository.dart notice');
