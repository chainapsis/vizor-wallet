// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String carouselPageSemantics(
    String name,
    int page,
    int count,
    String message,
  ) {
    return '$name $count⁠개 중 $page⁠번⁠째. $message';
  }

  @override
  String carouselShowPage(String name, int page, int count) {
    return '$name $count⁠개 중 $page⁠번⁠째 보⁠기';
  }

  @override
  String get commonAddressCopied => '주⁠소⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get commonBack => '뒤⁠로';

  @override
  String commonBackTo(String destination) {
    return '$destination(으)로 돌⁠아⁠가⁠기';
  }

  @override
  String get commonCancel => '취⁠소';

  @override
  String get commonCancellationFailed =>
      '취⁠소⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get commonClearText => '텍⁠스⁠트 지⁠우⁠기';

  @override
  String get commonClose => '닫⁠기';

  @override
  String get commonCopied => '복⁠사⁠했⁠어⁠요';

  @override
  String get commonCopyAddress => '주⁠소 복⁠사';

  @override
  String get commonDismissNotification => '알⁠림 닫⁠기';

  @override
  String get commonFeatureInProgress => '아⁠직 준⁠비 중⁠인 기⁠능⁠이⁠에⁠요.';

  @override
  String get commonInformation => '안⁠내';

  @override
  String get commonNotAvailableYet => '아⁠직 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get commonOk => '확⁠인';

  @override
  String get commonSensitiveContentHidden => '민⁠감⁠한 내⁠용⁠을 가⁠렸⁠어⁠요';

  @override
  String get commonUpdate => '변⁠경';

  @override
  String get commonUpdating => '변⁠경 중...';

  @override
  String languageSystemOption(String language) {
    return '시⁠스⁠템 ($language)';
  }

  @override
  String get navActivity => '활⁠동';

  @override
  String get navHome => '홈';

  @override
  String get navPay => '결⁠제';

  @override
  String get navSettings => '설⁠정';

  @override
  String get navSignOut => '로⁠그⁠아⁠웃';

  @override
  String get navSwap => '스⁠왑';

  @override
  String get navVote => '투⁠표';

  @override
  String get poolShielded => '차⁠폐⁠됨';

  @override
  String get poolTransparent => '투⁠명';

  @override
  String get profilePictureUpdateFailed => '프⁠로⁠필 사⁠진⁠을 바⁠꾸⁠지 못⁠했⁠어⁠요.';

  @override
  String get receiptMessageLabel => '메⁠시⁠지';

  @override
  String get settingsLanguageLabel => '언⁠어';

  @override
  String get settingsLanguageUpdateFailed => '언⁠어⁠를 바⁠꾸⁠지 못⁠했⁠어⁠요.';

  @override
  String get sidebarAccountNameFallback => '사⁠용⁠자 이⁠름';

  @override
  String get sidebarAddressCopyFailed => '주⁠소⁠를 복⁠사⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sidebarCopyShieldedAddress => '차⁠폐 주⁠소 복⁠사';

  @override
  String get sidebarHideBalance => '잔⁠액 숨⁠기⁠기';

  @override
  String get sidebarImporting => '가⁠져⁠오⁠는 중...';

  @override
  String get sidebarManageAccounts => '관⁠리';

  @override
  String get sidebarMigrating => '이⁠전 중...';

  @override
  String get sidebarMigrationNeedsInput => '확⁠인 필⁠요';

  @override
  String get sidebarMigrationStopped => '이⁠전 중⁠단⁠됨';

  @override
  String get sidebarMyAccounts => '내 계⁠정';

  @override
  String get sidebarShieldedAddressCopied => '차⁠폐 주⁠소⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get sidebarShowBalance => '잔⁠액 보⁠기';

  @override
  String get syncSynced => '동⁠기⁠화 완⁠료';

  @override
  String syncSyncedAtBlock(String height) {
    return '$height 블⁠록⁠까⁠지 동⁠기⁠화 완⁠료';
  }

  @override
  String get txFeeInfoDescription =>
      '네⁠트⁠워⁠크 수⁠수⁠료⁠는 Zcash 프⁠로⁠토⁠콜(ZIP 317)이 거⁠래 크⁠기⁠에 따⁠라 정⁠해⁠요. Vizor⁠는 추⁠가 수⁠수⁠료⁠를 받⁠지 않⁠아⁠요.';

  @override
  String get txFeeInfoTitle => '거⁠래 수⁠수⁠료';
}
