import '../l10n/app_localizations.dart';

/// A Shelf Life or Storage Life duration as it is shown: the days, and from
/// one year up the same length in years as well.
///   5    -> "5 days"
///   365  -> "365 days (1 year)"
///   730  -> "730 days (2 years)"
///   400  -> "400 days (1 year, 35 days)"
/// The end date of a countdown is never derived from this text: it is the
/// start date plus the exact number of days.
String lifeDurationText(AppLocalizations l10n, int days) {
  final base = '$days ${l10n.shelfDaysUnit}';
  if (days < 365) return base;
  final years = days ~/ 365;
  final rest = days % 365;
  final inYears = rest == 0
      ? l10n.lifeYears(years)
      : '${l10n.lifeYears(years)}, ${l10n.lifeDaysCount(rest)}';
  return '$base ($inYears)';
}
