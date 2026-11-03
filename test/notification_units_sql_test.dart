import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

/// supabase_schema_notification_units.sql re-creates live functions by replacing
/// exact pieces of message text. A piece that no longer matches the function's
/// source is silently skipped by the script, so this checks each piece against
/// the repository's own latest definition of that function.
void main() {
  final script = read('supabase_schema/supabase_schema_notification_units.sql');

  // (piece the script replaces, a file whose function source holds it)
  const pieces = <(String, String)>[
    ("' kg '", 'supabase_schema/supabase_schema_farmer_stock_management.sql'),
    ("'/kg (total '", 'supabase_schema/supabase_schema_farmer_stock_management.sql'),
    ("'/kg for '", 'supabase_schema/supabase_schema_farmer_stock_management.sql'),
    ("'/kg for your '", 'supabase_schema/supabase_schema_coop_offer_negotiation.sql'),
    ('The kg were returned to your inventory.', 'supabase_schema/supabase_schema_coop_offer_negotiation.sql'),
    ("' kg ' || v_batch.crop_name", 'supabase_schema/supabase_schema_coop_offer_negotiation.sql'),
    ("'/kg and needs a response.'", 'supabase_schema/supabase_schema_coop_offer_negotiation.sql'),
    ("' kg of '", 'supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql'),
    ("' kg is back in your stock.'", 'supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql'),
    ("' per kg (total '", 'supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql'),
    ("' kg is still in your request.'", 'supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql'),
    ("' kg unsold). Reason: '", 'supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql'),
    ("' kg already sold stays recorded.'", 'supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql'),
    ("'kg) was submitted for review.'", 'supabase_schema/supabase_schema_crop_photos_selling_rules.sql'),
    ("Only % kg remaining.', v_remaining;", 'supabase_schema/phase_marker_place_order'),
  ];

  group('every piece the notification script replaces exists in the repository source', () {
    for (final (piece, file) in pieces) {
      test(piece, () {
        expect(script, contains('\$f\$$piece\$f\$'), reason: 'the script must list this exact piece');
        if (file.endsWith('phase_marker_place_order')) {
          // place_order's latest definition is in the checkout/recipient-label script.
          expect(
            read('supabase_schema/supabase_schema_order_delivery_recipient_label.sql'),
            contains(piece),
          );
        } else {
          // The offer messages hold it as `' kg ' || v_offer.crop_name`.
          expect(
            read(file),
            contains(piece == "' kg '" ? "' kg ' || v_offer.crop_name" : piece),
          );
        }
      });
    }
  });

  group('the script is safe by construction', () {
    test('it reads the live definition and never contains a pasted function body', () {
      expect(script, contains('pg_get_functiondef'));
      expect(RegExp(r'CREATE (OR REPLACE )?FUNCTION').hasMatch(script.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n')), isFalse);
    });

    test('it refuses to run before the unit columns exist', () {
      expect(script, contains("column_name = 'unit'"));
      expect(script, contains('Run supabase_schema_ginger_any_unit.sql first'));
    });

    test('it re-creates a function only when something was replaced', () {
      expect(script, contains('IF v_new <> v_def THEN'));
    });

    test('it is a single transaction', () {
      expect(script, contains('BEGIN;'));
      expect(script, contains('COMMIT;'));
    });
  });

  group('run order is documented', () {
    test('the Ginger unit script comes before the notification script', () {
      expect(read('supabase_schema/supabase_schema_notification_units.sql'),
          contains('Run AFTER supabase_schema_ginger_any_unit.sql'));
    });
  });
}
