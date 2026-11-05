// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get accountsActionsLabel => '계⁠정 작⁠업';

  @override
  String get accountsAdd => '계⁠정 추⁠가';

  @override
  String get accountsAddressLoadFailed => '계⁠정 주⁠소⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsChangeProfilePicture => '프⁠로⁠필 사⁠진 변⁠경';

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
  String get accountsEditNameLabel => '계⁠정 이⁠름';

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
  String get accountsRemovePasswordCheckFailed =>
      '비⁠밀⁠번⁠호⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get accountsRemovePasswordHint => '비⁠밀⁠번⁠호⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String get accountsRemovePasswordIncorrect =>
      '비⁠밀⁠번⁠호⁠가 맞⁠지 않⁠아⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get accountsRemovePasswordLabel => '비⁠밀⁠번⁠호';

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
  String get accountsResetVizor => 'Vizor 초⁠기⁠화';

  @override
  String get accountsResetting => '초⁠기⁠화⁠하⁠는 중...';

  @override
  String get accountsSaveEdits => '변⁠경 사⁠항 저⁠장';

  @override
  String get accountsSaveFailed => '계⁠정 변⁠경 사⁠항⁠을 저⁠장⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get accountsSelectProfilePicture => '프⁠로⁠필 사⁠진 선⁠택';

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
  String get homeKeepAwakeEnable => '화⁠면 켜 두⁠기';

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
  String get homeShieldScanHold => 'QR 코⁠드⁠가 흔⁠들⁠리⁠지 않⁠고 전⁠부 보⁠이⁠게 해 주⁠세⁠요.';

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
  String get homeShieldTryAgain => '다⁠시 시⁠도';

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
  String get homeVotingTitle => '코⁠인 보⁠유⁠자 투⁠표';

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
  String keystoneAccountsFound(int count) {
    return '계⁠정 $count⁠개⁠를 찾⁠았⁠어⁠요';
  }

  @override
  String get keystoneBackWelcome => '시⁠작 화⁠면';

  @override
  String get keystoneBirthdayDatePlaceholder => 'mm/dd/yyyy';

  @override
  String get keystoneBirthdayEstimateError => '지⁠갑 생⁠성 높⁠이⁠를 추⁠정⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get keystoneBirthdayEstimating => '추⁠정⁠하⁠는 중...';

  @override
  String get keystoneBirthdayHeightHint => '블⁠록 높⁠이';

  @override
  String get keystoneBirthdayInvalidHeight => '올⁠바⁠른 블⁠록 높⁠이⁠가 아⁠닌 것 같⁠아⁠요.';

  @override
  String get keystoneBirthdayMetadataError =>
      '지⁠갑 생⁠성 높⁠이 정⁠보⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get keystoneBirthdayStopSyncing => '동⁠기⁠화⁠를 중⁠지⁠하⁠는 중...';

  @override
  String get keystoneBirthdaySubtitle => '알⁠려 주⁠시⁠면 지⁠갑⁠을 더 빨⁠리 가⁠져⁠올 수 있⁠어⁠요.';

  @override
  String get keystoneBirthdayTabBlockHeight => '블⁠록 높⁠이 입⁠력';

  @override
  String get keystoneBirthdayTabDate => '날⁠짜 입⁠력';

  @override
  String get keystoneBirthdayTitle => '지⁠갑⁠을 대⁠략 언⁠제 만⁠들⁠었⁠나⁠요?';

  @override
  String get keystoneBirthdayUnknown => '기⁠억⁠나⁠지 않⁠아⁠요';

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
  String get keystoneCameraTryAgain => '다⁠시 시⁠도';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone 가⁠져⁠오⁠기⁠는 카⁠메⁠라 QR 스⁠캔⁠만 지⁠원⁠해⁠요.\n카⁠메⁠라⁠를 연⁠결⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneCameraUnavailableTitle => '카⁠메⁠라⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get keystoneConfirmSelection => '선⁠택 확⁠인';

  @override
  String get keystoneConnectTitle => 'Keystone 연⁠결';

  @override
  String get keystoneContinue => '계⁠속';

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
  String get keystoneImporting => '가⁠져⁠오⁠는 중...';

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
  String get keystoneScanKeepSteady =>
      'QR 코⁠드⁠가 화⁠면⁠에 전⁠부 보⁠이⁠도⁠록 움⁠직⁠이⁠지 말⁠고 유⁠지⁠하⁠세⁠요.';

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
  String get keystoneScanTitle => 'QR 코⁠드 스⁠캔';

  @override
  String get keystoneSelectAccountTitle => '계⁠정 선⁠택';

  @override
  String get keystoneStepCustomiseWallet => '지⁠갑 꾸⁠미⁠기';

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
  String get keystoneStepSetPassword => '비⁠밀⁠번⁠호 설⁠정';

  @override
  String get keystoneStepWalletBirthdayHeight => '지⁠갑 생⁠성 높⁠이';

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
  String get ledgerBackAddAccount => '계⁠정 추⁠가';

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
  String get ledgerConnect => 'Ledger 연⁠결';

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
  String get ledgerStepAddAccount => '계⁠정 추⁠가';

  @override
  String get ledgerStepApproveViewingKey => '뷰⁠잉 키 승⁠인';

  @override
  String get ledgerStepCustomiseWallet => '지⁠갑 꾸⁠미⁠기';

  @override
  String ledgerStepOpenApp(String appName) {
    return '$appName 열⁠기';
  }

  @override
  String get ledgerStepOpenZcash => 'Zcash 열⁠기';

  @override
  String get ledgerStepSetPassword => '비⁠밀⁠번⁠호 설⁠정';

  @override
  String get ledgerStepWalletBirthdayHeight => '지⁠갑 생⁠성 높⁠이';

  @override
  String get ledgerStoppingSearch => '검⁠색⁠을 중⁠지⁠하⁠는 중';

  @override
  String get ledgerSupportedDevices => '지⁠원 기⁠기';

  @override
  String get ledgerTransportBluetooth => '블⁠루⁠투⁠스';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerTryAgain => '다⁠시 시⁠도';

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
  String get walletLinkContinue => '계⁠속';

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
  String get walletLinkGoBack => '돌⁠아⁠가⁠기';

  @override
  String walletLinkImportContacts(int count) {
    return '연⁠락⁠처 $count⁠개 가⁠져⁠오⁠기';
  }

  @override
  String get walletLinkImportContactsTitle => '연⁠락⁠처 가⁠져⁠오⁠기';

  @override
  String get walletLinkImporting => '가⁠져⁠오⁠는 중...';

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
  String get walletLinkScanTitle => 'QR 코⁠드 스⁠캔';

  @override
  String get walletLinkSelectAccountTitle => '계⁠정 선⁠택';

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
