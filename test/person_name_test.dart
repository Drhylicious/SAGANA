import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/person_name.dart';

// The name rules the app applies on the form. The database applies the same
// rules (supabase_schema_registration_12_name_components.sql) and builds the
// stored full name itself, so these tests also check that the two have not
// drifted apart.
void main() {
  group('compose: First M. Surname Suffix', () {
    // The same cases as verification query V5 in script 12.
    final cases = <List<String?>>[
      ['Juan', null, 'Cruz', null, 'Juan Cruz'],
      ['Juan', 'd', 'Cruz', null, 'Juan D. Cruz'],
      ['Juan', 'D.', 'Cruz', 'Jr.', 'Juan D. Cruz Jr.'],
      ['Marc Louie', 'M', 'Yañez', 'III', 'Marc Louie M. Yañez III'],
      ['Maria', null, 'de la Cruz', 'II', 'Maria de la Cruz II'],
    ];
    for (final c in cases) {
      test('${c[4]}', () {
        expect(
          PersonName.compose(
            firstName: c[0]!,
            middleInitial: c[1],
            surname: c[2]!,
            suffix: c[3],
          ),
          c[4],
        );
      });
    }

    test('blank middle initial and suffix leave no gap or stray period', () {
      expect(
        PersonName.compose(
          firstName: 'Ana',
          middleInitial: '  ',
          surname: 'Santos',
          suffix: '',
        ),
        'Ana Santos',
      );
    });

    test('extra spaces are collapsed and trimmed', () {
      expect(
        PersonName.compose(
          firstName: '  Marc   Louie ',
          middleInitial: 'm',
          surname: ' Yañez ',
          suffix: 'Jr.',
        ),
        'Marc Louie M. Yañez Jr.',
      );
    });

    test('a suffix that is not in the list is dropped, not shown', () {
      expect(
        PersonName.compose(
          firstName: 'Ana',
          surname: 'Santos',
          suffix: 'Esq',
        ),
        'Ana Santos',
      );
    });
  });

  group('surname and first name', () {
    test('required', () {
      expect(PersonName.checkPart('', required: true), NamePartProblem.required);
      expect(PersonName.checkPart('   ', required: true), NamePartProblem.required);
      expect(PersonName.checkPart(null, required: true), NamePartProblem.required);
      expect(PersonName.checkPart('', required: false), isNull);
    });

    test('2 to 60 characters', () {
      expect(PersonName.checkPart('A', required: true), NamePartProblem.length);
      expect(PersonName.checkPart('Li', required: true), isNull);
      expect(PersonName.checkPart('a' * 60, required: true), isNull);
      expect(PersonName.checkPart('a' * 61, required: true), NamePartProblem.length);
    });

    test('letters, spaces, hyphens, apostrophes and periods are accepted', () {
      for (final ok in [
        'Dela Cruz',
        "O'Brien-Cruz",
        'Dela Peña',
        'Yañez',
        'Zoë',
        'O’Neil',
        'St. Cruz',
        'Marc Louie',
      ]) {
        expect(PersonName.checkPart(ok, required: true), isNull, reason: ok);
      }
    });

    test('digits and symbols are rejected, and it must start with a letter', () {
      for (final bad in ['J0hn', 'Juan@', 'Juan_Cruz', '-Juan', "'Juan", '.Juan', 'Juan#']) {
        expect(
          PersonName.checkPart(bad, required: true),
          NamePartProblem.characters,
          reason: bad,
        );
      }
    });
  });

  group('middle initial', () {
    test('empty, or one letter with or without a period', () {
      for (final ok in ['', ' ', 'M', 'm', 'M.', 'm.', 'Ñ']) {
        expect(PersonName.isValidInitial(ok), isTrue, reason: "'$ok'");
      }
      expect(PersonName.isValidInitial(null), isTrue);
    });

    test('anything longer or not a letter is rejected', () {
      for (final bad in ['MA', '1', '.', 'M..', 'M.A', '-']) {
        expect(PersonName.isValidInitial(bad), isFalse, reason: bad);
      }
    });

    test('is stored as the capital letter alone', () {
      expect(PersonName.cleanInitial('m.'), 'M');
      expect(PersonName.cleanInitial(' d '), 'D');
      expect(PersonName.cleanInitial(''), isNull);
      expect(PersonName.cleanInitial(null), isNull);
    });
  });

  group('suffix', () {
    test('the choices are exactly the ones the database accepts', () {
      expect(PersonName.suffixes, ['Jr.', 'Sr.', 'II', 'III', 'IV', 'V']);
    });

    test('only a listed suffix is kept', () {
      expect(PersonName.cleanSuffix('Jr.'), 'Jr.');
      expect(PersonName.cleanSuffix('III'), 'III');
      expect(PersonName.cleanSuffix('Esq'), isNull);
      expect(PersonName.cleanSuffix(''), isNull);
      expect(PersonName.cleanSuffix(null), isNull);
    });
  });

  group('the app and the database use the same rules', () {
    final sql = File(
      'supabase_schema/supabase_schema_registration_12_name_components.sql',
    ).readAsStringSync();

    test('same pattern for a surname / first name', () {
      // Dart: ^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .'’-]*$
      // SQL string literal: the same, with the apostrophe doubled.
      const dartPattern =
          r"^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .'’-]*$";
      final sqlLiteral = dartPattern.replaceAll("'", "''");
      expect(sql, contains(sqlLiteral));
    });

    test('same pattern for the middle initial', () {
      expect(sql, contains(r"'^[A-Za-zÀ-ɏ]\.?$'"));
    });

    test('same length limits', () {
      expect(PersonName.minPartLength, 2);
      expect(PersonName.maxPartLength, 60);
      expect(sql, contains('length(v) < 2 OR length(v) > 60'));
    });

    test('same suffix list and spelling', () {
      for (final s in PersonName.suffixes) {
        expect(sql, contains("THEN '$s'"), reason: s);
      }
      expect(sql, contains("IN ('jr', 'sr', 'ii', 'iii', 'iv', 'v')"));
    });

    test('same full-name format: First M. Surname Suffix', () {
      expect(sql, contains('p_first_name'));
      // first, then the initial with its period, then surname, then suffix.
      final fn = sql.indexOf('FUNCTION public.compose_full_name');
      final body = sql.substring(fn, fn + 900);
      final order = [
        body.indexOf('p_first_name'),
        body.indexOf("btrim(p_middle_initial) || '.'"),
        body.lastIndexOf('btrim(p_surname)'),
        body.lastIndexOf('btrim(p_suffix)'),
      ];
      expect(order.every((i) => i >= 0), isTrue);
      expect([...order]..sort(), order);
    });
  });

  group('NameParts (what Edit Profile saves)', () {
    test('cleans each part and builds the complete name', () {
      final n = NameParts(
        surname: '  Dela   Cruz ',
        firstName: 'juan  carlos',
        middleInitial: 'd.',
        suffix: 'Jr.',
      );
      expect(n.surname, 'Dela Cruz');
      expect(n.firstName, 'juan carlos');
      expect(n.middleInitial, 'D');
      expect(n.fullName, 'juan carlos D. Dela Cruz Jr.');
    });

    test('toColumns sends the four parts and never full_name', () {
      final cols = NameParts(surname: 'Cruz', firstName: 'Juan').toColumns();
      expect(cols.keys.toSet(), {'surname', 'first_name', 'middle_initial', 'suffix'});
      expect(cols.containsKey('full_name'), isFalse);
      expect(cols['middle_initial'], isNull);
      expect(cols['suffix'], isNull);
    });

    test('an unknown suffix is dropped, as the database would reject it', () {
      expect(NameParts(surname: 'Cruz', firstName: 'Juan', suffix: 'Esq').suffix, isNull);
    });

    test('fromRow: parts present -> NameParts; any part missing or blank -> null (older account)', () {
      final n = NameParts.fromRow({
        'surname': 'Cruz',
        'first_name': 'Juan',
        'middle_initial': 'D',
        'suffix': null,
      });
      expect(n, isNotNull);
      expect(n!.fullName, 'Juan D. Cruz');
      expect(NameParts.fromRow({'surname': null, 'first_name': null}), isNull);
      expect(NameParts.fromRow({'surname': 'Cruz', 'first_name': null}), isNull);
      expect(NameParts.fromRow({'surname': ' ', 'first_name': 'Juan'}), isNull);
      expect(NameParts.fromRow(null), isNull);
    });

    test('survives the offline queue (Map<dynamic, dynamic>) round trip', () {
      final saved = NameParts(surname: 'Cruz', firstName: 'Juan', suffix: 'III').toColumns();
      final fromHive = Map<dynamic, dynamic>.from(saved);
      expect(NameParts.fromRow(fromHive)!.fullName, 'Juan Cruz III');
    });

    test('same composed text as PersonName.compose', () {
      expect(
        NameParts(surname: 'Yañez', firstName: 'Marc Louie', middleInitial: 'M', suffix: 'Jr.').fullName,
        PersonName.compose(firstName: 'Marc Louie', middleInitial: 'M', surname: 'Yañez', suffix: 'Jr.'),
      );
    });
  });

  group('avatar initials', () {
    test('a suffix is not taken as the surname', () {
      expect(PersonName.initials('Juan D. Cruz Jr.'), 'JC');
      expect(PersonName.initials('Marc Louie M. Yañez Jr.'), 'MY');
      expect(PersonName.initials('Maria Santos III'), 'MS');
      expect(PersonName.initials('Maria Santos iv'), 'MS');
    });
    test('plain names are unchanged', () {
      expect(PersonName.initials('Juan Dela Cruz'), 'JC');
      expect(PersonName.initials('Cher'), 'C');
      expect(PersonName.initials('  ana   reyes '), 'AR');
    });
    test('empty gives the fallback', () {
      expect(PersonName.initials(''), '?');
      expect(PersonName.initials(null, fallback: 'B'), 'B');
    });
  });
}
