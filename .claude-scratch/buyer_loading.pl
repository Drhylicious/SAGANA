use strict;
use warnings;

sub edit {
    my ($file, $from, $to) = @_;
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $t = do { local $/; <$in> };
    close($in);
    my $crlf = $t =~ /\r\n/ ? 1 : 0;
    $t =~ s/\r\n/\n/g;
    my $n = () = $t =~ /\Q$from\E/g;
    die "$file: expected 1 match, got $n\n" unless $n == 1;
    $t =~ s/\Q$from\E/$to/;
    $t =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "edited $file\n";
}

edit('lib/presentation/screens/buyer/order_detail_screen.dart',
    "      return const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: SkeletonList()));\n",
    "      return Scaffold(\n        body: Column(\n          children: [\n            SubPageTopBar(title: '', onBack: () => context.pop()),\n            const Expanded(\n              child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),\n            ),\n          ],\n        ),\n      );\n");

edit('lib/presentation/screens/buyer/listing_details_screen.dart',
    "      return const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: SkeletonList()));\n",
    "      // Same layout as the loaded page: photo area on top, back button over it.\n      return Scaffold(\n        body: Stack(\n          children: [\n            Column(\n              children: [\n                const SkeletonBlock(height: 260, radius: 0),\n                const Expanded(\n                  child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),\n                ),\n              ],\n            ),\n            Positioned(\n              top: MediaQuery.of(context).padding.top + 8,\n              left: 8,\n              child: SubPageBackButton(onPressed: () => context.pop()),\n            ),\n          ],\n        ),\n      );\n");
