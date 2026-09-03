/// Route-shape predicates shared by every policy that has to reason about
/// "where is the user right now".
///
/// Both incoming-link policies — `payment_uri_drain_policy.dart` for a
/// ZIP-321 `zcash:` request and `payment_link_entry_policy.dart` for a Vizor
/// Gift Card — ask the same two questions about setup and unlock routes, and
/// `appRedirect` in `app.dart` asks them too. Keeping one copy is the only way
/// a new onboarding route cannot be added to one guard and forgotten in the
/// other.
///
/// Only the predicates that are genuinely the same for every caller live here.
/// A policy's own extra routes (the Gift Card blocklist's transactional
/// routes, the drain policy's `/send/status`) stay in that policy.
library;

/// Whether [matchedLocation] is [routePath] itself or one of its children.
///
/// `matchedLocation` never carries a query string, so a plain prefix test with
/// the `/` separator is exact: `/send` matches `/send` and `/send/review` but
/// not `/send-something-else`.
bool isRouteOrChild(String matchedLocation, String routePath) =>
    matchedLocation == routePath || matchedLocation.startsWith('$routePath/');

/// Whether [matchedLocation] belongs to onboarding, import, or add-account.
///
/// These screens hold state that only lives in the widget tree — a typed seed
/// phrase, a freshly generated mnemonic, an in-flight account creation — so an
/// incoming link must never navigate away from or paint over them.
///
/// Covers both route trees: the desktop tree in `app.dart` and
/// `mobileOnboardingRoutes()` use the same paths on purpose. The `/import`
/// prefix also covers `/import-keystone` and its children.
bool isOnboardingLocation(String matchedLocation) =>
    matchedLocation == '/welcome' ||
    matchedLocation == '/add-account' ||
    matchedLocation.startsWith('/onboarding/') ||
    matchedLocation.startsWith('/import');

/// Locations that own the locked-wallet reset flow. An incoming link arriving
/// here must not navigate: `go('/unlock')` from `/lost-password` unmounts the
/// reset the user is part-way through (including while the Windows CredUI
/// prompt is up). The mobile forgot-passcode flow is a sheet over `/unlock`,
/// so it is covered by `/unlock` itself.
bool isUnlockFlowLocation(String matchedLocation) =>
    matchedLocation == '/unlock' || matchedLocation == '/lost-password';
