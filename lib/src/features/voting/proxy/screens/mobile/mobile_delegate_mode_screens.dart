import 'package:flutter/material.dart';

import '../../../../../core/l10n/l10n.dart';
import '../../../screens/mobile/mobile_voting_screens.dart';
import '../../proxy_delegation_routes.dart';
import '../delegate_ballot_screen.dart';
import '../delegate_key_import_screen.dart';
import '../delegate_mode_home_screen.dart';
import '../delegate_registration_screen.dart';
import '../delegate_retire_screen.dart';

/// Delegate mode's home on mobile.
class MobileDelegateModeHomeScreen extends StatelessWidget {
  /// Creates the screen.
  const MobileDelegateModeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.delegateModeTitle,
      child: const DelegateModeHomeView(showDesktopToolbar: false),
    );
  }
}

/// Key import on mobile.
class MobileDelegateKeyImportScreen extends StatelessWidget {
  /// Creates the screen.
  const MobileDelegateKeyImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.delegateImportTitle,
      fallbackPath: kDelegateModePath,
      child: const DelegateKeyImportView(showDesktopToolbar: false),
    );
  }
}

/// Registration on mobile.
class MobileDelegateRegistrationScreen extends StatelessWidget {
  /// Creates the screen.
  const MobileDelegateRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.delegateRegisterTitle,
      fallbackPath: kDelegateModePath,
      child: const DelegateRegistrationView(showDesktopToolbar: false),
    );
  }
}

/// DG-9 on mobile; DG-10 opens as a sheet.
class MobileDelegateBallotScreen extends StatelessWidget {
  /// Creates the screen for [roundId].
  const MobileDelegateBallotScreen({required this.roundId, super.key});

  /// Round to vote in.
  final String roundId;

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.delegateBallotTitle,
      fallbackPath: kDelegateModePath,
      child: DelegateRoundBallotView(
        roundId: roundId,
        showDesktopToolbar: false,
      ),
    );
  }
}

/// DG-11 on mobile.
class MobileDelegateRetireScreen extends StatelessWidget {
  /// Creates the screen.
  const MobileDelegateRetireScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileVotingScaffold(
      title: context.l10n.delegateRetireLabel,
      fallbackPath: kDelegateModePath,
      child: const DelegateRetireView(showDesktopToolbar: false),
    );
  }
}
