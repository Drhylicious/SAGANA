import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations_en.dart';
import 'package:sagana/core/l10n/app_localizations_tl.dart';
import 'package:sagana/data/models/farmer_member_model.dart';

void main() {
  group('Farmer statuses read Pending / Active / Disapproved', () {
    test('the stored values are unchanged', () {
      // Only the wording changed: no constraint, history row or function that
      // reads these values needs to change.
      expect(MemberStatus.pending.value, 'pending');
      expect(MemberStatus.active.value, 'active');
      expect(MemberStatus.rejected.value, 'rejected');
      expect(MemberStatusExt.fromString('rejected'), MemberStatus.rejected);
    });

    test('the model labels use the new wording', () {
      expect(MemberStatus.pending.label, 'Pending');
      expect(MemberStatus.active.label, 'Active');
      expect(MemberStatus.rejected.label, 'Disapproved');
    });

    test('screen strings say Disapproved, never Rejected, for a membership', () {
      final en = AppLocalizationsEn();
      expect(en.farmerMgmtStatusRejectedLabel, 'Disapproved');
      expect(en.farmerMgmtStatusActiveLabel, 'Active');
      expect(en.farmerMgmtRejectApplicationAction, 'Disapprove Application');
      expect(en.farmerMgmtRejectDialogTitle('Ana'), 'Disapprove Ana');
      expect(en.farmerMgmtRejectedToast('Ana'), "Ana's application was disapproved.");
      expect(en.farmerDetailsApplicationRejected, 'Application Disapproved');
      expect(en.pendingBadgeRejected, 'DISAPPROVED');
      expect(en.adminLogMembershipRejected, 'Disapproved a membership application.');
      for (final text in [
        en.farmerMgmtRejectApplicationAction,
        en.farmerMgmtConfirmRejectionTitle,
        en.farmerMgmtRejectOutcomeLine,
        en.farmerMgmtDeleteRejectedTitle,
        en.farmerMgmtSubtitleRejectedApp,
        en.pendingBannerRejected,
      ]) {
        expect(text.toLowerCase(), isNot(contains('reject')), reason: text);
      }
    });

    test('Tagalog has the same wording changes', () {
      final tl = AppLocalizationsTl();
      expect(tl.farmerMgmtStatusRejectedLabel, 'Hindi Inaprubahan');
      expect(tl.pendingBadgeRejected, 'HINDI INAPRUBAHAN');
    });
  });

  group('Manager wording', () {
    test('role-naming strings say Manager, not Admin', () {
      final en = AppLocalizationsEn();
      expect(en.adminProfileTitle, 'Manager Profile');
      expect(en.addMemberAdminNoticeTitle, 'Manager Notice');
      expect(en.pendingStepReviewSub, contains('Manager'));
      expect(en.createOfficerNotice, isNot(contains('Admin')));
      expect(en.termsOfUseBody, isNot(contains('Admin')));
      expect(en.privacyPolicyBody, isNot(contains('Admin')));
    });
  });

  group('Registration copy', () {
    test('the username label is just "Username", and registry wording is gone', () {
      final en = AppLocalizationsEn();
      expect(en.registerUsernameLabel, 'Username *');
      expect(en.registerUsernameTaken, 'This username is already taken.');
      expect(en.registerUsernameAvailable, 'Username is available.');
      expect(en.registerInvalidPhone, 'Please enter a valid Philippine mobile number.');
      expect(en.registerInvalidEmail, 'Please enter a valid email address.');
    });

    test('no string in the app mentions a member ID or membership year', () {
      final en = AppLocalizationsEn();
      final all = [en.addMemberUsernameHelp, en.createOfficerUsernameHelp, en.addMemberAdminNoticeBody, en.createOfficerNotice];
      for (final text in all) {
        expect(text, isNot(contains('SP3-YYYY')));
        expect(text.toLowerCase(), isNot(contains('membership year')));
      }
    });
  });

  group('FarmerMemberModel', () {
    test('contact details are separate lines: email, then phone', () {
      final both = FarmerMemberModel.fromMap({
        'user_id': 'u1',
        'contact_email': 'jd.salangsang05@gmail.com',
        'phone_number': '09154721724',
      });
      expect(both.contactLines, ['jd.salangsang05@gmail.com', '09154721724']);
    });

    test('a missing email or phone is left out, not shown as a blank line', () {
      expect(
        FarmerMemberModel.fromMap({'user_id': 'u2', 'phone_number': '09154721724'}).contactLines,
        ['09154721724'],
      );
      expect(
        FarmerMemberModel.fromMap({'user_id': 'u3', 'contact_email': ' a@b.co ', 'phone_number': '  '}).contactLines,
        ['a@b.co'],
      );
      expect(FarmerMemberModel.fromMap({'user_id': 'u4'}).contactLines, isEmpty);
    });

    test('a Members-list record loads without any identifier field', () {
      final m = FarmerMemberModel.fromMap({
        'user_id': 'u1',
        'full_name': 'Ana Reyes',
        'member_status': 'pending',
      });
      expect(m.fullName, 'Ana Reyes');
      expect(m.memberStatus, MemberStatus.pending);
    });
  });
}
