/// Route-shape predicates shared by every policy that has to reason about
/// "where is the user right now".
///
/// Incoming links and update prompts share the account-setup classification.
/// The router also shares initial onboarding and unlock predicates, but keeps
/// post-creation backup and education separate from wallet reachability.
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
    isRouteOrChild(matchedLocation, '/gift') ||
    matchedLocation.startsWith('/onboarding/') ||
    matchedLocation.startsWith('/import');

/// Backup and education continue account setup after the wallet exists.
/// These routes must remain reachable under the router's wallet guard.
bool isPostCreationSetupLocation(String matchedLocation) =>
    isRouteOrChild(matchedLocation, '/setup/backup') ||
    isRouteOrChild(matchedLocation, '/setup/education');

/// Account setup screens whose state must survive external interruptions.
/// Use this for incoming links and prompts, not wallet reachability redirects.
bool isAccountSetupLocation(String matchedLocation) =>
    isOnboardingLocation(matchedLocation) ||
    isPostCreationSetupLocation(matchedLocation);

/// Locations that own the locked-wallet reset flow. An incoming link arriving
/// here must not navigate: `go('/unlock')` from `/lost-password` unmounts the
/// reset the user is part-way through (including while the Windows CredUI
/// prompt is up). The mobile forgot-passcode flow is a sheet over `/unlock`,
/// so it is covered by `/unlock` itself.
bool isUnlockFlowLocation(String matchedLocation) =>
    matchedLocation == '/unlock' || matchedLocation == '/lost-password';
