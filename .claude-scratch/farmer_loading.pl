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

my $dir = 'lib/presentation/screens/farmer/';

edit($dir . 'farmer_settings_screen.dart',
"      return Scaffold(
        backgroundColor: sagana.scaffoldBackground,
        body: const Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      );
",
"      return Scaffold(
        backgroundColor: sagana.scaffoldBackground,
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
              top: 0,
              left: 0,
              right: 0,
              child: FarmerTopBar(
                title: l10n.settingsTitle,
                onBack: () => context.popRoute(),
                hideProfileAvatar: true,
                onProfileTap: () {},
                onNotificationTap: () {},
                showNotificationButton: false,
              ),
            ),
          ],
        ),
      );
");

edit($dir . 'harvest_entry_form_screen.dart',
"    if (_isLoadingCrops) {
      return const Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      );
    }
",
"    if (_isLoadingCrops) {
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
                title: '',
                onBack: () => Navigator.of(context).pop(),
                profilePhotoUrl: null,
                onProfileTap: () {},
                onNotificationTap: () {},
                onSettingsTap: null,
                hideProfileAvatar: true,
                showNotificationButton: false,
              ),
            ),
          ],
        ),
      );
    }
");

edit($dir . 'listing_success_screen.dart',
"    if (_listing == null) {
      return const Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      );
    }
",
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
");

edit($dir . 'pending_applicant_screen.dart',
"      body: _isLoading && _currentTab == 0
          ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
          : screens[_currentTab],
",
"      body: _isLoading && _currentTab == 0
          ? CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SimpleTopBar(
                    title: l10n.pendingHomeTitle,
                    sagana: sagana,
                    cs: cs,
                    topPadding: MediaQuery.of(context).padding.top,
                  ),
                ),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
                ),
              ],
            )
          : screens[_currentTab],
");
