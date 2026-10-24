import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations_en.dart';
import 'package:sagana/core/l10n/app_localizations_tl.dart';

// The Record Contribution "Type" list and the contribution ledger use plain
// words. Only the labels changed: each one still stands for the same stored
// value, so no calculation or report is affected.
//
//   member_payment     Capital Share Payment   money paid toward the member's capital share
//   patronage_capital  Payout to Capital       Balik-Tangkilik payout the member added to capital
//   manual_adjustment  Correction (+ or −)     fixes a past mistake; the only type that may be negative
//   opening_balance    Starting Capital        capital the member already had before SAGANA
void main() {
  final en = AppLocalizationsEn();
  final tl = AppLocalizationsTl();

  test('English labels in the Type list', () {
    expect(en.farmerDetailsSourcePaymentFull, 'Capital Share Payment');
    expect(en.farmerDetailsSourcePatronageFull, 'Payout to Capital');
    expect(en.farmerDetailsSourceAdjustmentFull, 'Correction (+ or −)');
    expect(en.farmerDetailsSourceOpeningBalance, 'Starting Capital');
  });

  test('English labels in the contribution history', () {
    expect(en.farmerDetailsSourcePayment, 'Payment');
    expect(en.farmerDetailsSourcePatronage, 'Payout to capital');
    expect(en.farmerDetailsSourceAdjustment, 'Correction');
    expect(en.farmerDetailsSourceOpeningBalance, 'Starting Capital');
  });

  test('Tagalog labels are real Tagalog, not left in English jargon', () {
    expect(tl.farmerDetailsSourcePaymentFull, 'Bayad sa Capital Share');
    expect(tl.farmerDetailsSourcePatronageFull, 'Payout para sa Capital');
    expect(tl.farmerDetailsSourceAdjustmentFull, 'Pagwawasto (+ o −)');
    expect(tl.farmerDetailsSourceOpeningBalance, 'Panimulang Capital');
    expect(tl.farmerDetailsSourcePayment, 'Bayad');
    expect(tl.farmerDetailsSourcePatronage, 'Payout sa capital');
    expect(tl.farmerDetailsSourceAdjustment, 'Pagwawasto');
  });

  test('the old jargon is gone', () {
    final all = [
      en.farmerDetailsSourcePaymentFull,
      en.farmerDetailsSourcePatronageFull,
      en.farmerDetailsSourceAdjustmentFull,
      en.farmerDetailsSourceOpeningBalance,
      en.farmerDetailsSourcePayment,
      en.farmerDetailsSourcePatronage,
      en.farmerDetailsSourceAdjustment,
      en.farmerDetailsOnlyAdjustmentNegative,
    ];
    for (final text in all) {
      expect(text.contains('→'), isFalse, reason: text);
      expect(text.toLowerCase().contains('adjustment'), isFalse, reason: text);
      expect(text.toLowerCase().contains('opening'), isFalse, reason: text);
      expect(text.toLowerCase().contains('patronage'), isFalse, reason: text);
    }
  });

  test('type-list labels are short enough for a phone-width dialog', () {
    // A label longer than about 22 characters is cut off with "…" in the
    // closed field on a 360 px phone (checked on screen). 28 characters
    // ("Payment toward capital share") was the original clipping bug.
    for (final text in [
      en.farmerDetailsSourcePaymentFull,
      en.farmerDetailsSourcePatronageFull,
      en.farmerDetailsSourceAdjustmentFull,
      en.farmerDetailsSourceOpeningBalance,
      tl.farmerDetailsSourcePaymentFull,
      tl.farmerDetailsSourcePatronageFull,
      tl.farmerDetailsSourceAdjustmentFull,
      tl.farmerDetailsSourceOpeningBalance,
    ]) {
      expect(text.length, lessThanOrEqualTo(22), reason: text);
    }
  });

  test('the error message uses the new word', () {
    expect(en.farmerDetailsOnlyAdjustmentNegative, 'Only a correction can be negative.');
    expect(tl.farmerDetailsOnlyAdjustmentNegative, 'Isang pagwawasto lamang ang maaaring negatibo.');
  });

  test('Add Farmer: the starting-capital field uses the same word as the history', () {
    expect(en.addMemberInitialContributionLabel, 'Starting Capital (₱)');
    expect(tl.addMemberInitialContributionLabel, 'Panimulang Capital (₱)');
    expect(en.addMemberContributionHelp, contains('Starting Capital'));
    expect(en.addMemberContributionHelp, contains('₱2,000'));
    expect(en.addMemberContributionHelp, contains('₱100/month'));
  });

  test('the stored values and their mapping are unchanged', () {
    // Labels were renamed; the values written to the database were not.
    final dialog = File('lib/presentation/screens/admin/farmer_details_screen.dart')
        .readAsStringSync();
    for (final pair in const {
      'member_payment': 'farmerDetailsSourcePaymentFull',
      'patronage_capital': 'farmerDetailsSourcePatronageFull',
      'manual_adjustment': 'farmerDetailsSourceAdjustmentFull',
      'opening_balance': 'farmerDetailsSourceOpeningBalance',
    }.entries) {
      expect(dialog, contains("'${pair.key}': l10n.${pair.value}"));
    }
    // Only a correction may be negative: the rule itself is still there.
    expect(dialog, contains("_source != 'manual_adjustment'"));
  });
}
