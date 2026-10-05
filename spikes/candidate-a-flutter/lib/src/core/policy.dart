// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Policies of G1-CIC-1.0 that need no platform API: the layout mode of the home screen (G1-LAYOUT-1.0) and the redirect
// rule of the lab update. The constants and the vectors of the contract are pinned by the unit tests.

/// G1-LAYOUT-1.0 mode of the home screen.
enum LayoutMode { regular, compact }

const double layoutMinWidthDp = 360;
const double layoutMinHeightDp = 600;
const double compactMapMaxHeightDp = 240;
const double compactMapMaxWindowFraction = 0.5;

/// [width] and [height]: the app window inside the system insets in logical pixels; [fontScale]: the text scale factor.
LayoutMode layoutMode(double width, double height, double fontScale) =>
    width / fontScale >= layoutMinWidthDp && height / fontScale >= layoutMinHeightDp ? LayoutMode.regular : LayoutMode.compact;

/// Height of the map in the compact mode for a window of [windowHeight].
double compactMapHeight(double windowHeight) {
  final byWindow = windowHeight * compactMapMaxWindowFraction;
  return byWindow < compactMapMaxHeightDp ? byWindow : compactMapMaxHeightDp;
}

const String labUpdateOrigin = 'https://localhost:8443/';
const String defaultUpdateUrl = 'https://localhost:8443/update/G1SYN-update.zip';
const String labUpdateScheme = 'https';
const String labUpdateHost = 'localhost';
const int labUpdatePort = 8443;
const int updateMaxRedirects = 5;

/// True when [uri] is inside the lab origin (scheme, host and port).
bool inLabOrigin(Uri uri) => uri.scheme == labUpdateScheme && uri.host == labUpdateHost && uri.port == labUpdatePort && uri.userInfo.isEmpty;

/// The next request URL of a redirect of the lab update, or null when the redirect is not followed: no Location header,
/// [hop] redirects already followed up to the bound, an unparsable target or a target outside the lab origin.
Uri? redirectTarget(Uri current, String? location, int hop) {
  if (location == null || hop >= updateMaxRedirects) return null;
  final Uri next;
  try {
    next = current.resolve(location);
  } on FormatException {
    return null;
  }
  return inLabOrigin(next) ? next : null;
}
