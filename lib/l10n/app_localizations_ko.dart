// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get accountNameLabel => '계⁠정 이⁠름';

  @override
  String get accountsActionsLabel => '계⁠정 작⁠업';

  @override
  String get accountsAddressLoadFailed => '계⁠정 주⁠소⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsClearName => '계⁠정 이⁠름 지⁠우⁠기';

  @override
  String get accountsCurrent => '현⁠재 계⁠정';

  @override
  String get accountsEdit => '계⁠정 편⁠집';

  @override
  String get accountsEditFailed => '계⁠정⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get accountsEditNameHint => '1-20⁠자';

  @override
  String get accountsManage => '계⁠정 관⁠리';

  @override
  String accountsOptionsFor(String name) {
    return '$name 계⁠정 옵⁠션';
  }

  @override
  String get accountsOther => '다⁠른 계⁠정';

  @override
  String get accountsOtherAccounts => '다⁠른 계⁠정';

  @override
  String get accountsRemove => '계⁠정 삭⁠제';

  @override
  String get accountsRemoveBackupWarning =>
      '이 계⁠정⁠의 복⁠구 문⁠구⁠를 백⁠업⁠하⁠지 않⁠았⁠다⁠면, 삭⁠제⁠한 뒤⁠에⁠는 계⁠정⁠의 자⁠금⁠을 복⁠구⁠할 수 없⁠어⁠요.';

  @override
  String accountsRemoveBlockedByGiftCards(int count) {
    return '이 계⁠정⁠으⁠로 기⁠프⁠트 카⁠드 $count⁠장⁠을 받⁠는 중⁠이⁠에⁠요. 이 계⁠정⁠을 삭⁠제⁠하⁠기 전⁠에 완⁠료⁠될 때⁠까⁠지 기⁠다⁠려 주⁠세⁠요.';
  }

  @override
  String accountsRemoveBlockedBySwaps(int count) {
    return '이 계⁠정⁠에 진⁠행 중⁠인 스⁠왑⁠이 $count⁠개 있⁠어⁠요. 이 계⁠정⁠을 삭⁠제⁠하⁠기 전⁠에 스⁠왑 활⁠동⁠에⁠서 완⁠료⁠하⁠거⁠나 삭⁠제⁠해 주⁠세⁠요.';
  }

  @override
  String get accountsRemoveBody =>
      '이 계⁠정⁠을 삭⁠제⁠하⁠면 Vizor⁠에⁠서 계⁠정⁠의 로⁠컬 데⁠이⁠터⁠가 삭⁠제⁠돼⁠요. 계⁠속⁠하⁠기 전⁠에 계⁠정⁠을 다⁠시 가⁠져⁠올 수 있⁠는⁠지 꼭 확⁠인⁠하⁠세⁠요.';

  @override
  String get accountsRemoveCheckingGiftCards =>
      '삭⁠제⁠하⁠기 전⁠에 이 계⁠정⁠으⁠로 받⁠는 중⁠인 기⁠프⁠트 카⁠드⁠가 있⁠는⁠지 확⁠인⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get accountsRemoveCheckingPassword => '비⁠밀⁠번⁠호 확⁠인 중...';

  @override
  String get accountsRemoveCheckingSwaps =>
      '삭⁠제⁠하⁠기 전⁠에 이 계⁠정⁠에 진⁠행 중⁠인 스⁠왑⁠이 있⁠는⁠지 확⁠인⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get accountsRemoveConfirm => '삭⁠제';

  @override
  String get accountsRemoveFailed => '계⁠정⁠을 삭⁠제⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get accountsRemoveFailedToast => '계⁠정⁠을 삭⁠제⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsRemoveGiftCardsCheckFailed =>
      '이 계⁠정⁠으⁠로 받⁠는 중⁠인 기⁠프⁠트 카⁠드⁠가 있⁠는⁠지 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 삭⁠제⁠하⁠기 전⁠에 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get accountsRemoveMigrationBody =>
      '이 계⁠정⁠의 이⁠전 작⁠업⁠은 더 이⁠상 Vizor⁠에⁠서 계⁠속⁠되⁠지 않⁠아⁠요. 이⁠미 Zcash 네⁠트⁠워⁠크⁠에 제⁠출⁠한 거⁠래⁠는 그⁠대⁠로 완⁠료⁠될 수 있⁠어⁠요. 다⁠시 가⁠져⁠온 뒤⁠에⁠는 계⁠정⁠을 완⁠전⁠히 동⁠기⁠화⁠한 다⁠음⁠에 이⁠전⁠을 다⁠시 시⁠작⁠하⁠세⁠요.';

  @override
  String get accountsRemoveModalBody =>
      '이 계⁠정⁠을 삭⁠제⁠할⁠까⁠요? 이 작⁠업⁠은 되⁠돌⁠릴 수 없⁠어⁠요.\n계⁠정⁠을 다⁠시 가⁠져⁠와⁠야 해⁠요.';

  @override
  String get accountsRemovePasswordHint => '비⁠밀⁠번⁠호⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String get accountsRemoveStoppingSync => '동⁠기⁠화⁠를 중⁠지⁠하⁠는 중...';

  @override
  String get accountsRemoveSwapsCheckFailed =>
      '이 계⁠정⁠에 진⁠행 중⁠인 스⁠왑⁠이 있⁠는⁠지 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 삭⁠제⁠하⁠기 전⁠에 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get accountsRemoving => '계⁠정⁠을 삭⁠제⁠하⁠는 중...';

  @override
  String get accountsResetBody =>
      'Vizor⁠를 초⁠기⁠화⁠하⁠면 모⁠든 계⁠정⁠과 지⁠갑 데⁠이⁠터⁠가 삭⁠제⁠돼⁠요. 계⁠속⁠하⁠기 전⁠에 계⁠정⁠을 다⁠시 가⁠져⁠올 수 있⁠는⁠지 꼭 확⁠인⁠하⁠세⁠요.';

  @override
  String get accountsResetFailed => 'Vizor⁠를 초⁠기⁠화⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get accountsResetFailedToast => 'Vizor⁠를 초⁠기⁠화⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsResetMigrationBody =>
      'Vizor⁠를 초⁠기⁠화⁠하⁠면 이 기⁠기⁠의 이⁠전 작⁠업⁠이 중⁠단⁠되⁠고 모⁠든 계⁠정⁠과 지⁠갑 데⁠이⁠터⁠가 삭⁠제⁠돼⁠요. 이⁠미 Zcash 네⁠트⁠워⁠크⁠에 제⁠출⁠한 거⁠래⁠는 그⁠대⁠로 완⁠료⁠될 수 있⁠어⁠요. 다⁠시 가⁠져⁠온 뒤⁠에⁠는 각 계⁠정⁠을 완⁠전⁠히 동⁠기⁠화⁠한 다⁠음⁠에 이⁠전⁠을 다⁠시 시⁠작⁠하⁠세⁠요.';

  @override
  String get accountsResetModalBody =>
      '이 계⁠정⁠을 삭⁠제⁠하⁠면 Vizor 앱⁠이 완⁠전⁠히 초⁠기⁠화⁠돼⁠요. 모⁠든 계⁠정⁠이 삭⁠제⁠되⁠고 계⁠정⁠을 다⁠시 가⁠져⁠와⁠야 해⁠요.\n공⁠유⁠하⁠지 않⁠은 기⁠프⁠트 카⁠드 링⁠크⁠도 영⁠구⁠적⁠으⁠로 사⁠라⁠져⁠요.\n이 작⁠업⁠은 되⁠돌⁠릴 수 없⁠어⁠요.';

  @override
  String get accountsResetting => '초⁠기⁠화⁠하⁠는 중...';

  @override
  String get accountsSaveEdits => '변⁠경 사⁠항 저⁠장';

  @override
  String get accountsSaveFailed => '계⁠정 변⁠경 사⁠항⁠을 저⁠장⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsSendFailed => '보⁠내⁠기⁠를 시⁠작⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsSendZec => 'ZEC 보⁠내⁠기';

  @override
  String get accountsTitle => '계⁠정';

  @override
  String get accountsUpdatePicture => '사⁠진 업⁠데⁠이⁠트';

  @override
  String get accountsViewSecretPhrase => '복⁠구 문⁠구 보⁠기';

  @override
  String get accountsViewViewingKey => '뷰⁠잉 키 보⁠기';

  @override
  String get appBackHardwareWallets => '하⁠드⁠웨⁠어 지⁠갑';

  @override
  String get appBackImportMethods => '가⁠져⁠오⁠기 방⁠법';

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
  String get appOpenFailedTitle => 'Vizor⁠를 열 수 없⁠어⁠요';

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
  String get appUpdateFailedTitle => '업⁠데⁠이⁠트 실⁠패';

  @override
  String get appUpdateLater => '나⁠중⁠에';

  @override
  String get appUpdateReadyMessage => '준⁠비⁠되⁠면 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get appUpdateReadyTitle => '업⁠데⁠이⁠트 준⁠비 완⁠료';

  @override
  String get appUpdateRestarting => '다⁠시 시⁠작 중';

  @override
  String get appUpdateRestartingTitle => 'Vizor 다⁠시 시⁠작 중';

  @override
  String get bip39PassphraseTitle => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈';

  @override
  String bip39PassphraseValue(String passphrase) {
    return 'BIP39 패⁠스⁠프⁠레⁠이⁠즈: $passphrase';
  }

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
  String get commonAddAccount => '계⁠정 추⁠가';

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
  String get commonCannotBeUndone => '되⁠돌⁠릴 수 없⁠어⁠요.';

  @override
  String get commonChecking => '확⁠인 중...';

  @override
  String get commonClearText => '텍⁠스⁠트 지⁠우⁠기';

  @override
  String get commonClose => '닫⁠기';

  @override
  String get commonCoinholderVoting => '코⁠인 보⁠유⁠자 투⁠표';

  @override
  String get commonContinue => '계⁠속';

  @override
  String get commonCopied => '복⁠사⁠했⁠어⁠요';

  @override
  String get commonCopy => '복⁠사';

  @override
  String get commonCopyAddress => '주⁠소 복⁠사';

  @override
  String get commonDismissNotification => '알⁠림 닫⁠기';

  @override
  String get commonFeatureInProgress => '아⁠직 준⁠비 중⁠인 기⁠능⁠이⁠에⁠요.';

  @override
  String get commonGoBack => '돌⁠아⁠가⁠기';

  @override
  String get commonImporting => '가⁠져⁠오⁠는 중...';

  @override
  String get commonInformation => '안⁠내';

  @override
  String get commonKeepQrSteady => 'QR 코⁠드⁠가 흔⁠들⁠리⁠지 않⁠고 전⁠부 보⁠이⁠게 해 주⁠세⁠요.';

  @override
  String get commonKeepScreenAwake => '화⁠면 켜 두⁠기';

  @override
  String get commonNotAvailableYet => '아⁠직 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get commonOk => '확⁠인';

  @override
  String get commonQuit => '종⁠료';

  @override
  String get commonResetVizor => 'Vizor 초⁠기⁠화';

  @override
  String get commonRetry => '다⁠시 시⁠도';

  @override
  String get commonScanQrCode => 'QR 코⁠드 스⁠캔';

  @override
  String get commonSelectAccount => '계⁠정 선⁠택';

  @override
  String get commonSensitiveContentHidden => '민⁠감⁠한 내⁠용⁠을 가⁠렸⁠어⁠요';

  @override
  String get commonTryAgain => '다⁠시 시⁠도';

  @override
  String get commonUnlockVizor => 'Vizor 잠⁠금 해⁠제';

  @override
  String get commonUpdate => '변⁠경';

  @override
  String get commonUpdating => '변⁠경 중...';

  @override
  String get commonWelcomeBack => '다⁠시 오⁠신 것⁠을 환⁠영⁠해⁠요';

  @override
  String endpointCurrent(String endpoint) {
    return '현⁠재: $endpoint';
  }

  @override
  String get endpointCustom => '사⁠용⁠자 지⁠정 엔⁠드⁠포⁠인⁠트';

  @override
  String get endpointUpdate => '엔⁠드⁠포⁠인⁠트 업⁠데⁠이⁠트';

  @override
  String get endpointUpdated => '엔⁠드⁠포⁠인⁠트⁠를 업⁠데⁠이⁠트⁠했⁠어⁠요';

  @override
  String get homeActivityEmpty => '아⁠직 활⁠동⁠이 없⁠어⁠요...';

  @override
  String get homeActivityEmptyHint => '첫 ZEC 거⁠래⁠를 보⁠내 볼⁠까⁠요?';

  @override
  String get homeActivityEmptyHintMobile => '첫 ZEC 거⁠래⁠를\n보⁠내 볼⁠까⁠요?';

  @override
  String get homeActivityLoading => '활⁠동 불⁠러⁠오⁠는 중';

  @override
  String get homeActivityUnavailable => '활⁠동⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeBackupSubtitle => '복⁠구 문⁠구⁠를 백⁠업⁠하⁠세⁠요\n마⁠지⁠막 단⁠계';

  @override
  String get homeBackupTitle => '지⁠갑 보⁠호⁠하⁠기';

  @override
  String get homeDismiss => '닫⁠기';

  @override
  String get homeEducationSubtitle => '프⁠라⁠이⁠버⁠시, 주⁠소 유⁠형, 앞⁠으⁠로 알⁠아⁠둘 점';

  @override
  String get homeEducationTitle => 'Zcash 알⁠아⁠보⁠기';

  @override
  String get homeImportingBodyMobile =>
      '잠⁠시⁠만 기⁠다⁠려 주⁠세⁠요... 시⁠간⁠이 걸⁠릴 수 있⁠어⁠요. Vizor⁠를 열⁠어 둔 채⁠로 실⁠행⁠해 주⁠세⁠요.';

  @override
  String get homeImportingDetail =>
      '시⁠간⁠이 걸⁠릴 수 있⁠어⁠요.\nVizor⁠를 열⁠어 둔 채⁠로 실⁠행⁠해 주⁠세⁠요.';

  @override
  String homeImportingDetailNamed(String name) {
    return '$name 가⁠져⁠오⁠는 중\nVizor⁠를 열⁠어 둔 채⁠로 실⁠행⁠해 주⁠세⁠요.';
  }

  @override
  String get homeImportingTitle => '지⁠갑⁠을\n가⁠져⁠오⁠는 중⁠이⁠에⁠요...';

  @override
  String get homeImportingTitleMobile => '지⁠갑⁠을 가⁠져⁠오⁠는 중⁠이⁠에⁠요...';

  @override
  String get homeKeepAwakeBody =>
      '화⁠면⁠이 꺼⁠지⁠면 휴⁠대⁠폰⁠이 동⁠기⁠화⁠를 멈⁠춰⁠요. 화⁠면⁠을 켜 두⁠면 동⁠기⁠화⁠가 더 빨⁠리 끝⁠나⁠요.';

  @override
  String get homeKeepAwakeLater => '나⁠중⁠에';

  @override
  String get homeKeepAwakeLockNote =>
      '1⁠분 동⁠안 사⁠용⁠하⁠지 않⁠으⁠면 앱⁠이 잠⁠겨⁠요. 잠⁠긴 상⁠태⁠에⁠서⁠도 동⁠기⁠화⁠는 계⁠속⁠돼⁠요.';

  @override
  String get homeKeepAwakeSettingsNote => '설⁠정⁠에⁠서 언⁠제⁠든 바⁠꿀 수 있⁠어⁠요.';

  @override
  String get homeKeepAwakeTitle => '동⁠기⁠화 중 화⁠면⁠을 켜 둘⁠까⁠요?';

  @override
  String get homeLedgerActionNeeded => '확⁠인 필⁠요';

  @override
  String get homeLedgerApprovalNotAccepted =>
      'Ledger⁠가 이 승⁠인⁠을 받⁠아⁠들⁠이⁠지 못⁠했⁠어⁠요. 이⁠전 승⁠인⁠은 이⁠미 전⁠송⁠됐⁠어⁠요.';

  @override
  String get homeLedgerBroadcastNotStored =>
      '차⁠폐 거⁠래⁠가 네⁠트⁠워⁠크⁠에 전⁠달⁠됐⁠지⁠만 기⁠기⁠에 저⁠장⁠되⁠지 않⁠았⁠어⁠요. 동⁠기⁠화⁠로 확⁠인⁠되⁠기 전⁠에⁠는 다⁠시 시⁠도⁠하⁠지 마⁠세⁠요.';

  @override
  String get homeLedgerBroadcastUnknown =>
      '차⁠폐 거⁠래⁠가 네⁠트⁠워⁠크⁠에 전⁠달⁠됐⁠을 수 있⁠어⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 활⁠동⁠을 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get homeLedgerCancelShielding => '차⁠폐 취⁠소';

  @override
  String get homeLedgerContextChanged =>
      '선⁠택⁠한 계⁠정⁠이⁠나 네⁠트⁠워⁠크⁠가 바⁠뀌⁠었⁠어⁠요. 지⁠갑⁠으⁠로 돌⁠아⁠가 주⁠세⁠요.';

  @override
  String get homeLedgerInputsRemaining => '남⁠은 입⁠력 있⁠음';

  @override
  String get homeLedgerNoFundsRemain =>
      '사⁠용⁠할 수 있⁠는 투⁠명 자⁠금⁠이 남⁠아 있⁠지 않⁠아⁠요. 지⁠갑⁠으⁠로 돌⁠아⁠가 주⁠세⁠요.';

  @override
  String get homeLedgerNoSapling =>
      '이 Ledger 미⁠리⁠보⁠기⁠는 Sapling 입⁠력⁠이⁠나 출⁠력⁠을 지⁠원⁠하⁠지 않⁠아⁠요.';

  @override
  String get homeLedgerPausedBelowThreshold =>
      '남⁠은 자⁠금⁠이 차⁠폐 최⁠소 금⁠액⁠보⁠다 적⁠어⁠요.';

  @override
  String get homeLedgerPausedTitle => '차⁠폐⁠가 일⁠시 중⁠지⁠됐⁠어⁠요';

  @override
  String get homeLedgerPausedWalletChanges =>
      '지⁠갑 변⁠경⁠이 끝⁠나⁠는 동⁠안 차⁠폐⁠를 일⁠시 중⁠지⁠했⁠어⁠요. 지⁠갑⁠으⁠로 돌⁠아⁠가 주⁠세⁠요.';

  @override
  String get homeLedgerRejected => 'Ledger⁠에⁠서 차⁠폐 거⁠래⁠를 거⁠부⁠했⁠어⁠요.';

  @override
  String get homeLedgerRoundFeeNotice =>
      '승⁠인⁠할 때⁠마⁠다 별⁠도⁠의 거⁠래⁠가 만⁠들⁠어⁠지⁠고 각⁠각 네⁠트⁠워⁠크 수⁠수⁠료⁠가 들⁠어⁠요.';

  @override
  String homeLedgerRoundSentBelowThreshold(int round) {
    return '$round⁠번⁠째 단⁠계⁠를 전⁠송⁠했⁠어⁠요. 남⁠은 자⁠금⁠이 차⁠폐 최⁠소 금⁠액⁠보⁠다 적⁠어⁠요.';
  }

  @override
  String homeLedgerRoundSentNoReduction(int round) {
    return '$round⁠번⁠째 단⁠계⁠는 전⁠송⁠했⁠지⁠만 사⁠용 가⁠능⁠한 입⁠력⁠이 줄⁠었⁠는⁠지 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 동⁠기⁠화⁠를 기⁠다⁠린 뒤 다⁠시 차⁠폐⁠해 주⁠세⁠요.';
  }

  @override
  String homeLedgerRoundSentUnchecked(int round) {
    return '$round⁠번⁠째 단⁠계⁠는 전⁠송⁠했⁠지⁠만 남⁠은 자⁠금⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 지⁠갑⁠으⁠로 돌⁠아⁠가 동⁠기⁠화⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';
  }

  @override
  String get homeLedgerShieldTitle => 'Ledger⁠로 차⁠폐⁠하⁠기';

  @override
  String get homeLedgerShieldingFailed => 'Ledger⁠로 차⁠폐⁠를 완⁠료⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeLedgerSigningFailedTitle => 'Ledger 서⁠명⁠에 실⁠패⁠했⁠어⁠요';

  @override
  String homeLoadFailed(String details) {
    return '문⁠제⁠가 생⁠겼⁠어⁠요. 잠⁠시 후 다⁠시 시⁠도⁠해 주⁠세⁠요.\n\n자⁠세⁠한 내⁠용: $details';
  }

  @override
  String get homeMigrateToIronwood => 'Ironwood⁠로 이⁠전⁠하⁠기';

  @override
  String get homeMigrationRequired => '이⁠전 필⁠요';

  @override
  String get homeMigrationRequiredTitle => '이⁠전 필⁠요';

  @override
  String homeMigrationStillMigrating(String amount) {
    return '$amount 이⁠전 중';
  }

  @override
  String get homeMigrationStoppedByUpgrade =>
      '네⁠트⁠워⁠크 업⁠그⁠레⁠이⁠드⁠로 이⁠전⁠이 중⁠단⁠됐⁠어⁠요';

  @override
  String get homeMigrationWaitingConfirmation => '확⁠인⁠을 기⁠다⁠리⁠는 중...';

  @override
  String get homeNu7FasterBody =>
      '첫 확⁠인⁠까⁠지 평⁠균 대⁠기 시⁠간⁠이 ~75⁠초⁠에⁠서 ~25⁠초⁠로 줄⁠어⁠요.';

  @override
  String get homeNu7FasterTitle => '블⁠록⁠이 ~3× 빨⁠라⁠져⁠요';

  @override
  String get homeNu7GotIt => '확⁠인⁠했⁠어⁠요';

  @override
  String get homeNu7ThroughputBody => '블⁠록⁠당 처⁠리⁠할 수 있⁠는 차⁠폐 거⁠래⁠가 2.3x 늘⁠어⁠요.';

  @override
  String get homeNu7ThroughputTitle => '차⁠폐 거⁠래 처⁠리⁠량 증⁠가';

  @override
  String get homeNu7Title => 'NU7 업⁠데⁠이⁠트⁠가 적⁠용⁠됐⁠어⁠요.\n무⁠엇⁠이 달⁠라⁠질⁠까⁠요?';

  @override
  String get homePasswordChangeUnverified =>
      '이⁠전 비⁠밀⁠번⁠호 변⁠경⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 Vizor⁠를 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get homePayInUsdc => 'USDC⁠로 결⁠제';

  @override
  String get homeReceive => '받⁠기';

  @override
  String get homeReceiveFirstZec => '첫 ZEC 받⁠기';

  @override
  String get homeRecentActivity => '최⁠근 활⁠동';

  @override
  String get homeSeeAll => '전⁠체 보⁠기';

  @override
  String get homeSend => '보⁠내⁠기';

  @override
  String get homeSetupBackupMessage =>
      '지⁠갑⁠을 백⁠업⁠하⁠세⁠요. 복⁠구 문⁠구⁠를 안⁠전⁠하⁠게 보⁠관⁠해 주⁠세⁠요.';

  @override
  String get homeSetupCarouselLabel => '지⁠갑 설⁠정';

  @override
  String get homeSetupCarouselName => '지⁠갑 설⁠정 배⁠너';

  @override
  String get homeSetupEducationMessage =>
      'Zcash⁠가 프⁠라⁠이⁠버⁠시⁠를 어⁠떻⁠게 보⁠호⁠하⁠는⁠지, 어⁠떤 주⁠소⁠를 써⁠야 하⁠는⁠지 알⁠아⁠보⁠세⁠요.';

  @override
  String get homeShield => '차⁠폐⁠하⁠기';

  @override
  String get homeShieldAfterScan => '스⁠캔⁠한 뒤 서⁠명 가⁠져⁠오⁠기⁠를 누⁠르⁠세⁠요.';

  @override
  String get homeShieldApproveTitle => 'Keystone⁠에⁠서 승⁠인⁠하⁠기';

  @override
  String get homeShieldAttentionTitle => '차⁠폐⁠에 확⁠인⁠이 필⁠요⁠해⁠요';

  @override
  String get homeShieldBackToWallet => '지⁠갑⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get homeShieldBackToWalletTitleCase => '지⁠갑⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get homeShieldBalanceTitle => '투⁠명 잔⁠액';

  @override
  String get homeShieldBroadcastNotStored =>
      '차⁠폐 거⁠래⁠가 네⁠트⁠워⁠크⁠에 전⁠달⁠됐⁠지⁠만 Vizor⁠가 기⁠기⁠에 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 동⁠기⁠화⁠나 탐⁠색⁠기⁠에⁠서 최⁠신 상⁠태⁠를 확⁠인⁠하⁠기 전⁠에⁠는 다⁠시 시⁠도⁠하⁠지 마⁠세⁠요.';

  @override
  String get homeShieldBroadcastUnknown =>
      '차⁠폐 거⁠래⁠가 네⁠트⁠워⁠크⁠에 전⁠달⁠됐⁠을 수 있⁠지⁠만 확⁠인 시⁠간⁠이 초⁠과⁠됐⁠어⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 활⁠동⁠을 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get homeShieldBroadcastingTitle => '차⁠폐 거⁠래 전⁠송 중';

  @override
  String get homeShieldCameraDenied =>
      'Keystone 서⁠명⁠을 스⁠캔⁠하⁠려⁠면 설⁠정⁠에⁠서 카⁠메⁠라 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get homeShieldCameraUnavailable => '지⁠금⁠은 카⁠메⁠라⁠를 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get homeShieldCancelFailed => '취⁠소⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get homeShieldCancelled => '차⁠폐⁠를 취⁠소⁠했⁠어⁠요.';

  @override
  String get homeShieldCancelledBeforeParams =>
      '증⁠명 매⁠개⁠변⁠수⁠를 내⁠려⁠받⁠기 전⁠에 차⁠폐⁠가 취⁠소⁠됐⁠어⁠요.';

  @override
  String get homeShieldComplete => '완⁠료';

  @override
  String get homeShieldDrag => '밀⁠어⁠서 차⁠폐⁠하⁠기';

  @override
  String get homeShieldErrorBroadcast => '차⁠폐 거⁠래⁠를 전⁠송⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeShieldErrorGeneric =>
      '잔⁠액⁠을 차⁠폐⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get homeShieldErrorNotFinalized => '차⁠폐 거⁠래⁠를 마⁠무⁠리⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeShieldErrorProvingParams =>
      '필⁠요⁠한 증⁠명 매⁠개⁠변⁠수⁠를 준⁠비⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeShieldErrorSignatureNotApplied =>
      'Keystone 서⁠명⁠을 적⁠용⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeShieldErrorSigningNotPrepared =>
      'Keystone 서⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeShieldErrorSyncFirst =>
      '투⁠명 잔⁠액⁠을 차⁠폐⁠하⁠기 전⁠에 지⁠갑⁠을 동⁠기⁠화⁠해 주⁠세⁠요.';

  @override
  String get homeShieldErrorTooSmall =>
      '수⁠수⁠료⁠를 내⁠고 나⁠면 차⁠폐⁠하⁠기⁠에⁠는 투⁠명 잔⁠액⁠이 너⁠무 적⁠어⁠요.';

  @override
  String get homeShieldFailedTitle => '차⁠폐⁠를 완⁠료⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get homeShieldGetSignature => '서⁠명 가⁠져⁠오⁠기';

  @override
  String get homeShieldKeepOpen => '거⁠래⁠를 전⁠송⁠하⁠는 동⁠안 Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String get homeShieldKeystoneQrSemantics => 'Keystone 거⁠래 QR';

  @override
  String get homeShieldNextStep => '다⁠음 단⁠계';

  @override
  String get homeShieldNoActiveAccount => '선⁠택⁠된 계⁠정⁠이 없⁠어⁠요.';

  @override
  String get homeShieldNow => '지⁠금 차⁠폐⁠하⁠기';

  @override
  String get homeShieldQueuedTitle => '차⁠폐⁠를 대⁠기⁠열⁠에 추⁠가⁠했⁠어⁠요';

  @override
  String get homeShieldReadingSignature => '서⁠명⁠을 읽⁠는 중…';

  @override
  String get homeShieldReject => '거⁠부';

  @override
  String get homeShieldScanDecodeFailed =>
      '이 QR 코⁠드⁠를 Keystone 서⁠명⁠으⁠로 읽⁠을 수 없⁠어⁠요.';

  @override
  String get homeShieldScanTitle => 'Keystone 서⁠명 스⁠캔⁠하⁠기';

  @override
  String get homeShieldScanToSign => 'QR 코⁠드⁠를 스⁠캔⁠해 서⁠명⁠하⁠세⁠요';

  @override
  String get homeShieldScanWrongQr =>
      'Keystone⁠에⁠서 서⁠명⁠된 차⁠폐 QR⁠을 열⁠고 다⁠시 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String homeShieldScanning(int progress) {
    return '스⁠캔⁠하⁠는 중… $progress%';
  }

  @override
  String get homeShieldShowQr => 'QR 보⁠기';

  @override
  String get homeShieldSignTitle => 'Keystone⁠에⁠서 거⁠래 서⁠명⁠하⁠기';

  @override
  String get homeShieldStatusUncertain =>
      '차⁠폐 거⁠래⁠의 상⁠태⁠가 불⁠확⁠실⁠해⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 활⁠동⁠을 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get homeShieldSubmitting => '거⁠래⁠를 제⁠출⁠하⁠는 중';

  @override
  String get homeShieldSucceededTitle => '차⁠폐⁠했⁠어⁠요';

  @override
  String get homeShieldToggleFlashlight => '손⁠전⁠등 켜⁠기/끄⁠기';

  @override
  String get homeShieldedBalance => '차⁠폐 잔⁠액';

  @override
  String get homeShieldingBalance => '잔⁠액⁠을 차⁠폐⁠하⁠는 중…';

  @override
  String get homeShieldingProgress => '차⁠폐⁠하⁠는 중...';

  @override
  String homeTransparentBalance(String balance) {
    return '투⁠명: $balance';
  }

  @override
  String get homeVotingSemantics => '코⁠인 보⁠유⁠자 투⁠표 열⁠기';

  @override
  String get homeVotingSubtitle => '네⁠트⁠워⁠크⁠의 방⁠향⁠을 함⁠께 정⁠해⁠요';

  @override
  String get keyringLockedBody =>
      'Vizor⁠가 시⁠스⁠템 키⁠링⁠에 접⁠근⁠할 수 없⁠어⁠요. 키⁠링 잠⁠금⁠을 해⁠제⁠한 뒤 다⁠시 시⁠도⁠를 선⁠택⁠하⁠세⁠요. 시⁠스⁠템⁠에⁠서 키⁠링 비⁠밀⁠번⁠호⁠를 물⁠어⁠볼 수 있⁠어⁠요.';

  @override
  String get keyringNoResponse => '키⁠링⁠이 응⁠답⁠하⁠지 않⁠았⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keyringOpeningTitle => 'Vizor 여⁠는 중';

  @override
  String get keyringPromptBody =>
      'Vizor⁠를 계⁠속 사⁠용⁠하⁠려⁠면 시⁠스⁠템 키⁠링 안⁠내⁠를 완⁠료⁠하⁠세⁠요.';

  @override
  String get keyringRestartHint => 'Vizor⁠를 종⁠료⁠하⁠고 다⁠시 시⁠작⁠해 주⁠세⁠요.';

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
  String get keyringUnlockTitle => '키⁠링 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요';

  @override
  String get keyringUnreadableBody =>
      'Vizor⁠가 시⁠스⁠템 키⁠링⁠의 데⁠이⁠터⁠를 읽⁠지 못⁠했⁠어⁠요. 접⁠근⁠을 복⁠구⁠한 뒤 다⁠시 시⁠도⁠하⁠거⁠나 Vizor⁠를 종⁠료⁠해 주⁠세⁠요.';

  @override
  String get keyringUnreadableTitle => '보⁠안 저⁠장⁠소⁠를 읽⁠을 수 없⁠어⁠요';

  @override
  String keystoneAccountsFound(int count) {
    return '계⁠정 $count⁠개⁠를 찾⁠았⁠어⁠요';
  }

  @override
  String get keystoneBirthdayInvalidHeight => '올⁠바⁠른 블⁠록 높⁠이⁠가 아⁠닌 것 같⁠아⁠요.';

  @override
  String get keystoneBirthdaySubtitle => '알⁠려 주⁠시⁠면 지⁠갑⁠을 더 빨⁠리 가⁠져⁠올 수 있⁠어⁠요.';

  @override
  String get keystoneCameraDeniedBody =>
      '다⁠시 요⁠청⁠하⁠거⁠나\n시⁠스⁠템 설⁠정⁠에⁠서 직⁠접 허⁠용⁠하⁠세⁠요.';

  @override
  String get keystoneCameraDeniedTitle => '카⁠메⁠라 접⁠근⁠을 거⁠부⁠했⁠어⁠요';

  @override
  String get keystoneCameraEnableBody =>
      'Keystone⁠을 연⁠결⁠하⁠려⁠면 카⁠메⁠라⁠가 필⁠요⁠해⁠요.\n나⁠중⁠에 설⁠정⁠에⁠서 언⁠제⁠든 되⁠돌⁠릴 수 있⁠어⁠요.';

  @override
  String get keystoneCameraEnableTitle => '카⁠메⁠라 접⁠근 허⁠용';

  @override
  String get keystoneCameraRequestAgain => '다⁠시 요⁠청';

  @override
  String get keystoneCameraRestrictedBody =>
      '스⁠크⁠린 타⁠임 또⁠는 기⁠기 관⁠리⁠가\n카⁠메⁠라⁠를 차⁠단⁠하⁠고 있⁠어⁠요.';

  @override
  String get keystoneCameraRestrictedTitle => '카⁠메⁠라 접⁠근⁠이 제⁠한⁠되⁠어 있⁠어⁠요';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone 가⁠져⁠오⁠기⁠는 카⁠메⁠라 QR 스⁠캔⁠만 지⁠원⁠해⁠요.\n카⁠메⁠라⁠를 연⁠결⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneCameraUnavailableTitle => '카⁠메⁠라⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get keystoneConfirmSelection => '선⁠택 확⁠인';

  @override
  String get keystoneFirmwareBody =>
      'Keystone⁠이 최⁠신 Cypherpunk 펌⁠웨⁠어⁠인⁠지 확⁠인⁠해 주⁠세⁠요. ';

  @override
  String get keystoneFirmwareDownloadSemantics => 'Keystone 펌⁠웨⁠어 다⁠운⁠로⁠드';

  @override
  String get keystoneFirmwareLinkLabel => '링⁠크';

  @override
  String get keystoneFirmwareTitle => 'Keystone 펌⁠웨⁠어 확⁠인';

  @override
  String get keystoneImReadyNow => '준⁠비⁠됐⁠어⁠요';

  @override
  String get keystoneOnVizor => 'Vizor⁠에⁠서';

  @override
  String get keystoneOnYourKeystone => 'Keystone⁠에⁠서';

  @override
  String get keystonePrepareSubtitle => 'Keystone 지⁠갑⁠을 준⁠비⁠해 주⁠세⁠요';

  @override
  String get keystonePrepareToConnectTitle => '연⁠결 준⁠비';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone 가⁠져⁠오⁠기⁠는 카⁠메⁠라⁠로 QR⁠을 스⁠캔⁠하⁠는 방⁠식⁠만 지⁠원⁠해⁠요. 카⁠메⁠라⁠를 연⁠결⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneScanCaption => 'Keystone 계⁠정 QR⁠을 스⁠캔⁠하⁠세⁠요';

  @override
  String get keystoneScanDecodeFailed =>
      '이 QR 코⁠드⁠를 Keystone Zcash 계⁠정⁠으⁠로 읽⁠지 못⁠했⁠어⁠요.';

  @override
  String get keystoneScanNoAccounts =>
      '이 Keystone QR⁠에⁠서 Zcash 계⁠정⁠을 찾⁠지 못⁠했⁠어⁠요.';

  @override
  String get keystoneScanOpenAccountQr =>
      'Keystone⁠에⁠서 Zcash 계⁠정 QR⁠을 열⁠고 다⁠시 스⁠캔⁠하⁠세⁠요.';

  @override
  String keystoneScanProgress(int progress) {
    return '스⁠캔 중... $progress%';
  }

  @override
  String get keystoneScanReadingAccounts => '계⁠정⁠을 읽⁠는 중...';

  @override
  String get keystoneStepHowToConnect => '연⁠결 방⁠법';

  @override
  String get keystoneStepOpenSoftwareWallet =>
      '오⁠른⁠쪽 위 •••를 탭⁠한 다⁠음 Connect software wallet⁠을 선⁠택⁠하⁠세⁠요.';

  @override
  String get keystoneStepScanDynamicQr =>
      'Keystone⁠에 표⁠시⁠된 동⁠적 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요.';

  @override
  String get keystoneStepSelectAccount => '계⁠정 선⁠택';

  @override
  String get keystoneStepSelectVizor => 'Vizor(또⁠는 ZODL)를 선⁠택⁠하⁠세⁠요';

  @override
  String languageSystemOption(String language) {
    return '시⁠스⁠템 ($language)';
  }

  @override
  String get ledgerAccountIndexHint =>
      '이 Ledger 계⁠정⁠에 다⁠른 인⁠덱⁠스⁠를 사⁠용⁠한 적⁠이 없⁠다⁠면 0⁠으⁠로 두⁠세⁠요.';

  @override
  String get ledgerAccountIndexLabel => '계⁠정 인⁠덱⁠스 (0–100)';

  @override
  String get ledgerAddAccountNote =>
      'Vizor⁠에⁠서 잔⁠액⁠과 활⁠동⁠을 볼 수 있⁠어⁠요. 거⁠래⁠는 여⁠전⁠히 Ledger⁠에⁠서 승⁠인⁠해⁠야 해⁠요.';

  @override
  String get ledgerAddAccountTitle => 'Ledger 계⁠정 추⁠가';

  @override
  String get ledgerAdvancedOptions => '고⁠급 옵⁠션';

  @override
  String get ledgerBalanceActivityNote =>
      'Vizor⁠에⁠서 잔⁠액⁠과 활⁠동⁠을 확⁠인⁠하⁠세⁠요.\nLedger⁠에⁠서 거⁠래⁠를 승⁠인⁠하⁠세⁠요.';

  @override
  String get ledgerBleDeclinedOpen =>
      'Ledger⁠에⁠서 Zcash 앱 열⁠기⁠를 거⁠부⁠했⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerBleDeclinedShare =>
      'Ledger⁠에⁠서 공⁠유⁠를 거⁠부⁠했⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerBleReadFailedTryAgain =>
      'Vizor⁠에⁠서 이 Ledger 계⁠정⁠을 읽⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerBleReadFailedUsb =>
      'Vizor⁠에⁠서 이 Ledger 계⁠정⁠을 읽⁠지 못⁠했⁠어⁠요. USB 케⁠이⁠블⁠로 Ledger⁠를 다⁠시 연⁠결⁠하⁠고 PIN⁠으⁠로 잠⁠금⁠을 해⁠제⁠한 다⁠음 Zcash 앱⁠을 열⁠어 주⁠세⁠요. 그⁠런 다⁠음 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerBluetoothConnection => '블⁠루⁠투⁠스 연⁠결';

  @override
  String get ledgerBluetoothPermissionRequired =>
      'Ledger⁠를 찾⁠으⁠려⁠면 블⁠루⁠투⁠스 권⁠한⁠이 필⁠요⁠해⁠요. 설⁠정⁠에⁠서 허⁠용⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerCancelFailed => '취⁠소⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerCancellingRequest => '요⁠청⁠을 취⁠소⁠하⁠는 중';

  @override
  String get ledgerCancellingTheRequest => 'Ledger 요⁠청⁠을 취⁠소⁠하⁠는 중…';

  @override
  String get ledgerCheckingBluetoothAccess => '블⁠루⁠투⁠스 접⁠근 권⁠한⁠을 확⁠인⁠하⁠는 중…';

  @override
  String get ledgerChooseAnother => '다⁠른 Ledger 선⁠택';

  @override
  String get ledgerCleanupFailed => '정⁠리⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerConfirmOpeningZcash => 'Ledger⁠에⁠서 Zcash 열⁠기⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get ledgerConnectSubtitle => 'Ledger 지⁠갑⁠을 준⁠비⁠해 주⁠세⁠요.';

  @override
  String get ledgerConnectUsbCable => 'USB 케⁠이⁠블⁠로 연⁠결⁠하⁠세⁠요.';

  @override
  String ledgerConnectingTo(String device) {
    return '$device⁠에 연⁠결⁠하⁠는 중';
  }

  @override
  String get ledgerConnectionHelp => '연⁠결 도⁠움⁠말';

  @override
  String get ledgerCouldNotConnect => 'Ledger⁠를 연⁠결⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get ledgerDiscoveryErrorFallback => '다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerDiscoveryErrorTitle => 'Ledger⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get ledgerDiscoveryFailed =>
      'Vizor⁠에⁠서 Ledger 기⁠기⁠를 찾⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerEnableBluetoothNearby =>
      '블⁠루⁠투⁠스⁠를 켜⁠고 Ledger⁠를 가⁠까⁠이⁠에 두⁠세⁠요.';

  @override
  String get ledgerErrorAlreadyAdded => '이 Ledger 계⁠정⁠은 이⁠미 Vizor⁠에 있⁠어⁠요.';

  @override
  String get ledgerErrorCannotReadCheckConnection =>
      'Vizor⁠에⁠서 이 Ledger 계⁠정⁠을 읽⁠지 못⁠했⁠어⁠요. 연⁠결⁠을 확⁠인⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String ledgerErrorCannotReadWithInstruction(String instruction) {
    return 'Vizor⁠에⁠서 이 Ledger 계⁠정⁠을 읽⁠지 못⁠했⁠어⁠요. $instruction 그⁠런 다⁠음 다⁠시 시⁠도⁠해 주⁠세⁠요.';
  }

  @override
  String ledgerErrorConnectAndUnlock(String instruction) {
    return 'Ledger⁠를 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요. $instruction';
  }

  @override
  String ledgerErrorUnlock(String instruction) {
    return 'Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요. $instruction';
  }

  @override
  String get ledgerErrorViewingKeyDeclined =>
      '[security] Ledger⁠에⁠서 뷰⁠잉 키 요⁠청⁠을 거⁠부⁠했⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerErrorViewingKeyRejected =>
      'Ledger⁠에⁠서 뷰⁠잉 키 요⁠청⁠을 거⁠부⁠했⁠어⁠요.';

  @override
  String get ledgerFind => 'Ledger 찾⁠기';

  @override
  String get ledgerFindMyLedger => '내 Ledger 찾⁠기';

  @override
  String ledgerKeepAppOpen(String appName) {
    return '$appName 앱⁠을 열⁠어 둔 채⁠로 유⁠지⁠하⁠세⁠요.';
  }

  @override
  String get ledgerKeepConnectedUntilCancelled =>
      '현⁠재 요⁠청⁠이 취⁠소⁠될 때⁠까⁠지 Ledger⁠를 연⁠결⁠해 두⁠세⁠요.';

  @override
  String get ledgerKeepConnectedWhileChecking =>
      'Vizor⁠가 앱⁠을 확⁠인⁠하⁠는 동⁠안 Ledger⁠를 연⁠결⁠해 두⁠세⁠요.';

  @override
  String get ledgerKeepNearbyUnlocked =>
      'Ledger⁠를 가⁠까⁠이⁠에 두⁠고 잠⁠금⁠을 해⁠제⁠한 상⁠태⁠로 블⁠루⁠투⁠스⁠를 켜 두⁠세⁠요.';

  @override
  String get ledgerKeepZcashOpen => 'Zcash 앱⁠을 열⁠어 둔 채⁠로 유⁠지⁠하⁠세⁠요.';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS⁠에⁠서 블⁠루⁠투⁠스 접⁠근 권⁠한⁠을 요⁠청⁠할 수 있⁠어⁠요. 요⁠청⁠이 나⁠타⁠나⁠면 Vizor⁠에 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerNoDevicesFound => 'Ledger 기⁠기⁠를 찾⁠지 못⁠했⁠어⁠요';

  @override
  String get ledgerNoDevicesFoundHint =>
      'Ledger⁠의 잠⁠금⁠이 해⁠제⁠되⁠어 있⁠는⁠지 확⁠인⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerNoneFoundDesktop =>
      'Ledger⁠를 찾⁠지 못⁠했⁠어⁠요. Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고 블⁠루⁠투⁠스⁠를 켠 다⁠음 가⁠까⁠이⁠에 두⁠세⁠요. 그⁠런 다⁠음 다⁠시 검⁠색⁠해 주⁠세⁠요.';

  @override
  String get ledgerOnYourLedger => 'Ledger⁠에⁠서';

  @override
  String get ledgerOpenBluetoothSettingsManually =>
      '블⁠루⁠투⁠스 설⁠정⁠을 직⁠접 열⁠어 기⁠존 페⁠어⁠링⁠을 삭⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerOpenZcashThenTryAgain => 'Zcash 앱⁠을 연 다⁠음 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerReturningToOptions => '연⁠결 옵⁠션⁠으⁠로 돌⁠아⁠가⁠는 중…';

  @override
  String get ledgerSearchAgain => '다⁠시 검⁠색';

  @override
  String get ledgerSearchTakesAWhile => '몇 초 정⁠도 걸⁠릴 수 있⁠어⁠요.';

  @override
  String get ledgerSearchingDevices => 'Ledger 기⁠기⁠를 검⁠색⁠하⁠는 중…';

  @override
  String get ledgerSearchingNearby => '주⁠변 Ledger⁠를 검⁠색⁠하⁠는 중…';

  @override
  String get ledgerSelectYourLedger => '사⁠용⁠할 Ledger⁠를 선⁠택⁠하⁠세⁠요.';

  @override
  String get ledgerSheetAddFailedTitle => 'Ledger 계⁠정⁠을 추⁠가⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get ledgerSheetCancelFailedTitle => 'Ledger 요⁠청⁠을 취⁠소⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get ledgerSheetDeclinedTitle => '요⁠청⁠이 거⁠부⁠됐⁠어⁠요';

  @override
  String get ledgerStepApproveViewingKey => '뷰⁠잉 키 승⁠인';

  @override
  String ledgerStepOpenApp(String appName) {
    return '$appName 열⁠기';
  }

  @override
  String get ledgerStepOpenZcash => 'Zcash 열⁠기';

  @override
  String get ledgerStoppingSearch => '검⁠색⁠을 중⁠지⁠하⁠는 중';

  @override
  String get ledgerSupportedDevices => '지⁠원 기⁠기';

  @override
  String get ledgerTransportBluetooth => '블⁠루⁠투⁠스';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerUnlockBluetoothNearby =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고 블⁠루⁠투⁠스⁠를 켠 다⁠음 가⁠까⁠이⁠에 두⁠세⁠요.';

  @override
  String get ledgerUnlockWithPin => 'PIN⁠으⁠로 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor⁠가 Zcash 앱⁠을 확⁠인⁠하⁠고 있⁠어⁠요.';

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
  String lockNavSyncing(int percent) {
    return '$percent% 동⁠기⁠화 중...';
  }

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
  String get networkSettingsTitle => '네⁠트⁠워⁠크 설⁠정';

  @override
  String get onboardingAdd => '추⁠가';

  @override
  String get onboardingAddBip39PassphraseOptional =>
      'BIP39 패⁠스⁠프⁠레⁠이⁠즈 추⁠가(선⁠택)';

  @override
  String get onboardingAddBip39PassphraseSemantics => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈 추⁠가';

  @override
  String get onboardingAddressShieldedBodyMobile =>
      '주⁠소⁠는 u1⁠로 시⁠작⁠해⁠요(예⁠전 형⁠식⁠은 zs).\n계⁠정 잔⁠액⁠과 거⁠래 내⁠역⁠은 나⁠만 볼 수 있⁠어⁠요.';

  @override
  String onboardingAddressShieldedDescription(
    String unifiedPrefix,
    String legacyPrefix,
  ) {
    return '주⁠소⁠는 $unifiedPrefix⁠로 시⁠작⁠해⁠요(예⁠전 형⁠식⁠은 $legacyPrefix). 계⁠정 잔⁠액⁠과 거⁠래 내⁠역⁠은 나⁠만 볼 수 있⁠어⁠요.';
  }

  @override
  String get onboardingAddressShieldedLabel => '차⁠폐 주⁠소';

  @override
  String get onboardingAddressShieldedTitleMobile => '차⁠폐 주⁠소';

  @override
  String get onboardingAddressTransparentDescription =>
      '주⁠소⁠는 t⁠로 시⁠작⁠하⁠며 Bitcoin⁠과 비⁠슷⁠해⁠요. 이 주⁠소⁠의 잔⁠액⁠과 거⁠래 내⁠역⁠은 누⁠구⁠나 볼 수 있⁠어⁠요.';

  @override
  String get onboardingAddressTransparentLabel => '투⁠명 주⁠소';

  @override
  String get onboardingAddressTransparentTitleMobile => '투⁠명 주⁠소';

  @override
  String get onboardingAddressTypesSubtitle =>
      'Zcash⁠에⁠는 두 가⁠지 주⁠소 유⁠형⁠이 있⁠어⁠요.\n하⁠나⁠는 프⁠라⁠이⁠버⁠시⁠용, 하⁠나⁠는 투⁠명⁠성⁠용⁠이⁠에⁠요.';

  @override
  String get onboardingAddressTypesSubtitleMobile =>
      'Zcash⁠에⁠는 두 가⁠지 주⁠소 유⁠형⁠이 있⁠어⁠요.\n하⁠나⁠는 프⁠라⁠이⁠버⁠시⁠용, 하⁠나⁠는 투⁠명⁠성⁠용⁠이⁠에⁠요.';

  @override
  String get onboardingAddressTypesTitle => 'Zcash 주⁠소 유⁠형';

  @override
  String onboardingBiometricEnableFailed(String method) {
    return '$method⁠을(를) 켜⁠지 못⁠했⁠어⁠요. 설⁠정⁠에⁠서 다⁠시 시⁠도⁠할 수 있⁠어⁠요.';
  }

  @override
  String onboardingBiometricSetUpFirst(String method) {
    return '먼⁠저 기⁠기 설⁠정⁠에⁠서 $method⁠을(를) 설⁠정⁠해 주⁠세⁠요.';
  }

  @override
  String get onboardingBiometricSubtitle =>
      '쉽⁠고 빠⁠르⁠게 로⁠그⁠인⁠하⁠는 방⁠법⁠이⁠에⁠요.\n언⁠제⁠든 암⁠호 입⁠력⁠으⁠로 다⁠시 바⁠꿀 수 있⁠어⁠요.';

  @override
  String onboardingBiometricTitle(String method) {
    return '$method(으)로\n지⁠갑 잠⁠금 해⁠제';
  }

  @override
  String get onboardingBip39PassphraseClear => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈 지⁠우⁠기';

  @override
  String get onboardingBip39PassphraseExplanation =>
      '선⁠택 사⁠항⁠인 패⁠스⁠프⁠레⁠이⁠즈(“25⁠번⁠째 단⁠어”)를 추⁠가⁠하⁠면 같⁠은 복⁠구 문⁠구⁠로 별⁠도⁠의 지⁠갑⁠을 만⁠들⁠거⁠나 가⁠져⁠올 수 있⁠어⁠요.';

  @override
  String get onboardingBip39PassphraseFieldLabel => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈';

  @override
  String get onboardingBip39PassphraseHint => '1–100⁠자';

  @override
  String get onboardingBip39PassphraseTitleOptional => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈(선⁠택)';

  @override
  String get onboardingBirthdayCantRemember => '기⁠억⁠나⁠지 않⁠아⁠요';

  @override
  String get onboardingBirthdayDateHint => 'mm/dd/yyyy';

  @override
  String get onboardingBirthdayDontRemember => '기⁠억⁠나⁠지 않⁠아⁠요';

  @override
  String get onboardingBirthdayEnterBlockHeight => '블⁠록 높⁠이 입⁠력';

  @override
  String get onboardingBirthdayEnterDate => '날⁠짜 입⁠력';

  @override
  String get onboardingBirthdayEnterMonth => '월 입⁠력';

  @override
  String get onboardingBirthdayEstimateFailed =>
      '지⁠갑 생⁠성 높⁠이⁠를 추⁠정⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String onboardingBirthdayHeightAtLeast(String height) {
    return '$height 이⁠상⁠이⁠어⁠야 해⁠요.';
  }

  @override
  String onboardingBirthdayHeightBetween(String min, String max) {
    return '$min⁠에⁠서 $max 사⁠이⁠여⁠야 해⁠요.';
  }

  @override
  String get onboardingBirthdayInvalidHeight => '올⁠바⁠른 블⁠록 높⁠이⁠가 아⁠닌 것 같⁠아⁠요';

  @override
  String get onboardingBirthdayMetadataFailed =>
      '지⁠갑 생⁠성 높⁠이 정⁠보⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get onboardingBirthdayMobileEstimateFailed =>
      '해⁠당 날⁠짜⁠의 높⁠이⁠를 추⁠정⁠하⁠지 못⁠했⁠어⁠요. 대⁠신 블⁠록 높⁠이⁠를 직⁠접 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get onboardingBirthdayMonthHint => 'mm/yyyy';

  @override
  String get onboardingBirthdayPickDate => '날⁠짜 고⁠르⁠기';

  @override
  String get onboardingBirthdayPickMonth => '월 고⁠르⁠기';

  @override
  String get onboardingBirthdaySelectDate => '날⁠짜 선⁠택';

  @override
  String get onboardingBirthdaySelectMonth => '월 선⁠택';

  @override
  String get onboardingBirthdayStatusEstimating => '높⁠이 추⁠정⁠하⁠는 중...';

  @override
  String get onboardingBirthdayStatusImporting => '지⁠갑 가⁠져⁠오⁠는 중...';

  @override
  String get onboardingBirthdayStatusPausingSync => '동⁠기⁠화 일⁠시 중⁠지⁠하⁠는 중...';

  @override
  String get onboardingBirthdaySubtitleMobile =>
      '대⁠략⁠적⁠이⁠어⁠도 괜⁠찮⁠아⁠요.\n그 시⁠점⁠부⁠터 동⁠기⁠화⁠를 시⁠작⁠해⁠요.';

  @override
  String get onboardingBirthdayTitle => '지⁠갑⁠을 대⁠략 언⁠제 만⁠들⁠었⁠나⁠요?';

  @override
  String get onboardingBlockHeight => '블⁠록 높⁠이';

  @override
  String get onboardingCheckingAccounts => '계⁠정 확⁠인⁠하⁠는 중...';

  @override
  String get onboardingClear => '지⁠우⁠기';

  @override
  String get onboardingConnectHardwareSubtitleDesktop =>
      '하⁠드⁠웨⁠어 지⁠갑⁠을 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get onboardingConnectHardwareSubtitleMobile =>
      '하⁠드⁠웨⁠어 기⁠기⁠를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get onboardingConnectHardwareTitle => '하⁠드⁠웨⁠어 지⁠갑\n연⁠결';

  @override
  String get onboardingConnectHardwareWallet => '하⁠드⁠웨⁠어 지⁠갑 연⁠결';

  @override
  String get onboardingConnectKeystone => 'Keystone 연⁠결';

  @override
  String get onboardingConnectLedger => 'Ledger 연⁠결';

  @override
  String get onboardingContinueAnywayDesktop => '그⁠래⁠도 계⁠속';

  @override
  String get onboardingContinueAnywayMobile => '그⁠래⁠도 계⁠속';

  @override
  String get onboardingCreatingWallet => '지⁠갑 만⁠드⁠는 중...';

  @override
  String get onboardingCustomiseAccount => '계⁠정 꾸⁠미⁠기';

  @override
  String get onboardingCustomiseAccountSubtitle =>
      '계⁠정 이⁠름⁠을 정⁠하⁠고 프⁠로⁠필 사⁠진⁠을 골⁠라 계⁠정⁠에 개⁠성⁠을 더⁠해 보⁠세⁠요.';

  @override
  String get onboardingDiscoverySubtitle => '가⁠져⁠올 추⁠가 계⁠정⁠을 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get onboardingDiscoveryTitle => '추⁠가 계⁠정⁠을 찾⁠았⁠어⁠요';

  @override
  String get onboardingEdit => '수⁠정';

  @override
  String get onboardingEditBip39Passphrase => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈 수⁠정';

  @override
  String get onboardingEnterPassword => '비⁠밀⁠번⁠호 입⁠력';

  @override
  String get onboardingEstimating => '추⁠정⁠하⁠는 중...';

  @override
  String get onboardingFinishSetup => '설⁠정 완⁠료';

  @override
  String get onboardingForgotPasscodeAreYouSure => '정⁠말 진⁠행⁠할⁠까⁠요?';

  @override
  String get onboardingForgotPasscodeBody =>
      '암⁠호⁠가 기⁠억⁠나⁠지 않⁠으⁠면 계⁠정⁠을 복⁠구⁠하⁠는 유⁠일⁠한 방⁠법⁠은 Vizor 앱⁠을 완⁠전⁠히 초⁠기⁠화⁠하⁠는 것⁠뿐⁠이⁠에⁠요. 모⁠든 계⁠정⁠이 삭⁠제⁠되⁠고 계⁠정⁠을 다⁠시 가⁠져⁠와⁠야 해⁠요. 공⁠유⁠하⁠지 않⁠은 기⁠프⁠트 카⁠드 링⁠크⁠는 영⁠구⁠적⁠으⁠로 사⁠라⁠져⁠요.';

  @override
  String get onboardingForgotPasscodeCantBeUndone => '되⁠돌⁠릴 수 없⁠어⁠요.\n';

  @override
  String get onboardingForgotPasscodeContinueToReset => 'Vizor 초⁠기⁠화 계⁠속';

  @override
  String get onboardingForgotPasscodeProceed => '본⁠인 책⁠임⁠하⁠에 진⁠행⁠해 주⁠세⁠요.';

  @override
  String get onboardingForgotPasscodeTitle => '암⁠호⁠를 잊⁠으⁠셨⁠나⁠요?';

  @override
  String get onboardingForgotPasscodeUnbackedWarning =>
      '계⁠정⁠의 복⁠구 문⁠구⁠를 백⁠업⁠하⁠지 않⁠았⁠다⁠면 Vizor⁠를 초⁠기⁠화⁠한 뒤⁠에⁠는 해⁠당 자⁠금⁠을 복⁠구⁠할 수 없⁠어⁠요.';

  @override
  String get onboardingForgotPassword => '비⁠밀⁠번⁠호⁠를 잊⁠으⁠셨⁠나⁠요?';

  @override
  String get onboardingGiftEducationClosing =>
      '지⁠갑⁠이 준⁠비⁠됐⁠어⁠요. Zcash⁠가 프⁠라⁠이⁠버⁠시⁠를 지⁠키⁠는 방⁠법⁠과 어⁠떤 주⁠소⁠를 써⁠야 하⁠는⁠지 알⁠아⁠보⁠세⁠요.';

  @override
  String get onboardingGiftEducationSaveFailed =>
      '진⁠행 상⁠황⁠을 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingGoBackDesktop => '돌⁠아⁠가⁠기';

  @override
  String get onboardingHardwareKeystoneOnly => 'Keystone 지⁠갑';

  @override
  String get onboardingHardwareLedgerOrKeystone => 'Ledger 또⁠는 Keystone 지⁠갑';

  @override
  String get onboardingIKnowHowToUseZcash => 'Zcash 사⁠용⁠법⁠을 알⁠아⁠요';

  @override
  String get onboardingImport => '가⁠져⁠오⁠기';

  @override
  String get onboardingImportAcceptWordCounts =>
      '12, 15, 18, 21 또⁠는 24⁠개 단⁠어⁠를 입⁠력⁠할 수 있⁠어⁠요.';

  @override
  String get onboardingImportCheckFailedError => '복⁠구 문⁠구⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get onboardingImportClipboardEmpty => '클⁠립⁠보⁠드⁠가 비⁠어 있⁠어⁠요';

  @override
  String get onboardingImportClipboardReadError => '클⁠립⁠보⁠드⁠를 읽⁠을 수 없⁠어⁠요';

  @override
  String get onboardingImportEnterManuallySemantics => '복⁠구 문⁠구 직⁠접 입⁠력';

  @override
  String get onboardingImportFromKeystone => 'Keystone 지⁠갑⁠에⁠서 가⁠져⁠오⁠기';

  @override
  String get onboardingImportFromLedger => 'Ledger 지⁠갑⁠에⁠서 가⁠져⁠오⁠기';

  @override
  String get onboardingImportInvalidPhraseError => '올⁠바⁠르⁠지 않⁠은 복⁠구 문⁠구⁠예⁠요';

  @override
  String get onboardingImportInvalidSecretPassphrase =>
      '12, 15, 18, 21 또⁠는 24⁠개 단⁠어⁠로 된 올⁠바⁠른 복⁠구 문⁠구⁠를 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get onboardingImportManualCardSubtitle => '단⁠어⁠를 하⁠나⁠씩 입⁠력⁠해⁠요.';

  @override
  String get onboardingImportManualCardTitle => '복⁠구 문⁠구\n직⁠접 입⁠력';

  @override
  String get onboardingImportMethodSubtitle => '원⁠하⁠는 방⁠법⁠을 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get onboardingImportMethodTitle => 'Vizor⁠로\n계⁠정 가⁠져⁠오⁠기';

  @override
  String get onboardingImportNoPhraseError => '복⁠구 문⁠구⁠를 찾⁠을 수 없⁠어⁠요';

  @override
  String get onboardingImportPasteFromClipboard => '또⁠는 클⁠립⁠보⁠드⁠에⁠서 붙⁠여⁠넣⁠기';

  @override
  String get onboardingImportPasteHelper =>
      '12, 15, 18, 21 또⁠는 24⁠개 단⁠어⁠로 된\n복⁠구 문⁠구⁠를 입⁠력⁠할 수 있⁠어⁠요';

  @override
  String get onboardingImportReadingClipboard => '클⁠립⁠보⁠드 읽⁠는 중...';

  @override
  String get onboardingImportSecretPassphrase => '복⁠구 문⁠구 가⁠져⁠오⁠기';

  @override
  String get onboardingImportSecretPassphraseDescriptionDesktop =>
      'Vizor 또⁠는 다⁠른 Zcash 지⁠갑';

  @override
  String get onboardingImportSecretPassphraseDescriptionMobile =>
      'Vizor, ZODL 또⁠는 다⁠른 지⁠갑';

  @override
  String get onboardingImportWalletTitle => '지⁠갑 가⁠져⁠오⁠기';

  @override
  String get onboardingImportWalletTitleMobile => '지⁠갑 가⁠져⁠오⁠기';

  @override
  String get onboardingIntroCard =>
      'Bitcoin⁠이⁠나 Ethereum⁠과 달⁠리 차⁠폐⁠된 Zcash 거⁠래⁠는 보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액⁠을 숨⁠겨⁠요. 신⁠뢰⁠가 아⁠니⁠라 암⁠호⁠학⁠으⁠로 검⁠증⁠돼⁠요.';

  @override
  String get onboardingIntroClosing =>
      '첫 프⁠라⁠이⁠빗 지⁠갑⁠까⁠지 몇 단⁠계⁠만 남⁠았⁠어⁠요.\n함⁠께 설⁠정⁠해 볼⁠까⁠요.';

  @override
  String get onboardingIntroClosingMobile =>
      '첫 프⁠라⁠이⁠빗 지⁠갑⁠까⁠지 몇 단⁠계⁠만 남⁠았⁠어⁠요. 함⁠께 설⁠정⁠해 볼⁠까⁠요.';

  @override
  String get onboardingIntroSubtitle =>
      'Zcash(ZEC)는 금⁠융 프⁠라⁠이⁠버⁠시⁠와 자⁠기 수⁠탁⁠을 중⁠심⁠으⁠로 만⁠들⁠어⁠졌⁠어⁠요.';

  @override
  String get onboardingIntroSubtitleMobile =>
      'Zcash(ZEC)는 금⁠융 프⁠라⁠이⁠버⁠시⁠와\n자⁠기 수⁠탁⁠을 중⁠심⁠으⁠로 만⁠들⁠어⁠졌⁠어⁠요.';

  @override
  String get onboardingIntroTitle => '차⁠폐⁠된 세⁠상';

  @override
  String get onboardingLinkVizorDesktop => 'Vizor 데⁠스⁠크⁠톱 연⁠결';

  @override
  String get onboardingLinkVizorDesktopDescription =>
      '스⁠캔⁠해⁠서 Vizor 데⁠스⁠크⁠톱⁠에 연⁠결';

  @override
  String get onboardingLoading => '불⁠러⁠오⁠는 중';

  @override
  String onboardingLostPasswordBody(String resetAction, String importAction) {
    return '비⁠밀⁠번⁠호⁠를 잊⁠으⁠셨⁠다⁠면 계⁠정⁠을 복⁠구⁠하⁠는 유⁠일⁠한 방⁠법⁠은 $resetAction⁠뿐⁠이⁠에⁠요.\n모⁠든 계⁠정⁠과 공⁠유⁠하⁠지 않⁠은 기⁠프⁠트 카⁠드 링⁠크⁠가 삭⁠제⁠돼⁠요.\n이⁠후⁠에⁠는 $importAction.';
  }

  @override
  String get onboardingLostPasswordImportAction => '계⁠정⁠을 다⁠시 가⁠져⁠와⁠야 해⁠요';

  @override
  String get onboardingLostPasswordResetAction => 'Vizor 앱⁠을 완⁠전⁠히 초⁠기⁠화⁠하⁠는 것';

  @override
  String onboardingLostPasswordResetCountdown(int seconds) {
    return '$seconds⁠초 후 초⁠기⁠화...';
  }

  @override
  String get onboardingLostPasswordTitle => '비⁠밀⁠번⁠호⁠를 잊⁠으⁠셨⁠나⁠요?';

  @override
  String get onboardingManualInvalidWord => '복⁠구 문⁠구⁠에 없⁠는 단⁠어⁠예⁠요.';

  @override
  String get onboardingManualNextWord => '다⁠음 단⁠어';

  @override
  String get onboardingManualReviewFinish => '검⁠토⁠하⁠고 완⁠료';

  @override
  String onboardingManualStoppedAt(String word) {
    return '\'$word\'에⁠서 멈⁠췄⁠어⁠요. 복⁠구 문⁠구 단⁠어 목⁠록⁠에 없⁠는 단⁠어⁠예⁠요.';
  }

  @override
  String get onboardingManualSubtitle =>
      '12, 15, 18, 21 또⁠는 24⁠개 단⁠어⁠를 입⁠력⁠할 수 있⁠어⁠요';

  @override
  String get onboardingManualTitle => '복⁠구 문⁠구 입⁠력';

  @override
  String get onboardingManualUndoLastWord => '마⁠지⁠막 단⁠어 취⁠소';

  @override
  String get onboardingNetworkCheckingEndpoint => '엔⁠드⁠포⁠인⁠트 확⁠인⁠하⁠는 중…';

  @override
  String get onboardingNetworkEndpointHelper =>
      '이 지⁠갑⁠의 네⁠트⁠워⁠크⁠용 lightwalletd 서⁠버⁠를 사⁠용⁠하⁠세⁠요.';

  @override
  String get onboardingNetworkSaveFailed =>
      '엔⁠드⁠포⁠인⁠트⁠를 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingNetworkVerifyFailed =>
      '해⁠당 엔⁠드⁠포⁠인⁠트⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 주⁠소⁠를 확⁠인⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingNext => '다⁠음';

  @override
  String get onboardingNotNow => '나⁠중⁠에';

  @override
  String get onboardingPasscodeCreateTitle => '암⁠호 만⁠들⁠기';

  @override
  String onboardingPasscodeDigitSemantics(int digit) {
    return '숫⁠자 $digit';
  }

  @override
  String get onboardingPasscodeReEnter => '암⁠호⁠를 다⁠시 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get onboardingPasscodeSettingUp => '지⁠갑⁠을 설⁠정⁠하⁠는 중...';

  @override
  String get onboardingRandomiseAccountPersona =>
      '계⁠정 이⁠름⁠과 프⁠로⁠필 사⁠진 무⁠작⁠위⁠로 바⁠꾸⁠기';

  @override
  String get onboardingRecoveringWallet => '지⁠갑 복⁠구⁠하⁠는 중...';

  @override
  String get onboardingResetAppFailed =>
      '앱⁠을 초⁠기⁠화⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingResumeSetupFailed =>
      '설⁠정⁠을 이⁠어⁠가⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingRetrySetup => '설⁠정 다⁠시 시⁠도';

  @override
  String get onboardingRetrying => '다⁠시 시⁠도⁠하⁠는 중';

  @override
  String get onboardingReviewClearSecretPassphrase => '복⁠구 문⁠구 지⁠우⁠기';

  @override
  String get onboardingReviewConfirmContinue => '확⁠인⁠하⁠고 계⁠속';

  @override
  String get onboardingReviewImportSubtitle =>
      '가⁠져⁠오⁠기⁠를 시⁠작⁠하⁠기 전⁠에\n복⁠구 문⁠구⁠를 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get onboardingReviewImportTitle => '가⁠져⁠오⁠기 검⁠토';

  @override
  String get onboardingSave => '저⁠장';

  @override
  String get onboardingSavingWallet => '지⁠갑 저⁠장⁠하⁠는 중...';

  @override
  String get onboardingSecretPassphraseAboutToSee => '곧 복⁠구 문⁠구⁠가 표⁠시⁠돼⁠요.';

  @override
  String get onboardingSecretPassphraseAboutToSeeMobile =>
      '곧 복⁠구 문⁠구⁠가\n표⁠시⁠돼⁠요.';

  @override
  String get onboardingSecretPassphraseReveal => '문⁠구 보⁠기';

  @override
  String get onboardingSecretPassphraseRevealMobile => '문⁠구 보⁠기';

  @override
  String get onboardingSecretPassphraseSubtitleDesktop => '지⁠갑⁠의 마⁠스⁠터 키⁠예⁠요.';

  @override
  String get onboardingSecretPassphraseSubtitleMobile => '지⁠갑⁠의 마⁠스⁠터 키⁠예⁠요.';

  @override
  String get onboardingSecretPassphraseWarning =>
      '이 문⁠구⁠는 내 자⁠금⁠의 마⁠스⁠터 키⁠예⁠요. 안⁠전⁠하⁠게 보⁠관⁠하⁠고 절⁠대 공⁠개⁠하⁠지 마⁠세⁠요. 잃⁠어⁠버⁠리⁠면 누⁠구⁠도 지⁠갑 복⁠구⁠를 도⁠와⁠줄 수 없⁠어⁠요. 저⁠희⁠도 마⁠찬⁠가⁠지⁠예⁠요.';

  @override
  String get onboardingSeedWordHint => '단⁠어';

  @override
  String get onboardingSetPasswordAndFinish => '비⁠밀⁠번⁠호 설⁠정⁠하⁠고 완⁠료';

  @override
  String get onboardingSetPasswordPlaceholder => '8⁠자 이⁠상, 기⁠호 포⁠함';

  @override
  String get onboardingSetPasswordSubtitle =>
      'Vizor 지⁠갑⁠에 로⁠그⁠인⁠할 비⁠밀⁠번⁠호⁠를 설⁠정⁠해 주⁠세⁠요.';

  @override
  String get onboardingSettingPassword => '비⁠밀⁠번⁠호 설⁠정⁠하⁠는 중...';

  @override
  String get onboardingSetupInterrupted =>
      '설⁠정⁠이 중⁠단⁠됐⁠어⁠요. 다⁠시 시⁠도⁠해⁠서 지⁠갑⁠을 복⁠구⁠해 주⁠세⁠요.';

  @override
  String get onboardingStepAddressTypes => '주⁠소 유⁠형';

  @override
  String get onboardingStepCustomiseWallet => '지⁠갑 꾸⁠미⁠기';

  @override
  String get onboardingStepImportContacts => '연⁠락⁠처 가⁠져⁠오⁠기';

  @override
  String get onboardingStepIntroToZcash => 'Zcash 소⁠개';

  @override
  String get onboardingStepSetPassword => '비⁠밀⁠번⁠호 설⁠정';

  @override
  String get onboardingStepWalletBirthdayHeight => '지⁠갑 생⁠성 높⁠이';

  @override
  String get onboardingStopSyncing => '동⁠기⁠화⁠를 중⁠지⁠하⁠는 중...';

  @override
  String get onboardingStorageDbMigrationBody =>
      '이 버⁠전⁠을 열⁠려⁠면 Vizor⁠가 로⁠컬 지⁠갑 데⁠이⁠터⁠베⁠이⁠스⁠를 업⁠데⁠이⁠트⁠해⁠야 해⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 Vizor⁠를 종⁠료⁠한 뒤 다⁠시 실⁠행⁠해 주⁠세⁠요.';

  @override
  String get onboardingStorageDbMigrationTitle =>
      '지⁠갑 데⁠이⁠터⁠베⁠이⁠스⁠를 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get onboardingStorageKeyringLockedBody =>
      '지⁠갑⁠을 열⁠려⁠면 Vizor⁠가 시⁠스⁠템 키⁠링⁠에 접⁠근⁠할 수 있⁠어⁠야 해⁠요. 키⁠링⁠을 잠⁠금 해⁠제⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingStorageRetrySecureStorageFailed =>
      '보⁠안 저⁠장⁠소⁠를 아⁠직 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get onboardingStorageRetryWalletDbFailed =>
      '지⁠갑 데⁠이⁠터⁠베⁠이⁠스 업⁠데⁠이⁠트⁠에 또 실⁠패⁠했⁠어⁠요.';

  @override
  String get onboardingStorageSecureStorageLockedBody =>
      '지⁠갑⁠을 열⁠려⁠면 Vizor⁠가 보⁠안 저⁠장⁠소⁠에 접⁠근⁠할 수 있⁠어⁠야 해⁠요. 보⁠안 저⁠장⁠소⁠를 잠⁠금 해⁠제⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingStorageSecureStorageLockedTitle =>
      '보⁠안 저⁠장⁠소⁠가 잠⁠겨 있⁠어⁠요';

  @override
  String get onboardingStorageStartupFailureBody =>
      'Vizor⁠가 로⁠컬 시⁠작 상⁠태⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 Vizor⁠를 종⁠료⁠한 뒤 다⁠시 실⁠행⁠해 주⁠세⁠요.';

  @override
  String get onboardingTellMeHowZcashWorks => 'Zcash 작⁠동 방⁠식 알⁠아⁠보⁠기';

  @override
  String get onboardingThingsKeepPrivacyBody =>
      '일⁠부 거⁠래⁠소⁠는 차⁠폐 주⁠소⁠로 보⁠낼 수 없⁠어⁠요. 거⁠래⁠소⁠에⁠서 출⁠금⁠한⁠다⁠면 투⁠명 주⁠소⁠를 사⁠용⁠하⁠세⁠요. ZEC⁠가 도⁠착⁠한 뒤⁠에 차⁠폐⁠할 수 있⁠어⁠요.';

  @override
  String get onboardingThingsKeepPrivacyTitle => '프⁠라⁠이⁠버⁠시 지⁠키⁠는 방⁠법';

  @override
  String get onboardingThingsSubtitleMobile => '시⁠작⁠하⁠기 전⁠에 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get onboardingThingsTimeToSyncBody =>
      '지⁠갑⁠은 서⁠버⁠에 의⁠존⁠하⁠지 않⁠고 Zcash 네⁠트⁠워⁠크⁠와 직⁠접 동⁠기⁠화⁠해⁠요. 프⁠라⁠이⁠버⁠시⁠는 지⁠켜⁠지⁠지⁠만 시⁠간⁠이 조⁠금 걸⁠려⁠요. 앱⁠이 따⁠라⁠잡⁠는 동⁠안⁠에⁠도 자⁠금⁠은 안⁠전⁠해⁠요.';

  @override
  String get onboardingThingsTimeToSyncTitle => '동⁠기⁠화 시⁠간';

  @override
  String get onboardingThingsToKnow => '알⁠아 두⁠세⁠요';

  @override
  String get onboardingUnknownHeightBody =>
      '지⁠갑 생⁠성 높⁠이 없⁠이 계⁠속⁠하⁠면 Vizor⁠가 지⁠원⁠하⁠는 가⁠장 오⁠래⁠된 차⁠폐 높⁠이⁠부⁠터 스⁠캔⁠해⁠요. 안⁠전⁠하⁠지⁠만 첫 동⁠기⁠화⁠에 아⁠주 오⁠랜 시⁠간⁠이 걸⁠릴 수 있⁠어⁠요.';

  @override
  String get onboardingUnknownHeightHint => '대⁠략⁠적⁠인 날⁠짜⁠만 골⁠라⁠도 훨⁠씬 빨⁠라⁠요.';

  @override
  String get onboardingUnknownHeightTitle => '가⁠장 오⁠래⁠된 높⁠이⁠부⁠터 가⁠져⁠올⁠까⁠요?';

  @override
  String get onboardingUnlockBiometricReason => '지⁠갑 잠⁠금 해⁠제';

  @override
  String get onboardingUnlockDescription =>
      'Vizor⁠를 열⁠려⁠면 비⁠밀⁠번⁠호⁠를 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get onboardingUnlockEnterPasscode => 'Vizor⁠를 열⁠려⁠면 암⁠호⁠를 입⁠력⁠해 주⁠세⁠요';

  @override
  String get onboardingUnlockIncorrectPassword =>
      '비⁠밀⁠번⁠호⁠가 맞⁠지 않⁠아⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingUnlockOpenFailed =>
      '지⁠갑⁠을 열⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get onboardingUnlockOpening => '지⁠갑⁠을 여⁠는 중...';

  @override
  String get onboardingUnlockWelcomeBack => '다⁠시 오⁠신 것⁠을 환⁠영⁠해⁠요';

  @override
  String get onboardingWelcome => '시⁠작 화⁠면';

  @override
  String get onboardingWelcomeActivateGiftCard => '기⁠프⁠트 카⁠드 활⁠성⁠화';

  @override
  String get onboardingWelcomeGetStarted => '시⁠작⁠하⁠기';

  @override
  String get onboardingWelcomeImportWallet => '지⁠갑 가⁠져⁠오⁠기';

  @override
  String get passcodeConfirmTitle => '암⁠호 확⁠인';

  @override
  String get passcodeIncorrect => '암⁠호⁠가 맞⁠지 않⁠아⁠요';

  @override
  String get passcodeSixDigits => '6⁠자⁠리 숫⁠자';

  @override
  String get passcodesDidNotMatch => '암⁠호⁠가 일⁠치⁠하⁠지 않⁠아⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get passwordCheckFailed =>
      '비⁠밀⁠번⁠호⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get passwordConfirmLabel => '비⁠밀⁠번⁠호 확⁠인';

  @override
  String get passwordIncorrect => '비⁠밀⁠번⁠호⁠가 맞⁠지 않⁠아⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get passwordLabel => '비⁠밀⁠번⁠호';

  @override
  String get passwordsDoNotMatch => '비⁠밀⁠번⁠호⁠가 일⁠치⁠하⁠지 않⁠아⁠요.';

  @override
  String get poolShielded => '차⁠폐⁠됨';

  @override
  String get poolTransparent => '투⁠명';

  @override
  String get profilePictureChange => '프⁠로⁠필 사⁠진 변⁠경';

  @override
  String get profilePictureSelect => '프⁠로⁠필 사⁠진 선⁠택';

  @override
  String get profilePictureUpdateFailed => '프⁠로⁠필 사⁠진⁠을 바⁠꾸⁠지 못⁠했⁠어⁠요.';

  @override
  String get receiptMessageLabel => '메⁠시⁠지';

  @override
  String get secretPassphraseCopy => '복⁠구 문⁠구 복⁠사';

  @override
  String get secretPassphraseTitle => '복⁠구 문⁠구';

  @override
  String get settingsAccountChangedPasscode =>
      '선⁠택⁠한 계⁠정⁠이 바⁠뀌⁠었⁠어⁠요. 암⁠호⁠를 다⁠시 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get settingsAccountChangedPassword =>
      '선⁠택⁠한 계⁠정⁠이 바⁠뀌⁠었⁠어⁠요. 비⁠밀⁠번⁠호⁠를 다⁠시 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get settingsAccountUnavailable => '선⁠택⁠한 계⁠정⁠을 더 이⁠상 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get settingsBackToAccounts => '계⁠정⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String settingsBiometricOffToast(String feature) {
    return '$feature 꺼⁠짐';
  }

  @override
  String settingsBiometricOnToast(String feature) {
    return '$feature 켜⁠짐';
  }

  @override
  String settingsBiometricSetupFirst(String biometric) {
    return '먼⁠저 기⁠기 설⁠정⁠에⁠서 $biometric⁠을(를) 설⁠정⁠하⁠세⁠요.';
  }

  @override
  String settingsBiometricTurnOffBody(String feature) {
    return 'Vizor⁠는 암⁠호⁠로 잠⁠금 해⁠제⁠해⁠요. $feature⁠은(는) 언⁠제⁠든 설⁠정⁠에⁠서 다⁠시 켤 수 있⁠어⁠요.';
  }

  @override
  String settingsBiometricTurnOffTitle(String feature) {
    return '$feature⁠을(를) 끌⁠까⁠요?';
  }

  @override
  String settingsBiometricUpdateFailed(String feature) {
    return '$feature⁠을(를) 변⁠경⁠하⁠지 못⁠했⁠어⁠요.';
  }

  @override
  String get settingsBip39PassphraseCopied => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get settingsBip39PassphraseCopy => 'BIP39 패⁠스⁠프⁠레⁠이⁠즈 복⁠사';

  @override
  String get settingsBirthdayBlockHeight => '생⁠성 블⁠록 높⁠이';

  @override
  String get settingsBirthdayDate => '생⁠성 날⁠짜';

  @override
  String get settingsBirthdayDateCopied => '생⁠성 날⁠짜⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get settingsBirthdayHeightCopied => '생⁠성 블⁠록 높⁠이⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get settingsConfirmAccessSubtitle => '본⁠인 확⁠인⁠이 필⁠요⁠해⁠요';

  @override
  String get settingsConfirmAccessTitle => '접⁠근 확⁠인';

  @override
  String settingsCopyLabel(String label) {
    return '$label 복⁠사';
  }

  @override
  String settingsCopyLabelCopied(String label) {
    return '$label 복⁠사⁠됨';
  }

  @override
  String settingsEndpointBalanceNote(String ticker) {
    return '지⁠갑⁠에⁠는 마⁠지⁠막⁠으⁠로 연⁠결⁠에 성⁠공⁠했⁠을 때⁠의 잔⁠액⁠이 표⁠시⁠돼⁠요. 최⁠근⁠에 받⁠은 $ticker⁠는 표⁠시⁠되⁠지 않⁠아⁠요.';
  }

  @override
  String get settingsEndpointCloseSettings => '엔⁠드⁠포⁠인⁠트 설⁠정 닫⁠기';

  @override
  String get settingsEndpointConnectFailed =>
      '엔⁠드⁠포⁠인⁠트⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요. 호⁠스⁠트⁠와 포⁠트⁠를 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get settingsEndpointCurrentPrefix => '현⁠재: ';

  @override
  String get settingsEndpointCustomise => '엔⁠드⁠포⁠인⁠트 직⁠접 설⁠정';

  @override
  String get settingsEndpointCustomize => '엔⁠드⁠포⁠인⁠트 직⁠접 설⁠정';

  @override
  String get settingsEndpointDefaultMarker => '(기⁠본⁠값)';

  @override
  String get settingsEndpointSelectFromList => '목⁠록⁠에⁠서 선⁠택';

  @override
  String get settingsEndpointTitle => '엔⁠드⁠포⁠인⁠트';

  @override
  String get settingsEndpointUpdating => '엔⁠드⁠포⁠인⁠트 업⁠데⁠이⁠트 중...';

  @override
  String get settingsEndpointWarningBlockchain =>
      '엔⁠드⁠포⁠인⁠트⁠를 잘⁠못 설⁠정⁠하⁠면 지⁠갑⁠이 Zcash 블⁠록⁠체⁠인⁠과 동⁠기⁠화⁠되⁠지 않⁠아⁠요.';

  @override
  String get settingsEndpointWarningNetwork =>
      '엔⁠드⁠포⁠인⁠트⁠를 잘⁠못 설⁠정⁠하⁠면 지⁠갑⁠이 Zcash 네⁠트⁠워⁠크⁠와 동⁠기⁠화⁠되⁠지 않⁠아⁠요.';

  @override
  String get settingsEndpointsTitle => '엔⁠드⁠포⁠인⁠트';

  @override
  String get settingsEnterCurrentPasswordAgain =>
      '현⁠재 비⁠밀⁠번⁠호⁠를 다⁠시 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get settingsEnterCurrentPasswordFirst =>
      '먼⁠저 현⁠재 비⁠밀⁠번⁠호⁠를 입⁠력⁠하⁠세⁠요.';

  @override
  String get settingsEnterPasscodeTitle => '암⁠호 입⁠력';

  @override
  String settingsExplorerCurrent(String explorer) {
    return '현⁠재: $explorer';
  }

  @override
  String settingsExplorerCurrentDefault(String host) {
    return '현⁠재: $host (기⁠본⁠값)';
  }

  @override
  String get settingsExplorerCustom => '직⁠접 입⁠력';

  @override
  String get settingsExplorerCustomSubtitle => '원⁠하⁠는 탐⁠색⁠기⁠를 사⁠용⁠해⁠요';

  @override
  String get settingsExplorerSaveFailed => '탐⁠색⁠기 URL⁠을 저⁠장⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get settingsExplorerTitle => '블⁠록 탐⁠색⁠기';

  @override
  String get settingsExplorerUpdate => '탐⁠색⁠기 업⁠데⁠이⁠트';

  @override
  String get settingsExplorerUrlLabel => '탐⁠색⁠기 URL';

  @override
  String get settingsIncorrectPasscode => '암⁠호⁠가 맞⁠지 않⁠아⁠요';

  @override
  String get settingsKeepAwakeDescription =>
      '휴⁠대⁠폰⁠이 잠⁠자⁠기 모⁠드⁠로 전⁠환⁠되⁠지 않⁠아 동⁠기⁠화⁠가 더 빨⁠리 끝⁠나⁠요. 앱⁠은 1⁠분⁠간 사⁠용⁠하⁠지 않⁠으⁠면 그⁠대⁠로 잠⁠겨⁠요.';

  @override
  String get settingsKeepAwakeUpdateFailed =>
      '화⁠면 켜⁠짐 유⁠지 설⁠정⁠을 변⁠경⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get settingsLanguageLabel => '언⁠어';

  @override
  String get settingsLanguageUpdateFailed => '언⁠어⁠를 바⁠꾸⁠지 못⁠했⁠어⁠요.';

  @override
  String get settingsNewBadge => '신⁠규';

  @override
  String get settingsNoActiveAccount => '선⁠택⁠된 계⁠정⁠이 없⁠어⁠요.';

  @override
  String get settingsPasscodeCheckFailed =>
      '암⁠호⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsPasscodeMustDiffer => '새 암⁠호⁠는 기⁠존 암⁠호⁠와 달⁠라⁠야 해⁠요.';

  @override
  String get settingsPasscodeRotationRecoveryFailed =>
      '이⁠전 암⁠호 변⁠경⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 복⁠구 문⁠구⁠를 준⁠비⁠해 두⁠세⁠요.';

  @override
  String get settingsPasscodeUpdateFailed =>
      '암⁠호⁠를 변⁠경⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsPasscodeUpdatedToast => '암⁠호⁠를 변⁠경⁠했⁠어⁠요';

  @override
  String get settingsPasscodeVerifyFailed =>
      '암⁠호⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsPasswordHint => '비⁠밀⁠번⁠호 입⁠력...';

  @override
  String get settingsPasswordMinimumHint =>
      '8⁠자 이⁠상⁠이⁠어⁠야 해⁠요. 숫⁠자⁠와 기⁠호⁠를 더⁠하⁠거⁠나 더 길⁠게 만⁠들⁠면 더 안⁠전⁠해⁠요.';

  @override
  String get settingsPasswordRotationRecoveryFailed =>
      '이⁠전 비⁠밀⁠번⁠호 변⁠경⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 복⁠구 문⁠구⁠를 준⁠비⁠해 두⁠세⁠요.';

  @override
  String get settingsPasswordUpdateFailed =>
      '비⁠밀⁠번⁠호⁠를 변⁠경⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsPfpKnight => '기⁠사';

  @override
  String get settingsPfpSamurai => '사⁠무⁠라⁠이';

  @override
  String get settingsPfpViking => '바⁠이⁠킹';

  @override
  String get settingsPfpWizard => '마⁠법⁠사';

  @override
  String get settingsPirCheckingUpdates => '업⁠데⁠이⁠트 확⁠인 중…';

  @override
  String get settingsPirChooseServer => '서⁠버 선⁠택';

  @override
  String get settingsPirConfigOpenFailed => '설⁠정 저⁠장⁠소⁠를 열⁠지 못⁠했⁠어⁠요.';

  @override
  String get settingsPirCustomInvalid =>
      '저⁠장⁠된 사⁠용⁠자 지⁠정 서⁠버⁠가 올⁠바⁠르⁠지 않⁠아⁠요. 수⁠정⁠하⁠거⁠나 다⁠른 서⁠버⁠를 선⁠택⁠하⁠세⁠요.';

  @override
  String get settingsPirCustomServer => '사⁠용⁠자 지⁠정 서⁠버';

  @override
  String get settingsPirCustomServerEllipsis => '사⁠용⁠자 지⁠정 서⁠버…';

  @override
  String get settingsPirCustomUrlInvalid =>
      '자⁠격 증⁠명, 쿼⁠리, 프⁠래⁠그⁠먼⁠트⁠가 없⁠는 HTTPS 기⁠본 URL⁠을 입⁠력⁠하⁠세⁠요.';

  @override
  String get settingsPirEditCustomServer => '사⁠용⁠자 지⁠정 서⁠버 편⁠집…';

  @override
  String get settingsPirListLoadFailed =>
      '서⁠버 목⁠록⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 사⁠용⁠자 지⁠정 서⁠버⁠를 입⁠력⁠하⁠세⁠요.';

  @override
  String get settingsPirListUpdateFailed =>
      '서⁠버 목⁠록⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요. 마⁠지⁠막⁠으⁠로 불⁠러⁠온 목⁠록⁠을 사⁠용⁠해⁠요.';

  @override
  String get settingsPirListUpdateFailedCustom =>
      '목⁠록⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요. 사⁠용⁠자 지⁠정 서⁠버⁠가 계⁠속 선⁠택⁠되⁠어 있⁠어⁠요.';

  @override
  String get settingsPirLoadingServers => '서⁠버 목⁠록⁠을 불⁠러⁠오⁠는 중…';

  @override
  String get settingsPirNoServers =>
      '아⁠직 제⁠공⁠되⁠는 서⁠버⁠가 없⁠어⁠요. 사⁠용⁠자 지⁠정 서⁠버⁠를 입⁠력⁠할 수 있⁠어⁠요.';

  @override
  String get settingsPirServerChangeFailed =>
      '서⁠버⁠를 변⁠경⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsPirServerCloseLabel => '비⁠공⁠개 조⁠회 서⁠버 설⁠정 닫⁠기';

  @override
  String get settingsPirServerRemoved =>
      '선⁠택⁠한 서⁠버⁠가 더 이⁠상 제⁠공⁠되⁠지 않⁠아⁠요. 비⁠공⁠개 조⁠회⁠를 다⁠시 시⁠작⁠하⁠려⁠면 다⁠른 서⁠버⁠를 선⁠택⁠하⁠세⁠요.';

  @override
  String get settingsPirServerSettingsLabel => '비⁠공⁠개 조⁠회 서⁠버 설⁠정';

  @override
  String get settingsPirServerTitle => '비⁠공⁠개 조⁠회 서⁠버';

  @override
  String get settingsPirSettingsReadFailed =>
      '비⁠공⁠개 조⁠회 서⁠버 설⁠정⁠을 읽⁠지 못⁠했⁠어⁠요.';

  @override
  String get settingsPirShareServer => '내 서⁠버 공⁠유';

  @override
  String get settingsPirUnavailable =>
      '이 네⁠트⁠워⁠크⁠에⁠서⁠는 비⁠공⁠개 조⁠회⁠를 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get settingsPirUpdatingServer => '서⁠버 변⁠경 중…';

  @override
  String get settingsPirUseCustomServer => '사⁠용⁠자 지⁠정 서⁠버 사⁠용';

  @override
  String get settingsPrivacyTitle => '개⁠인⁠정⁠보 보⁠호';

  @override
  String get settingsPrivateQueriesLabel => '비⁠공⁠개 조⁠회';

  @override
  String get settingsPrivateQueriesTurnOffBody =>
      'Vizor⁠가 투⁠명 내⁠역⁠을 공⁠개 방⁠식⁠으⁠로 다⁠시 구⁠성⁠하⁠며, 서⁠버⁠가 모⁠든 주⁠소⁠를 알⁠게 돼⁠요.';

  @override
  String get settingsPrivateQueriesTurnOffDisclosure =>
      '서⁠버⁠가 모⁠든 계⁠정⁠의 투⁠명 주⁠소 전⁠부⁠와 비⁠공⁠개 복⁠구⁠로 찾⁠은 거⁠래 ID⁠를 받⁠아⁠요. 서⁠버⁠는 이⁠를 서⁠로 연⁠결⁠할 수 있⁠고, Tor⁠를 쓰⁠지 않⁠으⁠면 IP 주⁠소⁠와⁠도 연⁠결⁠할 수 있⁠어⁠요.';

  @override
  String get settingsPrivateQueriesTurnOffTitle => '비⁠공⁠개 조⁠회⁠를 끌⁠까⁠요?';

  @override
  String get settingsProfilePictureCustom => '사⁠용⁠자 지⁠정';

  @override
  String get settingsRowAboutVizor => 'Vizor 정⁠보';

  @override
  String get settingsRowAccountNameMobile => '계⁠정 이⁠름';

  @override
  String get settingsRowAddressBook => '주⁠소⁠록';

  @override
  String get settingsRowChangePasscode => '암⁠호 변⁠경';

  @override
  String get settingsRowChangePassword => '비⁠밀⁠번⁠호 변⁠경';

  @override
  String get settingsRowLinkMobile => 'Vizor 모⁠바⁠일 연⁠결';

  @override
  String get settingsRowMyGiftCards => '내 기⁠프⁠트 카⁠드';

  @override
  String get settingsRowProfilePicture => '프⁠로⁠필 사⁠진';

  @override
  String get settingsRowProfilePictureMobile => '프⁠로⁠필 사⁠진';

  @override
  String get settingsRowSecretPassphrase => '복⁠구 문⁠구';

  @override
  String get settingsRowSupportVizor => 'Vizor 후⁠원';

  @override
  String get settingsRowUpdates => '업⁠데⁠이⁠트';

  @override
  String get settingsRowViewingKeyMobile => '뷰⁠잉 키';

  @override
  String get settingsSectionAccount => '계⁠정';

  @override
  String get settingsSectionDangerZone => '위⁠험 구⁠역';

  @override
  String get settingsSectionMisc => '기⁠타';

  @override
  String get settingsSectionPersonal => '개⁠인';

  @override
  String get settingsSectionSyncing => '동⁠기⁠화';

  @override
  String get settingsSectionSystem => '시⁠스⁠템';

  @override
  String get settingsSeedBackupSaveFailed =>
      '저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsSeedBiometricReason => '복⁠구 문⁠구 접⁠근 확⁠인';

  @override
  String get settingsSeedCopiedToast => '복⁠구 문⁠구⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get settingsSeedHeadingSubtitle =>
      '이⁠것⁠은 지⁠갑⁠의 마⁠스⁠터 키⁠예⁠요.\n누⁠구⁠에⁠게⁠도 공⁠유⁠하⁠지 마⁠세⁠요.';

  @override
  String get settingsSeedLoadFailed =>
      '복⁠구 문⁠구⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsSeedPasswordSubtitle => '복⁠구 문⁠구⁠를 보⁠려⁠면 필⁠요⁠해⁠요.';

  @override
  String get settingsSeedRemindLater => '나⁠중⁠에 알⁠림';

  @override
  String get settingsSeedScreenshotAck => '확⁠인⁠했⁠어⁠요';

  @override
  String get settingsSeedScreenshotBodyLead => '스⁠크⁠린⁠샷⁠은 안⁠전⁠하⁠지 않⁠아⁠요';

  @override
  String get settingsSeedScreenshotBodyRest =>
      '. 휴⁠대⁠폰⁠이⁠나 사⁠진 보⁠관⁠함⁠에 접⁠근⁠할 수 있⁠는 사⁠람⁠은 누⁠구⁠나 복⁠구 문⁠구⁠를 볼 수 있⁠어⁠요. 대⁠신 종⁠이⁠에 직⁠접 적⁠어 두⁠세⁠요.';

  @override
  String get settingsSeedScreenshotTitle => '복⁠구 문⁠구⁠를 스⁠크⁠린⁠샷⁠으⁠로 남⁠기⁠지 마⁠세⁠요';

  @override
  String get settingsSeedUnavailableAccount => '이 계⁠정⁠에⁠는 복⁠구 문⁠구⁠가 없⁠어⁠요.';

  @override
  String get settingsSeedUnavailableHardware =>
      '하⁠드⁠웨⁠어 계⁠정⁠에⁠는 복⁠구 문⁠구⁠가 없⁠어⁠요.';

  @override
  String get settingsSeedWrittenDown => '적⁠어 두⁠었⁠어⁠요';

  @override
  String get settingsSetNewPasscodeTitle => '새 암⁠호 설⁠정';

  @override
  String get settingsStatusOff => '꺼⁠짐';

  @override
  String get settingsStatusOn => '켜⁠짐';

  @override
  String get settingsThemeDark => '다⁠크';

  @override
  String get settingsThemeLight => '라⁠이⁠트';

  @override
  String get settingsThemeSystem => '시⁠스⁠템';

  @override
  String get settingsThemeSystemAuto => '시⁠스⁠템(자⁠동)';

  @override
  String get settingsThemeTitle => '테⁠마';

  @override
  String get settingsThemeUpdateFailed => '테⁠마⁠를 변⁠경⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get settingsTorDescBootstrapFailed =>
      'Vizor⁠가 Tor⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요. 연⁠결⁠되⁠거⁠나 Tor⁠를 끌 때⁠까⁠지 요⁠청⁠이 차⁠단⁠돼⁠요.';

  @override
  String get settingsTorDescConnected =>
      'Vizor⁠의 네⁠트⁠워⁠크 요⁠청⁠은 Tor⁠를 거⁠쳐⁠요. 다⁠른 앱⁠에⁠서 연 링⁠크⁠는 해⁠당 앱⁠의 네⁠트⁠워⁠크 설⁠정⁠을 따⁠라⁠요.';

  @override
  String get settingsTorDescConnectedIos =>
      'Vizor⁠의 네⁠트⁠워⁠크 요⁠청⁠은 Tor⁠를 거⁠쳐⁠요. Ironwood 비⁠공⁠개 마⁠이⁠그⁠레⁠이⁠션⁠은 Vizor⁠가 닫⁠혀 있⁠는 동⁠안 직⁠접 연⁠결⁠을 사⁠용⁠해⁠요. 다⁠른 앱⁠에⁠서 연 링⁠크⁠는 해⁠당 앱⁠의 네⁠트⁠워⁠크 설⁠정⁠을 따⁠라⁠요.';

  @override
  String get settingsTorDescConnectedNoUpdates =>
      'Vizor⁠의 네⁠트⁠워⁠크 요⁠청⁠은 Tor⁠를 거⁠치⁠지⁠만 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트⁠를 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get settingsTorDescConnecting =>
      '새 요⁠청⁠은 Tor 연⁠결⁠이 준⁠비⁠될 때⁠까⁠지 기⁠다⁠려⁠요. 연⁠결⁠을 멈⁠추⁠고 직⁠접 연⁠결⁠을 쓰⁠려⁠면 Tor⁠를 끄⁠세⁠요.';

  @override
  String get settingsTorDescConnectingLinux =>
      '새 요⁠청⁠은 Tor 연⁠결⁠이 준⁠비⁠될 때⁠까⁠지 기⁠다⁠려⁠요. 연⁠결⁠을 멈⁠추⁠고 직⁠접 연⁠결⁠을 쓰⁠려⁠면 Tor⁠를 끄⁠세⁠요. 다⁠른 앱⁠에⁠서 연 업⁠데⁠이⁠트 페⁠이⁠지⁠와 다⁠운⁠로⁠드⁠는 그 앱⁠의 연⁠결⁠을 사⁠용⁠해⁠요.';

  @override
  String get settingsTorDescConnectionFailed =>
      '직⁠접 요⁠청⁠은 계⁠속 차⁠단⁠돼⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 Tor⁠를 끄⁠세⁠요.';

  @override
  String get settingsTorDescDirectNoUpdates =>
      '네⁠트⁠워⁠크 요⁠청⁠이 직⁠접 연⁠결⁠돼⁠요. 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트⁠를 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get settingsTorDescDisableNotSaved =>
      '요⁠청⁠은 이⁠제 직⁠접 연⁠결⁠을 사⁠용⁠하⁠지⁠만 Vizor⁠가 변⁠경 사⁠항⁠을 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 앱⁠을 다⁠시 열⁠면 Tor⁠가 다⁠시 켜⁠져⁠요.';

  @override
  String get settingsTorDescEnableNotSaved =>
      'Vizor⁠가 변⁠경 사⁠항⁠을 저⁠장⁠하⁠지 못⁠해 Tor⁠가 켜⁠지⁠지 않⁠았⁠어⁠요. 요⁠청⁠은 계⁠속 직⁠접 연⁠결⁠을 사⁠용⁠해⁠요.';

  @override
  String get settingsTorDescOff =>
      'Tor⁠가 꺼⁠져 있⁠어⁠요. Zcash 네⁠트⁠워⁠크, 앱 내 서⁠비⁠스, 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트 요⁠청⁠이 직⁠접 연⁠결⁠돼⁠요.';

  @override
  String get settingsTorDescOffLinux =>
      'Tor⁠가 꺼⁠져 있⁠어⁠요. 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트 확⁠인⁠을 포⁠함⁠한 Vizor⁠의 요⁠청⁠이 직⁠접 연⁠결⁠돼⁠요. 업⁠데⁠이⁠트 페⁠이⁠지⁠와 다⁠운⁠로⁠드⁠는 다⁠른 앱⁠에⁠서 열⁠려⁠요.';

  @override
  String get settingsTorDescOffMobile =>
      '지⁠갑 동⁠기⁠화⁠와 앱 내 요⁠청⁠이 직⁠접 연⁠결⁠돼⁠요. Vizor⁠가 통⁠신⁠하⁠는 서⁠버⁠로⁠부⁠터 IP 주⁠소⁠를 숨⁠기⁠려⁠면 Tor⁠를 켜⁠세⁠요.';

  @override
  String get settingsTorDescSwitchFailed =>
      'Vizor⁠가 직⁠접 연⁠결⁠로 전⁠환⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsTorDescSwitchFailedStillOn =>
      'Vizor⁠가 직⁠접 연⁠결⁠로 전⁠환⁠하⁠지 못⁠했⁠어⁠요. Tor⁠는 계⁠속 켜⁠져 있⁠고 요⁠청⁠은 계⁠속 Tor⁠를 거⁠쳐⁠요.';

  @override
  String get settingsTorDescSwitching =>
      'Vizor⁠가 네⁠트⁠워⁠크 요⁠청⁠과 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트⁠를 직⁠접 연⁠결⁠로 전⁠환⁠하⁠고 있⁠어⁠요.';

  @override
  String get settingsTorDescSwitchingLinux =>
      'Vizor⁠가 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트 확⁠인⁠을 포⁠함⁠한 요⁠청⁠을 직⁠접 연⁠결⁠로 전⁠환⁠하⁠고 있⁠어⁠요.';

  @override
  String get settingsTorDescSwitchingMobile =>
      'Vizor⁠가 네⁠트⁠워⁠크 요⁠청⁠을 직⁠접 연⁠결⁠로 전⁠환⁠하⁠고 있⁠어⁠요.';

  @override
  String get settingsTorGeneralDescription =>
      'Tor⁠를 사⁠용⁠하⁠면 서⁠버⁠로⁠부⁠터 IP 주⁠소⁠를 숨⁠길 수 있⁠어⁠요. 다⁠른 앱⁠은 자⁠체 네⁠트⁠워⁠크 설⁠정⁠을 사⁠용⁠해⁠요.';

  @override
  String get settingsTorGeneralIosSuffix =>
      ' Ironwood 비⁠공⁠개 마⁠이⁠그⁠레⁠이⁠션⁠은 Vizor⁠가 닫⁠혀 있⁠는 동⁠안 직⁠접 연⁠결⁠돼⁠요.';

  @override
  String get settingsTorRetryUpdates => '업⁠데⁠이⁠트 다⁠시 시⁠도';

  @override
  String get settingsTorStatusConnected => '연⁠결⁠됨';

  @override
  String get settingsTorStatusConnecting => '연⁠결 중…';

  @override
  String get settingsTorStatusConnectionFailed => '연⁠결 실⁠패';

  @override
  String get settingsTorStatusDirect => '직⁠접 연⁠결';

  @override
  String get settingsTorStatusFailed => '실⁠패';

  @override
  String get settingsTorStatusNotSaved => '설⁠정⁠이 저⁠장⁠되⁠지 않⁠았⁠어⁠요';

  @override
  String get settingsTorStatusSwitchFailed => '전⁠환 실⁠패';

  @override
  String get settingsTorStatusSwitching => '전⁠환 중…';

  @override
  String get settingsTorStatusSwitchingDirect => '직⁠접 연⁠결⁠로 전⁠환 중…';

  @override
  String get settingsTorStopConnecting => 'Tor 연⁠결 중⁠단';

  @override
  String get settingsTorTryDirect => '직⁠접 연⁠결 다⁠시 시⁠도';

  @override
  String get settingsTorUse => 'Tor 사⁠용';

  @override
  String get settingsTurnOffConfirm => '끄⁠기';

  @override
  String settingsUninstallActiveSwaps(int count) {
    return '이 지⁠갑⁠에 진⁠행 중⁠인 스⁠왑⁠이 $count⁠개 있⁠어⁠요. 삭⁠제⁠하⁠기 전⁠에 모⁠두 끝⁠날 때⁠까⁠지 기⁠다⁠려 주⁠세⁠요.';
  }

  @override
  String get settingsUninstallClaimCheckFailed =>
      '받⁠는 중⁠인 기⁠프⁠트 카⁠드⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 삭⁠제⁠하⁠기 전⁠에 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsUninstallCloseApp => 'Vizor 닫⁠기';

  @override
  String get settingsUninstallDeviceGeneric => '이 기⁠기';

  @override
  String get settingsUninstallDeviceMac => '이 Mac';

  @override
  String get settingsUninstallDevicePc => '이 PC';

  @override
  String get settingsUninstallDoneTitle => '데⁠이⁠터⁠가 삭⁠제⁠되⁠었⁠어⁠요';

  @override
  String get settingsUninstallFinishGeneric =>
      '삭⁠제⁠를 마⁠치⁠려⁠면 이 기⁠기⁠에⁠서 Vizor 앱⁠을 제⁠거⁠하⁠세⁠요.';

  @override
  String get settingsUninstallFinishMac =>
      '삭⁠제⁠를 마⁠치⁠려⁠면 응⁠용 프⁠로⁠그⁠램⁠에⁠서 Vizor 앱⁠을 제⁠거⁠하⁠세⁠요.';

  @override
  String get settingsUninstallFinishWindows =>
      '삭⁠제⁠를 마⁠치⁠려⁠면 Windows 설⁠정⁠에⁠서 Vizor⁠를 제⁠거⁠하⁠세⁠요.';

  @override
  String get settingsUninstallPasswordSubtitle => 'Vizor⁠를 삭⁠제⁠하⁠려⁠면 필⁠요⁠해⁠요.';

  @override
  String get settingsUninstallRemovingTitle => '데⁠이⁠터 삭⁠제 중...';

  @override
  String get settingsUninstallSwapCheckFailed =>
      '진⁠행 중⁠인 스⁠왑⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 삭⁠제⁠하⁠기 전⁠에 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get settingsUninstallTitle => 'Vizor 삭⁠제';

  @override
  String get settingsUninstallWipeFailed =>
      '데⁠이⁠터⁠를 모⁠두 삭⁠제⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String settingsUninstallWipeSubtitle(String device) {
    return 'Vizor⁠가 $device⁠에⁠서 지⁠갑 데⁠이⁠터⁠와 보⁠안 저⁠장⁠소⁠를 삭⁠제⁠해⁠요. 공⁠유⁠하⁠지 않⁠은 기⁠프⁠트 카⁠드 링⁠크⁠는 영⁠구⁠적⁠으⁠로 사⁠라⁠져⁠요.';
  }

  @override
  String get settingsUpdateApplying => '적⁠용 중';

  @override
  String get settingsUpdateAvailable => '사⁠용 가⁠능';

  @override
  String get settingsUpdateCheck => '확⁠인';

  @override
  String get settingsUpdateCheckForUpdates => '업⁠데⁠이⁠트 확⁠인';

  @override
  String get settingsUpdateChecking => '확⁠인 중';

  @override
  String get settingsUpdateCheckingButton => '확⁠인 중…';

  @override
  String get settingsUpdateCurrentLabel => '현⁠재';

  @override
  String get settingsUpdateDownloadButton => '업⁠데⁠이⁠트 다⁠운⁠로⁠드';

  @override
  String get settingsUpdateDownloadingButton => '다⁠운⁠로⁠드 중…';

  @override
  String get settingsUpdateFailed => '실⁠패';

  @override
  String get settingsUpdatePasswordTitle => '비⁠밀⁠번⁠호 변⁠경';

  @override
  String get settingsUpdateRestartButton => '재⁠시⁠작⁠하⁠여 업⁠데⁠이⁠트';

  @override
  String get settingsUpdateRestartingButton => '재⁠시⁠작 중…';

  @override
  String settingsUpdateStatusAvailable(String version) {
    return '버⁠전 $version⁠을(를) 사⁠용⁠할 수 있⁠어⁠요.';
  }

  @override
  String get settingsUpdateStatusChecking => '업⁠데⁠이⁠트⁠를 확⁠인⁠하⁠고 있⁠어⁠요.';

  @override
  String settingsUpdateStatusDownloading(String percent) {
    return '$percent% 다⁠운⁠로⁠드 중⁠이⁠에⁠요.';
  }

  @override
  String get settingsUpdateStatusIdle => '업⁠데⁠이⁠트⁠를 확⁠인⁠할 준⁠비⁠가 되⁠었⁠어⁠요.';

  @override
  String settingsUpdateStatusReady(String version) {
    return '버⁠전 $version 설⁠치 준⁠비⁠가 되⁠었⁠어⁠요.';
  }

  @override
  String get settingsUpdateStatusRestarting => 'Vizor⁠를 다⁠시 시⁠작⁠하⁠고 있⁠어⁠요.';

  @override
  String get settingsUpdateStatusUnsupported =>
      '설⁠치⁠된 Windows 앱⁠에⁠서 업⁠데⁠이⁠트⁠할 수 있⁠어⁠요.';

  @override
  String get settingsUpdateStatusUpToDate => 'Vizor⁠가 최⁠신 버⁠전⁠이⁠에⁠요.';

  @override
  String get settingsUpdateUnavailable => '사⁠용 불⁠가';

  @override
  String get settingsUpdateUpToDate => '최⁠신 버⁠전';

  @override
  String get settingsUpdatingPassword => '비⁠밀⁠번⁠호 변⁠경 중...';

  @override
  String settingsVersionFooterLabel(String version) {
    return 'Vizor, 버⁠전 $version';
  }

  @override
  String get settingsViewingKeyBiometricReason => '뷰⁠잉 키 접⁠근 확⁠인';

  @override
  String get settingsViewingKeyChoiceSharingWarning =>
      '신⁠뢰⁠하⁠는 상⁠대⁠에⁠게⁠만 공⁠유⁠하⁠세⁠요. 두 키 모⁠두 투⁠명 잔⁠액⁠과 지⁠출⁠을 드⁠러⁠낼 수 있⁠어⁠요.';

  @override
  String get settingsViewingKeyChooseTitle =>
      '다⁠른 사⁠람⁠이 볼 수 있⁠는 범⁠위⁠를 선⁠택⁠하⁠세⁠요';

  @override
  String get settingsViewingKeyConfirmAgain =>
      '접⁠근⁠을 다⁠시 확⁠인⁠한 뒤 이 키⁠를 불⁠러⁠와 주⁠세⁠요.';

  @override
  String get settingsViewingKeyCopy => '뷰⁠잉 키 복⁠사';

  @override
  String get settingsViewingKeyExplanation =>
      '잔⁠액⁠과 과⁠거·미⁠래⁠의 모⁠든 거⁠래⁠를 드⁠러⁠내⁠요. ZEC⁠를 사⁠용⁠할 수⁠는 없⁠어⁠요.';

  @override
  String get settingsViewingKeyFormatQr => 'QR 코⁠드';

  @override
  String get settingsViewingKeyFormatText => '텍⁠스⁠트';

  @override
  String get settingsViewingKeyFullDescription =>
      '잔⁠액⁠과 받⁠은 거⁠래, 보⁠낸 거⁠래⁠를 볼 수 있⁠어⁠요.';

  @override
  String get settingsViewingKeyIncomingExplanation =>
      '과⁠거⁠와 미⁠래⁠의 받⁠은 결⁠제⁠를 드⁠러⁠내⁠요. ZEC⁠를 사⁠용⁠할 수⁠는 없⁠어⁠요.';

  @override
  String get settingsViewingKeyIncomingOnly => '수⁠신 전⁠용';

  @override
  String get settingsViewingKeyIncomingOnlyDescription =>
      '받⁠은 거⁠래⁠만 볼 수 있⁠어⁠요.';

  @override
  String get settingsViewingKeyIncomingWarningTitle =>
      '이 키⁠로 받⁠은 결⁠제⁠를 볼 수 있⁠어⁠요';

  @override
  String get settingsViewingKeyLoadFailedTitle => '뷰⁠잉 키⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요';

  @override
  String get settingsViewingKeyPasswordSubtitle => '뷰⁠잉 키⁠를 보⁠려⁠면 필⁠요⁠해⁠요.';

  @override
  String get settingsViewingKeyQrFull => '전⁠체 뷰⁠잉 키 QR 코⁠드';

  @override
  String get settingsViewingKeyQrIncoming => '수⁠신 전⁠용 뷰⁠잉 키 QR 코⁠드';

  @override
  String get settingsViewingKeyTitle => '뷰⁠잉 키';

  @override
  String get settingsViewingKeyTryCopyAgain => '다⁠시 복⁠사';

  @override
  String get settingsViewingKeyTypeFull => '전⁠체 뷰⁠잉 키';

  @override
  String get settingsViewingKeyTypeIncoming => '수⁠신 전⁠용 키';

  @override
  String get settingsViewingKeyWarningTitle => '이 키⁠로 거⁠래⁠를 볼 수 있⁠어⁠요';

  @override
  String get settingsWalletSessionChanged =>
      '지⁠갑 세⁠션⁠이 바⁠뀌⁠었⁠어⁠요. 비⁠밀⁠번⁠호⁠를 다⁠시 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get settingsWinUpdateContinueTor => 'Tor⁠로 계⁠속';

  @override
  String get settingsWinUpdateStartFailedTitle => '업⁠데⁠이⁠트⁠를 시⁠작⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get settingsWinUpdateTorBlockedBody =>
      'Vizor⁠는 직⁠접 요⁠청⁠을 계⁠속 차⁠단⁠했⁠어⁠요. 설⁠정⁠에⁠서 업⁠데⁠이⁠트⁠를 다⁠시 시⁠도⁠하⁠거⁠나, Tor⁠를 끄⁠고 다⁠시 다⁠운⁠로⁠드⁠해 보⁠세⁠요.';

  @override
  String get settingsWinUpdateTorBlockedTitle =>
      'Tor⁠로⁠는 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get settingsWinUpdateTorChoiceBody =>
      'Tor⁠로 업⁠데⁠이⁠트⁠하⁠면 더 오⁠래 걸⁠릴 수 있⁠어⁠요. Tor⁠를 끄⁠면 Vizor⁠의 모⁠든 네⁠트⁠워⁠크 요⁠청⁠이 직⁠접 연⁠결⁠로 바⁠뀌⁠어⁠요.';

  @override
  String get settingsWinUpdateTorChoiceTitle => '이 업⁠데⁠이⁠트⁠에 Tor⁠를 사⁠용⁠할⁠까⁠요?';

  @override
  String get settingsWinUpdateTorOffFailedBody =>
      'Tor⁠가 켜⁠진 채⁠라⁠서 Vizor⁠가 업⁠데⁠이⁠트⁠를 계⁠속 차⁠단⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나, 설⁠정⁠에⁠서 Tor⁠를 끈 뒤 다⁠운⁠로⁠드⁠하⁠세⁠요.';

  @override
  String get settingsWinUpdateTorOffFailedTitle => 'Tor⁠를 끄⁠지 못⁠했⁠어⁠요';

  @override
  String get settingsWinUpdateTurnOffTorAndUpdate => 'Tor⁠를 끄⁠고 업⁠데⁠이⁠트';

  @override
  String get settingsWinUpdateUnavailableBody =>
      'Tor⁠는 꺼⁠져 있⁠지⁠만 소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트⁠를 아⁠직 사⁠용⁠할 수 없⁠어⁠요. 다⁠운⁠로⁠드⁠하⁠기 전⁠에 설⁠정⁠에⁠서 업⁠데⁠이⁠트⁠를 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get settingsWinUpdateUnavailableTitle =>
      '소⁠프⁠트⁠웨⁠어 업⁠데⁠이⁠트⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get sidebarAccountNameFallback => '사⁠용⁠자 이⁠름';

  @override
  String get sidebarAddressCopyFailed => '주⁠소⁠를 복⁠사⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sidebarCopyShieldedAddress => '차⁠폐 주⁠소 복⁠사';

  @override
  String get sidebarHideBalance => '잔⁠액 숨⁠기⁠기';

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

  @override
  String get updateFailedMessage =>
      '업⁠데⁠이⁠트⁠를 완⁠료⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get updateRestart => '다⁠시 시⁠작';

  @override
  String walletLinkAccountsFound(int count) {
    return '계⁠정 $count⁠개⁠를 찾⁠았⁠어⁠요';
  }

  @override
  String walletLinkAccountsReadySubtitle(int ready, int imported) {
    return '가⁠져⁠올 수 있⁠는 계⁠정 $ready⁠개, 이⁠미 가⁠져⁠온 계⁠정 $imported⁠개';
  }

  @override
  String walletLinkAlreadyImported(int count) {
    return '이⁠미 가⁠져⁠온 항⁠목 $count⁠개';
  }

  @override
  String get walletLinkCameraRequired =>
      '데⁠스⁠크⁠탑 연⁠결⁠을 스⁠캔⁠하⁠려⁠면 이 기⁠기⁠에 카⁠메⁠라⁠가 필⁠요⁠해⁠요.';

  @override
  String walletLinkContactsFound(int count) {
    return '연⁠락⁠처 $count⁠개⁠를 찾⁠았⁠어⁠요';
  }

  @override
  String walletLinkContactsReadySubtitle(int found, int imported) {
    return '연⁠락⁠처 $found⁠개⁠를 찾⁠았⁠고, 이⁠미 가⁠져⁠온 연⁠락⁠처⁠는 $imported⁠개⁠예⁠요.';
  }

  @override
  String get walletLinkDeselectAll => '모⁠두 선⁠택 해⁠제';

  @override
  String get walletLinkErrorExpiredBody =>
      '컴⁠퓨⁠터⁠의 코⁠드⁠가 만⁠료⁠됐⁠어⁠요. 데⁠스⁠크⁠탑⁠에⁠서 새 코⁠드 생⁠성⁠을 선⁠택⁠하⁠고 다⁠시 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String get walletLinkErrorExpiredTitle => '링⁠크⁠가 만⁠료⁠됐⁠어⁠요';

  @override
  String get walletLinkErrorFailedBody =>
      '데⁠스⁠크⁠탑⁠에 코⁠드⁠가 계⁠속 표⁠시⁠되⁠어 있⁠는⁠지 확⁠인⁠한 뒤 다⁠시 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String get walletLinkErrorFailedTitle => '이 링⁠크⁠를 열 수 없⁠어⁠요';

  @override
  String get walletLinkErrorInvalidBody =>
      '스⁠캔⁠한 코⁠드⁠는 Vizor 데⁠스⁠크⁠탑 연⁠결 코⁠드⁠가 아⁠니⁠에⁠요. 컴⁠퓨⁠터⁠에⁠서 설⁠정 → Vizor 모⁠바⁠일 연⁠결⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get walletLinkErrorInvalidTitle => '잘⁠못⁠된 QR 코⁠드';

  @override
  String walletLinkImportContacts(int count) {
    return '연⁠락⁠처 $count⁠개 가⁠져⁠오⁠기';
  }

  @override
  String get walletLinkIntroNotice =>
      '지⁠갑⁠과 연⁠락⁠처⁠를 휴⁠대⁠폰⁠으⁠로 복⁠사⁠해⁠요. 컴⁠퓨⁠터⁠에⁠서⁠는 아⁠무⁠것⁠도 바⁠뀌⁠지 않⁠으⁠며 둘 다 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String get walletLinkIntroReady => '스⁠캔⁠할 준⁠비⁠가 됐⁠어⁠요';

  @override
  String get walletLinkIntroSubtitle => '데⁠스⁠크⁠탑 지⁠갑⁠을 이 휴⁠대⁠폰⁠으⁠로 복⁠사⁠하⁠세⁠요';

  @override
  String get walletLinkIntroTitle => '데⁠스⁠크⁠탑⁠과 연⁠결';

  @override
  String walletLinkLinkAccounts(int count) {
    return '계⁠정 $count⁠개 연⁠결';
  }

  @override
  String get walletLinkNothingNewSubtitle =>
      '이 데⁠스⁠크⁠탑 연⁠결⁠에⁠서 새⁠로 가⁠져⁠올 항⁠목⁠이 없⁠어⁠요.';

  @override
  String get walletLinkNothingToImportBody =>
      '이 데⁠스⁠크⁠탑 연⁠결⁠의 모⁠든 항⁠목⁠이 이⁠미 이 휴⁠대⁠폰⁠에 있⁠어⁠요.';

  @override
  String get walletLinkNothingToImportTitle => '가⁠져⁠올 항⁠목⁠이 없⁠어⁠요';

  @override
  String get walletLinkReadingLink => '링⁠크⁠를 읽⁠는 중...';

  @override
  String get walletLinkScanAgain => '다⁠시 스⁠캔';

  @override
  String get walletLinkScanCaption => 'Vizor 데⁠스⁠크⁠탑 QR⁠을 스⁠캔⁠하⁠세⁠요';

  @override
  String get walletLinkScanSubtitleDesktop => '데⁠스⁠크⁠탑⁠에 표⁠시⁠된 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get walletLinkSelectAll => '모⁠두 선⁠택';

  @override
  String get walletLinkStepOpenSettings => '설⁠정 → Vizor 모⁠바⁠일 연⁠결⁠로 이⁠동⁠하⁠세⁠요';

  @override
  String get walletLinkStepScanQr =>
      '다⁠음 화⁠면⁠에⁠서 데⁠스⁠크⁠탑⁠에 표⁠시⁠된 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요.';

  @override
  String get walletLinkStepUnlockDesktop =>
      'Vizor 데⁠스⁠크⁠탑 앱⁠을 열⁠고 잠⁠금⁠을 해⁠제⁠하⁠세⁠요';
}
