use strict;
use warnings;

# Builds the reverse map for admin_activity_log rows written before message
# keys existed: each English template in admin_log_keys.txt becomes an
# anchored regex that recovers the key and its parameters.
my $defs = 'C:/Users/Administrator/sagana/.claude-scratch/admin_log_keys.txt';
my $out_file = 'C:/Users/Administrator/sagana/lib/data/models/admin_legacy_generated.dart';

my $fh;
open($fh, '<:encoding(UTF-8)', $defs) or die "defs: $!";
my @rows;
while (my $line = <$fh>) {
    chomp $line;
    $line =~ s/\r$//;
    next unless length $line;
    my ($key, $params, $en, $tl) = split(/\|/, $line, 4);
    push @rows, { key => $key, en => $en, params => [ grep { length } split(/,/, $params // '') ] };
}
close($fh);

sub regex_escape {
    my ($s) = @_;
    $s =~ s/([.*+?^\$\{\}()|\[\]\\\/])/\\$1/g;
    return $s;
}

# Escape a regex for a Dart single-quoted string literal.
sub dart_str {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/'/\\'/g;
    $s =~ s/\$/\\\$/g;
    return "'$s'";
}

my @entries;
my @skipped;
for my $r (@rows) {
    my $en = $r->{en};
    if ($en =~ /\{\w+, plural/) {
        push @skipped, $r->{key};
        next;
    }
    my @names;
    my $pattern = '';
    my $rest = $en;
    while ($rest =~ /\G(.*?)\{(\w+)\}/gc) {
        $pattern .= regex_escape($1) . '(.+?)';
        push @names, $2;
    }
    $rest =~ /\G(.*)\z/s;
    $pattern .= regex_escape($1 // '');
    push @entries, [ $pattern, $r->{key}, \@names ];
}

my $dart;
open($dart, '>:encoding(UTF-8)', $out_file) or die "$out_file: $!";
print {$dart} "// GENERATED from .claude-scratch/admin_log_keys.txt. Do not edit by hand.\n";
print {$dart} "import 'admin_log_message.dart';\n\n";
print {$dart} "/// Recovers the key and parameters from an English admin_activity_log\n";
print {$dart} "/// description written before message keys existed. Null if no template matches.\n";
print {$dart} "AdminLogMessage? parseLegacyAdminLog(String text) {\n";
print {$dart} "  final checks = <(RegExp, String, List<String>)>[\n";
for my $e (@entries) {
    my ($pattern, $key, $names) = @$e;
    my $names_dart = '[' . join(', ', map { dart_str($_) } @$names) . ']';
    print {$dart} "    (RegExp(" . dart_str("^$pattern\$") . "), " . dart_str($key) . ", $names_dart),\n";
}
print {$dart} "  ];\n";
print {$dart} <<'TAIL';
  // Plural templates, matched by hand: the count word differs by number.
  final broadcast = RegExp(r'^Broadcast "(.+?)" sent to (\d+) recipients?\.$')
      .firstMatch(text);
  if (broadcast != null) {
    return AdminLogMessage('adminLogBroadcastSent', {
      'title': broadcast.group(1)!,
      'count': broadcast.group(2)!,
    });
  }
  final export = RegExp(r'^Generated a (.+?) export \((\d+) reports?\)\.$')
      .firstMatch(text);
  if (export != null) {
    return AdminLogMessage('adminLogExportGenerated', {
      'format': export.group(1)!,
      'count': export.group(2)!,
    });
  }
  for (final (regex, key, names) in checks) {
    final match = regex.firstMatch(text);
    if (match == null) continue;
    final params = <String, String>{
      for (var i = 0; i < names.length; i++) names[i]: match.group(i + 1)!,
    };
    return AdminLogMessage(key, params);
  }
  return null;
}
TAIL
close($dart);
print "wrote $out_file with " . scalar(@entries) . " templates; skipped plural: @skipped\n";
