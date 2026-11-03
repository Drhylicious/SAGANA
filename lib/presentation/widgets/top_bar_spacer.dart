import 'package:flutter/widgets.dart';

/// Space reserved at the top of a screen for an overlaid top bar.
///
/// The Farmer, Buyer and Manager top bars grow by the status-bar height (see
/// `MediaQuery.padding.top`), so a fixed gap under them hides the first rows of
/// content on a phone with a status bar or camera cut-out. [height] is the gap
/// the bar needs on a screen with no status bar (the old fixed value).
class TopBarSpacer extends StatelessWidget {
  final double height;

  const TopBarSpacer({super.key, this.height = 64});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height + MediaQuery.paddingOf(context).top);
}
