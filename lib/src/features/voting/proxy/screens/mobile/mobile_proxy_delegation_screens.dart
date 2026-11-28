import 'package:flutter/material.dart';

import '../../../../../core/l10n/l10n.dart';
import '../../../screens/mobile/mobile_voting_screens.dart';
import '../../../voting_routes.dart';
import '../proxy_allocation_screen.dart';
import '../proxy_delegate_directory_screen.dart';

/// PD-2 on mobile.
class MobileProxyDelegateDirectoryScreen extends StatelessWidget {
  /// Creates the screen for [roundId].
  const MobileProxyDelegateDirectoryScreen({required this.roundId, super.key});

  /// Round being delegated.
  final String roundId;

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.proxyDirectoryTitle,
      fallbackPath: votingPollRoute(roundId),
      child: ProxyDelegateDirectoryView(
        roundId: roundId,
        showDesktopToolbar: false,
      ),
    );
  }
}

/// PD-5 editor on mobile.
class MobileProxyAllocationScreen extends StatelessWidget {
  /// Creates the screen for [roundId].
  const MobileProxyAllocationScreen({required this.roundId, super.key});

  /// Round being delegated.
  final String roundId;

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.proxyAllocationTitle,
      fallbackPath: votingPollRoute(roundId),
      child: ProxyAllocationView(roundId: roundId, showDesktopToolbar: false),
    );
  }
}
