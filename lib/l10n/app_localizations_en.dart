// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String carouselPageSemantics(
    String name,
    int page,
    int count,
    String message,
  ) {
    return '$name $page of $count. $message';
  }

  @override
  String carouselShowPage(String name, int page, int count) {
    return 'Show $name $page of $count';
  }

  @override
  String get commonAddressCopied => 'Address copied';

  @override
  String get commonBack => 'Back';

  @override
  String commonBackTo(String destination) {
    return 'Back to $destination';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCancellationFailed =>
      'Could not finish cancellation. Try again.';

  @override
  String get commonClearText => 'Clear text';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonCopyAddress => 'Copy address';

  @override
  String get commonDismissNotification => 'Dismiss notification';

  @override
  String get commonFeatureInProgress => 'This feature is still in progress.';

  @override
  String get commonInformation => 'Information';

  @override
  String get commonNotAvailableYet => 'Not available yet';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSensitiveContentHidden => 'Sensitive content hidden';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonUpdating => 'Updating...';

  @override
  String languageSystemOption(String language) {
    return 'System ($language)';
  }

  @override
  String get navActivity => 'Activity';

  @override
  String get navHome => 'Home';

  @override
  String get navPay => 'Pay';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSignOut => 'Sign out';

  @override
  String get navSwap => 'Swap';

  @override
  String get navVote => 'Vote';

  @override
  String get poolShielded => 'Shielded';

  @override
  String get poolTransparent => 'Transparent';

  @override
  String get profilePictureUpdateFailed => 'Couldn\'t update profile picture.';

  @override
  String get receiptMessageLabel => 'Message';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageUpdateFailed => 'Couldn\'t update language.';

  @override
  String get sidebarAccountNameFallback => 'Username';

  @override
  String get sidebarAddressCopyFailed => 'Address couldn\'t be copied';

  @override
  String get sidebarCopyShieldedAddress => 'Copy shielded address';

  @override
  String get sidebarHideBalance => 'Hide balance';

  @override
  String get sidebarImporting => 'Importing...';

  @override
  String get sidebarManageAccounts => 'Manage';

  @override
  String get sidebarMigrating => 'Migrating...';

  @override
  String get sidebarMigrationNeedsInput => 'Needs input';

  @override
  String get sidebarMigrationStopped => 'Migration stopped';

  @override
  String get sidebarMyAccounts => 'My accounts';

  @override
  String get sidebarShieldedAddressCopied => 'Shielded address copied';

  @override
  String get sidebarShowBalance => 'Show balance';

  @override
  String get syncSynced => 'Synced';

  @override
  String syncSyncedAtBlock(String height) {
    return 'Synced at block $height';
  }

  @override
  String get txFeeInfoDescription =>
      'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.';

  @override
  String get txFeeInfoTitle => 'Tx fee';
}
