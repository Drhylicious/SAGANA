// OpenStreetMap map identification and attribution.
//
// PLACEHOLDER: kSaganaContactPlaceholder must be replaced with the actual
// SAGANA / SP3 cooperative email or URL before the final release. Search the
// project for "REPLACE_WITH_SAGANA_CONTACT" to find every place it is used.
// It is currently used only in kOsmTileUserAgent, which is sent on map tile
// requests on Android and iOS. Address search goes through the nominatim-proxy
// Edge Function, which uses the LocationIQ key from the LOCATIONIQ_API_KEY secret.

const String kSaganaContactPlaceholder = 'REPLACE_WITH_SAGANA_CONTACT';

/// Sent as the User-Agent on OpenStreetMap tile requests (native platforms;
/// browsers do not allow the header to be changed).
const String kOsmTileUserAgent = 'SAGANA/1.0 ($kSaganaContactPlaceholder)';

/// Attribution required by the OpenStreetMap licence. Shown on every map
/// that uses OSM tiles, always visible (not behind a toggle).
const String kOsmAttribution = '© OpenStreetMap contributors';

/// Link target for the OpenStreetMap attribution (licence requires it).
const String kOpenStreetMapCopyrightUrl =
    'https://www.openstreetmap.org/copyright';

/// Free-plan attribution for LocationIQ search and reverse results. The free
/// plan requires this exact wording as a link to LocationIQ.
const String kLocationIqAttributionText = 'Search by LocationIQ.com';
const String kLocationIqUrl = 'https://locationiq.com';
