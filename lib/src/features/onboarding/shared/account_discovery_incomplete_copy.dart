import '../../../rust/api/wallet.dart' as rust_wallet;

/// Copy for the warning shown when software account discovery could not check
/// every account. Shared by the desktop modal and the mobile sheet.
abstract final class AccountDiscoveryIncompleteCopy {
  static const title = "Some accounts weren't checked";

  static const continueLabel = 'Continue with available accounts';

  static const backLabel = 'Go back';

  /// Why discovery stopped early.
  static String reason(rust_wallet.SoftwareAccountDiscoveryStatus status) {
    return switch (status) {
      rust_wallet.SoftwareAccountDiscoveryStatus.withheld =>
        'Private queries kept Vizor from checking this recovery phrase for '
            'other accounts.',
      rust_wallet.SoftwareAccountDiscoveryStatus.unavailable =>
        "The wallet service couldn't be reached, so Vizor couldn't check "
            'this recovery phrase for other accounts.',
      rust_wallet.SoftwareAccountDiscoveryStatus.partial =>
        'Vizor found some accounts, but stopped before checking them all.',
      rust_wallet.SoftwareAccountDiscoveryStatus.completed => '',
    };
  }

  static const notEvidence =
      "This doesn't mean the other accounts are empty. You can import this "
      'recovery phrase again later to check for more.';
}
