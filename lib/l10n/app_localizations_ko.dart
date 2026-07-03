// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsSectionAccount => '계정';

  @override
  String get settingsSectionSystem => '시스템';

  @override
  String get settingsSectionMisc => '기타';

  @override
  String get settingsSectionDangerZone => '위험 구역';

  @override
  String get settingsSecretPassphrase => '비밀 복구 구문';

  @override
  String get settingsPassword => '비밀번호';

  @override
  String get settingsProfilePicture => '프로필 사진';

  @override
  String get settingsProfilePictureCustom => '사용자 지정';

  @override
  String get settingsAccountName => '계정 이름';

  @override
  String get settingsContacts => '연락처';

  @override
  String get settingsEndpoint => '엔드포인트';

  @override
  String get settingsTheme => '테마';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsUpdates => '업데이트';

  @override
  String get settingsAboutVizor => 'Vizor 정보';

  @override
  String get settingsUninstallVizor => 'Vizor 제거';

  @override
  String get settingsThemeSystem => '시스템';

  @override
  String get settingsThemeSystemAuto => '시스템 (자동)';

  @override
  String get settingsThemeLight => '라이트';

  @override
  String get settingsThemeDark => '다크';

  @override
  String get settingsThemeUpdateError => '테마를 업데이트하지 못했습니다.';

  @override
  String get settingsLanguageUpdateError => '언어를 업데이트하지 못했습니다.';

  @override
  String get commonCancel => '취소';

  @override
  String get commonUpdate => '업데이트';

  @override
  String get commonUpdating => '업데이트 중...';

  @override
  String get settingsUpdateCurrent => '현재';

  @override
  String get settingsUpdateAvailable => '사용 가능';

  @override
  String get settingsUpdateUnavailable => '사용 불가';

  @override
  String get settingsUpdateChecking => '확인 중';

  @override
  String get settingsUpdateRestart => '재시작';

  @override
  String get settingsUpdateApplying => '적용 중';

  @override
  String get settingsUpdateFailed => '실패';

  @override
  String get settingsUpdateUpToDate => '최신 상태';

  @override
  String get settingsUpdateCheck => '확인';

  @override
  String get settingsUpdateActionCheck => '업데이트 확인';

  @override
  String get settingsUpdateActionChecking => '확인 중...';

  @override
  String get settingsUpdateActionDownloading => '다운로드 중...';

  @override
  String get settingsUpdateActionRestarting => '재시작 중...';

  @override
  String get settingsUpdateActionDownload => '업데이트 다운로드';

  @override
  String get settingsUpdateActionRestartToUpdate => '재시작하여 업데이트';

  @override
  String get settingsUpdateActionTryAgain => '다시 시도';

  @override
  String get settingsUpdateStatusWindowsOnly =>
      '업데이트는 설치된 Windows 앱에서 사용할 수 있습니다.';

  @override
  String get settingsUpdateStatusChecking => '업데이트를 확인하고 있습니다.';

  @override
  String get settingsUpdateStatusUpToDate => 'Vizor가 최신 상태입니다.';

  @override
  String settingsUpdateStatusAvailable(String version) {
    return '$version 버전을 사용할 수 있습니다.';
  }

  @override
  String settingsUpdateStatusDownloading(int progress) {
    return '$progress% 다운로드 중입니다.';
  }

  @override
  String settingsUpdateStatusReady(String version) {
    return '$version 버전이 준비되었습니다.';
  }

  @override
  String get settingsUpdateStatusApplying => 'Vizor를 재시작하고 있습니다.';

  @override
  String get settingsUpdateStatusCheckFailed => '업데이트를 확인하지 못했습니다.';

  @override
  String get settingsUpdateStatusIdle => '업데이트를 확인할 준비가 되었습니다.';

  @override
  String get commonBack => '뒤로';

  @override
  String get commonClose => '닫기';

  @override
  String get commonOk => '확인';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonDone => '완료';

  @override
  String get commonNext => '다음';

  @override
  String get commonContinue => '계속';

  @override
  String get commonCopy => '복사';

  @override
  String get commonSave => '저장';

  @override
  String get commonRemove => '삭제';

  @override
  String get commonEdit => '편집';

  @override
  String get commonAdd => '추가';

  @override
  String get commonConfirm => '확인';

  @override
  String get commonDismiss => '닫기';

  @override
  String get homeNoticePasswordRotationFailed =>
      '이전 비밀번호 변경을 확인하지 못했습니다. 다시 시도하거나 Vizor를 재시작하세요.';

  @override
  String get navHome => '홈';

  @override
  String get navSend => '보내기';

  @override
  String get navReceive => '받기';

  @override
  String get navSwap => '스왑';

  @override
  String get navVote => '투표';

  @override
  String get navActivity => '활동';

  @override
  String get navAccounts => '계정';

  @override
  String get navSignOut => '로그아웃';

  @override
  String get navAmount => '금액';

  @override
  String get navReview => '검토';

  @override
  String get navStatus => '상태';

  @override
  String get navTransaction => '거래';

  @override
  String get navChangePassword => '비밀번호 변경';

  @override
  String get navConnectKeystone => 'Keystone 연결';

  @override
  String get navVotingRound => '투표 라운드';

  @override
  String get navSubmitted => '제출됨';

  @override
  String get navResults => '결과';

  @override
  String get navImporting => '가져오는 중...';

  @override
  String get sidebarMyAccounts => '내 계정';

  @override
  String get sidebarManage => '관리';

  @override
  String get sidebarShowBalance => '잔액 표시';

  @override
  String get sidebarHideBalance => '잔액 숨기기';

  @override
  String get sidebarCopyShieldedAddress => '쉴드 주소 복사';

  @override
  String get toastCopied => '복사됨';

  @override
  String get toastAddressCopied => '주소가 복사되었습니다';

  @override
  String get toastAddressCopyFailed => '주소를 복사하지 못했습니다';

  @override
  String get toastShieldedAddressCopied => '쉴드 주소가 복사되었습니다';

  @override
  String syncStatusSyncingLabel(String pct) {
    return '$pct% 동기화 중...';
  }

  @override
  String syncStatusSyncingSemantics(String pct) {
    return '$pct퍼센트 동기화 중';
  }

  @override
  String syncStatusFailedLabel(String reason) {
    return '동기화 실패. $reason...';
  }

  @override
  String syncStatusFailedSemantics(String reason) {
    return '동기화 실패. $reason';
  }

  @override
  String get syncStatusSynced => 'Vizor 동기화 완료';

  @override
  String get syncFailureNetwork => '네트워크 오류';

  @override
  String get syncFailureEndpoint => '엔드포인트 오류';

  @override
  String get syncFailureDatabaseBusy => '지갑 데이터 사용 중';

  @override
  String get syncFailureDatabaseFatal => '지갑 데이터 오류';

  @override
  String get syncFailureChainRecovery => '체인 복구';

  @override
  String get syncFailureParse => '데이터 오류';

  @override
  String get syncFailureUnknown => '알 수 없는 오류';

  @override
  String get syncUserMessageNetwork => '네트워크 연결이 끊겼습니다. 자동으로 계속 재시도합니다.';

  @override
  String get syncUserMessageEndpoint =>
      '설정된 Zcash 엔드포인트에 연결할 수 없습니다. 엔드포인트 설정을 확인하세요.';

  @override
  String get syncUserMessageDatabaseBusy =>
      '지갑 데이터가 사용 중입니다. 자동으로 다시 동기화를 시도합니다.';

  @override
  String get syncUserMessageDatabaseFatal =>
      '지갑 데이터를 읽을 수 없습니다. 앱을 재시작한 후 동기화를 다시 시도하세요.';

  @override
  String get syncUserMessageChainRecovery => '동기화 중 체인이 변경되었습니다. 계속 복구를 시도합니다.';

  @override
  String get syncUserMessageParse =>
      '동기화 데이터를 처리할 수 없습니다. 동기화를 다시 시도하거나 엔드포인트를 확인하세요.';

  @override
  String get syncUserMessageUnknown => '동기화에 실패했습니다. 다시 시도하세요.';

  @override
  String get homeShieldNoActiveAccount => '활성 계정이 없습니다.';

  @override
  String homeErrorGeneric(String details) {
    return '문제가 발생했습니다. 잠시 후 다시 시도하세요.\n\n상세 정보: $details';
  }

  @override
  String homeTransparentBalanceLabel(String balance) {
    return '투명 잔액: $balance';
  }

  @override
  String get homeShielding => '쉴드 처리 중...';

  @override
  String get homeShieldNow => '지금 쉴드';

  @override
  String homeImportingAccount(String name) {
    return '$name 가져오는 중\nVizor를 켜둔 채로 유지하세요.';
  }

  @override
  String get homeImportingGeneric => '시간이 걸릴 수 있습니다.\nVizor를 켜둔 채로 유지하세요.';

  @override
  String get homeShieldedBalance => '쉴드 잔액';

  @override
  String get homeReceiveFirstZec => '첫 ZEC 받기';

  @override
  String get homeLoadingActivity => '활동 불러오는 중...';

  @override
  String get homeNoActivity => '아직 활동이 없습니다...';

  @override
  String get homeFirstTxPrompt => '첫 ZEC 거래를 시작해 보세요!';

  @override
  String get homeRecentActivity => '최근 활동';

  @override
  String get homeSeeAll => '모두 보기';

  @override
  String get shieldQueuedRetry => '쉴드가 재시도 대기 중입니다. 활동을 확인하세요.';

  @override
  String get homeShieldComplete => '쉴드 완료';

  @override
  String get shieldErrorNoPassphrase => '이 계정의 비밀 복구 구문을 사용할 수 없습니다.';

  @override
  String get shieldErrorWaitForSync => '동기화가 끝난 후 쉴드하세요.';

  @override
  String get shieldErrorTooSmall => '투명 잔액이 수수료를 제하면 쉴드하기에 너무 적습니다.';

  @override
  String get shieldErrorBroadcast => '쉴드 거래를 전파하지 못했습니다. 다시 시도하세요.';

  @override
  String get shieldErrorGeneric => '잔액을 쉴드하지 못했습니다. 다시 시도하세요.';

  @override
  String get shieldTxBroadcastUnknown =>
      '쉴드 거래가 네트워크에 도달했을 수 있으나 확인 시간이 초과되었습니다. 다시 시도하기 전에 활동을 확인하세요.';

  @override
  String get shieldTxStorageFailed =>
      '쉴드 거래가 네트워크에 도달했지만 Vizor가 로컬에 저장하지 못했습니다. 동기화나 익스플로러로 최신 상태가 확인될 때까지 다시 시도하지 마세요.';

  @override
  String get shieldTxUncertain => '쉴드 거래 상태가 불확실합니다. 다시 시도하기 전에 활동을 확인하세요.';

  @override
  String get keystoneShieldParamsError => '필요한 증명 파라미터를 준비하지 못했습니다.';

  @override
  String get keystoneShieldSignatureError => 'Keystone 서명을 적용하지 못했습니다.';

  @override
  String get keystoneShieldFinalizeError => '쉴드 거래를 완료하지 못했습니다.';

  @override
  String get keystoneShieldPrepareError => 'Keystone 서명을 준비하지 못했습니다.';

  @override
  String get keystoneShieldQrDecodeError =>
      '이 QR 코드를 Keystone 서명으로 해석할 수 없습니다.';

  @override
  String get keystoneShieldOpenSignedQr =>
      'Keystone에서 서명된 쉴드 QR을 연 후 다시 스캔하세요.';

  @override
  String get keystoneScanHoldSteady => 'QR 코드를 흔들리지 않게 전체가 보이도록 유지하세요.';

  @override
  String get keystoneToggleFlashlight => '플래시 켜기/끄기';

  @override
  String get keystoneCancelSigning => '서명 취소';

  @override
  String get keystoneShieldBroadcasting => '쉴드 거래 전파 중';

  @override
  String get keystoneShieldTransparentBalance => '투명 잔액 쉴드';

  @override
  String get keystoneShieldKeepOpen => '거래가 전송되는 동안 Vizor를 켜두세요.';

  @override
  String get keystoneShieldScanInstructions =>
      'Keystone 지갑으로 이 쉴드 QR 코드를 스캔한 후 기기의 안내를 따르세요.';

  @override
  String get keystoneCameraDenied =>
      '카메라 접근이 꺼져 있습니다. Keystone 서명을 스캔하려면 설정에서 허용하세요.';

  @override
  String get keystoneCameraUnavailable => '지금은 카메라를 사용할 수 없습니다.';

  @override
  String get keystoneReadingSignature => '서명 읽는 중...';

  @override
  String keystoneScanningProgress(int progress) {
    return '스캔 중... $progress%';
  }

  @override
  String get keystoneScanSignedQr => 'Keystone의 서명된 QR을 스캔하세요';

  @override
  String get keystoneBackToWallet => '지갑으로 돌아가기';

  @override
  String get keystoneShowQr => 'QR 보기';

  @override
  String get keystoneBroadcastingEllipsis => '전파 중...';

  @override
  String get keystoneNextStep => '다음 단계';

  @override
  String get homeShield => '쉴드';

  @override
  String get homeFirstTxPromptWrapped => '첫 ZEC 거래를\n시작해 보세요!';

  @override
  String get homeHangTight => '잠시만요... 시간이 걸릴 수 있습니다. Vizor를 켜둔 채로 유지하세요.';

  @override
  String get receiveNoActiveAccount => '활성 계정이 없습니다';

  @override
  String get receiveRenewShieldedError =>
      '쉴드 주소를 갱신하지 못했습니다. 다시 시도하거나 현재 주소를 사용하세요.';

  @override
  String receiveRenewShieldedErrorDetails(String details) {
    return '쉴드 주소를 갱신하지 못했습니다. 다시 시도하거나 현재 주소를 사용하세요.\n상세 정보: $details';
  }

  @override
  String receiveTitle(String ticker) {
    return '$ticker 받기';
  }

  @override
  String get receiveCopyTransparentAddress => '투명 주소 복사';

  @override
  String get receiveShareShieldedAddress => '쉴드 주소 공유';

  @override
  String get receiveShareTransparentAddress => '투명 주소 공유';

  @override
  String get receiveShielded => '쉴드';

  @override
  String get receiveTransparent => '투명';

  @override
  String get receiveQrUnavailable => 'QR 사용 불가';

  @override
  String get previewUsername => '사용자 이름';

  @override
  String get aboutKeplrTeamHeading => 'Keplr 팀이 만들었습니다';

  @override
  String get aboutKeplrTeamBody =>
      '저희는 Cosmos, Ethereum, Bitcoin에서 수백만 명이 사용하는 지갑 Keplr를 만들었습니다. Vizor는 저희가 생각하는 이상적인 Zcash 지갑입니다.';

  @override
  String get aboutShieldedHeading => '쉴드 Zcash를 위한 설계';

  @override
  String get aboutShieldedBody =>
      'Vizor는 보내는 사람, 받는 사람, 금액이 비공개로 유지되는 쉴드 거래를 중심으로 만들어졌습니다. 투명 Zcash도 사용할 수 있지만 기본은 프라이버시입니다.';

  @override
  String get aboutOpenSourceHeading => '오픈 소스, 자기 수탁';

  @override
  String get aboutOpenSourceBody =>
      'Vizor는 Apache 라이선스입니다. 키는 기기에만 보관됩니다.\n저희는 잔액이나 거래를 볼 수 없습니다.';

  @override
  String get aboutLegalPlaceholderHeading => 'Keplr Wallet을 만든 팀이 전합니다.';

  @override
  String get aboutLegalPlaceholderBody =>
      'Bitcoin이나 Ethereum과 달리 쉴드 Zcash 거래는 보내는 사람, 받는 사람, 금액을 숨깁니다.';

  @override
  String get aboutTermsOfUsage => '이용 약관';

  @override
  String get aboutPrivacyPolicy => '개인정보 처리방침';

  @override
  String get aboutVizorWallet => 'Vizor Wallet 정보';

  @override
  String get aboutWelcome => '시작하기';

  @override
  String get aboutOpenGithub => 'Vizor GitHub 열기';

  @override
  String get aboutWebsite => '웹사이트';

  @override
  String get aboutOpenWebsite => 'Vizor 웹사이트 열기';

  @override
  String get activitySendFailed => '보내기 실패';

  @override
  String get activitySending => '보내는 중';

  @override
  String get activityReceiving => '받는 중';

  @override
  String get activityReceived => '받음';

  @override
  String get activitySent => '보냄';

  @override
  String get activityShielded => '쉴드됨';

  @override
  String get activityRefunded => '환불됨';

  @override
  String get activityFailed => '실패';

  @override
  String get activityInProgress => '진행 중';

  @override
  String get activityCompleted => '완료';

  @override
  String get activityMixed => '혼합';

  @override
  String get activityEarlier => '이전';

  @override
  String get activityJustNow => '방금 전';

  @override
  String activityMinutesAgo(int minutes) {
    return '$minutes분 전';
  }

  @override
  String get activityThisWeek => '이번 주';

  @override
  String activityTodayAt(String time) {
    return '오늘 $time';
  }

  @override
  String activityYesterdayAt(String time) {
    return '어제 $time';
  }

  @override
  String activityDateAt(String date, String time) {
    return '$date $time';
  }

  @override
  String get activityNoActiveAccount => '활성 계정이 없습니다.';

  @override
  String get activityTxLoadError => '거래를 불러올 수 없습니다.';

  @override
  String get activityTxRefreshError => '최신 거래 상태를 갱신하지 못했습니다.';

  @override
  String get activityTxHashCopied => '거래 해시가 복사되었습니다';

  @override
  String get activityLoadingTx => '거래 불러오는 중…';

  @override
  String get activityLoadError => '활동을 불러올 수 없습니다.';

  @override
  String get activityTimestamp => '시간';

  @override
  String get activityTxId => '거래 ID';

  @override
  String get activityFrom => '보낸 곳';

  @override
  String get activityTo => '받는 곳';

  @override
  String get activityShowFullAddress => '전체 주소 보기';

  @override
  String get activityFromTransparentBalance => '투명 잔액에서';

  @override
  String get activityReceivingEllipsis => '받는 중...';

  @override
  String get activitySendingEllipsis => '보내는 중...';

  @override
  String get activitySentSuccessfully => '성공적으로 보냈습니다';

  @override
  String get swapFailedTitle => '스왑 실패';

  @override
  String get swapReviewQuote => '견적 검토';

  @override
  String get shieldReceiptInProgress => '쉴드 진행 중...';

  @override
  String get shieldReceiptCompleted => '성공적으로 쉴드했습니다';

  @override
  String get shieldReceiptFailed => '쉴드 실패';

  @override
  String get receiveReceiptInProgress => '받기 진행 중...';

  @override
  String get receiveReceiptCompleted => '성공적으로 받았습니다';

  @override
  String get receiveReceiptFailed => '받기 실패';

  @override
  String get receivedFeeTooltip => '이 거래를 처리하기 위해 보낸 사람이 지불한 네트워크 수수료입니다.';

  @override
  String get activityNetworkFee => '네트워크 수수료';

  @override
  String get activityMessage => '메시지';

  @override
  String get activityFailedFundsReturned => '실패, 자금 반환됨';

  @override
  String sendTitle(String ticker) {
    return '$ticker 보내기';
  }

  @override
  String get sendKeystoneNoTex => 'Keystone은 아직 TEX 전송을 지원하지 않습니다.';

  @override
  String get sendInsufficientBalance => '잔액 부족';

  @override
  String get sendInsufficientShieldedBalance => '쉴드 잔액 부족';

  @override
  String get sendInsufficientBalanceCoverFee => '수수료를 낼 잔액이 부족합니다';

  @override
  String get sendInsufficientShieldedBalanceCoverFee => '수수료를 낼 쉴드 잔액이 부족합니다';

  @override
  String get sendInsufficientBalanceIncludingFee => '수수료 포함 잔액이 부족합니다';

  @override
  String get sendInsufficientShieldedBalanceIncludingFee =>
      '수수료 포함 쉴드 잔액이 부족합니다';

  @override
  String sendInsufficientBalanceWithFee(String fee) {
    return '잔액 부족 (수수료: $fee)';
  }

  @override
  String sendInsufficientShieldedBalanceWithFee(String fee) {
    return '쉴드 잔액 부족 (수수료: $fee)';
  }

  @override
  String get sendMessageTooLong => '메시지가 너무 깁니다';

  @override
  String get sendMessageShieldedOnly => '메시지는 쉴드 주소로 보낼 때만 사용할 수 있습니다';

  @override
  String get sendNoActiveAccount => '활성 계정이 없습니다';

  @override
  String get sendEnterValidAddressForMax => '최대 금액을 사용하려면 유효한 주소를 입력하세요';

  @override
  String get sendMaxUnavailable => '최대 금액을 사용할 수 없습니다';

  @override
  String get sendInvalidAmount => '잘못된 금액';

  @override
  String get sendCalculatingMax => '최대 금액 계산 중';

  @override
  String get sendEnterValidAddress => '유효한 주소를 입력하세요';

  @override
  String get sendInvalidAddress => '잘못된 주소';

  @override
  String get sendAddressValidationFailed => '주소 검증에 실패했습니다';

  @override
  String get sendSendTo => '받는 주소';

  @override
  String get sendZcashAddressHint => 'Zcash 주소';

  @override
  String get sendZcashAddressHintMobile => 'Zcash 주소';

  @override
  String get sendAddMessageHint => '메시지 추가';

  @override
  String get sendCloseMessage => '메시지 닫기';

  @override
  String get sendContactsZcashTitle => 'Zcash 연락처';

  @override
  String get sendNoZcashContacts => 'Zcash 연락처가 없습니다';

  @override
  String get sendOpenContacts => '연락처 열기';

  @override
  String get sendSpendableTooltipTitle => '사용 가능한 잔액은 총 잔액보다 적을 수 있습니다.';

  @override
  String get sendSpendableTooltipBody =>
      '자금은 사용 전에 확인이 필요합니다: 내 지갑의 잔돈은 3회, 다른 사람에게 받은 자금은 10회. 쉴드 노트는 전체 스캔도 완료되어야 합니다. 곧 사용할 수 있게 됩니다.';

  @override
  String sendMaxLabel(String amount) {
    return '최대: $amount';
  }

  @override
  String get sendUseMaxBalance => '사용 가능한 최대 잔액 사용';

  @override
  String get sendSpendableInfo => '사용 가능한 잔액 안내';

  @override
  String get sendAddMemo => '메모 추가';

  @override
  String get sendEncryptedShieldedOnly => '암호화되며 쉴드 주소에만 적용됩니다.';

  @override
  String get sendScanKeystoneQr => 'Keystone QR 코드를 스캔하세요';

  @override
  String get keystoneSendQrDecodeError =>
      '이 QR 코드를 Keystone 거래 서명으로 해석할 수 없습니다.';

  @override
  String get keystoneOpenSignedTxQr => 'Keystone에서 서명된 거래 QR을 연 후 다시 스캔하세요.';

  @override
  String get keystoneScanQrTitle => 'QR 코드 스캔';

  @override
  String get keystoneHoldQrSteady => 'QR 코드를 카메라 앞에 흔들리지 않게 유지하세요';

  @override
  String get keystoneCameraOnly =>
      'Keystone 서명은 카메라 QR 스캔만 지원합니다. 카메라를 연결한 후 다시 시도하세요.';

  @override
  String get sendSigningCancelledParams => '증명 파라미터 다운로드 전에 서명이 취소되었습니다.';

  @override
  String get sendTxExpired => '서명 전에 거래가 만료되었습니다.';

  @override
  String get sendKeystonePrepareError =>
      'Keystone 서명을 준비하지 못했습니다. 보내기로 돌아가 다시 시도하세요.';

  @override
  String get sendKeystonePrepareErrorGoBack =>
      'Keystone 서명을 준비하지 못했습니다. 뒤로 돌아가 다시 시도하세요.';

  @override
  String get sendConfirmWithKeystone => 'Keystone으로 확인';

  @override
  String get sendConfirmAndSend => '확인 후 보내기';

  @override
  String get sendConfirmAndSendMobile => '확인 후 보내기';

  @override
  String get sendScanWithKeystone => 'Keystone으로 스캔하세요';

  @override
  String get sendAfterScanGetSignature => '스캔한 후 서명 가져오기를 클릭하세요.';

  @override
  String get sendScanNowProofs => '지금 스캔하세요. 증명이 준비되면 서명 가져오기가 활성화됩니다.';

  @override
  String get sendPreparing => '준비 중';

  @override
  String get sendPreparingEllipsis => '준비 중...';

  @override
  String get sendGetSignature => '서명 가져오기';

  @override
  String get sendNotEnoughZec => 'ZEC 부족';

  @override
  String get sendFinishReview => '완료 후 검토';

  @override
  String get sendEnterAmountToContinue => '계속하려면 금액을 입력하세요';

  @override
  String get sendEnterAddressToContinue => '계속하려면 주소를 입력하세요';

  @override
  String get addressTex => 'TEX 주소';

  @override
  String get sendSelectRecipient => '받는 사람 선택';

  @override
  String get sendEnterAmount => '금액 입력';

  @override
  String get sendReviewSend => '보내기 검토';

  @override
  String get sendScanAQrCode => 'QR 코드 스캔';

  @override
  String get sendScanAddressUsingCamera => '카메라로 주소를 스캔하세요';

  @override
  String sendContactCount(int count) {
    return '연락처 $count개';
  }

  @override
  String get sendPaste => '붙여넣기';

  @override
  String get sendClear => '지우기';

  @override
  String get sendSendingTo => '받는 사람';

  @override
  String get sendMax => '최대';

  @override
  String get sendEnterAmountInZec => 'ZEC로 금액 입력';

  @override
  String get sendEnterAmountInUsd => 'USD로 금액 입력';

  @override
  String get sendFullAddress => '전체 주소';

  @override
  String get sendAddShortEncryptedMessage => '짧은 암호화 메시지 추가';

  @override
  String get sendAboutTxFee => '거래 수수료 안내';

  @override
  String get sendAddMemoTitle => '메모 추가';

  @override
  String get sendOnlyRecipientCanRead => '받는 사람만 읽을 수 있습니다';

  @override
  String get sendClearMemo => '메모 지우기';

  @override
  String get sendReviewTitle => '보내기 검토';

  @override
  String get sendCollapse => '접기';

  @override
  String sendTexAddressLabel(String address) {
    return 'TEX - $address';
  }

  @override
  String get sendInProgressTitle => '보내는 중...';

  @override
  String sendAmountToRecipient(String amount, String recipient) {
    return '$recipient에게 $amount';
  }

  @override
  String get sendConfirmTransaction => '거래 확인';

  @override
  String get sendErrorInsufficientForAmountFee => '금액과 수수료를 감당할 쉴드 잔액이 부족합니다.';

  @override
  String get sendErrorNetwork => '네트워크 오류입니다. 연결을 확인하고 다시 시도하세요.';

  @override
  String get sendErrorPartialBroadcast =>
      '이 거래의 일부가 전송되었습니다. 다시 시도하기 전에 활동에서 전송된 내용을 확인하세요.';

  @override
  String get sendErrorBroadcastRejected => '네트워크가 이 거래를 거부했습니다. 다시 시도하세요.';

  @override
  String get sendErrorBroadcastRejectedLater =>
      '네트워크가 이 거래를 거부했습니다. 나중에 다시 시도하세요.';

  @override
  String get sendErrorExpiredTryAgain => '전송 전에 거래가 만료되었습니다. 다시 시도하세요.';

  @override
  String get sendErrorExpired => '전송 전에 거래가 만료되었습니다.';

  @override
  String get sendErrorGenericShort => '보내기에 실패했습니다. 다시 시도하세요.';

  @override
  String get sendErrorCheckStatus => '거래를 보내지 못했습니다. 지갑으로 돌아가 최신 상태를 확인하세요.';

  @override
  String get saplingDownloadRequired => '다운로드 필요';

  @override
  String get saplingDownloadBody =>
      '이 비공개 거래를 만들려면 지갑이 약 50MB의 암호화 파라미터를 다운로드해야 합니다.';

  @override
  String get saplingDownloadOnce =>
      '한 번만 다운로드하면 됩니다.\n네트워크 데이터 요금이 발생할 수 있습니다.';

  @override
  String get saplingDownload => '다운로드';

  @override
  String get accountsAddAccount => '계정 추가';

  @override
  String get accountsCurrent => '현재';

  @override
  String get accountsOther => '기타';

  @override
  String get accountsAccountActions => '계정 작업';

  @override
  String get accountsEditAccount => '계정 편집';

  @override
  String get accountsCopyAddress => '주소 복사';

  @override
  String get accountsSendZec => 'ZEC 보내기';

  @override
  String get accountsRemoveAccount => '계정 삭제';

  @override
  String accountsOptionsFor(String name) {
    return '$name 계정 옵션';
  }

  @override
  String get accountsRemoveResetWarning =>
      '이 계정을 삭제하면 Vizor 앱이 완전히 초기화됩니다. 모든 계정이 삭제되며 계정을 다시 가져와야 합니다.\n이 작업은 되돌릴 수 없습니다.';

  @override
  String get accountsRemoveWarning =>
      '정말 이 계정을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.\n계정을 다시 가져와야 합니다.';

  @override
  String get accountsResetVizor => 'Vizor 초기화';

  @override
  String get accountsCheckingSwaps => '삭제 전에 이 계정의 진행 중인 스왑을 확인하고 있습니다.';

  @override
  String get accountsSwapCheckFailed =>
      '이 계정의 진행 중인 스왑을 확인하지 못했습니다. 삭제하기 전에 다시 시도하세요.';

  @override
  String accountsActiveSwaps(int count) {
    return '이 계정에는 진행 중인 스왑이 $count건 있습니다. 계정을 삭제하기 전에 스왑 활동에서 완료하거나 삭제하세요.';
  }

  @override
  String get accountsIncorrectPassword => '비밀번호가 올바르지 않습니다. 다시 시도하세요.';

  @override
  String get accountsEnterPassword => '비밀번호를 입력하세요';

  @override
  String get accountsCheckingPassword => '비밀번호 확인 중...';

  @override
  String get accountsStoppingSync => '동기화 중지 중...';

  @override
  String get accountsResetting => '초기화 중...';

  @override
  String get accountsRemoving => '계정 삭제 중...';

  @override
  String get accountsChangeProfilePicture => '프로필 사진 변경';

  @override
  String get accountsSelectProfilePicture => '프로필 사진 선택';

  @override
  String get accountsClearAccountName => '계정 이름 지우기';

  @override
  String get accountsSaveEdits => '변경 사항 저장';

  @override
  String get accountsUpdatePicture => '사진 업데이트';

  @override
  String get accountsOtherAccounts => '다른 계정';

  @override
  String get accountsManageAccounts => '계정 관리';

  @override
  String get accountsNameHint => '1-20자';

  @override
  String get accountsNameLengthMessage => '최대 20자까지 사용할 수 있습니다.';

  @override
  String get accountsUpdateError => '계정을 업데이트하지 못했습니다.';

  @override
  String get abSearch => '검색';

  @override
  String get abSearchHint => '이름 또는 네트워크 검색';

  @override
  String get abEditContact => '연락처 편집';

  @override
  String get abRemoveContact => '연락처 삭제';

  @override
  String get abNoContactsYet => '아직 연락처가 없습니다';

  @override
  String get abAddFirstContact => '첫 연락처를 추가해 시작하세요.';

  @override
  String get abNoContactsFound => '연락처를 찾을 수 없습니다';

  @override
  String get abModifySearch => '검색어를 바꿔 보세요';

  @override
  String get abAddContact => '연락처 추가';

  @override
  String get abAddressLabel => '주소 이름';

  @override
  String get abAddLabelHint => '이름 추가 (1-20자)';

  @override
  String get abAddress => '주소';

  @override
  String get abAddAddressHint => '주소 추가';

  @override
  String get abScanAddressQr => '주소 QR 스캔';

  @override
  String get abChangeContactPicture => '연락처 사진 변경';

  @override
  String get abChainAndAddress => '체인 및 주소';

  @override
  String get abSelectNetwork => '네트워크 선택';

  @override
  String get abSelectContactPicture => '연락처 사진 선택';

  @override
  String get abSearchNetworkHint => '네트워크 검색';

  @override
  String get abNoNetworksFound => '네트워크를 찾을 수 없습니다';

  @override
  String get abContactWillBeRemoved => '이 연락처가 삭제됩니다.';

  @override
  String abNamedContactWillBeRemoved(String name) {
    return '$name이(가) 연락처에서 삭제됩니다.';
  }

  @override
  String get abLoadError => '연락처를 불러오지 못했습니다. 다시 시도하거나 문제가 계속되면 지원팀에 문의하세요.';

  @override
  String get abSaveError => '연락처를 저장하지 못했습니다. 다시 시도하세요.';

  @override
  String get abRemoveError => '연락처를 삭제하지 못했습니다. 다시 시도하세요.';

  @override
  String get abNoContactsFoundShort => '연락처가 없습니다';

  @override
  String get abSearchContacts => '연락처 검색';

  @override
  String get abCloseContacts => '연락처 닫기';

  @override
  String get abClearSearch => '검색어 지우기';

  @override
  String get abQrNoAddress => 'QR 코드에 주소가 없습니다.';

  @override
  String get abClearName => '이름 지우기';

  @override
  String get abClearAddress => '주소 지우기';

  @override
  String get abNetwork => '네트워크';

  @override
  String get abName => '이름';

  @override
  String get abAddNameHint => '이름 추가';

  @override
  String get abAddAnAddressHint => '주소 추가';

  @override
  String get abSaveContact => '연락처 저장';

  @override
  String get abRemoveContactQuestion => '연락처를 삭제할까요?';

  @override
  String get abNoPastTxEffect => '과거 거래에는 영향을 주지 않습니다.';

  @override
  String get abInvalidEvm => '유효하지 않은 EVM 주소';

  @override
  String get abInvalidBitcoin => '유효하지 않은 Bitcoin 주소';

  @override
  String get abInvalidSolana => '유효하지 않은 Solana 주소';

  @override
  String get abInvalidZcash => '유효하지 않은 Zcash 주소';

  @override
  String get abInvalidNear => '유효하지 않은 NEAR 주소';

  @override
  String get abNearHint => 'NEAR 계정은 보통 .near로 끝납니다. 주소를 다시 확인하세요.';

  @override
  String get abAddLabelError => '이름을 추가하세요';

  @override
  String get abLabelLength => '1-20자를 사용하세요';

  @override
  String get abAddAddressError => '주소를 추가하세요';

  @override
  String abScanNetworkQr(String network) {
    return '$network QR 코드 스캔';
  }

  @override
  String get keystoneScanReadingQr => 'QR 읽는 중...';

  @override
  String get cameraNoneFound => '카메라가 없습니다';

  @override
  String get cameraLoading => '카메라 불러오는 중...';

  @override
  String get cameraDefault => '기본 카메라';

  @override
  String cameraDefaultSuffix(String name) {
    return '$name (기본)';
  }

  @override
  String get cameraOpenError =>
      '카메라를 열 수 없습니다. 카메라가 연결되어 있고 다른 앱에서 사용 중이 아닌지 확인하세요.';

  @override
  String get cameraDeniedWindowsTitle => 'Windows 카메라 접근 허용';

  @override
  String get cameraDeniedTitle => '카메라 접근이 거부되었습니다';

  @override
  String get cameraDeniedWindowsDesc =>
      'Windows 설정에서 카메라 접근과 데스크톱 앱의 카메라 사용을 켜세요.';

  @override
  String get cameraDeniedDesc => '다시 요청하거나 시스템 설정에서\n직접 허용하세요.';

  @override
  String get cameraAllow => '카메라 허용';

  @override
  String get cameraRequestAgain => '다시 요청';

  @override
  String get cameraOpenSettings => '설정 열기';

  @override
  String get cameraEnableAccess => '카메라 접근 허용';

  @override
  String get cameraKeystoneRequired =>
      'Keystone을 연결하려면 카메라가 필요합니다.\n언제든지 설정에서 되돌릴 수 있습니다.';

  @override
  String get cameraUnavailableTitle => '카메라 사용 불가';

  @override
  String get troubleScanning => '스캔이 잘 안 되나요?';

  @override
  String get troubleTipFullScreen =>
      'Keystone에서 QR 코드를 탭해 전체 화면으로 표시하세요. 가장 쉬운 해결책입니다.';

  @override
  String get troubleTipDistance => 'Keystone을 카메라에서 조금 더 떨어뜨려 초점이 맞도록 하세요.';

  @override
  String get troubleTipLighting => '방이 충분히 밝고 QR 코드에 반사광이 없는지 확인하세요.';

  @override
  String get troubleTipContinuity => 'Mac에서는 연속성 카메라로 iPhone을 사용해 스캔할 수 있습니다.';

  @override
  String get cameraLabel => '카메라';

  @override
  String get cameraSelect => '카메라 선택';

  @override
  String get cameraDetailDefault => '기본';

  @override
  String get cameraDetailExternal => '외장';

  @override
  String get cameraDetailFront => '전면';

  @override
  String get cameraDetailBack => '후면';

  @override
  String get cameraDetailNormal => '일반';

  @override
  String get cameraDetailWide => '광각';

  @override
  String get cameraDetailZoom => '줌';

  @override
  String get keystonePrepareWallet => 'Keystone 지갑을 준비하세요';

  @override
  String get keystoneStepCheckFirmware => '1. Keystone 펌웨어 확인';

  @override
  String get keystoneStepPrepareConnect => '2. 연결 준비';

  @override
  String get keystoneOnYourKeystone => 'Keystone에서';

  @override
  String get keystoneStepTapConnect =>
      '오른쪽 위 •••을 탭한 후 Connect software wallet을 선택하세요.';

  @override
  String get keystoneStepSelectVizor => 'Vizor(또는 ZODL)를 선택하세요';

  @override
  String get keystoneOnVizor => 'Vizor에서';

  @override
  String get keystoneStepScanDynamicQr => 'Keystone의 동적 QR 코드를 스캔하세요.';

  @override
  String get keystoneFirmwareNote => 'Keystone이 최신 Cypherpunk 펌웨어인지 확인하세요. ';

  @override
  String get keystoneDownloadFirmware => 'Keystone 펌웨어 다운로드';

  @override
  String get keystoneNoZcashAccounts => '이 Keystone QR에서 Zcash 계정을 찾을 수 없습니다.';

  @override
  String get keystoneAccountQrDecodeError =>
      '이 QR 코드를 Keystone Zcash 계정으로 해석할 수 없습니다.';

  @override
  String get keystoneOpenAccountQr => 'Keystone에서 Zcash 계정 QR을 연 후 다시 스캔하세요.';

  @override
  String get keystoneReadingAccounts => '계정 읽는 중...';

  @override
  String get keystoneImportCameraOnly =>
      'Keystone 가져오기는 카메라 QR 스캔만 지원합니다. 카메라를 연결한 후 다시 시도하세요.';

  @override
  String get keystoneSelectAccount => '계정 선택';

  @override
  String keystoneAccountsFound(int count) {
    return '계정 $count개를 찾았습니다';
  }

  @override
  String keystoneAccountFallback(int index) {
    return '계정 $index';
  }

  @override
  String get keystoneScanAccountQr => 'Keystone 계정 QR을 스캔하세요';

  @override
  String get onbEstimatingHeight => '높이 추정 중...';

  @override
  String get onbCheckingAccounts => '계정 확인 중...';

  @override
  String get onbPausingSync => '동기화 일시 중지 중...';

  @override
  String get onbImportingWallet => '지갑 가져오는 중...';

  @override
  String get onbSelectMonth => '월 선택';

  @override
  String get onbSelectDate => '날짜 선택';

  @override
  String get onbBirthdayTitle => '지갑을 언제쯤 만드셨나요?';

  @override
  String get onbBirthdaySubtitle => '대략적인 추정이면 충분합니다.\n동기화가 거기서부터 시작됩니다.';

  @override
  String get onbDontRemember => '기억나지 않아요';

  @override
  String get onbEnterMonth => '월 입력';

  @override
  String get onbEnterDate => '날짜 입력';

  @override
  String get onbEnterBlockHeight => '블록 높이 입력';

  @override
  String get onbBlockHeight => '블록 높이';

  @override
  String onbAtLeastHeight(String height) {
    return '$height 이상.';
  }

  @override
  String onbBetweenHeights(String min, String max) {
    return '$min에서 $max 사이.';
  }

  @override
  String get onbPickMonth => '월을 선택하세요';

  @override
  String get onbPickDate => '날짜를 선택하세요';

  @override
  String get onbEstimateFailed => '해당 날짜의 높이를 추정하지 못했습니다. 블록 높이를 직접 입력하세요.';

  @override
  String get scanZcashQrCaption => '계속하려면 Zcash QR 코드를 스캔하세요';

  @override
  String get scanAddressQrTitle => '주소 QR 코드를 스캔하세요';

  @override
  String get scanNeedsCamera => 'QR 스캔에는 이 기기의 카메라가 필요합니다.';

  @override
  String get scanAddressNeedsCamera => '주소 QR 스캔에는 이 기기의 카메라가 필요합니다.';

  @override
  String get scanAddressRequiresCamera => '주소 QR 스캔에는 이 기기의 카메라가 필요합니다.';

  @override
  String get scanCloseScanner => '스캐너 닫기';

  @override
  String get scanLoadingEllipsis => '불러오는 중...';

  @override
  String get scanLoading => '불러오는 중';

  @override
  String get scanGrantCameraAccess => '카메라 접근을 허용하세요';

  @override
  String get scanQrNoAddress => 'QR 코드에 주소가 없습니다.';

  @override
  String get scanCameraDeniedTitle => '카메라 접근이 거부되었습니다';

  @override
  String get keystoneLoadingQr => 'QR 코드 불러오는 중 ...';

  @override
  String get keystoneSignQrDecodeError => '이 QR 코드를 Keystone 서명으로 해석할 수 없습니다.';

  @override
  String get keystoneSignPrepareError => 'Keystone 서명을 준비하지 못했습니다.';

  @override
  String get keystoneScanSignedKeystoneQr => '서명된 Keystone QR을 스캔하세요';

  @override
  String get keystoneSignNeedsCamera => 'Keystone 서명에는 이 기기의 카메라가 필요합니다.';

  @override
  String get keystoneCloseSigning => 'Keystone 서명 닫기';

  @override
  String get onbWelcomeToVizor => 'Vizor에 오신 것을 환영합니다';

  @override
  String get onbSelectMethod => '원하는 방법을 선택하세요.';

  @override
  String get onbCreateWallet => '지갑 생성';

  @override
  String get onbImportWallet => '지갑 가져오기';

  @override
  String get onbAgreePrefix => 'Vizor를 사용하면 다음에 동의하는 것입니다: ';

  @override
  String get onbTerms => '이용 약관';

  @override
  String get onbPrivacy => '개인정보 처리방침';

  @override
  String get onbEndpointSettings => '엔드포인트 설정';

  @override
  String get onbPrivateMoney => '기본이 프라이버시인\n화폐';

  @override
  String get onbGetStarted => 'Vizor와 함께\n시작하세요';

  @override
  String get onbCreateAWallet => '지갑 생성';

  @override
  String get onbImportAWallet => '지갑 가져오기';

  @override
  String get onbIncorrectPassword => '비밀번호가 올바르지 않습니다.';

  @override
  String get onbWelcomeBack => '다시 오신 것을 환영합니다';

  @override
  String get onbEnterPasswordToOpen => 'Vizor를 열려면 비밀번호를 입력하세요.';

  @override
  String get onbEnterPassword => '비밀번호 입력';

  @override
  String get onbUnlockVizor => 'Vizor 잠금 해제';

  @override
  String get onbForgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String onbResetAfterSeconds(int seconds) {
    return '$seconds초 후 초기화...';
  }

  @override
  String get onbCannotBeUndone => '이 작업은 되돌릴 수 없습니다.';

  @override
  String get onbLostPassword => '비밀번호를 잃어버리셨나요?';

  @override
  String get onbLostPasswordBodyPrefix => '비밀번호를 잃어버렸다면 계정을 복구하는 유일한 방법은 ';

  @override
  String get onbLostPasswordReset => 'Vizor 앱을 완전히 초기화';

  @override
  String get onbLostPasswordBodyMiddle => '하는 것입니다. 이 경우 모든 계정이 삭제되며\n';

  @override
  String get onbLostPasswordReimport => '계정을 다시 가져와야 합니다';

  @override
  String get walletResetFailed => 'Vizor를 초기화하지 못했습니다. 다시 시도하세요.';

  @override
  String get storageDbUpdateStillFailed => '지갑 데이터베이스 업데이트가 여전히 실패했습니다.';

  @override
  String get storageStillUnavailable => '보안 저장소를 여전히 사용할 수 없습니다.';

  @override
  String get storageRetrying => '재시도 중';

  @override
  String get storageQuit => '종료';

  @override
  String get storageDbUpdateTitle => '지갑 데이터베이스를 업데이트할 수 없습니다';

  @override
  String get storageOpenFailedTitle => 'Vizor를 열 수 없습니다';

  @override
  String get storageUnlockKeyring => '키링을 잠금 해제하세요';

  @override
  String get storageLockedTitle => '보안 저장소가 잠겨 있습니다';

  @override
  String get storageDbUpdateBody =>
      '이 버전을 열기 전에 Vizor가 로컬 지갑 데이터베이스를 업데이트해야 합니다. 다시 시도하거나 Vizor를 종료 후 재시작하세요.';

  @override
  String get storageStartupBody =>
      'Vizor가 로컬 시작 상태를 불러오지 못했습니다. 다시 시도하거나 Vizor를 종료 후 재시작하세요.';

  @override
  String get storageKeyringBody =>
      '지갑을 열기 전에 Vizor가 시스템 키링에 접근해야 합니다. 키링을 잠금 해제한 후 다시 시도하세요.';

  @override
  String get storageSecureBody =>
      '지갑을 열기 전에 Vizor가 보안 저장소에 접근해야 합니다. 보안 저장소를 잠금 해제한 후 다시 시도하세요.';

  @override
  String get onbPasswordsDoNotMatch => '비밀번호가 일치하지 않습니다.';

  @override
  String get onbPasswordHint => '최소 8자, 기호 포함';

  @override
  String get onbConfirmPassword => '비밀번호 확인';

  @override
  String get onbSetPassword => '비밀번호 설정';

  @override
  String get onbSetPasswordSubtitle => 'Vizor 지갑 로그인 비밀번호를 설정하세요.';

  @override
  String get onbStopSyncing => '동기화 중지 중...';

  @override
  String get onbSettingPassword => '비밀번호 설정 중...';

  @override
  String get onbSetPasswordFinish => '비밀번호 설정 및 완료';

  @override
  String get onbSecretPassphrase => '비밀 복구 구문';

  @override
  String get onbMasterKeySubtitle => '지갑의 마스터 키입니다.';

  @override
  String get onbCreatingWallet => '지갑 생성 중...';

  @override
  String get onbRevealPhrase => '구문 표시';

  @override
  String get onbAboutToSeePrefix => '지금 ';

  @override
  String get onbAboutToSeeSuffix => '비밀 복구 구문을 확인합니다.';

  @override
  String get onbPhraseWarning =>
      '이 구문은 자금의 마스터 키입니다. 안전하게, 비밀로 보관하세요. 잃어버리면 누구도 지갑 복구를 도울 수 없습니다. 저희조차도요.';

  @override
  String get onbCopied => '복사됨';

  @override
  String get onbWelcomeStep => '시작';

  @override
  String get onbShieldedWorld => '쉴드의 세계';

  @override
  String get onbZecIntro => '금융 프라이버시와 자기 수탁을 위해 만들어진 Zcash(ZEC).';

  @override
  String get onbZecPrivacyBody =>
      'Bitcoin이나 Ethereum과 달리 쉴드 Zcash 거래는 보내는 사람, 받는 사람, 금액을 숨깁니다. 신뢰가 아닌 암호학으로 검증됩니다.';

  @override
  String get onbTellMeHow => 'Zcash 작동 방식 알아보기';

  @override
  String get onbIKnowZcash => 'Zcash 사용법을 알고 있어요';

  @override
  String get onbStepIntro => 'Zcash 소개';

  @override
  String get onbStepAddressTypes => '주소 유형';

  @override
  String get onbStepThingsToKnow => '알아둘 사항';

  @override
  String get onbZcashAddressTypes => 'Zcash 주소 유형';

  @override
  String get onbTwoAddressTypes =>
      'Zcash에는 두 가지 주소 유형이 있습니다.\n하나는 프라이버시용, 하나는 투명성용입니다.';

  @override
  String get onbAddressStartsWith => '주소가 다음으로 시작합니다: ';

  @override
  String get onbShieldedAddressSuffix => ' — 레거시). 계정 잔액과 거래 내역은 본인만 볼 수 있습니다.';

  @override
  String get onbShieldedAddressOr => ' (또는 ';

  @override
  String get onbTransparentAddressBody =>
      '주소가 t로 시작하며, Bitcoin처럼 주소의 잔액과 거래 내역이 공개적으로 표시됩니다.';

  @override
  String get onbThingsToKnow => '알아둘 사항';

  @override
  String get onbTimeToSync => '동기화 시간';

  @override
  String get onbTimeToSyncBody =>
      '지갑이 서버에 의존하지 않고 Zcash 네트워크와 직접 동기화합니다. 프라이버시를 보호하지만 시간이 조금 걸립니다. 앱이 따라잡는 동안에도 자금은 안전합니다.';

  @override
  String get onbKeepPrivacy => '프라이버시 유지 방법';

  @override
  String get onbKeepPrivacyBody =>
      '일부 거래소는 쉴드 주소로 보낼 수 없습니다. 거래소에서 출금할 때는 투명 주소를 사용하세요. ZEC가 도착한 후 쉴드할 수 있습니다.';

  @override
  String get keystoneSendScanInstructions =>
      'Keystone 지갑으로 이 거래 QR 코드를 스캔한 후 기기의 안내를 따르세요.';

  @override
  String get activityNoActivityYet => '아직 활동이 없습니다';

  @override
  String get activityShieldedSender => '쉴드 보낸 사람';

  @override
  String get activityUnknownSender => '알 수 없는 보낸 사람';

  @override
  String get addressUnified => '통합 주소';

  @override
  String get addressZcash => 'Zcash 주소';

  @override
  String get receiveGenerateNewShielded => '새 쉴드 주소 생성';

  @override
  String get receiveAboutAddressType => '이 주소 유형에 대하여';

  @override
  String get receiveShieldedAddressTitle => '쉴드 주소';

  @override
  String get receiveTransparentAddressTitle => '투명 주소';

  @override
  String get receiveShieldedSubtitle => '기본적으로 강력한 프라이버시.';

  @override
  String get receiveTransparentSubtitle => '공개적으로 표시됨';

  @override
  String get receiveShieldedInfoPrivacyTouch =>
      '거래 상세 정보(보내는 사람, 받는 사람, 금액)는 온체인에서 암호화되어 숨겨집니다.';

  @override
  String get receiveShieldedInfoPrivacyPointer =>
      '거래 상세 정보(보내는 사람, 받는 사람, 금액)는 온체인에서 암호화되어 숨겨집니다.';

  @override
  String get receiveShieldedInfoRenewTap =>
      '갱신 버튼을 탭할 때만 새 Zcash 쉴드 주소가 생성됩니다.';

  @override
  String get receiveShieldedInfoRenewClick =>
      '갱신 버튼을 클릭할 때만 새 Zcash 쉴드 주소가 생성됩니다.';

  @override
  String get receiveShieldedInfoDiversified =>
      '새 주소는 모두 같은 키에서 파생된 다변화 주소입니다. 모두 같은 지갑으로 입금됩니다.';

  @override
  String get receiveTransparentInfoPublicTouch =>
      '모든 거래 상세 정보(보내는 사람, 받는 사람, 금액)는 온체인에 공개적으로 표시됩니다.';

  @override
  String get receiveTransparentInfoPublicPointer =>
      '모든 거래 상세 정보(보내는 사람, 받는 사람, 금액)는 온체인에 공개적으로 표시됩니다.';

  @override
  String get receiveTransparentInfoExchanges =>
      '투명성이나 규제 준수가 필요한 거래소에서 흔히 사용됩니다. 여러 지갑과의 호환성을 위한 기본값이기도 합니다.';

  @override
  String get receiveTransparentInfoRotation =>
      '이 주소로 ZEC를 받고 Vizor가 동기화되면 다음 투명 주소가 자동으로 바뀝니다. 이전 주소도 계속 이 지갑에 속합니다.';

  @override
  String receiveTransparentInfoShieldGuide(String ticker) {
    return '투명 주소로 $ticker를 받으면 Vizor가 잔액을 쉴드하도록 안내합니다. 쉴드하지 않으면 보낼 수 없습니다.';
  }

  @override
  String get inputClearText => '텍스트 지우기';

  @override
  String backToLabel(String label) {
    return '$label(으)로 돌아가기';
  }

  @override
  String get txFeeHelpTooltip => '이 거래를 처리하기 위해 Zcash 네트워크에 지불하는 수수료입니다.';

  @override
  String get txFeeSheetTitle => '거래 수수료';

  @override
  String get txFeeSheetBody =>
      '네트워크 수수료는 거래 크기에 따라 Zcash 프로토콜(ZIP 317)이 정합니다. Vizor는 추가 수수료를 받지 않습니다.';

  @override
  String get sheetNotAvailableTitle => '아직 사용할 수 없습니다';

  @override
  String get sheetNotAvailableBody => '이 기능은 아직 준비 중입니다.';

  @override
  String get onbStepWalletBirthdayHeight => '지갑 생성 높이';

  @override
  String get onbStepHowToConnect => '연결 방법';

  @override
  String get onbStepScanQrCode => 'QR 코드 스캔';

  @override
  String get onbStepSelectAccount => '계정 선택';

  @override
  String get onbBirthdayMetadataError => '지갑 생성일 정보를 불러오지 못했습니다.';

  @override
  String get onbBirthdayEstimateError => '지갑 생성 높이를 추정하지 못했습니다.';

  @override
  String get onbImporting => '가져오는 중...';

  @override
  String get onbEstimating => '추정 중...';

  @override
  String get onbCantRemember => '기억나지 않아요';

  @override
  String get onbDateHint => 'yyyy. m. d.';

  @override
  String get onbBlockHeightHint => '블록 높이';

  @override
  String get onbUnknownHeightTitle => '가장 이른 높이부터 가져올까요?';

  @override
  String get onbUnknownHeightBody =>
      '지갑 생성일 없이 계속하면 Vizor는 지원되는 가장 이른 쉴드 높이부터 스캔합니다. 안전하지만 첫 동기화에 매우 오랜 시간이 걸릴 수 있습니다.';

  @override
  String get onbUnknownHeightHint => '대략적인 날짜만 선택해도 훨씬 빠릅니다.';

  @override
  String get onbContinueAnyway => '그래도 계속';

  @override
  String get onbGoBack => '돌아가기';

  @override
  String get onbErrorDuplicateAccount => '이 계정은 이미 지갑에 있습니다.';

  @override
  String get onbErrorDuplicateKeystoneAccount => '이 Keystone 계정은 이미 지갑에 있습니다.';

  @override
  String get onbErrorCurrentBlockHeight =>
      '지갑을 만들려면 현재 Zcash 블록 높이가 필요합니다. 네트워크 연결을 확인하고 다시 시도하세요.';

  @override
  String get onbZecIntroMobile => '재정적 프라이버시와 자기 수탁을 위해\n만들어진 Zcash (ZEC).';

  @override
  String get onbFewStepsAway => '첫 프라이빗 지갑까지 몇 단계만 남았습니다. 시작해 볼까요?';

  @override
  String get onbTwoAddressTypesMobile =>
      'Zcash에는 두 가지 주소 유형이 있습니다.\n하나는 프라이버시용, 하나는 투명성용입니다.';

  @override
  String get onbShieldedAddress => '쉴드 주소';

  @override
  String get onbTransparentAddress => '투명 주소';

  @override
  String get onbShieldedAddressBodyMobile =>
      '주소는 u1으로 시작합니다(레거시는 zs).\n계정 잔액과 거래 내역은 본인만 볼 수 있습니다.';

  @override
  String get onbBeforeYouDiveIn => '시작하기 전에 알아두세요.';

  @override
  String get onbInvalidPassphraseWordCount =>
      '12, 15, 18, 21 또는 24개 단어로 된 유효한 비밀 복구 구문을 입력하세요.';

  @override
  String get onbWelcomeAdventurer => '환영합니다, 모험가님';

  @override
  String get onbImportByPassphrase => '비밀 복구 구문을 입력해 지갑을 가져오세요.';

  @override
  String get onbWordHint => '단어';

  @override
  String onbPassphraseWordCountFound(int count) {
    return '비밀 복구 구문은 12, 15, 18, 21 또는 24개 단어입니다 — $count개가 입력되었습니다.';
  }

  @override
  String get onbPassphraseInvalidOrder =>
      '단어들은 유효하지만 올바른 비밀 복구 구문이 아닙니다. 순서를 확인하거나 잘못된 단어를 바꿔 주세요.';

  @override
  String get onbPassphraseCheckFailed => '구문을 확인하지 못했습니다. 다시 시도하세요.';

  @override
  String get onbImportWalletTitle => '지갑 가져오기';

  @override
  String get onbImportWalletSubtitleMobile =>
      '비밀 복구 구문을 붙여넣거나\n단어를 하나씩 직접 입력하세요.';

  @override
  String get onbConfirmAndImport => '확인 후 가져오기';

  @override
  String get onbClearSecretPhrase => '비밀 구문 지우기';

  @override
  String get onbPasteSecretPhrase => '비밀 구문 붙여넣기';

  @override
  String get onbEnterManually => '직접 입력';

  @override
  String get onbEnterSecretPhraseManually => '비밀 구문 직접 입력';

  @override
  String get onbClipboardEmpty => '클립보드가 비어 있습니다';

  @override
  String get onbClipboardReadFailed => '클립보드 데이터를 읽을 수 없습니다';

  @override
  String get onbUnlockBiometricReason => '지갑 잠금 해제';

  @override
  String get onbIncorrectPasscode => '잘못된 패스코드입니다';

  @override
  String get onbWelcomeBackMobile => '다시 오신 것을 환영합니다';

  @override
  String get onbOpeningWallet => '지갑 여는 중...';

  @override
  String get onbEnterPasscodeToOpen => '패스코드를 입력해 Vizor를 여세요';

  @override
  String get onbMasterKeySubtitleMobile => '지갑의 마스터 키입니다.';

  @override
  String get onbRevealPhraseMobile => '구문 표시';

  @override
  String get onbAboutToSeeMobile => '지금부터\n비밀 복구 구문이 표시됩니다.';

  @override
  String get keystoneConnectTitle => 'Keystone 연결';

  @override
  String get keystoneCheckFirmware => 'Keystone 펌웨어 확인';

  @override
  String get keystonePrepareToConnect => '연결 준비';

  @override
  String get keystoneFirmwareBody => 'Keystone이 최신 Cypherpunk 펌웨어인지 확인하세요. ';

  @override
  String get keystoneLink => '링크';

  @override
  String get keystoneNoAccountsFound => '이 Keystone QR에서 Zcash 계정을 찾지 못했습니다.';

  @override
  String get keystoneConfirmSelection => '선택 확인';

  @override
  String get biometricFaceId => 'Face ID';

  @override
  String get biometricFingerprintInline => '지문';

  @override
  String get biometricBiometricsInline => '생체 인식';

  @override
  String get biometricFingerprintStandalone => '지문';

  @override
  String get biometricBiometricsStandalone => '생체 인식';

  @override
  String get biometricYourFingerprint => '지문';

  @override
  String get biometricUnlockFeatureFace => 'Face ID 잠금 해제';

  @override
  String get biometricUnlockFeatureFingerprint => '지문 잠금 해제';

  @override
  String get biometricUnlockFeatureNone => '생체 인식 잠금 해제';

  @override
  String get biometricUnlockFeatureInlineFingerprint => '지문 잠금 해제';

  @override
  String get biometricUnlockFeatureInlineNone => '생체 인식 잠금 해제';

  @override
  String get biometricChangedFace => 'Face ID가 변경되었습니다. 패스코드를 입력하세요.';

  @override
  String get biometricChangedFingerprint => '지문이 변경되었습니다. 패스코드를 입력하세요.';

  @override
  String get biometricChangedNone => '생체 인식 정보가 변경되었습니다. 패스코드를 입력하세요.';

  @override
  String biometricEnable(String method) {
    return '$method 사용';
  }

  @override
  String biometricSignIn(String method) {
    return '$method로 로그인';
  }

  @override
  String biometricFeatureOff(String feature) {
    return '$feature 꺼짐';
  }

  @override
  String biometricFeatureOn(String feature) {
    return '$feature 켜짐';
  }

  @override
  String biometricSetUpFirst(String method) {
    return '먼저 기기 설정에서 $method을(를) 설정하세요.';
  }

  @override
  String biometricUpdateFailed(String feature) {
    return '$feature을(를) 변경하지 못했습니다.';
  }

  @override
  String biometricTurnOffTitle(String feature) {
    return '$feature을(를) 끌까요?';
  }

  @override
  String biometricTurnOffBody(String feature) {
    return '패스코드로 Vizor 잠금을 해제하게 됩니다. 언제든지 설정에서 $feature을(를) 다시 켤 수 있습니다.';
  }

  @override
  String biometricEnableFailed(String method) {
    return '$method을(를) 사용하도록 설정하지 못했습니다. 설정에서 다시 시도할 수 있습니다.';
  }

  @override
  String onbBiometricsTitle(String method) {
    return '$method로\n지갑 잠금 해제';
  }

  @override
  String get onbBiometricsSubtitle =>
      '쉽고 빠르게 로그인하는 방법입니다.\n언제든지 패스코드로 되돌릴 수 있습니다.';

  @override
  String get onbNotNow => '나중에';

  @override
  String passcodeDigitLabel(int digit) {
    return '숫자 $digit';
  }

  @override
  String get passcodeHelpLabel => '패스코드 도움말';

  @override
  String get passcodeDeleteDigit => '숫자 지우기';

  @override
  String get onbCopySecretPassphrase => '비밀 복구 구문 복사';

  @override
  String get onbPrivateMoneyMobile => '프라이빗 머니.\n기본으로';

  @override
  String get onbGetStartedShort => '시작하기';

  @override
  String get onbAnd => ' 및 ';

  @override
  String get onbOr => '또는';

  @override
  String get keystoneSubmittingTransaction => '트랜잭션 제출 중';

  @override
  String get onbMonthHint => 'yyyy. m.';

  @override
  String get onbForgotPasscodeTitle => '패스코드를 잊으셨나요?';

  @override
  String get onbForgotPasscodeBody =>
      '패스코드가 기억나지 않으면 계정을 복구하는 유일한 방법은 Vizor 앱을 완전히 초기화하는 것입니다. 이 경우 모든 계정이 삭제되며 계정을 다시 가져와야 합니다.';

  @override
  String get onbContinueToReset => 'Vizor 초기화 진행';

  @override
  String get onbResetVizor => 'Vizor 초기화';

  @override
  String get onbAreYouSure => '정말 진행할까요?';

  @override
  String get onbCantBeUndone => '되돌릴 수 없습니다.\n';

  @override
  String get onbProceedResponsibility => '본인 책임 하에 진행하세요.';

  @override
  String get onbSettingUpWallet => '지갑 설정 중...';

  @override
  String get onbReenterPasscode => '패스코드를 다시 입력하세요.';

  @override
  String get onbSixDigitsLength => '6자리 숫자';

  @override
  String get onbConfirmPasscode => '패스코드 확인';

  @override
  String get onbCreatePasscode => '패스코드 만들기';

  @override
  String get onbAdditionalAccountsFound => '추가 계정을 찾았습니다';

  @override
  String get onbChooseAdditionalAccounts => '가져올 추가 계정을 선택하세요.';

  @override
  String get onbImportAction => '가져오기';

  @override
  String get onbBalanceLoading => '불러오는 중';

  @override
  String get onbTransparentLabel => '투명';

  @override
  String get onbContinueAnywayLower => '그래도 계속';

  @override
  String get onbGoBackLower => '돌아가기';

  @override
  String onbWordNotInList(String word) {
    return '\'$word\'은(는) 복구 구문 단어 목록에 없습니다.';
  }

  @override
  String onbStoppedAtWord(String word) {
    return '\'$word\'에서 중단되었습니다 — 복구 구문 단어 목록에 없습니다.';
  }

  @override
  String get onbNextWord => '다음 단어';

  @override
  String get onbEnterYourPassphrase => '비밀 복구 구문 입력';

  @override
  String get onbAcceptWordCounts => '12, 15, 18, 21 또는 24개 단어 입력';

  @override
  String get onbUndoLastWord => '마지막 단어 취소';

  @override
  String get swapStatusAwaitingDeposit => '입금 대기 중';

  @override
  String get swapStatusAwaitingExternalDeposit => '외부 입금 대기 중';

  @override
  String get swapStatusDepositObserved => '입금 확인됨';

  @override
  String get swapStatusProcessing => '처리 중';

  @override
  String get swapStatusChecking => '상태 확인 중';

  @override
  String get swapStatusIncompleteDeposit => '입금 미완료';

  @override
  String get swapStatusComplete => '완료';

  @override
  String get swapStatusRefunded => '환불됨';

  @override
  String get swapStatusExpired => '만료됨';

  @override
  String get swapStatusFailed => '실패';

  @override
  String get swapTitleCompleted => '스왑 완료';

  @override
  String get swapTitleFailed => '스왑 실패';

  @override
  String get swapTitleInProgress => '스왑 진행 중...';

  @override
  String swapToAddressOnChain(String address, String chain) {
    return '받는 주소: $address ($chain)';
  }

  @override
  String swapRefundToAddress(String address) {
    return '환불 주소: $address';
  }

  @override
  String get swapVerbSending => '보내는 중';

  @override
  String get swapVerbDepositing => '입금 중';

  @override
  String swapSymbolSent(String symbol) {
    return '$symbol 보냄';
  }

  @override
  String swapSymbolDeposited(String symbol) {
    return '$symbol 입금됨';
  }

  @override
  String swapDeliverSymbol(String symbol) {
    return '$symbol 전달';
  }

  @override
  String swapSendSymbol(String symbol) {
    return '$symbol 보내기';
  }

  @override
  String swapDepositSymbol(String symbol) {
    return '$symbol 입금';
  }

  @override
  String get swapLastCheckJustNow => '마지막 확인: 방금 전';

  @override
  String swapLastCheckMinutesAgo(int minutes) {
    return '마지막 확인: $minutes분 전';
  }

  @override
  String get swapStepSourceDesc => '소스 체인과 제공자가 입금을 인식할 때까지 기다립니다';

  @override
  String get swapStepDepositConfirmation => '입금 확인';

  @override
  String get swapStepDepositConfirmationActive => '입금 확인 중...';

  @override
  String get swapStepConfirmingDesc => '스왑 경로가 시작되기 전에 입금을 확인합니다.';

  @override
  String get swapStepSwapTitle => '스왑';

  @override
  String get swapStepSwapActive => '스왑 중...';

  @override
  String get swapStepSwapDesc => '제공자가 스왑 경로를 실행하고 있습니다.';

  @override
  String get swapStepDeliveryDesc => '출력 자산을 수신자 주소로 전달합니다.';

  @override
  String get swapRealizedSlippageLabel => '실현 슬리피지';

  @override
  String get swapNotReported => '보고되지 않음';

  @override
  String get swapTimestampLabel => '시각';

  @override
  String swapDepositTxLabel(String symbol) {
    return '$symbol 입금 tx';
  }

  @override
  String swapRefundedToLabel(String symbol) {
    return '$symbol 환불된 주소';
  }

  @override
  String get swapTotalFeesLabel => '총 수수료';

  @override
  String get swapIncluded => '포함됨';

  @override
  String swapRecipientLabel(String symbol) {
    return '$symbol 수신자';
  }

  @override
  String swapRefundAddressLabel(String symbol) {
    return '$symbol 환불 주소';
  }

  @override
  String swapDepositToLabel(String symbol) {
    return '$symbol 입금 주소';
  }

  @override
  String get swapMemoLabel => '메모';

  @override
  String get swapSlippageToleranceLabel => '슬리피지 허용치';

  @override
  String get swapConfiguredQuote => '설정된 견적';

  @override
  String get swapGuaranteedMinimumLabel => '보장 최소 수량';

  @override
  String swapDeliveryTxLabel(String symbol) {
    return '$symbol 전달 tx';
  }

  @override
  String get swapFeeLabel => '스왑 수수료';

  @override
  String get swapIncludedInRate => '표시된 환율에 포함';

  @override
  String get swapTxIdLabel => 'Tx ID';

  @override
  String get swapMissingDepositLabel => '부족한 입금액';

  @override
  String get swapRequiredDepositLabel => '필요 입금액';

  @override
  String get swapDetectedDepositLabel => '감지된 입금액';

  @override
  String get swapDepositDeadlineRowLabel => '입금 기한';

  @override
  String get swapRefundFeeLabel => '환불 수수료';

  @override
  String swapHoursShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count시간',
    );
    return '$_temp0';
  }

  @override
  String swapMinutesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count분',
    );
    return '$_temp0';
  }

  @override
  String swapSendFromSourceChain(String symbol) {
    return '$symbol을(를) 소스 체인에서 보내기';
  }

  @override
  String swapDepositLabelShort(String symbol) {
    return '$symbol 입금';
  }

  @override
  String swapSourceDepositLabel(String symbol) {
    return '$symbol 소스 입금';
  }

  @override
  String swapDepositTxHashLabel(String symbol) {
    return '$symbol 입금 tx 해시';
  }

  @override
  String swapDepositTxHashHint(String symbol) {
    return '$symbol 소스 체인 트랜잭션 해시';
  }

  @override
  String swapSubmitDeposit(String symbol) {
    return '$symbol 입금 제출';
  }

  @override
  String get swapDoNotReuseAddress => '이 주소를 재사용하지 마세요';

  @override
  String swapMinReceiveTooltip(String symbol) {
    return '슬리피지 적용 후 받게 될 최소 $symbol 수량입니다. 더 받을 수는 있어도 덜 받지는 않습니다.';
  }

  @override
  String get swapGenericMinReceiveTooltip =>
      '슬리피지 적용 후 받게 될 최소 수량입니다. 더 받을 수는 있어도 덜 받지는 않습니다.';

  @override
  String get swapFeeTooltipText =>
      '이 스왑을 처리하기 위한 당사 수수료와 경로 제공자 비용을 포함합니다. 위에 표시된 환율에 이미 포함되어 있습니다.';

  @override
  String get swapStatusDetailTooltipText =>
      '세부 정보는 최신 스왑 기록과 제공자 상태를 기반으로 합니다.';

  @override
  String get swapProgressTab => '스왑 진행';

  @override
  String get swapTransactionDetailsTab => '거래 세부 정보';

  @override
  String get swapStatusRowLabel => '상태';

  @override
  String swapRefundsReturnedAs(String symbol, String chain) {
    return '스왑이 실패하거나 환율이 변동되면 수수료를 제외한 금액이 $chain의 $symbol(으)로 환불됩니다.';
  }

  @override
  String get swapReviewSwap => '스왑 검토';

  @override
  String get swapQuoteExpiredNotice => '견적이 만료되었습니다. 최신 환율로 다시 검토하세요.';

  @override
  String get swapYourePaying => '보내는 금액';

  @override
  String get swapYoureReceiving => '받는 금액';

  @override
  String get swapYouPaid => '보낸 금액';

  @override
  String get swapYouReceived => '받은 금액';

  @override
  String get swapVerbLockingQuote => '견적 고정 중';

  @override
  String get swapReviewAgain => '다시 검토';

  @override
  String get swapNotEnoughZec => 'ZEC 부족';

  @override
  String get swapConfirmSwap => '스왑 확인';

  @override
  String swapToShort(String address) {
    return '받는 주소: $address';
  }

  @override
  String swapRecipientAddressTitle(String symbol) {
    return '$symbol 수신 주소';
  }

  @override
  String swapRefundAddressTitle(String symbol) {
    return '$symbol 환불 주소';
  }

  @override
  String get swapRecipientFieldLabel => '수신자';

  @override
  String get swapRefundToFieldLabel => '환불 주소';

  @override
  String swapDeliveredToAddress(String symbol) {
    return '$symbol이(가) 이 주소로 전달됩니다.';
  }

  @override
  String get swapRememberRecipients => '이 주소를 수신자 목록에 저장';

  @override
  String get swapRememberRefunds => '이 주소를 환불 목록에 저장';

  @override
  String get swapUpdateAction => '업데이트';

  @override
  String get swapIveDepositedTokens => '토큰을 입금했습니다';

  @override
  String get swapIveDeposited => '입금 완료';

  @override
  String get swapDepositZec => 'ZEC 입금';

  @override
  String get swapDepositTokensTitle => '토큰 입금';

  @override
  String get swapChecking => '확인 중';

  @override
  String get swapTimesUp => '시간 종료';

  @override
  String get swapDepositExpiredBody =>
      '이 입금 주소는 더 이상 유효하지 않습니다.\n새 스왑 거래를 시작하세요.';

  @override
  String get swapRestartSwap => '스왑 다시 시작';

  @override
  String get swapDepositWithin => '입금 기한';

  @override
  String get swapAmountToDeposit => '입금할 금액';

  @override
  String get swapAmountLabel => '금액';

  @override
  String get swapAmountCopiedMobile => '금액이 복사되었습니다';

  @override
  String get swapAmountCopiedDesktop => '금액이 복사되었습니다';

  @override
  String get swapOneTimeAddress => '일회용 주소';

  @override
  String get swapMemoCopied => '메모가 복사되었습니다';

  @override
  String get swapSigningCancelledBeforeParams =>
      '증명 파라미터를 다운로드하기 전에 서명이 취소되었습니다.';

  @override
  String get swapTxStatusUncertain =>
      '트랜잭션 상태가 불확실합니다. 다시 시도하기 전에 활동을 새로고침하세요.';

  @override
  String get swapZecDepositAction => 'ZEC 입금';

  @override
  String swapBroadcastingAction(String action) {
    return '$action 전송 중';
  }

  @override
  String swapSignActionOnKeystone(String action) {
    return 'Keystone에서 $action 서명';
  }

  @override
  String get swapSubmittingTransaction => '트랜잭션 제출 중';

  @override
  String get swapScanToSign => '스캔하여 서명';

  @override
  String get swapAfterScannedClickGetSignature => '스캔한 후 서명 가져오기를 클릭하세요.';

  @override
  String get swapGetSignature => '서명 가져오기';

  @override
  String get swapBackToActivity => '활동으로 돌아가기';

  @override
  String get swapTxCouldNotBroadcast => '트랜잭션을 전송하지 못했습니다.';

  @override
  String get swapZecDepositSigningFailed => 'ZEC 입금 서명을 완료하지 못했습니다.';

  @override
  String get swapYouPay => '보내는 자산';

  @override
  String get swapYouReceive => '받는 자산';

  @override
  String get swapZcashLabel => 'Zcash';

  @override
  String get swapAddRefundAddress => '환불 주소 추가...';

  @override
  String get swapAddRecipientAddress => '수신 주소 추가...';

  @override
  String swapMaxAvailable(String amount) {
    return '최대: $amount';
  }

  @override
  String get swapZecDepositSent => 'ZEC 입금 보냄';

  @override
  String get swapCheckingZecDeposit => 'ZEC 입금 확인 중';

  @override
  String swapToTruncated(String address) {
    return '받는 주소: $address';
  }

  @override
  String get swapCouldntLoad => '이 스왑을 불러오지 못했습니다. 다시 시도하거나 당겨서 새로고침하세요.';

  @override
  String get swapReturnToActivity => '활동으로 돌아가 저장된 스왑을 선택하세요.';

  @override
  String get swapSignZecDeposit => 'ZEC 입금 서명';

  @override
  String get swapKeystoneSigningFailed => 'Keystone 서명 실패';

  @override
  String get swapScanTxQrInstructions =>
      'Keystone 지갑으로 이 트랜잭션 QR 코드를 스캔하세요. 기기의 안내를 따르세요.';

  @override
  String get swapBroadcastingZecDeposit => 'ZEC 입금 전송 중...';

  @override
  String get swapAlreadyInContacts => '이미 연락처에 있습니다';

  @override
  String get swapAlreadyInAddressBook => '이미 주소록에 있습니다';

  @override
  String get swapTitle => '스왑';

  @override
  String get swapGettingQuote => '견적 가져오는 중';

  @override
  String get swapAddRecipientAddressAction => '수신 주소 추가';

  @override
  String get swapAddRefundAddressAction => '환불 주소 추가';

  @override
  String get swapContinueToReview => '검토 계속하기';

  @override
  String get swapQrNoAddress => 'QR 코드에 주소가 없습니다.';

  @override
  String get swapSelectAsset => '자산 선택';

  @override
  String get swapSearchTokenOrChain => '토큰 또는 체인 검색';

  @override
  String get swapNoTokensFound => '토큰 또는 체인을 찾을 수 없습니다';

  @override
  String get swapSlippage => '슬리피지';

  @override
  String get swapSlippageRange => '슬리피지는 0.1 - 5% 사이여야 합니다';

  @override
  String get swapCustom => '직접 입력';

  @override
  String get swapTimeoutInvalidAddress => '이 입금 주소는 더 이상 유효하지 않습니다';

  @override
  String get swapTimeoutStartAnother => '새 스왑 거래를 시작하세요.';

  @override
  String get swapToPrefix => '받는 주소';

  @override
  String get swapFromPrefix => '보낸 주소';

  @override
  String get swapConfirmAndSwap => '확인 후 스왑';

  @override
  String get swapPoweredBy => 'Powered by';

  @override
  String get swapErrAmountTooLow => '이 스왑에는 금액이 너무 적습니다.\n더 큰 금액으로 시도하세요.';

  @override
  String get swapErrAmountPrecision =>
      '금액의 소수 자릿수가 너무 많습니다.\n소수 자릿수를 줄이고 다시 시도하세요.';

  @override
  String get swapErrInvalidRoute =>
      '이 경로 또는 주소가 거부되었습니다.\n세부 정보를 수정하고 새 견적을 요청하세요.';

  @override
  String get swapErrNoQuote =>
      '이 경로 또는 금액에 대한 견적이 없습니다.\n금액, 슬리피지 또는 자산을 조정하고 다시 시도하세요.';

  @override
  String get swapErrZecDepositFunding =>
      '이 스왑과 네트워크 수수료를 충당할 ZEC가 부족합니다.\n더 작은 금액을 시도하거나 최대를 사용하세요.';

  @override
  String get swapErrWalletPreflight =>
      'ZEC 입금을 준비하지 못했습니다.\n잔액을 확인하고 다시 시도하세요.';

  @override
  String get swapErrDepositNotFound => '입금이 아직 인덱싱되지 않았습니다.\n몇 분 후에 다시 확인하세요.';

  @override
  String get swapErrDepositRejected =>
      '입금 트랜잭션이 거부되었습니다.\n주소, 메모, tx 해시를 확인하세요.';

  @override
  String get swapErrUnsupportedPairNoResend =>
      '스왑 상태가 지원되지 않는 자산 쌍을 사용합니다.\n자금을 다시 보내지 마세요. 나중에 다시 시도하세요.';

  @override
  String get swapErrAssetUnavailable =>
      '이 자산은 지금 스왑할 수 없습니다.\n다른 자산을 선택하거나 나중에 다시 시도하세요.';

  @override
  String get swapErrServiceUnavailableNoResend =>
      '스왑 서비스를 일시적으로 사용할 수 없습니다.\n자금을 다시 보내지 마세요. 나중에 다시 시도하세요.';

  @override
  String get swapErrServiceUnavailable =>
      '스왑 서비스를 일시적으로 사용할 수 없습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrQuoteTimeout => '견적 요청 시간이 초과되었습니다.\n연결을 확인하고 다시 시도하세요.';

  @override
  String get swapErrTimeoutNoResend =>
      '요청 시간이 초과되었습니다.\n자금을 다시 보내지 마세요. 나중에 다시 시도하세요.';

  @override
  String get swapErrTimeout => '요청 시간이 초과되었습니다.\n연결을 확인하고 다시 시도하세요.';

  @override
  String get swapErrProcessingNoResend =>
      '스왑 서비스가 아직 처리 중입니다.\n자금을 다시 보내지 마세요. 나중에 다시 시도하세요.';

  @override
  String get swapErrProcessing => '스왑 서비스가 아직 처리 중입니다.\n잠시 후 다시 시도하세요.';

  @override
  String get swapErrQuoteUnverified => '견적 응답을 확인할 수 없습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrResponseUnverified => '스왑 응답을 확인할 수 없습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrTokenList => '스왑 토큰을 불러오지 못했습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrQuoteUnavailable => '지금은 견적을 사용할 수 없습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrStartFailed => '스왑을 시작하지 못했습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrRefreshFailed => '스왑 상태를 새로고침하지 못했습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrSubmitDepositFailed => '입금 상태를 제출하지 못했습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrSendZecDepositFailed => 'ZEC 입금을 보내지 못했습니다.\n나중에 다시 시도하세요.';

  @override
  String get swapErrNoActiveAccount => '활성 계정이 없습니다';

  @override
  String get swapErrInsufficientShieldedForFee => '수수료를 충당할 쉴드 잔액이 부족합니다';

  @override
  String get swapErrMaxUnavailable => '최대 금액을 사용할 수 없습니다';

  @override
  String get swapBadgeCompleted => '완료됨';

  @override
  String get swapBadgeNeedsAttention => '확인 필요';

  @override
  String get swapBadgeInProgress => '진행 중';

  @override
  String get swapZcashAddress => 'Zcash 주소';

  @override
  String swapChainAddress(String chain) {
    return '$chain 주소';
  }

  @override
  String get swapFullAddress => '전체 주소';

  @override
  String votingNotEligibleNoFunds(String snapshot) {
    return '이 계정은 이번 투표 라운드에 참여할 수 없습니다. $snapshot 시점에 적격 쉴드 자금이 없었습니다. 적격 계정으로 전환하여 투표하세요.';
  }

  @override
  String votingRequiresMinimumBundle(String snapshot) {
    return '투표하려면 $snapshot 시점에 0.125 ZEC 이상이 담긴 적격 쉴드 노트 번들이 하나 이상 필요합니다. 적격 계정으로 전환하여 투표하세요.';
  }

  @override
  String get votingSnapshotBlockFallback => '투표 라운드 스냅샷 블록';

  @override
  String votingSnapshotBlock(String height) {
    return '스냅샷 블록 $height';
  }

  @override
  String get votingSessionActionFailed => '투표 세션 작업이 실패했습니다.';

  @override
  String get votingTryAgain => '다시 시도';

  @override
  String get votingNoRounds => '진행 중인 투표 라운드가 없습니다';

  @override
  String get votingNoRoundsBody => '아직 표시할 토큰 홀더 투표 라운드가 없습니다.';

  @override
  String get votingVoteTitle => '투표';

  @override
  String get votingConfigTooltip => '투표 설정';

  @override
  String get votingConfigSemantics => '투표 구성 설정';

  @override
  String get votingBeta => '베타';

  @override
  String get votingCloses => '마감';

  @override
  String get votingClosed => '마감됨';

  @override
  String votingClosesOn(String label, String date) {
    return '$label $date';
  }

  @override
  String votingStartsOn(String date) {
    return '$date 시작';
  }

  @override
  String get votingStateInProgress => '진행 중';

  @override
  String get votingStateActive => '활성';

  @override
  String get votingStateVoted => '투표 완료';

  @override
  String get votingStateTallying => '집계 중';

  @override
  String get votingResume => '이어하기';

  @override
  String get votingStartVoting => '투표 시작';

  @override
  String get votingReview => '검토';

  @override
  String get votingViewResults => '결과 보기';

  @override
  String get votingRoundUnavailable => '투표 라운드를 사용할 수 없습니다';

  @override
  String get votingRoundLoadFailed => '선택한 투표 라운드를 불러오지 못했습니다.';

  @override
  String get votingTokenHolderVoting => '토큰 홀더 투표';

  @override
  String get votingPowerUnavailable => '투표 권한을 확인할 수 없습니다.';

  @override
  String get votingPreparingPower => '투표 권한 준비 중.';

  @override
  String get votingNoProposals => '제안 없음';

  @override
  String get votingNoProposalsBody => '이 투표 라운드에는 제안이 없습니다.';

  @override
  String get votingRetryEligibility => '자격 다시 확인';

  @override
  String get votingNotEligible => '자격 없음';

  @override
  String get votingReviewAnswers => '답변 검토';

  @override
  String get votingSkipUnanswered => '답하지 않은 질문을 건너뛸까요?';

  @override
  String votingSkipUnansweredBody(int skipped, int total) {
    return '$total개 질문 중 $skipped개에 답하지 않았습니다. 검토 화면에 건너뜀으로 표시되며, 건너뛴 질문은 제출되지 않습니다.';
  }

  @override
  String get votingContinueToReview => '검토 계속하기';

  @override
  String get votingKeepVoting => '계속 투표하기';

  @override
  String get votingNotEligibleRound => '이 투표 라운드에 참여할 수 없습니다';

  @override
  String get votingActive => '투표 진행 중';

  @override
  String votingEndsOn(String date) {
    return '$date 종료';
  }

  @override
  String get votingSkipped => '건너뜀';

  @override
  String get votingVoteInProgress => '진행 중인 투표';

  @override
  String get votingUnfinishedVote => '이 라운드에 완료하지 않은 투표가 있습니다. 이어서 제출을 완료하세요.';

  @override
  String get votingContinueVoting => '투표 계속하기';

  @override
  String get votingForumDiscussion => '포럼 토론';

  @override
  String votingChoiceLabel(String choice) {
    return '선택 $choice';
  }

  @override
  String get votingSelected => '선택됨';

  @override
  String get votingChoose => '선택';

  @override
  String get votingViewLess => '접기';

  @override
  String get votingViewMore => '더 보기';

  @override
  String get votingReviewYourAnswers => '답변을 검토하세요';

  @override
  String get votingChooseAtLeastOne => '제출하기 전에 하나 이상의 옵션을 선택하세요.';

  @override
  String get votingConfirmSubmit => '확인 후 제출';

  @override
  String get votingResults => '결과';

  @override
  String get votingNoProposalsInRound => '이 라운드에는 제안이 없습니다.';

  @override
  String get votingResultsPending => '결과 집계 중...';

  @override
  String votingVotedLabel(String label) {
    return '투표함: $label';
  }

  @override
  String votingTotalLabel(String amount) {
    return '합계: $amount';
  }

  @override
  String get votingResultsTitle => '투표 결과';

  @override
  String get votingSubmissionNotComplete => '제출이 완료되지 않았습니다';

  @override
  String get votingNotAvailable => '사용할 수 없음';

  @override
  String get votingNotSubmittedBody => '이 계정은 이 투표 라운드의 제출을 완료하지 않았습니다.';

  @override
  String get votingCheckingEligibility => '이 계정의 투표 자격을 확인하는 중입니다.';

  @override
  String get votingEligibilityNotConfirmed => '이 계정의 투표 자격이 확인되지 않았습니다.';

  @override
  String get votingSubmissionConfirmed => '제출이 확인되었습니다!';

  @override
  String get votingSubmissionPublished => '투표가 성공적으로 게시되었으며 변경할 수 없습니다.';

  @override
  String get votingRoundLabel => '투표 라운드';

  @override
  String get votingPowerLabel => '투표 권한';

  @override
  String get votingUpdatingRounds => '투표 라운드 업데이트 중...';

  @override
  String get votingGenericStatusError =>
      '이 계정으로 투표를 계속할 수 없습니다. 다시 시도하거나, 이 계정이 이번 라운드에 투표할 수 없다면 적격 계정으로 전환하세요.';

  @override
  String votingPirNotReady(String expected, String highest) {
    return '이 투표 라운드의 PIR 데이터가 아직 준비되지 않았습니다. 예상 스냅샷 블록 $expected, PIR 엔드포인트 보고 $highest.';
  }

  @override
  String votingPirNoEndpoint(String expected) {
    return '이 투표 라운드 스냅샷과 일치하는 PIR 엔드포인트가 없습니다. 예상 스냅샷 블록 $expected.';
  }

  @override
  String votingQuestionProgress(int current, int total) {
    return '질문 $current/$total';
  }

  @override
  String get votingUseSignedBundlesOnly => '서명된 번들만 사용할까요?';

  @override
  String get votingSignedBundlesBody =>
      'Vizor는 이미 Keystone에서 스캔한 서명만으로 지금 제출할 수 있습니다.';

  @override
  String get votingSignedBundlesWarning =>
      '서명되지 않은 번들은 건너뛰며, 이 라운드의 투표 권한이 줄어듭니다.';

  @override
  String get votingKeepSigning => '계속 서명하기';

  @override
  String get votingSkipBundles => '번들 건너뛰기';

  @override
  String get votingSubmittingVotes => '투표 제출 중';

  @override
  String get votingSigningWithKeystone => 'Keystone으로 서명 중';

  @override
  String get votingDelegatingAuthority => '투표 권한 위임 중';

  @override
  String get votingCastingVotes => '투표 및 지분 제출 중';

  @override
  String get votingFinalizingSubmission => '제출 마무리 중';

  @override
  String get votingFailed => '투표에 실패했습니다.';

  @override
  String get votingClear => '지우기';

  @override
  String votingSyncedToBlock(String height) {
    return '블록 $height까지 동기화됨';
  }

  @override
  String votingSnapshotBlockPart(String height) {
    return '스냅샷 블록 $height';
  }

  @override
  String votingChainTipPart(String height) {
    return '체인 팁 $height';
  }

  @override
  String get votingWaitingForSync => '지갑 동기화 대기 중';

  @override
  String get votingWaitingForSyncBody =>
      '지갑이 이 투표 라운드 스냅샷을 따라잡는 중입니다. 스냅샷 블록까지 동기화되면 투표가 자동으로 계속됩니다.';

  @override
  String votingBlocksRemaining(String count) {
    return '$count개 블록 남음';
  }

  @override
  String votingSignBundle(int current, int total) {
    return '번들 서명 $current/$total';
  }

  @override
  String get votingSkip => '건너뛰기';

  @override
  String get votingScanQrInstruction =>
      '이 화면의 QR을 Keystone으로 스캔하세요. 그런 다음 Keystone에 표시된 서명된 투표 QR을 이 기기의 카메라로 스캔하세요';

  @override
  String votingNowSigningBundle(int current, int total) {
    return '번들 서명 중 $current/$total';
  }

  @override
  String get votingScanSignature => '서명 스캔';

  @override
  String get votingSoftwareAccountRequired => '소프트웨어 계정 필요';

  @override
  String get votingSoftwareAccountBody =>
      '토큰 홀더 투표에는 소프트웨어 계정이 필요합니다. 소프트웨어 계정으로 전환하여 이 라운드에 투표하세요.';

  @override
  String get votingSignatureQrDecodeError =>
      '이 QR 코드를 Keystone 투표 서명으로 해석할 수 없습니다.';

  @override
  String get votingOpenSignedQr => 'Keystone에서 서명된 투표 QR을 연 후 다시 스캔하세요.';

  @override
  String get votingScanVotingSignature => '투표 서명 스캔';

  @override
  String get votingHoldKeystoneQr => 'Keystone QR 코드를 카메라 앞에 안정적으로 유지하세요';

  @override
  String get votingCameraOnly =>
      'Keystone 투표는 카메라 QR 스캔만 지원합니다. 카메라를 연결하고 다시 시도하세요.';

  @override
  String votingTitleTooLong(int max) {
    return '제목은 $max자 이하여야 합니다.';
  }

  @override
  String get votingSourceAlreadyAdded => '이 소스 URL은 이미 추가되었습니다.';

  @override
  String get votingCustomSource => '사용자 지정 소스';

  @override
  String get votingSaving => '저장 중...';

  @override
  String get votingAddCustomSource => '사용자 지정 소스 추가';

  @override
  String get votingCopySourceUrl => '소스 URL 복사';

  @override
  String get votingSourceUrlCopied => '소스 URL이 복사되었습니다.';

  @override
  String get votingEditSavedSource => '저장된 소스 편집';

  @override
  String get votingDeleteSavedSource => '저장된 소스 삭제';

  @override
  String get votingEditCustomSource => '사용자 지정 소스 편집';

  @override
  String get votingTitleField => '제목';

  @override
  String get votingStaticConfigUrl => '정적 구성 URL';

  @override
  String get votingValidating => '확인 중...';

  @override
  String get votingDefault => '기본';

  @override
  String get votingCloseConfigSettings => '투표 구성 설정 닫기';

  @override
  String get settingsAccountChangedReenterPassword =>
      '활성 계정이 변경되었습니다. 비밀번호를 다시 입력하세요.';

  @override
  String get settingsNoActiveAccount => '선택된 활성 계정이 없습니다.';

  @override
  String get settingsSeedNotAvailableHardware =>
      '하드웨어 계정에서는 비밀 복구 구문을 볼 수 없습니다.';

  @override
  String get settingsSeedNotAvailable => '이 계정에서는 비밀 복구 구문을 볼 수 없습니다.';

  @override
  String get settingsSeedConfirmSubtitle => '비밀 복구 구문을 확인하려면 입력하세요.';

  @override
  String get settingsSeedMasterKeyBody => '지갑의 마스터 키입니다.\n누구와도 공유하지 마세요.';

  @override
  String get settingsBirthdayDate => '생성 날짜';

  @override
  String get settingsBirthdayBlockHeight => '생성 블록 높이';

  @override
  String get settingsSeedBiometricReason => '비밀 복구 구문 접근 확인';

  @override
  String get settingsIncorrectPasscode => '잘못된 패스코드입니다';

  @override
  String get settingsEnterPasscode => '패스코드 입력';

  @override
  String get settingsConfirmYourAccess => '접근 확인';

  @override
  String get settingsSeedCopiedToast => '비밀 복구 구문이 복사되었습니다';

  @override
  String get settingsBirthdayDateCopied => '생성 날짜가 복사되었습니다';

  @override
  String get settingsBirthdayHeightCopied => '생성 높이가 복사되었습니다';

  @override
  String settingsCopyLabel(String label) {
    return '$label 복사';
  }

  @override
  String get settingsNoScreenshotsTitle => '비밀 복구 구문을 스크린샷으로 찍지 마세요';

  @override
  String get settingsScreenshotsNotReliable => '스크린샷은 안전하지 않습니다';

  @override
  String get settingsNoScreenshotsBody =>
      '. 휴대폰이나 사진 라이브러리에 접근할 수 있는 사람은 누구나 비밀 복구 구문을 볼 수 있습니다. 대신 종이에 구문을 적어 두세요.';

  @override
  String get settingsIUnderstand => '이해했습니다';

  @override
  String get settingsNewPasscodeMustDiffer => '새 패스코드는 이전과 달라야 합니다.';

  @override
  String get settingsPasscodeRotationRecoveryFailed =>
      '이전 패스코드 변경을 확인하지 못했습니다. 다시 시도하기 전에 비밀 복구 구문을 준비해 두세요.';

  @override
  String get settingsSetNewPasscode => '새 패스코드 설정';

  @override
  String get settingsEnterCurrentPasswordAgain => '현재 비밀번호를 다시 입력하세요.';

  @override
  String get settingsKeepPassphraseAvailable =>
      '이전 비밀번호 변경을 확인하지 못했습니다. 다시 시도하기 전에 비밀 복구 구문을 준비해 두세요.';

  @override
  String get settingsEnterCurrentPasswordFirst => '먼저 현재 비밀번호를 입력하세요.';

  @override
  String get settingsUpdatePassword => '비밀번호 변경';

  @override
  String get settingsPasswordHintLong =>
      '최소 8자입니다. 더 강력한 보안을 위해 숫자와 기호를 추가하거나 더 길게 만드세요.';

  @override
  String get settingsConfirmPassword => '비밀번호 확인';

  @override
  String get settingsUpdatingPassword => '비밀번호 변경 중...';

  @override
  String get settingsAccountSection => '계정';

  @override
  String get settingsSecretPassphraseTitle => '비밀 복구 구문';

  @override
  String get settingsProfilePictureTitle => '프로필 사진';

  @override
  String get settingsAccountNameTitle => '계정 이름';

  @override
  String get settingsSystemSection => '시스템';

  @override
  String get settingsOn => '켜짐';

  @override
  String get settingsOff => '꺼짐';

  @override
  String get settingsPasscodeUpdated => '패스코드가 변경되었습니다';

  @override
  String get settingsTurnOff => '끄기';

  @override
  String settingsUninstallBody(String device) {
    return 'Vizor가 $device에서 지갑 데이터와 보안 저장소를 삭제합니다.';
  }

  @override
  String get settingsThisMac => '이 Mac';

  @override
  String get settingsThisPc => '이 PC';

  @override
  String get settingsThisDevice => '이 기기';

  @override
  String get settingsUninstallFinishMac =>
      '제거를 완료하려면 응용 프로그램에서 Vizor 앱을 삭제하세요.';

  @override
  String get settingsUninstallFinishWindows =>
      '제거를 완료하려면 Windows 설정에서 Vizor를 제거하세요.';

  @override
  String get settingsUninstallFinishOther => '제거를 완료하려면 이 기기에서 Vizor 앱을 삭제하세요.';

  @override
  String settingsActiveSwapsBlockUninstall(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이 지갑에 진행 중인 스왑이 $count개 있습니다. 완료될 때까지 기다린 후 제거하세요.',
    );
    return '$_temp0';
  }

  @override
  String get settingsCannotBeUndone => '되돌릴 수 없습니다.';

  @override
  String get settingsCheckingSwaps => '스왑 확인 중...';

  @override
  String get settingsToUninstall => 'Vizor를 제거하려면 입력하세요.';

  @override
  String get settingsDataRemoved => '데이터가 삭제되었습니다';

  @override
  String get settingsRemovingData => '데이터 삭제 중...';

  @override
  String get settingsCloseVizor => 'Vizor 닫기';

  @override
  String get settingsConfirmAccess => '접근 확인';

  @override
  String get settingsYourPasswordHint => '비밀번호 입력...';

  @override
  String get endpointUpdating => '업데이트 중...';

  @override
  String get endpointCloseSettings => '엔드포인트 설정 닫기';

  @override
  String get endpointDefaultSuffix => '(기본)';

  @override
  String get endpointCurrentPrefix => '현재: ';

  @override
  String get endpointCustomEndpointTitle => '사용자 지정 엔드포인트';

  @override
  String get endpointHostPortHint => '<hostname>:<port>';

  @override
  String get endpointSelectAnEndpoint => '엔드포인트를 선택하세요.';

  @override
  String get endpointUpdated => '엔드포인트가 변경되었습니다';

  @override
  String get endpointsTitle => '엔드포인트';

  @override
  String get endpointSelectFromList => '목록에서 선택';

  @override
  String get endpointCustomEndpoint => '사용자 지정 엔드포인트';

  @override
  String get endpointUpdateEndpoint => '엔드포인트 변경';

  @override
  String get endpointCustomiseEndpoint => '엔드포인트 직접 설정';

  @override
  String get endpointCustomizeEndpoint => '엔드포인트 직접 설정';

  @override
  String get endpointMisconfiguredNetwork =>
      '엔드포인트가 잘못 설정되면 지갑이 Zcash 네트워크와 동기화할 수 없습니다.';

  @override
  String get endpointMisconfiguredBlockchain =>
      '엔드포인트가 잘못 설정되면 지갑이 Zcash 블록체인과 동기화할 수 없습니다.';

  @override
  String get endpointMisconfiguredNetworkNewline =>
      '엔드포인트가 잘못 설정되면 지갑이 Zcash 네트워크와 동기화할 수 없습니다.\n';

  @override
  String endpointStaleBalanceWarning(String ticker) {
    return '지갑은 마지막으로 성공적으로 연결된 시점의 잔액을 표시합니다. 최근에 받은 $ticker는 표시되지 않습니다.';
  }

  @override
  String get abCopyAddress => '주소 복사';

  @override
  String get abSendZec => 'ZEC 보내기';

  @override
  String abContactActions(String name) {
    return '$name 작업';
  }

  @override
  String get cameraDeniedShortTitle => '카메라 접근이 거부되었습니다';

  @override
  String get homeImportingWallet => '지갑을\n가져오는 중...';

  @override
  String get homeImportingWalletMobile => '지갑을 가져오는 중...';

  @override
  String get profilePictureUpdateFailed => '프로필 사진을 변경하지 못했습니다.';

  @override
  String get settingsRemoveDataFailed => '데이터 삭제를 완료하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsSwapCheckFailed =>
      '진행 중인 스왑을 확인하지 못했습니다. 제거하기 전에 다시 시도하세요.';

  @override
  String get settingsPasswordCheckFailed => '비밀번호를 확인하지 못했습니다. 다시 시도하세요.';

  @override
  String get endpointConnectFailed => '해당 엔드포인트에 연결하지 못했습니다. 호스트와 포트를 확인하세요.';

  @override
  String get settingsPasswordUpdateFailed => '비밀번호를 변경하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsPasscodesDidntMatch => '패스코드가 일치하지 않습니다. 다시 시도하세요.';

  @override
  String get settingsPasscodeCheckFailed => '패스코드를 확인하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsPasscodeUpdateFailed => '패스코드를 변경하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsAppResetFailed => '앱을 초기화하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsAccountSaveFailed => '계정 변경 사항을 저장하지 못했습니다';

  @override
  String get settingsSeedLoadFailed => '비밀 복구 구문을 불러오지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsPasscodeVerifyFailed => '패스코드를 확인하지 못했습니다. 다시 시도하세요.';

  @override
  String get votingRoundsLoadFailed => '투표 라운드를 불러오지 못했습니다';

  @override
  String get votingRoundLoadFailedTitle => '투표 라운드를 불러오지 못했습니다';

  @override
  String get votingConfigLoadFailed => '해당 소스에서 투표 구성을 불러오지 못했습니다.';

  @override
  String get votingConfigUpdateFailed => '투표 구성을 변경하지 못했습니다.';

  @override
  String votingRoundDetailsLoadFailed(String error) {
    return '투표 라운드 세부 정보를 불러오지 못했습니다: $error';
  }

  @override
  String get votingDontCloseWindow =>
      '창을 닫지 마세요. 영지식 증명 생성에는 시간이 걸릴 수 있으며, 지금 닫으면 진행 중인 증명 작업이 사라질 수 있습니다.';

  @override
  String get votingPirUnreachable =>
      '구성된 PIR 엔드포인트에 연결하지 못했습니다. 네트워크와 투표 구성을 확인한 후 다시 시도하세요.';

  @override
  String get swapNotEnoughZecBody => '이 스왑에 필요한 ZEC가 부족합니다. 더 작은 금액으로 시도하세요.';

  @override
  String get receiveTransparentShieldGuideBody =>
      '투명 주소로 ZEC를 받으면 Vizor가 잔액 쉴드를 안내합니다. 쉴드하지 않으면 보낼 수 없습니다.';

  @override
  String get accountsAddressCopyFailed => '주소를 복사하지 못했습니다';

  @override
  String get accountsAddressLoadFailed => '계정 주소를 불러오지 못했습니다';

  @override
  String get accountsResetVizorFailed => 'Vizor를 초기화하지 못했습니다';

  @override
  String get accountsRemoveFailedShort => '계정을 제거하지 못했습니다';

  @override
  String get receiveAddressLoadFailedLong => '주소를 불러오지 못했습니다. 잠시 후 다시 시도하세요.';

  @override
  String get receiveAddressLoadFailedShort => '주소를 불러오지 못했습니다. 다시 시도하세요.';

  @override
  String get accountsResetVizorFailedDot => 'Vizor를 초기화하지 못했습니다.';

  @override
  String get accountsRemoveFailedDot => '계정을 제거하지 못했습니다.';

  @override
  String get sendBroadcastRejectedRetrying =>
      '트랜잭션이 로컬에서 생성되었지만 네트워크에 도달하지 못했습니다. 만료될 때까지 지갑이 계속 재시도합니다. 이 트랜잭션이 만료되기 전에는 다시 보내지 마세요.';

  @override
  String get sendQrNotZcash => '이 QR 코드는 Zcash 주소가 아닙니다.';

  @override
  String get onbInvalidBlockHeight => '유효한 블록 높이가 아닌 것 같습니다.';

  @override
  String get onbNotLegitBlockHeight => '올바른 블록 높이가 아닌 것 같습니다';

  @override
  String get onbUnlockFailed => '지갑을 열지 못했습니다. 다시 시도하세요.';

  @override
  String get onbFewStepsAwayDesktop => '첫 프라이빗 지갑까지 몇 단계만 남았습니다.\n시작해 볼까요?';

  @override
  String get receivePreviewShieldedPrivacy =>
      '거래 세부 정보(보낸 사람, 받는 사람, 금액)는 온체인에서 암호화되어 숨겨집니다.';

  @override
  String get receivePreviewShieldedRenew =>
      '받기 페이지를 열거나 갱신 버튼을\n누를 때마다 새로운 Zcash 쉴드\n주소가 생성됩니다.';

  @override
  String get receivePreviewShieldedDiversified =>
      '새 주소는 모두 같은 키에서 파생된\n다변화 주소입니다.\n모두 같은 지갑으로 입금됩니다.';

  @override
  String passwordTooShort(int min) {
    return '비밀번호는 최소 $min자 이상이어야 합니다.';
  }

  @override
  String get passwordAsciiOnly =>
      'Use only English letters, numbers, and symbols.';

  @override
  String get passwordMustDiffer => '다른 비밀번호를 사용하세요.';

  @override
  String get votingChooseAtLeastOneVote => '제출하기 전에 하나 이상 투표하세요.';

  @override
  String get votingVoteLocked => '투표 확정됨';

  @override
  String votingVotedOn(String date) {
    return '$date 투표함';
  }

  @override
  String get votingPowerUnavailableShort => '투표 권한 확인 불가';

  @override
  String get votingPreparingPowerShort => '투표 권한 준비 중';

  @override
  String votingPowerMeta(String power) {
    return '투표 권한 $power';
  }

  @override
  String get keystonePreparingQr => 'QR 준비 중';

  @override
  String get keystoneImReadyNow => '준비됐어요';

  @override
  String swapChainAddressOrAccount(String chain) {
    return '$chain 주소 또는 계정';
  }

  @override
  String get swapNetworkErrorRetry =>
      '전송 중 네트워크 오류가 발생했습니다. 연결을 확인하고 다시 시도하세요. 서명은 다시 사용해도 안전합니다.';

  @override
  String get activitySwapped => '스왑 완료';

  @override
  String get activitySwapFailed => '스왑 실패';

  @override
  String get activitySwapping => '스왑 중...';

  @override
  String activitySymbolRefunded(String symbol) {
    return '$symbol 환불됨';
  }

  @override
  String activityReceivedSymbol(String symbol) {
    return '$symbol 받음';
  }

  @override
  String activityDepositedSymbol(String symbol) {
    return '$symbol 입금됨';
  }

  @override
  String get legalTermsOfUse => '이용 약관';

  @override
  String updateTitleAvailableVersion(String version) {
    return '업데이트 $version 사용 가능';
  }

  @override
  String get updateTitleDownloading => '업데이트 다운로드 중';

  @override
  String get updateTitleReady => '업데이트 준비 완료';

  @override
  String get updateTitleApplying => 'Vizor 다시 시작 중';

  @override
  String get updateTitleAvailable => '업데이트 사용 가능';

  @override
  String get updateBodyAvailable => '지금 다운로드하거나 계속 사용하세요.';

  @override
  String updateBodyDownloading(int progress) {
    return '$progress% 다운로드됨.';
  }

  @override
  String get updateBodyReady => '준비되면 다시 시작하세요.';

  @override
  String get updateBodyApplying => 'Vizor 종료 후 적용됩니다.';

  @override
  String get updateActionDownload => '다운로드';

  @override
  String get updateActionRestart => '다시 시작';

  @override
  String get updateActionDownloading => '다운로드 중';

  @override
  String get updateActionRestarting => '다시 시작 중';

  @override
  String get updateActionUpdate => '업데이트';

  @override
  String get updateActionLater => '나중에';

  @override
  String updateLinuxAvailable(String version) {
    return 'Vizor $version 버전이 제공됩니다.';
  }

  @override
  String get updateViewRelease => '릴리스 보기';

  @override
  String get endpointFailoverSwitched => '선택한 엔드포인트가 불안정합니다. 대체 엔드포인트로 전환했습니다.';

  @override
  String get endpointFailoverRecovered => '선택한 엔드포인트가 복구되어 다시 전환했습니다.';

  @override
  String get activityIncompleteDeposit => '미완료 입금';

  @override
  String get activityTimeout => '시간 초과';

  @override
  String get activityLoadErrorRetry => '활동을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';

  @override
  String get keystoneShieldSignTitle => 'Keystone에서 트랜잭션 서명';

  @override
  String get keystoneShieldScanToSign => '서명하려면 QR 코드를 스캔하세요';

  @override
  String get keystoneShieldSubmitting => '트랜잭션 제출 중';

  @override
  String get keystoneShieldReject => '거부';

  @override
  String get keystoneShieldBackToWallet => '지갑으로 돌아가기';

  @override
  String get shieldErrorSyncFirst => '투명 잔액을 보호하기 전에 지갑을 동기화하세요.';

  @override
  String get shieldErrorBroadcastFailed => '보호 트랜잭션을 브로드캐스트하지 못했습니다.';

  @override
  String get shieldErrorRetry => '잔액 보호에 실패했습니다. 다시 시도해 주세요.';

  @override
  String get shieldCancelledParamsDownload => '증명 매개변수 다운로드 전에 보호가 취소되었습니다.';

  @override
  String get scanCameraPermissionOff =>
      '카메라 접근이 꺼져 있습니다. 주소를 스캔하려면 설정에서 허용하세요.';

  @override
  String swapQuoteChangedLower(String percent) {
    return '실시간 견적이 이전 예상보다 $percent% 낮습니다. 계속하기 전에 보장 최소 수량을 확인하세요.';
  }

  @override
  String swapQuoteChangedHigher(String percent) {
    return '실시간 견적이 이전 예상보다 $percent% 높습니다. 계속하기 전에 보장 최소 수량을 확인하세요.';
  }

  @override
  String swapPickerRecipientsTitle(String symbol) {
    return '$symbol 수신인';
  }

  @override
  String swapPickerRefundsTitle(String symbol) {
    return '$symbol 환불 주소';
  }

  @override
  String swapPickerNoSavedRecipients(String symbol) {
    return '저장된 $symbol 수신인이 없습니다';
  }

  @override
  String swapPickerNoSavedRefunds(String symbol) {
    return '저장된 $symbol 환불 주소가 없습니다';
  }

  @override
  String get swapErrAccountChanged => '활성 계정이 변경되었습니다. 시작하기 전에 견적을 다시 검토하세요.';

  @override
  String get swapErrIntentMissing =>
      'ZEC 입금이 브로드캐스트되었지만 저장된 스왑 내역을 찾을 수 없습니다. 이 화면을 나가기 전에 트랜잭션 해시를 복사해 두세요.';

  @override
  String get swapDepositPartialBroadcast =>
      '일부 입금 트랜잭션이 네트워크에 도달했을 수 있습니다. 다시 시도하기 전에 활동을 확인하세요.';

  @override
  String get swapDepositPendingBroadcast =>
      '입금이 로컬에서 생성되었지만 브로드캐스트하지 못했습니다. 다시 시도하기 전에 활동을 확인하세요.';

  @override
  String get swapDepositBroadcastUnknown =>
      '트랜잭션이 네트워크에 도달했을 수 있으나 확인이 시간 초과되었습니다. 다시 시도하기 전에 활동을 확인하세요.';

  @override
  String get swapDepositStorageFailed =>
      '트랜잭션이 네트워크에 도달했지만 Vizor가 로컬에 저장하지 못했습니다. 동기화 또는 탐색기에서 최신 상태를 확인할 때까지 다시 시도하지 마세요.';

  @override
  String get swapDepositUncertain => '입금 상태가 불확실합니다. 다시 시도하기 전에 활동을 확인하세요.';

  @override
  String get endpointRegionDefault => '기본';

  @override
  String get endpointRegionAmericas => '아메리카';

  @override
  String get endpointRegionEurope => '유럽';

  @override
  String get endpointRegionAsiaPacific => '아시아 태평양';

  @override
  String get endpointRegionGlobal => '글로벌';

  @override
  String get endpointRegionCommunity => '커뮤니티';

  @override
  String get endpointRegionTestnet => '테스트넷';

  @override
  String get endpointRegionRegtest => 'Regtest';

  @override
  String get endpointErrEnter => '엔드포인트를 입력하세요.';

  @override
  String get endpointErrSpaces => '엔드포인트에는 공백을 포함할 수 없습니다.';

  @override
  String get endpointErrHostPort => '올바른 호스트 이름과 포트를 입력하세요.';

  @override
  String get endpointErrHttps => 'https:// 엔드포인트를 사용하세요.';

  @override
  String get endpointErrPort => '올바른 포트를 포함하세요. 예: us.zec.stardust.rest:443';

  @override
  String get endpointLatencyChecking => '확인 중...';

  @override
  String get endpointLatencyUnavailable => '사용 불가';

  @override
  String get endpointLatencyWrongNetwork => '네트워크 불일치';

  @override
  String aboutVersionLabel(String version) {
    return '버전: $version 퍼블릭 베타';
  }

  @override
  String get privacySensitiveContentHidden => '민감한 콘텐츠 숨김';

  @override
  String get sendUnknownShieldedAddress => '알 수 없는 보호 주소';

  @override
  String get sendUnknownTransparentAddress => '알 수 없는 투명 주소';

  @override
  String get accountsSendStartFailed => '보내기를 시작하지 못했습니다';

  @override
  String get abClearContactLabel => '연락처 라벨 지우기';

  @override
  String get abSaveContactFailed => '연락처를 저장하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get abRemoveContactFailed => '연락처를 삭제하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get abLoadContactsFailed => '연락처를 불러오지 못했습니다. 다시 시도해 주세요.';

  @override
  String get sendTxCouldNotBeSent => '트랜잭션을 보내지 못했습니다.';

  @override
  String get deviceAuthConfirmReset => 'Vizor 재설정 확인';

  @override
  String get deviceAuthRequired => 'Vizor를 재설정하려면 기기 인증이 필요합니다.';

  @override
  String get deviceAuthFailed => '기기 소유권을 확인하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get abPickerNoContacts => '연락처가 없습니다';

  @override
  String get sendPartialBroadcast =>
      '일부 트랜잭션이 브로드캐스트되었고 나머지는 자동으로 재시도됩니다. 다시 보내기 전에 활동을 확인하세요.';

  @override
  String get sendPendingBroadcastRetry =>
      '트랜잭션이 로컬에서 생성되었지만 브로드캐스트하지 못했습니다. 네트워크가 연결되면 자동으로 재시도합니다. 이 트랜잭션이 만료되지 않는 한 다시 보내지 마세요.';

  @override
  String get sendBroadcastUnknown =>
      '트랜잭션이 네트워크에 도달했을 수 있으나 확인이 시간 초과되었습니다. 다시 보내기 전에 활동을 확인하세요.';

  @override
  String get sendBroadcastStorageFailed =>
      '트랜잭션이 네트워크에 도달했지만 Vizor가 로컬에 저장하지 못했습니다. 동기화 또는 탐색기에서 최신 상태를 확인할 때까지 다시 보내지 마세요.';

  @override
  String get sendPcztRejected => '네트워크가 트랜잭션을 거부했습니다. 나중에 다시 시도해 주세요.';

  @override
  String get sendCancelledParamsDownload => '증명 매개변수 다운로드 전에 보내기가 취소되었습니다.';

  @override
  String get votingAccountLoadError => '계정을 불러오지 못했습니다';

  @override
  String get votingResultsFallbackTitle => '투표 결과';

  @override
  String votingLoadResultsError(String message) {
    return '결과를 불러오지 못했습니다: $message';
  }

  @override
  String votingLoadRoundDetailsError(String message) {
    return '투표 라운드 정보를 불러오지 못했습니다: $message';
  }

  @override
  String votingLoadReviewError(String message) {
    return '검토 내용을 불러오지 못했습니다: $message';
  }

  @override
  String votingLoadSubmissionError(String message) {
    return '제출 정보를 불러오지 못했습니다: $message';
  }

  @override
  String get votingRoundsRefreshError => '투표 라운드를 갱신하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get votingRecoveryDelegationPending =>
      '이 투표에 로컬 진행 상황이 있지만 위임이 아직 완전히 확인되지 않았습니다. 다른 투표를 진행하기 전에 앱이 복구를 계속해야 합니다.';

  @override
  String get votingRecoveryCommitmentPending =>
      '이 투표가 시작되었지만 커밋 트랜잭션 복구 데이터가 아직 완전하지 않습니다. 이 계정에서 다시 투표하지 마세요.';

  @override
  String get votingRecoverySharesPending =>
      '이 투표는 제출되었지만 일부 도우미 서버 지분이 아직 확인을 기다리고 있습니다. 이 계정에서 다시 투표하지 마세요.';

  @override
  String get votingEndsToday => '오늘 종료';

  @override
  String get votingOneDayLeft => '1일 남음';

  @override
  String votingDaysLeft(int days) {
    return '$days일 남음';
  }

  @override
  String get mobileExitBackHint => '종료하려면 뒤로 가기를 한 번 더 누르세요';
}
