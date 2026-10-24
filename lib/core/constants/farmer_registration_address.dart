/// The fixed address every Farmer and Buyer uses: Barangay Payanas, Torrijos,
/// Marinduque (the cooperative's service area).
///
/// The five values below are shown locked wherever an address is entered
/// (Farmer registration, Pending Applicant details, My Addresses). They are for
/// display only: the database writes its own copy of them (register_account(),
/// and the buyer_addresses trigger for every saved address) and ignores
/// anything the app sends for these fields. Codes are PSGC (2Q 2026) and match
/// assets/data/psgc_hierarchy.json.
class FarmerRegistrationAddress {
  FarmerRegistrationAddress._();

  static const String regionCode = '1700000000';
  static const String regionName = 'MIMAROPA Region';
  static const String provinceCode = '1704000000';
  static const String provinceName = 'Marinduque';
  static const String cityCode = '1704006000';
  static const String cityName = 'Torrijos';
  static const String barangayCode = '1704006019';
  static const String barangayName = 'Payanas';
  static const String postalCode = '4903';

  /// One-line form of the address, in the same order the database stores it:
  /// house no., building, street, barangay, city, province, region, postal code.
  static String composeLine({
    required String houseNo,
    String? building,
    required String street,
  }) {
    return [
      houseNo.trim(),
      building?.trim() ?? '',
      street.trim(),
      barangayName,
      cityName,
      provinceName,
      regionName,
      postalCode,
    ].where((part) => part.isNotEmpty).join(', ');
  }
}
