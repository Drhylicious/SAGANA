import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/admin_reports_model.dart'
    show MemberCapitalRecord, parseCreditSlices;
import 'capital_share_rates_repository.dart';
import '../models/contribution_model.dart';
import '../models/monthly_contribution_model.dart';
import '../models/program_model.dart';
import 'member_sales_aggregation.dart';
import 'monthly_contribution_repository.dart';

/// One Farmer's Member Contribution Report for one year: their Capital Share and
/// what the three sources ADDED to it, worked out the same way as the Manager's
/// Member Contribution Report, so a Farmer and the Manager never see two different
/// figures for the same year.
///
///  1. Monthly Contributions: the payments received (capital ledger).
///  2. Cooperative Product Purchases: completed orders at the MEMBER price; only
///     the discount they carry is added to the Capital Share (the purchase is
///     shown for reference).
///  3. Successful Offers to the Cooperative: completed offers. Nothing is added
///     to the Capital Share for them today; the sale value is for reference.
class BenefitsYear {
  final int year;

  // 1. Monthly Contributions
  /// The year's months (oldest first), from member_monthly_contribution_status.
  final List<MonthlyContribution> months;
  final double monthlyDue;

  /// Paid toward the year's months.
  final double monthlyPaidToMonths;

  /// Monthly payments of the year that were never tied to a month. They are in
  /// the Capital Share and counted in [monthlyTotal], but in no month.
  final double monthlyUnassigned;
  final double monthlyBalance;

  /// Every monthly payment received in the year (capital ledger, tied to a month
  /// or not): what the Monthly Contributions added to the Capital Share.
  final double monthlyReceived;

  /// The Capital Share at the start and at the end of the year (the ledger).
  final double capitalAtYearStart;
  final double capitalAtYearEnd;
  final double startingCapital;

  /// The year's Monthly Contribution records, each its own entry.
  final List<MemberCapitalRecord> records;

  /// What the two percentage credits added in the year, and the completed amounts
  /// they were worked out from (capital ledger sources purchase_share / offer_share),
  /// plus the earlier discount credit that stays in the ledger.
  final double purchaseShareCredited;
  final double purchaseShareBase;
  final double offerShareCredited;
  final double offerShareBase;
  final double discountCredited;

  /// The credits split by the settings version they were made under (version ->
  /// [credited, base, discount]), the latest version and the number of settings
  /// changes: newly credited = the latest version, previous = every earlier one.
  final Map<int, List<double>> purchaseByVersion;
  final Map<int, List<double>> offerByVersion;
  final int latestRateVersion;
  final int rateChanges;

  /// transaction id -> the settings version its credit was made under.
  final Map<String, int> creditVersions;

  // 2. Cooperative Product Purchases (member price only)
  final List<ProgramPurchase> purchases;
  final double purchasesNet;
  final double purchasesRegular;
  final double discountEarned;

  // 3. Successful Offers to the Cooperative
  final List<MemberSalesTransaction> offers;
  final double offersAmount;
  final double offersKg;

  const BenefitsYear({
    required this.year,
    this.months = const [],
    this.monthlyDue = 0,
    this.monthlyPaidToMonths = 0,
    this.monthlyUnassigned = 0,
    this.monthlyBalance = 0,
    this.monthlyReceived = 0,
    this.capitalAtYearStart = 0,
    this.capitalAtYearEnd = 0,
    this.startingCapital = 0,
    this.records = const [],
    this.purchaseShareCredited = 0,
    this.discountCredited = 0,
    this.purchaseByVersion = const {},
    this.offerByVersion = const {},
    this.latestRateVersion = 1,
    this.rateChanges = 0,
    this.creditVersions = const {},
    this.purchaseShareBase = 0,
    this.offerShareCredited = 0,
    this.offerShareBase = 0,
    this.purchases = const [],
    this.purchasesNet = 0,
    this.purchasesRegular = 0,
    this.discountEarned = 0,
    this.offers = const [],
    this.offersAmount = 0,
    this.offersKg = 0,
  });

