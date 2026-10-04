/// Philippine Standard Geographic Code (PSGC) hierarchy used by the
/// structured address form: Region → Province → City/Municipality →
/// Barangay.
///
/// Source: PSA PSGC 2Q 2026 publication, bundled as
/// assets/data/psgc_hierarchy.json. Acknowledgement of the Philippine
/// Statistics Authority as the source is required by its terms.
///
/// Regions with no provinces (NCR, HUCs, independent component cities)
/// carry their cities directly in [PsgcRegion.cities].
class PsgcHierarchy {
  final List<PsgcRegion> regions;

  const PsgcHierarchy({required this.regions});

  PsgcRegion? regionByCode(String code) {
    for (final r in regions) {
      if (r.code == code) return r;
    }
    return null;
  }
}

class PsgcRegion {
  final String code;
  final String name;
  final List<PsgcProvince> provinces;

  /// Cities/municipalities directly under the region (no province).
  final List<PsgcCity> cities;

  const PsgcRegion({
    required this.code,
    required this.name,
    required this.provinces,
    required this.cities,
  });

  bool get hasProvinces => provinces.isNotEmpty;
}

class PsgcProvince {
  final String code;
  final String name;
  final List<PsgcCity> cities;

  const PsgcProvince({
    required this.code,
    required this.name,
    required this.cities,
  });
}

class PsgcCity {
  final String code;
  final String name;

  /// Barangays of this city. Manila's districts are flattened into this
  /// list, so Manila barangays are selected directly under the city.
  final List<PsgcBarangay> barangays;

  const PsgcCity({
    required this.code,
    required this.name,
    required this.barangays,
  });
}

class PsgcBarangay {
  final String code;
  final String name;

  const PsgcBarangay({required this.code, required this.name});
}

/// Philippine postal codes are exactly four digits. This checks the
/// format only; it does not confirm the code belongs to the chosen area.
bool isValidPhilippinePostalCode(String value) {
  return RegExp(r'^\d{4}$').hasMatch(value.trim());
}
