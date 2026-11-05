// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appBackAddAccount => '계⁠정 추⁠가';

  @override
  String get appBackHardwareWallets => '하⁠드⁠웨⁠어 지⁠갑';

  @override
  String get appBackImportMethods => '가⁠져⁠오⁠기 방⁠법';

  @override
  String get appBackWalletBirthdayHeight => '지⁠갑 생⁠일 높⁠이';

  @override
  String get appBackWelcome => '시⁠작 화⁠면';

  @override
  String get appExitBackHint => '한 번 더 뒤⁠로 가⁠면 종⁠료⁠돼⁠요';

  @override
  String get appGiftCloseCardFailed => '카⁠드⁠를 닫⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String appLinuxUpdateAvailable(String version) {
    return 'Vizor $version⁠을(를) 사⁠용⁠할 수 있⁠어⁠요.';
  }

  @override
  String appLinuxUpdateAvailableTor(String version) {
    return 'Vizor $version⁠을(를) 사⁠용⁠할 수 있⁠어⁠요. 릴⁠리⁠스 페⁠이⁠지⁠는 Vizor⁠의 Tor 연⁠결 밖⁠에⁠서 브⁠라⁠우⁠저⁠로 열⁠려⁠요.';
  }

  @override
  String get appLinuxUpdateOpenInBrowser => '브⁠라⁠우⁠저⁠에⁠서 열⁠기';

  @override
  String get appLinuxUpdateViewRelease => '릴⁠리⁠스 보⁠기';

  @override
  String get appPrivacyPolicyTitle => '개⁠인⁠정⁠보 처⁠리⁠방⁠침';

  @override
  String get appTermsOfUseTitle => '이⁠용 약⁠관';

  @override
  String get appUpdateApplyingMessage => 'Vizor⁠가 종⁠료⁠되⁠면 적⁠용⁠돼⁠요.';

  @override
  String get appUpdateAvailableMessage =>
      '지⁠금 다⁠운⁠로⁠드⁠하⁠거⁠나 계⁠속 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String get appUpdateAvailableTitle => '업⁠데⁠이⁠트 사⁠용 가⁠능';

  @override
  String appUpdateAvailableVersionTitle(String version) {
    return '업⁠데⁠이⁠트 $version 사⁠용 가⁠능';
  }

  @override
  String get appUpdateDismiss => '닫⁠기';

  @override
  String get appUpdateDownload => '다⁠운⁠로⁠드';

  @override
  String get appUpdateDownloading => '다⁠운⁠로⁠드 중';

  @override
  String appUpdateDownloadingMessage(int percent) {
    return '$percent% 다⁠운⁠로⁠드⁠했⁠어⁠요.';
  }

  @override
  String get appUpdateDownloadingTitle => '업⁠데⁠이⁠트 다⁠운⁠로⁠드 중';

  @override
  String get appUpdateFailedMessage =>
      '업⁠데⁠이⁠트⁠를 완⁠료⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get appUpdateFailedTitle => '업⁠데⁠이⁠트 실⁠패';

  @override
  String get appUpdateLater => '나⁠중⁠에';

  @override
  String get appUpdateReadyMessage => '준⁠비⁠되⁠면 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get appUpdateReadyTitle => '업⁠데⁠이⁠트 준⁠비 완⁠료';

  @override
  String get appUpdateRestart => '다⁠시 시⁠작';

  @override
  String get appUpdateRestarting => '다⁠시 시⁠작 중';

  @override
  String get appUpdateRestartingTitle => 'Vizor 다⁠시 시⁠작 중';

  @override
  String get appUpdateTryAgain => '다⁠시 시⁠도';

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
  String get keyringLockedBody =>
      'Vizor⁠가 시⁠스⁠템 키⁠링⁠에 접⁠근⁠할 수 없⁠어⁠요. 키⁠링 잠⁠금⁠을 해⁠제⁠한 뒤 다⁠시 시⁠도⁠를 선⁠택⁠하⁠세⁠요. 시⁠스⁠템⁠에⁠서 키⁠링 비⁠밀⁠번⁠호⁠를 물⁠어⁠볼 수 있⁠어⁠요.';

  @override
  String get keyringNoResponse => '키⁠링⁠이 응⁠답⁠하⁠지 않⁠았⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keyringOpenFailedTitle => 'Vizor⁠를 열 수 없⁠어⁠요';

  @override
  String get keyringOpeningTitle => 'Vizor 여⁠는 중';

  @override
  String get keyringPromptBody =>
      'Vizor⁠를 계⁠속 사⁠용⁠하⁠려⁠면 시⁠스⁠템 키⁠링 안⁠내⁠를 완⁠료⁠하⁠세⁠요.';

  @override
  String get keyringQuit => '종⁠료';

  @override
  String get keyringRestartHint => 'Vizor⁠를 종⁠료⁠하⁠고 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get keyringRetry => '다⁠시 시⁠도';

  @override
  String get keyringSaveUnconfirmedBody =>
      '변⁠경 사⁠항⁠이 저⁠장⁠되⁠었⁠는⁠지 Vizor⁠가 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 계⁠속⁠하⁠기 전⁠에 Vizor⁠를 종⁠료⁠하⁠고 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get keyringSaveUnconfirmedTitle => '저⁠장⁠을 확⁠인⁠할 수 없⁠어⁠요';

  @override
  String get keyringTryingTitle => '보⁠안 저⁠장⁠소⁠에 접⁠근⁠하⁠는 중';

  @override
  String get keyringUnavailableBody =>
      'Vizor⁠가 시⁠스⁠템 키⁠링⁠에 연⁠결⁠할 수 없⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 Vizor⁠를 종⁠료⁠하⁠고 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get keyringUnavailableTitle => '보⁠안 저⁠장⁠소⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get keyringUnlockTitle => '키⁠링 잠⁠금 해⁠제';

  @override
  String get keyringUnreadableBody =>
      'Vizor⁠가 시⁠스⁠템 키⁠링⁠의 데⁠이⁠터⁠를 읽⁠지 못⁠했⁠어⁠요. 접⁠근⁠을 복⁠구⁠한 뒤 다⁠시 시⁠도⁠하⁠거⁠나 Vizor⁠를 종⁠료⁠해 주⁠세⁠요.';

  @override
  String get keyringUnreadableTitle => '보⁠안 저⁠장⁠소⁠를 읽⁠을 수 없⁠어⁠요';

  @override
  String languageSystemOption(String language) {
    return '시⁠스⁠템 ($language)';
  }

  @override
  String get lockBodyPaused =>
      '동⁠기⁠화⁠가 일⁠시 중⁠지⁠됐⁠어⁠요. 계⁠속⁠하⁠려⁠면 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get lockBodySynced =>
      '동⁠기⁠화⁠를 마⁠쳤⁠어⁠요. 계⁠속⁠하⁠려⁠면 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get lockCheckingPasscode => '암⁠호⁠를 확⁠인⁠하⁠는 중...';

  @override
  String get lockConfirmPasscodeSemantics => '암⁠호⁠를 확⁠인⁠하⁠여 Vizor 잠⁠금 해⁠제';

  @override
  String get lockNavSynced => '동⁠기⁠화⁠됨';

  @override
  String lockNavSyncing(int percent) {
    return '$percent% 동⁠기⁠화 중...';
  }

  @override
  String get lockPasscodeIncorrect => '암⁠호⁠가 올⁠바⁠르⁠지 않⁠아⁠요';

  @override
  String get lockSyncCompleteTitle => '동⁠기⁠화 완⁠료';

  @override
  String get lockSyncPausedSemantics => 'Vizor 동⁠기⁠화⁠가 일⁠시 중⁠지⁠됨';

  @override
  String get lockSyncPausedTitle => '동⁠기⁠화 일⁠시 중⁠지⁠됨';

  @override
  String get lockSyncedSemantics => 'Vizor 동⁠기⁠화⁠됨';

  @override
  String get lockSyncingMessage => 'Vizor 동⁠기⁠화 중';

  @override
  String get lockUnlockToContinue => '계⁠속⁠하⁠려⁠면 잠⁠금⁠을 해⁠제⁠하⁠세⁠요';

  @override
  String get lockUnlockToContinueBody => '계⁠속⁠하⁠려⁠면 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요';

  @override
  String get lockUnlockToContinuePausedBody =>
      '계⁠속⁠하⁠려⁠면 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get lockUnlockVizor => 'Vizor 잠⁠금 해⁠제';

  @override
  String get lockWelcomeBack => '다⁠시 오⁠신 것⁠을 환⁠영⁠해⁠요';

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
