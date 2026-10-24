use strict;
use warnings;

my $defs = 'C:/Users/Administrator/sagana/.claude-scratch/activity_writer_keys.txt';
my $l10n = 'C:/Users/Administrator/sagana/lib/core/l10n/';
my $dart = 'C:/Users/Administrator/sagana/lib/data/models/activity_keys_generated.dart';

my $fh;
open($fh, '<:encoding(UTF-8)', $defs) or die "defs: $!";
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
        push @out, '  ' . json_str($r->{key}) . ': ' . json_str($r->{$lang});
        if (@{ $r->{params} }) {
            my @ph = map { '"' . $_ . '": {"type": "String"}' } @{ $r->{params} };
            push @out, '  ' . json_str('@' . $r->{key}) . ': {"placeholders": {' . join(', ', @ph) . '}}';
        }
    }
    return join(",\n", @out);
}

for my $pair (['app_en.arb', 'en'], ['app_tl.arb', 'tl']) {
    my $file = $l10n . $pair->[0];
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);
    $text =~ s/\r\n/\n/g;
    $text =~ s/\s*\}\s*\z//;
    $text .= ",\n" . arb_block($pair->[1]) . "\n}\n";
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "appended " . scalar(@rows) . " keys to $pair->[0]\n";
}

my $gen;
open($gen, '>:encoding(UTF-8)', $dart) or die "$dart: $!";
print {$gen} "// GENERATED from .claude-scratch/activity_writer_keys.txt. Do not edit by hand.\n";
print {$gen} "import '../../core/l10n/app_localizations.dart';\n\n";
print {$gen} "/// Renders a writer-side activity key. Returns null for unknown keys.\n";
print {$gen} "String? renderGeneratedActivity(AppLocalizations l, String key, Map<String, String> p) {\n";
print {$gen} "  String v(String name) => p[name] ?? '';\n";
print {$gen} "  switch (key) {\n";
for my $r (@rows) {
    next if $r->{key} =~ /^activityField/;
    my @args = map { "v('$_')" } @{ $r->{params} };
    my $call = @args ? "l.$r->{key}(" . join(', ', @args) . ")" : "l.$r->{key}";
    print {$gen} "    case '$r->{key}':\n      return $call;\n";
}
print {$gen} "    default:\n      return null;\n  }\n}\n\n";
print {$gen} "/// Localized label for a profile field code ('name', 'phone', ...). Null if unknown.\n";
print {$gen} "String? activityFieldLabel(AppLocalizations l, String code) {\n  switch (code) {\n";
for my $r (@rows) {
    next unless $r->{key} =~ /^activityField(\w+)$/;
    my $code = lc(substr($1, 0, 1)) . substr($1, 1);
    print {$gen} "    case '$code':\n      return l.$r->{key};\n";
}
print {$gen} "    default:\n      return null;\n  }\n}\n";
close($gen);
print "wrote $dart\n";
