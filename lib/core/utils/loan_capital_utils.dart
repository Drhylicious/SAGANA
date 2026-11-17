import 'quantity_utils.dart';

/// Capital Share loan eligibility, as the screens show it.
///
/// THE RULE (enforced by the database, see
/// supabase_schema_loan_capital_eligibility.sql): a farmer can only borrow a loan
/// item whose value (quantity x unit price) does not exceed their current Capital
/// Share. These helpers only let a screen show the limit before the database is
/// asked; the Capital Share itself always comes from get_loan_capital_standing().

/// Is one loan item line worth no more than [capitalShare]?
bool lineWithinCapital(double lineValue, double capitalShare) =>
    lineValue <= capitalShare + 1e-9;

/// The most of an item (at [unitPrice]) that fits within [capitalShare], to the 2
/// decimals quantities are stored with. 0 when not even 0.01 fits (always 0 for a
/// Capital Share of 0). An item with no price has no limit.
double maxQuantityWithinCapital({
  required double capitalShare,
  required double unitPrice,
}) {
  if (capitalShare <= 0) return 0;
  if (unitPrice <= 0) return double.infinity;
  var cents = (capitalShare / unitPrice * 100).floor();
  while (cents > 0 && moneyOf(cents / 100, unitPrice) > capitalShare + 1e-9) {
    cents--;
  }
  return cents / 100;
}
