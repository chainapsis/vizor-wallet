/// Page identity for the routes a payment request can be answered onto twice.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// [GoRouterState.pageKey] widened by the identity of the payload the screen
/// behind it only reads once.
///
/// go_router keys a declaratively matched page by its matched path, so a `go`
/// to the location already on screen produces the same page key: the Navigator
/// updates the existing page in place, the screen's `State` is reused, and
/// neither `initState` nor `dispose` runs. Every screen keyed this way seeds
/// itself from the route's `extra` in `initState`, so an in-place update hands
/// the new payload to the previous payload's state and it is dropped.
///
/// That matters because the payment-request card is hosted above the router
/// and answers onto `/send` and `/send/review` from wherever the user already
/// is — including from a card sitting over one of those two screens. Without a
/// payload-scoped key the second request silently keeps the first request's
/// recipient and amount, and on the review screen the outgoing proposal is
/// never handed back, because `dispose` is the only thing that discards it.
///
/// [payloadId] is whatever field already identifies the payload
/// (`SendPrefillArgs.id`, `SendReviewArgs.sendFlowId`, …); null means the route
/// carried no payload, which is an identity of its own.
ValueKey<String> payloadScopedPageKey(GoRouterState state, String? payloadId) =>
    ValueKey<String>('${state.pageKey.value}:${payloadId ?? ''}');
