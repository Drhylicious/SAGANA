use strict;
use warnings;

my @rules = (
    [ qr/GestureDetector\(\s*onTap: ([^,\n]+?),\s*child: const Icon\(\s*Icons\.arrow_back_rounded,\s*color: AppConstants\.primaryGreen,\s*\),\s*\)/, 'SubPageBackButton(onPressed: $1)' ],
    [ qr/IconButton\(\s*icon: const Icon\(Icons\.arrow_back_rounded\),\s*color: cs\.onSurface,\s*onPressed: ([^,\n]+?),\s*\)/, 'SubPageBackButton(onPressed: $1)' ],
);

for my $file (@ARGV) {
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);

    my $count = 0;
    for my $rule (@rules) {
        $count += ($text =~ s/$rule->[0]/$rule->[1]/g);
    }
    next unless $count;

    unless ($text =~ m{sub_page_top_bar\.dart}) {
        my $nl = ($text =~ /\r\n/) ? "\r\n" : "\n";
        my $pos = 0;
        while ($text =~ /^import [^\n]*;\r?\n/mg) { $pos = pos($text); }
        substr($text, $pos, 0, "import '../../widgets/sub_page_top_bar.dart';$nl");
    }

    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "$file: $count\n";
}
