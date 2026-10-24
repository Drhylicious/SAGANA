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
    die "$file: expected 1 match, got $n for: " . substr($from, 0, 70) . "\n" unless $n == 1;
    $t =~ s/\Q$from\E/$to/;
    $t =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "edited $file\n";
}

edit('screens/farmer/listing_success_screen.dart',
"    if (_listing == null) {
      return Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 72),
                const Expanded(
                  child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
                ),
              ],
            ),
            Positioned(
              top: 0, left: 0, right: 0,
              child: FarmerTopBar(
                title: 'Submission Success',
                profilePhotoUrl: null,
                hideProfileAvatar: true,
                onProfileTap: () {},
                onNotificationTap: () {},
                showNotificationButton: false,
                onSettingsTap: null,
              ),
            ),
          ],
        ),
      );
    }
",
"    if (_listing == null) {
      // Normally unreachable: the route redirects when no listing is passed.
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppConstants.primaryGreen),
        ),
      );
    }
");

edit('screens/buyer/order_success_screen.dart',
"            ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
",
"            ? const Center(
                child: CircularProgressIndicator(color: AppConstants.primaryGreen),
              )
");
