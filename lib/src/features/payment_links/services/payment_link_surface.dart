import 'package:go_router/go_router.dart';

/// Whether [router] knows the Gift Card surface. The surface is registered by
/// the next PR in this stack; until then a pending link stays parked instead
/// of navigating into the router's error page.
bool paymentLinkSurfaceRegistered(GoRouter router) => router
    .configuration
    .routes
    .whereType<GoRoute>()
    .any((route) => route.path == '/payment-links');
