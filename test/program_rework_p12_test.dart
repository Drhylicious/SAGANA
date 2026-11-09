import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/program_enrollment_request_model.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

Map<String, dynamic> _enrolled({required bool hasRequest, String purpose = 'sales'}) => {
  'id': hasRequest ? 'req-1' : 'member:m1',
  'program_id': 'p1',
  'status': 'approved',
  'submitted_at': '2026-10-01T08:00:00Z',
  'reviewed_at': hasRequest ? '2026-10-02T08:00:00Z' : null,
  'cooperative_programs': {'program_name': 'Peanut Cookies', 'program_purpose': purpose, 'program_type': 'food'},
  'user_information': {'full_name': 'Ellen Rosal'},
  'member': {'status': 'active', 'enrolled_at': '2026-10-01T08:00:00Z'},
  'has_request': hasRequest,
};

void main() {
  group('Enrolled list = the active members, in every program type', () {
    final repo = _read('lib/data/repositories/program_repository.dart');
    final screen = _read('lib/presentation/screens/admin/program_enrollment_requests_screen.dart');

    test('it reads active program members, the same definition the Program Management count uses', () {
      final fn = repo.substring(repo.indexOf('fetchEnrolledMembers()'), repo.indexOf('fetchReviewedEnrollmentRequests()'));
      expect(fn, contains("from('program_members')"));
      expect(fn, contains(".eq('status', 'active')"));
      // Not narrowed to one program type.
      expect(fn.contains('program_purpose'), isTrue); // only to display it
      expect(fn.contains(".eq('program_purpose'"), isFalse);
      // Same definition as the count.
      expect(repo, contains(".eq('status', 'active')"));
    });

    test('the Enrolled tab and its count come from that list, not from approved requests', () {
      expect(screen, contains('_repo.fetchEnrolledMembers()'));
      expect(screen, contains('_enrolled = results[1];'));
      expect(screen.contains('fetchReviewedEnrollmentRequests'), isFalse);
    });

    test('a member with no request on record still gets a card, marked as enrolled by the cooperative', () {
      final m = ProgramEnrollmentRequest.fromMap(_enrolled(hasRequest: false));
      expect(m.hasRequest, isFalse);
      expect(m.isApproved, isTrue);
      expect(m.memberStatus, 'active');
      expect(m.programName, 'Peanut Cookies');
      expect(m.programPurpose, 'sales');
      expect(screen, contains('reqEnrolledDirect'));
    });

    test('a member who came through a request keeps that request\'s details', () {
      final m = ProgramEnrollmentRequest.fromMap(_enrolled(hasRequest: true));
      expect(m.hasRequest, isTrue);
      expect(m.reviewedAt, isNotNull);
    });

    test('members are grouped by program', () {
      final fn = repo.substring(repo.indexOf('fetchEnrolledMembers()'), repo.indexOf('fetchReviewedEnrollmentRequests()'));
      expect(fn, contains('a.programName.toLowerCase().compareTo(b.programName.toLowerCase())'));
    });
  });

  group('Enrollment audit script', () {
    final sql = _read('supabase_schema/supabase_schema_program_rework_p12_enrollment_audit.sql');
    final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('it only reads', () {
      for (final w in ['INSERT ', 'UPDATE ', 'DELETE ', 'DROP ', 'ALTER ', 'TRUNCATE', 'CREATE ']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });

    test('it checks the cases that can differ: no request, approved but not enrolled, duplicates', () {
      expect(sql, contains('A3'));
      expect(sql, contains('A4'));
      expect(sql, contains('A6'));
      expect(sql, contains("pm.status = 'active'"));
    });
  });
}
