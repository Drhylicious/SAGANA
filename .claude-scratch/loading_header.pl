use strict;
use warnings;

my %fix = (
    'lib/presentation/screens/admin/farmer_details_screen.dart' => "SubPageTopBar(title: '', onBack: () => context.pop())",
    'lib/presentation/screens/admin/listing_review_screen.dart' => "SubPageTopBar(title: '', onBack: () => Navigator.of(context).pop())",

    'lib/presentation/screens/buyer/buyer_settings_screen.dart' => "SubPageTopBar(title: l10n.settingsTitle, onBack: () => Navigator.of(context).pop())",
);

for my $file (sort keys %fix) {
    my $bar = $fix{$file};
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $t = do { local $/; <$in> };
    close($in);
    my $crlf = $t =~ /\r\n/ ? 1 : 0;
    $t =~ s/\r\n/\n/g;

    my $pat = qr/(    if \(_isLoading\) \{\n      return Scaffold\(\n(?:.*\n)*?        body: )const Padding\(padding: EdgeInsets\.all\(16\), child: SkeletonList\(\)\),\n/;
    my $n = () = $t =~ /$pat/g;
    die "$file: loading branch not found\n" unless $n == 1;
    my $repl = "$1Column(\n          children: [\n            $bar,\n            const Expanded(\n              child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),\n            ),\n          ],\n        ),\n";
    $t =~ s/$pat/$repl/;

    $t =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "fixed $file\n";
}
