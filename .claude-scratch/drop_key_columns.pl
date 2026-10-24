use strict;
use warnings;

sub edit {
    my ($file, $pairs) = @_;
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $t = do { local $/; <$in> };
    close($in);
    my $crlf = $t =~ /\r\n/ ? 1 : 0;
    $t =~ s/\r\n/\n/g;
    for my $p (@$pairs) {
        my ($from, $to) = @$p;
        my $n = () = $t =~ /\Q$from\E/g;
        die "$file: expected 1 match, got $n for: " . substr($from, 0, 60) . "\n" unless $n == 1;
        $t =~ s/\Q$from\E/$to/;
    }
    $t =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "edited $file\n";
}

edit('lib/data/repositories/admin_activity_repository.dart', [
    [ "'id, admin_id, module, description, message_key, message_params, reference_id, created_at',",
      "'id, admin_id, module, description, reference_id, created_at',", ],
    [ "      try {\n        await _client.from('admin_activity_log').insert({\n          ...row,\n          'message_key': message.key,\n          'message_params': message.params,\n        });\n      } catch (_) {\n        // Migration not applied yet (message_key/message_params missing):\n        // keep the entry with its English description rather than drop it.\n        await _client.from('admin_activity_log').insert(row);\n      }\n",
      "      await _client.from('admin_activity_log').insert(row);\n", ],
]);

edit('lib/data/models/activity_text.dart', [
    [ "/// Columns every activity writer inserts: the English copy for the legacy\n/// `description` column plus the key and parameters.\nMap<String, Object?> activityRowFields(AdminLogMessage m) => {\n      'description': activityEnglish(m),\n      'message_key': m.key,\n      'message_params': m.params,\n    };",
      "/// Columns every activity writer inserts. Only the English copy is stored;\n/// readers recover the key from it (see parseLegacyActivity), so no extra\n/// columns are needed.\nMap<String, Object?> activityRowFields(AdminLogMessage m) => {\n      'description': activityEnglish(m),\n    };", ],
]);