  /// What the Monthly Contributions added: every payment received in the year.
  double get monthlyTotal => monthlyReceived;

  /// What the two percentage credits added, and what the member paid in: the three
  /// always add up to [capitalAddedInYear] (Total Capital Share = Monthly
  /// Contribution + Cooperative Purchase + Offer to Cooperative).
  double get purchaseCredited => discountCredited + purchaseShareCredited;
  double get offersCredited => offerShareCredited;
  double get memberPaidInYear =>
      capitalAddedInYear - purchaseCredited - offersCredited;
  double get otherCapitalAdded =>
      memberPaidInYear - monthlyReceived - startingCapital;
  double get total => capitalAddedInYear;

  /// Everything the ledger added in the year, whatever its source.
  double get capitalAddedInYear => capitalAtYearEnd - capitalAtYearStart;

  bool get hasAnyActivity => total > 0 || months.isNotEmpty;
}

class BenefitsTrackingRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  /// The years this Farmer can open: continuously from the year of their first
  /// record (month, purchase or offer) to this year, newest first. Always holds
  /// this year, so the screen is never empty-handed.
  Future<List<int>> fetchYears() async {
    final now = DateTime.now().year;
    var earliest = now;
    Future<void> probe(
      String table,
      String column,
      String farmerColumn, {
      String? status,
    }) async {
      try {
        var query = _client
            .from(table)
            .select(column)
            .eq(farmerColumn, _userId);
        if (status != null) query = query.eq('status', status);
        final rows = await query.order(column, ascending: true).limit(1);
        if (rows.isEmpty || rows.first[column] == null) return;
        final y = DateTime.parse(rows.first[column] as String).toLocal().year;
        if (y < earliest) earliest = y;
      } catch (_) {
        // Not readable: this source adds no earlier year.
      }
    }

    await Future.wait([
      probe(
        'member_monthly_contribution_status',
        'contribution_month',
        'farmer_id',
      ),
      probe('member_sales_transactions', 'sale_date', 'farmer_id'),
      probe(
        'program_product_purchases',
        'requested_at',
        'farmer_id',
        status: 'completed',
      ),
    ]);
    return [for (var y = now; y >= earliest; y--) y];
  }

  Future<BenefitsYear> fetchYear(int year) async {
    final results = await Future.wait([
      _fetchMonths(year),
      _fetchPurchases(year),
      _fetchOffers(year),
      fetchMemberCapitalYear(_client, year),
      CapitalShareRatesRepository().fetchVersions(),
    ]);
    final months = results[0] as List<MonthlyContribution>;
    final purchases = results[1] as List<ProgramPurchase>;
    final offers = results[2] as List<MemberSalesTransaction>;
    final capital = (results[3] as Map<String, MemberCapitalYear>)[_userId];
    final versions = results[4] as List<CapitalShareRateVersion>;

    var due = 0.0, balance = 0.0;
    for (final m in months) {
      balance += m.balance;
      if (!m.isWaived) due += m.amountDue;
    }

    var net = 0.0, discount = 0.0;
    for (final p in purchases) {
      net += p.totalAmount;
      discount += p.discountAmount;
    }

    var amount = 0.0, kg = 0.0;
    for (final o in offers) {
      amount += o.amount;
      // Only kg sales add to the kilos; a sale in another unit adds its pesos.
      if (isKg(o.unit)) kg += o.quantityKg;
    }

    return BenefitsYear(
      year: year,
      months: months,
      monthlyDue: due,
      monthlyReceived: capital?.monthly ?? 0,
      monthlyPaidToMonths:
          (capital?.monthly ?? 0) - (capital?.monthlyUnassigned ?? 0),
      monthlyUnassigned: capital?.monthlyUnassigned ?? 0,
      monthlyBalance: balance,
      capitalAtYearStart: capital?.balanceAtYearStart ?? 0,
      capitalAtYearEnd: capital?.balanceAtYearEnd ?? 0,
      startingCapital: capital?.startingCapital ?? 0,
      records: [
        for (final m in capital?.records ?? const <Map<String, dynamic>>[])
          MemberCapitalRecord.fromMap(m),
      ],
      purchaseShareCredited: capital?.purchaseShare ?? 0,
      purchaseShareBase: capital?.purchaseShareBase ?? 0,
      offerShareCredited: capital?.offerShare ?? 0,
      offerShareBase: capital?.offerShareBase ?? 0,
      discountCredited: capital?.discountCredited ?? 0,
      purchaseByVersion: parseCreditSlices(capital?.purchaseByVersion),
      offerByVersion: parseCreditSlices(capital?.offerByVersion),
      latestRateVersion: versions.isEmpty ? 1 : versions.last.version,
      creditVersions: capital?.creditVersions ?? const {},
      rateChanges: versions.length > 1 ? versions.length - 1 : 0,
      purchases: purchases,
      purchasesNet: net,
      purchasesRegular: net + discount,
      discountEarned: discount,
      offers: offers,
      offersAmount: amount,
      offersKg: kg,
    );
  }

  Future<List<MonthlyContribution>> _fetchMonths(int year) async {
    final all = await MonthlyContributionRepository().fetchForFarmer(_userId);
    final inYear = all.where((m) => m.month.year == year).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return inYear;
  }

  /// Completed Cooperative Product orders of [year] from Product Sales programs,
  /// bought at the member price (the buyer was an approved, active program member),
  /// newest first. An order counts on the day it was COMPLETED (the day the Sales
  /// Report uses), or on its confirmation day when it predates completed_at.
  /// The same lists for any member (the Manager / Officer report opens a member's
  /// products and offers); staff can read every member's records.
  Future<List<ProgramPurchase>> fetchPurchasesFor(String farmerId, int year) =>
      _fetchPurchases(year, farmerId);

  Future<List<MemberSalesTransaction>> fetchOffersFor(
    String farmerId,
    int year,
  ) => _fetchOffers(year, farmerId);

  Future<List<ProgramPurchase>> _fetchPurchases(
    int year, [
    String? farmerId,
  ]) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(
            '*, cooperative_programs!inner(program_name, program_purpose), '
            'program_products(cooperative_inventory(item_name, unit))',
          )
          .eq('farmer_id', farmerId ?? _userId)
          .eq('status', 'completed')
          // Product Sales programs only, as in the Member Contribution Report.
          .eq('cooperative_programs.program_purpose', 'sales');
      final out = <ProgramPurchase>[];
      for (final r in rows) {
        final program = r['cooperative_programs'] as Map<String, dynamic>?;
        final product = r['program_products'] as Map<String, dynamic>?;
        final inv = product?['cooperative_inventory'] as Map<String, dynamic>?;
        final p = ProgramPurchase.fromMap({
          ...r,
          'program_name': program?['program_name'],
          'item_name': inv?['item_name'],
          'unit': inv?['unit'],
        });
        // Not enrolled in the program = regular price, no benefit, not a contribution.
        if (!p.isMemberPrice) continue;
        final on = p.completedAt ?? p.confirmedAt;
        if (on == null || on.toLocal().year != year) continue;
        out.add(p);
      }
      out.sort(
        (a, b) => (b.completedAt ?? b.confirmedAt!).compareTo(
          a.completedAt ?? a.confirmedAt!,
        ),
      );
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<MemberSalesTransaction>> _fetchOffers(
    int year, [
    String? farmerId,
  ]) async {
    try {
      final rows = await _client
          .from('member_sales_transactions')
          .select()
          .eq('farmer_id', farmerId ?? _userId)
          .gte('sale_date', '$year-01-01')
          .lt('sale_date', '${year + 1}-01-01')
          .order('sale_date', ascending: false);
      return rows.map((r) => MemberSalesTransaction.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }
}
