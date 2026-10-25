import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations_en.dart';
import 'package:sagana/core/l10n/app_localizations_tl.dart';
import 'package:sagana/data/models/farmer_member_model.dart';

// What a Manager can do with a member, by status. Every action is in the ⋯ menu
// on the member's card in the Members list; a member's profile is view-only.
void main() {
  const memberOnly = [
    MemberListAction.sendNotification,
    MemberListAction.resetPassword,
    MemberListAction.issueLoan,
    MemberListAction.recordLoanPayment,
    MemberListAction.toggleSuspend,
  ];

  group('Pending applicant', () {
    final actions = MemberStatus.pending.listActions;

    test('can only be viewed, approved or disapproved', () {
      expect(actions, [
        MemberListAction.viewProfile,
        MemberListAction.approve,
        MemberListAction.disapprove,
      ]);
    });

    test('is offered none of the approved-member actions', () {
      for (final a in memberOnly) {
        expect(actions, isNot(contains(a)), reason: '$a');
      }
      expect(actions, isNot(contains(MemberListAction.deleteApplicant)));
    });

    test('counts as an applicant (read-only profile, no capital recording)', () {
      expect(MemberStatus.pending.isApplicant, isTrue);
      expect(MemberStatus.rejected.isApplicant, isTrue);
      expect(MemberStatus.draft.isApplicant, isTrue);
    });
  });

  group('Approved member (Active, and Inactive which is Active with no recent sign-in)', () {
    for (final status in [MemberStatus.active, MemberStatus.inactive]) {
      test('${status.name} gets every member action and none of the review ones', () {
        final actions = status.listActions;
        expect(actions, [
          MemberListAction.viewProfile,
          MemberListAction.sendNotification,
          MemberListAction.resetPassword,
          MemberListAction.issueLoan,
          MemberListAction.recordLoanPayment,
          MemberListAction.toggleSuspend,
        ]);
        expect(actions, isNot(contains(MemberListAction.approve)));
        expect(actions, isNot(contains(MemberListAction.disapprove)));
        expect(actions, isNot(contains(MemberListAction.deleteApplicant)));
        expect(status.isApplicant, isFalse);
      });
    }

    test('everything the profile menu and bar used to offer is in the list', () {
      // Notify, Pay, Send Notification, Record Loan Payment, Set Suspended,
      // Reset Password and Issue Loan.
      final actions = MemberStatus.active.listActions;
      for (final a in [
        MemberListAction.sendNotification, // Notify
        MemberListAction.recordLoanPayment, // Pay
        MemberListAction.issueLoan, // Issue Loan
        MemberListAction.toggleSuspend, // Set Suspended
        MemberListAction.resetPassword, // Reset Password
      ]) {
        expect(actions, contains(a), reason: '$a');
      }
    });
  });

  test('Suspended member: no new loan, but can be notified, paid and reactivated', () {
    final actions = MemberStatus.suspended.listActions;
    expect(actions, isNot(contains(MemberListAction.issueLoan)));
    expect(actions, containsAll([
      MemberListAction.sendNotification,
      MemberListAction.resetPassword,
      MemberListAction.recordLoanPayment,
      MemberListAction.toggleSuspend,
    ]));
    expect(MemberStatus.suspended.isApplicant, isFalse);
  });

  test('Disapproved applicant: notify, reset password, delete; nothing financial', () {
    expect(MemberStatus.rejected.listActions, [
      MemberListAction.viewProfile,
      MemberListAction.sendNotification,
      MemberListAction.resetPassword,
      MemberListAction.deleteApplicant,
    ]);
  });

  test('the profile screen has no menu, no action bar and no Issue Loan button', () {
    final src = File('lib/presentation/screens/admin/farmer_details_screen.dart')
        .readAsStringSync();
    for (final gone in [
      'more_vert',
      '_BottomActionBar',
      '_ActionsMenu',
      '_showActionsMenu',
      'onIssueLoan',
      'AppRoutes.issueNewLoan',
      'AppRoutes.recordPayment',
      'announcementDashboard',
    ]) {
      expect(src, isNot(contains(gone)), reason: gone);
    }
    // Capital is recorded for members only.
    expect(src, contains('canRecordContribution: !profile.memberStatus.isApplicant'));
  });

  test('the Members list is where the actions live, including Issue Loan', () {
    final src = File('lib/presentation/screens/admin/farmer_management_screen.dart')
        .readAsStringSync();
    expect(src, contains('status.listActions'));
    expect(src, contains("case 'issueLoan':"));
    expect(src, contains('AppRoutes.issueNewLoan, extra: farmer.userId'));
  });

  test('the badge says Pending Applicant, not Pending Verification', () {
    expect(AppLocalizationsEn().farmerDetailsPendingApplicantBadge, 'Pending Applicant');
    expect(AppLocalizationsTl().farmerDetailsPendingApplicantBadge, 'Nakabinbing Aplikante');
    final profile = File('lib/presentation/widgets/member_profile_cards.dart')
        .readAsStringSync();
    expect(profile, contains('l10n.farmerDetailsPendingApplicantBadge'));
    final applicant = File('lib/presentation/screens/farmer/pending_applicant_screen.dart')
        .readAsStringSync();
    expect(applicant, isNot(contains('pendingVerificationBadge')));
    expect(applicant, contains('farmerDetailsPendingApplicantBadge'));
  });
}
