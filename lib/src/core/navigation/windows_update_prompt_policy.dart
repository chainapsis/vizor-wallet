import 'app_route_predicates.dart';

/// Keep update prompts and restart actions outside setup and wallet writes.
/// Unlock remains eligible so a locked wallet can still install an update.
bool canShowWindowsUpdatePromptAtLocation(String path) =>
    !isAccountSetupLocation(path) &&
    path != '/lost-password' &&
    !path.startsWith('/send') &&
    !isRouteOrChild(path, '/settings/secret-passphrase') &&
    !isRouteOrChild(path, '/settings/viewing-key') &&
    !isRouteOrChild(path, '/settings/change-password') &&
    !isRouteOrChild(path, '/settings/uninstall');
