use strict;
use warnings;

my $defs = 'C:/Users/Administrator/sagana/.claude-scratch/admin_log_keys.txt';
open(my $fh, '<:encoding(UTF-8)', $defs) or die "defs: $!";
my @rows;
while (my $line = <$fh>) {
    chomp $line;
    $line =~ s/\r$//;
    next unless length $line;
    my ($key, $params, $en, $tl) = split(/\|/, $line, 4);
    my @names = grep { length } split(/,/, $params // '');
    push @rows, { key => $key, params => \@names, en => $en, tl => $tl };
}
close($fh);

sub json_str {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    return "\"$s\"";
}

sub arb_block {
    my ($lang) = @_;
    my @out;
    for my $r (@rows) {
        my $text = $r->{$lang};
        push @out, '  ' . json_str($r->{key}) . ': ' . json_str($text);
        if (@{ $r->{params} }) {
            my @ph;
            for my $p (@{ $r->{params} }) {
                my $name = $p;
                my $type = 'String';
                if ($name =~ /^#(.+)$/) { $name = $1; $type = 'int'; }
                push @ph, '"' . $name . '": {"type": "' . $type . '"}';
            }
            push @out, '  ' . json_str('@' . $r->{key}) . ': {"placeholders": {' . join(', ', @ph) . '}}';
        }
    }
    return join(",\n", @out);
}

sub append_arb {
    my ($file, $lang) = @_;
    open(my $in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);
    $text =~ s/\s*\}\s*\z//;
    $text .= ",\n" . arb_block($lang) . "\n}\n";
    open(my $out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "appended " . scalar(@rows) . " keys to $file\n";
}

append_arb('C:/Users/Administrator/sagana/lib/core/l10n/app_en.arb', 'en');
append_arb('C:/Users/Administrator/sagana/lib/core/l10n/app_tl.arb', 'tl');

# Dart renderer: maps a stored key + params onto the generated localization method.
my $dart = "C:/Users/Administrator/sagana/lib/data/models/admin_log_message.dart";
open(my $d, '>:encoding(UTF-8)', $dart) or die "$dart: $!";
print {$d} <<'HEAD';
import 'package:flutter/widgets.dart' show Locale;

import '../../core/l10n/app_localizations.dart';

/// A structured admin activity entry. The log stores [key] and [params]
/// (admin_activity_log.message_key / message_params) so the text can be
/// rendered in the reader's language. Legacy rows have no key and keep their
/// stored English description.
class AdminLogMessage {
  final String key;
  final Map<String, String> params;

  const AdminLogMessage(this.key, [this.params = const {}]);
}

/// English text for storage in the legacy `description` column.
String adminLogEnglish(AdminLogMessage message) =>
    renderAdminLogMessage(lookupAppLocalizations(const Locale('en')), message);

String renderAdminLogMessage(AppLocalizations l, AdminLogMessage m) {
  final p = m.params;
  String v(String name) => p[name] ?? '';
  switch (m.key) {
HEAD
for my $r (@rows) {
    my @args;
    for my $p (@{ $r->{params} }) {
        my $name = $p;
        if ($name =~ /^#(.+)$/) {
            $name = $1;
            push @args, "int.tryParse(v('$name')) ?? 0";
        } else {
            push @args, "v('$name')";
        }
    }
    my $call = "l.$r->{key}(" . join(', ', @args) . ")";
    print {$d} "    case '$r->{key}':\n      return $call;\n";
}
print {$d} <<'TAIL';
    default:
      return m.key;
  }
}
TAIL
close($d);
print "wrote $dart\n";
