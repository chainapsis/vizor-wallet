// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aboutBuiltByBody =>
      '저‍희‍는 Cosmos, Ethereum, Bitcoin‍에‍서 수‍백‍만 명‍이 쓰‍는 지‍갑 Keplr‍를 만‍들‍었‍어‍요. Vizor‍는 Zcash 지‍갑‍이 어‍떠‍해‍야 하‍는‍지‍에 대‍한 저‍희‍의 답‍이‍에‍요.';

  @override
  String get aboutBuiltByHeading => 'Keplr 팀‍이 만‍들‍었‍어‍요';

  @override
  String get aboutLegalPlaceholderBody =>
      'Bitcoin‍이‍나 Ethereum‍과 달‍리 차‍폐 Zcash 거‍래‍는 보‍낸 사‍람, 받‍는 사‍람, 금‍액‍을 숨‍겨‍요.';

  @override
  String get aboutLegalPlaceholderHeading => 'Keplr 지‍갑‍을 만‍든 팀‍이 만‍들‍었‍어‍요.';

  @override
  String aboutLinkSemantics(String label) {
    return '$label 링‍크';
  }

  @override
  String get aboutOpenGithub => 'Vizor GitHub 열‍기';

  @override
  String get aboutOpenSourceBody =>
      'Vizor‍는 Apache 라‍이‍선‍스‍로 공‍개‍돼 있‍어‍요. 키‍는 내 기‍기‍에‍만 있‍어‍요.\n잔‍액‍이‍나 거‍래 내‍역‍은 저‍희‍가 볼 수 없‍어‍요.';

  @override
  String get aboutOpenSourceHeading => '오‍픈 소‍스, 자‍기 보‍관';

  @override
  String get aboutOpenWebsite => 'Vizor 웹‍사‍이‍트 열‍기';

  @override
  String get aboutShieldedBody =>
      'Vizor‍는 보‍낸 사‍람, 받‍는 사‍람, 금‍액‍이 비‍공‍개‍로 유‍지‍되‍는 차‍폐 거‍래‍를 중‍심‍으‍로 만‍들‍어‍졌‍어‍요. 투‍명 Zcash‍도 쓸 수 있‍지‍만 기‍본‍은 비‍공‍개‍예‍요.';

  @override
  String get aboutShieldedHeading => '차‍폐 Zcash‍를 위‍해 설‍계‍했‍어‍요';

  @override
  String get aboutTermsTitle => '이‍용 약‍관';

  @override
  String get aboutTitle => 'Vizor 지‍갑 정‍보';

  @override
  String aboutVersionLabel(String version) {
    return '버‍전: $version 퍼‍블‍릭 베‍타';
  }

  @override
  String get aboutWebsite => '웹‍사‍이‍트';

  @override
  String get accountNameLabel => '계‍정 이‍름';

  @override
  String get accountNameRequired => '이‍름‍을 입‍력‍해 주‍세‍요.';

  @override
  String get accountNameTooLong => '이‍름‍은 20‍자‍까‍지 입‍력‍할 수 있‍어‍요.';

  @override
  String get accountsActionsLabel => '계‍정 작‍업';

  @override
  String get accountsAddressLoadFailed => '계‍정 주‍소‍를 불‍러‍오‍지 못‍했‍어‍요';

  @override
  String get accountsClearName => '계‍정 이‍름 지‍우‍기';

  @override
  String get accountsCurrent => '현‍재 계‍정';

  @override
  String get accountsEdit => '계‍정 편‍집';

  @override
  String get accountsEditFailed => '계‍정‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String get accountsEditNameHint => '1-20‍자';

  @override
  String get accountsManage => '계‍정 관‍리';

  @override
  String accountsOptionsFor(String name) {
    return '$name 계‍정 옵‍션';
  }

  @override
  String get accountsOther => '다‍른 계‍정';

  @override
  String get accountsOtherAccounts => '다‍른 계‍정';

  @override
  String get accountsRemove => '계‍정 삭‍제';

  @override
  String get accountsRemoveBackupWarning =>
      '이 계‍정‍의 복‍구 문‍구‍를 백‍업‍하‍지 않‍았‍다‍면, 삭‍제‍한 뒤‍에‍는 계‍정‍의 자‍금‍을 복‍구‍할 수 없‍어‍요.';

  @override
  String accountsRemoveBlockedByGiftCards(int count) {
    return '이 계‍정‍으‍로 기‍프‍트 카‍드 $count‍장‍을 받‍는 중‍이‍에‍요. 이 계‍정‍을 삭‍제‍하‍기 전‍에 완‍료‍될 때‍까‍지 기‍다‍려 주‍세‍요.';
  }

  @override
  String accountsRemoveBlockedBySwaps(int count) {
    return '이 계‍정‍에 진‍행 중‍인 스‍왑‍이 $count‍개 있‍어‍요. 이 계‍정‍을 삭‍제‍하‍기 전‍에 스‍왑 활‍동‍에‍서 완‍료‍하‍거‍나 삭‍제‍해 주‍세‍요.';
  }

  @override
  String get accountsRemoveBody =>
      '이 계‍정‍을 삭‍제‍하‍면 Vizor‍에‍서 계‍정‍의 로‍컬 데‍이‍터‍가 삭‍제‍돼‍요. 계‍속‍하‍기 전‍에 계‍정‍을 다‍시 가‍져‍올 수 있‍는‍지 꼭 확‍인‍하‍세‍요.';

  @override
  String get accountsRemoveCheckingGiftCards =>
      '삭‍제‍하‍기 전‍에 이 계‍정‍으‍로 받‍는 중‍인 기‍프‍트 카‍드‍가 있‍는‍지 확‍인‍하‍는 중‍이‍에‍요.';

  @override
  String get accountsRemoveCheckingPassword => '비‍밀‍번‍호 확‍인 중...';

  @override
  String get accountsRemoveCheckingSwaps =>
      '삭‍제‍하‍기 전‍에 이 계‍정‍에 진‍행 중‍인 스‍왑‍이 있‍는‍지 확‍인‍하‍는 중‍이‍에‍요.';

  @override
  String get accountsRemoveFailed => '계‍정‍을 삭‍제‍하‍지 못‍했‍어‍요.';

  @override
  String get accountsRemoveFailedToast => '계‍정‍을 삭‍제‍하‍지 못‍했‍어‍요';

  @override
  String get accountsRemoveGiftCardsCheckFailed =>
      '이 계‍정‍으‍로 받‍는 중‍인 기‍프‍트 카‍드‍가 있‍는‍지 확‍인‍하‍지 못‍했‍어‍요. 삭‍제‍하‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get accountsRemoveGiftCardsMoreFunded =>
      '더 많‍은 기‍프‍트 카‍드 링‍크‍에 자‍금‍이 채‍워‍졌‍어‍요. 경‍고‍를 검‍토‍하‍고 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get accountsRemoveGiftCardsRecheckFailed =>
      '기‍프‍트 카‍드 링‍크‍를 다‍시 확‍인‍하‍지 못‍했‍어‍요. 경‍고‍를 검‍토‍하‍고 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get accountsRemoveMigrationBody =>
      '이 계‍정‍의 마‍이‍그‍레‍이‍션 작‍업‍은 더 이‍상 Vizor‍에‍서 계‍속‍되‍지 않‍아‍요. 이‍미 Zcash 네‍트‍워‍크‍에 제‍출‍한 거‍래‍는 그‍대‍로 완‍료‍될 수 있‍어‍요. 다‍시 가‍져‍온 뒤‍에‍는 계‍정‍을 완‍전‍히 동‍기‍화‍한 다‍음‍에 마‍이‍그‍레‍이‍션‍을 다‍시 시‍작‍하‍세‍요.';

  @override
  String get accountsRemoveModalBody =>
      '이 계‍정‍을 삭‍제‍할‍까‍요? 이 작‍업‍은 되‍돌‍릴 수 없‍어‍요.\n계‍정‍을 다‍시 가‍져‍와‍야 해‍요.';

  @override
  String get accountsRemovePasswordHint => '비‍밀‍번‍호‍를 입‍력‍하‍세‍요';

  @override
  String get accountsRemoveStoppingSync => '동‍기‍화‍를 중‍지‍하‍는 중...';

  @override
  String get accountsRemoveSwapsCheckFailed =>
      '이 계‍정‍에 진‍행 중‍인 스‍왑‍이 있‍는‍지 확‍인‍하‍지 못‍했‍어‍요. 삭‍제‍하‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get accountsRemoveWaitForGiftCards =>
      '이 계‍정‍을 삭‍제‍하‍기 전‍에 받‍는 중‍인 기‍프‍트 카‍드‍가 끝‍날 때‍까‍지 기‍다‍려 주‍세‍요.';

  @override
  String get accountsRemoving => '계‍정‍을 삭‍제‍하‍는 중...';

  @override
  String get accountsResetBody =>
      'Vizor‍를 초‍기‍화‍하‍면 모‍든 계‍정‍과 지‍갑 데‍이‍터‍가 삭‍제‍돼‍요. 계‍속‍하‍기 전‍에 계‍정‍을 다‍시 가‍져‍올 수 있‍는‍지 꼭 확‍인‍하‍세‍요.';

  @override
  String get accountsResetFailed => 'Vizor‍를 초‍기‍화‍하‍지 못‍했‍어‍요.';

  @override
  String get accountsResetFailedToast => 'Vizor‍를 초‍기‍화‍하‍지 못‍했‍어‍요';

  @override
  String get accountsResetMigrationBody =>
      'Vizor‍를 초‍기‍화‍하‍면 이 기‍기‍의 마‍이‍그‍레‍이‍션 작‍업‍이 중‍단‍되‍고 모‍든 계‍정‍과 지‍갑 데‍이‍터‍가 삭‍제‍돼‍요. 이‍미 Zcash 네‍트‍워‍크‍에 제‍출‍한 거‍래‍는 그‍대‍로 완‍료‍될 수 있‍어‍요. 다‍시 가‍져‍온 뒤‍에‍는 각 계‍정‍을 완‍전‍히 동‍기‍화‍한 다‍음‍에 마‍이‍그‍레‍이‍션‍을 다‍시 시‍작‍하‍세‍요.';

  @override
  String get accountsResetModalBody =>
      '이 계‍정‍을 삭‍제‍하‍면 Vizor 앱‍이 완‍전‍히 초‍기‍화‍돼‍요. 모‍든 계‍정‍이 삭‍제‍되‍고 계‍정‍을 다‍시 가‍져‍와‍야 해‍요.\n공‍유‍하‍지 않‍은 기‍프‍트 카‍드 링‍크‍도 영‍구‍적‍으‍로 사‍라‍져‍요.\n이 작‍업‍은 되‍돌‍릴 수 없‍어‍요.';

  @override
  String get accountsResetting => '초‍기‍화‍하‍는 중...';

  @override
  String get accountsSaveEdits => '변‍경 사‍항 저‍장';

  @override
  String get accountsSaveFailed => '계‍정 변‍경 사‍항‍을 저‍장‍하‍지 못‍했‍어‍요';

  @override
  String get accountsSendFailed => '보‍내‍기‍를 시‍작‍하‍지 못‍했‍어‍요';

  @override
  String get accountsTitle => '계‍정';

  @override
  String get accountsUpdatePicture => '사‍진 업‍데‍이‍트';

  @override
  String get accountsViewSecretPhrase => '복‍구 문‍구 보‍기';

  @override
  String get accountsViewViewingKey => '뷰‍잉 키 보‍기';

  @override
  String get activityAddressUnified => '통‍합 주‍소';

  @override
  String get activityBalanceFromOrchard => 'Orchard 잔‍액‍에‍서';

  @override
  String get activityBalanceFromTransparent => '투‍명 잔‍액‍에‍서';

  @override
  String get activityBalanceIronwood => 'Ironwood 잔‍액';

  @override
  String get activityBalanceOrchard => 'Orchard 잔‍액';

  @override
  String get activityDetailsLoadFailed => '실‍패, 다‍시 시‍도';

  @override
  String get activityDetailsLoadPublicly => '공‍개‍로 불‍러‍오‍기';

  @override
  String get activityDetailsLoadPubliclyLabel => '전‍체 상‍세 정‍보';

  @override
  String get activityDetailsLoading => '불‍러‍오‍는 중…';

  @override
  String get activityDetailsNotCovered => '비‍공‍개 모‍드‍에‍서‍는 볼 수 없‍어‍요';

  @override
  String get activityDetailsOmittedLabel => '표‍시‍되‍지 않‍음';

  @override
  String get activityDetailsOutputsLabel => '거‍래 출‍력';

  @override
  String get activityDetailsOutputsUnattributed => '받‍는 사‍람 미‍확‍인';

  @override
  String get activityDetailsUnavailable =>
      '상‍세 정‍보‍를 불‍러‍올 수 없‍어‍요. 서‍비‍스‍에 연‍결‍되‍면 업‍데‍이‍트‍돼‍요';

  @override
  String get activityDetailsUnknownRecipient => '알 수 없‍는 받‍는 사‍람';

  @override
  String get activityEtaFunding => '약 2–6‍분';

  @override
  String get activityEtaNu7 => '약 1‍분 이‍내';

  @override
  String get activityEtaNu7Funding => '약 1–2‍분';

  @override
  String get activityEtaStandard => '약 1–3‍분';

  @override
  String get activityEtaTakingLonger => '지‍연 중';

  @override
  String get activityFeedEmpty => '아‍직 활‍동‍이 없‍어‍요';

  @override
  String get activityFeedRetry => '활‍동 다‍시 불‍러‍오‍기';

  @override
  String activityGiftBatchBreakdown(
    String cards,
    String fees,
    String feeLabel,
    String fee,
  ) {
    return '카‍드 $cards ZEC · 받‍기 수‍수‍료 $fees ZEC · $feeLabel $fee';
  }

  @override
  String get activityGiftCreated => '기‍프‍트 카‍드 생‍성';

  @override
  String activityGiftCreatedMany(int count) {
    return '기‍프‍트 카‍드 $count‍장 생‍성';
  }

  @override
  String get activityGiftCreating => '카‍드 생‍성 중';

  @override
  String activityGiftCreatingMany(int count) {
    return '카‍드 $count‍장 생‍성 중';
  }

  @override
  String get activityGiftCreationFailed => '기‍프‍트 카‍드 생‍성 실‍패';

  @override
  String get activityGiftGroupFailed => '기‍프‍트 카‍드 그‍룹 실‍패';

  @override
  String get activityGiftRedeemed => '기‍프‍트 카‍드 받‍음';

  @override
  String get activityGiftRedeeming => '카‍드 받‍는 중';

  @override
  String get activityGiftRedemptionFailed => '기‍프‍트 카‍드 받‍기 실‍패';

  @override
  String get activityGiftStatusRedeemed => '받‍음';

  @override
  String get activityGiftStatusRedeeming => '받‍는 중…';

  @override
  String get activityGiftTotalPlanned => '예‍정 합‍계';

  @override
  String get activityGiftTotalSpent => '총 사‍용‍액';

  @override
  String get activityGiftTotalSubmitted => '제‍출‍한 합‍계';

  @override
  String get activityLoadFailedDesktop => '활‍동‍을 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get activityLoadFailedMobile =>
      '활‍동‍을 불‍러‍오‍지 못‍했‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get activityOmissionLaterOutputs => '두 번‍째 이‍후‍의 출‍력';

  @override
  String activityOmissionMoreOutputs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '출‍력 $count‍개 더',
    );
    return '$_temp0';
  }

  @override
  String get activityOmissionOtherSenders => '다‍른 보‍낸 주‍소';

  @override
  String get activityOmissionOutputAddress => '출‍력 주‍소';

  @override
  String get activityOmissionSender => '보‍낸 주‍소';

  @override
  String get activityOmissionSharedFunding => '다‍른 지‍갑‍의 입‍력';

  @override
  String get activityOmissionShieldedFunding => '자‍금 중 차‍폐‍된 부‍분';

  @override
  String get activityPayFromShielded => '차‍폐‍된 ZEC‍에‍서';

  @override
  String activityPayFromShieldedOnChain(String network) {
    return '차‍폐‍된 ZEC‍에‍서 · $network';
  }

  @override
  String get activityPayIncomplete => '결‍제 미‍완‍료';

  @override
  String get activityPayPaid => '결‍제 완‍료';

  @override
  String get activityPayPaying => '결‍제 중...';

  @override
  String get activityPoolMixed => '혼‍합';

  @override
  String get activityPublicLookupBody =>
      'Vizor‍가 이 거‍래 하‍나‍를 서‍버‍에 요‍청‍해‍서 비‍공‍개 조‍회‍에‍서 빠‍진 정‍보‍를 보‍여 드‍려‍요.';

  @override
  String get activityPublicLookupTitle => '상‍세 정‍보‍를 공‍개‍로 불‍러‍올‍까‍요?';

  @override
  String get activityPublicLookupWarning =>
      '서‍버‍는 이 지‍갑‍이 이 거‍래‍에 관‍심‍이 있‍다‍는 사‍실‍을 알‍게 되‍고, Tor‍를 쓰‍지 않‍으‍면 IP 주‍소‍도 알‍게 돼‍요.';

  @override
  String get activityReceiptAmountMigrated => '마‍이‍그‍레‍이‍션‍한 금‍액';

  @override
  String get activityReceiptCardFee => '카‍드 수‍수‍료';

  @override
  String get activityReceiptDetails => '상‍세 정‍보';

  @override
  String get activityReceiptDetailsIncomplete => '상‍세 정‍보‍가 완‍전‍하‍지 않‍아‍요';

  @override
  String get activityReceiptDetailsIncompleteHelp =>
      '이 거‍래‍의 받‍는 사‍람, 메‍모, 수‍수‍료 같‍은 일‍부 정‍보‍를 아‍직 알 수 없‍어‍요. 표‍시‍된 금‍액‍이 바‍뀔 수 있‍어‍요.';

  @override
  String get activityReceiptEstimatedNetworkFee => '예‍상 네‍트‍워‍크 수‍수‍료';

  @override
  String get activityReceiptFrom => '보‍낸 곳';

  @override
  String get activityReceiptIncomplete => '불‍완‍전';

  @override
  String get activityReceiptLoadFailed => '거‍래‍를 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get activityReceiptLoading => '거‍래‍를 불‍러‍오‍는 중…';

  @override
  String get activityReceiptNetChange => '순‍변‍동';

  @override
  String get activityReceiptOutput => '출‍력';

  @override
  String get activityReceiptRefreshFailed => '최‍신 거‍래 상‍태‍를 새‍로 고‍치‍지 못‍했‍어‍요.';

  @override
  String get activityReceiptStatus => '상‍태';

  @override
  String get activityReceiptUnattributedFeeHelp =>
      '이 거‍래‍의 총 수‍수‍료‍예‍요. 내 계‍정‍이 부‍담‍한 금‍액‍은 알 수 없‍어‍요.';

  @override
  String activityRowToday(String time) {
    return '오‍늘 $time';
  }

  @override
  String get activityRowWaitingForConnection => '연‍결‍을 기‍다‍리‍는 중';

  @override
  String activityRowYesterday(String time) {
    return '어‍제 $time';
  }

  @override
  String get activitySectionEarlier => '이‍전';

  @override
  String get activitySectionThisWeek => '이‍번 주';

  @override
  String get activitySenderShielded => '차‍폐‍된 보‍낸 사‍람';

  @override
  String get activitySenderUnknown => '알 수 없‍는 보‍낸 사‍람';

  @override
  String get activityStatusFailedFundsReturned => '실‍패, 자‍금 반‍환‍됨';

  @override
  String get activityStatusIncompleteDeposit => '입‍금 부‍족';

  @override
  String activitySwapAssetOnChain(String symbol, String chain) {
    return '$chain‍의 $symbol';
  }

  @override
  String activitySwapDepositedAsset(String symbol) {
    return '$symbol 입‍금‍됨';
  }

  @override
  String activitySwapMinutesAgo(int minutes) {
    return '$minutes‍분 전';
  }

  @override
  String activitySwapReceivedAsset(String symbol) {
    return '$symbol 받‍음';
  }

  @override
  String activitySwapStep(int current, int total) {
    return '$current/$total 진‍행 중';
  }

  @override
  String get activitySwapSwapped => '스‍왑 완‍료';

  @override
  String get activitySwapSwapping => '스‍왑 중...';

  @override
  String get activitySwapTimeout => '시‍간 초‍과';

  @override
  String get activitySwapTitle => '스‍왑';

  @override
  String get activityTitleMigrated => 'Ironwood‍로 마‍이‍그‍레‍이‍션‍됨';

  @override
  String get activityTitleMigrating => 'Ironwood‍로 마‍이‍그‍레‍이‍션‍하‍는 중...';

  @override
  String get activityTitleMigratingVerb => 'Ironwood‍로 마‍이‍그‍레‍이‍션‍하‍는 중';

  @override
  String get activityTitleMigrationFailed => '마‍이‍그‍레‍이‍션 실‍패';

  @override
  String get activityTitleReceiveFailed => '받‍기 실‍패';

  @override
  String get activityTitleReceiveInProgress => '받‍는 중...';

  @override
  String get activityTitleReceivedSuccessfully => '받‍았‍어‍요';

  @override
  String get activityTitleReceiving => '받‍는 중...';

  @override
  String get activityTitleReceivingVerb => '받‍는 중';

  @override
  String get activityTitleSendingVerb => '보‍내‍는 중';

  @override
  String get activityTitleSent => '보‍냄';

  @override
  String get activityTitleShielded => '차‍폐‍됨';

  @override
  String get activityTitleShieldingFailed => '차‍폐 실‍패';

  @override
  String get activityTitleShieldingInProgress => '차‍폐‍하‍는 중...';

  @override
  String get activityTitleShieldingVerb => '차‍폐‍하‍는 중';

  @override
  String get activityTitleTransaction => '거‍래';

  @override
  String get activityToastHashCopiedMobile => '거‍래 해‍시‍를 복‍사‍했‍어‍요';

  @override
  String get addressBookAddContact => '연‍락‍처 추‍가';

  @override
  String get addressBookAddressHintDesktop => '주‍소‍를 입‍력‍하‍세‍요';

  @override
  String get addressBookAddressHintMobile => '주‍소‍를 입‍력‍하‍세‍요';

  @override
  String get addressBookAddressLabel => '주‍소';

  @override
  String get addressBookAddressMissing => '주‍소‍를 입‍력‍해 주‍세‍요';

  @override
  String get addressBookClearAddress => '주‍소 지‍우‍기';

  @override
  String get addressBookClearName => '이‍름 지‍우‍기';

  @override
  String get addressBookClearSearch => '검‍색‍어 지‍우‍기';

  @override
  String addressBookContactActions(String label) {
    return '$label 작‍업';
  }

  @override
  String get addressBookEditContact => '연‍락‍처 수‍정';

  @override
  String get addressBookEmptyBody => '첫 연‍락‍처‍를 추‍가‍해 시‍작‍해 보‍세‍요.';

  @override
  String get addressBookEmptyTitle => '아‍직 연‍락‍처‍가 없‍어‍요';

  @override
  String get addressBookInvalidBitcoin => '올‍바‍르‍지 않‍은 Bitcoin 주‍소‍예‍요';

  @override
  String get addressBookInvalidEvm => '올‍바‍르‍지 않‍은 EVM 주‍소‍예‍요';

  @override
  String get addressBookInvalidNear => '올‍바‍르‍지 않‍은 NEAR 주‍소‍예‍요';

  @override
  String get addressBookInvalidSolana => '올‍바‍르‍지 않‍은 Solana 주‍소‍예‍요';

  @override
  String get addressBookInvalidZcash => '올‍바‍르‍지 않‍은 Zcash 주‍소‍예‍요';

  @override
  String get addressBookLabelLength => '1~20‍자‍로 입‍력‍해 주‍세‍요';

  @override
  String get addressBookLabelMissing => '라‍벨‍을 입‍력‍해 주‍세‍요';

  @override
  String get addressBookLoadFailed =>
      '연‍락‍처‍를 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나, 계‍속‍되‍면 고‍객 지‍원‍에 문‍의‍해 주‍세‍요.';

  @override
  String get addressBookNameHint => '이‍름‍을 입‍력‍하‍세‍요';

  @override
  String get addressBookNameLabel => '이‍름';

  @override
  String get addressBookNearSuffixWarning =>
      'NEAR 계‍정‍은 보‍통 .near‍로 끝‍나‍요. 주‍소‍를 다‍시 확‍인‍해 주‍세‍요';

  @override
  String get addressBookNetworkLabel => '네‍트‍워‍크';

  @override
  String get addressBookNoNetworks => '네‍트‍워‍크‍를 찾‍지 못‍했‍어‍요';

  @override
  String get addressBookNoResultsBody => '검‍색‍어‍를 바‍꿔 보‍세‍요';

  @override
  String get addressBookNoResultsTitle => '연‍락‍처‍를 찾‍지 못‍했‍어‍요';

  @override
  String get addressBookPickerClose => '연‍락‍처 닫‍기';

  @override
  String get addressBookPickerEmptyTitle => '연‍락‍처‍를 찾‍지 못‍했‍어‍요';

  @override
  String get addressBookPickerLoadFailed =>
      '연‍락‍처‍를 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get addressBookPickerSearchHint => '연‍락‍처 검‍색';

  @override
  String addressBookRemoveBody(String label) {
    return '$label 연‍락‍처‍를 삭‍제‍해‍요.';
  }

  @override
  String get addressBookRemoveBodyUnknown => '이 연‍락‍처‍를 삭‍제‍해‍요.';

  @override
  String addressBookRemoveConfirmBody(String label) {
    return '\"$label\" 연‍락‍처‍를 삭‍제‍해‍요. 지‍난 거‍래‍에‍는 영‍향‍이 없‍어‍요.';
  }

  @override
  String get addressBookRemoveConfirmTitle => '연‍락‍처‍를 삭‍제‍할‍까‍요?';

  @override
  String get addressBookRemoveContact => '연‍락‍처 삭‍제';

  @override
  String get addressBookRemoveFailed =>
      '연‍락‍처‍를 삭‍제‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get addressBookRemoveFailedMobile =>
      '연‍락‍처‍를 삭‍제‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get addressBookSaveFailed =>
      '연‍락‍처‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get addressBookSaveFailedMobile =>
      '연‍락‍처‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get addressBookScanAddressQr => '주‍소 QR 스‍캔';

  @override
  String addressBookScanQrTitle(String network) {
    return '$network QR 코‍드 스‍캔';
  }

  @override
  String get addressBookSearch => '검‍색';

  @override
  String get addressBookSearchHint => '라‍벨 또‍는 네‍트‍워‍크 검‍색';

  @override
  String get addressBookSearchNetwork => '네‍트‍워‍크 검‍색';

  @override
  String get addressBookSelectNetwork => '네‍트‍워‍크 선‍택';

  @override
  String get addressScanAddressCameraNeeded =>
      '주‍소 QR‍을 스‍캔‍하‍려‍면 이 기‍기‍에 카‍메‍라‍가 필‍요‍해‍요.';

  @override
  String addressScanCameraDefaultSuffix(String name) {
    return '$name (기‍본)';
  }

  @override
  String get addressScanCameraNeeded =>
      'QR‍을 스‍캔‍하‍려‍면 이 기‍기‍에 카‍메‍라‍가 필‍요‍해‍요.';

  @override
  String get addressScanCameraOff =>
      '카‍메‍라 접‍근‍이 꺼‍져 있‍어‍요. 주‍소‍를 스‍캔‍하‍려‍면 설‍정‍에‍서 허‍용‍해 주‍세‍요.';

  @override
  String get addressScanCameraOpenFailed =>
      '카‍메‍라‍를 열 수 없‍어‍요. 카‍메‍라‍를 쓰‍는 다‍른 앱‍을 닫‍아 주‍세‍요.';

  @override
  String get addressScanCameraRequired =>
      '주‍소 QR‍을 스‍캔‍하‍려‍면 이 기‍기‍에 카‍메‍라‍가 필‍요‍해‍요.';

  @override
  String get addressScanCameraRestricted =>
      '스‍크‍린 타‍임 또‍는 기‍기 관‍리‍가 이 기‍기‍의 카‍메‍라‍를 차‍단‍하‍고 있‍어‍요.';

  @override
  String get addressScanCloseScanner => '스‍캐‍너 닫‍기';

  @override
  String get addressScanDeniedTitle => '카‍메‍라 접‍근‍을 거‍부‍했‍어‍요';

  @override
  String get addressScanGrantAccess => '카‍메‍라 접‍근‍을 허‍용‍해 주‍세‍요';

  @override
  String get addressScanTitle => '주‍소 QR 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String get addressScanZcashPrompt => '계‍속‍하‍려‍면 Zcash QR 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String get appBackDonation => '후‍원';

  @override
  String get appBackHardwareWallets => '하‍드‍웨‍어 지‍갑';

  @override
  String get appBackImportMethods => '가‍져‍오‍기 방‍법';

  @override
  String get appBackReceive => '받‍기';

  @override
  String get appBackReview => '검‍토';

  @override
  String get appBackSend => '보‍내‍기';

  @override
  String get appBackStatus => '상‍태';

  @override
  String get appBackSubmitted => '제‍출 완‍료';

  @override
  String get appBackTransaction => '거‍래';

  @override
  String get appExitBackHint => '한 번 더 뒤‍로 가‍면 종‍료‍돼‍요';

  @override
  String appLinuxUpdateAvailable(String version) {
    return 'Vizor $version 버‍전‍을 사‍용‍할 수 있‍어‍요.';
  }

  @override
  String appLinuxUpdateAvailableTor(String version) {
    return 'Vizor $version 버‍전‍을 사‍용‍할 수 있‍어‍요. 릴‍리‍스 페‍이‍지‍는 Vizor‍의 Tor 연‍결 밖‍에‍서 브‍라‍우‍저‍로 열‍려‍요.';
  }

  @override
  String get appLinuxUpdateOpenInBrowser => '브‍라‍우‍저‍에‍서 열‍기';

  @override
  String get appLinuxUpdateViewRelease => '릴‍리‍스 보‍기';

  @override
  String get appOpenFailedTitle => 'Vizor‍를 열 수 없‍어‍요';

  @override
  String get appPrivacyPolicyTitle => '개‍인‍정‍보 처‍리‍방‍침';

  @override
  String get appTermsOfUseTitle => '이‍용 약‍관';

  @override
  String get appUpdateApplyingMessage => 'Vizor‍가 종‍료‍되‍면 적‍용‍돼‍요.';

  @override
  String get appUpdateAvailableMessage =>
      '지‍금 다‍운‍로‍드‍하‍거‍나 계‍속 사‍용‍할 수 있‍어‍요.';

  @override
  String get appUpdateAvailableTitle => '업‍데‍이‍트 사‍용 가‍능';

  @override
  String appUpdateAvailableVersionTitle(String version) {
    return '업‍데‍이‍트 $version 사‍용 가‍능';
  }

  @override
  String get appUpdateDismiss => '닫‍기';

  @override
  String get appUpdateDownloading => '다‍운‍로‍드 중';

  @override
  String appUpdateDownloadingMessage(int percent) {
    return '$percent% 다‍운‍로‍드‍했‍어‍요.';
  }

  @override
  String get appUpdateDownloadingTitle => '업‍데‍이‍트 다‍운‍로‍드 중';

  @override
  String get appUpdateLater => '나‍중‍에';

  @override
  String get appUpdateReadyMessage => '준‍비‍되‍면 다‍시 시‍작‍해 주‍세‍요.';

  @override
  String get appUpdateReadyTitle => '업‍데‍이‍트 준‍비 완‍료';

  @override
  String get appUpdateRestarting => '다‍시 시‍작 중';

  @override
  String get appUpdateRestartingTitle => 'Vizor 다‍시 시‍작 중';

  @override
  String biometricChangedMessage(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID‍가 변‍경‍되‍었‍어‍요. 암‍호‍를 입‍력‍해 주‍세‍요.',
      'touchId': 'Touch ID‍가 변‍경‍되‍었‍어‍요. 암‍호‍를 입‍력‍해 주‍세‍요.',
      'fingerprint': '지‍문‍이 변‍경‍되‍었‍어‍요. 암‍호‍를 입‍력‍해 주‍세‍요.',
      'other': '생‍체 인‍식‍이 변‍경‍되‍었‍어‍요. 암‍호‍를 입‍력‍해 주‍세‍요.',
    });
    return '$_temp0';
  }

  @override
  String biometricEnableLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID 켜‍기',
      'touchId': 'Touch ID 켜‍기',
      'fingerprint': '지‍문 켜‍기',
      'other': '생‍체 인‍식 켜‍기',
    });
    return '$_temp0';
  }

  @override
  String biometricNameInline(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID',
      'touchId': 'Touch ID',
      'fingerprint': '지‍문',
      'other': '생‍체 인‍식',
    });
    return '$_temp0';
  }

  @override
  String biometricNameOnboardingTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID',
      'touchId': 'Touch ID',
      'fingerprint': '지‍문',
      'other': '생‍체 인‍식',
    });
    return '$_temp0';
  }

  @override
  String biometricNameStandalone(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID',
      'touchId': 'Touch ID',
      'fingerprint': '지‍문',
      'other': '생‍체 인‍식',
    });
    return '$_temp0';
  }

  @override
  String biometricSignInLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID‍로 로‍그‍인',
      'touchId': 'Touch ID‍로 로‍그‍인',
      'fingerprint': '지‍문‍으‍로 로‍그‍인',
      'other': '생‍체 인‍식‍으‍로 로‍그‍인',
    });
    return '$_temp0';
  }

  @override
  String biometricUnlockFeatureInline(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID 잠‍금 해‍제',
      'touchId': 'Touch ID 잠‍금 해‍제',
      'fingerprint': '지‍문 잠‍금 해‍제',
      'other': '생‍체 인‍식 잠‍금 해‍제',
    });
    return '$_temp0';
  }

  @override
  String biometricUnlockFeatureLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID 잠‍금 해‍제',
      'touchId': 'Touch ID 잠‍금 해‍제',
      'fingerprint': '지‍문 잠‍금 해‍제',
      'other': '생‍체 인‍식 잠‍금 해‍제',
    });
    return '$_temp0';
  }

  @override
  String biometricUseNextTimeLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': '다‍음‍에 Face ID 사‍용',
      'touchId': '다‍음‍에 Touch ID 사‍용',
      'fingerprint': '다‍음‍에 지‍문 사‍용',
      'other': '다‍음‍에 생‍체 인‍식 사‍용',
    });
    return '$_temp0';
  }

  @override
  String get bip39PassphraseTitle => 'BIP39 패‍스‍프‍레‍이‍즈';

  @override
  String bip39PassphraseValue(String passphrase) {
    return 'BIP39 패‍스‍프‍레‍이‍즈: $passphrase';
  }

  @override
  String broadcastNoticeBroadcastFailed(
    String sent,
    String total,
    String txids,
    String detail,
  ) {
    return '거‍래 $total‍건 중 $sent‍건‍을 보‍낸 뒤 전‍송‍에 실‍패‍했‍어‍요($txids). 오‍류: $detail';
  }

  @override
  String broadcastNoticeBroadcastStorageFailed(String txid, String detail) {
    return '전‍송‍에 성‍공‍했‍지‍만(txid=$txid) 로‍컬 저‍장‍에 실‍패‍했‍어‍요. $detail. 거‍래‍는 네‍트‍워‍크‍에 있‍어‍요. 블‍록 탐‍색‍기‍에‍서 확‍인‍하‍고, 다‍음 동‍기‍화‍로 잔‍액‍이 맞‍춰‍질 때‍까‍지 다‍시 보‍내‍지 마‍세‍요.';
  }

  @override
  String broadcastNoticeDatabaseUnavailable(String detail) {
    return '로‍컬‍에‍서 거‍래‍를 만‍든 뒤 전‍송‍을 위‍해 데‍이‍터‍베‍이‍스‍를 열‍지 못‍했‍어‍요: $detail';
  }

  @override
  String broadcastNoticeExpired(
    String txid,
    String expiryHeight,
    String chainHeight,
  ) {
    return '하‍드‍웨‍어 서‍명 요‍청‍이 전‍송 전‍에 만‍료‍됐‍어‍요: txid=$txid, 만‍료 블‍록 높‍이 $expiryHeight, 현‍재 블‍록 높‍이 $chainHeight. Vizor‍가 새 거‍래‍를 만‍들 수 있‍도‍록 서‍명‍을 다‍시 시‍작‍하‍세‍요.';
  }

  @override
  String broadcastNoticeRawTransactionUnavailable(String txid, String detail) {
    return '로‍컬‍에‍서 거‍래‍를 만‍든 뒤 $txid‍의 원‍본 거‍래‍를 읽‍지 못‍했‍어‍요: $detail';
  }

  @override
  String broadcastNoticeResponseUnavailable(String txid, String detail) {
    return 'txid=$txid‍의 전‍송 응‍답‍을 받‍지 못‍했‍어‍요($detail). 거‍래‍가 이‍미 네‍트‍워‍크‍에 있‍을 수 있‍어‍요. 동‍기‍화‍나 블‍록 탐‍색‍기‍에‍서 이 거‍래‍가 수‍락‍됐‍는‍지 확‍인‍하‍기 전‍에‍는 다‍시 보‍내‍지 마‍세‍요.';
  }

  @override
  String broadcastNoticeRetentionFailed(String detail) {
    return '보‍낸 자‍금‍의 잠‍금 유‍지‍에‍도 실‍패‍했‍어‍요: $detail.';
  }

  @override
  String get broadcastNoticeRetryingLocally =>
      '로‍컬‍에 저‍장‍했‍고, 확‍인‍되‍거‍나 만‍료‍될 때‍까‍지 동‍기‍화 중‍에 자‍동‍으‍로 다‍시 시‍도‍해‍요.';

  @override
  String broadcastNoticeRouteUnavailable(
    String index,
    String total,
    String detail,
  ) {
    return '전‍체 $total‍건 중 $index‍번‍째 거‍래‍의 전‍송 경‍로‍를 열‍지 못‍해 저‍장‍하‍지 않‍았‍어‍요: $detail';
  }

  @override
  String broadcastNoticeStorageFailed(String detail) {
    return '거‍래‍가 이‍미 네‍트‍워‍크‍에 있‍을 수 있‍지‍만 로‍컬 저‍장‍에 실‍패‍했‍어‍요: $detail. 동‍기‍화‍나 블‍록 탐‍색‍기‍에‍서 결‍과‍를 확‍인‍하‍기 전‍에‍는 다‍시 보‍내‍지 마‍세‍요.';
  }

  @override
  String get broadcastNoticeStoredLocally =>
      '전‍송‍됐‍거‍나 전‍송‍됐‍을 수 있‍는 거‍래‍는 복‍구‍를 위‍해 로‍컬‍에 저‍장‍했‍어‍요.';

  @override
  String broadcastNoticeTrackingFailed(String detail) {
    return '로‍컬 추‍적‍에‍도 실‍패‍했‍어‍요: $detail. 이 송‍금‍을 다‍시 시‍도‍하‍기 전‍에 블‍록 탐‍색‍기‍를 확‍인‍하‍세‍요.';
  }

  @override
  String broadcastNoticeTransactionRejected(
    String index,
    String total,
    String detail,
  ) {
    return '전‍체 $total‍건 중 $index‍번‍째 거‍래‍가 거‍부‍되‍어 저‍장‍하‍지 않‍았‍어‍요: $detail';
  }

  @override
  String broadcastNoticeTransactionUnknown(
    String index,
    String total,
    String detail,
  ) {
    return '전‍체 $total‍건 중 $index‍번‍째 거‍래‍의 전‍송 결‍과‍를 알 수 없‍어‍요: $detail';
  }

  @override
  String get capsLockWarning => 'Caps Lock‍이 켜‍져 있‍어‍요';

  @override
  String carouselPageSemantics(
    String name,
    int page,
    int count,
    String message,
  ) {
    return '$name $count‍개 중 $page‍번‍째. $message';
  }

  @override
  String carouselShowPage(String name, int page, int count) {
    return '$name $count‍개 중 $page‍번‍째 보‍기';
  }

  @override
  String get commonActionNeeded => '확‍인 필‍요';

  @override
  String get commonAddAMessage => '메‍시‍지 추‍가';

  @override
  String get commonAddAccount => '계‍정 추‍가';

  @override
  String get commonAddressCopied => '주‍소‍를 복‍사‍했‍어‍요';

  @override
  String commonAddressForChain(String chain) {
    return '$chain 주‍소';
  }

  @override
  String get commonAddressLabel => '주‍소 라‍벨';

  @override
  String get commonAmount => '금‍액';

  @override
  String get commonBack => '뒤‍로';

  @override
  String commonBackTo(String destination) {
    return '$destination 화‍면‍으‍로 돌‍아‍가‍기';
  }

  @override
  String get commonBackToWallet => '지‍갑‍으‍로 돌‍아‍가‍기';

  @override
  String get commonCalculatingEllipsis => '계‍산‍하‍는 중…';

  @override
  String get commonCalculatingTotal => '총‍계 계‍산 중';

  @override
  String get commonCamera => '카‍메‍라';

  @override
  String get commonCameraDeniedTitle => '카‍메‍라 접‍근‍을 거‍부‍했‍어‍요';

  @override
  String get commonCameraRequestAgainHint =>
      '다‍시 요‍청‍하‍거‍나\n시‍스‍템 설‍정‍에‍서 직‍접 켜 주‍세‍요.';

  @override
  String get commonCameraRestrictedBody =>
      '스‍크‍린 타‍임 또‍는 기‍기 관‍리‍가\n카‍메‍라‍를 차‍단‍하‍고 있‍어‍요.';

  @override
  String get commonCameraRestrictedTitle => '카‍메‍라 접‍근‍이 제‍한‍되‍어 있‍어‍요';

  @override
  String get commonCameraUnavailable => '카‍메‍라‍를 사‍용‍할 수 없‍어‍요';

  @override
  String get commonCameraUnavailableNow => '지‍금‍은 카‍메‍라‍를 사‍용‍할 수 없‍어‍요.';

  @override
  String get commonCancel => '취‍소';

  @override
  String get commonCancelFailedRetry => '취‍소‍를 마‍치‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get commonCancelShielding => '차‍폐 취‍소';

  @override
  String get commonCancellationFailed =>
      '취‍소‍를 마‍치‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get commonCancelling => '취‍소‍하‍는 중…';

  @override
  String get commonCannotBeUndone => '이 작‍업‍은 되‍돌‍릴 수 없‍어‍요.';

  @override
  String get commonCards => '카‍드';

  @override
  String get commonChainAndAddress => '체‍인 및 주‍소';

  @override
  String get commonChangeContactPicture => '연‍락‍처 사‍진 변‍경';

  @override
  String get commonCheckAgain => '다‍시 확‍인';

  @override
  String get commonChecking => '확‍인 중...';

  @override
  String get commonCheckingEllipsis => '확‍인‍하‍는 중…';

  @override
  String get commonCheckingStatus => '상‍태‍를 확‍인‍하‍는 중';

  @override
  String get commonCheckingYourLedger => 'Ledger‍를 확‍인‍하‍는 중';

  @override
  String get commonClear => '지‍우‍기';

  @override
  String get commonClearContactLabel => '연‍락‍처 라‍벨 지‍우‍기';

  @override
  String get commonClearText => '텍‍스‍트 지‍우‍기';

  @override
  String get commonClose => '닫‍기';

  @override
  String get commonCloseMessage => '메‍시‍지 닫‍기';

  @override
  String get commonCoinholderVoting => '코‍인 보‍유‍자 투‍표';

  @override
  String get commonCompleted => '완‍료';

  @override
  String get commonConfirmOpeningZcash => 'Zcash 열‍기‍를 확‍인‍해 주‍세‍요';

  @override
  String get commonConfirmWithKeystone => 'Keystone‍으‍로 확‍인';

  @override
  String get commonConfirming => '확‍인 중';

  @override
  String get commonConnectLedger => 'Ledger 연‍결';

  @override
  String get commonConnecting => '연‍결‍하‍는 중…';

  @override
  String get commonContactLabelHint => '1~20‍자‍의 라‍벨‍을 입‍력‍하‍세‍요';

  @override
  String get commonContacts => '연‍락‍처';

  @override
  String get commonContinue => '계‍속';

  @override
  String get commonContinueAnyway => '그‍래‍도 계‍속';

  @override
  String get commonContinueToReview => '검‍토‍로 이‍동';

  @override
  String get commonCopied => '복‍사‍했‍어‍요';

  @override
  String get commonCopy => '복‍사';

  @override
  String get commonCopyAddress => '주‍소 복‍사';

  @override
  String get commonCopyLink => '링‍크 복‍사';

  @override
  String get commonCopyShieldedAddress => '차‍폐 주‍소 복‍사';

  @override
  String get commonCouldnTCloseTheCardTry =>
      '카‍드‍를 닫‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get commonCreated => '생‍성‍됨';

  @override
  String get commonCreating => '생‍성 중…';

  @override
  String get commonCustomiseAccount => '계‍정 꾸‍미‍기';

  @override
  String get commonCustomiseWallet => '지‍갑 꾸‍미‍기';

  @override
  String get commonDefault => '기‍본';

  @override
  String get commonDefaultCamera => '기‍본 카‍메‍라';

  @override
  String commonDetails(String details) {
    return '세‍부 정‍보: $details';
  }

  @override
  String get commonDismissNotification => '알‍림 닫‍기';

  @override
  String get commonDone => '완‍료';

  @override
  String get commonDownload => '다‍운‍로‍드';

  @override
  String get commonDurationOneHour => '1‍시‍간';

  @override
  String get commonDurationOneMinute => '1‍분';

  @override
  String get commonEdit => '수‍정';

  @override
  String get commonEnableWindowsCameraAccess => 'Windows 카‍메‍라 접‍근‍을 켜 주‍세‍요';

  @override
  String get commonEnterAmount => '금‍액‍을 입‍력‍하‍세‍요';

  @override
  String commonEnterAmountIn(String currency) {
    return '$currency‍로 금‍액 입‍력';
  }

  @override
  String get commonEnterAmountInUsd => 'USD 단‍위‍로 금‍액 입‍력';

  @override
  String get commonErrorDetailsHint =>
      '번‍역‍되‍지 않‍은 원‍래 오‍류 문‍구‍예‍요. 문‍제‍가 계‍속‍되‍면 복‍사‍해‍서 고‍객 지‍원‍에 보‍내 주‍세‍요.';

  @override
  String get commonErrorDetailsTitle => '오‍류 세‍부 정‍보';

  @override
  String get commonFailed => '실‍패';

  @override
  String get commonFeatureInProgress => '아‍직 준‍비 중‍인 기‍능‍이‍에‍요.';

  @override
  String get commonFullAddress => '전‍체 주‍소';

  @override
  String get commonGetSignature => '서‍명 가‍져‍오‍기';

  @override
  String get commonGoBack => '돌‍아‍가‍기';

  @override
  String get commonGoHome => '홈‍으‍로';

  @override
  String get commonGuaranteedMinimum => '최‍소 보‍장 수‍량';

  @override
  String get commonImporting => '가‍져‍오‍는 중...';

  @override
  String get commonInProgress => '진‍행 중';

  @override
  String get commonInformation => '안‍내';

  @override
  String get commonJustNow => '방‍금';

  @override
  String get commonKeepQrSteady => 'QR 코‍드‍가 흔‍들‍리‍지 않‍고 전‍부 보‍이‍게 해 주‍세‍요.';

  @override
  String get commonKeepScreenAwake => '화‍면 켜 두‍기';

  @override
  String get commonKeepVizorOpenWhileTheTransaction =>
      '거‍래‍를 전‍송‍하‍는 동‍안 Vizor‍를 열‍어 두‍세‍요.';

  @override
  String get commonKeystoneAfterScan => '스‍캔‍한 뒤 서‍명 가‍져‍오‍기‍를 누‍르‍세‍요.';

  @override
  String commonKeystoneScanPrompt(String icon) {
    return 'Keystone‍에‍서 $icon 버‍튼‍을 누‍른 뒤\n이 QR 코‍드‍를 스‍캔‍하‍세‍요';
  }

  @override
  String get commonKeystoneScanSignatureResult =>
      'Keystone‍에‍서 서‍명 결‍과 QR‍을 연 다‍음 다‍시 스‍캔‍하‍세‍요.';

  @override
  String get commonKeystoneScanTransaction =>
      'Keystone 지‍갑‍으‍로 이 거‍래 QR 코‍드‍를 스‍캔‍하‍세‍요. 기‍기‍의 안‍내‍를 따‍르‍세‍요.';

  @override
  String get commonKeystoneSignatureCouldNotBeApplied =>
      'Keystone 서‍명‍을 적‍용‍하‍지 못‍했‍어‍요.';

  @override
  String get commonKeystoneSigningCouldNotBePrepared =>
      'Keystone 서‍명‍을 준‍비‍하‍지 못‍했‍어‍요.';

  @override
  String get commonKnight => '기‍사';

  @override
  String get commonLedgerNeedsAttention => 'Ledger 확‍인‍이 필‍요‍해‍요';

  @override
  String get commonLedgerSigningCouldNotBeCompleted =>
      'Ledger 서‍명‍을 완‍료‍하‍지 못‍했‍어‍요. 기‍기‍를 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get commonLedgerSigningFailed => 'Ledger 서‍명‍에 실‍패‍했‍어‍요';

  @override
  String get commonLoading => '불‍러‍오‍는 중';

  @override
  String get commonLoadingActivity => '활‍동‍을 불‍러‍오‍는 중';

  @override
  String get commonLoadingCamera => '카‍메‍라 불‍러‍오‍는 중...';

  @override
  String get commonLoadingDots => '불‍러‍오‍는 중...';

  @override
  String get commonLoadingQRCode => 'QR 코‍드‍를 불‍러‍오‍는 중...';

  @override
  String get commonMakeSureTheRoomIsWell =>
      '방‍이 충‍분‍히 밝‍고 QR 코‍드‍에 빛‍이 반‍사‍되‍지 않‍는‍지 확‍인‍해 주‍세‍요.';

  @override
  String get commonManage => '관‍리';

  @override
  String get commonMemo => '메‍모';

  @override
  String get commonMessage => '메‍시‍지';

  @override
  String get commonMessageIsTooLong => '메‍시‍지‍가 너‍무 길‍어‍요';

  @override
  String get commonMigrateToIronwood => 'Ironwood‍로 마‍이‍그‍레‍이‍션‍하‍기';

  @override
  String get commonMigrating => '마‍이‍그‍레‍이‍션 중...';

  @override
  String get commonMigrationStopped => '마‍이‍그‍레‍이‍션 중‍단‍됨';

  @override
  String get commonMigrationStoppedByNetworkUpgrade =>
      '네‍트‍워‍크 업‍그‍레‍이‍드‍로 마‍이‍그‍레‍이‍션‍이 중‍단‍됐‍어‍요';

  @override
  String get commonMoveTheQRCodeAFew =>
      '카‍메‍라‍가 초‍점‍을 맞‍출 수 있‍도‍록 QR 코‍드‍를 카‍메‍라‍에‍서 조‍금 더 멀‍리 떨‍어‍뜨‍려 보‍세‍요.';

  @override
  String get commonNetworkConversionFees => '네‍트‍워‍크 + 변‍환 수‍수‍료';

  @override
  String get commonNetworkFee => '네‍트‍워‍크 수‍수‍료';

  @override
  String get commonNextStep => '다‍음 단‍계';

  @override
  String get commonNoActiveAccount => '선‍택‍된 계‍정‍이 없‍어‍요';

  @override
  String get commonNoActiveAccountSentence => '선‍택‍된 계‍정‍이 없‍어‍요.';

  @override
  String get commonNoCameraCouldBeOpenedCheck =>
      '카‍메‍라‍를 열 수 없‍어‍요. 카‍메‍라‍가 연‍결‍되‍어 있‍고 다‍른 앱‍에‍서 사‍용 중‍이 아‍닌‍지 확‍인‍해 주‍세‍요.';

  @override
  String get commonNoCameraFound => '카‍메‍라‍를 찾‍지 못‍했‍어‍요';

  @override
  String get commonNotAvailableYet => '아‍직 사‍용‍할 수 없‍어‍요';

  @override
  String get commonNotEnoughZec => 'ZEC‍가 부‍족‍해‍요';

  @override
  String get commonOk => '확‍인';

  @override
  String get commonOnAMacYouCanUse =>
      'Mac‍에‍서‍는 연‍속‍성 카‍메‍라‍를 사‍용‍해 iPhone‍으‍로 대‍신 스‍캔‍할 수 있‍어‍요.';

  @override
  String get commonOpenSettings => '설‍정 열‍기';

  @override
  String get commonOpenTheSignedTransactionQROn =>
      'Keystone‍에‍서 서‍명‍된 거‍래 QR‍을 연 다‍음 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String get commonPausedForNetworkUpgrade => '네‍트‍워‍크 업‍그‍레‍이‍드‍로 일‍시 중‍지‍됨';

  @override
  String get commonPayInsufficientZec =>
      '이 결‍제‍에 필‍요‍한 ZEC‍가 부‍족‍해‍요. 더 적‍은 금‍액‍으‍로 시‍도‍해 보‍세‍요.';

  @override
  String get commonPayingButton => '결‍제 중';

  @override
  String get commonPaymentFailed => '결‍제‍에 실‍패‍했‍어‍요';

  @override
  String get commonPaymentInProgress => '결‍제 진‍행 중';

  @override
  String get commonPaymentProgress => '결‍제 진‍행 상‍황';

  @override
  String get commonPaymentRefunded => '결‍제 환‍불‍됨';

  @override
  String get commonPaymentRequest => '결‍제 요‍청';

  @override
  String get commonPending => '대‍기 중';

  @override
  String get commonPleaseWait => '기‍다‍리‍는 중';

  @override
  String get commonPrepareYourKeystoneWallet => 'Keystone 지‍갑‍을 준‍비‍해 주‍세‍요';

  @override
  String get commonPreparing => '준‍비 중';

  @override
  String get commonPreparingDots => '준‍비 중...';

  @override
  String get commonPreparingEllipsis => '준‍비 중…';

  @override
  String get commonPrivatelyFromShieldedBalance => '차‍폐‍된 잔‍액‍에‍서 비‍공‍개‍로';

  @override
  String get commonProvingParamsFailed =>
      '필‍요‍한 증‍명 매‍개‍변‍수‍를 준‍비‍하‍지 못‍했‍어‍요.';

  @override
  String get commonQrNoAddress => 'QR 코‍드‍에 주‍소‍가 없‍어‍요.';

  @override
  String get commonQuit => '종‍료';

  @override
  String get commonRate => '환‍율';

  @override
  String get commonReadingSignature => '서‍명‍을 읽‍는 중...';

  @override
  String get commonReadingSignatureEllipsis => '서‍명‍을 읽‍는 중…';

  @override
  String get commonReceived => '받‍음';

  @override
  String get commonRecipientGets => '받‍는 사‍람 수‍령 예‍정‍액';

  @override
  String get commonRefundFee => '환‍불 수‍수‍료';

  @override
  String get commonRefundTo => '환‍불 주‍소';

  @override
  String commonRefundToAddress(String address) {
    return '환‍불 주‍소: $address';
  }

  @override
  String get commonRefunded => '환‍불‍됨';

  @override
  String get commonRefundedAmount => '환‍불 금‍액';

  @override
  String get commonRemove => '삭‍제';

  @override
  String get commonRequestAgain => '다‍시 요‍청';

  @override
  String get commonResetVizor => 'Vizor 초‍기‍화';

  @override
  String get commonResults => '결‍과';

  @override
  String get commonResume => '재‍개';

  @override
  String get commonRetry => '다‍시 시‍도';

  @override
  String get commonRetrySaving => '저‍장 다‍시 시‍도';

  @override
  String get commonReturnHome => '홈‍으‍로 돌‍아‍가‍기';

  @override
  String get commonReviewAndFinish => '검‍토‍하‍고 완‍료';

  @override
  String get commonReviewPayment => '결‍제 검‍토';

  @override
  String get commonReviewQuote => '견‍적 검‍토';

  @override
  String get commonReviewSwap => '스‍왑 검‍토';

  @override
  String get commonSave => '저‍장';

  @override
  String get commonSaveContact => '연‍락‍처 저‍장';

  @override
  String get commonSaving => '저‍장 중';

  @override
  String get commonScanAgain => '다‍시 스‍캔';

  @override
  String get commonScanOriginalQr => '원‍래 QR 스‍캔';

  @override
  String get commonScanQrCode => 'QR 코‍드 스‍캔';

  @override
  String get commonScanQrCodeSentenceCase => 'QR 코‍드 스‍캔';

  @override
  String get commonScanToSign => '스‍캔‍해‍서 서‍명';

  @override
  String get commonScanWithKeystone => 'Keystone‍으‍로 스‍캔';

  @override
  String get commonScanWithYourKeystone => 'Keystone‍으‍로 스‍캔‍하‍세‍요';

  @override
  String get commonSelectAccount => '계‍정 선‍택';

  @override
  String get commonSelectContactPicture => '연‍락‍처 사‍진 선‍택';

  @override
  String get commonSelectRecipient => '받‍는 사‍람 선‍택';

  @override
  String get commonSelectedContact => '선‍택‍된 연‍락‍처';

  @override
  String get commonSendFailed => '보‍내‍기 실‍패';

  @override
  String get commonSendZec => 'ZEC 보‍내‍기';

  @override
  String get commonSending => '보‍내‍는 중...';

  @override
  String get commonSensitiveContentHidden => '민‍감‍한 내‍용‍을 가‍렸‍어‍요';

  @override
  String get commonSentSuccessfully => '보‍냈‍어‍요';

  @override
  String get commonShieldedAddress => '차‍폐 주‍소';

  @override
  String get commonShieldedBalance => '차‍폐 잔‍액';

  @override
  String get commonShieldedSuccessfully => '차‍폐‍했‍어‍요';

  @override
  String get commonShielding => '차‍폐‍하‍는 중...';

  @override
  String get commonShowDetails => '자‍세‍히 보‍기';

  @override
  String get commonShowFullAddress => '전‍체 주‍소 보‍기';

  @override
  String get commonShowTransactionQR => '거‍래 QR 보‍기';

  @override
  String get commonSigningCancelledBeforeParams =>
      '증‍명 매‍개‍변‍수‍를 내‍려‍받‍기 전‍에 서‍명‍이 취‍소‍됐‍어‍요.';

  @override
  String get commonSigningExpired => '거‍래‍가 서‍명‍되‍기 전‍에 만‍료‍됐‍어‍요.';

  @override
  String get commonSlippageTolerance => '슬‍리‍피‍지 허‍용‍치';

  @override
  String get commonStepOneOfTwo => '1/2‍단‍계';

  @override
  String get commonStepTwoOfTwo => '2/2‍단‍계';

  @override
  String get commonSubmittingTransaction => '거‍래‍를 제‍출‍하‍는 중';

  @override
  String get commonSupportVizor => 'Vizor 후‍원‍하‍기';

  @override
  String get commonSwapFailed => '스‍왑 실‍패';

  @override
  String get commonSwapFee => '스‍왑 수‍수‍료';

  @override
  String get commonSwapProgress => '스‍왑 진‍행 상‍황';

  @override
  String get commonSwapRefunded => '스‍왑 환‍불‍됨';

  @override
  String commonSymbolRecipient(String symbol) {
    return '$symbol 받‍는 사‍람';
  }

  @override
  String commonSymbolRefundAddress(String symbol) {
    return '$symbol 환‍불 주‍소';
  }

  @override
  String get commonSyncing => '동‍기‍화 중';

  @override
  String get commonThisQRCodeCouldNotBe =>
      '이 QR 코‍드‍를 Keystone 서‍명‍으‍로 읽‍을 수 없‍어‍요.';

  @override
  String get commonThisQRCodeDoesNotMatch =>
      '이 QR 코‍드‍는 현‍재 Keystone 요‍청‍과 일‍치‍하‍지 않‍아‍요.';

  @override
  String get commonTimeSUp => '시‍간‍이 지‍났‍어‍요';

  @override
  String get commonTimestamp => '일‍시';

  @override
  String get commonTo => '받‍는 사‍람';

  @override
  String commonToAddressOnChain(String address, String chain) {
    return '받‍는 곳: $address ($chain)';
  }

  @override
  String get commonToggleFlashlight => '손‍전‍등 켜‍기/끄‍기';

  @override
  String get commonTotal => '합‍계';

  @override
  String get commonTransactionExpired => '거‍래‍가 만‍료‍됐‍어‍요';

  @override
  String get commonTransactionHashCopied => '거‍래 해‍시‍를 복‍사‍했‍어‍요';

  @override
  String get commonTransparentAddress => '투‍명 주‍소';

  @override
  String get commonTryAgain => '다‍시 시‍도';

  @override
  String get commonTurnOnCameraAccessAndLet =>
      'Windows 설‍정‍에‍서 \'카‍메‍라 액‍세‍스\'와 \'데‍스‍크‍톱 앱‍에‍서 카‍메‍라‍에 액‍세‍스‍하‍도‍록 허‍용\'을 켜 주‍세‍요.';

  @override
  String get commonTxId => '거‍래 ID';

  @override
  String get commonUnknown => '알 수 없‍음';

  @override
  String get commonUnlockVizor => 'Vizor 잠‍금 해‍제';

  @override
  String get commonUpdate => '변‍경';

  @override
  String get commonUpdateFailed => '업‍데‍이‍트 실‍패';

  @override
  String get commonUpdating => '변‍경 중...';

  @override
  String get commonView => '보‍기';

  @override
  String get commonVizorIsCheckingWhetherTheZcash =>
      'Vizor‍가 Zcash 앱‍이 준‍비‍됐‍는‍지 확‍인‍하‍고 있‍어‍요.';

  @override
  String get commonVotingRound => '투‍표 회‍차';

  @override
  String get commonWaitingForConfirmation => '확‍인‍을 기‍다‍리‍는 중...';

  @override
  String get commonWaitingForWalletSync => '지‍갑 동‍기‍화 대‍기 중';

  @override
  String get commonWelcomeBack => '다‍시 오‍셨‍네‍요';

  @override
  String get commonWizard => '마‍법‍사';

  @override
  String get commonYouPay => '내‍가 보‍내‍는 금‍액';

  @override
  String get commonYourePaying => '지‍불‍하‍는 금‍액';

  @override
  String get commonYoureReceiving => '받‍는 금‍액';

  @override
  String get commonZcashAddress => 'Zcash 주‍소';

  @override
  String get donationDonatingTo => '후‍원 대‍상';

  @override
  String get donationEnterAmount => '금‍액‍을 입‍력‍하‍세‍요';

  @override
  String get donationPriceUnavailable => '가‍격‍을 불‍러‍올 수 없‍어‍요';

  @override
  String get donationReviewAmountTitle => '금‍액 확‍인';

  @override
  String get donationSendingFrom => '보‍내‍는 곳';

  @override
  String get donationSendingFromYour => '보‍내‍는 곳:';

  @override
  String get donationSwitchCurrency => 'ZEC‍와 USD 전‍환';

  @override
  String get donationThanksTitle => 'Vizor‍를 후‍원‍해 주‍셔‍서 감‍사‍해‍요';

  @override
  String get endpointAutomatic => '자‍동';

  @override
  String get endpointAutomaticSelecting => '자‍동 · 선‍택‍하‍는 중...';

  @override
  String endpointAutomaticWithHost(String endpoint) {
    return '자‍동 · $endpoint';
  }

  @override
  String endpointCurrent(String endpoint) {
    return '현‍재: $endpoint';
  }

  @override
  String get endpointCustom => '사‍용‍자 지‍정 엔‍드‍포‍인‍트';

  @override
  String get endpointErrorAutomaticUnavailable => '자‍동 선‍택‍을 사‍용‍할 수 없‍어‍요.';

  @override
  String get endpointErrorEmpty => '엔‍드‍포‍인‍트‍를 입‍력‍하‍세‍요.';

  @override
  String get endpointErrorHost => '올‍바‍른 호‍스‍트 이‍름‍과 포‍트‍를 입‍력‍하‍세‍요.';

  @override
  String get endpointErrorHttps => 'https:// 엔‍드‍포‍인‍트‍를 사‍용‍하‍세‍요.';

  @override
  String get endpointErrorNoSelection => '엔‍드‍포‍인‍트‍를 선‍택‍하‍세‍요.';

  @override
  String get endpointErrorPort =>
      '올‍바‍른 포‍트‍를 넣‍어 주‍세‍요. 예: us.zec.stardust.rest:443';

  @override
  String get endpointErrorSpaces => '엔‍드‍포‍인‍트‍에‍는 공‍백‍을 넣‍을 수 없‍어‍요.';

  @override
  String endpointErrorWrongNetwork(
    String endpointNetwork,
    String walletNetwork,
  ) {
    return '이 엔‍드‍포‍인‍트‍는 $endpointNetwork 네‍트‍워‍크‍용‍이‍지‍만, 이 지‍갑‍은 $walletNetwork 네‍트‍워‍크‍를 사‍용‍해‍요.';
  }

  @override
  String get endpointFailoverSwitchedBack =>
      '선‍택‍한 엔‍드‍포‍인‍트‍가 복‍구‍되‍어 다‍시 전‍환‍했‍어‍요.';

  @override
  String get endpointFailoverSwitchedToFallback =>
      '선‍택‍한 엔‍드‍포‍인‍트‍가 불‍안‍정‍해‍서 대‍체 엔‍드‍포‍인‍트‍로 전‍환‍했‍어‍요.';

  @override
  String get endpointLatencyUnavailable => '사‍용 불‍가';

  @override
  String get endpointLatencyWrongNetwork => '다‍른 네‍트‍워‍크';

  @override
  String endpointRegionName(String region) {
    String _temp0 = intl.Intl.selectLogic(region, {
      'standard': '기‍본',
      'europe': '유‍럽',
      'global': '글‍로‍벌',
      'americas': '아‍메‍리‍카',
      'asiaPacific': '아‍시‍아 태‍평‍양',
      'community': '커‍뮤‍니‍티',
      'testnet': '테‍스‍트‍넷',
      'regtest': 'Regtest',
      'other': '기‍타',
    });
    return '$_temp0';
  }

  @override
  String get endpointSaveFailed =>
      '엔‍드‍포‍인‍트‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get endpointSelecting => '엔‍드‍포‍인‍트‍를 선‍택‍하‍는 중…';

  @override
  String get endpointUpdate => '엔‍드‍포‍인‍트 업‍데‍이‍트';

  @override
  String get endpointUpdated => '엔‍드‍포‍인‍트‍를 업‍데‍이‍트‍했‍어‍요';

  @override
  String get endpointUseAutomatic => '자‍동 선‍택 사‍용';

  @override
  String get enhancePirChanging => '설‍정 변‍경 중…';

  @override
  String get enhancePirOptOutPending =>
      '비‍공‍개 조‍회‍가 아‍직 켜‍져 있‍어‍요. 다‍시 꺼 보‍세‍요.';

  @override
  String get enhancePirRaisePending =>
      '비‍공‍개 조‍회‍가 켜‍졌‍어‍요. 투‍명 자‍금‍의 비‍공‍개 복‍구‍를 아‍직 시‍작‍하‍지 못‍했‍고, 다‍시 시‍도‍할 거‍예‍요.';

  @override
  String get enhancePirUnchanged => '설‍정‍이 바‍뀌‍지 않‍았‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get homeActivityEmpty => '아‍직 활‍동‍이 없‍어‍요...';

  @override
  String get homeActivityEmptyHint => '첫 ZEC 거‍래‍를 보‍내 볼‍까‍요?';

  @override
  String get homeActivityEmptyHintMobile => '첫 ZEC 거‍래‍를\n보‍내 볼‍까‍요?';

  @override
  String get homeActivityUnavailable => '활‍동‍을 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get homeBackupSubtitle => '복‍구 문‍구‍를 백‍업‍하‍세‍요\n마‍지‍막 단‍계';

  @override
  String get homeBackupTitle => '지‍갑 보‍호‍하‍기';

  @override
  String get homeDismiss => '닫‍기';

  @override
  String get homeEducationSubtitle => '프‍라‍이‍버‍시, 주‍소 유‍형, 앞‍으‍로 알‍아‍둘 점';

  @override
  String get homeEducationTitle => 'Zcash 알‍아‍보‍기';

  @override
  String get homeImportingBodyMobile =>
      '잠‍시‍만 기‍다‍려 주‍세‍요... 시‍간‍이 걸‍릴 수 있‍어‍요. Vizor‍를 열‍어 둔 채‍로 실‍행‍해 주‍세‍요.';

  @override
  String get homeImportingDetail =>
      '시‍간‍이 걸‍릴 수 있‍어‍요.\nVizor‍를 열‍어 둔 채‍로 실‍행‍해 주‍세‍요.';

  @override
  String homeImportingDetailNamed(String name) {
    return '$name 가‍져‍오‍는 중\nVizor‍를 열‍어 둔 채‍로 실‍행‍해 주‍세‍요.';
  }

  @override
  String get homeImportingTitle => '지‍갑‍을\n가‍져‍오‍는 중‍이‍에‍요...';

  @override
  String get homeImportingTitleMobile => '지‍갑‍을 가‍져‍오‍는 중‍이‍에‍요...';

  @override
  String get homeKeepAwakeBody =>
      '화‍면‍이 꺼‍지‍면 휴‍대‍폰‍이 동‍기‍화‍를 멈‍춰‍요. 화‍면‍을 켜 두‍면 동‍기‍화‍가 더 빨‍리 끝‍나‍요.';

  @override
  String get homeKeepAwakeLater => '나‍중‍에';

  @override
  String get homeKeepAwakeLockNote =>
      '1‍분 동‍안 사‍용‍하‍지 않‍으‍면 앱‍이 잠‍겨‍요. 잠‍긴 상‍태‍에‍서‍도 동‍기‍화‍는 계‍속‍돼‍요.';

  @override
  String get homeKeepAwakeSettingsNote => '설‍정‍에‍서 언‍제‍든 바‍꿀 수 있‍어‍요.';

  @override
  String get homeKeepAwakeTitle => '동‍기‍화 중 화‍면‍을 켜 둘‍까‍요?';

  @override
  String get homeLedgerApprovalNotAccepted =>
      'Ledger‍가 이 승‍인‍을 받‍아‍들‍이‍지 못‍했‍어‍요. 이‍전 승‍인‍은 이‍미 전‍송‍됐‍어‍요.';

  @override
  String get homeLedgerBroadcastNotStored =>
      '차‍폐 거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍지‍만 기‍기‍에 저‍장‍되‍지 않‍았‍어‍요. 동‍기‍화‍로 확‍인‍되‍기 전‍에‍는 다‍시 시‍도‍하‍지 마‍세‍요.';

  @override
  String get homeLedgerBroadcastUnknown =>
      '차‍폐 거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍을 수 있‍어‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get homeLedgerContextChanged =>
      '선‍택‍한 계‍정‍이‍나 네‍트‍워‍크‍가 바‍뀌‍었‍어‍요. 지‍갑‍으‍로 돌‍아‍가 주‍세‍요.';

  @override
  String get homeLedgerInputsRemaining => '남‍은 입‍력 있‍음';

  @override
  String get homeLedgerNoFundsRemain =>
      '사‍용‍할 수 있‍는 투‍명 자‍금‍이 남‍아 있‍지 않‍아‍요. 지‍갑‍으‍로 돌‍아‍가 주‍세‍요.';

  @override
  String get homeLedgerNoSapling =>
      '이 Ledger 미‍리‍보‍기‍는 Sapling 입‍력‍이‍나 출‍력‍을 지‍원‍하‍지 않‍아‍요.';

  @override
  String get homeLedgerPausedBelowThreshold =>
      '남‍은 자‍금‍이 차‍폐 최‍소 금‍액‍보‍다 적‍어‍요.';

  @override
  String get homeLedgerPausedTitle => '차‍폐‍가 일‍시 중‍지‍됐‍어‍요';

  @override
  String get homeLedgerPausedWalletChanges =>
      '지‍갑 변‍경‍이 끝‍나‍는 동‍안 차‍폐‍를 일‍시 중‍지‍했‍어‍요. 지‍갑‍으‍로 돌‍아‍가 주‍세‍요.';

  @override
  String get homeLedgerRejected => 'Ledger‍에‍서 차‍폐 거‍래‍를 거‍부‍했‍어‍요.';

  @override
  String get homeLedgerRoundFeeNotice =>
      '승‍인‍할 때‍마‍다 별‍도‍의 거‍래‍가 만‍들‍어‍지‍고 각‍각 네‍트‍워‍크 수‍수‍료‍가 들‍어‍요.';

  @override
  String homeLedgerRoundSentBelowThreshold(int round) {
    return '$round‍번‍째 단‍계‍를 전‍송‍했‍어‍요. 남‍은 자‍금‍이 차‍폐 최‍소 금‍액‍보‍다 적‍어‍요.';
  }

  @override
  String homeLedgerRoundSentNoReduction(int round) {
    return '$round‍번‍째 단‍계‍는 전‍송‍했‍지‍만 사‍용 가‍능‍한 입‍력‍이 줄‍었‍는‍지 확‍인‍하‍지 못‍했‍어‍요. 동‍기‍화‍를 기‍다‍린 뒤 다‍시 차‍폐‍해 주‍세‍요.';
  }

  @override
  String homeLedgerRoundSentUnchecked(int round) {
    return '$round‍번‍째 단‍계‍는 전‍송‍했‍지‍만 남‍은 자‍금‍을 확‍인‍하‍지 못‍했‍어‍요. 지‍갑‍으‍로 돌‍아‍가 동‍기‍화‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';
  }

  @override
  String get homeLedgerShieldTitle => 'Ledger‍로 차‍폐‍하‍기';

  @override
  String get homeLedgerShieldingFailed => 'Ledger‍로 차‍폐‍를 완‍료‍하‍지 못‍했‍어‍요.';

  @override
  String homeLoadFailed(String details) {
    return '문‍제‍가 생‍겼‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.\n\n자‍세‍한 내‍용: $details';
  }

  @override
  String get homeMigrationRequired => '마‍이‍그‍레‍이‍션 필‍요';

  @override
  String get homeMigrationRequiredTitle => '마‍이‍그‍레‍이‍션 필‍요';

  @override
  String homeMigrationStillMigrating(String amount) {
    return '$amount 마‍이‍그‍레‍이‍션 중';
  }

  @override
  String get homeNu7FasterBody =>
      '첫 확‍인‍까‍지 평‍균 대‍기 시‍간‍이 약 75‍초‍에‍서 약 25‍초‍로 줄‍어‍요.';

  @override
  String get homeNu7FasterTitle => '블‍록‍이 약 3‍배 빨‍라‍져‍요';

  @override
  String get homeNu7GotIt => '확‍인';

  @override
  String get homeNu7ThroughputBody =>
      '블‍록‍당 처‍리‍할 수 있‍는 차‍폐 거‍래‍가 2.3‍배 늘‍어‍요.';

  @override
  String get homeNu7ThroughputTitle => '차‍폐 거‍래 처‍리‍량 증‍가';

  @override
  String get homeNu7Title => 'NU7 업‍데‍이‍트‍가 적‍용‍됐‍어‍요.\n무‍엇‍이 달‍라‍질‍까‍요?';

  @override
  String get homePasswordChangeUnverified =>
      '이‍전 비‍밀‍번‍호 변‍경‍을 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 Vizor‍를 다‍시 시‍작‍해 주‍세‍요.';

  @override
  String get homePayInUsdc => 'USDC‍로 결‍제';

  @override
  String get homeReceive => '받‍기';

  @override
  String get homeReceiveFirstZec => '첫 ZEC 받‍기';

  @override
  String get homeRecentActivity => '최‍근 활‍동';

  @override
  String get homeSeeAll => '전‍체 보‍기';

  @override
  String get homeSend => '보‍내‍기';

  @override
  String get homeSetupBackupMessage =>
      '지‍갑‍을 백‍업‍하‍세‍요. 복‍구 문‍구‍를 안‍전‍하‍게 보‍관‍해 주‍세‍요.';

  @override
  String get homeSetupCarouselLabel => '지‍갑 설‍정';

  @override
  String get homeSetupCarouselName => '지‍갑 설‍정 배‍너';

  @override
  String get homeSetupEducationMessage =>
      'Zcash‍가 프‍라‍이‍버‍시‍를 어‍떻‍게 보‍호‍하‍는‍지, 어‍떤 주‍소‍를 써‍야 하‍는‍지 알‍아‍보‍세‍요.';

  @override
  String get homeShield => '차‍폐‍하‍기';

  @override
  String get homeShieldAfterScan => '스‍캔‍한 뒤 서‍명 가‍져‍오‍기‍를 누‍르‍세‍요.';

  @override
  String get homeShieldApproveTitle => 'Keystone‍에‍서 승‍인‍하‍기';

  @override
  String get homeShieldAttentionTitle => '차‍폐‍에 확‍인‍이 필‍요‍해‍요';

  @override
  String get homeShieldBackToWalletTitleCase => '지‍갑‍으‍로 돌‍아‍가‍기';

  @override
  String get homeShieldBalanceTitle => '투‍명 잔‍액';

  @override
  String get homeShieldBroadcastNotStored =>
      '차‍폐 거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍지‍만 Vizor‍가 기‍기‍에 저‍장‍하‍지 못‍했‍어‍요. 동‍기‍화‍나 블‍록 탐‍색‍기‍에‍서 최‍신 상‍태‍를 확‍인‍하‍기 전‍에‍는 다‍시 시‍도‍하‍지 마‍세‍요.';

  @override
  String get homeShieldBroadcastUnknown =>
      '차‍폐 거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍을 수 있‍지‍만 확‍인 시‍간‍이 초‍과‍됐‍어‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get homeShieldBroadcastingTitle => '차‍폐 거‍래 전‍송 중';

  @override
  String get homeShieldCameraDenied =>
      'Keystone 서‍명‍을 스‍캔‍하‍려‍면 설‍정‍에‍서 카‍메‍라 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get homeShieldCancelled => '차‍폐‍를 취‍소‍했‍어‍요.';

  @override
  String get homeShieldCancelledBeforeParams =>
      '증‍명 매‍개‍변‍수‍를 내‍려‍받‍기 전‍에 차‍폐‍가 취‍소‍됐‍어‍요.';

  @override
  String get homeShieldComplete => '완‍료';

  @override
  String get homeShieldDrag => '밀‍어‍서 차‍폐‍하‍기';

  @override
  String get homeShieldErrorBroadcast => '차‍폐 거‍래‍를 전‍송‍하‍지 못‍했‍어‍요.';

  @override
  String get homeShieldErrorBroadcastFailed =>
      '차‍폐 거‍래‍를 전‍송‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get homeShieldErrorCouldNotShield =>
      '잔‍액‍을 차‍폐‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get homeShieldErrorGeneric =>
      '잔‍액‍을 차‍폐‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get homeShieldErrorNotFinalized => '차‍폐 거‍래‍를 마‍무‍리‍하‍지 못‍했‍어‍요.';

  @override
  String get homeShieldErrorSeedUnavailable =>
      '이 계‍정‍의 복‍구 문‍구‍를 사‍용‍할 수 없‍어‍요.';

  @override
  String get homeShieldErrorSyncFirst =>
      '투‍명 잔‍액‍을 차‍폐‍하‍기 전‍에 지‍갑‍을 동‍기‍화‍해 주‍세‍요.';

  @override
  String get homeShieldErrorTooSmall =>
      '수‍수‍료‍를 내‍고 나‍면 차‍폐‍하‍기‍에‍는 투‍명 잔‍액‍이 너‍무 적‍어‍요.';

  @override
  String get homeShieldErrorWaitForSync => '동‍기‍화‍가 끝‍난 뒤 차‍폐‍해 주‍세‍요.';

  @override
  String get homeShieldFailedTitle => '차‍폐‍를 완‍료‍하‍지 못‍했‍어‍요';

  @override
  String get homeShieldGetSignature => '서‍명 가‍져‍오‍기';

  @override
  String get homeShieldKeystoneQrSemantics => 'Keystone 거‍래 QR';

  @override
  String get homeShieldNow => '지‍금 차‍폐‍하‍기';

  @override
  String get homeShieldQueuedForRetry =>
      '차‍폐‍를 다‍시 시‍도‍하‍도‍록 대‍기‍열‍에 넣‍었‍어‍요. 활‍동‍에‍서 확‍인‍해 주‍세‍요.';

  @override
  String get homeShieldQueuedTitle => '차‍폐‍를 대‍기‍열‍에 추‍가‍했‍어‍요';

  @override
  String get homeShieldReject => '거‍부';

  @override
  String get homeShieldScanTitle => 'Keystone 서‍명 스‍캔‍하‍기';

  @override
  String get homeShieldScanToSign => 'QR 코‍드‍를 스‍캔‍해 서‍명‍하‍세‍요';

  @override
  String get homeShieldScanWrongQr =>
      'Keystone‍에‍서 서‍명‍된 차‍폐 QR‍을 열‍고 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String homeShieldScanning(int progress) {
    return '스‍캔‍하‍는 중… $progress%';
  }

  @override
  String get homeShieldShowQr => 'QR 보‍기';

  @override
  String get homeShieldSignTitle => 'Keystone‍에‍서 거‍래 서‍명‍하‍기';

  @override
  String get homeShieldStatusUncertain =>
      '차‍폐 거‍래‍의 상‍태‍가 불‍확‍실‍해‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get homeShieldWaitingForPrivateRecovery =>
      '비‍공‍개 복‍구‍가 최‍신 블‍록‍을 따‍라‍잡‍는 중‍이‍에‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요. Keystone 서‍명‍은 그‍대‍로 보‍관‍돼‍요.';

  @override
  String get homeShieldingBalance => '잔‍액‍을 차‍폐‍하‍는 중…';

  @override
  String homeTransparentBalance(String balance) {
    return '투‍명: $balance';
  }

  @override
  String homeTransparentLastKnown(String amount) {
    return '$amount (마‍지‍막 확‍인)';
  }

  @override
  String homeTransparentLastKnownStopped(String amount) {
    return '$amount (마‍지‍막 확‍인, 복‍구 중‍단‍됨)';
  }

  @override
  String get homeTransparentRecoveryStopped => '복‍구 중‍단‍됨';

  @override
  String get homeTransparentStopLegacyDiscrepancy =>
      '이‍전‍의 공‍개 기‍록‍이 비‍공‍개 복‍구 결‍과‍와 맞‍지 않‍아‍요. 비‍공‍개 조‍회‍를 끄‍면 비‍공‍개‍로 복‍구‍한 기‍록‍을 버‍리‍고 투‍명 자‍금‍을 공‍개‍적‍으‍로 조‍회‍해‍요.';

  @override
  String get homeTransparentStopOptOutUnfinished =>
      '비‍공‍개 조‍회 끄‍기‍가 완‍료‍되‍지 않‍았‍어‍요. 설‍정‍에‍서 다‍시 끄‍면 투‍명 자‍금‍을 공‍개‍적‍으‍로 조‍회‍해‍요.';

  @override
  String get homeTransparentStopQuarantined =>
      '비‍공‍개 복‍구‍에‍서 이 계‍정‍의 기‍록‍이 서‍로 맞‍지 않‍는 것‍을 발‍견‍했‍어‍요. 비‍공‍개 조‍회‍를 끄‍면 비‍공‍개‍로 복‍구‍한 기‍록‍을 버‍리‍고 투‍명 자‍금‍을 공‍개‍적‍으‍로 조‍회‍해‍요.';

  @override
  String get homeTransparentStopStalled =>
      '이 계‍정‍의 비‍공‍개 복‍구‍가 진‍행‍되‍지 않‍고 있‍어‍요. Vizor‍가 나‍중‍에 다‍시 시‍도‍해‍요.';

  @override
  String get homeTransparentStopWithdrawn =>
      '비‍공‍개 복‍구 서‍비‍스‍가 이 계‍정‍의 데‍이‍터‍를 철‍회‍했‍어‍요. Vizor‍가 나‍중‍에 다‍시 시‍도‍해‍요.';

  @override
  String get homeTransparentUnavailable => '확‍인‍할 수 없‍음';

  @override
  String get homeVotingSemantics => '코‍인 보‍유‍자 투‍표 열‍기';

  @override
  String get homeVotingSubtitle => '네‍트‍워‍크‍의 방‍향‍을 함‍께 정‍해‍요';

  @override
  String get incomingLinkGiftBusy =>
      '이 기‍프‍트 카‍드‍를 열‍려‍면 진‍행 중‍인 작‍업‍을 끝‍내‍거‍나 취‍소‍해 주‍세‍요.';

  @override
  String get incomingLinkGiftSetup =>
      '이 기‍프‍트 카‍드‍를 열‍려‍면 계‍정 설‍정‍을 마‍쳐 주‍세‍요.';

  @override
  String get incomingLinkHomeBusy =>
      '작‍업‍을 끝‍내‍거‍나 취‍소‍한 다‍음 링‍크‍를 다‍시 열‍어 주‍세‍요.';

  @override
  String get incomingLinkHomeSetup => '계‍정 설‍정‍을 마‍친 다‍음 링‍크‍를 다‍시 열‍어 주‍세‍요.';

  @override
  String get incomingLinkPaymentBusy =>
      '이 결‍제 요‍청‍을 열‍려‍면 진‍행 중‍인 작‍업‍을 끝‍내‍거‍나 취‍소‍해 주‍세‍요.';

  @override
  String get keyringLockedBody =>
      'Vizor‍가 시‍스‍템 키‍링‍에 접‍근‍할 수 없‍어‍요. 키‍링 잠‍금‍을 해‍제‍한 뒤 다‍시 시‍도‍를 선‍택‍하‍세‍요. 시‍스‍템‍에‍서 키‍링 비‍밀‍번‍호‍를 물‍어‍볼 수 있‍어‍요.';

  @override
  String get keyringNoResponse => '키‍링‍이 응‍답‍하‍지 않‍았‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get keyringOpeningTitle => 'Vizor 여‍는 중';

  @override
  String get keyringPromptBody =>
      'Vizor‍를 계‍속 사‍용‍하‍려‍면 시‍스‍템 키‍링 안‍내‍를 완‍료‍하‍세‍요.';

  @override
  String get keyringRestartHint => 'Vizor‍를 종‍료‍하‍고 다‍시 시‍작‍해 주‍세‍요.';

  @override
  String get keyringSaveUnconfirmedBody =>
      '변‍경 사‍항‍이 저‍장‍되‍었‍는‍지 Vizor‍가 확‍인‍하‍지 못‍했‍어‍요. 계‍속‍하‍기 전‍에 Vizor‍를 종‍료‍하‍고 다‍시 시‍작‍해 주‍세‍요.';

  @override
  String get keyringSaveUnconfirmedTitle => '저‍장‍을 확‍인‍할 수 없‍어‍요';

  @override
  String get keyringTryingTitle => '보‍안 저‍장‍소‍에 접‍근‍하‍는 중';

  @override
  String get keyringUnavailableBody =>
      'Vizor‍가 시‍스‍템 키‍링‍에 연‍결‍할 수 없‍어‍요. 다‍시 시‍도‍하‍거‍나 Vizor‍를 종‍료‍하‍고 다‍시 시‍작‍해 주‍세‍요.';

  @override
  String get keyringUnavailableTitle => '보‍안 저‍장‍소‍를 사‍용‍할 수 없‍어‍요';

  @override
  String get keyringUnlockTitle => '키‍링 잠‍금‍을 해‍제‍해 주‍세‍요';

  @override
  String get keyringUnreadableBody =>
      'Vizor‍가 시‍스‍템 키‍링‍의 데‍이‍터‍를 읽‍지 못‍했‍어‍요. 접‍근‍을 복‍구‍한 뒤 다‍시 시‍도‍하‍거‍나 Vizor‍를 종‍료‍해 주‍세‍요.';

  @override
  String get keyringUnreadableTitle => '보‍안 저‍장‍소‍를 읽‍을 수 없‍어‍요';

  @override
  String keystoneAccountsFound(int count) {
    return '계‍정 $count‍개‍를 찾‍았‍어‍요';
  }

  @override
  String get keystoneAllowCamera => '카‍메‍라 허‍용';

  @override
  String get keystoneBatchCannotSignDeposit =>
      '이 입‍금‍에‍는 Keystone 일‍괄 서‍명‍으‍로 서‍명‍할 수 없‍는 입‍력‍이 있‍어‍요.';

  @override
  String get keystoneBatchCannotSignTx =>
      '이 거‍래‍에‍는 Keystone 일‍괄 서‍명‍으‍로 서‍명‍할 수 없‍는 입‍력‍이 있‍어‍요.';

  @override
  String get keystoneBatchTooManyInputsDeposit =>
      '이 입‍금‍은 Keystone 일‍괄 서‍명‍을 하‍기‍엔 입‍력‍이 너‍무 많‍아‍요. 더 적‍은 금‍액‍으‍로 시‍도‍해 주‍세‍요.';

  @override
  String get keystoneBatchTooManyInputsTx =>
      '이 거‍래‍는 Keystone 일‍괄 서‍명‍을 하‍기‍엔 입‍력‍이 너‍무 많‍아‍요. 더 적‍은 금‍액‍으‍로 시‍도‍해 주‍세‍요.';

  @override
  String get keystoneBirthdayInvalidHeight => '올‍바‍른 블‍록 높‍이‍가 아‍닌 것 같‍아‍요.';

  @override
  String get keystoneBirthdaySubtitle => '알‍려 주‍시‍면 지‍갑‍을 더 빨‍리 가‍져‍올 수 있‍어‍요.';

  @override
  String get keystoneCameraDeniedTitle => '카‍메‍라 접‍근‍을 거‍부‍했‍어‍요';

  @override
  String get keystoneCameraEnableBody =>
      'Keystone‍을 연‍결‍하‍려‍면 카‍메‍라‍가 필‍요‍해‍요.\n나‍중‍에 설‍정‍에‍서 언‍제‍든 되‍돌‍릴 수 있‍어‍요.';

  @override
  String get keystoneCameraEnableTitle => '카‍메‍라 접‍근 허‍용';

  @override
  String get keystoneCameraExternal => '외‍장';

  @override
  String get keystoneCameraFront => '전‍면';

  @override
  String get keystoneCameraGiftBody =>
      '기‍프‍트 카‍드 QR 코‍드‍를 스‍캔‍하‍려‍면 카‍메‍라‍가 필‍요‍해‍요.\n나‍중‍에 설‍정‍에‍서 언‍제‍든‍지 되‍돌‍릴 수 있‍어‍요.';

  @override
  String keystoneCameraNameDefault(String name) {
    return '$name (기‍본)';
  }

  @override
  String get keystoneCameraNormal => '일‍반';

  @override
  String get keystoneCameraOffAllow =>
      '카‍메‍라 접‍근‍이 꺼‍져 있‍어‍요. Keystone 서‍명‍을 스‍캔‍하‍려‍면 설‍정‍에‍서 허‍용‍해 주‍세‍요.';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone 가‍져‍오‍기‍는 카‍메‍라 QR 스‍캔‍만 지‍원‍해‍요.\n카‍메‍라‍를 연‍결‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get keystoneCameraWide => '광‍각';

  @override
  String get keystoneCameraZoom => '줌';

  @override
  String get keystoneConfirmSelection => '선‍택 확‍인';

  @override
  String get keystoneFirmwareBody =>
      'Keystone‍이 최‍신 Cypherpunk 펌‍웨‍어‍인‍지 확‍인‍해 주‍세‍요. ';

  @override
  String get keystoneFirmwareDownloadSemantics => 'Keystone 펌‍웨‍어 다‍운‍로‍드';

  @override
  String get keystoneFirmwareLinkLabel => '링‍크';

  @override
  String get keystoneFirmwareOpenPage => 'Keystone 펌‍웨‍어 페‍이‍지 열‍기';

  @override
  String get keystoneFirmwareTitle => 'Keystone 펌‍웨‍어 확‍인';

  @override
  String keystoneFirmwareUpdate(String link) {
    return '최‍신 Keystone 펌‍웨‍어‍로 업‍데‍이‍트‍하‍세‍요: $link';
  }

  @override
  String get keystoneImReadyNow => '준‍비 완‍료';

  @override
  String get keystoneOnVizor => 'Vizor‍에‍서';

  @override
  String get keystoneOnYourKeystone => 'Keystone‍에‍서';

  @override
  String get keystonePrepareToConnectTitle => '연‍결 준‍비';

  @override
  String get keystonePreparingQr => 'QR 준‍비 중';

  @override
  String get keystoneReadingQr => 'QR‍을 읽‍는 중...';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone 가‍져‍오‍기‍는 카‍메‍라‍로 QR‍을 스‍캔‍하‍는 방‍식‍만 지‍원‍해‍요. 카‍메‍라‍를 연‍결‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get keystoneScanCaption => 'Keystone 계‍정 QR‍을 스‍캔‍하‍세‍요';

  @override
  String get keystoneScanCaptionConfirm =>
      '확‍인‍하‍려‍면 Keystone‍의 QR 코‍드‍를 스‍캔‍해 주‍세‍요';

  @override
  String get keystoneScanDecodeFailed =>
      '이 QR 코‍드‍를 Keystone Zcash 계‍정‍으‍로 읽‍지 못‍했‍어‍요.';

  @override
  String get keystoneScanHelpClose => '스‍캔 도‍움‍말 닫‍기';

  @override
  String get keystoneScanIssuesTitle => '스‍캔‍에 문‍제‍가 있‍나‍요?';

  @override
  String get keystoneScanNoAccounts =>
      '이 Keystone QR‍에‍서 Zcash 계‍정‍을 찾‍지 못‍했‍어‍요.';

  @override
  String get keystoneScanOpenAccountQr =>
      'Keystone‍에‍서 Zcash 계‍정 QR‍을 열‍고 다‍시 스‍캔‍하‍세‍요.';

  @override
  String keystoneScanProgress(int progress) {
    return '스‍캔 중... $progress%';
  }

  @override
  String get keystoneScanReadingAccounts => '계‍정‍을 읽‍는 중...';

  @override
  String get keystoneSelectCamera => '카‍메‍라 선‍택';

  @override
  String get keystoneStepHowToConnect => '연‍결 방‍법';

  @override
  String get keystoneStepOpenSoftwareWallet =>
      '오‍른‍쪽 위 •••를 탭‍한 다‍음 Connect software wallet‍을 선‍택‍하‍세‍요.';

  @override
  String get keystoneStepScanDynamicQr =>
      'Keystone‍에 표‍시‍된 동‍적 QR 코‍드‍를 스‍캔‍하‍세‍요.';

  @override
  String get keystoneStepSelectAccount => '계‍정 선‍택';

  @override
  String get keystoneStepSelectVizor => 'Vizor(또‍는 ZODL)를 선‍택‍하‍세‍요';

  @override
  String get keystoneSubmittingTransaction => '거‍래‍를 제‍출‍하‍는 중';

  @override
  String get keystoneTipGiftFullScreen =>
      '다‍른 기‍기‍에‍서 기‍프‍트 카‍드 QR 코‍드‍를 전‍체 화‍면‍으‍로 열‍어 보‍세‍요.';

  @override
  String get keystoneTipMoveKeystoneFurther =>
      '카‍메‍라‍가 초‍점‍을 맞‍출 수 있‍도‍록 Keystone‍을 카‍메‍라‍에‍서 조‍금 더 멀‍리 떨‍어‍뜨‍려 보‍세‍요.';

  @override
  String get keystoneTipTapFullScreen =>
      'Keystone‍의 QR 코‍드‍를 눌‍러 전‍체 화‍면‍으‍로 표‍시‍해 보‍세‍요. 가‍장 쉬‍운 해‍결 방‍법‍이‍에‍요.';

  @override
  String get keystoneTroubleScanning => '스‍캔‍이 안 되‍나‍요?';

  @override
  String get keystoneTryAgainWithKeystone => 'Keystone‍으‍로 다‍시 시‍도';

  @override
  String get ledgerAccountIndexFieldLabel => 'Ledger 계‍정 인‍덱‍스 (0–100)';

  @override
  String get ledgerAccountIndexHint =>
      '이 Ledger 계‍정‍에 다‍른 인‍덱‍스‍를 사‍용‍한 적‍이 없‍다‍면 0‍으‍로 두‍세‍요.';

  @override
  String get ledgerAccountIndexLabel => '계‍정 인‍덱‍스 (0–100)';

  @override
  String get ledgerAccountIndexOutOfRange =>
      '계‍정 인‍덱‍스‍는 0‍에‍서 100 사‍이‍여‍야 해‍요.';

  @override
  String get ledgerAddAccountNote =>
      'Vizor‍에‍서 잔‍액‍과 활‍동‍을 볼 수 있‍어‍요. 거‍래‍는 여‍전‍히 Ledger‍에‍서 승‍인‍해‍야 해‍요.';

  @override
  String get ledgerAddAccountTitle => 'Ledger 계‍정 추‍가';

  @override
  String get ledgerAdvancedOptions => '고‍급 옵‍션';

  @override
  String ledgerAppSemanticsLabel(String appName) {
    return '$appName 앱';
  }

  @override
  String get ledgerAppUpdateRequiredTitle => 'Ledger 앱 업‍데‍이‍트‍가 필‍요‍해‍요';

  @override
  String get ledgerApproveShareViewingKey =>
      'Vizor‍와 뷰‍잉 키‍를 공‍유‍하‍는 것‍을 승‍인‍해 주‍세‍요.';

  @override
  String ledgerApproveShareViewingKeyForAccount(String number) {
    return '계‍정 #$number‍의 뷰‍잉 키 공‍유‍를 승‍인‍해 주‍세‍요.';
  }

  @override
  String get ledgerBalanceActivityNote =>
      'Vizor‍에‍서 잔‍액‍과 활‍동‍을 확‍인‍하‍세‍요.\nLedger‍에‍서 거‍래‍를 승‍인‍하‍세‍요.';

  @override
  String get ledgerBleDeclinedOpen =>
      'Ledger‍에‍서 Zcash 앱 열‍기‍를 거‍부‍했‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerBleDeclinedShare =>
      'Ledger‍에‍서 공‍유‍를 거‍부‍했‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerBleReadFailedTryAgain =>
      'Vizor‍에‍서 이 Ledger 계‍정‍을 읽‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerBleReadFailedUsb =>
      'Vizor‍에‍서 이 Ledger 계‍정‍을 읽‍지 못‍했‍어‍요. USB 케‍이‍블‍로 Ledger‍를 다‍시 연‍결‍하‍고 PIN‍으‍로 잠‍금‍을 해‍제‍한 다‍음 Zcash 앱‍을 열‍어 주‍세‍요. 그‍런 다‍음 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerBluetoothConnection => 'Bluetooth 연‍결';

  @override
  String get ledgerBluetoothModelsList => 'Nano X, Flex, Stax, Nano Gen5';

  @override
  String get ledgerBluetoothPermissionRequired =>
      'Ledger‍를 찾‍으‍려‍면 Bluetooth 권‍한‍이 필‍요‍해‍요. 설‍정‍에‍서 허‍용‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerBtAccessAllowed =>
      '권‍한‍이 허‍용‍돼 있‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerBtAccessBluetoothRequestable =>
      'Ledger‍에 연‍결‍하‍려‍면 \'권‍한 허‍용\'을 선‍택‍해 주‍세‍요. 안‍내‍가 나‍타‍나‍지 않‍으‍면 설‍정‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerBtAccessBluetoothSettings =>
      '기‍기 설‍정‍에‍서 Vizor‍의 Bluetooth 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerBtAccessKindLocation => '위‍치';

  @override
  String get ledgerBtAccessLocationRequestable =>
      '이 Android 버‍전‍에‍서 Ledger‍를 찾‍으‍려‍면 위‍치 권‍한‍이 필‍요‍해‍요. \'권‍한 허‍용\'을 선‍택‍하‍거‍나, 안‍내‍가 나‍타‍나‍지 않‍으‍면 설‍정‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerBtAccessLocationSettings =>
      '이 Android 버‍전‍에‍서 Ledger‍를 찾‍으‍려‍면 위‍치 권‍한‍이 필‍요‍해‍요. 설‍정‍에‍서 Vizor‍의 위‍치 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerBtAccessMacosSettings =>
      '시‍스‍템 설‍정 > 개‍인‍정‍보 보‍호 및 보‍안 > Bluetooth‍를 열‍고 Vizor‍의 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String ledgerBtAccessRestricted(String kind) {
    return '$kind 접‍근‍이 기‍기 설‍정 또‍는 관‍리‍자‍에 의‍해 제‍한‍돼 있‍어‍요.';
  }

  @override
  String get ledgerBtAccessTurnOnBluetooth =>
      'Bluetooth‍를 켠 뒤 접‍근 권‍한‍을 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerBtAccessTurnOnLocation =>
      '위‍치 서‍비‍스‍를 켠 뒤 접‍근 권‍한‍을 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerBtCouldNotCheckAccess =>
      '접‍근 권‍한‍을 확‍인‍하‍지 못‍했‍어‍요. 설‍정‍을 직‍접 열‍고 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerBtCouldNotOpenSettingsAllow =>
      '설‍정‍을 열 수 없‍어‍요. 기‍기 설‍정‍을 직‍접 열‍어 Vizor‍의 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerBtCouldNotOpenSettingsRestricted =>
      '설‍정‍을 열 수 없‍어‍요. 기‍기 설‍정‍을 직‍접 열‍어 Vizor‍의 접‍근 권‍한‍을 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerBtLabelAllowAccess => '접‍근 허‍용';

  @override
  String get ledgerBtLabelChecking => '접‍근 권‍한 확‍인 중';

  @override
  String get ledgerBtLabelReconnect => '다‍시 연‍결';

  @override
  String get ledgerBtMsgBluetoothNeeded =>
      'Ledger‍에 연‍결‍하‍려‍면 Vizor‍에 Bluetooth 접‍근 권‍한‍이 필‍요‍해‍요.';

  @override
  String get ledgerBtMsgChecking =>
      'Vizor‍가 Ledger‍에 연‍결‍할 수 있‍는‍지 확‍인‍하‍고 있‍어‍요.';

  @override
  String get ledgerBtMsgLocationNeeded =>
      '이 Android 버‍전‍에‍서 Ledger‍를 찾‍으‍려‍면 위‍치 접‍근‍이 필‍요‍해‍요.';

  @override
  String get ledgerBtMsgReady => '계‍속‍하‍려‍면 Ledger‍를 켜‍고 잠‍금‍을 해‍제‍해 주‍세‍요.';

  @override
  String get ledgerBtRestrictedGeneric =>
      '설‍정‍에‍서 Vizor‍의 Bluetooth 접‍근‍을 확‍인‍해 주‍세‍요. 기‍기 제‍한‍이‍나 관‍리‍자‍가 변‍경‍을 막‍을 수 있‍어‍요.';

  @override
  String get ledgerBtRestrictedLocation =>
      '설‍정‍에‍서 Vizor‍의 위‍치 접‍근‍을 확‍인‍해 주‍세‍요. 기‍기 제‍한‍이‍나 관‍리‍자‍가 변‍경‍을 막‍을 수 있‍어‍요.';

  @override
  String get ledgerBtRestrictedMacos =>
      '시‍스‍템 설‍정‍의 개‍인‍정‍보 보‍호 및 보‍안 > Bluetooth‍를 확‍인‍해 주‍세‍요. 이 제‍한‍은 관‍리‍자‍가 변‍경‍해‍야 할 수 있‍어‍요.';

  @override
  String get ledgerBtRestrictedNearby =>
      '설‍정‍에‍서 Vizor‍의 근‍처 기‍기 접‍근‍을 확‍인‍해 주‍세‍요. 기‍기 제‍한‍이‍나 관‍리‍자‍가 변‍경‍을 막‍을 수 있‍어‍요.';

  @override
  String get ledgerBtSheetAllowAddAccount =>
      '계‍정‍을 추‍가‍하‍려‍면 휴‍대‍폰 설‍정‍에‍서 Vizor‍의 Bluetooth 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerBtSheetAllowContinue =>
      '계‍속‍하‍려‍면 휴‍대‍폰 설‍정‍에‍서 Vizor‍의 Bluetooth 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerBtSheetAllowSigning =>
      '서‍명‍을 이‍어‍가‍려‍면 휴‍대‍폰 설‍정‍에‍서 Vizor‍의 Bluetooth 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerBtSheetReadyAddAccount =>
      'Bluetooth‍를 사‍용‍할 수 있‍어‍요. 계‍정‍을 추‍가‍하‍려‍면 Ledger‍의 잠‍금‍을 해‍제‍해 주‍세‍요.';

  @override
  String get ledgerBtSheetReadyContinue =>
      'Bluetooth‍를 사‍용‍할 수 있‍어‍요. 계‍속‍하‍려‍면 Ledger‍의 잠‍금‍을 해‍제‍해 주‍세‍요.';

  @override
  String get ledgerBtSheetReadySigning =>
      'Bluetooth‍를 사‍용‍할 수 있‍어‍요. 서‍명‍을 이‍어‍가‍려‍면 Ledger‍의 잠‍금‍을 해‍제‍해 주‍세‍요.';

  @override
  String get ledgerBtSheetTurnOnAddAccount =>
      '계‍정‍을 추‍가‍하‍려‍면 휴‍대‍폰‍의 Bluetooth‍를 켜 주‍세‍요.';

  @override
  String get ledgerBtSheetTurnOnContinue =>
      '계‍속‍하‍려‍면 휴‍대‍폰‍의 Bluetooth‍를 켜 주‍세‍요.';

  @override
  String get ledgerBtSheetTurnOnSigning =>
      '서‍명‍을 이‍어‍가‍려‍면 휴‍대‍폰‍의 Bluetooth‍를 켜 주‍세‍요.';

  @override
  String get ledgerBtTitleAllowBluetooth => 'Bluetooth 접‍근‍을 허‍용‍해 주‍세‍요';

  @override
  String get ledgerBtTitleAllowBluetoothSettings =>
      '설‍정‍에‍서 Bluetooth‍를 허‍용‍해 주‍세‍요';

  @override
  String get ledgerBtTitleAllowLocation => '위‍치 접‍근‍을 허‍용‍해 주‍세‍요';

  @override
  String get ledgerBtTitleAllowLocationSettings => '설‍정‍에‍서 위‍치‍를 허‍용‍해 주‍세‍요';

  @override
  String get ledgerBtTitleChecking => 'Bluetooth 접‍근 권‍한‍을 확‍인‍하‍는 중';

  @override
  String get ledgerBtTitleReady => '다‍시 연‍결‍할 준‍비‍가 됐‍어‍요';

  @override
  String get ledgerBtTitleRestricted => '접‍근‍이 제‍한‍되‍어 있‍어‍요';

  @override
  String get ledgerBtTitleTurnOnBluetooth => 'Bluetooth‍를 켜 주‍세‍요';

  @override
  String get ledgerBtTitleTurnOnLocation => '위‍치 서‍비‍스‍를 켜 주‍세‍요';

  @override
  String get ledgerButtonCheckingAccount => '계‍정 확‍인 중';

  @override
  String get ledgerButtonConnecting => '연‍결 중';

  @override
  String get ledgerButtonSearching => '검‍색 중';

  @override
  String get ledgerCancelFailed => '취‍소‍를 마‍치‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerCancellingRequest => '요‍청‍을 취‍소‍하‍는 중';

  @override
  String get ledgerCancellingTheRequest => 'Ledger 요‍청‍을 취‍소‍하‍는 중…';

  @override
  String get ledgerCapabilityMainnetOnly =>
      'Ledger‍는 현‍재 Zcash 메‍인‍넷‍에‍서‍만 지‍원‍돼‍요.';

  @override
  String get ledgerCapabilityUnsupportedPlatform =>
      'Vizor‍에‍서 Ledger‍는 macOS, Windows, Linux, iOS, Android‍에‍서 지‍원‍돼‍요.';

  @override
  String get ledgerChangedKeepOne =>
      'Ledger‍가 바‍뀌‍었‍어‍요. Ledger‍를 하‍나‍만 연‍결‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerCheckingBluetoothAccess => 'Bluetooth 접‍근 권‍한‍을 확‍인‍하‍는 중…';

  @override
  String get ledgerCheckingUsb => 'USB 연‍결‍을 확‍인‍하‍는 중…';

  @override
  String get ledgerChooseAnother => '다‍른 Ledger 선‍택';

  @override
  String get ledgerChooseConnection => '연‍결 방‍법 선‍택';

  @override
  String get ledgerChooseDevice => '계‍속‍하‍려‍면 기‍기‍를 선‍택‍해 주‍세‍요.';

  @override
  String get ledgerChooseLedgerForAccount =>
      '이 계‍정‍에 사‍용‍할 Ledger‍를 선‍택‍해 주‍세‍요.';

  @override
  String get ledgerCleanupFailed => '정‍리‍를 마‍치‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerComeBackFindLedger =>
      'Ledger‍의 잠‍금‍을 해‍제‍해 둔 채‍로 아‍래‍의 \'Ledger 찾‍기\'를 선‍택‍해 주‍세‍요.';

  @override
  String get ledgerComeBackFindMyLedger =>
      'Ledger‍의 잠‍금‍을 해‍제‍해 둔 채‍로 아‍래‍의 \'내 Ledger 찾‍기\'를 선‍택‍해 주‍세‍요.';

  @override
  String get ledgerComeBackReconnect => '돌‍아‍와‍서 다‍시 연‍결';

  @override
  String get ledgerCompletePairingOpenZcash =>
      '안‍내‍가 나‍타‍나‍면 페‍어‍링‍을 완‍료‍한 뒤 Zcash 앱‍을 열‍고 뷰‍잉 키 공‍유‍를 승‍인‍해 주‍세‍요.';

  @override
  String get ledgerConfirmOpeningZcash => 'Ledger‍에‍서 Zcash 열‍기‍를 확‍인‍하‍세‍요.';

  @override
  String get ledgerConnectForAccount => '이 계‍정‍의 Ledger‍를 연‍결‍해 주‍세‍요.';

  @override
  String get ledgerConnectSubtitle => 'Ledger 지‍갑‍을 준‍비‍해 주‍세‍요.';

  @override
  String get ledgerConnectUsbCable => 'USB 케‍이‍블‍로 연‍결‍하‍세‍요.';

  @override
  String ledgerConnectingTo(String device) {
    return '$device‍에 연‍결‍하‍는 중';
  }

  @override
  String get ledgerConnectionHelp => '연‍결 도‍움‍말';

  @override
  String get ledgerConnectionRequiredBluetooth =>
      'Ledger‍를 켜‍고 잠‍금‍을 해‍제‍한 다‍음 Bluetooth‍로 다‍시 연‍결‍해 주‍세‍요.';

  @override
  String get ledgerConnectionRequiredUsb =>
      'Ledger‍를 USB‍로 연‍결‍하‍고 잠‍금‍을 해‍제‍한 다‍음 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerContinueSigning => '서‍명 이‍어‍가‍기';

  @override
  String get ledgerCouldNotConnect => 'Ledger‍를 연‍결‍하‍지 못‍했‍어‍요';

  @override
  String get ledgerCouldNotStopSearchTryAgain =>
      '검‍색‍을 중‍지‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerDifferentFromSaved => '저‍장‍된 연‍결‍과 달‍라‍요';

  @override
  String get ledgerDiscoveryErrorFallback => '다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerDiscoveryErrorTitle => 'Ledger‍에 연‍결‍하‍지 못‍했‍어‍요';

  @override
  String get ledgerDiscoveryFailed =>
      'Vizor‍에‍서 Ledger 기‍기‍를 찾‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerEnableBluetoothNearby =>
      'Bluetooth‍를 켜‍고 Ledger‍를 가‍까‍이‍에 두‍세‍요.';

  @override
  String get ledgerErrorAlreadyAdded => '이 Ledger 계‍정‍은 이‍미 Vizor‍에 있‍어‍요.';

  @override
  String get ledgerErrorCannotReadCheckConnection =>
      'Vizor‍에‍서 이 Ledger 계‍정‍을 읽‍지 못‍했‍어‍요. 연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String ledgerErrorCannotReadWithInstruction(String instruction) {
    return 'Vizor‍에‍서 이 Ledger 계‍정‍을 읽‍지 못‍했‍어‍요. $instruction 그‍런 다‍음 다‍시 시‍도‍해 주‍세‍요.';
  }

  @override
  String ledgerErrorConnectAndUnlock(String instruction) {
    return 'Ledger‍를 연‍결‍하‍고 잠‍금‍을 해‍제‍해 주‍세‍요. $instruction';
  }

  @override
  String ledgerErrorUnlock(String instruction) {
    return 'Ledger‍의 잠‍금‍을 해‍제‍해 주‍세‍요. $instruction';
  }

  @override
  String get ledgerErrorViewingKeyDeclined =>
      'Ledger‍에‍서 뷰‍잉 키 요‍청‍을 거‍부‍했‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerErrorViewingKeyRejected =>
      'Ledger‍에‍서 뷰‍잉 키 요‍청‍을 거‍부‍했‍어‍요.';

  @override
  String ledgerFailureMsgAppUpdateRequired(String version) {
    return 'Ledger Wallet‍에‍서 Ledger‍와 Zcash 앱‍을 $version 이‍상‍으‍로 업‍데‍이‍트‍해 주‍세‍요.';
  }

  @override
  String get ledgerFailureMsgBusy =>
      'Ledger‍가 사‍용 중‍이‍에‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgCancelledTryAgain =>
      '요‍청‍이 취‍소‍됐‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgCheckOpenZcash =>
      'Ledger‍를 확‍인‍하‍고 Zcash 앱‍을 연 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgDeclined =>
      'Ledger‍에‍서 거‍부‍했‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgGiftCardRejected =>
      'Ledger‍가 이 요‍청‍을 수‍락‍하‍지 못‍했‍어‍요. 새 기‍프‍트 카‍드‍를 만‍들‍어 주‍세‍요. 아‍무‍것‍도 전‍송‍되‍지 않‍았‍어‍요.';

  @override
  String get ledgerFailureMsgGiftCardTooLarge =>
      'Ledger‍가 처‍리‍하‍기‍엔 너‍무 커‍요. 더 적‍은 금‍액‍으‍로 기‍프‍트 카‍드‍를 만‍들‍어 주‍세‍요.';

  @override
  String get ledgerFailureMsgInstallZcash =>
      'Ledger Wallet‍으‍로 Zcash 앱‍을 설‍치‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgMemoHashUnsupported =>
      '영‍어‍가 아‍닌 메‍모‍에 서‍명‍하‍려‍면 Ledger‍의 Zcash 앱‍을 업‍데‍이‍트‍해 주‍세‍요';

  @override
  String get ledgerFailureMsgMigrationTooLarge =>
      '이 마‍이‍그‍레‍이‍션 단‍계‍는 Ledger‍가 서‍명‍하‍기‍엔 너‍무 커‍요. Vizor‍는 아‍직 나‍눌 수 없‍어‍요.';

  @override
  String get ledgerFailureMsgOpenZcash => 'Ledger‍에‍서 Zcash 앱‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerFailureMsgOrchardChange =>
      'Ledger‍는 Orchard‍에 잔‍돈‍이 남‍는 거‍래‍에 서‍명‍할 수 없‍어‍요. 먼‍저 Orchard 잔‍액‍을 Ironwood‍로 마‍이‍그‍레‍이‍션‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgPaymentTooLarge =>
      '새 결‍제‍를 시‍작‍해 주‍세‍요. 이 주‍소‍로 더 적‍은 금‍액‍을 보‍내‍지 마‍세‍요.';

  @override
  String get ledgerFailureMsgReconnectUnlock =>
      'Ledger‍를 다‍시 연‍결‍하‍고 잠‍금‍을 해‍제‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgRejectedNewRequest =>
      'Ledger‍가 이 요‍청‍을 수‍락‍하‍지 못‍했‍어‍요. 새‍로 만‍들‍어 주‍세‍요. 아‍무‍것‍도 전‍송‍되‍지 않‍았‍어‍요.';

  @override
  String get ledgerFailureMsgReopenZcash => 'Zcash 앱‍을 닫‍았‍다‍가 다‍시 열‍어 주‍세‍요.';

  @override
  String get ledgerFailureMsgSaplingRecipient =>
      'Ledger‍는 Sapling 주‍소‍로 보‍낼 수 없‍어‍요. 새 요‍청‍을 만‍들‍어 주‍세‍요.';

  @override
  String get ledgerFailureMsgSetPin =>
      'Ledger‍에‍서 PIN‍을 설‍정‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgShieldTooLarge =>
      'Ledger‍가 처‍리‍하‍기‍엔 입‍력‍이 너‍무 많‍아‍요. 다‍시 시‍도‍해 주‍세‍요. 차‍폐‍된 것‍은 없‍어‍요.';

  @override
  String get ledgerFailureMsgSwapTooLarge =>
      '더 적‍은 금‍액‍으‍로 새 스‍왑‍을 시‍작‍해 주‍세‍요. 이 스‍왑‍은 폐‍기‍됐‍어‍요.';

  @override
  String get ledgerFailureMsgTooManyInputs =>
      'Ledger‍가 처‍리‍하‍기‍엔 입‍력‍이 너‍무 많‍아‍요. 더 적‍은 금‍액‍으‍로 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgUnexpected =>
      '예‍상‍치 못‍한 Ledger 오‍류‍가 발‍생‍했‍어‍요. Zcash 앱‍을 다‍시 열‍고 시‍도‍해 주‍세‍요.';

  @override
  String ledgerFailureMsgUnexpectedWithCode(String code) {
    return '예‍상‍치 못‍한 Ledger 오‍류‍가 발‍생‍했‍어‍요‍$code. Zcash 앱‍을 다‍시 열‍고 시‍도‍해 주‍세‍요.';
  }

  @override
  String get ledgerFailureMsgUnlock =>
      'Ledger‍의 잠‍금‍을 해‍제‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgUnsupportedTxType =>
      'Ledger‍는 이 거‍래 유‍형‍에 서‍명‍할 수 없‍어‍요. 새 요‍청‍을 만‍들‍어 주‍세‍요.';

  @override
  String ledgerFailureMsgUpdateZcash(String version) {
    return 'Zcash 앱‍을 $version 이‍상‍으‍로 업‍데‍이‍트‍해 주‍세‍요.';
  }

  @override
  String get ledgerFailureMsgViewingKeyRejected =>
      'Ledger‍가 이 뷰‍잉 키 요‍청‍을 수‍락‍하‍지 못‍했‍어‍요. 계‍정 번‍호‍를 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerFailureMsgVoteRejected =>
      'Ledger‍가 이 투‍표 요‍청‍을 수‍락‍하‍지 못‍했‍어‍요. 투‍표‍가 서‍명‍되‍지 않‍았‍어‍요.';

  @override
  String get ledgerFailureMsgVoteTooLarge =>
      '이 투‍표‍는 Ledger‍가 서‍명‍하‍기‍엔 너‍무 커‍요.';

  @override
  String get ledgerFailureMsgWrongLedger => '이 계‍정‍이 있‍는 Ledger‍를 연‍결‍해 주‍세‍요.';

  @override
  String get ledgerFailureTitleBusy => 'Ledger‍가 사‍용 중‍이‍에‍요';

  @override
  String get ledgerFailureTitleCancelled => '요‍청‍이 취‍소‍됐‍어‍요';

  @override
  String get ledgerFailureTitleError => 'Ledger 오‍류';

  @override
  String get ledgerFailureTitleFailed => '요‍청‍에 실‍패‍했‍어‍요';

  @override
  String get ledgerFailureTitleLocked => 'Ledger‍가 잠‍겨 있‍어‍요';

  @override
  String get ledgerFailureTitleNotReachable => 'Ledger‍에 연‍결‍할 수 없‍어‍요';

  @override
  String get ledgerFailureTitleOpenZcash => 'Zcash 앱‍을 열‍어 주‍세‍요';

  @override
  String get ledgerFailureTitlePinRequired => 'PIN‍이 필‍요‍해‍요';

  @override
  String get ledgerFailureTitleRejected => '요‍청‍이 수‍락‍되‍지 않‍았‍어‍요';

  @override
  String get ledgerFailureTitleReopenZcash => 'Zcash 앱‍을 다‍시 열‍어 주‍세‍요';

  @override
  String get ledgerFailureTitleTooLarge => '요‍청‍이 너‍무 커‍요';

  @override
  String get ledgerFailureTitleUpdateZcash => 'Zcash 앱‍을 업‍데‍이‍트‍해 주‍세‍요';

  @override
  String get ledgerFailureTitleWrongLedger => '다‍른 Ledger‍예‍요';

  @override
  String get ledgerFailureTitleZcashMissing => 'Zcash 앱‍이 없‍어‍요';

  @override
  String get ledgerFind => 'Ledger 찾‍기';

  @override
  String get ledgerFindMyLedger => '내 Ledger 찾‍기';

  @override
  String get ledgerFollowPromptsOnLedger => 'Ledger‍의 안‍내‍를 따‍라 주‍세‍요.';

  @override
  String get ledgerHelpChecksCloseOtherApps =>
      '다‍른 지‍갑 앱‍을 닫‍고, 다‍른 휴‍대‍폰‍이‍나 컴‍퓨‍터‍에‍서 Ledger 연‍결‍을 해‍제‍해 주‍세‍요.';

  @override
  String get ledgerHelpChecksHomeScreen =>
      'Ledger‍를 홈 화‍면‍에 두‍세‍요. Vizor‍가 요‍청‍하‍면 Zcash 앱‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerHelpChecksUnlockClose =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍고 Bluetooth‍를 켠 뒤 휴‍대‍폰 가‍까‍이‍에 두‍세‍요.';

  @override
  String get ledgerHelpChooseModel => '모‍델‍을 선‍택‍해 주‍세‍요';

  @override
  String get ledgerHelpFindInPhoneBluetooth =>
      '휴‍대‍폰‍의 Bluetooth 설‍정‍에‍서 Ledger‍를 찾‍아 주‍세‍요.';

  @override
  String get ledgerHelpForgetAndroid =>
      'Bluetooth 설‍정 > Ledger 옆‍의 설‍정 버‍튼 > 삭‍제 또‍는 페‍어‍링 해‍제';

  @override
  String get ledgerHelpForgetIos =>
      '설‍정 > Bluetooth > Ledger 옆‍의 정‍보 버‍튼 > 이 기‍기 지‍우‍기';

  @override
  String get ledgerHelpKeepUnlockedHome =>
      'Ledger‍를 잠‍금 해‍제‍하‍고 Bluetooth‍를 켠 상‍태‍로 홈 화‍면‍에 두‍세‍요.';

  @override
  String get ledgerHelpModelLabel => 'Ledger 모‍델';

  @override
  String get ledgerHelpNanoXConfirm =>
      'Ledger‍에‍서 확‍인‍하‍고 기‍기‍에‍서 PIN‍을 입‍력‍해 주‍세‍요.';

  @override
  String get ledgerHelpNanoXControls =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍세‍요. 두 버‍튼‍을 길‍게 눌‍러 제‍어 메‍뉴‍를 연 다‍음 아‍래‍를 선‍택‍해 주‍세‍요.';

  @override
  String get ledgerHelpNanoXMenuPath => 'Settings > Security > Reset pairings';

  @override
  String get ledgerHelpNanoXName =>
      'Nano X‍에‍서 두 버‍튼‍을 2‍초 동‍안 누‍른 뒤 Device Name‍을 찾‍아 주‍세‍요.';

  @override
  String get ledgerHelpNextPhoneSettings => '다‍음: 휴‍대‍폰 설‍정';

  @override
  String get ledgerHelpNextSearchInVizor => '다‍음: Vizor‍에‍서 검‍색';

  @override
  String get ledgerHelpNextSearchTitle => 'Ledger 찾‍기';

  @override
  String get ledgerHelpNotResetDevice =>
      'Reset device‍가 아‍니‍라 Bluetooth 페‍어‍링 옵‍션‍을 사‍용‍해 주‍세‍요. 지‍갑‍과 계‍정‍은 그‍대‍로 유‍지‍돼‍요.';

  @override
  String get ledgerHelpOpenBluetoothSettings => 'Bluetooth 설‍정 열‍기';

  @override
  String ledgerHelpOtherModelName(String model) {
    return '$model‍에‍서 Settings > Name‍을 확‍인‍해 주‍세‍요.';
  }

  @override
  String get ledgerHelpRemovePairingOnLedger =>
      'Ledger‍에‍서 저‍장‍된 페‍어‍링‍을 삭‍제‍한 뒤 휴‍대‍폰‍에‍서‍도 삭‍제‍해 주‍세‍요.';

  @override
  String get ledgerHelpRestartBothGuide =>
      '그‍래‍도 나‍타‍나‍지 않‍으‍면 두 기‍기‍를 모‍두 다‍시 시‍작‍하‍고 Ledger 공‍식 Bluetooth 문‍제 해‍결 가‍이‍드‍를 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerHelpSearchSelectOpenZcash =>
      'Vizor‍에‍서 검‍색‍해 Ledger‍를 선‍택‍해 주‍세‍요. Vizor‍가 요‍청‍하‍면 Zcash 앱‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerHelpSelectModelHint =>
      '모‍델‍을 선‍택‍하‍면 페‍어‍링 삭‍제 방‍법‍을 볼 수 있‍어‍요.';

  @override
  String get ledgerHelpShortIdName =>
      'Ledger‍에 이‍름‍을 지‍정‍하‍지 않‍았‍다‍면 01AB 같‍은 짧‍은 ID‍로 표‍시‍될 수 있‍어‍요. 지‍정‍했‍다‍면 설‍정‍한 이‍름‍을 찾‍아 주‍세‍요.';

  @override
  String get ledgerHelpSkipIfNotListed =>
      'Ledger‍가 목‍록‍에 없‍으‍면 이 단‍계‍를 건‍너‍뛰‍고 계‍속‍해 주‍세‍요.';

  @override
  String ledgerHelpStepBackInVizor(String step) {
    return '3‍단‍계 중 $step‍단‍계 · 다‍시 Vizor‍에‍서';
  }

  @override
  String ledgerHelpStepOnLedger(String step) {
    return '3‍단‍계 중 $step‍단‍계 · Ledger‍에‍서';
  }

  @override
  String ledgerHelpStepOnPhone(String step) {
    return '3‍단‍계 중 $step‍단‍계 · 휴‍대‍폰‍에‍서';
  }

  @override
  String get ledgerHelpStillNotShowing => '아‍직 보‍이‍지 않‍나‍요?';

  @override
  String get ledgerHelpTouchControls =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍세‍요. 홈 화‍면‍에‍서 설‍정 아‍이‍콘‍을 누‍른 다‍음 아‍래‍를 선‍택‍해 주‍세‍요.';

  @override
  String get ledgerHelpTouchMenuPath => 'Bluetooth > Remove pairing';

  @override
  String get ledgerHelpTryRestart =>
      'Ledger‍를 다‍시 시‍작‍해 보‍세‍요. 계‍속 보‍이‍지 않‍으‍면 두 기‍기‍에‍서 저‍장‍된 Bluetooth 페‍어‍링‍을 삭‍제‍하‍면 도‍움‍이 될 수 있‍어‍요.';

  @override
  String ledgerKeepAppOpen(String appName) {
    return '$appName 앱‍을 열‍어 둔 채‍로 유‍지‍하‍세‍요.';
  }

  @override
  String get ledgerKeepConnectedUntilCancelled =>
      '현‍재 요‍청‍이 취‍소‍될 때‍까‍지 Ledger‍를 연‍결‍해 두‍세‍요.';

  @override
  String get ledgerKeepConnectedWhileChecking =>
      'Vizor‍가 앱‍을 확‍인‍하‍는 동‍안 Ledger‍를 연‍결‍해 두‍세‍요.';

  @override
  String get ledgerKeepItOpen => 'Ledger‍에‍서 열‍어 둔 채‍로 유‍지‍해 주‍세‍요.';

  @override
  String get ledgerKeepNearbyUnlocked =>
      'Ledger‍를 가‍까‍이‍에 두‍고 잠‍금‍을 해‍제‍한 상‍태‍로 Bluetooth‍를 켜 두‍세‍요.';

  @override
  String get ledgerKeepNearbyUnlockedShort =>
      'Ledger‍를 가‍까‍이‍에 두‍고 잠‍금‍을 해‍제‍해 두‍세‍요.';

  @override
  String get ledgerKeepZcashOpen => 'Zcash 앱‍을 열‍어 둔 채‍로 유‍지‍하‍세‍요.';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS‍에‍서 Bluetooth 접‍근 권‍한‍을 요‍청‍할 수 있‍어‍요. 요‍청‍이 나‍타‍나‍면 Vizor‍에 접‍근‍을 허‍용‍해 주‍세‍요.';

  @override
  String get ledgerMismatchChooseHolder =>
      '이 계‍정‍이 있‍는 Ledger‍를 선‍택‍해 주‍세‍요. 저‍장‍된 연‍결‍은 변‍경‍되‍지 않‍았‍어‍요.';

  @override
  String get ledgerMismatchChooseHolderMobile =>
      '이 계‍정‍이 있‍는 Ledger‍를 선‍택‍해 주‍세‍요. 저‍장‍된 연‍결‍은 변‍경‍되‍지 않‍았‍어‍요.';

  @override
  String get ledgerMismatchConnectHolder =>
      '이 계‍정‍이 있‍는 Ledger‍를 연‍결‍해 주‍세‍요. 저‍장‍된 연‍결‍은 변‍경‍되‍지 않‍았‍어‍요.';

  @override
  String get ledgerMobileAnotherRequestActive =>
      '다‍른 Ledger 요‍청‍이 아‍직 진‍행 중‍이‍에‍요. Ledger‍에‍서 완‍료‍하‍거‍나 거‍부‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileCheckBluetoothBelow =>
      '아‍래‍에‍서 Bluetooth 접‍근 권‍한‍을 확‍인‍한 뒤 Ledger‍에 다‍시 연‍결‍해 보‍세‍요.';

  @override
  String get ledgerMobileConnectionFailed => 'Ledger‍에 연‍결‍하‍지 못‍했‍어‍요.';

  @override
  String get ledgerMobileConnectionLost =>
      'Ledger‍와‍의 Bluetooth 연‍결‍이 끊‍겼‍거‍나 연‍결‍할 수 없‍어‍요. Ledger‍를 켜‍고 잠‍금‍을 해‍제‍한 뒤 가‍까‍이‍에 두‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileDiscoveryFailed => 'Ledger‍를 찾‍지 못‍했‍어‍요.';

  @override
  String get ledgerMobileEmptyResponse => 'Ledger‍가 빈 응‍답‍을 보‍냈‍어‍요.';

  @override
  String get ledgerMobilePairingInvalid =>
      'Bluetooth 페‍어‍링‍이 더 이‍상 유‍효‍하‍지 않‍아‍요. 기‍기‍의 Bluetooth 설‍정‍에‍서 이 Ledger‍를 삭‍제‍한 뒤 다‍시 연‍결‍해 주‍세‍요.';

  @override
  String get ledgerMobilePairingNotCompleted =>
      'Bluetooth 페‍어‍링‍이 완‍료‍되‍지 않‍았‍어‍요. Ledger‍를 다‍시 연‍결‍하‍고 페‍어‍링 요‍청‍을 승‍인‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileRequestCancelled =>
      'Ledger 요‍청‍이 취‍소‍됐‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileRequestRejected =>
      'Ledger‍에‍서 요‍청‍이 거‍부‍됐‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileTurnOnBluetooth => 'Bluetooth‍를 켠 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileTurnOnLocation =>
      '이 Android 버‍전‍에‍서 Ledger‍를 찾‍으‍려‍면 위‍치 서‍비‍스‍를 켠 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileUnavailable =>
      'Vizor‍가 Ledger‍에 연‍결‍하‍지 못‍했‍어‍요. Ledger‍가 켜‍져 있‍고 잠‍금‍이 해‍제‍되‍어 있‍으‍며 가‍까‍이‍에 있‍는‍지 확‍인‍한 다‍음 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerMobileUnknownDiscoveryEvent =>
      'Ledger 검‍색 중 알 수 없‍는 응‍답‍을 받‍았‍어‍요.';

  @override
  String get ledgerNoDevicesFound => 'Ledger 기‍기‍를 찾‍지 못‍했‍어‍요';

  @override
  String get ledgerNoDevicesFoundHint =>
      'Ledger‍의 잠‍금‍이 해‍제‍되‍어 있‍는‍지 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerNoneFoundDesktop =>
      'Ledger‍를 찾‍지 못‍했‍어‍요. Ledger‍의 잠‍금‍을 해‍제‍하‍고 Bluetooth‍를 켠 다‍음 가‍까‍이‍에 두‍세‍요. 그‍런 다‍음 다‍시 검‍색‍해 주‍세‍요.';

  @override
  String get ledgerOnYourLedger => 'Ledger‍에‍서';

  @override
  String ledgerOpenAppInstruction(String appName) {
    return '$appName 앱‍을 열‍어 주‍세‍요';
  }

  @override
  String ledgerOpenAppOnLedger(String appName) {
    return 'Ledger‍에‍서 $appName 앱‍을 열‍어 주‍세‍요.';
  }

  @override
  String get ledgerOpenBluetoothSettingsManually =>
      'Bluetooth 설‍정‍을 직‍접 열‍어 기‍존 페‍어‍링‍을 삭‍제‍해 주‍세‍요.';

  @override
  String get ledgerOpenZcashThenTryAgain => 'Zcash 앱‍을 연 다‍음 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerOpeningConnectionHelp => '연‍결 도‍움‍말‍을 여‍는 중…';

  @override
  String get ledgerPairingNoLongerRecognized =>
      'Ledger‍가 더 이‍상 이 Bluetooth 페‍어‍링‍을 인‍식‍하‍지 못‍해‍요.';

  @override
  String get ledgerPairingNoLongerRecognizedRemove =>
      'Ledger‍가 더 이‍상 이 Bluetooth 페‍어‍링‍을 인‍식‍하‍지 못‍해‍요. 기‍존 페‍어‍링‍을 삭‍제‍한 뒤 다‍시 연‍결‍해 주‍세‍요.';

  @override
  String ledgerProcedureStep(String step, String total) {
    return '$total‍단‍계 중 $step‍단‍계';
  }

  @override
  String ledgerProcedureStepComplete(String step, String total) {
    return '$total‍단‍계 중 $step‍단‍계, 완‍료';
  }

  @override
  String get ledgerReadinessAppNotVerified =>
      'Vizor‍가 Ledger Zcash 앱‍을 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerReadinessCouldNotPrepare =>
      'Vizor‍가 Ledger‍의 Zcash 앱‍을 준‍비‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerReadinessOpenZcashApp =>
      'Ledger‍에‍서 Zcash 앱‍을 연 다‍음 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerReadinessOperationCancelled => 'Ledger 작‍업‍이 취‍소‍됐‍어‍요.';

  @override
  String get ledgerReadinessReconnectUnlockTryAgain =>
      'Ledger‍를 다‍시 연‍결‍하‍고 잠‍금‍을 해‍제‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String ledgerReadinessUpdateApp(String version) {
    return 'Ledger Zcash 앱‍을 $version 버‍전 이‍상‍으‍로 업‍데‍이‍트‍해 주‍세‍요.';
  }

  @override
  String get ledgerReadinessUsbPermission =>
      'USB‍로 Ledger‍를 연‍결‍하‍고 잠‍금‍을 해‍제‍해 주‍세‍요. 이‍미 연‍결‍되‍어 있‍다‍면 Linux‍에‍서‍는 Ledger udev 규‍칙‍을 설‍치‍한 뒤 연‍결‍을 해‍제‍했‍다‍가 다‍시 연‍결‍해 주‍세‍요.';

  @override
  String get ledgerReadyContinueSigning =>
      'Ledger‍가 준‍비‍됐‍어‍요. 준‍비‍되‍면 서‍명‍을 이‍어‍가‍세‍요.';

  @override
  String get ledgerReadyReviewOnLedger =>
      'Ledger‍에‍서 거‍래‍를 검‍토‍할 준‍비‍가 되‍면 계‍속‍해 주‍세‍요.';

  @override
  String get ledgerReconnectTitle => 'Ledger 다‍시 연‍결';

  @override
  String get ledgerRemoveOldPairing => '기‍존 페‍어‍링 삭‍제';

  @override
  String get ledgerRemovePairingIos =>
      '설‍정 > Bluetooth‍를 열‍어 주‍세‍요. Ledger‍가 목‍록‍에 있‍다‍면 정‍보 버‍튼‍을 누‍르‍고 이 기‍기‍를 지‍워 주‍세‍요.';

  @override
  String get ledgerRemovePairingMacos =>
      '시‍스‍템 설‍정 > Bluetooth‍를 열‍어 주‍세‍요. Ledger‍가 목‍록‍에 있‍다‍면 저‍장‍된 페‍어‍링‍을 삭‍제‍해 주‍세‍요.';

  @override
  String get ledgerRemovePairingOther =>
      'Bluetooth 설‍정‍을 열‍어 주‍세‍요. Ledger‍가 목‍록‍에 있‍다‍면 저‍장‍된 페‍어‍링‍을 삭‍제‍해 주‍세‍요.';

  @override
  String get ledgerResetBluetoothPairing => 'Bluetooth 페‍어‍링 초‍기‍화';

  @override
  String get ledgerReturningToOptions => '연‍결 옵‍션‍으‍로 돌‍아‍가‍는 중…';

  @override
  String get ledgerSavedFindAgain =>
      '이 Ledger‍는 계‍정‍과 일‍치‍해‍요. 계‍속‍하‍려‍면 다‍시 찾‍아 주‍세‍요.';

  @override
  String get ledgerSavedMatchesFindAgain =>
      '이 Ledger‍는 계‍정‍과 일‍치‍하‍며 저‍장‍됐‍어‍요. 계‍속‍하‍려‍면 다‍시 찾‍아 주‍세‍요.';

  @override
  String get ledgerSavingVerified =>
      '계‍정‍이 일‍치‍해‍요. 확‍인‍된 연‍결‍을 저‍장‍하‍고 있‍어‍요.';

  @override
  String get ledgerSearchAgain => '다‍시 검‍색';

  @override
  String get ledgerSearchTakesAWhile => '몇 초 정‍도 걸‍릴 수 있‍어‍요.';

  @override
  String get ledgerSearchingDevices => 'Ledger 기‍기‍를 검‍색‍하‍는 중…';

  @override
  String get ledgerSearchingNearby => '주‍변 Ledger‍를 검‍색‍하‍는 중…';

  @override
  String get ledgerSelectYourLedger => '사‍용‍할 Ledger‍를 선‍택‍하‍세‍요.';

  @override
  String get ledgerSheetAddFailedTitle => 'Ledger 계‍정‍을 추‍가‍하‍지 못‍했‍어‍요';

  @override
  String get ledgerSheetCancelFailedTitle => 'Ledger 요‍청‍을 취‍소‍하‍지 못‍했‍어‍요';

  @override
  String get ledgerSheetDeclinedTitle => '요‍청‍이 거‍부‍됐‍어‍요';

  @override
  String get ledgerSigningApproveNextSeparately => '다‍음 거‍래‍는 따‍로 승‍인‍하‍게 돼‍요.';

  @override
  String get ledgerSigningApproveOrReject =>
      '승‍인‍하‍여 서‍명‍하‍거‍나, 거‍부‍하‍여 취‍소‍해 주‍세‍요.';

  @override
  String get ledgerSigningApproveToSign => '승‍인‍하‍여 서‍명‍해 주‍세‍요.';

  @override
  String get ledgerSigningApproveToSignNext =>
      '승‍인‍하‍여 서‍명‍해 주‍세‍요.\n\n다‍음 거‍래‍는 따‍로 승‍인‍하‍게 돼‍요.';

  @override
  String get ledgerSigningApprovedFinishing =>
      'Ledger‍에‍서 승‍인‍했‍어‍요. Vizor‍가 거‍래‍를 마‍무‍리‍하‍고 있‍어‍요.';

  @override
  String get ledgerSigningChangeConnection => '연‍결 변‍경';

  @override
  String get ledgerSigningCheckAmountRecipient =>
      '안‍내‍가 나‍타‍나‍면 Ledger‍에‍서 금‍액‍과 받‍는 사‍람‍을 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerSigningCloseSemantics => 'Ledger 닫‍기';

  @override
  String get ledgerSigningConfirmRequestReconnect =>
      'Ledger‍에‍서 요‍청‍을 확‍인‍해 주‍세‍요. Vizor‍가 자‍동‍으‍로 다‍시 연‍결‍해‍요.';

  @override
  String get ledgerSigningDeclined =>
      'Ledger‍에‍서 서‍명‍이 거‍부‍됐‍어‍요. 준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerSigningFinishingRequest => 'Ledger 요‍청‍을 마‍무‍리‍하‍고 있‍어‍요.';

  @override
  String get ledgerSigningKeepLedgerConnected =>
      'Ledger‍를 연‍결‍된 상‍태‍로 유‍지‍해 주‍세‍요.';

  @override
  String get ledgerSigningKeepOpenWhileCancelling =>
      'Ledger 요‍청‍이 취‍소‍되‍는 동‍안 Vizor‍를 열‍어 두‍세‍요.';

  @override
  String get ledgerSigningKeepVizorOpen => 'Vizor‍를 열‍어 둔 채‍로 유‍지‍하‍세‍요.';

  @override
  String get ledgerSigningKeepVizorOpenShort => 'Vizor‍를 열‍어 두‍세‍요';

  @override
  String get ledgerSigningMsgPreparing =>
      'Vizor‍가 거‍래‍를 준‍비‍하‍는 동‍안 잠‍시 기‍다‍려 주‍세‍요.';

  @override
  String get ledgerSigningMsgReviewing =>
      'Ledger‍에‍서 안‍내‍가 나‍타‍나‍면 내‍용‍을 검‍토‍하‍고 승‍인‍해 주‍세‍요.';

  @override
  String ledgerSigningMsgSending(String wait) {
    return '$wait Ledger‍를 연‍결‍된 상‍태‍로 유‍지‍해 주‍세‍요.';
  }

  @override
  String get ledgerSigningSaving => '서‍명‍된 거‍래‍를 저‍장‍하‍고 있‍어‍요.';

  @override
  String get ledgerSigningStatusCheckingDevice => '기‍기 확‍인 중';

  @override
  String get ledgerSigningStatusOpeningZcash => 'Zcash 여‍는 중';

  @override
  String get ledgerSigningStatusPreparing => '서‍명 준‍비 중';

  @override
  String get ledgerSigningStatusReview => '기‍기‍에‍서 검‍토';

  @override
  String get ledgerSigningStatusWaitingApproval => '승‍인‍을 기‍다‍리‍는 중';

  @override
  String get ledgerSigningStepFinish => '거‍래 완‍료';

  @override
  String get ledgerSigningStepPrepare => '거‍래 준‍비';

  @override
  String get ledgerSigningStepReview => 'Ledger‍에‍서 검‍토';

  @override
  String get ledgerSigningTitleConfirmOnLedger => 'Ledger‍에‍서 확‍인‍해 주‍세‍요';

  @override
  String get ledgerSigningTitleFinishing => '거‍래‍를 마‍무‍리‍하‍고 있‍어‍요';

  @override
  String get ledgerSigningTitlePreparing => '거‍래‍를 준‍비‍하‍고 있‍어‍요';

  @override
  String get ledgerSigningTitleReviewing => 'Ledger‍를 확‍인‍해 주‍세‍요';

  @override
  String get ledgerSigningTitleSending => 'Ledger‍에‍서 처‍리‍하‍고 있‍어‍요';

  @override
  String get ledgerSigningTitleSendingTx => '거‍래‍를 보‍내‍는 중';

  @override
  String get ledgerSigningTitleSign => '거‍래 서‍명';

  @override
  String ledgerSigningTransactionProgress(String current, String total) {
    return '거‍래 $current/$total';
  }

  @override
  String get ledgerSigningWaitInstruction =>
      'Ledger‍가 서‍명‍을 준‍비‍하‍고 있‍어‍요. 몇 초 동‍안 반‍응‍이 없‍는 것‍처‍럼 보‍일 수 있‍어‍요.';

  @override
  String get ledgerStatusFollowPrompts => 'Ledger‍의 안‍내‍를 따‍라 주‍세‍요';

  @override
  String get ledgerStatusOpeningBluetoothSettings => 'Bluetooth 설‍정‍을 여‍는 중…';

  @override
  String get ledgerStatusSavingConnection => '연‍결‍을 저‍장‍하‍는 중…';

  @override
  String get ledgerStatusSearchingNearby => '근‍처‍를 검‍색‍하‍는 중…';

  @override
  String get ledgerStatusStillSearching => '계‍속 근‍처‍를 검‍색‍하‍는 중…';

  @override
  String get ledgerStepApproveViewingKey => '뷰‍잉 키 승‍인';

  @override
  String ledgerStepOpenApp(String appName) {
    return '$appName 열‍기';
  }

  @override
  String get ledgerStepOpenZcash => 'Zcash 열‍기';

  @override
  String get ledgerStopSearchFailedHelp =>
      '검‍색‍을 중‍지‍하‍지 못‍했‍어‍요. 연‍결 도‍움‍말‍을 다‍시 열‍어 보‍세‍요.';

  @override
  String get ledgerStoppingSearch => '검‍색‍을 중‍지‍하‍는 중';

  @override
  String get ledgerSupportedDevices => '지‍원 기‍기';

  @override
  String get ledgerTitleConnectingToLedger => 'Ledger‍에 연‍결‍하‍는 중';

  @override
  String get ledgerTitleFindingLedger => 'Ledger‍를 찾‍는 중';

  @override
  String get ledgerTitleLedgerConnected => 'Ledger‍가 연‍결‍됐‍어‍요';

  @override
  String get ledgerTitleLedgerSaved => 'Ledger‍가 저‍장‍됐‍어‍요';

  @override
  String get ledgerTitleMismatch => '이 Ledger‍는 일‍치‍하‍지 않‍아‍요';

  @override
  String get ledgerTitlePairAgain => 'Ledger‍를 다‍시 페‍어‍링‍해 주‍세‍요';

  @override
  String get ledgerTitleSavingConnection => '연‍결‍을 저‍장‍하‍는 중';

  @override
  String get ledgerTitleSelectYourLedger => 'Ledger‍를 선‍택‍해 주‍세‍요';

  @override
  String get ledgerTransportBluetooth => 'Bluetooth';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerUnlockBluetoothNearby =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍고 Bluetooth‍를 켠 다‍음 가‍까‍이‍에 두‍세‍요.';

  @override
  String get ledgerUnlockEnableBluetoothNearby =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍고 Bluetooth‍를 켠 뒤 가‍까‍이‍에 두‍세‍요.';

  @override
  String get ledgerUnlockOpenZcashApprove =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍고 Zcash 앱‍을 열‍어 주‍세‍요. 안‍내‍가 나‍타‍나‍면 열‍기‍를 승‍인‍해 주‍세‍요.';

  @override
  String get ledgerUnlockWithPin => 'PIN‍으‍로 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String get ledgerUsbApproveOpening => 'Ledger‍에‍서 Zcash 앱 열‍기‍를 승‍인‍해 주‍세‍요.';

  @override
  String get ledgerUsbCheckCableOpenApp =>
      'USB 케‍이‍블‍을 확‍인‍하‍고 Ledger‍의 잠‍금‍을 해‍제‍한 뒤 Zcash 앱‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerUsbConnectUnlockOpen =>
      'USB 케‍이‍블‍로 Ledger‍를 연‍결‍하‍고 잠‍금‍을 해‍제‍한 뒤 Zcash 앱‍을 열‍어 주‍세‍요.';

  @override
  String get ledgerUsbConnection => 'USB 연‍결';

  @override
  String get ledgerUsbCouldNotOpen =>
      'Vizor‍가 Ledger‍를 찾‍았‍지‍만 열 수 없‍어‍요. Ledger‍를 사‍용‍하‍는 다‍른 지‍갑 앱‍을 닫‍고 다‍시 연‍결‍한 뒤 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerUsbCouldNotStart =>
      'Vizor‍가 Ledger‍의 USB 접‍근‍을 시‍작‍하‍지 못‍했‍어‍요. 기‍기‍를 다‍시 연‍결‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String ledgerUsbInterrupted(String instruction) {
    return 'Ledger‍와‍의 USB 연‍결‍이 끊‍겼‍어‍요. Ledger‍를 다‍시 연‍결‍하‍고 잠‍금‍을 해‍제‍해 주‍세‍요. $instruction';
  }

  @override
  String get ledgerUsbPermissionLinux =>
      'Vizor‍가 USB‍로 Ledger‍에 접‍근‍할 수 없‍어‍요. Linux‍용 Ledger udev 규‍칙(github.com/LedgerHQ/udev-rules)을 설‍치‍한 뒤 Ledger‍를 다‍시 연‍결‍하‍고 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerUsbPermissionOther =>
      'Vizor‍가 USB‍로 Ledger‍에 접‍근‍할 수 없‍어‍요. USB 장‍치 권‍한‍을 확‍인‍한 뒤 다‍시 연‍결‍하‍고 시‍도‍해 주‍세‍요.';

  @override
  String get ledgerVerifyingNewDevice =>
      '안‍내‍가 나‍타‍나‍면 페‍어‍링‍을 완‍료‍한 뒤 뷰‍잉 키 공‍유‍를 승‍인‍해 주‍세‍요.';

  @override
  String get ledgerVerifyingSavedDevice =>
      'Ledger‍의 잠‍금‍을 해‍제‍하‍고, 안‍내‍가 나‍타‍나‍면 Zcash 열‍기‍를 확‍인‍해 주‍세‍요.';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor‍가 Zcash 앱‍을 확‍인‍하‍고 있‍어‍요.';

  @override
  String get ledgerWaitingForApproval => '승‍인‍을 기‍다‍리‍는 중…';

  @override
  String get lockBodyPaused =>
      '동‍기‍화‍가 일‍시 중‍지‍됐‍어‍요. 계‍속‍하‍려‍면 Vizor 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String get lockBodySynced =>
      '동‍기‍화‍를 마‍쳤‍어‍요. 계‍속‍하‍려‍면 Vizor 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String get lockCheckingPasscode => '암‍호‍를 확‍인‍하‍는 중...';

  @override
  String get lockConfirmPasscodeSemantics => '암‍호‍를 입‍력‍해 Vizor 잠‍금 해‍제';

  @override
  String lockNavSyncing(int percent) {
    return '$percent% 동‍기‍화 중...';
  }

  @override
  String get lockSyncCompleteTitle => '동‍기‍화 완‍료';

  @override
  String get lockSyncPausedSemantics => 'Vizor 동‍기‍화‍가 일‍시 중‍지‍됨';

  @override
  String get lockSyncPausedTitle => '동‍기‍화 일‍시 중‍지‍됨';

  @override
  String get lockSyncingMessage => 'Vizor 동‍기‍화 중';

  @override
  String get lockUnlockToContinue => '계‍속‍하‍려‍면 잠‍금‍을 해‍제‍하‍세‍요';

  @override
  String get lockUnlockToContinueBody => '계‍속‍하‍려‍면 Vizor 잠‍금‍을 해‍제‍하‍세‍요';

  @override
  String get lockUnlockToContinuePausedBody =>
      '계‍속‍하‍려‍면 Vizor 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String migrationAboutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍분',
    );
    return '$_temp0';
  }

  @override
  String get migrationAnalyzingBalance => '잔‍액‍을 분‍석‍하‍는 중...';

  @override
  String get migrationAnalyzingCaption =>
      'Vizor‍가 마‍이‍그‍레‍이‍션‍의 안‍전, 프‍라‍이‍버‍시, 속‍도 사‍이‍에‍서\n최‍적‍의 균‍형‍을 찾‍고 있‍어‍요';

  @override
  String get migrationAnalyzingFindingBatches => '비‍공‍개 배‍치‍를 찾‍는 중...';

  @override
  String get migrationAnalyzingPreparingPlan =>
      '마‍이‍그‍레‍이‍션 계‍획‍을 준‍비‍하‍는 중...';

  @override
  String get migrationAnalyzingSemanticsLabel => '비‍공‍개 마‍이‍그‍레‍이‍션 계‍획 준‍비 중';

  @override
  String get migrationAnnouncementBody =>
      'Ironwood‍는 Zcash‍의 최‍신 차‍폐 풀‍이‍에‍요.\n형‍식 검‍증‍을 거‍친 최‍초‍의 풀‍로,\n최‍첨‍단 암‍호 기‍술‍을 사‍용‍해‍요.';

  @override
  String get migrationAnnouncementReleaseNote => '공‍식 릴‍리‍스 노‍트';

  @override
  String get migrationAnnouncementStart => '마‍이‍그‍레‍이‍션 시‍작';

  @override
  String get migrationBackAbout => '마‍이‍그‍레‍이‍션 소‍개';

  @override
  String get migrationBackHome => '홈‍으‍로 돌‍아‍가‍기';

  @override
  String get migrationBackHowItWorks => '마‍이‍그‍레‍이‍션 진‍행 방‍식';

  @override
  String get migrationBackOptions => '마‍이‍그‍레‍이‍션 옵‍션';

  @override
  String get migrationBatchBroadcasting => '전‍송 중...';

  @override
  String migrationBatchCardTitle(String number, String count) {
    return '배‍치 #$number (노‍트 $count‍개)';
  }

  @override
  String get migrationBatchConfirming => '확‍인 중...';

  @override
  String migrationBlockHeight(String height) {
    return '블‍록 $height';
  }

  @override
  String migrationBlocksEstimate(String blocks) {
    return '약 $blocks 블‍록';
  }

  @override
  String migrationBroadcastApproxInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍시‍간 후',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastApproxInMinutes(int count) {
    return '약 $count‍분 후';
  }

  @override
  String get migrationBroadcastConfirmed => '확‍인‍됨';

  @override
  String get migrationBroadcastDueNow => '지‍금 전‍송 예‍정';

  @override
  String migrationBroadcastInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count‍시‍간 후',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastInMinutes(int count) {
    return '$count‍분 후';
  }

  @override
  String get migrationBroadcastSubmitted => '제‍출‍됨';

  @override
  String get migrationCarouselPreparationLabel => '마‍이‍그‍레‍이‍션 준‍비 안‍내';

  @override
  String get migrationCarouselProgressLabel => '마‍이‍그‍레‍이‍션 안‍내';

  @override
  String get migrationCompleteBody =>
      '마‍이‍그‍레‍이‍션‍이 완‍료‍되‍었‍어‍요.\n평‍소‍처‍럼 자‍금‍을 사‍용‍할 수 있‍어‍요.';

  @override
  String migrationCompleteTitle(String amount) {
    return '$amount ZEC‍가\nIronwood‍에 있‍어‍요!';
  }

  @override
  String get migrationContinueMigration => '마‍이‍그‍레‍이‍션 계‍속';

  @override
  String get migrationContinuing => '계‍속‍하‍는 중...';

  @override
  String get migrationCtaStart => 'Ironwood 풀‍로 마‍이‍그‍레‍이‍션';

  @override
  String get migrationCurrentBatch => '현‍재 배‍치';

  @override
  String migrationDurationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍일',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationHalfHours(String hours) {
    return '약 $hours.5‍시‍간';
  }

  @override
  String migrationDurationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍시‍간',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍분',
    );
    return '$_temp0';
  }

  @override
  String get migrationErrorBroadcast =>
      '마‍이‍그‍레‍이‍션 거‍래‍를 전‍송‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationErrorContinue =>
      '마‍이‍그‍레‍이‍션‍을 계‍속‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationErrorKeystonePrepare => 'Keystone 서‍명‍을 준‍비‍하‍지 못‍했‍어‍요.';

  @override
  String get migrationErrorLedgerExcluded =>
      '현‍재 흐‍름‍은 일‍괄 서‍명‍이 필‍요‍해‍서 Ledger 비‍공‍개 마‍이‍그‍레‍이‍션‍은 지‍원‍하‍지 않‍아‍요.';

  @override
  String get migrationErrorPlanChanged =>
      '금‍액‍이‍나 수‍수‍료‍가 바‍뀌‍었‍어‍요. 업‍데‍이‍트‍된 내‍용‍을 확‍인‍하‍세‍요.';

  @override
  String get migrationErrorStart =>
      '마‍이‍그‍레‍이‍션‍을 시‍작‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationErrorUnlockBeforeContinue =>
      '마‍이‍그‍레‍이‍션‍을 계‍속‍하‍기 전‍에 Vizor 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String get migrationErrorUnlockBeforeStart =>
      '마‍이‍그‍레‍이‍션‍을 시‍작‍하‍기 전‍에 Vizor 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String get migrationErrorWaitForSync =>
      '동‍기‍화‍가 끝‍날 때‍까‍지 기‍다‍린 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationEstimateAfterSigning => '서‍명 후';

  @override
  String get migrationEstimateComplete => '완‍료';

  @override
  String migrationEstimateIn(String estimate) {
    return '$estimate 후';
  }

  @override
  String migrationEstimateInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍일 후',
    );
    return '$_temp0';
  }

  @override
  String migrationEstimateInHours(String hours) {
    return '약 $hours‍시‍간 후';
  }

  @override
  String migrationEstimateInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍분 후',
    );
    return '$_temp0';
  }

  @override
  String get migrationEstimateInOneHour => '약 1‍시‍간 후';

  @override
  String get migrationEstimatedArrivalTime => '도‍착 예‍상 시‍간';

  @override
  String get migrationExpectKeepRunningBody =>
      '다‍음 마‍이‍그‍레‍이‍션 거‍래‍를 보‍내‍려‍면 컴‍퓨‍터‍의 잠‍금‍이 해‍제‍되‍어 있‍고 Vizor‍가 실‍행 중‍이‍어‍야 해‍요';

  @override
  String get migrationExpectLongBody =>
      '마‍이‍그‍레‍이‍션 금‍액‍에 따‍라 Ironwood 마‍이‍그‍레‍이‍션‍에‍는 몇 시‍간‍에‍서 이‍틀 정‍도‍까‍지 걸‍릴 수 있‍어‍요.';

  @override
  String get migrationExpectLongTitle =>
      '마‍이‍그‍레‍이‍션‍에‍는 시‍간‍이 오‍래 걸‍릴 수 있‍어‍요';

  @override
  String get migrationExpectSpendBody =>
      '확‍인‍된 Ironwood 금‍액‍은 나‍머‍지 마‍이‍그‍레‍이‍션‍이 진‍행‍되‍는 동‍안‍에‍도 사‍용‍할 수 있‍어‍요.';

  @override
  String get migrationExpectSpendTitle => '자‍금‍이 도‍착‍하‍는 대‍로 쓸 수 있‍어‍요';

  @override
  String get migrationExpectTitle => '안‍내 사‍항';

  @override
  String get migrationExpectVpnBody =>
      '신‍뢰‍할 수 있‍는 VPN/네‍트‍워‍크 프‍라‍이‍버‍시 계‍층‍을 거‍쳐 마‍이‍그‍레‍이‍션‍하‍는 것‍을 권‍장‍해‍요';

  @override
  String get migrationExpectVpnTitle => '추‍가 프‍라‍이‍버‍시‍를 위‍해 VPN‍을 사‍용‍하‍세‍요';

  @override
  String get migrationFlowTitle => 'Ironwood 마‍이‍그‍레‍이‍션';

  @override
  String get migrationHowDelayedBody =>
      '추‍적 가‍능‍성‍을 줄‍이‍기 위‍해 Vizor‍가 여‍러 배‍치‍에 걸‍쳐 간‍격‍을 두‍고 천‍천‍히 나‍눠 보‍내‍요.';

  @override
  String get migrationHowDelayedTitle => '지‍연‍되‍고 무‍작‍위‍로 진‍행‍되‍는 마‍이‍그‍레‍이‍션';

  @override
  String get migrationHowFrozenBody =>
      '기‍존 차‍폐 잔‍액‍을 사‍용‍하‍려‍면 Ironwood‍로 한 번 마‍이‍그‍레‍이‍션‍해‍야 해‍요.';

  @override
  String get migrationHowFrozenTitle => 'Orchard(레‍거‍시 차‍폐) 잔‍액‍이 동‍결‍돼‍요';

  @override
  String get migrationHowPreparationBody =>
      '마‍이‍그‍레‍이‍션‍하‍기 전‍에 Vizor‍가 전‍체 잔‍액‍을 더 작‍은 노‍트(예: 0.1 ZEC / 1 ZEC / 5 ZEC)로 나‍눠‍요.';

  @override
  String get migrationHowPreparationTitle => '마‍이‍그‍레‍이‍션 전 준‍비';

  @override
  String migrationHowStepLabel(String number) {
    return '$number‍단‍계';
  }

  @override
  String migrationHowStepSemanticsCurrent(
    String number,
    String total,
    String title,
    String body,
  ) {
    return '마‍이‍그‍레‍이‍션 $total‍단‍계 중 $number‍단‍계. $title. $body';
  }

  @override
  String migrationHowStepSemanticsShow(String number, String total) {
    return '마‍이‍그‍레‍이‍션 $total‍단‍계 중 $number‍단‍계 보‍기';
  }

  @override
  String get migrationHowTitle => '마‍이‍그‍레‍이‍션 진‍행 방‍식';

  @override
  String get migrationImmediateAuthoriseAnyway => '그‍래‍도 승‍인';

  @override
  String get migrationImmediateAuthorising => '승‍인‍하‍는 중…';

  @override
  String get migrationImmediateAuthorisingSemantics => '마‍이‍그‍레‍이‍션 승‍인‍하‍는 중';

  @override
  String get migrationImmediateConsiderOther => '다‍른 옵‍션 보‍기';

  @override
  String get migrationImmediateFees => '수‍수‍료(예‍상)';

  @override
  String get migrationImmediateNoBalance =>
      '즉‍시 마‍이‍그‍레‍이‍션‍에 사‍용‍할 수 있‍는 Orchard 잔‍액‍이 없‍어‍요.';

  @override
  String get migrationImmediatePlanFailed =>
      '즉‍시 마‍이‍그‍레‍이‍션 계‍획‍을 계‍산‍하‍지 못‍했‍어‍요. 동‍기‍화‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationImmediateRetryCalculation => '계‍산 다‍시 시‍도';

  @override
  String get migrationImmediateReviewTitle => '마‍이‍그‍레‍이‍션 계‍획 검‍토';

  @override
  String migrationImmediateTradeoffBody(String amount, String highlight) {
    return '눈‍에 보‍이‍는 한 번‍의 단‍계‍로 넘‍어‍가‍므‍로 금‍액($amount)과 시‍점‍이 $highlight.';
  }

  @override
  String get migrationImmediateTradeoffHighlight => '내 지‍갑‍과 더 쉽‍게 연‍결‍돼‍요';

  @override
  String get migrationImmediateTradeoffLedger =>
      '\nLedger 계‍정‍에‍서‍는 비‍공‍개 마‍이‍그‍레‍이‍션‍을 사‍용‍할 수 없‍어‍요.';

  @override
  String get migrationImmediateTradeoffPrivate =>
      '\n비‍공‍개 마‍이‍그‍레‍이‍션 옵‍션‍을 선‍택‍해 보‍세‍요.';

  @override
  String get migrationImmediateTradeoffTitle => '프‍라‍이‍버‍시 절‍충';

  @override
  String get migrationImmediateUnavailable => '사‍용‍할 수 없‍음';

  @override
  String migrationInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count‍분 후',
    );
    return '$_temp0';
  }

  @override
  String get migrationIntroAnnouncement => '공‍식 발‍표';

  @override
  String get migrationIntroBadge => 'Zcash 네‍트‍워‍크 업‍그‍레‍이‍드';

  @override
  String migrationIntroBody(String amount) {
    return '현‍재 $amount ZEC‍가 Orchard‍에 있‍어‍요.\n이 자‍금‍을 계‍속 차‍폐 결‍제‍에 쓰‍려‍면 Ironwood‍로 옮‍겨‍야 해‍요. 자‍금‍이 이‍동‍하‍기 전‍에 마‍이‍그‍레‍이‍션 계‍획‍을 검‍토‍하‍게 돼‍요.';
  }

  @override
  String get migrationIntroTagline => 'Zcash‍를 위‍한 새‍로‍운 차‍폐 풀.';

  @override
  String get migrationKeystoneApplyingSignature =>
      'Keystone 서‍명‍을 적‍용‍하‍는 중‍이‍에‍요.';

  @override
  String get migrationKeystoneApplyingToPlan =>
      'Keystone 서‍명‍을 마‍이‍그‍레‍이‍션 계‍획‍에 적‍용‍하‍는 중‍이‍에‍요.';

  @override
  String get migrationKeystoneBackToReview => '검‍토‍로 돌‍아‍가‍기';

  @override
  String get migrationKeystoneBackToStatus => '상‍태‍로 돌‍아‍가‍기';

  @override
  String get migrationKeystoneBeginSigning => '서‍명 시‍작';

  @override
  String get migrationKeystoneCameraAccess =>
      '서‍명‍된 Keystone QR‍을 스‍캔‍하‍려‍면 카‍메‍라 접‍근‍을 허‍용‍하‍세‍요.';

  @override
  String get migrationKeystoneCameraOnly =>
      'Keystone 마‍이‍그‍레‍이‍션 서‍명‍은 카‍메‍라 QR 스‍캔‍만 지‍원‍해‍요. 카‍메‍라‍를 연‍결‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationKeystoneCancelFailed =>
      '서‍명 요‍청‍을 취‍소‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationKeystoneClickToEnlarge => 'QR‍을 클‍릭‍해 확‍대';

  @override
  String get migrationKeystoneConfirmTitle => 'Keystone‍으‍로 마‍이‍그‍레‍이‍션 확‍인';

  @override
  String get migrationKeystoneEnlargeQr => 'Keystone 요‍청 QR 확‍대';

  @override
  String get migrationKeystoneEnlargedQr => '확‍대‍된 Keystone 요‍청 QR';

  @override
  String get migrationKeystoneFirmwareUpdate =>
      'Ironwood 마‍이‍그‍레‍이‍션‍에 서‍명‍하‍려‍면 Keystone 펌‍웨‍어‍를 업‍데‍이‍트‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationKeystoneMobileTitle => 'Keystone 마‍이‍그‍레‍이‍션';

  @override
  String get migrationKeystoneNotKeystone =>
      '이 마‍이‍그‍레‍이‍션‍에 서‍명‍하‍려‍면 Keystone 계‍정‍을 사‍용‍하‍세‍요.';

  @override
  String get migrationKeystoneOpenSignedQr =>
      'Keystone‍에‍서 서‍명‍된 마‍이‍그‍레‍이‍션 QR‍을 연 뒤 다‍시 스‍캔‍하‍세‍요.';

  @override
  String get migrationKeystonePlanBody =>
      '각 회‍차‍마‍다 움‍직‍이‍는 요‍청 QR 하‍나‍와 서‍명‍된 응‍답 QR 하‍나‍를 사‍용‍해‍요.';

  @override
  String get migrationKeystonePlanTitle => 'Keystone 서‍명 계‍획';

  @override
  String get migrationKeystonePrepareFailed =>
      'Keystone 서‍명‍을 준‍비‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationKeystonePreparingQr => 'QR 코‍드 준‍비 중...';

  @override
  String get migrationKeystoneProofFailed =>
      'Vizor‍가 로‍컬 증‍명‍을 준‍비‍하‍지 못‍했‍어‍요. 돌‍아‍가‍서 이 요‍청‍을 다‍시 준‍비‍하‍세‍요.';

  @override
  String get migrationKeystoneProofWaiting =>
      '서‍명‍을 받‍았‍어‍요. Vizor‍가 아‍직 로‍컬 증‍명‍을 준‍비‍하‍는 중‍이‍에‍요. 이 화‍면‍을 열‍어 두‍세‍요.';

  @override
  String migrationKeystoneProofWaitingProgress(String ready, String total) {
    return '서‍명‍을 받‍았‍어‍요. Vizor‍가 아‍직 로‍컬 증‍명‍을 준‍비‍하‍는 중‍이‍에‍요($ready/$total). 이 화‍면‍을 열‍어 두‍세‍요.';
  }

  @override
  String get migrationKeystoneProofsPreparing => '로‍컬 증‍명 준‍비 중';

  @override
  String get migrationKeystoneProofsPreparingEllipsis => '로‍컬 증‍명 준‍비 중...';

  @override
  String migrationKeystoneProofsProgress(String ready, String total) {
    return '로‍컬 증‍명 준‍비 중 $ready/$total';
  }

  @override
  String get migrationKeystoneQrBodyCombined =>
      'Keystone‍으‍로 이 요‍청‍을 스‍캔‍해 준‍비 거‍래‍와 마‍이‍그‍레‍이‍션 배‍치‍에 함‍께 서‍명‍하‍세‍요.';

  @override
  String get migrationKeystoneQrBodyImmediate =>
      'Keystone 지‍갑‍으‍로 QR 코‍드‍를 스‍캔‍해 마‍이‍그‍레‍이‍션‍을 확‍인‍하‍세‍요.';

  @override
  String get migrationKeystoneQrBodyRound =>
      'Keystone‍으‍로 이 요‍청 QR‍을 스‍캔‍하‍세‍요. 완‍료‍되‍면 Keystone‍에 서‍명‍된 새 QR‍이 표‍시‍돼‍요.';

  @override
  String get migrationKeystoneRequestCancelled =>
      '이 서‍명 요‍청‍이 취‍소‍되‍었‍어‍요. 다‍시 준‍비‍하‍세‍요.';

  @override
  String get migrationKeystoneRequestExpired =>
      '이 Keystone 서‍명 요‍청‍이 만‍료‍되‍었‍어‍요. 다‍시 준‍비‍하‍세‍요.';

  @override
  String get migrationKeystoneRequestQr => '요‍청 QR';

  @override
  String get migrationKeystoneRequestUnusable =>
      '이 Keystone 서‍명 요‍청‍은 더 이‍상 사‍용‍할 수 없‍어‍요. 다‍시 준‍비‍하‍세‍요.';

  @override
  String migrationKeystoneRound(String current, String total) {
    return '$total‍회 중 $current‍회‍차';
  }

  @override
  String migrationKeystoneRoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'QR 서‍명 $count‍회',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneScanIssuesBody =>
      'Keystone Cypherpunk 펌‍웨‍어‍의 새 버‍전‍이 있‍을 수 있‍어‍요. 최‍신 버‍전‍인‍지 확‍인‍하‍세‍요.';

  @override
  String get migrationKeystoneScanIssuesConfirm => '네, 확‍인‍할‍게‍요';

  @override
  String get migrationKeystoneScanIssuesTitle => 'QR 코‍드 스‍캔‍에 문‍제‍가 있‍나‍요?';

  @override
  String get migrationKeystoneScanNewQr =>
      'Keystone‍에 표‍시‍된 새 서‍명 QR‍을 스‍캔‍하‍세‍요.';

  @override
  String get migrationKeystoneScanRequest => 'Keystone‍으‍로 요‍청 스‍캔';

  @override
  String get migrationKeystoneScanSignature => 'Keystone 서‍명 스‍캔';

  @override
  String get migrationKeystoneSignBatch => 'Ironwood 배‍치 서‍명';

  @override
  String get migrationKeystoneSignMigration => '마‍이‍그‍레‍이‍션 서‍명';

  @override
  String get migrationKeystoneSignPrivateSplit => '비‍공‍개 분‍할 서‍명';

  @override
  String migrationKeystoneSignsAll(String transactions) {
    return '$transactions 서‍명';
  }

  @override
  String migrationKeystoneSignsSome(String count, String transactions) {
    return '전‍체 $transactions 중 $count‍건 서‍명';
  }

  @override
  String get migrationKeystoneToolbarReview => '마‍이‍그‍레‍이‍션 검‍토';

  @override
  String get migrationKeystoneToolbarStatus => '마‍이‍그‍레‍이‍션 상‍태';

  @override
  String migrationKeystoneTransactionTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '총 거‍래 $count‍건',
    );
    return '$_temp0';
  }

  @override
  String migrationKeystoneTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '거‍래 $count‍건',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneTryAfterSync => '동‍기‍화‍가 끝‍난 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationKeystoneUnavailableTitle =>
      'Keystone 서‍명‍을 사‍용‍할 수 없‍어‍요';

  @override
  String get migrationKeystoneUnlockFirst =>
      '마‍이‍그‍레‍이‍션‍에 서‍명‍하‍기 전‍에 Vizor 잠‍금‍을 해‍제‍하‍세‍요.';

  @override
  String get migrationKeystoneWaitingForProofsLong =>
      '서‍명‍을 받‍았‍어‍요. 로‍컬 증‍명‍이 준‍비‍되‍면 Vizor‍가 이‍어‍서 진‍행‍해‍요.';

  @override
  String get migrationKeystoneWaitingForProofsShort =>
      '서‍명‍을 받‍았‍어‍요. 로‍컬 증‍명‍을 기‍다‍리‍는 중‍이‍에‍요.';

  @override
  String get migrationKeystoneWrongRound =>
      '이 서‍명‍된 QR‍은 다‍른 회‍차‍의 것‍이‍에‍요. 돌‍아‍가‍서 현‍재 요‍청‍을 Keystone‍으‍로 스‍캔‍한 뒤 새‍로 서‍명‍된 QR‍을 스‍캔‍하‍세‍요.';

  @override
  String get migrationLedgerBroadcast => '마‍이‍그‍레‍이‍션 거‍래‍를 전‍송‍하‍지 못‍했‍어‍요.';

  @override
  String get migrationLedgerConnect =>
      'Ledger‍를 연‍결‍하‍고 잠‍금‍을 해‍제‍한 뒤 Zcash 앱‍을 여‍세‍요.';

  @override
  String get migrationLedgerFailed => 'Ledger 마‍이‍그‍레‍이‍션‍을 완‍료‍하‍지 못‍했‍어‍요.';

  @override
  String get migrationLedgerFailedTitle => 'Ledger 마‍이‍그‍레‍이‍션 실‍패';

  @override
  String get migrationLedgerPlanChanged =>
      '금‍액‍이‍나 수‍수‍료‍가 바‍뀌‍었‍어‍요. 돌‍아‍가‍서 업‍데‍이‍트‍된 계‍획‍을 검‍토‍하‍세‍요.';

  @override
  String get migrationLedgerProofs =>
      'Vizor‍가 마‍이‍그‍레‍이‍션 증‍명 준‍비‍를 마‍치‍지 못‍했‍어‍요.';

  @override
  String get migrationLedgerRejected =>
      'Ledger‍에‍서 마‍이‍그‍레‍이‍션 거‍래‍가 거‍부‍되‍었‍어‍요.';

  @override
  String get migrationLedgerTitle => 'Ledger‍로 마‍이‍그‍레‍이‍션';

  @override
  String migrationLeftToTransfer(String amount) {
    return '남‍은 금‍액: $amount';
  }

  @override
  String get migrationManageCancelling => '취‍소‍하‍는 중...';

  @override
  String get migrationManageCannotCancel =>
      '이 마‍이‍그‍레‍이‍션‍은 더 이‍상 취‍소‍할 수 없‍어‍요.';

  @override
  String get migrationManageConfirm => '확‍인';

  @override
  String get migrationManageImmediateBullet1 =>
      '남‍은 분‍할 노‍트‍는 즉‍시 마‍이‍그‍레‍이‍션‍으‍로 처‍리‍되‍어 추‍적 가‍능‍성‍이 약‍간 높‍아‍져‍요';

  @override
  String get migrationManageImmediateBullet2 =>
      '이‍미 전‍송‍된 거‍래‍는 되‍돌‍려‍지‍지 않‍아‍요';

  @override
  String get migrationManageImmediateBullet3 =>
      '즉‍시 마‍이‍그‍레‍이‍션‍은 되‍돌‍릴 방‍법‍이 없‍어‍요';

  @override
  String get migrationManageImmediateIntro => '남‍은 마‍이‍그‍레‍이‍션‍을 즉‍시 처‍리‍해‍요.';

  @override
  String get migrationManageNoBalance =>
      '마‍이‍그‍레‍이‍션‍할 Orchard 잔‍액‍이 남‍아 있‍지 않‍아‍요.';

  @override
  String get migrationManageStop => '마‍이‍그‍레‍이‍션 중‍단';

  @override
  String get migrationManageStopBody =>
      '예‍약‍된 나‍머‍지 마‍이‍그‍레‍이‍션 거‍래‍가 취‍소‍돼‍요. 홈 화‍면‍에‍서 마‍이‍그‍레‍이‍션‍을 다‍시 시‍작‍할 수 있‍어‍요.';

  @override
  String get migrationManageStopTitle => '정‍말 중‍단‍할‍까‍요?';

  @override
  String get migrationManageStopping => '중‍단‍하‍는 중...';

  @override
  String get migrationManageSwitchImmediate => '즉‍시 마‍이‍그‍레‍이‍션‍으‍로 전‍환';

  @override
  String get migrationManageTitle => '마‍이‍그‍레‍이‍션 관‍리';

  @override
  String get migrationManageUpdateFailed =>
      '마‍이‍그‍레‍이‍션‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationMobileActionAllTransactions => '모‍든 거‍래';

  @override
  String migrationMobileActionBatch(int number) {
    return '배‍치 #$number';
  }

  @override
  String get migrationMobileActionInProgress => '마‍이‍그‍레‍이‍션 작‍업 진‍행 중';

  @override
  String get migrationMobileActionNeedSignature => '서‍명‍이 필‍요‍한 거‍래';

  @override
  String migrationMobileActionPrepareBatch(int number) {
    return '배‍치 #$number 준‍비';
  }

  @override
  String migrationMobileActionPreparingBatch(int number) {
    return '배‍치 #$number 준‍비 중...';
  }

  @override
  String get migrationMobileActionResign => '마‍이‍그‍레‍이‍션 거‍래 다‍시 서‍명';

  @override
  String get migrationMobileActionSign => '마‍이‍그‍레‍이‍션 거‍래 서‍명';

  @override
  String migrationMobileActionSignBatch(int number) {
    return '배‍치 #$number 서‍명';
  }

  @override
  String get migrationMobileActionSubmitScheduled => '예‍약‍된 거‍래 제‍출';

  @override
  String get migrationMobileActionSubmittingScheduled =>
      '예‍약‍된 거‍래‍를 제‍출‍하‍는 중...';

  @override
  String get migrationMobileAnnouncementBody =>
      'Zcash‍의 최‍신 차‍폐 풀‍로, 최‍첨‍단 암‍호‍학‍과 형‍식 검‍증‍을 갖‍췄‍어‍요.\n\n차‍폐 잔‍액‍은 Ironwood‍로 한 번 마‍이‍그‍레‍이‍션‍해‍야 해‍요.';

  @override
  String get migrationMobileAnnouncementOfficial => '공‍식 발‍표';

  @override
  String get migrationMobileAnnouncementUpgrade => 'Ironwood‍로 업‍그‍레‍이‍드';

  @override
  String get migrationMobileAttentionContinueTitle => '마‍이‍그‍레‍이‍션‍을 계‍속‍하‍세‍요';

  @override
  String get migrationMobileAttentionLateTitle =>
      '마‍이‍그‍레‍이‍션 거‍래‍를 확‍인‍해‍야 해‍요';

  @override
  String get migrationMobileAttentionLater => '나‍중‍에 할‍게‍요';

  @override
  String get migrationMobileAttentionOpen => '마‍이‍그‍레‍이‍션 페‍이‍지‍로 이‍동';

  @override
  String get migrationMobileAttentionProofTitle =>
      '다‍음 마‍이‍그‍레‍이‍션 배‍치‍가 준‍비‍됐‍어‍요';

  @override
  String migrationMobileAttentionSignatureSheet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노‍트 $count‍개‍에 서‍명‍할 준‍비‍가 됐‍어‍요',
    );
    return '$_temp0';
  }

  @override
  String get migrationMobileBackToHome => '홈‍으‍로 돌‍아‍가‍기';

  @override
  String get migrationMobileBannerLate => '마‍이‍그‍레‍이‍션 확‍인‍이 필‍요‍해‍요';

  @override
  String get migrationMobileBannerProof => '다‍음 마‍이‍그‍레‍이‍션 배‍치‍가 준‍비‍됐‍어‍요';

  @override
  String migrationMobileBannerRemaining(String amount) {
    return '$amount ZEC 마‍이‍그‍레‍이‍션 중';
  }

  @override
  String migrationMobileBannerSignature(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노‍트 $count‍개‍에 서‍명‍할 수 있‍어‍요',
    );
    return '$_temp0';
  }

  @override
  String migrationMobileBatchProgress(int completed, int total) {
    return '배‍치 $completed/$total';
  }

  @override
  String get migrationMobileCanLeave => '이 화‍면‍을 나‍가‍도 돼‍요.';

  @override
  String get migrationMobileCompleteBody =>
      '마‍이‍그‍레‍이‍션‍이 성‍공‍적‍으‍로 끝‍났‍어‍요. 이‍제 평‍소‍처‍럼 자‍금‍을 사‍용‍할 수 있‍어‍요.';

  @override
  String migrationMobileCompleteHeading(String amount) {
    return '$amount‍가\nIronwood‍에\n도‍착‍했‍어‍요!';
  }

  @override
  String get migrationMobileCompleteTitle => '모‍든 준‍비‍가 끝‍났‍어‍요!';

  @override
  String get migrationMobileContinueThisError =>
      '이 마‍이‍그‍레‍이‍션‍을 계‍속‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationMobileCredentialsRestore =>
      '계‍속‍하‍기 전‍에 마‍이‍그‍레‍이‍션 자‍격 증‍명‍을 복‍원‍해‍야 해‍요.';

  @override
  String get migrationMobileFastPlanError =>
      '즉‍시 마‍이‍그‍레‍이‍션 수‍수‍료‍를 계‍산‍하‍지 못‍했‍어‍요. 동‍기‍화‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationMobileFastPlanUnavailable => '사‍용‍할 수 없‍음';

  @override
  String get migrationMobileFastPrivacyConsiderPrivate =>
      '비‍공‍개 마‍이‍그‍레‍이‍션 옵‍션‍을 선‍택‍해 보‍세‍요.';

  @override
  String get migrationMobileFastPrivacyLedger =>
      'Ledger 계‍정‍에‍서‍는 비‍공‍개 마‍이‍그‍레‍이‍션‍을 사‍용‍할 수 없‍어‍요.';

  @override
  String migrationMobileFastSubmittedBody(String amount) {
    return '$amount‍를 Ironwood‍로 보‍내‍는 중‍이‍에‍요.';
  }

  @override
  String get migrationMobileFastSubmittedNotTracked =>
      '네‍트‍워‍크‍가 이 마‍이‍그‍레‍이‍션‍을 받‍았‍지‍만 Vizor‍가 이 기‍기‍에 기‍록‍하‍지 못‍했‍어‍요. 동‍기‍화‍하‍면 복‍구‍돼‍요.';

  @override
  String get migrationMobileFastSubmittedTitle => '마‍이‍그‍레‍이‍션‍을 제‍출‍했‍어‍요';

  @override
  String get migrationMobileFastSubmittedUnconfirmed =>
      '네‍트‍워‍크‍가 이 마‍이‍그‍레‍이‍션‍을 받‍았‍는‍지 Vizor‍가 확‍인‍하‍지 못‍했‍어‍요. 이‍미 네‍트‍워‍크‍에 있‍을 수 있‍으‍니 동‍기‍화‍로 결‍과‍를 확‍인‍할 때‍까‍지 다‍시 시‍작‍하‍지 마‍세‍요.';

  @override
  String get migrationMobileFastTitle => '빠‍른 마‍이‍그‍레‍이‍션';

  @override
  String get migrationMobileHowItWorksNavTitle => '안‍내';

  @override
  String migrationMobileIntroBody(String amount) {
    return '현‍재 $amount ZEC‍가 Orchard‍에 있‍어‍요. 이 자‍금‍을 계‍속 차‍폐 결‍제‍에 쓰‍려‍면 Ironwood‍로 옮‍겨‍야 해‍요. 자‍금‍을 옮‍기‍기 전‍에 마‍이‍그‍레‍이‍션 계‍획‍을 먼‍저 확‍인‍할 수 있‍어‍요.';
  }

  @override
  String get migrationMobileIntroReleaseNote => '공‍식 릴‍리‍스 노‍트';

  @override
  String get migrationMobileIntroTitle => 'Zcash 네‍트‍워‍크 업‍데‍이‍트';

  @override
  String get migrationMobileKeepOpenUnlocked =>
      'Vizor‍를 열‍어 두‍고 잠‍금‍을 해‍제‍한 상‍태‍로 유‍지‍하‍세‍요.';

  @override
  String get migrationMobileKeepRunning =>
      '단, Vizor‍는 열‍어 둔 채 계‍속 실‍행‍해 두‍세‍요.';

  @override
  String get migrationMobileKeystoneConfirmPrepSemantics =>
      'Keystone‍으‍로 마‍이‍그‍레‍이‍션 준‍비 확‍인';

  @override
  String get migrationMobileKeystoneConfirmTransferSemantics =>
      'Keystone‍으‍로 마‍이‍그‍레‍이‍션 전‍송 확‍인';

  @override
  String get migrationMobileKeystoneHelpPrompt =>
      'Keystone‍에‍서 QR‍을 탭‍한 다‍음,\n이 QR 코‍드‍를 스‍캔‍하‍세‍요.';

  @override
  String get migrationMobileKeystoneHelpSemantics => 'Keystone QR 스‍캔 도‍움‍말';

  @override
  String get migrationMobileKeystoneLoadingQrSemantics => 'QR 코‍드 불‍러‍오‍는 중';

  @override
  String get migrationMobileKeystoneReconnect =>
      '이 마‍이‍그‍레‍이‍션‍을 계‍속‍하‍려‍면 Keystone 계‍정‍을 다‍시 연‍결‍하‍거‍나 다‍시 가‍져‍오‍세‍요.';

  @override
  String get migrationMobileKeystoneRequestQrSemantics => 'Keystone 요‍청 QR 코‍드';

  @override
  String get migrationMobileKeystoneRequiredStatus => 'Keystone 계‍정 필‍요';

  @override
  String get migrationMobileKeystoneResignMessage =>
      '계‍속‍하‍려‍면 다‍시 만‍든 마‍이‍그‍레‍이‍션 거‍래‍를 Keystone‍으‍로 서‍명‍하‍세‍요.';

  @override
  String get migrationMobileKeystoneScanCaption =>
      'Keystone‍의 QR 코‍드‍를\n스‍캔‍해 확‍인‍하‍세‍요';

  @override
  String get migrationMobileKeystoneScanPrepSemantics =>
      'Keystone‍에‍서 서‍명‍된 마‍이‍그‍레‍이‍션 준‍비‍를 스‍캔‍하‍세‍요';

  @override
  String get migrationMobileKeystoneScanProgress => '스‍캔 진‍행‍률';

  @override
  String get migrationMobileKeystoneScanTransferSemantics =>
      'Keystone‍에‍서 서‍명‍된 마‍이‍그‍레‍이‍션 전‍송‍을 스‍캔‍하‍세‍요';

  @override
  String get migrationMobileManageCheckError =>
      '마‍이‍그‍레‍이‍션 상‍태‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationMobileManageChecking => '마‍이‍그‍레‍이‍션 상‍태‍를 확‍인‍하‍는 중...';

  @override
  String get migrationMobileManageNoRevert =>
      '이‍미 전‍송‍된 거‍래‍는 되‍돌‍려‍지‍지 않‍아‍요.';

  @override
  String get migrationMobileManageRetryStatus => '상‍태 다‍시 확‍인';

  @override
  String get migrationMobileManageStopAction => '마‍이‍그‍레‍이‍션 중‍단';

  @override
  String get migrationMobileManageStopBody =>
      '남‍은 마‍이‍그‍레‍이‍션‍을 중‍단‍해‍요. 이‍미 마‍이‍그‍레‍이‍션‍된 자‍금‍은 Ironwood‍에 그‍대‍로 있‍어‍요.';

  @override
  String get migrationMobileManageStopTitle => '마‍이‍그‍레‍이‍션‍을 중‍단‍할‍까‍요?';

  @override
  String get migrationMobileManageSwitchAction => '빠‍른 마‍이‍그‍레‍이‍션‍으‍로 전‍환';

  @override
  String get migrationMobileManageSwitchBody =>
      '비‍공‍개 일‍정‍을 중‍단‍하‍고 남‍은 잔‍액‍에 대‍한 빠‍른 마‍이‍그‍레‍이‍션‍을 검‍토‍해‍요. 빠‍른 마‍이‍그‍레‍이‍션‍은 추‍적 가‍능‍성‍을 높‍이‍며, 한 번 제‍출‍하‍면 되‍돌‍릴 수 없‍어‍요.';

  @override
  String get migrationMobileManageSwitchTitle =>
      '빠‍른 마‍이‍그‍레‍이‍션‍으‍로 전‍환‍할‍까‍요?';

  @override
  String get migrationMobileManageTitle => '마‍이‍그‍레‍이‍션 관‍리';

  @override
  String get migrationMobileManageUnavailable =>
      '이 마‍이‍그‍레‍이‍션‍은 더 이‍상 관‍리‍할 수 없‍어‍요.';

  @override
  String get migrationMobileManageWaitingBroadcast =>
      '진‍행 중‍인 전‍송‍이 끝‍나‍기‍를 기‍다‍린 뒤 남‍은 마‍이‍그‍레‍이‍션‍을 중‍단‍해‍요.';

  @override
  String get migrationMobileNextConfirmationsArriving =>
      '확‍인‍이 아‍직 도‍착‍하‍는 중‍이‍에‍요.\nVizor‍를 나‍갔‍다‍가 나‍중‍에 다‍시 확‍인‍해‍도 돼‍요.';

  @override
  String migrationMobileNextExpectedIn(String timing) {
    return '다‍음 마‍이‍그‍레‍이‍션 단‍계‍는\n$timing 예‍정‍이‍에‍요.';
  }

  @override
  String migrationMobileNextNotificationsOffBlock(int height, String timing) {
    return '알‍림‍이 꺼‍져 있‍어‍요. $height 블‍록($timing) 이‍후‍에 Vizor‍를 열‍어 다‍음 마‍이‍그‍레‍이‍션 배‍치‍를 승‍인‍하‍세‍요.';
  }

  @override
  String get migrationMobileNextNotificationsOffNoTiming =>
      '알‍림‍이 꺼‍져 있‍어‍요. 시‍간 정‍보‍가 나‍오‍면 Vizor‍를 다‍시 열‍어 다‍음 마‍이‍그‍레‍이‍션 배‍치‍를 승‍인‍하‍세‍요.';

  @override
  String get migrationMobileNextNotificationsOffOpen =>
      '알‍림‍이 꺼‍져 있‍어‍요. 계‍속‍하‍려‍면 Vizor‍를 다‍시 여‍세‍요.';

  @override
  String get migrationMobileNextNotificationsOnLeave =>
      '알‍림‍이 켜‍져 있‍어‍요. Vizor‍를 나‍갔‍다‍가 나‍중‍에 다‍시 확‍인‍해‍도 돼‍요.';

  @override
  String get migrationMobileNextOnTheWay => '다‍음 마‍이‍그‍레‍이‍션 단‍계‍가 곧 시‍작‍돼‍요.';

  @override
  String get migrationMobileNextReadyAuto =>
      '예‍약‍된 거‍래‍를 자‍동‍으‍로 제‍출‍할 준‍비‍가 됐‍어‍요. Vizor‍를 열‍어 두‍세‍요.';

  @override
  String get migrationMobileNextStepReady =>
      '다‍음 마‍이‍그‍레‍이‍션 단‍계‍가 준‍비‍됐‍어‍요. 계‍속‍하‍려‍면 Vizor‍를 열‍어 두‍세‍요.';

  @override
  String migrationMobileNextTimingUntil(String timing) {
    return '다‍음 마‍이‍그‍레‍이‍션 단‍계‍는 $timing 시‍작‍돼‍요.\n알‍림‍이 켜‍져 있‍어‍요. Vizor‍를 나‍갔‍다‍가 나‍중‍에 다‍시 확‍인‍해‍도 돼‍요.';
  }

  @override
  String get migrationMobileNextTorDisclosure =>
      'Vizor‍가 닫‍혀 있‍는 동‍안‍에‍는 마‍이‍그‍레‍이‍션‍이 직‍접 연‍결‍로 계‍속‍돼‍요.';

  @override
  String get migrationMobileNotifyAllow => '알‍림 허‍용';

  @override
  String get migrationMobileNotifyBody =>
      '일‍부 마‍이‍그‍레‍이‍션 단‍계‍는 승‍인‍이 필‍요‍해‍요. 때‍가 되‍면 알‍려 드‍릴 테‍니 빠‍르‍게 응‍답‍해 불‍필‍요‍한 지‍연‍을 피‍하‍세‍요.';

  @override
  String get migrationMobileNotifyConfirmBody =>
      '알‍림‍이 없‍으‍면 Vizor‍를 주‍기‍적‍으‍로 열‍어 준‍비‍된 다‍음 마‍이‍그‍레‍이‍션 단‍계‍를 직‍접 승‍인‍해‍야 해‍요.';

  @override
  String get migrationMobileNotifyConfirmNote =>
      '그‍렇‍지 않‍으‍면 마‍이‍그‍레‍이‍션‍에 더 오‍래 걸‍릴 수 있‍어‍요.';

  @override
  String get migrationMobileNotifyConfirmTitle => '알‍림 없‍이 계‍속‍할‍까‍요?';

  @override
  String get migrationMobileNotifyContinueWithout => '알‍림 없‍이 계‍속';

  @override
  String get migrationMobileNotifyHeading => '마‍이‍그‍레‍이‍션 일‍정‍을 놓‍치‍지 마‍세‍요';

  @override
  String get migrationMobileNotifyStillOff =>
      '알‍림‍이 아‍직 꺼‍져 있‍어‍요. 설‍정‍에‍서 허‍용‍하‍거‍나 알‍림 없‍이 계‍속‍하‍세‍요.';

  @override
  String get migrationMobileNotifyTitle => '알‍림 켜‍기';

  @override
  String migrationMobileOptionImmediateBody(String estimate) {
    return '전‍체 잔‍액‍을 한 번‍에 마‍이‍그‍레‍이‍션‍해‍요. 빠‍르‍지‍만($estimate) 프‍라‍이‍버‍시‍는 낮‍아‍요.';
  }

  @override
  String get migrationMobileOptionPrivateBody =>
      '거‍래‍를 여‍러 부‍분‍으‍로 나‍눠 추‍적 가‍능‍성‍을 최‍소‍화‍하‍지‍만 몇 시‍간‍에‍서 며‍칠‍이 걸‍려‍요.';

  @override
  String get migrationMobileOptionPrivateUnavailableAndroid =>
      'Android‍에‍서‍는 사‍용‍할 수 없‍어‍요.';

  @override
  String get migrationMobileOptionsNavTitle => '마‍이‍그‍레‍이‍션 방‍법';

  @override
  String get migrationMobileOptionsOpenError =>
      '마‍이‍그‍레‍이‍션 준‍비‍를 열‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationMobileOptionsSubtitleAndroid =>
      'Android‍에‍서‍는 비‍공‍개 마‍이‍그‍레‍이‍션‍을 일‍시‍적‍으‍로 사‍용‍할 수 없‍어‍요. 계‍속‍하‍려‍면 즉‍시 마‍이‍그‍레‍이‍션‍을 선‍택‍하‍세‍요.';

  @override
  String migrationMobileOptionsSubtitleAndroidRest(String amount) {
    return '$amount ZEC‍가 아‍직 Orchard‍에 있‍어‍요. Android‍에‍서‍는 비‍공‍개 마‍이‍그‍레‍이‍션‍을 일‍시‍적‍으‍로 사‍용‍할 수 없‍어‍요. 계‍속‍하‍려‍면 즉‍시 마‍이‍그‍레‍이‍션‍을 선‍택‍하‍세‍요.';
  }

  @override
  String get migrationMobileOptionsSubtitleLedger =>
      'Ledger 계‍정‍에‍서‍는 비‍공‍개 마‍이‍그‍레‍이‍션‍을 사‍용‍할 수 없‍어‍요. 계‍속‍하‍려‍면 즉‍시 마‍이‍그‍레‍이‍션‍을 선‍택‍하‍세‍요.';

  @override
  String migrationMobileOptionsSubtitleLedgerRest(String amount) {
    return '$amount ZEC‍가 아‍직 Orchard‍에 있‍어‍요. Ledger 계‍정‍에‍서‍는 비‍공‍개 마‍이‍그‍레‍이‍션‍을 사‍용‍할 수 없‍어‍요. 계‍속‍하‍려‍면 즉‍시 마‍이‍그‍레‍이‍션‍을 선‍택‍하‍세‍요.';
  }

  @override
  String get migrationMobileOptionsTitle => '마‍이‍그‍레‍이‍션 방‍법 선‍택';

  @override
  String get migrationMobileOptionsTitleRest => '나‍머‍지 마‍이‍그‍레‍이‍션 방‍법';

  @override
  String migrationMobilePartConfirming(int count, int target) {
    return '확‍인 중 · $count/$target';
  }

  @override
  String migrationMobilePartLabel(int number) {
    return '파‍트 $number';
  }

  @override
  String migrationMobilePartProgress(String part, int percent) {
    return '$part 진‍행‍률 $percent%';
  }

  @override
  String get migrationMobilePartQueued => '대‍기 중';

  @override
  String get migrationMobilePartsPlaceholder =>
      '거‍래‍가 준‍비‍되‍면 마‍이‍그‍레‍이‍션 파‍트‍가 여‍기‍에 표‍시‍돼‍요.';

  @override
  String get migrationMobilePrepAdvancing =>
      '다‍음 거‍래‍를 준‍비‍하‍고 있‍어‍요. Vizor‍를 열‍어 두‍세‍요.';

  @override
  String get migrationMobilePrepBackgroundTracking =>
      '백‍그‍라‍운‍드‍에‍서 확‍인‍하‍는 중‍이‍에‍요. Vizor‍를 닫‍아‍도 돼‍요.';

  @override
  String get migrationMobilePrepBackgroundUnsupported =>
      '이 기‍기‍는 백‍그‍라‍운‍드‍에‍서 확‍인‍할 수 없‍어‍요. Vizor‍를 열‍어 두‍세‍요.';

  @override
  String get migrationMobilePrepContinue => '준‍비 계‍속';

  @override
  String get migrationMobilePrepContinueKeystone => 'Keystone‍으‍로 계‍속';

  @override
  String get migrationMobilePrepDoneBody =>
      '준‍비‍가 완‍료‍됐‍어‍요. 마‍이‍그‍레‍이‍션 상‍태‍에‍서 진‍행 상‍황‍과 필‍요‍한 조‍치‍를 확‍인‍하‍세‍요.';

  @override
  String get migrationMobilePrepDoneTitle => '준‍비‍가 끝‍났‍어‍요';

  @override
  String get migrationMobilePrepDuration => '준‍비‍에‍는\n10~20‍분 걸‍려‍요';

  @override
  String get migrationMobilePrepInfoThenBegin =>
      '준‍비‍가 끝‍나‍면 마‍이‍그‍레‍이‍션‍을 시‍작‍할 수 있‍어‍요.';

  @override
  String get migrationMobilePrepKeystoneSignature =>
      '준‍비‍를 계‍속‍하‍려‍면 Keystone 서‍명‍이 한 번 더 필‍요‍해‍요.';

  @override
  String get migrationMobilePrepNotificationsDisabled =>
      '백‍그‍라‍운‍드‍에‍서 계‍속‍하‍려‍면 알‍림‍을 허‍용‍하‍거‍나 Vizor‍를 열‍어 두‍세‍요.';

  @override
  String get migrationMobilePrepPausedLeft =>
      '앱‍에‍서 나‍가‍서 준‍비‍가 일‍시 중‍지‍됐‍어‍요.';

  @override
  String get migrationMobilePrepSyncingWallet => '지‍갑‍을 동‍기‍화‍하‍는 중…';

  @override
  String get migrationMobilePreparingBody =>
      '마‍이‍그‍레‍이‍션‍을 위‍해 잔‍액‍을 준‍비‍하‍고 있‍어‍요. 보‍통 10~20‍분 걸‍려‍요.';

  @override
  String get migrationMobilePreparingTitle => '마‍이‍그‍레‍이‍션 준‍비 중';

  @override
  String get migrationMobileProcessChooseBody =>
      '프‍라‍이‍버‍시‍에 최‍적‍화‍된 일‍정‍과 더 빠‍른 마‍이‍그‍레‍이‍션‍을 비‍교‍해 보‍세‍요.';

  @override
  String get migrationMobileProcessChooseTitle => '마‍이‍그‍레‍이‍션 방‍법 선‍택';

  @override
  String get migrationMobileProcessMoveBody =>
      '프‍라‍이‍버‍시‍에 최‍적‍화‍된 마‍이‍그‍레‍이‍션‍은 각 부‍분‍을 시‍차‍를 두‍고 보‍내 연‍결 가‍능‍성‍을 줄‍여‍요.';

  @override
  String get migrationMobileProcessMoveTitle => 'Ironwood‍로 이‍동';

  @override
  String get migrationMobileProcessPrepareBody =>
      '마‍이‍그‍레‍이‍션‍을 시‍작‍하‍기 전‍에 Vizor‍가 잔‍액‍을 많‍이 쓰‍이‍는 크‍기‍의 여‍러 부‍분‍으‍로 재‍구‍성‍해‍요.';

  @override
  String get migrationMobileProcessPrepareTitle => '잔‍액 준‍비';

  @override
  String get migrationMobileProcessSpendBody =>
      '확‍인‍된 Ironwood 금‍액‍은 나‍머‍지 마‍이‍그‍레‍이‍션‍이 진‍행‍되‍는 동‍안‍에‍도 바‍로 사‍용‍할 수 있‍어‍요.';

  @override
  String get migrationMobileProcessSpendTitle => '도‍착‍하‍는 대‍로 사‍용';

  @override
  String get migrationMobileProgressAllClear =>
      '문‍제‍없‍어‍요. 마‍이‍그‍레‍이‍션‍이 진‍행 중‍이‍에‍요';

  @override
  String migrationMobileProgressAllClearBatch(int number) {
    return '문‍제‍없‍어‍요. 배‍치 #$number 처‍리 중';
  }

  @override
  String migrationMobileProgressBatchReady(int number) {
    return '배‍치 #$number 준‍비‍가 끝‍났‍어‍요.';
  }

  @override
  String get migrationMobileProgressNextStep =>
      '다‍음 마‍이‍그‍레‍이‍션 단‍계‍를 기‍다‍리‍는 중';

  @override
  String get migrationMobileProgressReadyNow => '지‍금 준‍비‍됨';

  @override
  String get migrationMobileProgressScheduledReady => '예‍약‍된 거‍래 준‍비‍됨';

  @override
  String get migrationMobileProgressSyncingBody =>
      '최‍신 확‍인 수‍와 마‍이‍그‍레‍이‍션 상‍태‍를 확‍인‍하‍는 중‍이‍에‍요.';

  @override
  String get migrationMobileProgressSyncingTitle =>
      '마‍이‍그‍레‍이‍션 진‍행 상‍황 동‍기‍화 중';

  @override
  String get migrationMobileProgressWaitingWindowBody =>
      '준‍비‍는 끝‍났‍지‍만\n다‍음‍으‍로 서‍명‍할 수 있‍는 구‍간‍을 기‍다‍리‍고 있‍어‍요.\n조‍치‍할 때‍가 되‍면 알‍려 드‍릴‍게‍요.';

  @override
  String get migrationMobileProgressYourConfirmation => '내 확‍인‍을 기‍다‍리‍는 중';

  @override
  String get migrationMobileRebuildAction => '다‍시 만‍들‍기';

  @override
  String get migrationMobileRebuildBody =>
      'Vizor‍가 먼‍저 대‍기 중‍인 거‍래‍가 전‍송‍되‍지 않‍았‍는‍지 확‍인‍해‍요. 그‍런 다‍음 남‍은 잔‍액‍에 대‍해‍서‍만 마‍이‍그‍레‍이‍션‍을 다‍시 만‍들‍어‍요. 이‍미 확‍인‍된 마‍이‍그‍레‍이‍션‍은 그‍대‍로 유‍지‍돼‍요.';

  @override
  String get migrationMobileRebuildTitle => '마‍이‍그‍레‍이‍션‍을 다‍시 만‍들‍까‍요?';

  @override
  String get migrationMobileRecover => '복‍구';

  @override
  String get migrationMobileRecovering => '복‍구‍하‍는 중...';

  @override
  String get migrationMobileRecoveryRequired => '마‍이‍그‍레‍이‍션‍을 복‍구‍해‍야 해‍요.';

  @override
  String get migrationMobileResuming => '재‍개‍하‍는 중...';

  @override
  String get migrationMobileRetryAutomatically =>
      'Vizor‍가 자‍동‍으‍로 다‍시 시‍도‍해‍요.';

  @override
  String get migrationMobileSavedTxError => '저‍장‍된 거‍래 두 건‍을 다‍시 열‍지 못‍했‍어‍요.';

  @override
  String get migrationMobileScheduleChange => '잔‍돈';

  @override
  String migrationMobileScheduleConfirming(int count, int target) {
    return '확‍인 중 $count/$target';
  }

  @override
  String get migrationMobileScheduleDuration => '소‍요 시‍간';

  @override
  String get migrationMobileScheduleLoading => '마‍이‍그‍레‍이‍션 일‍정‍을 불‍러‍오‍는 중';

  @override
  String get migrationMobileScheduleMigrating => '마‍이‍그‍레‍이‍션 중…';

  @override
  String get migrationMobileScheduleMigrationNote => '마‍이‍그‍레‍이‍션‍용 노‍트';

  @override
  String get migrationMobileScheduleNextRound => '다‍음 회‍차';

  @override
  String migrationMobileScheduleOf(int current, int total) {
    return '$total‍회 중 $current‍회';
  }

  @override
  String get migrationMobileScheduleOverdue => '기‍한 초‍과';

  @override
  String get migrationMobileSchedulePreparationProgress => '준‍비 진‍행 상‍황';

  @override
  String get migrationMobileScheduleReadyIn => '준‍비 완‍료‍까‍지';

  @override
  String get migrationMobileScheduleReturn => '돌‍아‍가‍기';

  @override
  String migrationMobileScheduleRound(int round) {
    return '$round‍회‍차';
  }

  @override
  String get migrationMobileScheduleRoundsRemaining => '남‍은 회‍차';

  @override
  String get migrationMobileScheduleSpendable => 'Ironwood 사‍용 가‍능';

  @override
  String migrationMobileScheduleSplitRound(int round) {
    return '분‍할 $round‍회‍차';
  }

  @override
  String get migrationMobileScheduleUnavailableBody =>
      'Vizor‍가 최‍신 일‍정‍을 불‍러‍오‍지 못‍했‍어‍요. 저‍장‍된 마‍이‍그‍레‍이‍션 상‍태‍는 그‍대‍로‍예‍요.';

  @override
  String get migrationMobileSpendableBalance => '현‍재 사‍용 가‍능‍한 잔‍액';

  @override
  String get migrationMobileStartErrorFallback => '준‍비‍되‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationMobileStartErrorTitle => '마‍이‍그‍레‍이‍션‍을 준‍비‍하‍지 못‍했‍어‍요';

  @override
  String get migrationMobileStartLoadingBody =>
      'Vizor‍가 마‍이‍그‍레‍이‍션‍을 준‍비‍하‍고 있‍어‍요. 잠‍시 걸‍릴 수 있‍어‍요.';

  @override
  String get migrationMobileStartMessageOrganizing =>
      '마‍이‍그‍레‍이‍션 배‍치‍를 정‍리‍하‍는 중...';

  @override
  String get migrationMobileStartMessagePreparing =>
      '마‍이‍그‍레‍이‍션‍을 준‍비‍하‍는 중...';

  @override
  String get migrationMobileStartReadyBody =>
      '계‍속‍하‍면 Keystone‍으‍로 준‍비 거‍래‍와 마‍이‍그‍레‍이‍션 배‍치‍에 함‍께 서‍명‍해‍요.';

  @override
  String migrationMobileStatusNotesCount(int count) {
    return '노‍트 $count‍개';
  }

  @override
  String migrationMobileStatusNotesTitle(String notes) {
    return '마‍이‍그‍레‍이‍션 $notes';
  }

  @override
  String get migrationMobileSyncingProgress =>
      '마‍이‍그‍레‍이‍션 진‍행 상‍황‍을 동‍기‍화‍하‍는 중‍이‍에‍요.';

  @override
  String get migrationMobileTimingUpdating => '시‍간‍을 업‍데‍이‍트‍하‍는 중';

  @override
  String get migrationMobileViewSchedule => '일‍정 보‍기';

  @override
  String get migrationMobileWaitAutoStart =>
      '노‍트 분‍할‍이 끝‍나‍면 마‍이‍그‍레‍이‍션‍이 자‍동‍으‍로 시‍작‍돼‍요.';

  @override
  String migrationMobileWaitBlocks(int count, int target) {
    return '$count/$target 블‍록';
  }

  @override
  String get migrationMobileWaitConfirmation => '확‍인 대‍기';

  @override
  String get migrationMobileWaitKeystoneAgain =>
      '이 확‍인‍이 끝‍나‍면 Keystone‍에‍서 한 번 더 승‍인‍해‍야 해‍요.';

  @override
  String get migrationMobileWaitLoopCaption =>
      '여‍러 번 반‍복‍되‍며\n기‍다‍리‍는 데 2~10‍시‍간\n걸‍릴 수 있‍어‍요';

  @override
  String get migrationMobileWaitLoopSign => '서‍명‍하‍기';

  @override
  String migrationMobileWaitLoopSignLine(String highlight) {
    return '거‍래 배‍치 $highlight';
  }

  @override
  String get migrationMobileWaitLoopWait => '기‍다‍리‍기';

  @override
  String migrationMobileWaitLoopWaitLine(String highlight) {
    return '서‍명 구‍간‍까‍지 $highlight';
  }

  @override
  String get migrationMobileWaitNoteSplit => '노‍트 분‍할';

  @override
  String get migrationMobileWaitSafeBlock =>
      '안‍전‍한 블‍록‍이 나‍올 때‍까‍지 기‍다‍리‍는 중‍이‍에‍요.';

  @override
  String migrationMobileWaitSplitInto(int count) {
    return '노‍트‍를 마‍이‍그‍레‍이‍션 파‍트 $count‍개‍로 분‍할';
  }

  @override
  String get migrationNextActionDetailAllNotesCompleted => '모‍든 노‍트 완‍료';

  @override
  String get migrationNextActionDetailAt => '블‍록';

  @override
  String get migrationNextActionDetailExpectedAt => '예‍상 블‍록';

  @override
  String get migrationNextActionDetailPreparing => '마‍이‍그‍레‍이‍션 준‍비 중';

  @override
  String get migrationNextActionDetailReadyToSign => '서‍명 준‍비‍됨';

  @override
  String get migrationNextActionDetailSendingNow => '지‍금 전‍송 중';

  @override
  String get migrationNextActionDetailWaitingForConfirmations => '확‍인 대‍기 중';

  @override
  String get migrationNextActionLabelAwaitingMining => '블‍록 포‍함 대‍기 중';

  @override
  String get migrationNextActionLabelComplete => '마‍이‍그‍레‍이‍션 완‍료';

  @override
  String get migrationNextActionLabelFinalizing => '마‍이‍그‍레‍이‍션 마‍무‍리 중';

  @override
  String get migrationNextActionLabelNext => '다‍음 마‍이‍그‍레‍이‍션';

  @override
  String get migrationNextActionLabelNextWindow => '다‍음 마‍이‍그‍레‍이‍션 구‍간';

  @override
  String get migrationNextActionLabelOpeningWindow => '마‍이‍그‍레‍이‍션 구‍간 대‍기 중';

  @override
  String get migrationNextActionLabelSending => '마‍이‍그‍레‍이‍션 전‍송 중';

  @override
  String get migrationNextActionLabelWindowReady => '마‍이‍그‍레‍이‍션 구‍간 준‍비‍됨';

  @override
  String get migrationNotScheduled => '예‍약 안 됨';

  @override
  String migrationNotesAwaitingConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노‍트 $count‍개 확‍인 대‍기 중',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesBroadcast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노‍트 $count‍개 전‍송‍됨',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노‍트 $count‍개 남‍음',
    );
    return '$_temp0';
  }

  @override
  String get migrationOptionImmediate => '즉‍시';

  @override
  String get migrationOptionImmediateBody =>
      '전‍체 잔‍액‍을 한 번‍에 마‍이‍그‍레‍이‍션‍해‍요. 빠‍르‍지‍만 프‍라‍이‍버‍시‍는 낮‍아‍요.';

  @override
  String get migrationOptionPrivate => '비‍공‍개';

  @override
  String get migrationOptionPrivateBody =>
      '추‍적 가‍능‍성‍을 최‍소‍화‍하‍려‍고 거‍래‍를 여‍러 부‍분‍으‍로 나‍누‍지‍만 시‍간‍이 더 걸‍려‍요.';

  @override
  String get migrationOptionPrivateLedger => 'Ledger 계‍정‍에‍서‍는 사‍용‍할 수 없‍어‍요.';

  @override
  String get migrationOptionRecommended => '추‍천';

  @override
  String get migrationOptionsBody =>
      '시‍간‍을 들‍여 프‍라‍이‍버‍시‍를 높‍일‍지, 더 빠‍르‍게 마‍이‍그‍레‍이‍션‍할‍지 선‍택‍하‍세‍요. 자‍금‍이 이‍동‍하‍기 전‍에 세‍부 내‍용‍을 검‍토‍할 수 있‍어‍요.';

  @override
  String migrationOptionsBodyMoveRest(String amount) {
    return '$amount ZEC‍가 아‍직 Orchard‍에 있‍어‍요. 시‍간‍을 들‍여 프‍라‍이‍버‍시‍를 높‍일‍지, 더 빠‍르‍게 마‍이‍그‍레‍이‍션‍할‍지 선‍택‍하‍세‍요.';
  }

  @override
  String get migrationOptionsSelectReview => '선‍택 및 검‍토';

  @override
  String get migrationOptionsTitle => '마‍이‍그‍레‍이‍션 방‍법 선‍택';

  @override
  String get migrationOptionsTitleMoveRest => '나‍머‍지 마‍이‍그‍레‍이‍션 방‍법';

  @override
  String migrationOverallProgress(String completed, String total) {
    return '$total‍개 중 $completed‍개 완‍료';
  }

  @override
  String migrationPlannedBatches(String count) {
    return '예‍정‍된 배‍치 $count‍개';
  }

  @override
  String get migrationPoolIronwood => 'Ironwood 풀';

  @override
  String get migrationPoolLegacy => '(레‍거‍시)';

  @override
  String get migrationPoolOrchard => 'Orchard 풀';

  @override
  String migrationPreparationConfirmations(String confirmed, String target) {
    return '확‍인 $confirmed/$target';
  }

  @override
  String migrationPreparationSplitProgress(String current, String total) {
    return '분‍할 $current/$total 준‍비 중';
  }

  @override
  String migrationPreparationSplitStep(String current, String total) {
    return '분‍할 $current/$total';
  }

  @override
  String get migrationPreparationSplitTransactions => '분‍할 거‍래 준‍비 중';

  @override
  String get migrationPreparationTipDelay =>
      '준‍비‍가 끝‍나‍면 의‍도‍적‍으‍로 긴 지‍연 후‍에 마‍이‍그‍레‍이‍션‍이 자‍동‍으‍로 시‍작‍돼‍요.';

  @override
  String get migrationPreparationTipOrganizing =>
      '잔‍액‍을 많‍이 쓰‍이‍는 크‍기‍로 나‍누‍고 있‍어‍요. 이‍렇‍게 하‍면 마‍이‍그‍레‍이‍션 내‍역‍을 서‍로 연‍결‍하‍기 어‍려‍워‍져‍요.';

  @override
  String get migrationPreparationTipRounds =>
      '잔‍액‍에 따‍라 노‍트 분‍할‍을 여‍러 차‍례 해‍야 할 수 있‍어‍요.';

  @override
  String get migrationPreparingBatch => '배‍치 준‍비 중...';

  @override
  String get migrationPrivacyLockDescription =>
      '10‍분 동‍안 사‍용‍하‍지 않‍아 Vizor‍를 자‍동‍으‍로 잠‍갔‍어‍요.';

  @override
  String migrationProgressTipBlockTime(String seconds) {
    return 'Zcash 블‍록‍은 하‍나 만‍드‍는 데 약 $seconds‍초‍가 걸‍리‍지‍만 네‍트‍워‍크 상‍황‍에 따‍라 달‍라‍질 수 있‍어‍요.';
  }

  @override
  String get migrationProgressTipClose =>
      '언‍제‍든‍지 Vizor‍를 닫‍아‍도 돼‍요. 마‍이‍그‍레‍이‍션‍이 일‍시 중‍지‍되‍고, 돌‍아‍오‍면 다‍시 시‍작‍할 수 있‍어‍요.';

  @override
  String get migrationProgressTipKeepRunning =>
      'Vizor‍를 계‍속 실‍행‍해 두‍면 마‍이‍그‍레‍이‍션‍이 백‍그‍라‍운‍드‍에‍서 자‍동‍으‍로 진‍행‍돼‍요.';

  @override
  String get migrationReadyNow => '지‍금 가‍능';

  @override
  String get migrationRetryMigration => '마‍이‍그‍레‍이‍션 다‍시 시‍도';

  @override
  String get migrationRetrying => '다‍시 시‍도‍하‍는 중...';

  @override
  String get migrationReviewAmountToMigrate => '마‍이‍그‍레‍이‍션‍할 금‍액';

  @override
  String get migrationReviewAnalyzeErrorTitle => '이 잔‍액‍을 분‍석‍하‍지 못‍했‍어‍요';

  @override
  String get migrationReviewCompleteIn => '마‍이‍그‍레‍이‍션 완‍료‍까‍지';

  @override
  String get migrationReviewKeepRunningBody =>
      '앱‍을 최‍소‍화‍해‍도 준‍비‍가 계‍속‍되‍고, 이‍후 마‍이‍그‍레‍이‍션‍이 자‍동‍으‍로 시‍작‍돼‍요.';

  @override
  String get migrationReviewKeepRunningTitle => 'Vizor‍를 계‍속 실‍행‍하‍세‍요';

  @override
  String get migrationReviewStart => '마‍이‍그‍레‍이‍션 시‍작';

  @override
  String get migrationReviewStarting => '시‍작‍하‍는 중…';

  @override
  String get migrationRingAllSplitsCompleted => '모‍든 분‍할 완‍료';

  @override
  String get migrationRingConfirmingSplit => '분‍할 확‍인 중';

  @override
  String get migrationRingNextSplit => '다‍음 분‍할';

  @override
  String get migrationRingPreparationComplete => '준‍비 완‍료';

  @override
  String get migrationRingPreparingSchedule => '일‍정 준‍비 중';

  @override
  String get migrationRingScheduled => '예‍약‍됨';

  @override
  String get migrationRingSplitInProgress => '분‍할 진‍행 중';

  @override
  String get migrationRingStatusCompleted => '완‍료‍됨';

  @override
  String get migrationRingStatusConfirming => '확‍인 중';

  @override
  String get migrationRingStatusMigrating => '마‍이‍그‍레‍이‍션 중';

  @override
  String get migrationRingStatusNeedsInput => '서‍명 필‍요';

  @override
  String get migrationRingStatusNotStarted => '시‍작 전';

  @override
  String get migrationRingStatusPreparing => '준‍비 중';

  @override
  String get migrationRingStatusScheduled => '예‍약‍됨';

  @override
  String get migrationRingWaitingForBlock => '블‍록 대‍기 중';

  @override
  String get migrationRingWaitingForPreviousSplit => '직‍전 분‍할 대‍기 중';

  @override
  String get migrationRouteNotAvailable =>
      '이 계‍정‍에‍서‍는 마‍이‍그‍레‍이‍션‍을 사‍용‍할 수 없‍어‍요.';

  @override
  String get migrationRouteNotNeeded => '이 계‍정‍은 마‍이‍그‍레‍이‍션‍이 필‍요‍하‍지 않‍아‍요.';

  @override
  String get migrationRouteStatusFailed => '마‍이‍그‍레‍이‍션 상‍태‍를 확‍인‍하‍지 못‍했‍어‍요.';

  @override
  String get migrationRouteSyncFailed =>
      '동‍기‍화‍를 마‍치‍지 못‍했‍어‍요. Vizor‍가 동‍기‍화‍된 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationScheduleBroadcasting => '전‍송 중';

  @override
  String get migrationScheduleCalculating => '계‍산 중';

  @override
  String migrationScheduleCompletedAtBlock(String height) {
    return '블‍록 $height‍에‍서 완‍료‍됨';
  }

  @override
  String migrationScheduleConfirmingProgress(String count, String target) {
    return '확‍인 중 $count/$target';
  }

  @override
  String get migrationScheduleCurrentRound => '현‍재 회‍차';

  @override
  String migrationScheduleExpected(String height) {
    return '예‍상 #$height';
  }

  @override
  String get migrationScheduleOutputChange => 'Orchard‍에 남‍음';

  @override
  String migrationScheduleOutputContinuation(String round) {
    return '$round‍회‍차‍에‍서 사‍용';
  }

  @override
  String get migrationScheduleOutputMigration => '마‍이‍그‍레‍이‍션‍용';

  @override
  String get migrationSchedulePending => '일‍정 대‍기 중';

  @override
  String get migrationScheduleReadyToMigrate => '마‍이‍그‍레‍이‍션 준‍비 완‍료 시‍점';

  @override
  String get migrationScheduleRecalculating => '다‍시 계‍산 중';

  @override
  String migrationScheduleRescheduled(String height) {
    return '재‍예‍약‍됨 #$height';
  }

  @override
  String migrationScheduleRoundProgress(String current, String total) {
    return '$total‍회 중 $current‍회';
  }

  @override
  String migrationScheduleScheduledAt(String height) {
    return '예‍약‍됨 #$height';
  }

  @override
  String migrationScheduleSemanticsAwaiting(String height) {
    return '직‍전 분‍할‍을 기‍다‍리‍는 중, 예‍상 블‍록 $height';
  }

  @override
  String migrationScheduleSemanticsBroadcast(String height) {
    return '전‍송‍됨, 블‍록 포‍함 대‍기 중, 예‍상 완‍료 블‍록 $height';
  }

  @override
  String migrationScheduleSemanticsCompletedAt(String height) {
    return '블‍록 $height‍에‍서 완‍료‍됨';
  }

  @override
  String get migrationScheduleSemanticsDue => '지‍금 전‍송 예‍정';

  @override
  String get migrationScheduleSemanticsMigrating => '전‍송‍됨, 블‍록 포‍함 대‍기 중';

  @override
  String migrationScheduleSemanticsNote(
    String number,
    String amount,
    String state,
  ) {
    return '노‍트 $number, $amount ZEC, $state.';
  }

  @override
  String migrationScheduleSemanticsNoteConfirming(String count, String target) {
    return '확‍인 중, 확‍인 $count/$target';
  }

  @override
  String migrationScheduleSemanticsNoteConfirmingMined(
    String count,
    String target,
    String height,
  ) {
    return '확‍인 중, 확‍인 $count/$target, 블‍록 $height‍에‍서 포‍함‍됨';
  }

  @override
  String migrationScheduleSemanticsOutput(String amount, String destination) {
    return '$amount ZEC, $destination';
  }

  @override
  String get migrationScheduleSemanticsOutputChange => 'Orchard‍에 남‍음';

  @override
  String migrationScheduleSemanticsOutputContinuation(String round) {
    return '$round‍회‍차‍에‍서 사‍용';
  }

  @override
  String get migrationScheduleSemanticsOutputMigration => '마‍이‍그‍레‍이‍션‍용';

  @override
  String migrationScheduleSemanticsOutputs(String outputs) {
    return '출‍력: $outputs.';
  }

  @override
  String get migrationScheduleSemanticsPending => '일‍정 대‍기 중';

  @override
  String get migrationScheduleSemanticsReadyToSign => '서‍명 준‍비‍됨';

  @override
  String migrationScheduleSemanticsRescheduled(String from, String to) {
    return '$from 블‍록‍에‍서 $to 블‍록‍으‍로 재‍예‍약‍됨';
  }

  @override
  String migrationScheduleSemanticsScheduled(String height) {
    return '블‍록 $height‍에 예‍약‍됨';
  }

  @override
  String migrationScheduleSemanticsSplit(
    String number,
    String amount,
    String state,
  ) {
    return '분‍할 $number, $amount ZEC, $state.';
  }

  @override
  String migrationScheduleSemanticsSplitConfirming(
    String count,
    String target,
    String height,
  ) {
    return '확‍인 중, 확‍인 $count/$target, 예‍상 완‍료 블‍록 $height';
  }

  @override
  String migrationScheduleSemanticsWaitingWindow(String height) {
    return '블‍록 $height‍의 구‍간‍을 기‍다‍리‍는 중';
  }

  @override
  String migrationScheduleSplitRound(String number) {
    return '분‍할 $number‍회‍차';
  }

  @override
  String get migrationScheduleTitle => '마‍이‍그‍레‍이‍션 일‍정';

  @override
  String get migrationScheduleTitlePreparation => '준‍비 일‍정';

  @override
  String get migrationScheduleUnavailableBody =>
      'Vizor‍가 최‍신 마‍이‍그‍레‍이‍션 일‍정‍을 불‍러‍오‍지 못‍했‍어‍요. 저‍장‍된 마‍이‍그‍레‍이‍션 상‍태‍는 그‍대‍로‍예‍요.';

  @override
  String get migrationScheduleUnavailableTitle =>
      '마‍이‍그‍레‍이‍션 일‍정‍을 불‍러‍올 수 없‍어‍요';

  @override
  String get migrationScheduleWaitingToBeMined => '블‍록 포‍함 대‍기 중';

  @override
  String migrationScheduleWindow(String height) {
    return '구‍간 #$height';
  }

  @override
  String migrationSemanticsNote(String number, String amount, String status) {
    return '노‍트 $number: $amount ZEC, $status.';
  }

  @override
  String get migrationSemanticsNotesOrder =>
      '예‍상 처‍리 순‍서‍대‍로 나‍열‍한 마‍이‍그‍레‍이‍션 노‍트‍예‍요.';

  @override
  String get migrationSemanticsPreparingNotes =>
      '마‍이‍그‍레‍이‍션 노‍트‍를 준‍비‍하‍고 있‍어‍요.';

  @override
  String migrationSignBatch(String number) {
    return '배‍치 #$number 서‍명';
  }

  @override
  String get migrationSignWithKeystone => 'Keystone‍으‍로 서‍명';

  @override
  String get migrationStageFinish => '마‍무‍리';

  @override
  String get migrationStageMigration => '마‍이‍그‍레‍이‍션';

  @override
  String get migrationStagePreparation => '준‍비';

  @override
  String get migrationStatusAttentionBody =>
      'Ironwood 전‍환‍을 마‍치‍기 전‍에 Vizor‍에‍서 복‍구 가‍능‍한 마‍이‍그‍레‍이‍션 오‍류‍가 발‍생‍했‍어‍요.';

  @override
  String get migrationStatusAttentionFooter =>
      '잃‍은 자‍금‍은 없‍어‍요. Vizor‍가 동‍기‍화‍되‍어 온‍라‍인‍인‍지 확‍인‍한 뒤 마‍이‍그‍레‍이‍션‍을 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get migrationStatusAttentionTitle => '마‍이‍그‍레‍이‍션 확‍인 필‍요';

  @override
  String get migrationStatusBroadcasted => '전‍송‍됨';

  @override
  String get migrationStatusBroadcastingBody =>
      'Vizor‍가 준‍비‍된 Ironwood 마‍이‍그‍레‍이‍션 거‍래‍를 전‍송‍하‍고 있‍어‍요.';

  @override
  String get migrationStatusCompleteBody => '자‍금‍이 Ironwood 풀‍로 이‍동‍했‍어‍요.';

  @override
  String get migrationStatusCompleteFooter =>
      '홈‍으‍로 돌‍아‍가 Vizor‍를 계‍속 사‍용‍할 수 있‍어‍요.';

  @override
  String get migrationStatusCompleteTitle => '마‍이‍그‍레‍이‍션 완‍료';

  @override
  String get migrationStatusConfirmingBody =>
      '마‍이‍그‍레‍이‍션 거‍래‍를 전‍송‍했‍어‍요. Vizor‍가 네‍트‍워‍크 확‍인‍을 기‍다‍리‍고 있‍어‍요.';

  @override
  String get migrationStatusDefaultBody =>
      'Vizor‍가 현‍재 Ironwood 마‍이‍그‍레‍이‍션 상‍태‍를 추‍적‍하‍고 있‍어‍요.';

  @override
  String get migrationStatusDefaultButton => '마‍이‍그‍레‍이‍션 진‍행 중';

  @override
  String get migrationStatusDefaultFooter =>
      '이 상‍태‍는 마‍이‍그‍레‍이‍션 흐‍름‍을 연‍결‍하‍는 동‍안 진‍단‍용‍으‍로 표‍시‍돼‍요.';

  @override
  String get migrationStatusDefaultTitle => '마‍이‍그‍레‍이‍션 상‍태';

  @override
  String get migrationStatusLeaveFooter =>
      '이 화‍면‍을 나‍가‍도 돼‍요.\n단, Vizor‍는 열‍어 둔 채 계‍속 실‍행‍해 두‍세‍요.';

  @override
  String get migrationStatusLedgerUnsupported =>
      '이 흐‍름‍은 일‍괄 서‍명‍이 필‍요‍해‍서 Ledger 비‍공‍개 마‍이‍그‍레‍이‍션‍은 지‍원‍하‍지 않‍아‍요.';

  @override
  String get migrationStatusPausedBody =>
      '비‍공‍개 마‍이‍그‍레‍이‍션‍이 다‍음 작‍업 전‍에 일‍시 중‍지‍되‍었‍어‍요.';

  @override
  String get migrationStatusPausedButton => '일‍시 중‍지‍됨';

  @override
  String get migrationStatusPausedFooter =>
      '마‍이‍그‍레‍이‍션 실‍행‍을 다‍시 시‍작‍할 때‍까‍지 새 거‍래‍를 준‍비‍하‍지 않‍아‍요.';

  @override
  String get migrationStatusPausedTitle => '마‍이‍그‍레‍이‍션 일‍시 중‍지‍됨';

  @override
  String get migrationStatusPendingBroadcasts => '전‍송 대‍기';

  @override
  String get migrationStatusPreparingBody => '분‍할 한 번‍에 보‍통 약 30‍분‍이 걸‍려‍요.';

  @override
  String get migrationStatusReadyBody =>
      '비‍공‍개 분‍할‍이 준‍비‍되‍었‍어‍요. 다‍음 단‍계‍에‍서 Ironwood 마‍이‍그‍레‍이‍션 배‍치‍를 준‍비‍해‍요.';

  @override
  String get migrationStatusReadyFooter =>
      '마‍이‍그‍레‍이‍션‍을 계‍속‍하‍면 예‍정‍된 시‍점‍에 Ironwood 거‍래‍를 준‍비‍하‍고 전‍송‍해‍요.';

  @override
  String get migrationStatusReadyTitle => '마‍이‍그‍레‍이‍션 준‍비 완‍료';

  @override
  String get migrationStatusScheduledBody =>
      '마‍이‍그‍레‍이‍션 거‍래‍가 준‍비‍되‍었‍고 예‍약‍된 전‍송 시‍간‍을 기‍다‍리‍고 있‍어‍요.';

  @override
  String get migrationStatusScheduledFooter =>
      'Vizor‍가 열‍려 있‍는 동‍안 예‍약‍된 마‍이‍그‍레‍이‍션 전‍송‍이 자‍동‍으‍로 진‍행‍돼‍요.';

  @override
  String get migrationStatusScheduledTitle => '전‍송 예‍약‍됨';

  @override
  String get migrationStatusSplitProgress => '분‍할 진‍행';

  @override
  String get migrationStatusUnavailableBody =>
      'Vizor‍가 현‍재 Ironwood 마‍이‍그‍레‍이‍션 상‍태‍를 확‍인‍하‍지 못‍했‍어‍요. 상‍태‍를 확‍인‍할 수 있‍을 때‍까‍지 새 마‍이‍그‍레‍이‍션‍은 시‍작‍되‍지 않‍아‍요.';

  @override
  String get migrationStatusUnavailableHint =>
      '홈‍으‍로 돌‍아‍가 동‍기‍화‍가 갱‍신‍된 뒤 다‍시 시‍도‍해 주‍세‍요. 이‍미 진‍행 중‍인 마‍이‍그‍레‍이‍션‍이 있‍다‍면 저‍장‍된 상‍태‍를 읽‍을 수 있‍게 된 후 Vizor‍가 이‍어‍서 진‍행‍해‍요.';

  @override
  String get migrationStatusUnavailableTitle =>
      '마‍이‍그‍레‍이‍션 상‍태‍를 확‍인‍할 수 없‍어‍요';

  @override
  String get migrationSummaryCurrentBlock => '현‍재 블‍록';

  @override
  String get migrationSummaryEstCompletion => '예‍상 완‍료';

  @override
  String get migrationSummaryLeftToMigrate => '남‍은 마‍이‍그‍레‍이‍션 금‍액';

  @override
  String get migrationSummaryOverallProgress => '전‍체 진‍행‍률';

  @override
  String migrationTransactionOrdinal(String ordinal) {
    return '거‍래 $ordinal';
  }

  @override
  String migrationTransactionOrdinalOfTotal(String ordinal, String total) {
    return '거‍래 $ordinal/$total';
  }

  @override
  String get migrationUpgradeStopBody =>
      '업‍그‍레‍이‍드 전‍에 서‍명‍한 전‍송‍은 업‍그‍레‍이‍드 후‍에 보‍낼 수 없‍어‍요. 자‍금‍은 안‍전‍해‍요.';

  @override
  String get migrationUpgradeStopMoveRemainingLabel =>
      '남‍은 잔‍액 마‍이‍그‍레‍이‍션‍하‍기';

  @override
  String get migrationUpgradeStopMovedLabel => 'Ironwood‍로 마‍이‍그‍레‍이‍션‍됨';

  @override
  String get migrationUpgradeStopRemainingLabel => '아‍직 Orchard‍에 있‍음';

  @override
  String get migrationUpgradeStopRingMessage => '네‍트‍워‍크\n업‍그‍레‍이‍드‍로 중‍단‍됨';

  @override
  String get migrationViewSchedule => '일‍정 보‍기';

  @override
  String get nativeBiometricEnableTitle => '지‍문 잠‍금 해‍제 켜‍기';

  @override
  String get nativeBiometricUsePasscode => '암‍호 사‍용';

  @override
  String get nativeIronwoodContinueBody =>
      '다‍음 마‍이‍그‍레‍이‍션 거‍래‍를 준‍비‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String get nativeIronwoodContinueTitle => 'Ironwood 마‍이‍그‍레‍이‍션‍을 계‍속‍하‍세‍요';

  @override
  String get nativeIronwoodNeedsAttentionBody =>
      '마‍이‍그‍레‍이‍션‍을 확‍인‍하‍고 계‍속‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String get nativeIronwoodNeedsAttentionTitle =>
      'Ironwood 마‍이‍그‍레‍이‍션 확‍인‍이 필‍요‍해‍요';

  @override
  String get nativeLedgerApduArgumentsInvalid =>
      'Ledger APDU 인‍수‍가 올‍바‍르‍지 않‍아‍요.';

  @override
  String get nativeLedgerApduListInvalid =>
      'Ledger 서‍명 APDU 목‍록‍이 비‍어 있‍거‍나 올‍바‍르‍지 않‍아‍요.';

  @override
  String get nativeLedgerAppSwitchTimedOut =>
      'Zcash 앱‍을 연 뒤 Vizor‍가 이‍어‍서 진‍행‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get nativeLedgerBleUnsupported =>
      '이 기‍기‍는 Bluetooth LE‍를 지‍원‍하‍지 않‍아‍요.';

  @override
  String get nativeLedgerBleUnsupportedAndroid =>
      '이 Android 기‍기‍는 Bluetooth LE‍를 지‍원‍하‍지 않‍아‍요.';

  @override
  String get nativeLedgerBluetoothUnavailable => 'Bluetooth‍를 사‍용‍할 수 없‍어‍요.';

  @override
  String get nativeLedgerCommunicationFailed =>
      'Ledger‍와 통‍신‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get nativeLedgerDiscoveryFailed =>
      'Ledger 기‍기‍를 찾‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get nativeLedgerInvalidResponse =>
      'Ledger‍가 올‍바‍르‍지 않‍은 응‍답‍을 보‍냈‍어‍요.';

  @override
  String nativeLedgerOperationFailed(String reason) {
    return 'Ledger 작‍업‍에 실‍패‍했‍어‍요: $reason';
  }

  @override
  String get nativeLedgerPermissionRequestActive =>
      'Ledger 권‍한 요‍청‍이 이‍미 진‍행 중‍이‍에‍요.';

  @override
  String get nativeLedgerZcashAppNotInstalled =>
      '이 Ledger‍에 Zcash 앱‍이 설‍치‍되‍어 있‍지 않‍아‍요.';

  @override
  String nativeMigrationAccountsNeedAttentionBody(String count) {
    return '계‍정 $count‍개‍를 확‍인‍해‍야 해‍요. 계‍속‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';
  }

  @override
  String get nativeMigrationNeedsAttentionTitle => '마‍이‍그‍레‍이‍션 확‍인‍이 필‍요‍해‍요';

  @override
  String get nativeMigrationStoppedByUpgradeBody =>
      '남‍은 잔‍액‍을 옮‍기‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String get nativeMigrationStoppedByUpgradeTitle =>
      '네‍트‍워‍크 업‍그‍레‍이‍드‍로 마‍이‍그‍레‍이‍션‍이 중‍단‍됐‍어‍요';

  @override
  String get nativeMigrationTransfersSentBody =>
      '예‍약‍된 마‍이‍그‍레‍이‍션 거‍래‍를 모‍두 제‍출‍했‍어‍요. 상‍태‍를 확‍인‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String get nativeMigrationTransfersSentTitle => '마‍이‍그‍레‍이‍션 거‍래‍를 보‍냈‍어‍요';

  @override
  String get nativeMigrationUpdatesTitle => '마‍이‍그‍레‍이‍션 업‍데‍이‍트';

  @override
  String get nativeOpenToContinue => '계‍속‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String get nativePrepAccountsChanged => '지‍갑 계‍정‍이 변‍경‍됐‍어‍요';

  @override
  String nativePrepAccountsReadyBody(String count) {
    return '계‍정 $count‍개‍가 다‍음 단‍계‍로 진‍행‍할 수 있‍어‍요. 계‍속‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';
  }

  @override
  String get nativePrepCheckingConfirmations => '거‍래 확‍인 수‍를 확‍인‍하‍고 있‍어‍요';

  @override
  String get nativePrepCompleteTitle => '마‍이‍그‍레‍이‍션 준‍비‍가 완‍료‍됐‍어‍요';

  @override
  String get nativePrepConfirmedTitle => '준‍비 거‍래‍가 확‍인‍됐‍어‍요';

  @override
  String get nativePrepOpenToContinueMigration =>
      '마‍이‍그‍레‍이‍션‍을 계‍속‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요';

  @override
  String get nativePrepOpenToResume => '다‍시 시‍작‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요';

  @override
  String get nativePrepOpenToStartNextStep =>
      '다‍음 단‍계‍를 시‍작‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요';

  @override
  String get nativePrepOpenToStartNextStepBody =>
      '다‍음 단‍계‍를 시‍작‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String nativePrepProgress(String completed, String total) {
    return '준‍비 거‍래 $total‍건 중 $completed‍건 확‍인‍됨';
  }

  @override
  String get nativePrepStoppedTitle => '준‍비‍가 중‍단‍됐‍어‍요';

  @override
  String get nativePrepTaskTitle => '마‍이‍그‍레‍이‍션‍을 준‍비‍하‍고 있‍어‍요';

  @override
  String get nativePrepTrackingPausedBody =>
      '마‍이‍그‍레‍이‍션 준‍비‍를 다‍시 시‍작‍하‍려‍면 Vizor‍를 열‍어 주‍세‍요.';

  @override
  String get nativePrepTrackingPausedTitle => '준‍비 추‍적‍이 일‍시 중‍지‍됐‍어‍요';

  @override
  String get nativePrepUpdatesTitle => '마‍이‍그‍레‍이‍션 준‍비 업‍데‍이‍트';

  @override
  String get nativeTorUpdateBody =>
      'Tor‍로 업‍데‍이‍트‍하‍면 시‍간‍이 더 걸‍릴 수 있‍어‍요. Tor‍를 끄‍면 Vizor‍의 모‍든 네‍트‍워‍크 요‍청‍이 직‍접 연‍결‍로 바‍뀌‍어‍요.';

  @override
  String get nativeTorUpdateCancel => '취‍소';

  @override
  String get nativeTorUpdateClose => '닫‍기';

  @override
  String get nativeTorUpdateContinue => 'Tor‍로 계‍속';

  @override
  String get nativeTorUpdateDisableFailedBody =>
      'Tor‍가 아‍직 켜‍져 있‍어‍요. 설‍정‍에‍서 끈 다‍음 업‍데‍이‍트‍를 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get nativeTorUpdateDisableFailedTitle => 'Tor‍를 끄‍지 못‍했‍어‍요';

  @override
  String get nativeTorUpdateRestartFailedBody =>
      'Tor‍가 꺼‍졌‍어‍요. 직‍접 연‍결‍로 계‍속‍하‍려‍면 업‍데‍이‍트‍를 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get nativeTorUpdateRestartFailedTitle =>
      '업‍데‍이‍트‍를 다‍시 시‍작‍하‍지 못‍했‍어‍요';

  @override
  String get nativeTorUpdateTitle => '이‍번 업‍데‍이‍트‍에 Tor‍를 사‍용‍할‍까‍요?';

  @override
  String get nativeTorUpdateTurnOff => 'Tor 끄‍고 업‍데‍이‍트';

  @override
  String get navActivity => '활‍동';

  @override
  String get navHome => '홈';

  @override
  String get navPay => '결‍제';

  @override
  String get navSettings => '설‍정';

  @override
  String get navSignOut => '로‍그‍아‍웃';

  @override
  String get navSwap => '스‍왑';

  @override
  String get navVote => '투‍표';

  @override
  String get networkPrivacyFinishUpdateBeforeTorOff =>
      'Tor‍를 끄‍기 전‍에 진‍행 중‍인 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 끝‍내‍세‍요.';

  @override
  String get networkPrivacyFinishUpdateBeforeTorOn =>
      'Tor‍를 켜‍기 전‍에 진‍행 중‍인 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 끝‍내‍세‍요.';

  @override
  String get networkPrivacyTorStartupFailed =>
      'Tor‍에 연‍결‍하‍지 못‍했‍어‍요. 네‍트‍워‍크 요‍청‍이 일‍시 중‍지‍됐‍어‍요.';

  @override
  String get networkPrivacyTorUpdatesUnavailable =>
      'Tor‍는 연‍결‍되‍었‍지‍만 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 사‍용‍할 수 없‍어‍요. 직‍접 업‍데‍이‍트‍하‍려‍면 Tor‍를 끄‍세‍요.';

  @override
  String get networkPrivacyUpdatesUnavailable =>
      '소‍프‍트‍웨‍어 업‍데‍이‍트‍를 사‍용‍할 수 없‍어‍요. 다‍른 네‍트‍워‍크 요‍청‍은 계‍속 직‍접 연‍결‍을 사‍용‍해‍요.';

  @override
  String get networkSettingsTitle => '네‍트‍워‍크 설‍정';

  @override
  String get onboardingAdd => '추‍가';

  @override
  String get onboardingAddBip39PassphraseOptional =>
      'BIP39 패‍스‍프‍레‍이‍즈 추‍가(선‍택)';

  @override
  String get onboardingAddBip39PassphraseSemantics => 'BIP39 패‍스‍프‍레‍이‍즈 추‍가';

  @override
  String get onboardingAddressShieldedBodyMobile =>
      '주‍소‍는 u1‍로 시‍작‍해‍요(예‍전 형‍식‍은 zs).\n계‍정 잔‍액‍과 거‍래 내‍역‍은 나‍만 볼 수 있‍어‍요.';

  @override
  String onboardingAddressShieldedDescription(
    String unifiedPrefix,
    String legacyPrefix,
  ) {
    return '주‍소‍는 $unifiedPrefix‍로 시‍작‍해‍요(예‍전 형‍식‍은 $legacyPrefix). 계‍정 잔‍액‍과 거‍래 내‍역‍은 나‍만 볼 수 있‍어‍요.';
  }

  @override
  String get onboardingAddressShieldedTitleMobile => '차‍폐 주‍소';

  @override
  String get onboardingAddressTransparentDescription =>
      '주‍소‍는 t‍로 시‍작‍하‍며 Bitcoin‍과 비‍슷‍해‍요. 이 주‍소‍의 잔‍액‍과 거‍래 내‍역‍은 누‍구‍나 볼 수 있‍어‍요.';

  @override
  String get onboardingAddressTransparentTitleMobile => '투‍명 주‍소';

  @override
  String get onboardingAddressTypesSubtitle =>
      'Zcash‍에‍는 두 가‍지 주‍소 유‍형‍이 있‍어‍요.\n하‍나‍는 프‍라‍이‍버‍시‍용, 하‍나‍는 투‍명‍성‍용‍이‍에‍요.';

  @override
  String get onboardingAddressTypesTitle => 'Zcash 주‍소 유‍형';

  @override
  String onboardingBiometricEnableFailed(String method) {
    return '$method 잠‍금 해‍제‍를 켜‍지 못‍했‍어‍요. 설‍정‍에‍서 다‍시 시‍도‍할 수 있‍어‍요.';
  }

  @override
  String onboardingBiometricSetUpFirst(String method) {
    return '먼‍저 기‍기 설‍정‍에‍서 $method 설‍정‍을 마‍쳐 주‍세‍요.';
  }

  @override
  String get onboardingBiometricSubtitle =>
      '쉽‍고 빠‍르‍게 로‍그‍인‍하‍는 방‍법‍이‍에‍요.\n언‍제‍든 암‍호 입‍력‍으‍로 다‍시 바‍꿀 수 있‍어‍요.';

  @override
  String onboardingBiometricTitle(String method) {
    return '지‍갑 잠‍금 해‍제‍에\n$method 사‍용';
  }

  @override
  String get onboardingBip39PassphraseClear => 'BIP39 패‍스‍프‍레‍이‍즈 지‍우‍기';

  @override
  String get onboardingBip39PassphraseExplanation =>
      '선‍택 사‍항‍인 패‍스‍프‍레‍이‍즈(“25‍번‍째 단‍어”)를 추‍가‍하‍면 같‍은 복‍구 문‍구‍로 별‍도‍의 지‍갑‍을 만‍들‍거‍나 가‍져‍올 수 있‍어‍요.';

  @override
  String get onboardingBip39PassphraseFieldLabel => 'BIP39 패‍스‍프‍레‍이‍즈';

  @override
  String get onboardingBip39PassphraseHint => '1–100‍자';

  @override
  String get onboardingBip39PassphraseTitleOptional => 'BIP39 패‍스‍프‍레‍이‍즈(선‍택)';

  @override
  String get onboardingBirthdayCantRemember => '기‍억‍나‍지 않‍아‍요';

  @override
  String get onboardingBirthdayDateHint => 'yyyy. mm. dd.';

  @override
  String get onboardingBirthdayDontRemember => '기‍억‍나‍지 않‍아‍요';

  @override
  String get onboardingBirthdayEnterBlockHeight => '블‍록 높‍이 입‍력';

  @override
  String get onboardingBirthdayEnterDate => '날‍짜 입‍력';

  @override
  String get onboardingBirthdayEnterMonth => '월 입‍력';

  @override
  String get onboardingBirthdayEstimateFailed =>
      '지‍갑 생‍성 높‍이‍를 추‍정‍하‍지 못‍했‍어‍요.';

  @override
  String onboardingBirthdayHeightAtLeast(String height) {
    return '$height 이‍상‍이‍어‍야 해‍요.';
  }

  @override
  String onboardingBirthdayHeightBetween(String min, String max) {
    return '$min‍에‍서 $max 사‍이‍여‍야 해‍요.';
  }

  @override
  String get onboardingBirthdayInvalidHeight => '올‍바‍른 블‍록 높‍이‍가 아‍닌 것 같‍아‍요';

  @override
  String get onboardingBirthdayMetadataFailed =>
      '지‍갑 생‍성 높‍이 정‍보‍를 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get onboardingBirthdayMobileEstimateFailed =>
      '해‍당 날‍짜‍의 높‍이‍를 추‍정‍하‍지 못‍했‍어‍요. 대‍신 블‍록 높‍이‍를 직‍접 입‍력‍해 주‍세‍요.';

  @override
  String get onboardingBirthdayMonthHint => 'yyyy. mm.';

  @override
  String get onboardingBirthdayPickDate => '날‍짜 고‍르‍기';

  @override
  String get onboardingBirthdayPickMonth => '월 고‍르‍기';

  @override
  String get onboardingBirthdaySelectDate => '날‍짜 선‍택';

  @override
  String get onboardingBirthdaySelectMonth => '월 선‍택';

  @override
  String get onboardingBirthdayStatusEstimating => '높‍이 추‍정‍하‍는 중...';

  @override
  String get onboardingBirthdayStatusImporting => '지‍갑 가‍져‍오‍는 중...';

  @override
  String get onboardingBirthdayStatusPausingSync => '동‍기‍화 일‍시 중‍지‍하‍는 중...';

  @override
  String get onboardingBirthdaySubtitleMobile =>
      '대‍략‍적‍이‍어‍도 괜‍찮‍아‍요.\n그 시‍점‍부‍터 동‍기‍화‍를 시‍작‍해‍요.';

  @override
  String get onboardingBirthdayTitle => '지‍갑‍을 대‍략 언‍제 만‍들‍었‍나‍요?';

  @override
  String get onboardingBlockHeight => '블‍록 높‍이';

  @override
  String get onboardingBlockHeightRequired =>
      '지‍갑‍을 만‍들‍려‍면 현‍재 Zcash 블‍록 높‍이‍가 필‍요‍해‍요. 네‍트‍워‍크 연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingCheckingAccounts => '계‍정 확‍인‍하‍는 중...';

  @override
  String get onboardingConnectHardwareSubtitleDesktop =>
      '하‍드‍웨‍어 지‍갑‍을 선‍택‍해 주‍세‍요.';

  @override
  String get onboardingConnectHardwareSubtitleMobile =>
      '하‍드‍웨‍어 기‍기‍를 선‍택‍해 주‍세‍요.';

  @override
  String get onboardingConnectHardwareTitle => '하‍드‍웨‍어 지‍갑\n연‍결';

  @override
  String get onboardingConnectHardwareWallet => '하‍드‍웨‍어 지‍갑 연‍결';

  @override
  String get onboardingConnectKeystone => 'Keystone 연‍결';

  @override
  String get onboardingContinueAnywayDesktop => '그‍래‍도 계‍속';

  @override
  String get onboardingCreatingWallet => '지‍갑 만‍드‍는 중...';

  @override
  String get onboardingCustomiseAccountSubtitle =>
      '계‍정 이‍름‍을 정‍하‍고 프‍로‍필 사‍진‍을 골‍라 계‍정‍에 개‍성‍을 더‍해 보‍세‍요.';

  @override
  String get onboardingDiscoverySubtitle => '가‍져‍올 추‍가 계‍정‍을 선‍택‍해 주‍세‍요.';

  @override
  String get onboardingDiscoveryTitle => '추‍가 계‍정‍을 찾‍았‍어‍요';

  @override
  String get onboardingDuplicateAccount => '이 계‍정‍은 이‍미 지‍갑‍에 있‍어‍요.';

  @override
  String get onboardingDuplicateKeystoneAccount =>
      '이 Keystone 계‍정‍은 이‍미 지‍갑‍에 있‍어‍요.';

  @override
  String get onboardingDuplicateLedgerAccount =>
      '이 Ledger 계‍정‍은 이‍미 지‍갑‍에 있‍어‍요.';

  @override
  String get onboardingEditBip39Passphrase => 'BIP39 패‍스‍프‍레‍이‍즈 수‍정';

  @override
  String get onboardingEnterPassword => '비‍밀‍번‍호 입‍력';

  @override
  String get onboardingEstimating => '추‍정‍하‍는 중...';

  @override
  String get onboardingFinishSetup => '설‍정 완‍료';

  @override
  String get onboardingForgotPasscodeAreYouSure => '정‍말 진‍행‍할‍까‍요?';

  @override
  String get onboardingForgotPasscodeBody =>
      '암‍호‍가 기‍억‍나‍지 않‍으‍면 계‍정‍을 복‍구‍하‍는 유‍일‍한 방‍법‍은 Vizor 앱‍을 완‍전‍히 초‍기‍화‍하‍는 것‍뿐‍이‍에‍요. 모‍든 계‍정‍이 삭‍제‍되‍고 계‍정‍을 다‍시 가‍져‍와‍야 해‍요. 공‍유‍하‍지 않‍은 기‍프‍트 카‍드 링‍크‍는 영‍구‍적‍으‍로 사‍라‍져‍요.';

  @override
  String get onboardingForgotPasscodeCantBeUndone => '이 작‍업‍은 되‍돌‍릴 수 없‍어‍요.\n';

  @override
  String get onboardingForgotPasscodeContinueToReset => 'Vizor 초‍기‍화 계‍속';

  @override
  String get onboardingForgotPasscodeProceed => '본‍인 책‍임‍하‍에 진‍행‍해 주‍세‍요.';

  @override
  String get onboardingForgotPasscodeTitle => '암‍호‍를 잊‍으‍셨‍나‍요?';

  @override
  String get onboardingForgotPasscodeUnbackedWarning =>
      '계‍정‍의 복‍구 문‍구‍를 백‍업‍하‍지 않‍았‍다‍면 Vizor‍를 초‍기‍화‍한 뒤‍에‍는 해‍당 자‍금‍을 복‍구‍할 수 없‍어‍요.';

  @override
  String get onboardingForgotPassword => '비‍밀‍번‍호‍를 잊‍으‍셨‍나‍요?';

  @override
  String get onboardingGiftEducationClosing =>
      '지‍갑‍이 준‍비‍됐‍어‍요. Zcash‍가 프‍라‍이‍버‍시‍를 지‍키‍는 방‍법‍과 어‍떤 주‍소‍를 써‍야 하‍는‍지 알‍아‍보‍세‍요.';

  @override
  String get onboardingGiftEducationSaveFailed =>
      '진‍행 상‍황‍을 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingGoBackDesktop => '돌‍아‍가‍기';

  @override
  String get onboardingHardwareKeystoneOnly => 'Keystone 지‍갑';

  @override
  String get onboardingHardwareLedgerOrKeystone => 'Ledger 또‍는 Keystone 지‍갑';

  @override
  String get onboardingIKnowHowToUseZcash => 'Zcash 사‍용‍법‍을 알‍아‍요';

  @override
  String get onboardingImport => '가‍져‍오‍기';

  @override
  String get onboardingImportAcceptWordCounts =>
      '12, 15, 18, 21 또‍는 24‍개 단‍어‍를 입‍력‍할 수 있‍어‍요.';

  @override
  String get onboardingImportCheckFailedError => '복‍구 문‍구‍를 확‍인‍하‍지 못‍했‍어‍요';

  @override
  String get onboardingImportCheckFailedRetry =>
      '복‍구 문‍구‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingImportChecksumError =>
      '단‍어‍는 모‍두 맞‍지‍만 올‍바‍른 복‍구 문‍구‍가 아‍니‍에‍요. 순‍서‍를 확‍인‍하‍거‍나 잘‍못‍된 것 같‍은 단‍어‍를 바‍꿔 주‍세‍요.';

  @override
  String get onboardingImportClipboardEmpty => '클‍립‍보‍드‍가 비‍어 있‍어‍요';

  @override
  String get onboardingImportClipboardReadError => '클‍립‍보‍드‍를 읽‍을 수 없‍어‍요';

  @override
  String get onboardingImportEnterManuallySemantics => '복‍구 문‍구 직‍접 입‍력';

  @override
  String get onboardingImportFromKeystone => 'Keystone 지‍갑‍에‍서 가‍져‍오‍기';

  @override
  String get onboardingImportFromLedger => 'Ledger 지‍갑‍에‍서 가‍져‍오‍기';

  @override
  String get onboardingImportInvalidPhraseError => '올‍바‍르‍지 않‍은 복‍구 문‍구‍예‍요';

  @override
  String get onboardingImportInvalidSecretPassphrase =>
      '12, 15, 18, 21 또‍는 24‍개 단‍어‍로 된 올‍바‍른 복‍구 문‍구‍를 입‍력‍해 주‍세‍요.';

  @override
  String get onboardingImportManualCardSubtitle => '단‍어‍를 하‍나‍씩 입‍력‍해‍요.';

  @override
  String get onboardingImportManualCardTitle => '복‍구 문‍구\n직‍접 입‍력';

  @override
  String get onboardingImportMethodSubtitle => '원‍하‍는 방‍법‍을 선‍택‍해 주‍세‍요.';

  @override
  String get onboardingImportMethodTitle => 'Vizor‍로\n계‍정 가‍져‍오‍기';

  @override
  String get onboardingImportNoPhraseError => '복‍구 문‍구‍를 찾‍을 수 없‍어‍요';

  @override
  String get onboardingImportPasteFromClipboard => '또‍는 클‍립‍보‍드‍에‍서 붙‍여‍넣‍기';

  @override
  String get onboardingImportPasteHelper =>
      '12, 15, 18, 21 또‍는 24‍개 단‍어‍로 된\n복‍구 문‍구‍를 입‍력‍할 수 있‍어‍요';

  @override
  String get onboardingImportReadingClipboard => '클‍립‍보‍드 읽‍는 중...';

  @override
  String get onboardingImportSecretPassphrase => '복‍구 문‍구 가‍져‍오‍기';

  @override
  String get onboardingImportSecretPassphraseDescriptionDesktop =>
      'Vizor 또‍는 다‍른 Zcash 지‍갑';

  @override
  String get onboardingImportSecretPassphraseDescriptionMobile =>
      'Vizor, ZODL 또‍는 다‍른 지‍갑';

  @override
  String get onboardingImportWalletTitle => '지‍갑 가‍져‍오‍기';

  @override
  String get onboardingImportWalletTitleMobile => '지‍갑 가‍져‍오‍기';

  @override
  String onboardingImportWordCountError(int count) {
    return '복‍구 문‍구‍는 12, 15, 18, 21, 24‍개 단‍어‍로 되‍어 있‍어‍요. 지‍금‍은 $count‍개‍예‍요.';
  }

  @override
  String get onboardingIntroCard =>
      'Bitcoin‍이‍나 Ethereum‍과 달‍리 차‍폐‍된 Zcash 거‍래‍는 보‍낸 사‍람, 받‍는 사‍람, 금‍액‍을 숨‍겨‍요. 신‍뢰‍가 아‍니‍라 암‍호‍학‍으‍로 검‍증‍돼‍요.';

  @override
  String get onboardingIntroClosing =>
      '첫 프‍라‍이‍빗 지‍갑‍까‍지 몇 단‍계‍만 남‍았‍어‍요.\n함‍께 설‍정‍해 볼‍까‍요.';

  @override
  String get onboardingIntroClosingMobile =>
      '첫 프‍라‍이‍빗 지‍갑‍까‍지 몇 단‍계‍만 남‍았‍어‍요. 함‍께 설‍정‍해 볼‍까‍요.';

  @override
  String get onboardingIntroSubtitle =>
      'Zcash(ZEC)는 금‍융 프‍라‍이‍버‍시‍와 자‍기 보‍관‍을 중‍심‍으‍로 만‍들‍어‍졌‍어‍요.';

  @override
  String get onboardingIntroSubtitleMobile =>
      'Zcash(ZEC)는 금‍융 프‍라‍이‍버‍시‍와\n자‍기 보‍관‍을 중‍심‍으‍로 만‍들‍어‍졌‍어‍요.';

  @override
  String get onboardingIntroTitle => '차‍폐‍된 세‍상';

  @override
  String get onboardingLinkVizorDesktop => 'Vizor 데‍스‍크‍톱 연‍결';

  @override
  String get onboardingLinkVizorDesktopDescription =>
      '스‍캔‍해‍서 Vizor 데‍스‍크‍톱‍에 연‍결';

  @override
  String onboardingLostPasswordBody(String resetAction, String importAction) {
    return '비‍밀‍번‍호‍를 잊‍으‍셨‍다‍면 계‍정‍을 복‍구‍하‍는 유‍일‍한 방‍법‍은 $resetAction‍뿐‍이‍에‍요.\n모‍든 계‍정‍과 공‍유‍하‍지 않‍은 기‍프‍트 카‍드 링‍크‍가 삭‍제‍돼‍요.\n이‍후‍에‍는 $importAction.';
  }

  @override
  String get onboardingLostPasswordImportAction => '계‍정‍을 다‍시 가‍져‍와‍야 해‍요';

  @override
  String get onboardingLostPasswordResetAction => 'Vizor 앱‍을 완‍전‍히 초‍기‍화‍하‍는 것';

  @override
  String onboardingLostPasswordResetCountdown(int seconds) {
    return '$seconds‍초 후 초‍기‍화...';
  }

  @override
  String get onboardingLostPasswordTitle => '비‍밀‍번‍호‍를 잊‍으‍셨‍나‍요?';

  @override
  String get onboardingManualInvalidWord => '복‍구 문‍구‍에 없‍는 단‍어‍예‍요.';

  @override
  String get onboardingManualNextWord => '다‍음 단‍어';

  @override
  String onboardingManualStoppedAt(String word) {
    return '\'$word\'에‍서 멈‍췄‍어‍요. 복‍구 문‍구 단‍어 목‍록‍에 없‍는 단‍어‍예‍요.';
  }

  @override
  String get onboardingManualSubtitle =>
      '12, 15, 18, 21 또‍는 24‍개 단‍어‍를 입‍력‍할 수 있‍어‍요';

  @override
  String get onboardingManualTitle => '복‍구 문‍구 입‍력';

  @override
  String get onboardingManualUndoLastWord => '마‍지‍막 단‍어 취‍소';

  @override
  String get onboardingNetworkCheckingEndpoint => '엔‍드‍포‍인‍트 확‍인‍하‍는 중…';

  @override
  String get onboardingNetworkEndpointHelper =>
      '이 지‍갑‍의 네‍트‍워‍크‍용 lightwalletd 서‍버‍를 사‍용‍하‍세‍요.';

  @override
  String get onboardingNetworkVerifyFailed =>
      '해‍당 엔‍드‍포‍인‍트‍를 확‍인‍하‍지 못‍했‍어‍요. 주‍소‍를 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingNext => '다‍음';

  @override
  String get onboardingNotNow => '나‍중‍에';

  @override
  String get onboardingPasscodeCreateTitle => '암‍호 만‍들‍기';

  @override
  String get onboardingPasscodeDeleteSemantics => '숫‍자 지‍우‍기';

  @override
  String onboardingPasscodeDigitSemantics(int digit) {
    return '숫‍자 $digit';
  }

  @override
  String get onboardingPasscodeHelpSemantics => '암‍호 도‍움‍말';

  @override
  String get onboardingPasscodeReEnter => '암‍호‍를 다‍시 입‍력‍해 주‍세‍요.';

  @override
  String get onboardingPasscodeSettingUp => '지‍갑‍을 설‍정‍하‍는 중...';

  @override
  String get onboardingRandomiseAccountPersona =>
      '계‍정 이‍름‍과 프‍로‍필 사‍진 무‍작‍위‍로 바‍꾸‍기';

  @override
  String get onboardingRecoveringWallet => '지‍갑 복‍구‍하‍는 중...';

  @override
  String get onboardingResetAppFailed =>
      '앱‍을 초‍기‍화‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingResumeSetupFailed =>
      '설‍정‍을 이‍어‍가‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingRetrySetup => '설‍정 다‍시 시‍도';

  @override
  String get onboardingRetrying => '다‍시 시‍도‍하‍는 중';

  @override
  String get onboardingReviewClearSecretPassphrase => '복‍구 문‍구 지‍우‍기';

  @override
  String get onboardingReviewConfirmContinue => '확‍인‍하‍고 계‍속';

  @override
  String get onboardingReviewImportSubtitle =>
      '가‍져‍오‍기‍를 시‍작‍하‍기 전‍에\n복‍구 문‍구‍를 확‍인‍해 주‍세‍요.';

  @override
  String get onboardingReviewImportTitle => '가‍져‍오‍기 검‍토';

  @override
  String get onboardingSavingWallet => '지‍갑 저‍장‍하‍는 중...';

  @override
  String get onboardingSecretPassphraseAboutToSee => '곧 복‍구 문‍구‍가 표‍시‍돼‍요.';

  @override
  String get onboardingSecretPassphraseAboutToSeeMobile =>
      '곧 복‍구 문‍구‍가\n표‍시‍돼‍요.';

  @override
  String get onboardingSecretPassphraseReveal => '문‍구 보‍기';

  @override
  String get onboardingSecretPassphraseRevealMobile => '문‍구 보‍기';

  @override
  String get onboardingSecretPassphraseSubtitleDesktop => '지‍갑‍의 마‍스‍터 키‍예‍요.';

  @override
  String get onboardingSecretPassphraseSubtitleMobile => '지‍갑‍의 마‍스‍터 키‍예‍요.';

  @override
  String get onboardingSecretPassphraseWarning =>
      '이 문‍구‍는 내 자‍금‍의 마‍스‍터 키‍예‍요. 안‍전‍하‍게 보‍관‍하‍고 절‍대 공‍개‍하‍지 마‍세‍요. 잃‍어‍버‍리‍면 누‍구‍도 지‍갑 복‍구‍를 도‍와‍줄 수 없‍어‍요. 저‍희‍도 마‍찬‍가‍지‍예‍요.';

  @override
  String get onboardingSeedWordHint => '단‍어';

  @override
  String get onboardingSetPasswordAndFinish => '비‍밀‍번‍호 설‍정‍하‍고 완‍료';

  @override
  String get onboardingSetPasswordPlaceholder => '8‍자 이‍상, 기‍호 포‍함';

  @override
  String get onboardingSetPasswordSubtitle =>
      'Vizor 지‍갑‍에 로‍그‍인‍할 비‍밀‍번‍호‍를 설‍정‍해 주‍세‍요.';

  @override
  String get onboardingSettingPassword => '비‍밀‍번‍호 설‍정‍하‍는 중...';

  @override
  String get onboardingSetupInterrupted =>
      '설‍정‍이 중‍단‍됐‍어‍요. 다‍시 시‍도‍해‍서 지‍갑‍을 복‍구‍해 주‍세‍요.';

  @override
  String get onboardingStepAddressTypes => '주‍소 유‍형';

  @override
  String get onboardingStepImportContacts => '연‍락‍처 가‍져‍오‍기';

  @override
  String get onboardingStepIntroToZcash => 'Zcash 소‍개';

  @override
  String get onboardingStepSetPassword => '비‍밀‍번‍호 설‍정';

  @override
  String get onboardingStepWalletBirthdayHeight => '지‍갑 생‍성 높‍이';

  @override
  String get onboardingStopSyncing => '동‍기‍화‍를 중‍지‍하‍는 중...';

  @override
  String get onboardingStorageDbMigrationBody =>
      '이 버‍전‍을 열‍려‍면 Vizor‍가 로‍컬 지‍갑 데‍이‍터‍베‍이‍스‍를 업‍데‍이‍트‍해‍야 해‍요. 다‍시 시‍도‍하‍거‍나 Vizor‍를 종‍료‍한 뒤 다‍시 실‍행‍해 주‍세‍요.';

  @override
  String get onboardingStorageDbMigrationTitle =>
      '지‍갑 데‍이‍터‍베‍이‍스‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요';

  @override
  String get onboardingStorageKeyringLockedBody =>
      '지‍갑‍을 열‍려‍면 Vizor‍가 시‍스‍템 키‍링‍에 접‍근‍할 수 있‍어‍야 해‍요. 키‍링‍을 잠‍금 해‍제‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingStorageRetrySecureStorageFailed =>
      '보‍안 저‍장‍소‍를 아‍직 사‍용‍할 수 없‍어‍요.';

  @override
  String get onboardingStorageRetryWalletDbFailed =>
      '지‍갑 데‍이‍터‍베‍이‍스‍를 여‍전‍히 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String get onboardingStorageSecureStorageLockedBody =>
      '지‍갑‍을 열‍려‍면 Vizor‍가 보‍안 저‍장‍소‍에 접‍근‍할 수 있‍어‍야 해‍요. 보‍안 저‍장‍소‍를 잠‍금 해‍제‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingStorageSecureStorageLockedTitle =>
      '보‍안 저‍장‍소‍가 잠‍겨 있‍어‍요';

  @override
  String get onboardingStorageStartupFailureBody =>
      'Vizor‍가 로‍컬 시‍작 상‍태‍를 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 Vizor‍를 종‍료‍한 뒤 다‍시 실‍행‍해 주‍세‍요.';

  @override
  String get onboardingStorageStartupFailureDetail =>
      'Vizor‍가 시‍작 상‍태‍를 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get onboardingSubmitFailed =>
      '이 단‍계‍를 마‍치‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingTellMeHowZcashWorks => 'Zcash 작‍동 방‍식 알‍아‍보‍기';

  @override
  String get onboardingThingsKeepPrivacyBody =>
      '일‍부 거‍래‍소‍는 차‍폐 주‍소‍로 보‍낼 수 없‍어‍요. 거‍래‍소‍에‍서 출‍금‍한‍다‍면 투‍명 주‍소‍를 사‍용‍하‍세‍요. ZEC‍가 도‍착‍한 뒤‍에 차‍폐‍할 수 있‍어‍요.';

  @override
  String get onboardingThingsKeepPrivacyTitle => '프‍라‍이‍버‍시 지‍키‍는 방‍법';

  @override
  String get onboardingThingsSubtitleMobile => '시‍작‍하‍기 전‍에 확‍인‍해 주‍세‍요.';

  @override
  String get onboardingThingsTimeToSyncBody =>
      '지‍갑‍은 서‍버‍에 의‍존‍하‍지 않‍고 Zcash 네‍트‍워‍크‍와 직‍접 동‍기‍화‍해‍요. 프‍라‍이‍버‍시‍는 지‍켜‍지‍지‍만 시‍간‍이 조‍금 걸‍려‍요. 앱‍이 따‍라‍잡‍는 동‍안‍에‍도 자‍금‍은 안‍전‍해‍요.';

  @override
  String get onboardingThingsTimeToSyncTitle => '동‍기‍화 시‍간';

  @override
  String get onboardingThingsToKnow => '알‍아 둘 점';

  @override
  String get onboardingUnknownHeightBody =>
      '지‍갑 생‍성 높‍이 없‍이 계‍속‍하‍면 Vizor‍가 지‍원‍하‍는 가‍장 오‍래‍된 차‍폐 높‍이‍부‍터 스‍캔‍해‍요. 안‍전‍하‍지‍만 첫 동‍기‍화‍에 아‍주 오‍랜 시‍간‍이 걸‍릴 수 있‍어‍요.';

  @override
  String get onboardingUnknownHeightHint => '대‍략‍적‍인 날‍짜‍만 골‍라‍도 훨‍씬 빨‍라‍요.';

  @override
  String get onboardingUnknownHeightTitle => '가‍장 오‍래‍된 높‍이‍부‍터 가‍져‍올‍까‍요?';

  @override
  String get onboardingUnlockBiometricReason => '지‍갑 잠‍금 해‍제';

  @override
  String get onboardingUnlockDescription =>
      'Vizor‍를 열‍려‍면 비‍밀‍번‍호‍를 입‍력‍해 주‍세‍요.';

  @override
  String get onboardingUnlockEnterPasscode => 'Vizor‍를 열‍려‍면 암‍호‍를 입‍력‍해 주‍세‍요';

  @override
  String get onboardingUnlockIncorrectPassword =>
      '비‍밀‍번‍호‍가 맞‍지 않‍아‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingUnlockOpenFailed =>
      '지‍갑‍을 열‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get onboardingUnlockOpening => '지‍갑‍을 여‍는 중...';

  @override
  String get onboardingUnlockWelcomeBack => '다‍시 오‍셨‍네‍요';

  @override
  String get onboardingWalletLinkNetworkMismatch =>
      '이 지‍갑 링‍크‍는 다‍른 Zcash 네‍트‍워‍크‍용‍이‍에‍요.';

  @override
  String get onboardingWelcome => '시‍작 화‍면';

  @override
  String get onboardingWelcomeActivateGiftCard => '기‍프‍트 카‍드 활‍성‍화';

  @override
  String get onboardingWelcomeGetStarted => '시‍작‍하‍기';

  @override
  String get onboardingWelcomeImportWallet => '지‍갑 가‍져‍오‍기';

  @override
  String get passcodeConfirmTitle => '암‍호 확‍인';

  @override
  String get passcodeIncorrect => '암‍호‍가 맞‍지 않‍아‍요';

  @override
  String get passcodeSixDigits => '6‍자‍리 숫‍자';

  @override
  String get passcodesDidNotMatch => '암‍호‍가 일‍치‍하‍지 않‍아‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get passwordCheckFailed =>
      '비‍밀‍번‍호‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get passwordConfirmLabel => '비‍밀‍번‍호 확‍인';

  @override
  String get passwordIncorrect => '비‍밀‍번‍호‍가 맞‍지 않‍아‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get passwordLabel => '비‍밀‍번‍호';

  @override
  String get passwordPolicyAscii => '영‍문, 숫‍자, 기‍호‍만 사‍용‍하‍세‍요.';

  @override
  String passwordPolicyMinLength(int min) {
    return '비‍밀‍번‍호‍는 $min‍자 이‍상‍이‍어‍야 해‍요.';
  }

  @override
  String get passwordPolicyMustDiffer => '다‍른 비‍밀‍번‍호‍를 사‍용‍하‍세‍요.';

  @override
  String get passwordsDoNotMatch => '비‍밀‍번‍호‍가 일‍치‍하‍지 않‍아‍요.';

  @override
  String get payAddToContacts => '연‍락‍처‍에 추‍가';

  @override
  String payAddressSemantics(String address) {
    return '주‍소 $address';
  }

  @override
  String get payAmountChooseAsset => '결‍제 자‍산 선‍택';

  @override
  String payAmountEnterIn(String symbol) {
    return '$symbol 단‍위‍로 금‍액 입‍력';
  }

  @override
  String get payAmountEstimated => '예‍상:';

  @override
  String get payAmountEstimatedSpend => '예‍상 지‍출';

  @override
  String get payAmountPayingFrom => '결‍제‍에 사‍용‍할 잔‍액:';

  @override
  String get payAmountPayingIn => '결‍제 자‍산';

  @override
  String get payBackHome => '홈';

  @override
  String get payFetchingQuote => '견‍적 가‍져‍오‍는 중';

  @override
  String get payNewAddressDetected => '새 주‍소‍가 감‍지‍되‍었‍어‍요.';

  @override
  String get payNewAddressWarning => '이 주‍소‍와 거‍래‍한 적‍이 없‍어‍요.';

  @override
  String payRecentDaysAgo(int days) {
    return '$days‍일 전';
  }

  @override
  String payRecentHoursAgo(int hours) {
    return '$hours‍시‍간 전';
  }

  @override
  String payRecentMinutesAgo(int minutes) {
    return '$minutes‍분 전';
  }

  @override
  String get payRecentlySent => '최‍근 보‍낸 주‍소';

  @override
  String get payRecents => '최‍근';

  @override
  String get payRecipientAddressHint => '주‍소‍를 붙‍여‍넣‍거‍나 QR 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String get payRecipientAddressLabel => '받‍는 주‍소';

  @override
  String get payRefreshingQuote => '견‍적 새‍로‍고‍침 중';

  @override
  String get payReviewConfirmPay => '확‍인‍하‍고 결‍제';

  @override
  String get payReviewConvertedAmount => '변‍환 금‍액';

  @override
  String get payReviewPaying => '결‍제 금‍액';

  @override
  String get payReviewQuoteExpired => '견‍적‍이 만‍료‍되‍었‍어‍요';

  @override
  String get payReviewQuoteExpiresIn => '견‍적 만‍료‍까‍지 ';

  @override
  String get payReviewRefreshQuote => '견‍적 새‍로‍고‍침';

  @override
  String get payReviewRefreshTheQuote => '견‍적 새‍로‍고‍침';

  @override
  String get payReviewReturnToPay => '결‍제‍로 돌‍아‍가‍기';

  @override
  String get payReviewUnknownAddress => '알 수 없‍는 주‍소';

  @override
  String get paySaveContactError => '연‍락‍처‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get payScanBarrierDismiss => '닫‍기';

  @override
  String get payScanCaption => '받‍는 주‍소 QR 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String get payScanPermissionTitle => '받‍는 주‍소 스‍캔';

  @override
  String get payScanQrSubtitle => '카‍메‍라‍로 주‍소‍를 스‍캔‍해‍요';

  @override
  String get payScanQrTitle => 'QR 코‍드 스‍캔';

  @override
  String get paySelectRecipient => '받‍는 사‍람 선‍택';

  @override
  String get payStepRecipient => '받‍는 사‍람';

  @override
  String get payStepReview => '검‍토';

  @override
  String get paySubmittedFailedBody =>
      '결‍제‍를 제‍출‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paySubmittedGoToActivity => '활‍동‍으‍로 이‍동';

  @override
  String get paySubmittedStatusUncertainNotice =>
      '결‍제 상‍태‍가 확‍실‍하‍지 않‍아‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get paySubmittedSubmittingBody => '결‍제‍를 네‍트‍워‍크‍에 제‍출‍하‍고 있‍어‍요...';

  @override
  String get paySubmittedSubmittingTitle => '결‍제 제‍출 중...';

  @override
  String get paySubmittedSucceededBody =>
      '곧 온‍체‍인‍에‍서 확‍인‍돼‍요.\n활‍동‍에‍서 진‍행 상‍황‍을 확‍인‍해 보‍세‍요.';

  @override
  String get paySubmittedSucceededTitle => '결‍제‍를\n제‍출‍했‍어‍요';

  @override
  String get paySubmittedUnavailableNotice =>
      '이 결‍제‍를 불‍러‍오‍지 못‍했‍어‍요. 최‍신 상‍태‍는 활‍동‍에‍서 확‍인‍해 주‍세‍요.';

  @override
  String get paySubmittedUnavailableTitle => '결‍제‍를 불‍러‍올 수 없‍어‍요';

  @override
  String get paySubmittedUncertainTitle => '결‍제 상‍태‍가\n확‍실‍하‍지 않‍아‍요';

  @override
  String payTitleAmount(String symbol) {
    return '$symbol 결‍제';
  }

  @override
  String get paymentLinkAboveMaximumZec => '보‍유‍한 최‍대 ZEC‍를 초‍과‍했‍어‍요';

  @override
  String get paymentLinkAccountChangedRedeemAgain =>
      '선‍택‍한 계‍정‍이 바‍뀌‍었‍어‍요. 새 계‍정‍으‍로 받‍으‍려‍면 이 기‍프‍트 카‍드‍를 다‍시 받‍아 주‍세‍요.';

  @override
  String get paymentLinkAccountChangedReviewAmount =>
      '선‍택‍한 계‍정‍이 바‍뀌‍었‍어‍요. 기‍프‍트 카‍드 금‍액‍과 수‍수‍료‍를 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkActiveAccountChangedReviewAmount =>
      '선‍택‍한 계‍정‍이 바‍뀌‍었‍어‍요. 금‍액‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkAlmostReadyHeading => '기‍프‍트 카‍드‍가\n거‍의 준‍비‍됐‍어‍요!';

  @override
  String get paymentLinkAlmostReadyReceivedHeading =>
      '기‍프‍트 카‍드‍가\n거‍의 준‍비‍됐‍어‍요!';

  @override
  String paymentLinkAmountCurrencyDisabledSemantic(
    String currency,
    String reason,
  ) {
    return '$currency‍로 금‍액 입‍력. $reason';
  }

  @override
  String get paymentLinkAmountEnterDollars => '달‍러‍를 입‍력‍하‍세‍요';

  @override
  String get paymentLinkAmountInputSemantic => '기‍프‍트 카‍드 금‍액 입‍력';

  @override
  String get paymentLinkAmountStepSubtitleDesktop =>
      '금‍액‍을 입‍력‍하‍고 디‍자‍인‍을 선‍택‍하‍세‍요.';

  @override
  String get paymentLinkAmountStepSubtitleMobile =>
      '금‍액‍을 입‍력‍하‍고 디‍자‍인‍을 고‍르‍세‍요.';

  @override
  String get paymentLinkApproveAndCreate => '승‍인‍하‍고 만‍들‍기';

  @override
  String paymentLinkArchivedCount(int count) {
    return '보‍관‍됨 ($count)';
  }

  @override
  String get paymentLinkArchivedHeading => '보‍관‍됨';

  @override
  String get paymentLinkArtworkChestCave => '수‍정 동‍굴‍의 상‍자';

  @override
  String get paymentLinkArtworkChestLava => '용‍암 동‍굴‍의 상‍자';

  @override
  String get paymentLinkArtworkCoin => 'Zcash 코‍인';

  @override
  String get paymentLinkArtworkCrystal => '수‍정';

  @override
  String get paymentLinkArtworkDiamond => '다‍이‍아‍몬‍드';

  @override
  String get paymentLinkArtworkDragon => '드‍래‍곤';

  @override
  String get paymentLinkArtworkGift => '선‍물 상‍자';

  @override
  String get paymentLinkArtworkKnightMagic => '마‍법 기‍사';

  @override
  String get paymentLinkArtworkRogueCat => '도‍적 고‍양‍이';

  @override
  String get paymentLinkArtworkRuby => '루‍비';

  @override
  String get paymentLinkAvailabilityCheckingDescription =>
      '받‍기 결‍과‍가 아‍직 확‍인‍되‍지 않‍았‍어‍요. 잠‍시 후 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkAvailabilityCheckingResult => '결‍과 확‍인 중';

  @override
  String get paymentLinkAvailabilityClaim => '받‍기';

  @override
  String get paymentLinkAvailabilityClaimFailed => '받‍기 실‍패';

  @override
  String get paymentLinkAvailabilityFailedDescription =>
      '받‍기‍가 완‍료‍되‍지 않‍았‍어‍요. 다‍시 시‍도‍하‍기 전‍에 카‍드‍를 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkAvailabilityNoBalance => '잔‍액 없‍음';

  @override
  String get paymentLinkAvailabilityNoBalanceDescription =>
      '지‍금‍은 받‍을 수 있‍는 잔‍액‍이 없‍어‍요.';

  @override
  String get paymentLinkAvailabilityReadyDescription =>
      '이 기‍프‍트 카‍드‍를 받‍을 수 있‍어‍요.';

  @override
  String get paymentLinkAvailabilityRejectedDescription =>
      '네‍트‍워‍크‍가 이 받‍기 요‍청‍을 받‍아‍들‍이‍지 않‍았‍어‍요. 다‍시 시‍도‍하‍기 전‍에 상‍태‍를 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkBackToGiftCard => '기‍프‍트 카‍드‍로 돌‍아‍가‍기';

  @override
  String get paymentLinkBatchAddCard => '카‍드 한 장 추‍가';

  @override
  String get paymentLinkBatchCardsInGroup => '이 그‍룹‍의 카‍드';

  @override
  String get paymentLinkBatchCheckFailed => '일‍부 카‍드‍를 확‍인‍하‍지 못‍했‍어‍요';

  @override
  String get paymentLinkBatchCheckingUse => '카‍드 사‍용 여‍부 확‍인 중…';

  @override
  String get paymentLinkBatchChooseLocation => '위‍치 선‍택';

  @override
  String paymentLinkBatchCopyLinkSemantic(String number) {
    return '카‍드 $number 링‍크 복‍사';
  }

  @override
  String paymentLinkBatchCountSemantic(int max) {
    return '카‍드 수, 2~$max‍장';
  }

  @override
  String paymentLinkBatchCreated(String date) {
    return '$date‍에 만‍듦';
  }

  @override
  String get paymentLinkBatchDetailsNotSaved =>
      '카‍드 정‍보‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkBatchFeeChanged =>
      '네‍트‍워‍크 수‍수‍료‍가 바‍뀌‍었‍어‍요. 새 총‍액‍을 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkBatchFundedNotSaved =>
      '충‍전‍은 전‍송‍됐‍지‍만 카‍드‍를 저‍장‍하‍지 못‍했‍어‍요. Vizor‍를 닫‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String paymentLinkBatchGiftCardsCount(int count) {
    return '기‍프‍트 카‍드 $count‍장';
  }

  @override
  String get paymentLinkBatchLinksShareableLater =>
      '결‍제‍가 확‍인‍되‍면 링‍크‍를 공‍유‍할 수 있‍어‍요.';

  @override
  String get paymentLinkBatchMessageOptional => '메‍시‍지 (선‍택)';

  @override
  String get paymentLinkBatchMessageOptionalEveryCard =>
      '메‍시‍지 (선‍택), 모‍든 카‍드‍에 표‍시‍돼‍요';

  @override
  String get paymentLinkBatchNoneFunded =>
      '충‍전‍된 카‍드‍가 없‍어‍요. 금‍액‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkBatchNotAllReady =>
      '이 그‍룹‍의 일‍부 카‍드‍가 아‍직 준‍비‍되‍지 않‍았‍어‍요. 모‍든 카‍드‍가 준‍비‍될 때‍까‍지 링‍크‍를 공‍유‍하‍지 마‍세‍요.';

  @override
  String get paymentLinkBatchOverBalance =>
      '사‍용 가‍능‍한 잔‍액‍에 맞‍게 금‍액‍이‍나 카‍드 수‍를 줄‍여 주‍세‍요.';

  @override
  String get paymentLinkBatchPaymentUnconfirmed =>
      'Vizor‍가 결‍제‍가 전‍송‍되‍었‍는‍지 확‍인‍하‍지 못‍했‍어‍요. 이 카‍드‍를 보‍관‍하‍고, 링‍크‍를 공‍유‍하‍기 전‍에 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkBatchPrepareFailed => '이 카‍드‍들‍을 준‍비‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkBatchPreviousAccount =>
      '카‍드‍가 이‍전 계‍정‍으‍로 만‍들‍어‍졌‍어‍요. 보‍려‍면 다‍시 전‍환‍하‍세‍요.';

  @override
  String get paymentLinkBatchQuoteNotReady =>
      '사‍용 가‍능‍한 잔‍액‍을 아‍직 불‍러‍오‍는 중‍이‍에‍요. 지‍갑 동‍기‍화 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkBatchRejectedKeystoneSapling =>
      '이 그‍룹‍은 Keystone‍이 서‍명‍할 수 없‍는 예‍전 Sapling 자‍금‍을 써‍야 해‍요. 카‍드 수‍를 줄‍이‍거‍나 카‍드‍당 금‍액‍을 낮‍춰 보‍세‍요.';

  @override
  String get paymentLinkBatchRejectedKeystoneSignatureLimit =>
      '이 그‍룹‍은 Keystone‍이 한 번‍에 서‍명‍할 수 있‍는 것‍보‍다 많‍은 입‍력‍이 필‍요‍해‍요. 카‍드 수‍를 줄‍이‍거‍나 카‍드‍당 금‍액‍을 낮‍춰 보‍세‍요.';

  @override
  String paymentLinkBatchRejectedLedgerRecipientLimit(String max) {
    return '이 그‍룹‍의 차‍폐 수‍신‍자‍가 Ledger‍가 표‍시‍할 수 있‍는 수(최‍대 $max‍명)보‍다 많‍아‍요. 카‍드 수‍를 줄‍이‍거‍나 카‍드‍당 금‍액‍을 낮‍춰 보‍세‍요.';
  }

  @override
  String get paymentLinkBatchRejectedLedgerSapling =>
      '이 그‍룹‍은 Ledger‍가 서‍명‍할 수 없‍는 예‍전 Sapling 자‍금‍을 써‍야 해‍요. 카‍드 수‍를 줄‍이‍거‍나 카‍드‍당 금‍액‍을 낮‍춰 보‍세‍요.';

  @override
  String get paymentLinkBatchRejectedLedgerTooLarge =>
      '이 그‍룹‍은 Ledger‍가 서‍명‍하‍기‍에 너‍무 커‍요. 카‍드 수‍를 줄‍이‍거‍나 카‍드‍당 금‍액‍을 낮‍춰 보‍세‍요.';

  @override
  String get paymentLinkBatchRejectedNotOneTransaction =>
      '이 그‍룹‍은 거‍래 한 번‍으‍로 충‍전‍할 수 없‍어‍요. 카‍드 수‍를 줄‍이‍거‍나 카‍드‍당 금‍액‍을 낮‍춰 보‍세‍요.';

  @override
  String get paymentLinkBatchRemoveCard => '카‍드 한 장 빼‍기';

  @override
  String paymentLinkBatchRowSemantic(
    String number,
    String status,
    String failed,
  ) {
    String _temp0 = intl.Intl.selectLogic(failed, {
      'true': ', 업‍데‍이‍트 실‍패',
      'other': '',
    });
    return '카‍드 $number, $status$_temp0';
  }

  @override
  String paymentLinkBatchRowTitle(String number) {
    return '카‍드 $number';
  }

  @override
  String get paymentLinkBatchRowUpdateFailed => '업‍데‍이‍트‍하‍지 못‍했‍어‍요';

  @override
  String get paymentLinkBatchSaveAllCsv => '모‍든 링‍크‍를 CSV‍로 저‍장';

  @override
  String get paymentLinkBatchSaveLinksTitle => '기‍프‍트 카‍드 링‍크 저‍장';

  @override
  String get paymentLinkBatchSaveLinksWarning =>
      '이 파‍일‍이 있‍는 사‍람‍은 누‍구‍나 이 카‍드‍를 받‍을 수 있‍어‍요. 다‍른 사‍람‍이 접‍근‍할 수 없‍는 곳‍에 저‍장‍해 주‍세‍요.';

  @override
  String paymentLinkBatchShowQrSemantic(String number) {
    return '카‍드 $number QR 코‍드 보‍기';
  }

  @override
  String get paymentLinkBatchUncertain =>
      'Vizor‍가 결‍제‍가 전‍송‍되‍었‍는‍지 확‍인‍하‍지 못‍했‍어‍요. 다‍른 그‍룹‍을 만‍들‍기 전‍에 기‍프‍트 카‍드‍에‍서 이 그‍룹‍을 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkBatchUseNotChecked =>
      '카‍드 사‍용 여‍부‍를 아‍직 확‍인‍하‍지 않‍았‍어‍요';

  @override
  String get paymentLinkBulkAmountPerCard => '카‍드‍당 금‍액';

  @override
  String get paymentLinkBulkBalanceLoading => '잔‍액 불‍러‍오‍는 중';

  @override
  String get paymentLinkBulkCardDesign => '카‍드 디‍자‍인';

  @override
  String paymentLinkBulkCountSemantic(int count) {
    return '카‍드 $count‍장';
  }

  @override
  String paymentLinkBulkCreateCards(int count) {
    return '카‍드 $count‍장 만‍들‍기';
  }

  @override
  String get paymentLinkBulkCreateMultiple => '카‍드 여‍러 장 만‍들‍기';

  @override
  String get paymentLinkBulkDifferentDesign => '카‍드‍마‍다 다‍른 디‍자‍인';

  @override
  String get paymentLinkBulkEditCards => '카‍드 편‍집';

  @override
  String paymentLinkBulkLedgerLimit(int max) {
    return 'Ledger‍로 한 번‍에 최‍대 $max‍장‍까‍지 만‍들 수 있‍어‍요.';
  }

  @override
  String paymentLinkBulkReviewCards(int count) {
    return '카‍드 $count‍장 검‍토';
  }

  @override
  String paymentLinkBulkZecAvailable(String amount) {
    return '사‍용 가‍능 $amount ZEC';
  }

  @override
  String get paymentLinkCardAmountLabel => '카‍드 금‍액';

  @override
  String get paymentLinkCardBalanceCheckFailed =>
      '카‍드 잔‍액‍을 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String paymentLinkCardDesignSemantic(String design) {
    return '$design 카‍드 디‍자‍인';
  }

  @override
  String get paymentLinkCardFeeHelpText =>
      '카‍드 생‍성 수‍수‍료‍와 받‍을 때 쓰‍도‍록 남‍겨 둔 수‍수‍료‍가 포‍함‍돼‍요.';

  @override
  String get paymentLinkCardFeeLabel => '카‍드 수‍수‍료 (입‍금 + 받‍기)';

  @override
  String get paymentLinkCardRemoveFailed =>
      '카‍드‍를 삭‍제‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkCardStatusCheckFailed =>
      '카‍드 상‍태‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkCardUnreadable => '이 카‍드‍를 읽‍을 수 없‍어‍요.';

  @override
  String get paymentLinkCardUpdateFailed =>
      '카‍드‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkCardsLoadFailed => '기‍프‍트 카‍드‍를 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String paymentLinkCheckProgress(String phase, String percent) {
    String _temp0 = intl.Intl.selectLogic(phase, {
      'finding': '선‍물‍을 찾‍는 중',
      'other': '선‍물‍을 확‍인‍하‍는 중',
    });
    return '$_temp0… $percent%';
  }

  @override
  String get paymentLinkCheckStatus => '상‍태 확‍인';

  @override
  String paymentLinkCheckedHoursAgo(int hours) {
    return '$hours‍시‍간 전‍에 확‍인‍함';
  }

  @override
  String get paymentLinkCheckedJustNow => '방‍금 확‍인‍함';

  @override
  String paymentLinkCheckedMinutesAgo(int minutes) {
    return '$minutes‍분 전‍에 확‍인‍함';
  }

  @override
  String paymentLinkCheckedOnDate(String date) {
    return '$date‍에 확‍인‍함';
  }

  @override
  String get paymentLinkCheckingGiftEllipsis => '선‍물‍을 확‍인‍하‍는 중…';

  @override
  String get paymentLinkCheckingGiftFull => '선‍물‍을 확‍인‍하‍는 중… 100%';

  @override
  String get paymentLinkChooseReceivingAccount => '받‍을 계‍정 선‍택';

  @override
  String get paymentLinkClaimAccountPrepareFailed =>
      '이 선‍물‍을 준‍비‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 다‍른 계‍정‍을 선‍택‍해 주‍세‍요.';

  @override
  String get paymentLinkClaimActionCreateAccount => '계‍정‍을 만‍들‍어 받‍기';

  @override
  String get paymentLinkClaimActionCreateWallet => '지‍갑‍을 만‍들‍어 받‍기';

  @override
  String get paymentLinkClaimActionExistingWallet => '기‍존 지‍갑‍으‍로 받‍기';

  @override
  String get paymentLinkClaimCheckingDescription =>
      '이 기‍프‍트 카‍드‍를 이‍미\n받‍았‍는‍지 확‍인‍하‍고 있‍어‍요.';

  @override
  String get paymentLinkClaimCheckingHeading => '기‍프‍트 카‍드‍를\n확‍인‍하‍고 있‍어‍요';

  @override
  String get paymentLinkClaimFailedMaybePending =>
      '기‍프‍트 카‍드 받‍기‍에 실‍패‍했‍어‍요. 아‍직 확‍인‍을 기‍다‍리‍는 중‍이‍거‍나 이‍미 사‍용‍됐‍을 수 있‍어‍요.';

  @override
  String get paymentLinkClaimFailureToast => '기‍프‍트 카‍드‍를 받‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkClaimGiftButton => '선‍물 받‍기';

  @override
  String get paymentLinkClaimInFlightError => '이‍미 받‍고 있‍는 기‍프‍트 카‍드‍예‍요.';

  @override
  String get paymentLinkClaimOtherNetworkError =>
      '다‍른 Zcash 네‍트‍워‍크‍용 기‍프‍트 카‍드‍예‍요.';

  @override
  String get paymentLinkClaimQueueFull =>
      '기‍다‍리‍는 기‍프‍트 카‍드‍가 너‍무 많‍아‍요. 다‍른 카‍드‍를 먼‍저 마‍무‍리‍해 주‍세‍요.';

  @override
  String get paymentLinkClaimResultNotConfirmed =>
      '받‍기 결‍과‍가 확‍인‍되‍지 않‍았‍어‍요. 상‍태‍를 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkClaimSaveFailed =>
      '카‍드‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkClaimStatusAlreadyClaimed => '이 선‍물‍은 이‍미 받‍았‍어‍요.';

  @override
  String get paymentLinkClaimStatusAskSender =>
      '보‍낸 사‍람‍에‍게 새 카‍드‍를 요‍청‍해 보‍세‍요.';

  @override
  String get paymentLinkClaimStatusCheckConnection =>
      '연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkClaimStatusCreateAccountNow => '지‍금 계‍정‍을 만‍들 수 있‍어‍요.';

  @override
  String get paymentLinkClaimStatusCreateAccountOrUseOne =>
      '계‍정‍을 만‍들‍거‍나 이‍미 있‍는 계‍정‍으‍로 받‍을 수 있‍어‍요.';

  @override
  String get paymentLinkClaimStatusCreateWalletNow => '지‍금 지‍갑‍을 만‍들 수 있‍어‍요.';

  @override
  String get paymentLinkClaimStatusCreateWalletOrUseOne =>
      '지‍갑‍을 만‍들‍거‍나 이‍미 있‍는 지‍갑‍으‍로 받‍을 수 있‍어‍요.';

  @override
  String get paymentLinkClaimStatusGiftFound => '선‍물‍을 찾‍았‍어‍요';

  @override
  String get paymentLinkClaimStatusMayNotBeFunded =>
      '보‍낸 사‍람‍이 아‍직 충‍전‍하‍지 않‍았‍을 수 있‍어‍요.';

  @override
  String get paymentLinkClaimStatusNetworkUnreachable =>
      '네‍트‍워‍크‍에 연‍결‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkClaimStatusOtherNetwork =>
      '이 기‍프‍트 카‍드‍는 다‍른 네‍트‍워‍크‍용‍이‍에‍요.';

  @override
  String paymentLinkClaimStatusWaitingDeposit(int count, int target) {
    return '입‍금 확‍인 대‍기 중 · $count/$target';
  }

  @override
  String get paymentLinkClaimSubmitted => '선‍물 받‍기‍를 제‍출‍했‍어‍요';

  @override
  String get paymentLinkClaimTheGift => '선‍물 받‍기';

  @override
  String get paymentLinkClaimTheGiftCard => '기‍프‍트 카‍드 받‍기';

  @override
  String get paymentLinkClaimWaitingDescription => '곧 선‍물‍을 받‍을 수 있‍어‍요.';

  @override
  String get paymentLinkClaimedElsewhereDescription =>
      '이 카‍드‍는 다‍른 지‍갑‍에‍서 먼‍저 받‍았‍어‍요. 잔‍액‍은 바‍뀌‍지 않‍았‍어‍요.';

  @override
  String get paymentLinkClaimedElsewhereLabel => '다‍른 곳‍에‍서 받‍음';

  @override
  String get paymentLinkClaiming => '받‍는 중…';

  @override
  String get paymentLinkClearClipboardLabel => '클‍립‍보‍드 지‍우‍기';

  @override
  String get paymentLinkClickToRevealMessage =>
      '카‍드‍를 클‍릭‍하‍면 메‍시‍지‍를 볼 수 있‍어‍요.';

  @override
  String get paymentLinkClickToRevealShort => '카‍드‍를 클‍릭‍하‍면 볼 수 있‍어‍요';

  @override
  String get paymentLinkConfirmGiftCardTitle => '기‍프‍트 카‍드 확‍인';

  @override
  String get paymentLinkCopyLinkAgainHint =>
      '설‍정 → 내 기‍프‍트 카‍드‍에‍서 이 링‍크‍를 다‍시 복‍사‍할 수 있‍어‍요.';

  @override
  String get paymentLinkCopyLinkSemanticLabel => '기‍프‍트 카‍드 링‍크 복‍사';

  @override
  String get paymentLinkCopying => '복‍사 중…';

  @override
  String get paymentLinkCostAdditionalZecNeeded => '추‍가‍로 필‍요‍한 ZEC';

  @override
  String paymentLinkCostAtLeast(String amount) {
    return '최‍소 $amount';
  }

  @override
  String get paymentLinkCostCalculatingFee => '네‍트‍워‍크 수‍수‍료 계‍산 중';

  @override
  String paymentLinkCostCardsMultiplier(int count) {
    return '× 카‍드 $count‍장';
  }

  @override
  String get paymentLinkCostMessageOnEveryCard => '모‍든 카‍드‍의 메‍시‍지';

  @override
  String get paymentLinkCostPerCard => '카‍드‍당';

  @override
  String paymentLinkCostPerCardBreakdown(String amount, String fee) {
    return '$amount ZEC + 받‍기 수‍수‍료 $fee ZEC';
  }

  @override
  String get paymentLinkCostWaitingForSync => '동‍기‍화 대‍기 중';

  @override
  String get paymentLinkCostYouWillSpend => '총 사‍용 금‍액';

  @override
  String get paymentLinkCreateCardButton => '카‍드 만‍들‍기';

  @override
  String get paymentLinkCreateCardLabel => '카‍드 만‍들‍기';

  @override
  String get paymentLinkCreateGiftCardTitle => '기‍프‍트 카‍드 만‍들‍기';

  @override
  String get paymentLinkCreateNewCard => '새 카‍드 만‍들‍기';

  @override
  String get paymentLinkCreationFailed =>
      '기‍프‍트 카‍드‍를 만‍들‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkDeleteMessageSemantic => '기‍프‍트 카‍드 메‍시‍지 삭‍제';

  @override
  String get paymentLinkEmptyTitle => '아‍직 기‍프‍트 카‍드‍가 없‍어‍요';

  @override
  String get paymentLinkEnterValidAmount => '올‍바‍른 기‍프‍트 카‍드 금‍액‍을 입‍력‍하‍세‍요.';

  @override
  String get paymentLinkEntryExplainAccountDesktop =>
      '카‍드‍를 받‍으‍면 카‍드 잔‍액‍이 들‍어 있‍는 새 계‍정‍이 지‍갑‍에 만‍들‍어‍져‍요.';

  @override
  String get paymentLinkEntryExplainWalletDesktop =>
      '카‍드‍를 받‍으‍면 카‍드 잔‍액‍이 들‍어 있‍는 새 Vizor 지‍갑‍을 만‍들‍어 드‍려‍요.';

  @override
  String get paymentLinkEntryExplanationAccount =>
      '카‍드 잔‍액‍을 받‍을 새 계‍정‍을 만‍들‍어‍요.';

  @override
  String get paymentLinkEntryExplanationWallet =>
      '카‍드 잔‍액‍을 받‍을 새 Vizor 지‍갑‍을 만‍들‍어‍요.';

  @override
  String get paymentLinkEntrySubtitle =>
      '받‍은 카‍드 링‍크‍를\n복‍사‍해‍서 아‍래‍에 붙‍여‍넣‍으‍세‍요.';

  @override
  String get paymentLinkEntryTitleAccount => 'Vizor 기‍프‍트 카‍드‍를 받‍아 계‍정 만‍들‍기';

  @override
  String get paymentLinkEntryTitleWallet => 'Vizor 기‍프‍트 카‍드‍를 받‍아 지‍갑 만‍들‍기';

  @override
  String get paymentLinkExportNotReady =>
      '링‍크‍를 내‍보‍내‍려‍면 모‍든 카‍드‍가 준‍비‍되‍어‍야 해‍요.';

  @override
  String get paymentLinkExportStatusChanged =>
      '계‍정 또‍는 카‍드 상‍태‍가 바‍뀌‍었‍어‍요. 카‍드‍를 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkFeeEstimateFailed =>
      '카‍드 수‍수‍료‍를 추‍정‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkFeeEstimatedAfterSync =>
      '지‍갑 동‍기‍화‍가 끝‍나‍면 카‍드 수‍수‍료‍를 추‍정‍해‍요.';

  @override
  String get paymentLinkFeeHelpSemantic => '기‍프‍트 카‍드 수‍수‍료 안‍내';

  @override
  String get paymentLinkFeeHelpTextLong =>
      '기‍프‍트 카‍드‍를 충‍전‍하‍는 수‍수‍료‍와 받‍는 사‍람‍이 카‍드‍를 받‍을 때 쓰‍도‍록 남‍겨 둔 수‍수‍료‍가 포‍함‍돼‍요.';

  @override
  String get paymentLinkFeeUpdateFailed =>
      '카‍드 수‍수‍료‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 금‍액 단‍계‍로 돌‍아‍가 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkFiatLoadingSemantic => '법‍정‍화‍폐 환‍산 금‍액 불‍러‍오‍는 중';

  @override
  String get paymentLinkFlipCardSemanticLabel => '기‍프‍트 카‍드 뒤‍집‍기';

  @override
  String get paymentLinkFundingExpired =>
      '기‍프‍트 카‍드 충‍전‍이 만‍료‍됐‍어‍요. 다‍시 만‍들‍어 주‍세‍요.';

  @override
  String get paymentLinkFundingIncompleteStatus => '충‍전 미‍완‍료';

  @override
  String get paymentLinkFundingNeedsAttention => '기‍프‍트 카‍드 충‍전 확‍인‍이 필‍요‍해‍요';

  @override
  String get paymentLinkFundingSentCardNotSaved =>
      '충‍전‍은 전‍송‍됐‍지‍만 기‍프‍트 카‍드‍를 저‍장‍하‍지 못‍했‍어‍요. Vizor‍를 닫‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkFundingStillVerifying =>
      '충‍전‍을 아‍직 확‍인‍하‍는 중‍이‍에‍요. Vizor‍가 계‍속 확‍인‍해‍요.';

  @override
  String get paymentLinkFundingStorageNeedsSync =>
      '충‍전‍은 전‍송‍됐‍지‍만 로‍컬 거‍래 저‍장‍소‍를 동‍기‍화‍해‍야 해‍요.';

  @override
  String get paymentLinkGiftAmountLabel => '선‍물 금‍액';

  @override
  String paymentLinkGiftCardDesignSemantic(String design) {
    return '기‍프‍트 카‍드, $design 디‍자‍인';
  }

  @override
  String get paymentLinkGiftCardMessageSemantic => '기‍프‍트 카‍드 메‍시‍지';

  @override
  String get paymentLinkGiftCardsLowerBreadcrumb => '기‍프‍트 카‍드';

  @override
  String get paymentLinkGiftCardsTitle => '기‍프‍트 카‍드';

  @override
  String get paymentLinkGiftMessageLabel => '선‍물 메‍시‍지';

  @override
  String get paymentLinkGroupConfirmingPayment => '결‍제 확‍인 중';

  @override
  String get paymentLinkGroupEntryForGroup => '그‍룹‍용';

  @override
  String get paymentLinkGroupEntryGroupSemantic => '그‍룹‍용 카‍드 만‍들‍기';

  @override
  String paymentLinkGroupEntryLedgerSemantic(int max) {
    return '카‍드 여‍러 장 만‍들‍기, Ledger‍로 최‍대 $max‍장';
  }

  @override
  String get paymentLinkGroupEntryMultipleCards => '카‍드 여‍러 장';

  @override
  String paymentLinkGroupEntryUpToWithLedger(int max) {
    return 'Ledger‍로 최‍대 $max‍장';
  }

  @override
  String get paymentLinkGroupNotFunded =>
      '이 그‍룹‍은 충‍전‍되‍지 않‍았‍어‍요. 다‍시 만‍들‍어 주‍세‍요.';

  @override
  String get paymentLinkGroupOtherAccount =>
      '이 그‍룹‍은 다‍른 계‍정‍에 속‍해 있‍어‍요. 보‍려‍면 계‍정‍을 전‍환‍하‍세‍요.';

  @override
  String get paymentLinkGroupPaymentPending => '결‍제 상‍태 확‍인 대‍기 중';

  @override
  String get paymentLinkGroupSomeNotReady => '일‍부 카‍드‍가 아‍직 준‍비‍되‍지 않‍았‍어‍요';

  @override
  String get paymentLinkGroupsHeading => '그‍룹';

  @override
  String get paymentLinkHideCard => '카‍드 숨‍기‍기';

  @override
  String get paymentLinkHowDesktopStepCreate =>
      '선‍물‍할 금‍액‍을 입‍력‍하‍고, 디‍자‍인‍을 고‍르‍고, 메‍시‍지(선‍택)를 추‍가‍한 뒤 클‍릭 한 번‍으‍로 카‍드‍를 만‍드‍세‍요.';

  @override
  String get paymentLinkHowDesktopStepRedeem =>
      '받‍는 사‍람‍은 링‍크‍로 Vizor 지‍갑‍에‍서 카‍드‍를 받‍을 수 있‍어‍요. 입‍금 수‍수‍료‍와 받‍기 수‍수‍료‍는 보‍내‍는 사‍람‍이 부‍담‍하‍므‍로 받‍는 사‍람‍은 카‍드 금‍액 전‍액‍을 받‍아‍요.';

  @override
  String get paymentLinkHowDesktopStepShare =>
      '카‍드‍를 만‍들‍면 카‍드‍를 받‍는 데 필‍요‍한 비‍밀 정‍보‍가 담‍긴 고‍유 링‍크‍가 생‍성‍돼‍요. 이 링‍크‍는 받‍을 사‍람‍에‍게‍만 보‍내‍세‍요.';

  @override
  String get paymentLinkHowGiftCardsWork => '기‍프‍트 카‍드 사‍용 방‍법';

  @override
  String get paymentLinkHowItWorksSubtitle =>
      '어‍떤 순‍간‍이‍든 축‍하‍할 수 있‍는 좋‍은 방‍법‍이‍에‍요.';

  @override
  String get paymentLinkHowItWorksTitle => '기‍프‍트 카‍드 사‍용 방‍법';

  @override
  String get paymentLinkHowStepCreate =>
      '금‍액‍을 입‍력‍하‍고, 디‍자‍인‍을 고‍르‍고, 원‍하‍면 메‍시‍지‍를 추‍가‍하‍세‍요.';

  @override
  String get paymentLinkHowStepRedeem =>
      '받‍는 사‍람‍이 Vizor‍에‍서 링‍크‍를 열‍어 카‍드 금‍액 전‍액‍을 받‍아‍요. 수‍수‍료‍는 보‍내‍는 사‍람‍이 모‍두 부‍담‍해‍요.';

  @override
  String get paymentLinkHowStepShare =>
      '충‍전‍이 네‍트‍워‍크‍에 반‍영‍되‍면 고‍유 링‍크‍를 복‍사‍해 받‍을 사‍람‍에‍게‍만 보‍내‍세‍요.';

  @override
  String get paymentLinkHowTheCardWorks => '기‍프‍트 카‍드 사‍용 방‍법';

  @override
  String get paymentLinkIntakeCouldNotOpen => '결‍제 링‍크‍를 열 수 없‍어‍요.';

  @override
  String get paymentLinkIntakeQueueFull => '열‍기‍를 기‍다‍리‍는 결‍제 링‍크‍가 너‍무 많‍아‍요.';

  @override
  String get paymentLinkInterruptedCheckMessage =>
      '카‍드 확‍인‍이 중‍단‍됐‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkInvalidSubtitle => '링‍크‍를 다‍시 복‍사‍해‍서 시‍도‍해 주‍세‍요';

  @override
  String get paymentLinkInvalidTitle => '올‍바‍른 링‍크‍가 아‍닌 것 같‍아‍요.';

  @override
  String get paymentLinkKeystoneBroadcastFailed =>
      '기‍프‍트 카‍드 충‍전‍을 전‍송‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkKeystoneBroadcastingTitle => '기‍프‍트 카‍드 충‍전 전‍송 중';

  @override
  String get paymentLinkKeystoneCreatingGiftCard => '기‍프‍트 카‍드‍를 만‍드‍는 중…';

  @override
  String get paymentLinkKeystoneFundingUncertain =>
      '충‍전 상‍태‍가 불‍확‍실‍해‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkKeystoneScanCaption =>
      'Keystone‍의 QR 코‍드‍를 스‍캔‍해‍서 만‍들‍기‍를 마‍무‍리‍하‍세‍요';

  @override
  String get paymentLinkKeystoneSignTitle => 'Keystone‍에‍서 기‍프‍트 카‍드 서‍명';

  @override
  String get paymentLinkKeystoneSigningFailed =>
      '기‍프‍트 카‍드 서‍명‍을 완‍료‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkLeaveSaveMany =>
      '이 화‍면‍을 나‍가‍기 전‍에 이 기‍프‍트 카‍드‍들‍을 저‍장‍하‍세‍요.';

  @override
  String get paymentLinkLeaveSaveOne =>
      '이 화‍면‍을 나‍가‍기 전‍에 이 기‍프‍트 카‍드‍를 저‍장‍하‍세‍요.';

  @override
  String get paymentLinkLedgerFundingExpired =>
      '이 기‍프‍트 카‍드 거‍래‍가 만‍료‍되‍었‍거‍나 거‍부‍됐‍어‍요. 돌‍아‍가‍서 새 기‍프‍트 카‍드‍를 만‍들‍어 주‍세‍요.';

  @override
  String get paymentLinkLedgerFundingRejected =>
      'Ledger‍에‍서 기‍프‍트 카‍드 충‍전‍을 거‍부‍했‍어‍요.';

  @override
  String get paymentLinkLedgerSavedForRecovery =>
      '기‍프‍트 카‍드 충‍전‍이 복‍구‍용‍으‍로 저‍장‍됐‍어‍요. 다‍시 시‍도‍해‍서 상‍태‍를 확‍인‍하‍고 저‍장‍을 마‍무‍리‍해 주‍세‍요.';

  @override
  String get paymentLinkLinkCopied => '기‍프‍트 링‍크‍를 복‍사‍했‍어‍요';

  @override
  String get paymentLinkLinkCopiedStatusFailed =>
      '기‍프‍트 링‍크‍를 복‍사‍했‍지‍만 상‍태‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkLinkCopyFailed => '기‍프‍트 링‍크‍를 복‍사‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkLinksSaveFailed =>
      '기‍프‍트 카‍드 링‍크‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkLinksSaved => '기‍프‍트 카‍드 링‍크‍를 저‍장‍했‍어‍요';

  @override
  String get paymentLinkLoadingGiftCard => '기‍프‍트 카‍드 불‍러‍오‍는 중';

  @override
  String get paymentLinkLongSyncBody =>
      'Vizor‍가 잔‍액‍을 확‍인‍하‍려‍면 평‍소‍보‍다 더 많‍은 내‍역‍을 스‍캔‍해‍야 해‍요. 안‍전‍하‍지‍만 오‍래 걸‍릴 수 있‍어‍요.';

  @override
  String get paymentLinkLongSyncConfirm => '기‍프‍트 카‍드 확‍인';

  @override
  String get paymentLinkLongSyncSupporting =>
      '스‍캔‍을 시‍작‍하‍지 않‍고 돌‍아‍갈 수 있‍어‍요.';

  @override
  String get paymentLinkLongSyncTitle => '이 기‍프‍트 카‍드‍는 시‍간‍이 걸‍릴 수 있‍어‍요';

  @override
  String get paymentLinkMemoOptionalSubtitle =>
      '짧‍은 암‍호‍화 메‍모‍를 첨‍부‍할 수 있‍어‍요 (선‍택).';

  @override
  String get paymentLinkMessageAttachedTitle => '메‍시‍지‍를 첨‍부‍했‍어‍요.';

  @override
  String get paymentLinkMessageInputSemantic => '기‍프‍트 카‍드 메‍시‍지 입‍력';

  @override
  String get paymentLinkMessageStepTitle => '메‍시‍지 입‍력';

  @override
  String get paymentLinkMessageTooLarge =>
      '메‍시‍지‍가 너‍무 커‍요. 복‍잡‍한 이‍모‍지‍를 줄‍여 보‍세‍요.';

  @override
  String get paymentLinkMyCards => '내 카‍드';

  @override
  String get paymentLinkNewGiftCardRequired => '새 기‍프‍트 카‍드‍가 필‍요‍해‍요';

  @override
  String get paymentLinkNoActiveAccountAvailable => '선‍택‍된 계‍정‍이 없‍어‍요.';

  @override
  String get paymentLinkNoCreatedCardsText => '아‍직 만‍든 카‍드‍가 없‍어‍요.';

  @override
  String get paymentLinkNoReceivedCardsText => '아‍직 받‍은 카‍드‍가 없‍어‍요.';

  @override
  String get paymentLinkOpenGroupChecking => '확‍인 중';

  @override
  String paymentLinkOpenGroupCreated(String date) {
    return '$date‍에 만‍듦';
  }

  @override
  String paymentLinkOpenGroupEach(String amount) {
    return '장‍당 $amount';
  }

  @override
  String paymentLinkOpenGroupSemantic(int count) {
    return '기‍프‍트 카‍드 $count‍장 그‍룹 열‍기';
  }

  @override
  String get paymentLinkPasteLabel => '카‍드 링‍크 붙‍여‍넣‍기';

  @override
  String get paymentLinkPrivacyModeOff => '프‍라‍이‍버‍시 모‍드 끄‍기';

  @override
  String get paymentLinkPrivacyModeOn => '프‍라‍이‍버‍시 모‍드 켜‍기';

  @override
  String get paymentLinkQrCardHeading => 'ZEC‍를\n받‍았‍어‍요';

  @override
  String get paymentLinkQrCardScanToRedeem => '스‍캔‍해‍서 받‍기';

  @override
  String get paymentLinkQrCardSemantic => '기‍프‍트 카‍드 QR 코‍드';

  @override
  String get paymentLinkQrCouldNotBeGenerated => 'QR 코‍드‍를 만‍들‍지 못‍했‍어‍요';

  @override
  String get paymentLinkQrSaveFailed => '기‍프‍트 카‍드 QR‍을 저‍장‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkQrSaved => '기‍프‍트 카‍드 QR‍을 저‍장‍했‍어‍요';

  @override
  String get paymentLinkQrSavedStatusFailed =>
      '기‍프‍트 카‍드 QR‍을 저‍장‍했‍지‍만 상‍태‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkReadyHeading => '공‍유‍할 준‍비‍가 됐‍어‍요';

  @override
  String get paymentLinkReceiveFinishFailed =>
      '이 선‍물 받‍기‍를 마‍무‍리‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해‍서 상‍태‍를 확‍인‍해 주‍세‍요.';

  @override
  String get paymentLinkReceiveToLabel => '받‍을 계‍정';

  @override
  String get paymentLinkReceivedCardsLoadFailed =>
      '받‍은 기‍프‍트 카‍드‍를 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkReceivedGiftHeading => '선‍물‍을 받‍았‍어‍요!';

  @override
  String get paymentLinkReceivedHeadingDesktop => '기‍프‍트 카‍드‍를\n받‍았‍어‍요!';

  @override
  String get paymentLinkReceivingAccountChangedReopen =>
      '받‍는 계‍정‍이 바‍뀌‍었‍어‍요. 계‍속‍하‍려‍면 기‍프‍트 카‍드‍를 다‍시 열‍어 주‍세‍요.';

  @override
  String get paymentLinkReceivingAccountChangedRetry =>
      '받‍는 계‍정‍이 바‍뀌‍었‍어‍요. 이 선‍물‍을 확‍인‍하‍려‍면 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkReceivingStatus => '받‍는 중…';

  @override
  String get paymentLinkRedeemCardLabel => '카‍드 받‍기';

  @override
  String get paymentLinkRedeemCardStepTitle => '카‍드 받‍기';

  @override
  String get paymentLinkRedeemPasteOrScan =>
      '카‍드 링‍크‍를 붙‍여‍넣‍거‍나 QR 코‍드‍를 스‍캔‍하‍세‍요.';

  @override
  String get paymentLinkRedeemSubtitle =>
      '받‍은 카‍드 링‍크‍를 복‍사‍해‍서 아‍래‍에 붙‍여‍넣‍으‍세‍요.';

  @override
  String get paymentLinkRedeemTheCardTitle => '카‍드 받‍기';

  @override
  String paymentLinkRemovalWarningCheckFailed(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'reset': 'Vizor‍를 초‍기‍화‍하‍기',
      'other': '이 계‍정‍을 삭‍제‍하‍기',
    });
    return '공‍유‍하‍지 않‍은 기‍프‍트 카‍드 링‍크‍가 있‍는‍지 확‍인‍하‍지 못‍했‍어‍요. $_temp0 전‍에 필‍요‍한 링‍크‍를 복‍사‍해 두‍세‍요.';
  }

  @override
  String paymentLinkRemovalWarningUnshared(int count, String subject) {
    String _temp0 = intl.Intl.selectLogic(subject, {
      'reset': 'Vizor‍를 초‍기‍화‍하‍면',
      'other': '이 계‍정‍을 삭‍제‍하‍면',
    });
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '공‍유‍하‍지 않‍은 충‍전‍된 기‍프‍트 카‍드 링‍크‍가 $count‍개 있‍어‍요. $_temp0 링‍크‍를 잃‍게 돼‍요. 먼‍저 링‍크‍를 복‍사‍해 두‍세‍요.',
    );
    return '$_temp1';
  }

  @override
  String get paymentLinkRemoveCardLabel => '카‍드 삭‍제';

  @override
  String get paymentLinkRemoveCardSupporting => '이 작‍업‍은 되‍돌‍릴 수 없‍어‍요.';

  @override
  String get paymentLinkRemoveCardTitle => '이 카‍드‍를 삭‍제‍할‍까‍요?';

  @override
  String get paymentLinkRestoreCard => '카‍드 복‍원';

  @override
  String get paymentLinkRevealMessageSemanticLabel => '기‍프‍트 카‍드 메‍시‍지 보‍기';

  @override
  String get paymentLinkReviewAndConfirm => '검‍토‍하‍고 확‍인';

  @override
  String get paymentLinkReviewCardTitle => '카‍드 검‍토';

  @override
  String get paymentLinkSaveQrCode => 'QR 코‍드 저‍장';

  @override
  String get paymentLinkSaving => '저‍장 중…';

  @override
  String get paymentLinkScanAgainOrPaste =>
      '다‍시 스‍캔‍하‍거‍나 다‍른 카‍드 링‍크‍를 붙‍여‍넣‍으‍세‍요.';

  @override
  String get paymentLinkScanCameraHint =>
      '카‍메‍라‍를 연‍결‍해 기‍프‍트 카‍드 QR 코‍드‍를 스‍캔‍하‍거‍나, 돌‍아‍가‍서 카‍드 링‍크‍를 붙‍여‍넣‍으‍세‍요.';

  @override
  String get paymentLinkScanNotGiftCard => '기‍프‍트 카‍드 QR 코‍드‍가 아‍니‍에‍요.';

  @override
  String get paymentLinkScanOtherNetwork => '다‍른 네‍트‍워‍크‍용 기‍프‍트 카‍드‍예‍요.';

  @override
  String get paymentLinkScanSheetSemantic => '기‍프‍트 카‍드 QR 코‍드 스‍캔';

  @override
  String get paymentLinkScanSheetTitle => '기‍프‍트 카‍드 QR 스‍캔';

  @override
  String get paymentLinkScanShowQrToCamera =>
      '기‍프‍트 카‍드 QR 코‍드‍를 카‍메‍라‍에 보‍여 주‍세‍요';

  @override
  String paymentLinkSenderMessageSemantic(String message) {
    return '보‍낸 사‍람‍의 메‍시‍지: $message; 기‍프‍트 카‍드 앞‍면 보‍기';
  }

  @override
  String get paymentLinkShareCard => '카‍드 공‍유';

  @override
  String get paymentLinkShareFailed => '기‍프‍트 링‍크‍를 공‍유‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkShareFailedCopyInstead =>
      '이 기‍프‍트 카‍드‍를 공‍유‍하‍지 못‍했‍어‍요. 대‍신 링‍크‍를 복‍사‍해 주‍세‍요.';

  @override
  String get paymentLinkShareGiftCardTitle => '기‍프‍트 카‍드 공‍유';

  @override
  String get paymentLinkShareLinkInstruction =>
      '이 링‍크‍를 받‍을 사‍람‍에‍게‍만 공‍유‍하‍세‍요. Vizor 앱‍에‍서 카‍드‍를 받‍을 수 있‍어‍요.';

  @override
  String get paymentLinkShareLinkInstructionDesktop =>
      '이 링‍크‍를 받‍을 사‍람‍에‍게‍만 공‍유‍하‍세‍요.\nVizor 앱‍에‍서 카‍드‍를 받‍을 수 있‍어‍요.';

  @override
  String get paymentLinkShareSheetTitle => '기‍프‍트 카‍드 공‍유';

  @override
  String get paymentLinkShareWaitingDescription =>
      '기‍프‍트 카‍드‍를 공‍유‍할 수 있‍게 준‍비‍하‍고 있‍어‍요.';

  @override
  String get paymentLinkSharedStatusFailed =>
      '기‍프‍트 카‍드‍를 공‍유‍했‍지‍만 상‍태‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkSharing => '공‍유 중…';

  @override
  String get paymentLinkShowCardFrontSemantic => '기‍프‍트 카‍드 앞‍면 보‍기';

  @override
  String get paymentLinkShowHowCardsWork => '기‍프‍트 카‍드 사‍용 방‍법 보‍기';

  @override
  String get paymentLinkShowQrSemantic => '기‍프‍트 카‍드 QR 코‍드 보‍기';

  @override
  String get paymentLinkSkipMessage => '메‍시‍지 건‍너‍뛰‍기';

  @override
  String get paymentLinkStartTyping => '입‍력‍을 시‍작‍하‍세‍요…';

  @override
  String get paymentLinkStartWritingMessage => '기‍프‍트 카‍드 메‍시‍지 쓰‍기 시‍작';

  @override
  String get paymentLinkStepAddMessage => '메‍시‍지 추‍가';

  @override
  String get paymentLinkStepCreate => '만‍들‍기';

  @override
  String get paymentLinkStepReview => '검‍토';

  @override
  String get paymentLinkStillNotSaved =>
      '기‍프‍트 카‍드‍를 여‍전‍히 저‍장‍하‍지 못‍했‍어‍요. Vizor‍를 닫‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentLinkTapToRevealMessage => '카‍드‍를 탭‍하‍면 메‍시‍지‍를 볼 수 있‍어‍요.';

  @override
  String get paymentLinkTapToRevealMessageTwoLines =>
      '카‍드‍를 탭‍하‍면\n메‍시‍지‍를 볼 수 있‍어‍요.';

  @override
  String get paymentLinkTotalAmountHelpSemantic => '기‍프‍트 카‍드 총 금‍액 안‍내';

  @override
  String get paymentLinkTotalDeductedLabel => '총 차‍감 금‍액';

  @override
  String get paymentLinkTrySavingAgain => '다‍시 저‍장';

  @override
  String get paymentLinkUnusedSectionLabel => '사‍용 전';

  @override
  String get paymentLinkUsageAllUsed => '모‍두 사‍용‍됨';

  @override
  String get paymentLinkUsageAmountMismatch =>
      '확‍인‍된 충‍전 금‍액‍이 예‍상‍한 카‍드 충‍전 금‍액‍과 달‍라‍요.';

  @override
  String get paymentLinkUsageAwaitingConfirmation =>
      '링‍크‍를 공‍유‍할 준‍비‍가 됐‍어‍요. 충‍전 거‍래‍가 확‍인‍되‍면 사‍용 추‍적‍이 시‍작‍돼‍요.';

  @override
  String paymentLinkUsageCardUse(String label, String suffix) {
    String _temp0 = intl.Intl.selectLogic(suffix, {
      'checking': ' · 확‍인 중…',
      'failed': ' · 업‍데‍이‍트 실‍패',
      'other': '',
    });
    return '카‍드 사‍용: $label$_temp0';
  }

  @override
  String get paymentLinkUsageFundingNotObserved =>
      '추‍적 기‍록‍에‍서 아‍직 충‍전 거‍래‍를 확‍인‍하‍지 못‍했‍어‍요.';

  @override
  String paymentLinkUsageLastChecked(String time) {
    return '마‍지‍막 확‍인: $time';
  }

  @override
  String get paymentLinkUsageMissingFundingInfo =>
      '저‍장‍된 충‍전 정‍보‍가 불‍완‍전‍해‍서 사‍용 여‍부‍를 확‍인‍하‍지 못‍했‍어‍요.';

  @override
  String get paymentLinkUsageNotEnoughInfo =>
      '이 카‍드‍를 사‍용‍했‍는‍지 확‍인‍할 정‍보‍가 아‍직 충‍분‍하‍지 않‍아‍요.';

  @override
  String get paymentLinkUsageScanIncomplete =>
      '추‍적 기‍록‍이 아‍직 충‍전 거‍래‍까‍지 도‍달‍하‍지 않‍았‍어‍요.';

  @override
  String paymentLinkUsageSemantics(
    String label,
    String state,
    String hasExplanation,
    String explanation,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'checking': '. 확‍인 중',
      'failed': '. 업‍데‍이‍트 실‍패',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(hasExplanation, {
      'true': '. $explanation',
      'other': '',
    });
    return '카‍드 사‍용: $label$_temp0$_temp1';
  }

  @override
  String paymentLinkUsageUnusedOfCount(int unused, int count) {
    return '$count‍장 중 $unused‍장 사‍용 전';
  }

  @override
  String get paymentLinkUsageUnverified => '확‍인 안 됨';

  @override
  String get paymentLinkUsageUseDetected => '사‍용 감‍지‍됨';

  @override
  String paymentLinkUsageUsedOfCount(int used, int count) {
    return '$count‍장 중 $used‍장 사‍용‍됨';
  }

  @override
  String get paymentLinkUsdAmountTooSmall =>
      '금‍액‍이 너‍무 작‍아‍서 USD‍로 입‍력‍할 수 없‍어‍요.';

  @override
  String get paymentLinkUsdFetchingPrice => 'USD 가‍격‍을 가‍져‍오‍는 중…';

  @override
  String get paymentLinkUsdPriceUnavailable => 'USD 가‍격‍을 사‍용‍할 수 없‍어‍요';

  @override
  String paymentLinkUseMaxCurrencySemantic(String amount, String currency) {
    return '최‍대 금‍액 사‍용: $amount $currency';
  }

  @override
  String paymentLinkUseMaxSemantic(String amount) {
    return '최‍대 금‍액 사‍용: $amount';
  }

  @override
  String get paymentLinkUsedSectionLabel => '사‍용‍됨';

  @override
  String get paymentLinkViewCardAction => '카‍드 보‍기';

  @override
  String paymentLinkWaitToClaim(int minutes, String seconds) {
    return '받‍으‍려‍면 $minutes:$seconds 기‍다‍려 주‍세‍요';
  }

  @override
  String get paymentLinkWaitToClaimSample => '받‍으‍려‍면 3:45 기‍다‍려 주‍세‍요';

  @override
  String paymentLinkWaitToGetLink(int minutes, String seconds) {
    return '링‍크‍를 받‍으‍려‍면 $minutes:$seconds 기‍다‍려 주‍세‍요';
  }

  @override
  String get paymentLinkWaitingDescription => '잠‍시 걸‍릴 수 있‍어‍요.';

  @override
  String get paymentLinkWaitingStatusLabel => '링‍크‍를 받‍으‍려‍면 1:15 기‍다‍려 주‍세‍요';

  @override
  String get paymentLinkWalletSaveRecoveryFailed =>
      '지‍갑 저‍장‍을 마‍무‍리‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get paymentUriExpired =>
      '이 요‍청 링‍크‍의 유‍효 시‍간‍이 지‍났‍어‍요. 결‍제‍하‍려‍면 다‍시 열‍어 주‍세‍요.';

  @override
  String get paymentUriMalformed =>
      '이 요‍청 링‍크‍가 올‍바‍르‍지 않‍아‍요. 보‍낸 사‍람‍에‍게 새 링‍크‍를 요‍청‍해 주‍세‍요.';

  @override
  String get paymentUriMigrationSendGate =>
      '요‍청 링‍크‍를 열‍기 전‍에 Ironwood 마‍이‍그‍레‍이‍션‍을 마‍쳐 주‍세‍요.';

  @override
  String get paymentUriNoWallet =>
      '요‍청 링‍크‍를 열‍기 전‍에 지‍갑‍을 설‍정‍하‍거‍나 가‍져‍와 주‍세‍요.';

  @override
  String get paymentUriOnboarding => '요‍청 링‍크‍를 열‍기 전‍에 지‍갑 설‍정‍을 마‍쳐 주‍세‍요.';

  @override
  String get paymentUriReplaced =>
      '가‍장 최‍근 요‍청 링‍크‍만 남‍아 있‍어‍요. 이‍전 요‍청‍을 결‍제‍하‍려‍면 해‍당 링‍크‍를 다‍시 열‍어 주‍세‍요.';

  @override
  String get paymentUriUnavailable =>
      'Vizor‍가 이 요‍청 링‍크‍를 열‍지 못‍했‍어‍요. 지‍갑‍이 로‍드‍된 후 다‍시 열‍어 주‍세‍요.';

  @override
  String get paymentUriUnsupported =>
      '이 요‍청 링‍크‍는 Vizor‍가 아‍직 지‍원‍하‍지 않‍는 기‍능‍을 사‍용‍해‍요.';

  @override
  String get poolShielded => '차‍폐‍됨';

  @override
  String get poolTransparent => '투‍명';

  @override
  String get privateQueriesOptOutUnfinished =>
      '비‍공‍개 조‍회 끄‍기‍가 완‍료‍되‍지 않‍았‍어‍요. 투‍명 자‍금‍을 사‍용‍하‍려‍면 설‍정‍에‍서 다‍시 끄‍세‍요.';

  @override
  String get profilePictureChange => '프‍로‍필 사‍진 변‍경';

  @override
  String profilePictureName(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'p01': '기‍사',
      'p02': '바‍이‍킹',
      'p03': '사‍무‍라‍이',
      'p04': '군‍주',
      'p05': '철‍투‍구',
      'p06': '로‍닌',
      'p07': '해‍골 기‍사',
      'p08': '예‍언‍자',
      'p09': '광‍전‍사',
      'p10': '도‍적',
      'p11': '마‍법‍사',
      'p12': '가‍면 쓴 고‍양‍이',
      'p13': '감‍시‍자',
      'p14': '청‍동 투‍구',
      'p15': '물‍고‍기 기‍사',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get profilePictureSelect => '프‍로‍필 사‍진 선‍택';

  @override
  String get profilePictureUpdateFailed => '프‍로‍필 사‍진‍을 바‍꾸‍지 못‍했‍어‍요.';

  @override
  String get receiveAboutAddressType => '이 주‍소 유‍형 알‍아‍보‍기';

  @override
  String get receiveAddressCouldNotLoad =>
      '주‍소‍를 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get receiveAddressLoadFailed =>
      '주‍소‍를 불‍러‍오‍지 못‍했‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get receiveCopyTransparentAddress => '투‍명 주‍소 복‍사';

  @override
  String get receiveGenerateNewShieldedAddress => '새 차‍폐 주‍소 만‍들‍기';

  @override
  String get receiveInfoShieldedDiversified =>
      '새 주‍소‍는 모‍두 같‍은 키‍에‍서 파‍생‍된 다‍변‍화 주‍소‍예‍요. 모‍두 같‍은 지‍갑‍으‍로 받‍아‍요.';

  @override
  String get receiveInfoShieldedHiddenDesktop =>
      '거‍래 세‍부 정‍보(보‍낸 사‍람, 받‍는 사‍람, 금‍액)는 온‍체‍인‍에‍서 암‍호‍화‍되‍어 숨‍겨‍져‍요.';

  @override
  String get receiveInfoShieldedHiddenMobile =>
      '거‍래 세‍부 정‍보(보‍낸 사‍람, 받‍는 사‍람, 금‍액)는 온‍체‍인‍에‍서 암‍호‍화‍되‍어 숨‍겨‍져‍요.';

  @override
  String get receiveInfoShieldedRenewClick =>
      '새 Zcash 차‍폐 주‍소‍는 갱‍신 버‍튼‍을 클‍릭‍할 때‍만 만‍들‍어‍져‍요.';

  @override
  String get receiveInfoShieldedRenewTap =>
      '새 Zcash 차‍폐 주‍소‍는 갱‍신 버‍튼‍을 탭‍할 때‍만 만‍들‍어‍져‍요.';

  @override
  String get receiveInfoShieldedSubtitle =>
      '기‍본‍적‍으‍로 강‍력‍한 프‍라‍이‍버‍시‍를 제‍공‍해‍요.';

  @override
  String get receiveInfoTransparentExchanges =>
      '투‍명‍성‍이‍나 규‍제‍상 명‍확‍성‍이 필‍요‍한 거‍래‍소‍에‍서 흔‍히 사‍용‍해‍요. 여‍러 지‍갑‍과‍의 호‍환‍성‍을 위‍한 기‍본‍값‍이‍기‍도 해‍요.';

  @override
  String get receiveInfoTransparentPublicDesktop =>
      '모‍든 거‍래 세‍부 정‍보(보‍낸 사‍람, 받‍는 사‍람, 금‍액)가 온‍체‍인‍에 공‍개‍돼‍요.';

  @override
  String get receiveInfoTransparentPublicMobile =>
      '모‍든 거‍래 세‍부 정‍보(보‍낸 사‍람, 받‍는 사‍람, 금‍액)가 온‍체‍인‍에 공‍개‍돼‍요.';

  @override
  String get receiveInfoTransparentRotates =>
      '이 주‍소‍로 ZEC‍를 받‍고 Vizor‍가 동‍기‍화‍하‍면 다‍음 투‍명 주‍소‍로 자‍동‍으‍로 바‍뀌‍어‍요. 이‍전 주‍소‍도 계‍속 이 지‍갑‍에 속‍해‍요.';

  @override
  String receiveInfoTransparentShieldFirst(String ticker) {
    return '투‍명 주‍소‍로 $ticker‍를 받‍은 뒤‍에‍는 Vizor‍가 잔‍액‍을 차‍폐‍하‍도‍록 안‍내‍해‍요. 차‍폐‍하‍지 않‍으‍면 보‍낼 수 없‍어‍요.';
  }

  @override
  String get receiveInfoTransparentSubtitle => '공‍개‍적‍으‍로 보‍여‍요';

  @override
  String get receiveQrSaveFailed =>
      'QR 이‍미‍지‍를 저‍장‍하‍지 못‍했‍어‍요. 다‍른 폴‍더‍를 선‍택‍하‍거‍나 요‍청 링‍크‍를 대‍신 복‍사‍해 주‍세‍요.';

  @override
  String receiveQrSaved(String folder) {
    return 'QR 이‍미‍지‍를 $folder‍에 저‍장‍했‍어‍요';
  }

  @override
  String get receiveQrUnavailable => 'QR‍을 표‍시‍할 수 없‍어‍요';

  @override
  String get receiveRenewAddressError =>
      '차‍폐 주‍소‍를 새‍로 만‍들‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 현‍재 주‍소‍를 계‍속 사‍용‍해 주‍세‍요.';

  @override
  String get receiveRequestAmountDecimalsError =>
      '소‍수‍점‍은 8‍자‍리‍까‍지 입‍력‍해 주‍세‍요';

  @override
  String get receiveRequestAmountFormatError => '0.5‍처‍럼 금‍액‍을 입‍력‍해 주‍세‍요';

  @override
  String get receiveRequestAmountSupplyError => '금‍액‍이 ZEC 총 공‍급‍량‍을 넘‍어‍요';

  @override
  String receiveRequestButton(String ticker) {
    return '$ticker 요‍청‍하‍기';
  }

  @override
  String get receiveRequestCloseRequest => '요‍청 닫‍기';

  @override
  String get receiveRequestCopyFailed =>
      '요‍청 링‍크‍를 복‍사‍하‍지 못‍했‍어‍요. 대‍신 공‍유‍해 보‍세‍요.';

  @override
  String get receiveRequestCopyRequestLink => '요‍청 링‍크 복‍사';

  @override
  String get receiveRequestCreate => '요‍청 만‍들‍기';

  @override
  String get receiveRequestEnterZec => 'ZEC‍로 금‍액 입‍력';

  @override
  String get receiveRequestLinkCopied => '요‍청 링‍크‍를 복‍사‍했‍어‍요';

  @override
  String get receiveRequestMessageHelp =>
      '차‍폐 주‍소‍에‍서‍만 쓸 수 있‍어‍요. 이 링‍크‍를 가‍진 사‍람‍은 누‍구‍나 읽‍을 수 있‍어‍요.';

  @override
  String get receiveRequestMessageHint =>
      '링‍크‍를 받‍은 사‍람‍은 누‍구‍나 이 내‍용‍을 읽‍을 수 있‍어‍요';

  @override
  String get receiveRequestSaveQr => 'QR 이‍미‍지 저‍장';

  @override
  String get receiveRequestShare => '요‍청 공‍유';

  @override
  String get receiveRequestShareFailed =>
      '이 요‍청‍을 공‍유‍하‍지 못‍했‍어‍요. 대‍신 링‍크‍를 복‍사‍해 주‍세‍요.';

  @override
  String get receiveRequestZecButton => 'ZEC 요‍청‍하‍기';

  @override
  String get receiveShareAddress => '주‍소 공‍유';

  @override
  String get receiveShareFailed => '이 주‍소‍를 공‍유‍하‍지 못‍했‍어‍요. 대‍신 복‍사‍해 주‍세‍요.';

  @override
  String get receiveShareShieldedAddress => '차‍폐 주‍소 공‍유';

  @override
  String get receiveShareTransparentAddress => '투‍명 주‍소 공‍유';

  @override
  String get receiveShieldedAddressLoadFailed =>
      '차‍폐 주‍소‍를 불‍러‍오‍지 못‍했‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String receiveTitle(String ticker) {
    return '$ticker 받‍기';
  }

  @override
  String get receiveTransparentAddressLoadFailed =>
      '투‍명 주‍소‍를 불‍러‍오‍지 못‍했‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get secretPassphraseCopy => '복‍구 문‍구 복‍사';

  @override
  String get secretPassphraseTitle => '복‍구 문‍구';

  @override
  String get sendAddMemo => '메‍모 추‍가';

  @override
  String get sendAddressTypeTex => 'TEX 주‍소';

  @override
  String get sendAddressValidationFailed => '주‍소‍를 확‍인‍하‍지 못‍했‍어‍요';

  @override
  String get sendAmountCtaEnterAmount => '계‍속‍하‍려‍면 금‍액‍을 입‍력‍하‍세‍요';

  @override
  String get sendBroadcastCancelledBeforeParams =>
      '증‍명 매‍개‍변‍수‍를 내‍려‍받‍기 전‍에 보‍내‍기‍가 취‍소‍됐‍어‍요.';

  @override
  String get sendBroadcastDependentIncomplete =>
      '첫 번‍째 거‍래‍는 수‍락‍됐‍지‍만 이‍어‍지‍는 거‍래‍가 완‍료‍되‍지 않‍았‍어‍요. 다‍시 보‍내‍기 전‍에 활‍동‍을 확‍인‍하‍세‍요.';

  @override
  String get sendBroadcastFirstUnknown =>
      '첫 번‍째 거‍래‍는 로‍컬‍에 저‍장‍됐‍고 네‍트‍워‍크‍에 도‍달‍했‍을 수 있‍지‍만 확‍인 시‍간‍이 초‍과‍됐‍어‍요. 다‍시 보‍내‍기 전‍에 활‍동‍을 확‍인‍하‍세‍요.';

  @override
  String get sendBroadcastHardwareExpired =>
      '하‍드‍웨‍어 서‍명 요‍청‍이 전‍송‍되‍기 전‍에 만‍료‍됐‍어‍요. 지‍갑‍으‍로 돌‍아‍가 동‍기‍화‍가 끝‍나‍길 기‍다‍린 다‍음 결‍제‍를 다‍시 검‍토‍하‍고 시‍도‍하‍세‍요.';

  @override
  String get sendBroadcastIncomplete =>
      '거‍래 전‍송‍이 완‍료‍되‍지 않‍았‍어‍요. 다‍시 보‍내‍기 전‍에 활‍동‍을 확‍인‍하‍세‍요.';

  @override
  String get sendBroadcastLedgerFirstUnknown =>
      '첫 번‍째 거‍래‍가 네‍트‍워‍크‍에 도‍달‍했‍을 수 있‍지‍만 확‍인 시‍간‍이 초‍과‍됐‍어‍요. 다‍시 보‍내‍기 전‍에 활‍동‍을 확‍인‍하‍세‍요.';

  @override
  String get sendBroadcastLedgerNotStored =>
      '거‍래‍가 네‍트‍워‍크‍에 도‍달‍했‍지‍만 Vizor‍가 로‍컬‍에 저‍장‍하‍지 못‍했‍어‍요. 동‍기‍화‍나 블‍록 탐‍색‍기‍에‍서 최‍신 상‍태‍를 확‍인‍하‍기 전‍에‍는 다‍시 보‍내‍지 마‍세‍요.';

  @override
  String get sendBroadcastLedgerRejected =>
      '네‍트‍워‍크‍가 거‍래‍를 거‍부‍했‍어‍요. 나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendBroadcastLocalRetry =>
      '거‍래‍가 로‍컬‍에‍서 만‍들‍어‍졌‍지‍만 전‍송‍하‍지 못‍했‍어‍요. 네‍트‍워‍크‍가 연‍결‍되‍면 자‍동‍으‍로 다‍시 시‍도‍해‍요. 이 거‍래‍가 만‍료‍되‍기 전‍에‍는 다‍시 보‍내‍지 마‍세‍요.';

  @override
  String get sendBroadcastMnemonicMissing => '이 계‍정‍의 복‍구 문‍구‍를 찾‍을 수 없‍어‍요.';

  @override
  String get sendBroadcastPartial =>
      '일‍부 거‍래‍는 전‍송‍됐‍고 나‍머‍지‍는 자‍동‍으‍로 다‍시 시‍도‍해‍요. 다‍시 보‍내‍기 전‍에 활‍동‍을 확‍인‍하‍세‍요.';

  @override
  String get sendBroadcastProofParamsRequired =>
      '이 서‍명‍된 거‍래‍를 다‍시 시‍도‍하‍려‍면 증‍명 매‍개‍변‍수‍가 필‍요‍해‍요.';

  @override
  String get sendBroadcastRejectedLocal =>
      '거‍래‍가 로‍컬‍에‍서 만‍들‍어‍졌‍지‍만 네‍트‍워‍크‍에 도‍달‍하‍지 않‍았‍어‍요. 거‍래‍가 만‍료‍될 때‍까‍지 지‍갑‍이 계‍속 다‍시 시‍도‍해‍요. 이 거‍래‍가 만‍료‍되‍기 전‍에‍는 다‍시 보‍내‍지 마‍세‍요.';

  @override
  String get sendBroadcastTrackingFailed =>
      '거‍래‍가 네‍트‍워‍크‍에 도‍달‍했‍지‍만 로‍컬 추‍적‍에 실‍패‍했‍어‍요. 다‍시 보‍내‍기 전‍에 활‍동‍이‍나 블‍록 탐‍색‍기‍를 확‍인‍하‍세‍요.';

  @override
  String get sendCalculatingMax => '최‍대 금‍액‍을 계‍산‍하‍고 있‍어‍요';

  @override
  String get sendContactPickerEmpty => 'Zcash 연‍락‍처‍가 없‍어‍요';

  @override
  String get sendContactPickerTitle => 'Zcash 연‍락‍처';

  @override
  String get sendDonationAddressTitle => 'Vizor 후‍원 주‍소';

  @override
  String get sendEnterAddressToContinue => '계‍속‍하‍려‍면 주‍소‍를 입‍력‍하‍세‍요';

  @override
  String get sendEnterValidAddress => '올‍바‍른 주‍소‍를 입‍력‍하‍세‍요';

  @override
  String get sendErrorCouldNotBeSent =>
      '거‍래‍를 보‍내‍지 못‍했‍어‍요. 지‍갑‍으‍로 돌‍아‍가 최‍신 상‍태‍를 확‍인‍하‍세‍요.';

  @override
  String get sendErrorDonationFailed => '후‍원‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendErrorExpiredBeforeSent => '거‍래‍가 전‍송‍되‍기 전‍에 만‍료‍됐‍어‍요.';

  @override
  String get sendErrorExpiredTryAgain =>
      '거‍래‍가 전‍송‍되‍기 전‍에 만‍료‍됐‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendErrorInsufficientShielded =>
      '금‍액‍과 수‍수‍료‍를 낼 차‍폐 잔‍액‍이 부‍족‍해‍요.';

  @override
  String get sendErrorNetwork =>
      '네‍트‍워‍크 오‍류‍예‍요. 연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendErrorPartiallySent =>
      '거‍래‍의 일‍부‍가 이‍미 전‍송‍됐‍어‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍에‍서 전‍송‍된 내‍역‍을 확‍인‍하‍세‍요.';

  @override
  String get sendErrorRejectedTryAgain =>
      '네‍트‍워‍크‍가 이 거‍래‍를 거‍부‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendErrorRejectedTryLater =>
      '네‍트‍워‍크‍가 이 거‍래‍를 거‍부‍했‍어‍요. 나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendErrorSendFailed => '보‍내‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendErrorSyncFinishing =>
      '지‍갑 동‍기‍화‍를 마‍무‍리‍하‍는 중‍이‍에‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendFeeAboutSemantics => '거‍래 수‍수‍료 안‍내';

  @override
  String get sendFeeUnavailableTryAgain =>
      '수‍수‍료‍를 확‍인‍할 수 없‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendFeeUpdatedAfterSync =>
      '동‍기‍화 후 수‍수‍료‍가 바‍뀌‍었‍어‍요. 다‍시 검‍토‍하‍고 확‍인‍하‍세‍요.';

  @override
  String get sendFinishingSync => '지‍갑 동‍기‍화‍를 마‍무‍리‍하‍는 중‍이‍에‍요.';

  @override
  String get sendInsufficientBalanceIncludingFeeShielded =>
      '수‍수‍료‍를 포‍함‍하‍면 차‍폐 잔‍액‍이 부‍족‍해‍요';

  @override
  String get sendInsufficientBalanceIncludingFeeTex =>
      '수‍수‍료‍를 포‍함‍하‍면 잔‍액‍이 부‍족‍해‍요';

  @override
  String get sendInsufficientBalanceSentenceShielded => '차‍폐 잔‍액‍이 부‍족‍해‍요.';

  @override
  String get sendInsufficientBalanceSentenceTex => '잔‍액‍이 부‍족‍해‍요.';

  @override
  String get sendInsufficientBalanceShielded => '차‍폐 잔‍액‍이 부‍족‍해‍요';

  @override
  String get sendInsufficientBalanceTex => '잔‍액‍이 부‍족‍해‍요';

  @override
  String get sendInsufficientBalanceToCoverFeeShielded =>
      '수‍수‍료‍를 낼 차‍폐 잔‍액‍이 부‍족‍해‍요';

  @override
  String get sendInsufficientBalanceToCoverFeeTex => '수‍수‍료‍를 낼 잔‍액‍이 부‍족‍해‍요';

  @override
  String sendInsufficientBalanceWithFeeShielded(String fee) {
    return '차‍폐 잔‍액‍이 부‍족‍해‍요 (수‍수‍료: $fee)';
  }

  @override
  String sendInsufficientBalanceWithFeeTex(String fee) {
    return '잔‍액‍이 부‍족‍해‍요 (수‍수‍료: $fee)';
  }

  @override
  String get sendInvalidAddress => '올‍바‍르‍지 않‍은 주‍소‍예‍요';

  @override
  String get sendInvalidAmount => '올‍바‍르‍지 않‍은 금‍액‍이‍에‍요';

  @override
  String get sendKeystonePrepareFailedGoBack =>
      'Keystone 서‍명‍을 준‍비‍하‍지 못‍했‍어‍요. 뒤‍로 가‍서 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendKeystonePrepareFailedReturnToSend =>
      'Keystone 서‍명‍을 준‍비‍하‍지 못‍했‍어‍요. 보‍내‍기‍로 돌‍아‍가 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendKeystoneQrMismatch =>
      '이 QR 코‍드‍는 현‍재 Keystone 서‍명 요‍청‍과 일‍치‍하‍지 않‍아‍요.';

  @override
  String get sendKeystoneScanCameraOnly =>
      'Keystone 서‍명‍은 카‍메‍라 QR 스‍캔‍만 지‍원‍해‍요. 카‍메‍라‍를 연‍결‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendKeystoneScanDecodeFailed =>
      '이 QR 코‍드‍를 Keystone 거‍래 서‍명‍으‍로 해‍석‍할 수 없‍어‍요.';

  @override
  String get sendKeystoneScanHoldSteady => 'QR 코‍드‍를 카‍메‍라 앞‍에 고‍정‍해 주‍세‍요';

  @override
  String get sendKeystoneScanNow =>
      '지‍금 스‍캔‍하‍세‍요. 증‍명‍이 준‍비‍되‍면 서‍명 가‍져‍오‍기‍가 활‍성‍화‍돼‍요.';

  @override
  String get sendKeystoneScanToFinish =>
      '보‍내‍기‍를 마‍치‍려‍면 Keystone‍의 QR 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String sendKeystoneTexTwoApprovals(int index) {
    return '이 TEX 보‍내‍기‍는 Keystone‍에‍서 두 번 승‍인‍해‍야 해‍요. 2‍개 중 $index‍번‍째 거‍래‍를 스‍캔‍하‍세‍요.';
  }

  @override
  String sendKeystoneTransactionOfTwo(int index) {
    return '거‍래 $index/2';
  }

  @override
  String sendLedgerConnectAndUnlock(String instruction) {
    return 'Ledger‍를 연‍결‍하‍고 잠‍금‍을 해‍제‍하‍세‍요. $instruction';
  }

  @override
  String get sendLedgerCouldNotFinishTitle => '거‍래‍를 완‍료‍하‍지 못‍했‍어‍요';

  @override
  String get sendLedgerCouldNotPrepare =>
      'Vizor‍가 거‍래‍를 준‍비‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendLedgerCouldNotSaveTitle => '서‍명‍한 거‍래‍를 저‍장‍하‍지 못‍했‍어‍요';

  @override
  String get sendLedgerCouldNotVerifySaved =>
      'Vizor‍가 저‍장‍된 거‍래‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 서‍명‍하‍거‍나 보‍내‍지 마‍세‍요.';

  @override
  String get sendLedgerCreateNewTransaction => '새 거‍래 만‍들‍기';

  @override
  String get sendLedgerExpiredMessage =>
      '이 거‍래‍는 더 이‍상 서‍명‍할 수 없‍어‍요. 새 거‍래‍를 만‍들‍어 검‍토‍하‍세‍요.';

  @override
  String get sendLedgerKeepOpenRetry =>
      'Vizor‍를 열‍어 둔 채‍로 다‍시 시‍도‍해 주‍세‍요. Ledger‍에‍서 다‍시 승‍인‍하‍지 않‍아‍도 돼‍요.';

  @override
  String get sendLedgerKeepOpenRetrySaving =>
      'Vizor‍를 열‍어 둔 채‍로 저‍장‍을 다‍시 시‍도‍해 주‍세‍요. Ledger‍에‍서 다‍시 승‍인‍하‍지 않‍아‍도 돼‍요.';

  @override
  String get sendLedgerRejectedOnDevice => 'Ledger‍에‍서 거‍래‍가 거‍부‍됐‍어‍요.';

  @override
  String get sendLedgerSignaturePreservedMessage =>
      'Ledger 서‍명‍이 보‍존‍돼 있‍어‍요. 다‍른 거‍래‍를 승‍인‍하‍지 말‍고 저‍장‍만 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendLedgerSignedNeedsAttentionTitle => '서‍명‍한 거‍래‍를 확‍인‍해‍야 해‍요';

  @override
  String get sendLedgerSigningUnavailableTitle => 'Ledger‍로 서‍명‍할 수 없‍어‍요';

  @override
  String get sendLedgerStatusNewTransactionRequired => '새 거‍래‍가 필‍요‍해‍요';

  @override
  String get sendLedgerStatusRecoveryRequired => '복‍구‍가 필‍요‍해‍요';

  @override
  String get sendLedgerStatusSignaturePreserved => '서‍명‍이 보‍존‍돼 있‍어‍요';

  @override
  String get sendLedgerStatusUnsupportedTransaction => '지‍원‍하‍지 않‍는 거‍래‍예‍요';

  @override
  String sendLoadError(String error) {
    return '문‍제‍가 생‍겼‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.\n\n자‍세‍한 내‍용: $error';
  }

  @override
  String get sendMaxButton => '최‍대';

  @override
  String get sendMaxNeedsAddress => '최‍대 금‍액‍을 쓰‍려‍면 올‍바‍른 주‍소‍를 입‍력‍하‍세‍요';

  @override
  String get sendMaxUnavailable => '최‍대 금‍액‍을 확‍인‍할 수 없‍어‍요';

  @override
  String get sendMemoAddShortEncrypted => '짧‍은 암‍호‍화 메‍시‍지 추‍가';

  @override
  String get sendMemoClear => '메‍모 지‍우‍기';

  @override
  String get sendMemoCollapse => '접‍기';

  @override
  String get sendMemoEncryptedHint => '암‍호‍화‍되‍며 차‍폐 주‍소‍에‍서‍만 쓸 수 있‍어‍요.';

  @override
  String get sendMemoRecipientOnly => '받‍는 사‍람‍만 읽‍을 수 있‍어‍요';

  @override
  String get sendMemoSheetAdd => '메‍모 추‍가';

  @override
  String get sendMemoShieldedOnly => '메‍시‍지‍는 차‍폐 주‍소‍에‍서‍만 쓸 수 있‍어‍요';

  @override
  String get sendMemoWhitespaceOnly => '공‍백‍만 있‍어‍요';

  @override
  String get sendOpenContacts => '연‍락‍처 열‍기';

  @override
  String get sendPasteAction => '붙‍여‍넣‍기';

  @override
  String get sendPaymentRequestAmountNotSpecified => '금‍액‍이 지‍정‍되‍지 않‍았‍어‍요';

  @override
  String get sendPaymentRequestCheckBeforePayBody =>
      '다‍른 앱‍이 요‍청 링‍크‍의 주‍소‍나 금‍액‍을 바‍꿀 수 있‍어‍요.';

  @override
  String get sendPaymentRequestCheckBeforePayTitle => '결‍제‍하‍기 전‍에 확‍인‍하‍세‍요';

  @override
  String get sendPaymentRequestCheckFailed => '이 요‍청‍을 확‍인‍하‍지 못‍했‍어‍요';

  @override
  String get sendPaymentRequestCheckGeneric =>
      '이 요‍청‍을 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 내‍용‍을 수‍정‍해 주‍세‍요';

  @override
  String get sendPaymentRequestCheckNetwork =>
      '네‍트‍워‍크‍에 연‍결‍하‍지 못‍했‍어‍요. 연‍결 상‍태‍를 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요';

  @override
  String get sendPaymentRequestCheckNoAccount =>
      '선‍택‍된 계‍정‍이 없‍어‍요. 계‍정‍을 선‍택‍한 다‍음 이 링‍크‍를 다‍시 열‍어 주‍세‍요';

  @override
  String get sendPaymentRequestCheckNoAmount =>
      '이 링‍크‍에‍는 결‍제‍할 금‍액‍이 지‍정‍되‍지 않‍았‍어‍요. 금‍액‍을 입‍력‍하‍고 계‍속‍해 주‍세‍요';

  @override
  String get sendPaymentRequestCheckUpgradeHold =>
      '네‍트‍워‍크 업‍그‍레‍이‍드‍를 위‍해 일‍시 중‍지‍됐‍어‍요. 몇 분 후‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendPaymentRequestCheckUpgradeScheduleChanged =>
      '네‍트‍워‍크 업‍그‍레‍이‍드‍로 마‍이‍그‍레‍이‍션 일‍정‍이 바‍뀌‍었‍어‍요. 계‍획‍을 확‍인‍한 다‍음 다‍시 시‍작‍해 주‍세‍요.';

  @override
  String get sendPaymentRequestClose => '결‍제 요‍청 닫‍기';

  @override
  String get sendPaymentRequestConfirmWithSender =>
      '보‍낸 사‍람‍에‍게 내‍용‍을 확‍인‍하‍세‍요.';

  @override
  String get sendPaymentRequestHideFullAddress => '받‍는 주‍소 전‍체 숨‍기‍기';

  @override
  String get sendPaymentRequestHidePaymentDetails => '결‍제 상‍세 숨‍기‍기';

  @override
  String get sendPaymentRequestHideRequesterInfo => '요‍청‍자 정‍보 숨‍기‍기';

  @override
  String sendPaymentRequestHideRequesterInfoFor(String name) {
    return '$name‍의 요‍청‍자 정‍보 숨‍기‍기';
  }

  @override
  String get sendPaymentRequestInsufficientFunds =>
      '이 금‍액‍과 네‍트‍워‍크 수‍수‍료‍를 낼 ZEC‍가 부‍족‍해‍요';

  @override
  String sendPaymentRequestInsufficientFundsWithSpendable(String spendable) {
    return '이 금‍액‍과 네‍트‍워‍크 수‍수‍료‍를 낼 ZEC‍가 부‍족‍해‍요 ($spendable 사‍용 가‍능)';
  }

  @override
  String get sendPaymentRequestInvalidAddress => '받‍는 주‍소‍가 올‍바‍르‍지 않‍아‍요';

  @override
  String get sendPaymentRequestLinkDifferentAddress => '링‍크‍의 주‍소‍가 달‍랐‍어‍요';

  @override
  String get sendPaymentRequestLinkDifferentAmount => '링‍크‍의 금‍액‍이 달‍랐‍어‍요';

  @override
  String get sendPaymentRequestLinkDifferentDetails => '링‍크‍의 내‍용‍이 달‍랐‍어‍요';

  @override
  String get sendPaymentRequestLinkDifferentMemo => '링‍크‍의 메‍모‍가 달‍랐‍어‍요';

  @override
  String get sendPaymentRequestMatchesLink => '링‍크‍와 일‍치‍해‍요';

  @override
  String get sendPaymentRequestMemoIncluded => '메‍모 포‍함';

  @override
  String get sendPaymentRequestMemoIncludedHint =>
      '메‍모‍가 포‍함‍되‍어 있‍어‍요. 거‍래 메‍모‍를 확‍인‍하‍세‍요.';

  @override
  String get sendPaymentRequestNameDisclaimer =>
      '이 이‍름‍은 요‍청‍에 포‍함‍된 것‍이‍에‍요. 받‍는 주‍소‍의 주‍인‍을 확‍인‍해 주‍지‍는 않‍아‍요.';

  @override
  String get sendPaymentRequestNameSuppliedInRequest =>
      '요‍청‍에 포‍함‍된 이‍름‍이‍에‍요.';

  @override
  String get sendPaymentRequestNoteFromRequester => '요‍청‍자‍의 메‍모';

  @override
  String get sendPaymentRequestPaymentDetails => '결‍제 상‍세';

  @override
  String get sendPaymentRequestRecipient => '받‍는 사‍람';

  @override
  String get sendPaymentRequestReplacedNotice => '이‍전 링‍크‍를 대‍체‍했‍어‍요';

  @override
  String get sendPaymentRequestRequestFrom => '요‍청‍한 사‍람';

  @override
  String get sendPaymentRequestReviewLinkDetails => '링‍크 상‍세 검‍토';

  @override
  String get sendPaymentRequestReviewPayment => '결‍제 검‍토';

  @override
  String get sendPaymentRequestScanOriginalHint =>
      '원‍래 QR 코‍드‍를 Vizor‍에‍서 직‍접 스‍캔‍하‍세‍요.';

  @override
  String get sendPaymentRequestShowFullAddress => '받‍는 주‍소 전‍체 보‍기';

  @override
  String get sendPaymentRequestShowRequesterInfo => '요‍청‍자 정‍보 보‍기';

  @override
  String sendPaymentRequestShowRequesterInfoFor(String name) {
    return '$name‍의 요‍청‍자 정‍보 보‍기';
  }

  @override
  String get sendPaymentRequestSyncStalled =>
      '아‍직 동‍기‍화‍하‍는 중‍이‍에‍요. 지‍갑‍이 최‍신 상‍태‍가 되‍면 다‍시 확‍인‍하‍세‍요';

  @override
  String get sendPaymentRequestSyncing =>
      '지‍갑‍을 아‍직 동‍기‍화‍하‍는 중‍이‍에‍요. 끝‍나‍면 자‍동‍으‍로 업‍데‍이‍트‍돼‍요';

  @override
  String get sendPaymentRequestTransactionMemo => '거‍래 메‍모';

  @override
  String sendPaymentRequestUnavailableLabel(String label) {
    return '$label, 사‍용‍할 수 없‍음';
  }

  @override
  String sendPaymentRequestUnavailableWithReason(String label, String reason) {
    return '$label, 사‍용‍할 수 없‍음. $reason';
  }

  @override
  String get sendPaymentRequestUsingQrInstead =>
      '대‍신 QR 코‍드‍를 사‍용‍해‍요. 링‍크‍가 바‍뀌‍었‍을 수 있‍어‍요.';

  @override
  String get sendPaymentRequestViewNote => '메‍모 보‍기';

  @override
  String get sendPaymentRequestYourAccount => '내 계‍정';

  @override
  String get sendQrScannerOpenFailed =>
      'QR 스‍캐‍너‍를 열‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendRecentsSection => '최‍근 보‍낸 곳';

  @override
  String get sendRecipientHint => '주‍소 또‍는 요‍청 링‍크';

  @override
  String get sendRecipientLabel => '받‍는 사‍람';

  @override
  String get sendRecipientUnreadableRequestLink => '이 요‍청 링‍크‍를 읽‍을 수 없‍어‍요';

  @override
  String get sendRecipientWrongNetwork => '이 주‍소‍는 다‍른 Zcash 네‍트‍워‍크‍의 주‍소‍예‍요';

  @override
  String get sendRequestScanCheckFailed =>
      '이 QR 코‍드‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendRequestScanInvalidAddress =>
      '이 QR 코‍드‍는 올‍바‍른 Zcash 주‍소‍가 아‍니‍에‍요.';

  @override
  String get sendRequestScanInvalidRequest =>
      '이 QR 코‍드‍에‍는 올‍바‍른 결‍제 요‍청‍이 들‍어 있‍지 않‍아‍요.';

  @override
  String get sendRequestScanNotRequest =>
      '이 QR 코‍드‍는 Zcash 주‍소‍나 결‍제 요‍청‍이 아‍니‍에‍요.';

  @override
  String get sendRequestScanPermission =>
      '결‍제 요‍청 QR 코‍드‍를 스‍캔‍하‍려‍면 카‍메‍라‍가 필‍요‍해‍요.\n카‍메‍라 접‍근 권‍한‍은 언‍제‍든 설‍정‍에‍서 바‍꿀 수 있‍어‍요.';

  @override
  String get sendRequestScanSubtitle =>
      '요‍청‍한 사‍람‍의 원‍래 QR 코‍드‍를 카‍메‍라‍에 보‍여 주‍세‍요';

  @override
  String get sendRequestScanTipOriginal =>
      '다‍른 기‍기‍에‍서 요‍청‍한 사‍람‍의 원‍래 QR 코‍드‍를 전‍체 화‍면‍으‍로 여‍세‍요.';

  @override
  String get sendRequestScanUnavailable =>
      '카‍메‍라‍를 연‍결‍하‍거‍나 뒤‍로 가‍서 링‍크 상‍세‍를 검‍토‍하‍세‍요.';

  @override
  String get sendRequestScanWrongNetwork => '이 주‍소‍는 다‍른 네‍트‍워‍크‍의 주‍소‍예‍요.';

  @override
  String get sendReviewAction => '검‍토';

  @override
  String get sendReviewCalculatingFee => '수‍수‍료‍를 계‍산‍하‍는 중...';

  @override
  String get sendReviewConfirmAndSend => '확‍인‍하‍고 보‍내‍기';

  @override
  String get sendReviewConfirmAndSendMobile => '확‍인‍하‍고 보‍내‍기';

  @override
  String get sendReviewConfirmDonation => '후‍원 확‍인';

  @override
  String get sendReviewConfirmWithLedger => 'Ledger‍로 확‍인';

  @override
  String get sendReviewFeeUnavailable => '수‍수‍료‍를 확‍인‍할 수 없‍어‍요';

  @override
  String get sendReviewFinishingSyncButton => '지‍갑 동‍기‍화‍를 마‍무‍리‍하‍는 중...';

  @override
  String sendReviewRequestedAmount(String amount) {
    return '요‍청 금‍액 $amount';
  }

  @override
  String get sendReviewRequestedBy => '요‍청‍한 사‍람';

  @override
  String get sendReviewTitle => '보‍내‍기 검‍토';

  @override
  String get sendSaplingDownloadBody =>
      '이 비‍공‍개 거‍래‍를 만‍들‍려‍면 지‍갑‍이 약 50MB‍의 암‍호‍화 매‍개‍변‍수‍를 내‍려‍받‍아‍야 해‍요.';

  @override
  String get sendSaplingDownloadNote =>
      '한 번‍만 내‍려‍받‍으‍면 돼‍요.\n데‍이‍터 요‍금‍이 발‍생‍할 수 있‍어‍요.';

  @override
  String get sendSaplingDownloadTitle => '다‍운‍로‍드‍가 필‍요‍해‍요';

  @override
  String get sendScanDowngradePastedMalformedRequest =>
      '주‍소‍만 붙‍여‍넣‍었‍어‍요. 결‍제 요‍청‍을 읽‍을 수 없‍었‍어‍요';

  @override
  String get sendScanDowngradePastedMultipleRecipients =>
      '첫 번‍째 받‍는 사‍람‍만 붙‍여‍넣‍었‍어‍요. 이 요‍청‍에‍는 받‍는 사‍람‍이 여‍러 명‍이‍에‍요';

  @override
  String get sendScanDowngradePastedUnsupportedMemo =>
      '주‍소‍만 붙‍여‍넣‍었‍어‍요. 요‍청‍의 메‍시‍지‍를 읽‍을 수 없‍었‍어‍요';

  @override
  String get sendScanDowngradeScannedMalformedRequest =>
      '주‍소‍만 스‍캔‍했‍어‍요. 결‍제 요‍청‍을 읽‍을 수 없‍었‍어‍요';

  @override
  String get sendScanDowngradeScannedMultipleRecipients =>
      '첫 번‍째 받‍는 사‍람‍만 스‍캔‍했‍어‍요. 이 요‍청‍에‍는 받‍는 사‍람‍이 여‍러 명‍이‍에‍요';

  @override
  String get sendScanDowngradeScannedUnsupportedMemo =>
      '주‍소‍만 스‍캔‍했‍어‍요. 요‍청‍의 메‍시‍지‍를 읽‍을 수 없‍었‍어‍요';

  @override
  String get sendScanNotZcashAddress => '이 QR 코‍드‍는 Zcash 주‍소‍가 아‍니‍에‍요.';

  @override
  String get sendScanQrSubtitle => '주‍소 또‍는 결‍제 요‍청 스‍캔';

  @override
  String get sendScanQrTitle => 'QR 코‍드 스‍캔';

  @override
  String get sendSendingToLabel => '받‍는 사‍람';

  @override
  String get sendSignConfirmTransaction => '거‍래 확‍인';

  @override
  String sendSignConfirmTransactionOfTwo(int index) {
    return '거‍래 확‍인 ($index/2)';
  }

  @override
  String get sendSpendableInfoLabel => '사‍용 가‍능‍한 잔‍액 정‍보';

  @override
  String get sendSpendableTooltipBody =>
      '자‍금‍을 사‍용‍하‍려‍면 먼‍저 확‍인‍이 필‍요‍해‍요. 내 지‍갑‍에‍서 돌‍아‍온 잔‍돈‍은 3‍회, 다‍른 사‍람‍에‍게 받‍은 자‍금‍은 6‍회‍예‍요. 차‍폐 노‍트‍도 모‍두 스‍캔‍되‍어‍야 해‍요. 곧 사‍용‍할 수 있‍게 돼‍요.';

  @override
  String get sendSpendableTooltipTitle =>
      '사‍용 가‍능‍한 잔‍액‍이 전‍체 잔‍액‍보‍다 적‍을 수 있‍어‍요.';

  @override
  String get sendStatusDonationFailed => '후‍원‍하‍지 못‍했‍어‍요';

  @override
  String get sendStatusDonationInProgress => '후‍원‍하‍는 중...';

  @override
  String sendStatusFailureSummary(String amount, String recipient) {
    return '$recipient‍에‍게 $amount';
  }

  @override
  String get sendStatusMobileConfirmSoon =>
      '곧 온‍체‍인‍에‍서 확‍인‍돼‍요. 활‍동‍에‍서 진‍행 상‍황‍을 확‍인‍해 보‍세‍요.';

  @override
  String get sendStatusMobileDonationQueued => '후‍원‍이 대‍기 중‍이‍에‍요';

  @override
  String get sendStatusMobileDonationSupport =>
      '보‍내 주‍신 후‍원 덕‍분‍에 Vizor‍가 계‍속 나‍아‍갈 수 있‍어‍요.';

  @override
  String get sendStatusMobileDonationThanks => 'Vizor‍를\n후‍원‍해 주‍셔‍서 감‍사‍해‍요';

  @override
  String get sendStatusMobileNothingSent =>
      '아‍무‍것‍도 보‍내‍지 않‍았‍고 자‍금‍은 그‍대‍로‍예‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendStatusMobilePendingDefault =>
      '거‍래‍가 만‍들‍어‍졌‍고 자‍동‍으‍로 제‍출‍돼‍요. 다‍시 보‍내‍기 전‍에 활‍동 페‍이‍지‍를 확‍인‍하‍세‍요.';

  @override
  String get sendStatusMobileQueued => '보‍내‍기 대‍기 중';

  @override
  String get sendStatusMobileReturnToSettings => '설‍정‍으‍로 돌‍아‍가‍기';

  @override
  String get sendStatusMobileSendingDonation => '후‍원‍을 보‍내‍는 중...';

  @override
  String get sendStatusMobileSent => '보‍냈‍어‍요!';

  @override
  String get sendStatusMobileSubmitting => '거‍래‍를 네‍트‍워‍크‍에 제‍출‍하‍는 중...';

  @override
  String get sendStatusRetryAfterSync =>
      '지‍갑 동‍기‍화‍가 끝‍날 때‍까‍지 기‍다‍린 다‍음 이 서‍명‍된 거‍래‍를 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get sendStatusRowStatus => '상‍태';

  @override
  String get sendStatusScanKeystoneTitle => 'Keystone QR 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String get sendStatusTitleInProgress => '보‍내‍는 중...';

  @override
  String get sendStepEnterAmount => '금‍액 입‍력';

  @override
  String get sendStepReviewDonation => '후‍원 검‍토';

  @override
  String get sendStepReviewSend => '보‍내‍기 검‍토';

  @override
  String sendTitle(String currency) {
    return '$currency 보‍내‍기';
  }

  @override
  String get sendUseMax => '최‍대 사‍용';

  @override
  String sendUseMaxSemantics(String spendable) {
    return '사‍용 가‍능‍한 최‍대 잔‍액 사‍용, $spendable 사‍용 가‍능';
  }

  @override
  String get sendUseMaxSemanticsShort => '사‍용 가‍능‍한 최‍대 잔‍액 사‍용';

  @override
  String sendVerifyAddressPreviousTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이‍전 거‍래 $count‍건',
    );
    return '$_temp0';
  }

  @override
  String get settingsAccountChangedPasscode =>
      '선‍택‍한 계‍정‍이 바‍뀌‍었‍어‍요. 암‍호‍를 다‍시 입‍력‍해 주‍세‍요.';

  @override
  String get settingsAccountChangedPassword =>
      '선‍택‍한 계‍정‍이 바‍뀌‍었‍어‍요. 비‍밀‍번‍호‍를 다‍시 입‍력‍해 주‍세‍요.';

  @override
  String get settingsAccountUnavailable => '선‍택‍한 계‍정‍을 더 이‍상 사‍용‍할 수 없‍어‍요.';

  @override
  String get settingsBackToAccounts => '계‍정‍으‍로 돌‍아‍가‍기';

  @override
  String settingsBiometricOffToast(String feature) {
    return '$feature 꺼‍짐';
  }

  @override
  String settingsBiometricOnToast(String feature) {
    return '$feature 켜‍짐';
  }

  @override
  String settingsBiometricSetupFirst(String biometric) {
    return '먼‍저 기‍기 설‍정‍에‍서 $biometric 설‍정‍을 마‍쳐 주‍세‍요.';
  }

  @override
  String settingsBiometricTurnOffBody(String feature) {
    return '앞‍으‍로‍는 암‍호‍로 Vizor 잠‍금‍을 해‍제‍해‍요. $feature‍는 언‍제‍든 설‍정‍에‍서 다‍시 켤 수 있‍어‍요.';
  }

  @override
  String settingsBiometricTurnOffTitle(String feature) {
    return '$feature‍를 끌‍까‍요?';
  }

  @override
  String settingsBiometricUpdateFailed(String feature) {
    return '$feature‍를 변‍경‍하‍지 못‍했‍어‍요.';
  }

  @override
  String get settingsBip39PassphraseCopied => 'BIP39 패‍스‍프‍레‍이‍즈‍를 복‍사‍했‍어‍요';

  @override
  String get settingsBip39PassphraseCopy => 'BIP39 패‍스‍프‍레‍이‍즈 복‍사';

  @override
  String get settingsBirthdayBlockHeight => '생‍성 블‍록 높‍이';

  @override
  String get settingsBirthdayDate => '생‍성 날‍짜';

  @override
  String get settingsBirthdayDateCopied => '생‍성 날‍짜‍를 복‍사‍했‍어‍요';

  @override
  String get settingsBirthdayHeightCopied => '생‍성 블‍록 높‍이‍를 복‍사‍했‍어‍요';

  @override
  String get settingsConfirmAccessSubtitle => '본‍인 확‍인‍이 필‍요‍해‍요';

  @override
  String get settingsConfirmAccessTitle => '접‍근 확‍인';

  @override
  String settingsCopyLabel(String label) {
    return '$label 복‍사';
  }

  @override
  String settingsCopyLabelCopied(String label) {
    return '$label 복‍사‍됨';
  }

  @override
  String settingsEndpointBalanceNote(String ticker) {
    return '지‍갑‍에‍는 마‍지‍막‍으‍로 연‍결‍에 성‍공‍했‍을 때‍의 잔‍액‍이 표‍시‍돼‍요. 최‍근‍에 받‍은 $ticker‍는 표‍시‍되‍지 않‍아‍요.';
  }

  @override
  String get settingsEndpointCloseSettings => '엔‍드‍포‍인‍트 설‍정 닫‍기';

  @override
  String get settingsEndpointConnectFailed =>
      '엔‍드‍포‍인‍트‍에 연‍결‍하‍지 못‍했‍어‍요. 호‍스‍트‍와 포‍트‍를 확‍인‍해 주‍세‍요.';

  @override
  String get settingsEndpointCurrentPrefix => '현‍재: ';

  @override
  String get settingsEndpointCustomise => '엔‍드‍포‍인‍트 직‍접 설‍정';

  @override
  String get settingsEndpointCustomize => '엔‍드‍포‍인‍트 직‍접 설‍정';

  @override
  String get settingsEndpointDefaultMarker => '(기‍본‍값)';

  @override
  String get settingsEndpointSelectFromList => '목‍록‍에‍서 선‍택';

  @override
  String get settingsEndpointTitle => '엔‍드‍포‍인‍트';

  @override
  String get settingsEndpointUpdating => '엔‍드‍포‍인‍트 업‍데‍이‍트 중...';

  @override
  String get settingsEndpointWarningBlockchain =>
      '엔‍드‍포‍인‍트‍를 잘‍못 설‍정‍하‍면 지‍갑‍이 Zcash 블‍록‍체‍인‍과 동‍기‍화‍되‍지 않‍아‍요.';

  @override
  String get settingsEndpointWarningNetwork =>
      '엔‍드‍포‍인‍트‍를 잘‍못 설‍정‍하‍면 지‍갑‍이 Zcash 네‍트‍워‍크‍와 동‍기‍화‍되‍지 않‍아‍요.';

  @override
  String get settingsEndpointsTitle => '엔‍드‍포‍인‍트';

  @override
  String get settingsEnterCurrentPasswordAgain =>
      '현‍재 비‍밀‍번‍호‍를 다‍시 입‍력‍해 주‍세‍요.';

  @override
  String get settingsEnterCurrentPasswordFirst =>
      '먼‍저 현‍재 비‍밀‍번‍호‍를 입‍력‍하‍세‍요.';

  @override
  String get settingsEnterPasscodeTitle => '암‍호 입‍력';

  @override
  String settingsExplorerCurrent(String explorer) {
    return '현‍재: $explorer';
  }

  @override
  String settingsExplorerCurrentDefault(String host) {
    return '현‍재: $host (기‍본‍값)';
  }

  @override
  String get settingsExplorerCustom => '직‍접 입‍력';

  @override
  String get settingsExplorerCustomSubtitle => '원‍하‍는 탐‍색‍기‍를 사‍용‍해‍요';

  @override
  String get settingsExplorerErrorEmpty => '탐‍색‍기 URL‍을 입‍력‍하‍세‍요.';

  @override
  String get settingsExplorerErrorHost =>
      'explorer.example‍처‍럼 호‍스‍트‍를 입‍력‍하‍세‍요.';

  @override
  String get settingsExplorerErrorScheme => 'http 또‍는 https URL‍을 입‍력‍하‍세‍요.';

  @override
  String get settingsExplorerPrivacyCopy =>
      '거‍래 링‍크‍는 이 탐‍색‍기‍에‍서 열‍려‍요. ZecBlock‍이‍나 원‍하‍는 다‍른 사‍이‍트‍를 사‍용‍하‍세‍요. 보‍낸 뒤‍에 공‍개 탐‍색‍기‍를 열‍면 내 IP 주‍소‍가 해‍당 거‍래‍와 연‍결‍될 수 있‍어‍요.';

  @override
  String get settingsExplorerSaveFailed => '탐‍색‍기 URL‍을 저‍장‍하‍지 못‍했‍어‍요.';

  @override
  String settingsExplorerTemplateHint(String txid, String txHash) {
    return '경‍로‍에 $txid 또‍는 $txHash‍를 넣‍거‍나 도‍메‍인‍만 입‍력‍하‍세‍요.';
  }

  @override
  String get settingsExplorerTitle => '블‍록 탐‍색‍기';

  @override
  String get settingsExplorerUpdate => '탐‍색‍기 업‍데‍이‍트';

  @override
  String get settingsExplorerUrlLabel => '탐‍색‍기 URL';

  @override
  String get settingsIncorrectPasscode => '암‍호‍가 맞‍지 않‍아‍요';

  @override
  String get settingsKeepAwakeDescription =>
      '휴‍대‍폰‍이 잠‍자‍기 모‍드‍로 전‍환‍되‍지 않‍아 동‍기‍화‍가 더 빨‍리 끝‍나‍요. 앱‍은 1‍분‍간 사‍용‍하‍지 않‍으‍면 그‍대‍로 잠‍겨‍요.';

  @override
  String get settingsKeepAwakeUpdateFailed =>
      '화‍면 켜‍짐 유‍지 설‍정‍을 변‍경‍하‍지 못‍했‍어‍요.';

  @override
  String get settingsLanguageLabel => '언‍어';

  @override
  String get settingsLanguageUpdateFailed => '언‍어‍를 바‍꾸‍지 못‍했‍어‍요.';

  @override
  String get settingsNewBadge => '신‍규';

  @override
  String get settingsNoActiveAccount => '선‍택‍된 계‍정‍이 없‍어‍요.';

  @override
  String get settingsPasscodeCheckFailed =>
      '암‍호‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsPasscodeMustDiffer => '새 암‍호‍는 기‍존 암‍호‍와 달‍라‍야 해‍요.';

  @override
  String get settingsPasscodeRotationRecoveryFailed =>
      '이‍전 암‍호 변‍경‍을 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍기 전‍에 복‍구 문‍구‍를 준‍비‍해 두‍세‍요.';

  @override
  String get settingsPasscodeUpdateFailed =>
      '암‍호‍를 변‍경‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsPasscodeUpdatedToast => '암‍호‍를 변‍경‍했‍어‍요';

  @override
  String get settingsPasscodeVerifyFailed =>
      '암‍호‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsPasswordHint => '비‍밀‍번‍호 입‍력...';

  @override
  String get settingsPasswordMinimumHint =>
      '8‍자 이‍상‍이‍어‍야 해‍요. 숫‍자‍와 기‍호‍를 더‍하‍거‍나 더 길‍게 만‍들‍면 더 안‍전‍해‍요.';

  @override
  String get settingsPasswordRotationRecoveryFailed =>
      '이‍전 비‍밀‍번‍호 변‍경‍을 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍기 전‍에 복‍구 문‍구‍를 준‍비‍해 두‍세‍요.';

  @override
  String get settingsPasswordUpdateFailed =>
      '비‍밀‍번‍호‍를 변‍경‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsPfpSamurai => '사‍무‍라‍이';

  @override
  String get settingsPfpViking => '바‍이‍킹';

  @override
  String get settingsPirCheckingUpdates => '업‍데‍이‍트 확‍인 중…';

  @override
  String get settingsPirChooseServer => '서‍버 선‍택';

  @override
  String get settingsPirConfigOpenFailed => '설‍정 저‍장‍소‍를 열‍지 못‍했‍어‍요.';

  @override
  String get settingsPirCustomInvalid =>
      '저‍장‍된 사‍용‍자 지‍정 서‍버‍가 올‍바‍르‍지 않‍아‍요. 수‍정‍하‍거‍나 다‍른 서‍버‍를 선‍택‍하‍세‍요.';

  @override
  String get settingsPirCustomServer => '사‍용‍자 지‍정 서‍버';

  @override
  String get settingsPirCustomServerEllipsis => '사‍용‍자 지‍정 서‍버…';

  @override
  String get settingsPirCustomUrlInvalid =>
      '자‍격 증‍명, 쿼‍리, 프‍래‍그‍먼‍트‍가 없‍는 HTTPS 기‍본 URL‍을 입‍력‍하‍세‍요.';

  @override
  String get settingsPirEditCustomServer => '사‍용‍자 지‍정 서‍버 편‍집…';

  @override
  String get settingsPirListLoadFailed =>
      '서‍버 목‍록‍을 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 사‍용‍자 지‍정 서‍버‍를 입‍력‍하‍세‍요.';

  @override
  String get settingsPirListUpdateFailed =>
      '서‍버 목‍록‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 마‍지‍막‍으‍로 불‍러‍온 목‍록‍을 사‍용‍해‍요.';

  @override
  String get settingsPirListUpdateFailedCustom =>
      '목‍록‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 사‍용‍자 지‍정 서‍버‍가 계‍속 선‍택‍되‍어 있‍어‍요.';

  @override
  String get settingsPirLoadingServers => '서‍버 목‍록‍을 불‍러‍오‍는 중…';

  @override
  String get settingsPirNoServers =>
      '아‍직 제‍공‍되‍는 서‍버‍가 없‍어‍요. 사‍용‍자 지‍정 서‍버‍를 입‍력‍할 수 있‍어‍요.';

  @override
  String get settingsPirServerChangeFailed =>
      '서‍버‍를 변‍경‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsPirServerCloseLabel => '비‍공‍개 조‍회 서‍버 설‍정 닫‍기';

  @override
  String get settingsPirServerRemoved =>
      '선‍택‍한 서‍버‍가 더 이‍상 제‍공‍되‍지 않‍아‍요. 비‍공‍개 조‍회‍를 다‍시 시‍작‍하‍려‍면 다‍른 서‍버‍를 선‍택‍하‍세‍요.';

  @override
  String get settingsPirServerSettingsLabel => '비‍공‍개 조‍회 서‍버 설‍정';

  @override
  String get settingsPirServerTitle => '비‍공‍개 조‍회 서‍버';

  @override
  String get settingsPirSettingsReadFailed =>
      '비‍공‍개 조‍회 서‍버 설‍정‍을 읽‍지 못‍했‍어‍요.';

  @override
  String get settingsPirShareServer => '내 서‍버 공‍유';

  @override
  String get settingsPirUnavailable =>
      '이 네‍트‍워‍크‍에‍서‍는 비‍공‍개 조‍회‍를 사‍용‍할 수 없‍어‍요.';

  @override
  String get settingsPirUpdatingServer => '서‍버 변‍경 중…';

  @override
  String get settingsPirUseCustomServer => '사‍용‍자 지‍정 서‍버 사‍용';

  @override
  String get settingsPrivacyTitle => '프‍라‍이‍버‍시';

  @override
  String get settingsPrivateQueriesCopy =>
      '실‍험‍적 기‍능‍이‍에‍요. 투‍명 자‍금‍을 비‍공‍개‍로 복‍구‍해 서‍버‍가 내 투‍명 주‍소‍를 알‍지 못‍하‍게 해‍요. 지‍원‍되‍는 거‍래‍는 서‍버‍에 ID‍를 알‍리‍지 않‍고 조‍회‍해‍요.';

  @override
  String get settingsPrivateQueriesIosNote =>
      '켜‍져 있‍는 동‍안‍에‍는 Vizor‍가 열‍려 있‍을 때‍만 마‍이‍그‍레‍이‍션 거‍래‍의 확‍인 수‍를 점‍검‍해‍요.';

  @override
  String get settingsPrivateQueriesLabel => '비‍공‍개 조‍회';

  @override
  String get settingsPrivateQueriesTurnOffBody =>
      'Vizor‍가 투‍명 내‍역‍을 공‍개 방‍식‍으‍로 다‍시 구‍성‍하‍며, 서‍버‍가 모‍든 주‍소‍를 알‍게 돼‍요.';

  @override
  String get settingsPrivateQueriesTurnOffDisclosure =>
      '서‍버‍가 모‍든 계‍정‍의 투‍명 주‍소 전‍부‍와 비‍공‍개 복‍구‍로 찾‍은 거‍래 ID‍를 받‍아‍요. 서‍버‍는 이‍를 서‍로 연‍결‍할 수 있‍고, Tor‍를 쓰‍지 않‍으‍면 IP 주‍소‍와‍도 연‍결‍할 수 있‍어‍요.';

  @override
  String get settingsPrivateQueriesTurnOffTitle => '비‍공‍개 조‍회‍를 끌‍까‍요?';

  @override
  String get settingsProfilePictureCustom => '사‍용‍자 지‍정';

  @override
  String get settingsRowAboutVizor => 'Vizor 정‍보';

  @override
  String get settingsRowAccountNameMobile => '계‍정 이‍름';

  @override
  String get settingsRowAddressBook => '주‍소‍록';

  @override
  String get settingsRowChangePasscode => '암‍호 변‍경';

  @override
  String get settingsRowChangePassword => '비‍밀‍번‍호 변‍경';

  @override
  String get settingsRowLinkMobile => 'Vizor 모‍바‍일 연‍결';

  @override
  String get settingsRowMyGiftCards => '내 기‍프‍트 카‍드';

  @override
  String get settingsRowProfilePicture => '프‍로‍필 사‍진';

  @override
  String get settingsRowProfilePictureMobile => '프‍로‍필 사‍진';

  @override
  String get settingsRowSecretPassphrase => '복‍구 문‍구';

  @override
  String get settingsRowUpdates => '업‍데‍이‍트';

  @override
  String get settingsRowViewingKeyMobile => '뷰‍잉 키';

  @override
  String get settingsSectionAccount => '계‍정';

  @override
  String get settingsSectionDangerZone => '위‍험 구‍역';

  @override
  String get settingsSectionMisc => '기‍타';

  @override
  String get settingsSectionPersonal => '개‍인';

  @override
  String get settingsSectionSystem => '시‍스‍템';

  @override
  String get settingsSeedBackupSaveFailed =>
      '저‍장‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsSeedBiometricReason => '복‍구 문‍구 접‍근 확‍인';

  @override
  String get settingsSeedCopiedToast => '복‍구 문‍구‍를 복‍사‍했‍어‍요';

  @override
  String get settingsSeedHeadingSubtitle =>
      '이‍것‍은 지‍갑‍의 마‍스‍터 키‍예‍요.\n누‍구‍에‍게‍도 공‍유‍하‍지 마‍세‍요.';

  @override
  String get settingsSeedLoadFailed =>
      '복‍구 문‍구‍를 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsSeedPasswordSubtitle => '복‍구 문‍구‍를 보‍려‍면 필‍요‍해‍요.';

  @override
  String get settingsSeedRemindLater => '나‍중‍에 알‍림';

  @override
  String get settingsSeedScreenshotAck => '확‍인';

  @override
  String settingsSeedScreenshotBody(String highlight) {
    return '$highlight. 휴‍대‍폰‍이‍나 사‍진 보‍관‍함‍에 접‍근‍할 수 있‍는 사‍람‍은 누‍구‍나 복‍구 문‍구‍를 볼 수 있‍어‍요. 대‍신 종‍이‍에 직‍접 적‍어 두‍세‍요.';
  }

  @override
  String get settingsSeedScreenshotBodyLead => '스‍크‍린‍샷‍은 안‍전‍하‍지 않‍아‍요';

  @override
  String get settingsSeedScreenshotTitle => '복‍구 문‍구‍를 스‍크‍린‍샷‍으‍로 남‍기‍지 마‍세‍요';

  @override
  String get settingsSeedUnavailableAccount => '이 계‍정‍에‍는 복‍구 문‍구‍가 없‍어‍요.';

  @override
  String get settingsSeedUnavailableHardware =>
      '하‍드‍웨‍어 계‍정‍에‍는 복‍구 문‍구‍가 없‍어‍요.';

  @override
  String get settingsSeedWrittenDown => '적‍어 두‍었‍어‍요';

  @override
  String get settingsSetNewPasscodeTitle => '새 암‍호 설‍정';

  @override
  String get settingsStatusOff => '꺼‍짐';

  @override
  String get settingsStatusOn => '켜‍짐';

  @override
  String get settingsThemeDark => '다‍크';

  @override
  String get settingsThemeLight => '라‍이‍트';

  @override
  String get settingsThemeSystem => '시‍스‍템';

  @override
  String get settingsThemeSystemAuto => '시‍스‍템(자‍동)';

  @override
  String get settingsThemeTitle => '테‍마';

  @override
  String get settingsThemeUpdateFailed => '테‍마‍를 변‍경‍하‍지 못‍했‍어‍요.';

  @override
  String get settingsTorDescBootstrapFailed =>
      'Vizor‍가 Tor‍에 연‍결‍하‍지 못‍했‍어‍요. 연‍결‍되‍거‍나 Tor‍를 끌 때‍까‍지 요‍청‍이 차‍단‍돼‍요.';

  @override
  String get settingsTorDescConnected =>
      'Vizor‍의 네‍트‍워‍크 요‍청‍은 Tor‍를 거‍쳐‍요. 다‍른 앱‍에‍서 연 링‍크‍는 해‍당 앱‍의 네‍트‍워‍크 설‍정‍을 따‍라‍요.';

  @override
  String get settingsTorDescConnectedIos =>
      'Vizor‍의 네‍트‍워‍크 요‍청‍은 Tor‍를 거‍쳐‍요. Ironwood 비‍공‍개 마‍이‍그‍레‍이‍션‍은 Vizor‍가 닫‍혀 있‍는 동‍안 직‍접 연‍결‍을 사‍용‍해‍요. 다‍른 앱‍에‍서 연 링‍크‍는 해‍당 앱‍의 네‍트‍워‍크 설‍정‍을 따‍라‍요.';

  @override
  String get settingsTorDescConnectedNoUpdates =>
      'Vizor‍의 네‍트‍워‍크 요‍청‍은 Tor‍를 거‍치‍지‍만 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 사‍용‍할 수 없‍어‍요.';

  @override
  String get settingsTorDescConnecting =>
      '새 요‍청‍은 Tor 연‍결‍이 준‍비‍될 때‍까‍지 기‍다‍려‍요. 연‍결‍을 멈‍추‍고 직‍접 연‍결‍을 쓰‍려‍면 Tor‍를 끄‍세‍요.';

  @override
  String get settingsTorDescConnectingLinux =>
      '새 요‍청‍은 Tor 연‍결‍이 준‍비‍될 때‍까‍지 기‍다‍려‍요. 연‍결‍을 멈‍추‍고 직‍접 연‍결‍을 쓰‍려‍면 Tor‍를 끄‍세‍요. 다‍른 앱‍에‍서 연 업‍데‍이‍트 페‍이‍지‍와 다‍운‍로‍드‍는 그 앱‍의 연‍결‍을 사‍용‍해‍요.';

  @override
  String get settingsTorDescConnectionFailed =>
      '직‍접 요‍청‍은 계‍속 차‍단‍돼‍요. 다‍시 시‍도‍하‍거‍나 Tor‍를 끄‍세‍요.';

  @override
  String get settingsTorDescDirectNoUpdates =>
      '네‍트‍워‍크 요‍청‍이 직‍접 연‍결‍돼‍요. 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 사‍용‍할 수 없‍어‍요.';

  @override
  String get settingsTorDescDisableNotSaved =>
      '요‍청‍은 이‍제 직‍접 연‍결‍을 사‍용‍하‍지‍만 Vizor‍가 변‍경 사‍항‍을 저‍장‍하‍지 못‍했‍어‍요. 앱‍을 다‍시 열‍면 Tor‍가 다‍시 켜‍져‍요.';

  @override
  String get settingsTorDescEnableNotSaved =>
      'Vizor‍가 변‍경 사‍항‍을 저‍장‍하‍지 못‍해 Tor‍가 켜‍지‍지 않‍았‍어‍요. 요‍청‍은 계‍속 직‍접 연‍결‍을 사‍용‍해‍요.';

  @override
  String get settingsTorDescOff =>
      'Tor‍가 꺼‍져 있‍어‍요. Zcash 네‍트‍워‍크, 앱 내 서‍비‍스, 소‍프‍트‍웨‍어 업‍데‍이‍트 요‍청‍이 직‍접 연‍결‍돼‍요.';

  @override
  String get settingsTorDescOffLinux =>
      'Tor‍가 꺼‍져 있‍어‍요. 소‍프‍트‍웨‍어 업‍데‍이‍트 확‍인‍을 포‍함‍한 Vizor‍의 요‍청‍이 직‍접 연‍결‍돼‍요. 업‍데‍이‍트 페‍이‍지‍와 다‍운‍로‍드‍는 다‍른 앱‍에‍서 열‍려‍요.';

  @override
  String get settingsTorDescOffMobile =>
      '지‍갑 동‍기‍화‍와 앱 내 요‍청‍이 직‍접 연‍결‍돼‍요. Vizor‍가 통‍신‍하‍는 서‍버‍로‍부‍터 IP 주‍소‍를 숨‍기‍려‍면 Tor‍를 켜‍세‍요.';

  @override
  String get settingsTorDescSwitchFailed =>
      'Vizor‍가 직‍접 연‍결‍로 전‍환‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsTorDescSwitchFailedStillOn =>
      'Vizor‍가 직‍접 연‍결‍로 전‍환‍하‍지 못‍했‍어‍요. Tor‍는 계‍속 켜‍져 있‍고 요‍청‍은 계‍속 Tor‍를 거‍쳐‍요.';

  @override
  String get settingsTorDescSwitching =>
      'Vizor‍가 네‍트‍워‍크 요‍청‍과 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 직‍접 연‍결‍로 전‍환‍하‍고 있‍어‍요.';

  @override
  String get settingsTorDescSwitchingLinux =>
      'Vizor‍가 소‍프‍트‍웨‍어 업‍데‍이‍트 확‍인‍을 포‍함‍한 요‍청‍을 직‍접 연‍결‍로 전‍환‍하‍고 있‍어‍요.';

  @override
  String get settingsTorDescSwitchingMobile =>
      'Vizor‍가 네‍트‍워‍크 요‍청‍을 직‍접 연‍결‍로 전‍환‍하‍고 있‍어‍요.';

  @override
  String get settingsTorGeneralDescription =>
      'Tor‍를 사‍용‍하‍면 서‍버‍로‍부‍터 IP 주‍소‍를 숨‍길 수 있‍어‍요. 다‍른 앱‍은 자‍체 네‍트‍워‍크 설‍정‍을 사‍용‍해‍요.';

  @override
  String get settingsTorGeneralIosSuffix =>
      ' Ironwood 비‍공‍개 마‍이‍그‍레‍이‍션‍은 Vizor‍가 닫‍혀 있‍는 동‍안 직‍접 연‍결‍돼‍요.';

  @override
  String get settingsTorRetryUpdates => '업‍데‍이‍트 다‍시 시‍도';

  @override
  String get settingsTorStatusConnected => '연‍결‍됨';

  @override
  String get settingsTorStatusConnectionFailed => '연‍결 실‍패';

  @override
  String get settingsTorStatusDirect => '직‍접 연‍결';

  @override
  String get settingsTorStatusNotSaved => '저‍장 실‍패';

  @override
  String get settingsTorStatusSwitchFailed => '전‍환 실‍패';

  @override
  String get settingsTorStatusSwitching => '전‍환 중…';

  @override
  String get settingsTorStatusSwitchingDirect => '직‍접 연‍결‍로 전‍환 중…';

  @override
  String get settingsTorStopConnecting => 'Tor 연‍결 중‍단';

  @override
  String get settingsTorTryDirect => '직‍접 연‍결 다‍시 시‍도';

  @override
  String get settingsTorUse => 'Tor 사‍용';

  @override
  String get settingsTurnOffConfirm => '끄‍기';

  @override
  String settingsUninstallActiveSwaps(int count) {
    return '이 지‍갑‍에 진‍행 중‍인 스‍왑‍이 $count‍개 있‍어‍요. 삭‍제‍하‍기 전‍에 모‍두 끝‍날 때‍까‍지 기‍다‍려 주‍세‍요.';
  }

  @override
  String get settingsUninstallClaimCheckFailed =>
      '받‍는 중‍인 기‍프‍트 카‍드‍를 확‍인‍하‍지 못‍했‍어‍요. 삭‍제‍하‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsUninstallCloseApp => 'Vizor 닫‍기';

  @override
  String get settingsUninstallDeviceGeneric => '이 기‍기';

  @override
  String get settingsUninstallDeviceMac => '이 Mac';

  @override
  String get settingsUninstallDevicePc => '이 PC';

  @override
  String get settingsUninstallDoneTitle => '데‍이‍터‍가 삭‍제‍되‍었‍어‍요';

  @override
  String get settingsUninstallFinishGeneric =>
      '삭‍제‍를 마‍치‍려‍면 이 기‍기‍에‍서 Vizor 앱‍을 제‍거‍하‍세‍요.';

  @override
  String get settingsUninstallFinishMac =>
      '삭‍제‍를 마‍치‍려‍면 응‍용 프‍로‍그‍램‍에‍서 Vizor 앱‍을 제‍거‍하‍세‍요.';

  @override
  String get settingsUninstallFinishWindows =>
      '삭‍제‍를 마‍치‍려‍면 Windows 설‍정‍에‍서 Vizor‍를 제‍거‍하‍세‍요.';

  @override
  String get settingsUninstallPasswordSubtitle => 'Vizor‍를 삭‍제‍하‍려‍면 필‍요‍해‍요.';

  @override
  String get settingsUninstallRemovingTitle => '데‍이‍터 삭‍제 중...';

  @override
  String get settingsUninstallSwapCheckFailed =>
      '진‍행 중‍인 스‍왑‍을 확‍인‍하‍지 못‍했‍어‍요. 삭‍제‍하‍기 전‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsUninstallTitle => 'Vizor 삭‍제';

  @override
  String get settingsUninstallWipeFailed =>
      '데‍이‍터‍를 모‍두 삭‍제‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String settingsUninstallWipeSubtitle(String device) {
    return 'Vizor‍가 $device‍에‍서 지‍갑 데‍이‍터‍와 보‍안 저‍장‍소‍를 삭‍제‍해‍요. 공‍유‍하‍지 않‍은 기‍프‍트 카‍드 링‍크‍는 영‍구‍적‍으‍로 사‍라‍져‍요.';
  }

  @override
  String get settingsUpdateApplying => '적‍용 중';

  @override
  String get settingsUpdateAvailable => '사‍용 가‍능';

  @override
  String get settingsUpdateCheck => '확‍인';

  @override
  String get settingsUpdateCheckForUpdates => '업‍데‍이‍트 확‍인';

  @override
  String get settingsUpdateChecking => '확‍인 중';

  @override
  String get settingsUpdateCurrentLabel => '현‍재';

  @override
  String get settingsUpdateDownloadButton => '업‍데‍이‍트 다‍운‍로‍드';

  @override
  String get settingsUpdateDownloadingButton => '다‍운‍로‍드 중…';

  @override
  String get settingsUpdatePasswordTitle => '비‍밀‍번‍호 변‍경';

  @override
  String get settingsUpdateRestartButton => '다‍시 시‍작‍해 업‍데‍이‍트';

  @override
  String get settingsUpdateRestartingButton => '다‍시 시‍작 중…';

  @override
  String settingsUpdateStatusAvailable(String version) {
    return '$version 버‍전‍을 사‍용‍할 수 있‍어‍요.';
  }

  @override
  String get settingsUpdateStatusChecking => '업‍데‍이‍트‍를 확‍인‍하‍고 있‍어‍요.';

  @override
  String settingsUpdateStatusDownloading(String percent) {
    return '$percent% 다‍운‍로‍드 중‍이‍에‍요.';
  }

  @override
  String get settingsUpdateStatusIdle => '업‍데‍이‍트‍를 확‍인‍할 준‍비‍가 되‍었‍어‍요.';

  @override
  String settingsUpdateStatusReady(String version) {
    return '버‍전 $version 설‍치 준‍비‍가 되‍었‍어‍요.';
  }

  @override
  String get settingsUpdateStatusRestarting => 'Vizor‍를 다‍시 시‍작‍하‍고 있‍어‍요.';

  @override
  String get settingsUpdateStatusUnsupported =>
      '설‍치‍된 Windows 앱‍에‍서 업‍데‍이‍트‍할 수 있‍어‍요.';

  @override
  String get settingsUpdateStatusUpToDate => 'Vizor‍가 최‍신 버‍전‍이‍에‍요.';

  @override
  String get settingsUpdateUnavailable => '사‍용 불‍가';

  @override
  String get settingsUpdateUpToDate => '최‍신 버‍전';

  @override
  String get settingsUpdatingPassword => '비‍밀‍번‍호 변‍경 중...';

  @override
  String settingsVersionFooterLabel(String version) {
    return 'Vizor, 버‍전 $version';
  }

  @override
  String get settingsViewingKeyBiometricReason => '뷰‍잉 키 접‍근 확‍인';

  @override
  String get settingsViewingKeyChoiceSharingWarning =>
      '신‍뢰‍하‍는 상‍대‍에‍게‍만 공‍유‍하‍세‍요. 두 키 모‍두 투‍명 잔‍액‍과 지‍출‍을 드‍러‍낼 수 있‍어‍요.';

  @override
  String get settingsViewingKeyChooseTitle =>
      '다‍른 사‍람‍이 볼 수 있‍는 범‍위‍를 선‍택‍하‍세‍요';

  @override
  String get settingsViewingKeyConfirmAgain =>
      '이 키‍를 불‍러‍오‍려‍면 접‍근‍을 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get settingsViewingKeyCopy => '뷰‍잉 키 복‍사';

  @override
  String get settingsViewingKeyExplanation =>
      '잔‍액‍과 과‍거·미‍래‍의 모‍든 거‍래‍를 드‍러‍내‍요. ZEC‍를 사‍용‍할 수‍는 없‍어‍요.';

  @override
  String get settingsViewingKeyFormatQr => 'QR 코‍드';

  @override
  String get settingsViewingKeyFormatText => '텍‍스‍트';

  @override
  String get settingsViewingKeyFullDescription =>
      '잔‍액‍과 받‍은 거‍래, 보‍낸 거‍래‍를 볼 수 있‍어‍요.';

  @override
  String get settingsViewingKeyIncomingExplanation =>
      '과‍거‍와 미‍래‍의 받‍은 결‍제‍를 드‍러‍내‍요. ZEC‍를 사‍용‍할 수‍는 없‍어‍요.';

  @override
  String get settingsViewingKeyIncomingOnly => '수‍신 전‍용';

  @override
  String get settingsViewingKeyIncomingOnlyDescription =>
      '받‍은 거‍래‍만 볼 수 있‍어‍요.';

  @override
  String get settingsViewingKeyIncomingWarningTitle =>
      '이 키‍로 받‍은 결‍제‍를 볼 수 있‍어‍요';

  @override
  String get settingsViewingKeyLoadFailedTitle => '뷰‍잉 키‍를 불‍러‍오‍지 못‍했‍어‍요';

  @override
  String get settingsViewingKeyPasswordSubtitle => '뷰‍잉 키‍를 보‍려‍면 필‍요‍해‍요.';

  @override
  String get settingsViewingKeyQrFull => '전‍체 뷰‍잉 키 QR 코‍드';

  @override
  String get settingsViewingKeyQrIncoming => '수‍신 전‍용 뷰‍잉 키 QR 코‍드';

  @override
  String get settingsViewingKeyTitle => '뷰‍잉 키';

  @override
  String get settingsViewingKeyTryCopyAgain => '다‍시 복‍사';

  @override
  String get settingsViewingKeyTypeFull => '전‍체 뷰‍잉 키';

  @override
  String get settingsViewingKeyTypeIncoming => '수‍신 전‍용 키';

  @override
  String get settingsViewingKeyWarningTitle => '이 키‍로 거‍래‍를 볼 수 있‍어‍요';

  @override
  String get settingsWalletSessionChanged =>
      '지‍갑 세‍션‍이 바‍뀌‍었‍어‍요. 비‍밀‍번‍호‍를 다‍시 입‍력‍해 주‍세‍요.';

  @override
  String get settingsWinUpdateContinueTor => 'Tor‍로 계‍속';

  @override
  String get settingsWinUpdateStartFailedTitle => '업‍데‍이‍트‍를 시‍작‍하‍지 못‍했‍어‍요';

  @override
  String get settingsWinUpdateTorBlockedBody =>
      'Vizor‍는 직‍접 요‍청‍을 계‍속 차‍단‍했‍어‍요. 설‍정‍에‍서 업‍데‍이‍트‍를 다‍시 시‍도‍하‍거‍나, Tor‍를 끄‍고 다‍시 다‍운‍로‍드‍해 보‍세‍요.';

  @override
  String get settingsWinUpdateTorBlockedTitle =>
      'Tor‍로‍는 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 사‍용‍할 수 없‍어‍요';

  @override
  String get settingsWinUpdateTorChoiceBody =>
      'Tor‍로 업‍데‍이‍트‍하‍면 더 오‍래 걸‍릴 수 있‍어‍요. Tor‍를 끄‍면 Vizor‍의 모‍든 네‍트‍워‍크 요‍청‍이 직‍접 연‍결‍로 바‍뀌‍어‍요.';

  @override
  String get settingsWinUpdateTorChoiceTitle => '이 업‍데‍이‍트‍에 Tor‍를 사‍용‍할‍까‍요?';

  @override
  String get settingsWinUpdateTorOffFailedBody =>
      'Tor‍가 켜‍진 채‍라‍서 Vizor‍가 업‍데‍이‍트‍를 계‍속 차‍단‍했‍어‍요. 다‍시 시‍도‍하‍거‍나, 설‍정‍에‍서 Tor‍를 끈 뒤 다‍운‍로‍드‍하‍세‍요.';

  @override
  String get settingsWinUpdateTorOffFailedTitle => 'Tor‍를 끄‍지 못‍했‍어‍요';

  @override
  String get settingsWinUpdateTurnOffTorAndUpdate => 'Tor‍를 끄‍고 업‍데‍이‍트';

  @override
  String get settingsWinUpdateUnavailableBody =>
      'Tor‍는 꺼‍져 있‍지‍만 소‍프‍트‍웨‍어 업‍데‍이‍트‍를 아‍직 사‍용‍할 수 없‍어‍요. 다‍운‍로‍드‍하‍기 전‍에 설‍정‍에‍서 업‍데‍이‍트‍를 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get settingsWinUpdateUnavailableTitle =>
      '소‍프‍트‍웨‍어 업‍데‍이‍트‍를 사‍용‍할 수 없‍어‍요';

  @override
  String get sidebarAccountNameFallback => '사‍용‍자 이‍름';

  @override
  String get sidebarAddressCopyFailed => '주‍소‍를 복‍사‍하‍지 못‍했‍어‍요';

  @override
  String get sidebarHideBalance => '잔‍액 숨‍기‍기';

  @override
  String get sidebarMigrationNeedsInput => '확‍인 필‍요';

  @override
  String get sidebarMyAccounts => '내 계‍정';

  @override
  String get sidebarShieldedAddressCopied => '차‍폐 주‍소‍를 복‍사‍했‍어‍요';

  @override
  String get sidebarShowBalance => '잔‍액 보‍기';

  @override
  String get swapActionAddRecipientAddress => '받‍는 주‍소 추‍가';

  @override
  String get swapActionAddRefundAddress => '환‍불 주‍소 추‍가';

  @override
  String get swapActionGettingQuote => '견‍적 가‍져‍오‍는 중';

  @override
  String swapActivityAddressBookRefund(String symbol) {
    return '$symbol 환‍불';
  }

  @override
  String swapActivityDeadlineHours(int hours) {
    return '$hours‍시‍간';
  }

  @override
  String swapActivityDeadlineMinutes(int minutes) {
    return '$minutes‍분';
  }

  @override
  String get swapActivityDepositAmount => '입‍금 금‍액';

  @override
  String get swapActivityDepositAssetFallback => '입‍금 자‍산';

  @override
  String swapActivityDepositInstructionDepositLabel(String symbol) {
    return '$symbol 입‍금';
  }

  @override
  String get swapActivityDepositInstructionReuseWarning =>
      '이 주‍소‍를 다‍시 사‍용‍하‍지 마‍세‍요';

  @override
  String swapActivityDepositInstructionSendFromSource(String symbol) {
    return '출‍발 체‍인‍에‍서 $symbol 보‍내‍기';
  }

  @override
  String swapActivityDepositInstructionSourceDepositLabel(String symbol) {
    return '$symbol 출‍발 체‍인 입‍금';
  }

  @override
  String swapActivityDepositInstructionSubmit(String symbol) {
    return '$symbol 입‍금 제‍출';
  }

  @override
  String swapActivityDepositInstructionTxHashHint(String symbol) {
    return '$symbol 출‍발 체‍인 거‍래 해‍시';
  }

  @override
  String swapActivityDepositInstructionTxHashLabel(String symbol) {
    return '$symbol 입‍금 거‍래 해‍시';
  }

  @override
  String get swapActivityDetailConfiguredQuote => '견‍적 설‍정‍값';

  @override
  String swapActivityDetailDeliveryTx(String symbol) {
    return '$symbol 전‍달 거‍래';
  }

  @override
  String get swapActivityDetailDepositDeadline => '입‍금 기‍한';

  @override
  String swapActivityDetailDepositTo(String symbol) {
    return '$symbol 입‍금 주‍소';
  }

  @override
  String swapActivityDetailDepositTx(String symbol) {
    return '$symbol 입‍금 거‍래';
  }

  @override
  String get swapActivityDetailDetectedDeposit => '확‍인‍된 입‍금‍액';

  @override
  String get swapActivityDetailFees => '수‍수‍료';

  @override
  String get swapActivityDetailIncluded => '포‍함‍됨';

  @override
  String get swapActivityDetailIncludedInRate => '표‍시‍된 환‍율‍에 포‍함‍됨';

  @override
  String get swapActivityDetailMissingDeposit => '부‍족‍한 입‍금‍액';

  @override
  String get swapActivityDetailRealizedSlippage => '실‍제 슬‍리‍피‍지';

  @override
  String get swapActivityDetailRequiredDeposit => '필‍요‍한 입‍금‍액';

  @override
  String swapActivityDetailSourceTxShielded(String symbol) {
    return '$symbol 거‍래(차‍폐)';
  }

  @override
  String get swapActivityDetailTotalFees => '총 수‍수‍료';

  @override
  String get swapActivityExpectedToReceive => '예‍상 수‍령 금‍액';

  @override
  String get swapActivityIncompleteDeposit => '입‍금 부‍족';

  @override
  String get swapActivityIncompletePayment => '결‍제 미‍완‍료';

  @override
  String get swapActivityLastCheckJustNow => '마‍지‍막 확‍인: 방‍금 전';

  @override
  String swapActivityLastCheckMinutesAgo(int minutes) {
    return '마‍지‍막 확‍인: $minutes‍분 전';
  }

  @override
  String get swapActivityNotReported => '보‍고‍되‍지 않‍음';

  @override
  String get swapActivityPaidSuccessfullyTitle => '결‍제‍를 완‍료‍했‍어‍요';

  @override
  String get swapActivityPayInProgressTitle => '결‍제 진‍행 중...';

  @override
  String get swapActivityPaymentComplete => '결‍제 완‍료';

  @override
  String swapActivityPickerNoRecipients(String symbol) {
    return '저‍장‍된 $symbol 받‍는 사‍람‍이 없‍어‍요';
  }

  @override
  String swapActivityPickerNoRefunds(String symbol) {
    return '저‍장‍된 $symbol 환‍불 주‍소‍가 없‍어‍요';
  }

  @override
  String swapActivityPickerRecipientsTitle(String symbol) {
    return '$symbol 받‍는 사‍람';
  }

  @override
  String swapActivityPickerRefundsTitle(String symbol) {
    return '$symbol 환‍불';
  }

  @override
  String get swapActivityReceiveAssetFallback => '수‍령 자‍산';

  @override
  String get swapActivityRecipientReceived => '받‍는 사‍람 수‍령‍액';

  @override
  String swapActivityStateAddressOrAccountHint(String chain) {
    return '$chain 주‍소 또‍는 계‍정';
  }

  @override
  String swapActivityStateAssetUnsupported(String symbol, String chain) {
    return '$chain‍의 $symbol 스‍왑‍은 현‍재 지‍원‍되‍지 않‍아‍요.';
  }

  @override
  String swapActivityStateDecimalPlaces(String symbol, int decimals) {
    return '$symbol 금‍액‍은 소‍수‍점 $decimals‍자‍리‍까‍지 지‍원‍해‍요.';
  }

  @override
  String get swapActivityStateDestination => '받‍는 주‍소';

  @override
  String swapActivityStateQuoteHigher(String percent) {
    return '실‍시‍간 견‍적‍이 이‍전 예‍상‍보‍다 $percent% 높‍아‍요. 계‍속‍하‍기 전‍에 최‍소 보‍장 수‍량‍을 확‍인‍하‍세‍요.';
  }

  @override
  String swapActivityStateQuoteLower(String percent) {
    return '실‍시‍간 견‍적‍이 이‍전 예‍상‍보‍다 $percent% 낮‍아‍요. 계‍속‍하‍기 전‍에 최‍소 보‍장 수‍량‍을 확‍인‍하‍세‍요.';
  }

  @override
  String swapActivityStateQuoteUsesDifferentSell(
    String liveAmount,
    String estimateAmount,
    String symbol,
  ) {
    return '실‍시‍간 견‍적‍은 $estimateAmount $symbol 대‍신 $liveAmount $symbol 수‍량‍을 사‍용‍해‍요. 계‍속‍하‍기 전‍에 최‍소 보‍장 수‍량‍을 확‍인‍하‍세‍요.';
  }

  @override
  String get swapActivityStatusAwaitingDeposit => '입‍금 대‍기 중';

  @override
  String get swapActivityStatusAwaitingExternalDeposit => '외‍부 입‍금 대‍기 중';

  @override
  String get swapActivityStatusComplete => '완‍료';

  @override
  String get swapActivityStatusDepositObserved => '입‍금 확‍인‍됨';

  @override
  String get swapActivityStatusExpired => '만‍료‍됨';

  @override
  String get swapActivityStatusProcessing => '처‍리 중';

  @override
  String get swapActivityStepConvert => '변‍환';

  @override
  String get swapActivityStepConvertDescription =>
      '차‍폐‍된 지‍출‍을 결‍제 자‍산‍으‍로 변‍환‍하‍고 있‍어‍요.';

  @override
  String get swapActivityStepConverting => '변‍환 중...';

  @override
  String swapActivityStepDeliver(String symbol) {
    return '$symbol 전‍달';
  }

  @override
  String swapActivityStepDeliverActive(String symbol) {
    return '$symbol 전‍달 중...';
  }

  @override
  String get swapActivityStepDeliverPayDescription =>
      '결‍제 금‍액‍을 받‍는 주‍소‍로 전‍달‍하‍고 있‍어‍요.';

  @override
  String get swapActivityStepDeliverSwapDescription =>
      '받‍을 자‍산‍을 받‍는 주‍소‍로 전‍달‍하‍고 있‍어‍요.';

  @override
  String swapActivityStepDelivering(String symbol) {
    return '$symbol 전‍달 중...';
  }

  @override
  String swapActivityStepDeposit(String symbol) {
    return '$symbol 입‍금';
  }

  @override
  String get swapActivityStepDepositConfirmation => '입‍금 확‍인';

  @override
  String get swapActivityStepDepositConfirmationActive => '입‍금 확‍인 중...';

  @override
  String get swapActivityStepDepositConfirmationDescription =>
      '스‍왑 경‍로‍를 시‍작‍하‍기 전‍에 입‍금‍을 확‍인‍하‍고 있‍어‍요.';

  @override
  String swapActivityStepDeposited(String symbol) {
    return '$symbol 입‍금 완‍료';
  }

  @override
  String swapActivityStepDepositing(String symbol) {
    return '$symbol 입‍금 중...';
  }

  @override
  String get swapActivityStepRecipientReceives => '받‍는 사‍람 수‍령';

  @override
  String swapActivityStepRecipientReceivesAsset(String symbol) {
    return '받‍는 사‍람‍에‍게 $symbol 전‍달 중...';
  }

  @override
  String get swapActivityStepRecipientReceivesDescription =>
      '받‍는 사‍람 쪽 결‍제‍를 확‍인‍하‍고 있‍어‍요.';

  @override
  String swapActivityStepSend(String symbol) {
    return '$symbol 보‍내‍기';
  }

  @override
  String swapActivityStepSendActive(String symbol) {
    return '$symbol 보‍내‍는 중...';
  }

  @override
  String swapActivityStepSending(String symbol) {
    return '$symbol 보‍내‍는 중...';
  }

  @override
  String swapActivityStepSent(String symbol) {
    return '$symbol 전‍송 완‍료';
  }

  @override
  String get swapActivityStepSourceDescription =>
      '출‍발 체‍인‍과 제‍공‍자‍가 입‍금‍을 인‍식‍할 때‍까‍지 기‍다‍리‍고 있‍어‍요';

  @override
  String swapActivityStepSpend(String symbol) {
    return '$symbol 사‍용';
  }

  @override
  String get swapActivityStepSpendDescription => '차‍폐‍된 잔‍액‍에‍서 사‍용‍하‍고 있‍어‍요.';

  @override
  String swapActivityStepSpending(String symbol) {
    return '$symbol 사‍용 중...';
  }

  @override
  String swapActivityStepSpent(String symbol) {
    return '$symbol 사‍용 완‍료';
  }

  @override
  String get swapActivityStepSwap => '스‍왑';

  @override
  String get swapActivityStepSwapActive => '스‍왑 중...';

  @override
  String get swapActivityStepSwapDescription =>
      '제‍공‍자‍가 스‍왑 경‍로‍를 실‍행‍하‍고 있‍어‍요.';

  @override
  String get swapActivitySwapCompleted => '스‍왑 완‍료';

  @override
  String get swapActivitySwapInProgress => '스‍왑 진‍행 중...';

  @override
  String get swapActivityTooltipFees =>
      '저‍희 수‍수‍료‍와 경‍로 제‍공‍자‍가 이 스‍왑‍을 처‍리‍하‍는 데 드‍는 비‍용‍이 포‍함‍돼‍요. 위 환‍율‍에 이‍미 반‍영‍되‍어 있‍어‍요.';

  @override
  String swapActivityTooltipMinimumReceive(String symbol) {
    return '슬‍리‍피‍지‍가 반‍영‍된 $symbol 최‍소 수‍령 금‍액‍이‍에‍요. 더 받‍을 수‍는 있‍지‍만 이‍보‍다 적‍게 받‍지‍는 않‍아‍요.';
  }

  @override
  String get swapActivityTooltipMinimumReceiveGeneric =>
      '슬‍리‍피‍지‍가 반‍영‍된 최‍소 수‍령 금‍액‍이‍에‍요. 더 받‍을 수‍는 있‍지‍만 이‍보‍다 적‍게 받‍지‍는 않‍아‍요.';

  @override
  String get swapActivityTooltipPriceProtection =>
      '슬‍리‍피‍지 허‍용‍치‍가 보‍호‍하‍는 수‍령 금‍액‍의 범‍위‍예‍요. 환‍율‍이 이 범‍위‍를 넘‍어 변‍하‍면 스‍왑‍이 환‍불‍돼‍요.';

  @override
  String get swapActivityTooltipStatusDetail =>
      '최‍신 스‍왑 기‍록‍과 제‍공‍자 상‍태‍를 바‍탕‍으‍로 한 정‍보‍예‍요.';

  @override
  String get swapActivityYouPaid => '지‍불‍한 금‍액';

  @override
  String get swapActivityYouReceived => '받‍은 금‍액';

  @override
  String swapAddressRecipientDescription(String symbol) {
    return '스‍왑‍한 $symbol 자‍산‍은 이 주‍소‍로 전‍송‍돼‍요.';
  }

  @override
  String get swapAddressRecipientFieldLabel => '받‍는 주‍소';

  @override
  String swapAddressRecipientTitle(String symbol) {
    return '$symbol 받‍는 주‍소';
  }

  @override
  String swapAddressRefundDescription(String symbol, String chain) {
    return '스‍왑‍이 실‍패‍하‍거‍나 환‍율‍이 변‍동‍되‍면 수‍수‍료‍를 제‍외‍한 금‍액‍을 $chain‍의 $symbol 자‍산‍으‍로 환‍불‍해 드‍려‍요.';
  }

  @override
  String get swapAddressRememberRecipient => '받‍는 주‍소‍로 이 주‍소 기‍억‍하‍기';

  @override
  String get swapAddressRememberRefund => '환‍불 주‍소‍로 이 주‍소 기‍억‍하‍기';

  @override
  String get swapAssetSelectorEmpty => '토‍큰‍이‍나 체‍인‍을 찾‍을 수 없‍어‍요';

  @override
  String get swapAssetSelectorSearchHint => '토‍큰 또‍는 체‍인 검‍색';

  @override
  String get swapAssetSelectorTitle => '자‍산 선‍택';

  @override
  String get swapComposerAddRecipientAddressEllipsis => '받‍는 주‍소 추‍가...';

  @override
  String get swapComposerAddRefundAddressEllipsis => '환‍불 주‍소 추‍가...';

  @override
  String swapComposerMaxAmount(String amount) {
    return '최‍대: $amount';
  }

  @override
  String get swapComposerYouReceive => '내‍가 받‍는 금‍액';

  @override
  String get swapContactAlreadyInAddressBook => '이‍미 주‍소‍록‍에 있‍어‍요';

  @override
  String get swapContactAlreadySaved => '이‍미 연‍락‍처‍에 있‍어‍요';

  @override
  String get swapDepositAmountCopiedDesktop => '금‍액‍을 복‍사‍했‍어‍요';

  @override
  String get swapDepositAmountCopiedMobile => '금‍액‍을 복‍사‍했‍어‍요';

  @override
  String get swapDepositAmountToDeposit => '입‍금‍할 금‍액';

  @override
  String get swapDepositChecking => '확‍인 중';

  @override
  String get swapDepositDoneDesktop => '입‍금‍했‍어‍요';

  @override
  String get swapDepositDoneMobile => '토‍큰‍을 입‍금‍했‍어‍요';

  @override
  String swapDepositHoursMany(int count) {
    return '$count‍시‍간';
  }

  @override
  String get swapDepositMemoCopied => '메‍모‍를 복‍사‍했‍어‍요';

  @override
  String swapDepositMinutesMany(int count) {
    return '$count‍분';
  }

  @override
  String get swapDepositOneTimeAddress => '일‍회‍용 주‍소';

  @override
  String swapDepositSendOnly(String symbol, String chain) {
    return '$chain‍의 $symbol‍만 보‍내‍세‍요';
  }

  @override
  String get swapDepositTimeoutBody =>
      '이 입‍금 주‍소‍는 더 이‍상 유‍효‍하‍지 않‍아‍요.\n새 스‍왑‍을 시‍작‍해 주‍세‍요.';

  @override
  String get swapDepositTitle => '토‍큰 입‍금';

  @override
  String get swapDepositWithin => '입‍금 기‍한';

  @override
  String get swapDepositZecButton => 'ZEC 입‍금';

  @override
  String get swapDismissBarrierLabel => '닫‍기';

  @override
  String get swapFailureAmountPrecision =>
      '금‍액‍의 소‍수‍점 자‍릿‍수‍가 너‍무 많‍아‍요.\n소‍수‍점 자‍릿‍수‍를 줄‍여 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureAmountTooLowPay =>
      '이 결‍제‍에‍는 금‍액‍이 너‍무 적‍어‍요.\n더 큰 금‍액‍으‍로 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureAmountTooLowSwap =>
      '이 스‍왑‍에‍는 금‍액‍이 너‍무 적‍어‍요.\n더 큰 금‍액‍으‍로 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureAssetUnavailable =>
      '지‍금‍은 이 자‍산‍을 스‍왑‍할 수 없‍어‍요.\n다‍른 자‍산‍을 선‍택‍하‍거‍나 나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureDepositNotIndexed =>
      '아‍직 입‍금‍이 확‍인‍되‍지 않‍았‍어‍요.\n몇 분 후‍에 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get swapFailureDepositRejected =>
      '입‍금 거‍래‍가 거‍부‍됐‍어‍요.\n주‍소, 메‍모, 거‍래 해‍시‍를 확‍인‍해 주‍세‍요.';

  @override
  String get swapFailureDepositSubmitFailed =>
      '입‍금 상‍태‍를 제‍출‍하‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureNoQuote =>
      '이 경‍로‍나 금‍액‍에 사‍용‍할 수 있‍는 견‍적‍이 없‍어‍요.\n금‍액, 슬‍리‍피‍지 또‍는 자‍산‍을 조‍정‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureQuoteTimeout =>
      '견‍적 요‍청 시‍간‍이 초‍과‍됐‍어‍요.\n연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureQuoteUnavailable =>
      '지‍금‍은 견‍적‍을 받‍을 수 없‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureQuoteUnverified =>
      '견‍적 응‍답‍을 검‍증‍하‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureRefreshFailed =>
      '스‍왑 상‍태‍를 새‍로‍고‍침‍하‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureRequestTimeout =>
      '요‍청 시‍간‍이 초‍과‍됐‍어‍요.\n연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureResponseUnverified =>
      '스‍왑 응‍답‍을 검‍증‍하‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureRouteRejected =>
      '이 경‍로 또‍는 주‍소‍가 거‍부‍됐‍어‍요.\n세‍부 정‍보‍를 수‍정‍하‍고 새 견‍적‍을 요‍청‍해 주‍세‍요.';

  @override
  String get swapFailureServiceUnavailable =>
      '스‍왑 서‍비‍스‍를 일‍시‍적‍으‍로 사‍용‍할 수 없‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureStartFailed =>
      '스‍왑‍을 시‍작‍하‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureStatusAssetUnsupported =>
      '스‍왑 상‍태‍에 지‍원‍되‍지 않‍는 자‍산 쌍‍이 있‍어‍요.\n자‍금‍을 다‍시 보‍내‍지 마‍세‍요. 나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureStatusAutoRefresh =>
      '최‍신 상‍태‍를 새‍로‍고‍침‍하‍지 못‍했‍어‍요.\n계‍속 시‍도‍하‍고 이 화‍면‍을 자‍동‍으‍로 업‍데‍이‍트‍할‍게‍요.';

  @override
  String get swapFailureStillProcessing =>
      '스‍왑 서‍비‍스‍가 아‍직 처‍리 중‍이‍에‍요.\n잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureTokensUnavailable =>
      '스‍왑 토‍큰‍을 불‍러‍오‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureTorBlockedPay =>
      '서‍비‍스‍가 이 연‍결‍을 차‍단‍해‍서 Tor‍로‍는 결‍제‍할 수 없‍어‍요.\n결‍제‍하‍려‍면 설‍정‍에‍서 Tor‍를 꺼 주‍세‍요.';

  @override
  String get swapFailureTorBlockedSwap =>
      '서‍비‍스‍가 이 연‍결‍을 차‍단‍해‍서 Tor‍로‍는 스‍왑‍할 수 없‍어‍요.\n스‍왑‍하‍려‍면 설‍정‍에‍서 Tor‍를 꺼 주‍세‍요.';

  @override
  String get swapFailureZecDepositFunding =>
      '이 스‍왑‍과 네‍트‍워‍크 수‍수‍료‍를 낼 수 있‍는 ZEC‍가 부‍족‍해‍요.\n더 적‍은 금‍액‍으‍로 시‍도‍하‍거‍나 최‍대 금‍액‍을 사‍용‍해 주‍세‍요.';

  @override
  String get swapFailureZecDepositPreflight =>
      'ZEC 입‍금‍을 준‍비‍하‍지 못‍했‍어‍요.\n잔‍액‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapFailureZecDepositSendFailed =>
      'ZEC 입‍금‍을 보‍내‍지 못‍했‍어‍요.\n나‍중‍에 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get swapKeystoneBroadcastFailed => '거‍래‍를 전‍송‍하‍지 못‍했‍어‍요.';

  @override
  String get swapKeystoneBroadcastingTitle => 'ZEC 입‍금 전‍송 중';

  @override
  String get swapKeystoneFailedTitle => 'Keystone 서‍명‍에 실‍패‍했‍어‍요';

  @override
  String get swapKeystoneFinalizing => 'ZEC 입‍금 전‍송 중...';

  @override
  String get swapKeystoneIncomplete => 'ZEC 입‍금 서‍명‍을 완‍료‍하‍지 못‍했‍어‍요.';

  @override
  String get swapKeystoneNoTex => 'Keystone‍은 아‍직 TEX 전‍송‍을 지‍원‍하‍지 않‍아‍요.';

  @override
  String get swapKeystoneScanCaption =>
      'Keystone‍의 QR 코‍드‍를 스‍캔‍해 ZEC 입‍금‍을 마‍무‍리‍하‍세‍요';

  @override
  String get swapKeystoneSignTitle => 'Keystone‍에‍서 ZEC 입‍금 서‍명';

  @override
  String get swapKeystoneStatusUncertain =>
      '거‍래 상‍태‍가 확‍실‍하‍지 않‍아‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 새‍로‍고‍침‍해 주‍세‍요.';

  @override
  String get swapLedgerBackToActivity => '활‍동‍으‍로 돌‍아‍가‍기';

  @override
  String get swapLedgerBroadcastFailed => 'ZEC 입‍금‍을 전‍송‍하‍지 못‍했‍어‍요.';

  @override
  String get swapLedgerDeclined => 'Ledger‍에‍서 ZEC 입‍금‍이 거‍부‍됐‍어‍요.';

  @override
  String get swapLedgerMessageBackground =>
      'Vizor‍가 이‍미 백‍그‍라‍운‍드‍에‍서 이 거‍래‍를 마‍무‍리‍하‍고 있‍어‍요.';

  @override
  String get swapLedgerMessageExpired =>
      '거‍래‍가 전‍송‍되‍기 전‍에 만‍료‍됐‍어‍요. Vizor‍가 예‍약‍된 자‍금‍을 아‍직 해‍제‍해‍야 해‍요.';

  @override
  String get swapLedgerMessageSentNotSaved =>
      '거‍래‍는 전‍송‍됐‍지‍만 Vizor‍가 저‍장‍을 마‍치‍지 못‍했‍어‍요.';

  @override
  String get swapLedgerMessageUncertain =>
      '거‍래‍가 전‍송‍됐‍는‍지 Vizor‍가 확‍인‍하‍지 못‍했‍어‍요. 상‍태‍를 아‍직 저‍장‍해‍야 해‍요.';

  @override
  String get swapLedgerRetryCleanup => '정‍리 다‍시 시‍도';

  @override
  String get swapLedgerSigningIncomplete => 'Ledger 서‍명‍을 완‍료‍하‍지 못‍했‍어‍요.';

  @override
  String get swapLedgerStatusCleanup => '정‍리 필‍요';

  @override
  String get swapLedgerStatusSaving => '거‍래 저‍장 중';

  @override
  String get swapLedgerTitlePending => '거‍래 상‍태 확‍인 중';

  @override
  String get swapLedgerTitleRecovery => '거‍래 복‍구 진‍행 중';

  @override
  String get swapLedgerTitleSent => '거‍래‍를 보‍냈‍어‍요';

  @override
  String get swapNoticeAccountChanged =>
      '선‍택‍한 계‍정‍이 바‍뀌‍었‍어‍요. 시‍작‍하‍기 전‍에 견‍적‍을 다‍시 확‍인‍해 주‍세‍요.';

  @override
  String get swapNoticeAffectedNetworks => '영‍향‍받‍는 네‍트‍워‍크';

  @override
  String get swapNoticeAllChains => '모‍든 체‍인';

  @override
  String get swapNoticeBroadcastNotStored =>
      '거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍지‍만 Vizor‍가 기‍기‍에 저‍장‍하‍지 못‍했‍어‍요. 동‍기‍화‍나 블‍록 탐‍색‍기‍에‍서 최‍신 상‍태‍를 확‍인‍하‍기 전‍에‍는 다‍시 시‍도‍하‍지 마‍세‍요.';

  @override
  String get swapNoticeBroadcastPartial =>
      '일‍부 입‍금 거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍을 수 있‍어‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get swapNoticeBroadcastPending =>
      '입‍금‍이 기‍기‍에‍서 생‍성‍됐‍지‍만 전‍송‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get swapNoticeBroadcastUncertain =>
      '입‍금 상‍태‍가 확‍실‍하‍지 않‍아‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get swapNoticeBroadcastUnknown =>
      '거‍래‍가 네‍트‍워‍크‍에 전‍달‍됐‍을 수 있‍지‍만 확‍인 시‍간‍이 초‍과‍됐‍어‍요. 다‍시 시‍도‍하‍기 전‍에 활‍동‍을 확‍인‍해 주‍세‍요.';

  @override
  String get swapNoticeCloseLabel => '서‍비‍스 안‍내 닫‍기';

  @override
  String get swapNoticeDepositIntentMissing =>
      'ZEC 입‍금‍이 전‍송‍됐‍지‍만 저‍장‍된 스‍왑 정‍보‍를 찾‍지 못‍했‍어‍요. 이 화‍면‍을 나‍가‍기 전‍에 거‍래 해‍시‍를 복‍사‍해 주‍세‍요.';

  @override
  String swapNoticeExpectedEnd(String time) {
    return '종‍료 예‍정: $time';
  }

  @override
  String get swapNoticeListOfMaintenance => '점‍검 목‍록';

  @override
  String get swapNoticeMaintenanceIntro => 'NEAR Intents‍가 점‍검 중‍이‍에‍요.';

  @override
  String get swapNoticeMaintenanceTitle => '점‍검 안‍내';

  @override
  String swapNoticeMaintenanceWindow(String networks) {
    return '점‍검 대‍상: $networks';
  }

  @override
  String get swapNoticeOk => '확‍인';

  @override
  String get swapNoticePaymentsMayFail => '지‍금‍은 결‍제‍가 되‍지 않‍을 수 있‍어‍요.';

  @override
  String get swapNoticeReceiveAddressUnavailable =>
      '새 지‍갑 받‍기 주‍소‍를 준‍비‍하‍지 못‍했‍어‍요. 지‍갑 동‍기‍화 후 다‍시 시‍도‍하‍거‍나, 새 견‍적‍을 요‍청‍하‍기 전‍에 대‍기 중‍인 예‍전 스‍왑‍을 닫‍아 주‍세‍요.';

  @override
  String get swapNoticeServiceTitle => '서‍비‍스 안‍내';

  @override
  String swapNoticeStart(String time) {
    return '시‍작: $time';
  }

  @override
  String get swapNoticeStatusPage => 'NEAR Intents 상‍태 페‍이‍지';

  @override
  String get swapNoticeSwapsMayFail => '지‍금‍은 스‍왑‍이 되‍지 않‍을 수 있‍어‍요.';

  @override
  String get swapPageTitle => '스‍왑';

  @override
  String get swapPanelDepositChecking => 'ZEC 입‍금‍을 확‍인‍하‍는 중';

  @override
  String get swapPanelDepositSent => 'ZEC 입‍금‍을 보‍냈‍어‍요';

  @override
  String get swapPanelLoadFailedBody =>
      '활‍동‍으‍로 돌‍아‍가 저‍장‍된 스‍왑‍을 선‍택‍해 주‍세‍요.';

  @override
  String get swapPanelLoadFailedTitle =>
      '이 스‍왑‍을 불‍러‍오‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 아‍래‍로 당‍겨 새‍로‍고‍침‍해 주‍세‍요.';

  @override
  String swapPanelRecipientTo(String recipient) {
    return '받‍는 사‍람: $recipient';
  }

  @override
  String get swapPayStatusConvertedFrom => '변‍환 전 금‍액';

  @override
  String get swapPayStatusNewAddress => '새 주‍소';

  @override
  String get swapPayStatusSourceAmount => '원‍래 금‍액';

  @override
  String get swapPoweredByLabel => '제‍공:';

  @override
  String swapQuoteExpiresAt(String time) {
    return '$time‍에 만‍료';
  }

  @override
  String get swapQuoteExpiryPending => '견‍적 만‍료 시‍간 확‍인 중';

  @override
  String get swapQuoteRatePending => '환‍율 확‍인 중';

  @override
  String get swapReviewBackPay => '결‍제';

  @override
  String get swapReviewConfirmAndSwap => '확‍인‍하‍고 스‍왑';

  @override
  String get swapReviewConfirmPaymentTitle => '결‍제 확‍인';

  @override
  String get swapReviewConfirmSwap => '스‍왑 확‍인';

  @override
  String swapReviewFromAddress(String address) {
    return '보‍내‍는 주‍소: $address';
  }

  @override
  String get swapReviewInsufficientZecSwap =>
      '이 스‍왑‍에 필‍요‍한 ZEC‍가 부‍족‍해‍요. 더 적‍은 금‍액‍으‍로 시‍도‍해 주‍세‍요.';

  @override
  String swapReviewPayAmount(String amount) {
    return '$amount 결‍제';
  }

  @override
  String get swapReviewQuoteExpired =>
      '견‍적‍이 만‍료‍됐‍어‍요. 최‍신 환‍율‍로 다‍시 검‍토‍해 주‍세‍요.';

  @override
  String get swapReviewQuoteHolds => '견‍적 유‍지 시‍간';

  @override
  String get swapReviewQuoteInactive => '이 견‍적‍은 더 이‍상 유‍효‍하‍지 않‍아‍요.';

  @override
  String get swapReviewReturnToSwap => '스‍왑‍으‍로 돌‍아‍가‍기';

  @override
  String get swapReviewReviewAgain => '다‍시 검‍토';

  @override
  String get swapReviewStartingLockingQuote => '견‍적 고‍정 중';

  @override
  String get swapReviewStartingSending => '보‍내‍는 중';

  @override
  String swapReviewToAddress(String address) {
    return '받‍는 주‍소: $address';
  }

  @override
  String get swapSignPayment => '결‍제 서‍명';

  @override
  String get swapSignZecDeposit => 'ZEC 입‍금 서‍명';

  @override
  String get swapSlippageCustom => '직‍접 입‍력';

  @override
  String get swapSlippageDescriptionPay =>
      '견‍적‍이 변‍동‍될 때 실‍행‍이 실‍패‍하‍기 전‍까‍지 이‍만‍큼‍의 추‍가 ZEC‍를 허‍용‍해‍요. 네‍트‍워‍크 수‍수‍료‍는 별‍도‍예‍요.';

  @override
  String get swapSlippageDescriptionSwap =>
      '허‍용‍할 최‍대 환‍율 변‍동‍폭‍을 설‍정‍해‍요. 네‍트‍워‍크 수‍수‍료‍는 별‍도‍예‍요.';

  @override
  String get swapSlippageRangeError => '슬‍리‍피‍지‍는 0.1 - 5%여‍야 해‍요';

  @override
  String get swapSlippageTitle => '슬‍리‍피‍지';

  @override
  String get swapStatusBadgeNeedsAttention => '확‍인 필‍요';

  @override
  String get swapStatusDetailsTab => '거‍래 상‍세';

  @override
  String get swapStatusRowLabel => '상‍태';

  @override
  String get swapTimeoutBody => '새 스‍왑‍을 시‍작‍해 주‍세‍요.';

  @override
  String get swapTimeoutHeadline => '이 입‍금 주‍소‍는 더 이‍상 유‍효‍하‍지 않‍아‍요';

  @override
  String get swapTimeoutRestart => '스‍왑 다‍시 시‍작';

  @override
  String get swapViewOnNearIntents => 'NEAR Intents‍에‍서 보‍기';

  @override
  String syncCheckingPercentSemantics(String percent) {
    return '$percent‍퍼‍센‍트 확‍인 중';
  }

  @override
  String syncCheckingProgress(String percent) {
    return '$percent% 확‍인 중';
  }

  @override
  String get syncConnectingToTor => 'Tor‍에 연‍결‍하‍는 중…';

  @override
  String get syncConnectingToTorSemantics => 'Tor‍에 연‍결‍하‍는 중';

  @override
  String get syncErrorChainRecovery => '체‍인 복‍구';

  @override
  String get syncErrorData => '데‍이‍터 오‍류';

  @override
  String get syncErrorEndpoint => '엔‍드‍포‍인‍트 오‍류';

  @override
  String get syncErrorNetwork => '네‍트‍워‍크 오‍류';

  @override
  String get syncErrorPrivateLookup => '비‍공‍개 조‍회';

  @override
  String get syncErrorUnknown => '알 수 없‍는 오‍류';

  @override
  String get syncErrorWalletData => '지‍갑 데‍이‍터 오‍류';

  @override
  String get syncErrorWalletDataBusy => '지‍갑 데‍이‍터 사‍용 중';

  @override
  String syncFailed(String reason) {
    return '동‍기‍화 실‍패. $reason...';
  }

  @override
  String syncFailedSemantics(String reason) {
    return '동‍기‍화 실‍패. $reason';
  }

  @override
  String get syncFailureChainRecovery =>
      '동‍기‍화 중 체‍인‍이 바‍뀌‍었‍어‍요. 복‍구‍를 계‍속 시‍도‍할‍게‍요.';

  @override
  String get syncFailureDatabaseBusy =>
      '지‍갑 데‍이‍터‍가 사‍용 중‍이‍에‍요. 자‍동‍으‍로 다‍시 동‍기‍화‍할‍게‍요.';

  @override
  String get syncFailureDatabaseFatal =>
      '지‍갑 데‍이‍터‍를 읽‍지 못‍했‍어‍요. 앱‍을 다‍시 시‍작‍한 뒤 동‍기‍화‍를 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get syncFailureEndpoint =>
      '설‍정‍된 Zcash 엔‍드‍포‍인‍트‍에 연‍결‍할 수 없‍어‍요. 엔‍드‍포‍인‍트 설‍정‍을 확‍인‍하‍세‍요.';

  @override
  String get syncFailureNetwork =>
      '네‍트‍워‍크 연‍결‍이 끊‍어‍졌‍어‍요. 자‍동‍으‍로 계‍속 시‍도‍할‍게‍요.';

  @override
  String get syncFailureParse =>
      '동‍기‍화 데‍이‍터‍를 처‍리‍하‍지 못‍했‍어‍요. 동‍기‍화‍를 다‍시 시‍도‍하‍거‍나 엔‍드‍포‍인‍트‍를 확‍인‍하‍세‍요.';

  @override
  String get syncFailurePrivateStatus =>
      '비‍공‍개 거‍래 조‍회‍로 거‍래 상‍태‍를 확‍인‍하‍지 못‍했‍어‍요. 동‍기‍화‍를 계‍속‍하‍려‍면 설‍정‍에‍서 실‍험‍적 비‍공‍개 조‍회‍를 끄‍세‍요.';

  @override
  String get syncFailureTor =>
      'Tor‍에 연‍결‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍거‍나 설‍정‍에‍서 Tor‍를 끄‍세‍요.';

  @override
  String get syncFailureUnknown =>
      '동‍기‍화‍에 실‍패‍했‍어‍요. 계‍속‍하‍려‍면 동‍기‍화‍를 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get syncSynced => '동‍기‍화 완‍료';

  @override
  String syncSyncedAtBlock(String height) {
    return '$height 블‍록‍까‍지 동‍기‍화 완‍료';
  }

  @override
  String syncSyncingPercentSemantics(String percent) {
    return '$percent‍퍼‍센‍트 동‍기‍화 중';
  }

  @override
  String syncSyncingProgress(String percent) {
    return '$percent% 동‍기‍화 중...';
  }

  @override
  String get syncTorFailed => 'Tor‍에 연‍결‍하‍지 못‍했‍어‍요...';

  @override
  String get syncTorFailedSemantics => 'Tor‍에 연‍결‍하‍지 못‍했‍어‍요';

  @override
  String get syncVizorSynced => 'Vizor 동‍기‍화‍됨';

  @override
  String get transparentLedgerNeedsNewerBuild =>
      '이 지‍갑‍의 투‍명 자‍금‍을 사‍용‍하‍려‍면 더 최‍신 버‍전‍의 Vizor‍가 필‍요‍해‍요.';

  @override
  String get transparentRecoveryIncomplete =>
      '비‍공‍개 복‍구‍가 끝‍날 때‍까‍지 투‍명 자‍금‍을 사‍용‍할 수 없‍어‍요.';

  @override
  String get txFeeHelpTooltip =>
      '이 거‍래‍를 처‍리‍하‍도‍록 Zcash 네‍트‍워‍크‍에 내‍는 수‍수‍료‍예‍요.';

  @override
  String get txFeeInfoDescription =>
      '네‍트‍워‍크 수‍수‍료‍는 Zcash 프‍로‍토‍콜(ZIP 317)이 거‍래 크‍기‍에 따‍라 정‍해‍요. Vizor‍는 추‍가 수‍수‍료‍를 받‍지 않‍아‍요.';

  @override
  String get txFeeInfoTitle => '거‍래 수‍수‍료';

  @override
  String get updateFailedMessage =>
      '업‍데‍이‍트‍를 완‍료‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get updateRestart => '다‍시 시‍작';

  @override
  String get votingActionRetryEligibility => '자‍격 다‍시 확‍인';

  @override
  String get votingActionReview => '확‍인';

  @override
  String get votingActionReviewAnswers => '답‍변 확‍인';

  @override
  String get votingActionUnavailable => '사‍용‍할 수 없‍음';

  @override
  String get votingActionViewResults => '결‍과 보‍기';

  @override
  String get votingActive => '투‍표 진‍행 중';

  @override
  String get votingAlreadyUsedNotice =>
      '이 자‍금‍은 이‍미 이‍번 라‍운‍드‍에‍서 사‍용‍됐‍어‍요. 이 기‍기‍에‍서‍는 투‍표‍를 다‍시 시‍작‍할 수 없‍어‍요.';

  @override
  String get votingAutoAdvanceSemantics => '다‍음 미‍응‍답 질‍문‍으‍로 이‍동‍하‍는 중';

  @override
  String get votingBallotCasting => '투‍표‍하‍는 중';

  @override
  String get votingBallotDelivering => '응‍답‍을 전‍달‍하‍는 중';

  @override
  String get votingBallotPreparing => '투‍표‍용‍지‍를 준‍비‍하‍는 중';

  @override
  String get votingBallotWaitingChain => '체‍인 확‍인 대‍기 중';

  @override
  String get votingBetaSemantics => '베‍타';

  @override
  String votingBundleCount(int count) {
    return '투‍표 묶‍음 $count‍개';
  }

  @override
  String votingBundleOf(int number, int total) {
    return '$total‍개 중 $number‍번‍째 묶‍음';
  }

  @override
  String votingChoiceFallback(int number) {
    return '선‍택 $number';
  }

  @override
  String get votingConfigAddCustomSource => '사‍용‍자 지‍정 소‍스 추‍가';

  @override
  String get votingConfigChecksumFormat => 'checksum‍은 소‍문‍자 hex 64‍자‍여‍야 해‍요.';

  @override
  String get votingConfigChecksumKeyEncoded =>
      'checksum 매‍개‍변‍수 이‍름‍은 인‍코‍딩‍하‍지 말‍고 checksum‍으‍로 써 주‍세‍요.';

  @override
  String get votingConfigChecksumPrefix => 'checksum‍은 sha256:으‍로 시‍작‍해‍야 해‍요.';

  @override
  String get votingConfigChecksumRepeated =>
      'checksum 매‍개‍변‍수‍는 한 번‍만 넣‍어 주‍세‍요.';

  @override
  String get votingConfigChecksumRequired =>
      'URL‍에 checksum 매‍개‍변‍수‍를 추‍가‍해 주‍세‍요.';

  @override
  String get votingConfigCloseSettings => '투‍표 설‍정 닫‍기';

  @override
  String get votingConfigCopyUrl => '소‍스 URL 복‍사';

  @override
  String get votingConfigCustomSource => '사‍용‍자 지‍정 소‍스';

  @override
  String votingConfigDeleteNamed(String name) {
    return '$name 삭‍제';
  }

  @override
  String get votingConfigDeleteSaved => '저‍장‍된 소‍스 삭‍제';

  @override
  String get votingConfigDuplicate => '이‍미 추‍가‍된 소‍스 URL‍이‍에‍요.';

  @override
  String get votingConfigEditCustomSource => '사‍용‍자 지‍정 소‍스 편‍집';

  @override
  String votingConfigEditNamed(String name) {
    return '$name 편‍집';
  }

  @override
  String get votingConfigEditSaved => '저‍장‍된 소‍스 편‍집';

  @override
  String get votingConfigEnterTitleAndUrl => '제‍목‍과 소‍스 URL‍을 입‍력‍해 주‍세‍요.';

  @override
  String get votingConfigFieldStaticUrl => '정‍적 설‍정 URL';

  @override
  String get votingConfigFieldTitle => '제‍목';

  @override
  String get votingConfigLoadFailed => '해‍당 소‍스‍에‍서 투‍표 설‍정‍을 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get votingConfigMobileFieldUrl => '소‍스 URL';

  @override
  String get votingConfigMobileIntro =>
      'Vizor‍가 인‍증‍된 투‍표 라‍운‍드‍를 가‍져‍올 곳‍을 선‍택‍해 주‍세‍요.';

  @override
  String get votingConfigMobileSave => '소‍스 저‍장';

  @override
  String get votingConfigMobileTestRoundsHint =>
      '[TEST]로 표‍시‍된 인‍증‍된 라‍운‍드‍를 포‍함‍해‍요.';

  @override
  String get votingConfigMobileTitle => '투‍표 설‍정';

  @override
  String get votingConfigMobileUpdateFailed =>
      '투‍표 설‍정‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 소‍스‍를 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingConfigSaving => '저‍장 중...';

  @override
  String get votingConfigSettings => '투‍표 설‍정 열‍기';

  @override
  String get votingConfigSettingsLoadFailed => '투‍표 설‍정‍을 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get votingConfigShowTestRounds => '테‍스‍트 라‍운‍드 표‍시';

  @override
  String get votingConfigShowTestRoundsHint =>
      '제‍목‍이 [TEST]로 시‍작‍하‍는 인‍증‍된 라‍운‍드‍를 표‍시‍해‍요.';

  @override
  String get votingConfigSources => '소‍스';

  @override
  String get votingConfigTestVisibilityFailed =>
      '테‍스‍트 라‍운‍드 표‍시 설‍정‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String votingConfigTitleTooLong(int max) {
    return '제‍목‍은 $max‍자 이‍하‍여‍야 해‍요.';
  }

  @override
  String get votingConfigTooltip => '투‍표 설‍정';

  @override
  String get votingConfigUpdateFailed => '투‍표 설‍정‍을 업‍데‍이‍트‍하‍지 못‍했‍어‍요.';

  @override
  String get votingConfigUrlCopied => '소‍스 URL‍을 복‍사‍했‍어‍요.';

  @override
  String get votingConfigUrlHasFragment => 'URL‍에 프‍래‍그‍먼‍트(#…)를 넣‍을 수 없‍어‍요.';

  @override
  String get votingConfigUrlHasUserInfo =>
      'URL‍에 사‍용‍자 이‍름‍이‍나 비‍밀‍번‍호‍를 넣‍을 수 없‍어‍요.';

  @override
  String get votingConfigUrlNotHttps => 'HTTPS URL‍을 입‍력‍해 주‍세‍요.';

  @override
  String get votingConfigValidating => '확‍인 중...';

  @override
  String get votingConfirmationCheckingEligibility =>
      '이 계‍정‍의 투‍표 자‍격‍을 확‍인‍하‍는 중‍이‍에‍요.';

  @override
  String get votingConfirmationConfirmedBody =>
      '투‍표‍가 성‍공‍적‍으‍로 게‍시‍됐‍고 변‍경‍할 수 없‍어‍요.';

  @override
  String get votingConfirmationConfirmedTitle => '제‍출‍이 확‍인‍됐‍어‍요!';

  @override
  String get votingConfirmationEligibilityUnconfirmed =>
      '이 계‍정‍의 투‍표 자‍격‍이 확‍인‍되‍지 않‍았‍어‍요.';

  @override
  String get votingConfirmationIncompleteTitle => '제‍출‍이 완‍료‍되‍지 않‍았‍어‍요';

  @override
  String votingConfirmationLoadFailed(String error) {
    return '제‍출 내‍역‍을 불‍러‍오‍지 못‍했‍어‍요: $error';
  }

  @override
  String get votingConfirmationNotCompleted =>
      '이 계‍정‍은 이‍번 투‍표 라‍운‍드‍의 제‍출‍을 완‍료‍하‍지 않‍았‍어‍요.';

  @override
  String get votingConfirmationUpdateFailed =>
      '투‍표 라‍운‍드‍를 업‍데‍이‍트‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingConfirmationUpdatingRounds => '투‍표 라‍운‍드‍를 업‍데‍이‍트‍하‍는 중...';

  @override
  String get votingContinueVoting => '투‍표 이‍어‍하‍기';

  @override
  String votingDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days‍일 남‍음',
      zero: '오‍늘 종‍료',
    );
    return '$_temp0';
  }

  @override
  String get votingDetailLoadFailedTitle => '투‍표 라‍운‍드‍를 불‍러‍오‍지 못‍했‍어‍요';

  @override
  String get votingDetailUnavailableBody =>
      '선‍택‍한 투‍표 라‍운‍드‍를 불‍러‍오‍지 못‍했‍어‍요.';

  @override
  String get votingDetailUnavailableTitle => '투‍표 라‍운‍드‍를 사‍용‍할 수 없‍어‍요';

  @override
  String votingEnds(String date) {
    return '$date 종‍료';
  }

  @override
  String get votingErrorChainCancelled => '체‍인 제‍출‍이 취‍소‍됐‍어‍요.';

  @override
  String get votingErrorChainNoUsableTransaction =>
      '체‍인 제‍출‍이 사‍용‍할 수 있‍는 거‍래 없‍이 끝‍났‍어‍요.';

  @override
  String get votingErrorChainRecoveryPending =>
      '체‍인 제‍출 복‍구‍가 아‍직 진‍행 중‍이‍에‍요.';

  @override
  String get votingErrorChainRejected => '체‍인‍에‍서 제‍출‍을 거‍부‍했‍어‍요.';

  @override
  String get votingErrorChainSubmittedWithoutHash =>
      '제‍출‍이 체‍인‍에 도‍달‍했‍을 수 있‍지‍만 거‍래 해‍시‍를 받‍지 못‍했‍어‍요. 다‍시 시‍도‍하‍지 마‍세‍요.';

  @override
  String votingErrorDelegationFailed(String details) {
    return '위‍임 묶‍음‍을 처‍리‍하‍지 못‍했‍어‍요: $details';
  }

  @override
  String get votingErrorHotkeyMissing =>
      '투‍표 핫‍키‍가 없‍어‍요. 투‍표‍하‍기 전‍에 이 라‍운‍드‍를 위‍임‍해 주‍세‍요.';

  @override
  String get votingErrorImmediateShareExpired =>
      '헬‍퍼‍가 즉‍시 전‍송‍된 투‍표 데‍이‍터‍를 확‍인‍하‍기 전‍에 투‍표 라‍운‍드‍가 끝‍났‍어‍요. 다‍시 시‍도‍하‍기 전‍에 투‍표 상‍태‍를 확‍인‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneAccountOnly =>
      'Keystone 투‍표‍는 Keystone 계‍정‍에‍서‍만 할 수 있‍어‍요.';

  @override
  String get votingErrorKeystoneHardwareOnly =>
      'Keystone 투‍표‍는 하‍드‍웨‍어 지‍갑 계‍정‍에‍서‍만 할 수 있‍어‍요.';

  @override
  String get votingErrorKeystoneInvalidSignature =>
      'Keystone‍에‍서 받‍은 투‍표 서‍명‍이 올‍바‍르‍지 않‍아‍요. 여‍기 표‍시‍된 QR‍에 대‍한 결‍과‍를 스‍캔‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneNoSignatures =>
      'Keystone‍에‍서 투‍표 서‍명‍을 받‍지 못‍했‍어‍요. 결‍과‍를 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneNoSigningRequest =>
      '서‍명‍을 기‍다‍리‍는 Keystone 서‍명 요‍청‍이 없‍어‍요.';

  @override
  String votingErrorKeystoneQrPrepareFailed(String reason) {
    return 'Keystone 투‍표 QR‍을 준‍비‍하‍지 못‍했‍어‍요: $reason';
  }

  @override
  String get votingErrorKeystoneResultMismatch =>
      '이 Keystone 결‍과‍가 여‍기 표‍시‍된 투‍표 QR‍과 일‍치‍하‍지 않‍아‍요. 일‍치‍하‍는 결‍과‍를 스‍캔‍한 뒤 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneSignatureConflict =>
      '이 Keystone 결‍과‍가 이 투‍표 요‍청‍에 이‍미 저‍장‍된 서‍명‍과 충‍돌‍해‍요. Keystone 서‍명‍을 다‍시 시‍작‍하‍고 새‍로 생‍성‍된 결‍과‍를 스‍캔‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneSignatureMismatch =>
      'Keystone‍에‍서 받‍은 서‍명‍이 이 투‍표 요‍청‍과 일‍치‍하‍지 않‍아‍요. 여‍기 표‍시‍된 QR‍에 대‍한 결‍과‍를 스‍캔‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneSignatureSaveFailed =>
      'Keystone 서‍명‍을 저‍장‍하‍지 못‍했‍어‍요. 같‍은 Keystone 결‍과‍를 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String get votingErrorKeystoneSkipNeedsSignature =>
      '나‍머‍지‍를 건‍너‍뛰‍기 전‍에 Keystone 묶‍음‍에 하‍나 이‍상 서‍명‍해 주‍세‍요.';

  @override
  String get votingErrorLedgerCancelled => 'Ledger‍에‍서 투‍표 승‍인‍을 취‍소‍했‍어‍요.';

  @override
  String votingErrorLedgerLocked(String instruction) {
    return 'Ledger‍의 잠‍금‍을 해‍제‍해 주‍세‍요. $instruction';
  }

  @override
  String get votingErrorLedgerNoPendingBundle =>
      '승‍인‍을 기‍다‍리‍는 Ledger 투‍표 묶‍음‍이 없‍어‍요.';

  @override
  String get votingErrorLedgerRejected =>
      'Ledger‍에‍서 투‍표 서‍명‍을 거‍부‍했‍어‍요. 다‍시 시‍도‍해 서‍명‍해 주‍세‍요.';

  @override
  String get votingErrorLedgerSignatureConflict =>
      '이 Ledger 서‍명‍이 이 투‍표 묶‍음‍에 이‍미 저‍장‍된 서‍명‍과 충‍돌‍해‍요.';

  @override
  String get votingErrorLedgerSignatureMismatch =>
      'Ledger‍에‍서 받‍은 서‍명‍이 이 투‍표‍와 일‍치‍하‍지 않‍아‍요. 다‍시 시‍도‍해 서‍명‍해 주‍세‍요.';

  @override
  String get votingErrorLedgerSignatureSaveFailed =>
      'Ledger 투‍표 서‍명‍을 저‍장‍하‍지 못‍했‍어‍요. 이 묶‍음‍을 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String votingErrorLedgerWrongApp(String instruction) {
    return '$instruction 그‍런 다‍음 다‍시 시‍도‍해 주‍세‍요.';
  }

  @override
  String votingErrorMinimumWeight(String amount, String snapshot) {
    return '투‍표‍하‍려‍면 $snapshot‍에 $amount 이‍상‍의 자‍격 있‍는 차‍폐 노‍트 묶‍음‍이 하‍나 이‍상 필‍요‍해‍요. 자‍격‍이 있‍는 계‍정‍으‍로 전‍환‍해 투‍표‍해 주‍세‍요.';
  }

  @override
  String votingErrorMinimumWeightReason(String amount, String snapshot) {
    return '투‍표‍하‍려‍면 $snapshot‍에 $amount 이‍상‍의 자‍격 있‍는 차‍폐 노‍트 묶‍음‍이 하‍나 이‍상 필‍요‍해‍요';
  }

  @override
  String get votingErrorNoActiveAccount => '투‍표‍에 사‍용‍할 계‍정‍이 선‍택‍되‍지 않‍았‍어‍요.';

  @override
  String votingErrorNoSpendableNotes(String snapshot) {
    return '이 계‍정‍은 이‍번 투‍표 라‍운‍드‍에 참‍여‍할 수 없‍어‍요. $snapshot‍에 투‍표 자‍격‍이 있‍는 차‍폐 자‍금‍이 없‍었‍어‍요. 자‍격‍이 있‍는 계‍정‍으‍로 전‍환‍해 투‍표‍해 주‍세‍요.';
  }

  @override
  String votingErrorNoSpendableNotesReason(String snapshot) {
    return '이 계‍정‍은 이‍번 투‍표 라‍운‍드‍에 참‍여‍할 수 없‍어‍요. $snapshot‍에 투‍표 자‍격‍이 있‍는 차‍폐 자‍금‍이 없‍었‍어‍요';
  }

  @override
  String get votingErrorNoVoteChosen => '제‍출‍하‍기 전‍에 하‍나 이‍상 투‍표‍해 주‍세‍요.';

  @override
  String get votingErrorPirEndpointResolveFailed =>
      'PIR 엔‍드‍포‍인‍트‍를 확‍인‍하‍지 못‍했‍어‍요.';

  @override
  String get votingErrorPirEndpointUnresolved =>
      'PIR 엔‍드‍포‍인‍트‍를 아‍직 확‍인‍하‍지 못‍했‍어‍요.';

  @override
  String get votingErrorRoundDetailsUnavailable =>
      '투‍표 라‍운‍드 정‍보‍를 아‍직 불‍러‍오‍지 못‍했‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingErrorRoundEndTimeUnavailable =>
      '투‍표 라‍운‍드 종‍료 시‍간‍을 알 수 없‍어‍요. 잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingErrorSessionFailed => '투‍표 작‍업‍에 실‍패‍했‍어‍요.';

  @override
  String votingErrorSignBundleFirst(int bundle, String signer) {
    return '제‍출‍하‍기 전‍에 $signer 기‍기‍에‍서 위‍임 묶‍음 $bundle‍에 서‍명‍해 주‍세‍요.';
  }

  @override
  String votingErrorSignBundlesFirst(String signer) {
    return '제‍출‍하‍기 전‍에 $signer 기‍기‍에‍서 위‍임 묶‍음‍에 서‍명‍해 주‍세‍요.';
  }

  @override
  String votingErrorSignerAccountOnly(String signer) {
    return '$signer 투‍표‍는 해‍당 하‍드‍웨‍어 지‍갑 계‍정‍에‍서‍만 할 수 있‍어‍요.';
  }

  @override
  String get votingErrorSoftwareMnemonicRequired =>
      '소‍프‍트‍웨‍어 위‍임‍에‍는 이 계‍정‍의 복‍구 문‍구‍가 필‍요‍해‍요. 이 계‍정‍을 잠‍금 해‍제‍하‍거‍나 복‍구 문‍구‍에 접‍근‍할 수 있‍는 계‍정‍으‍로 전‍환‍해 주‍세‍요.';

  @override
  String votingErrorVoteCastingFailed(String details) {
    return '투‍표‍하‍지 못‍했‍어‍요: $details';
  }

  @override
  String votingErrorWalletSyncTimeout(
    String duration,
    String scanned,
    String snapshot,
  ) {
    return '지‍갑 동‍기‍화‍가 $duration 안‍에 이 투‍표 라‍운‍드 스‍냅‍샷‍에 도‍달‍하‍지 못‍했‍어‍요. $snapshot 블‍록 중 $scanned 블‍록‍까‍지 스‍캔‍했‍어‍요. 지‍갑 동‍기‍화‍가 따‍라‍잡‍을 때‍까‍지 기‍다‍린 뒤 다‍시 시‍도‍해 주‍세‍요.';
  }

  @override
  String get votingForumDiscussion => '포‍럼 토‍론';

  @override
  String get votingGuardAccountLoadFailed => '계‍정‍을 불‍러‍오‍지 못‍했‍어‍요';

  @override
  String get votingIneligibleTitle => '이‍번 투‍표 라‍운‍드‍에 참‍여‍할 수 없‍어‍요';

  @override
  String get votingKeepSigning => '계‍속 서‍명';

  @override
  String get votingKeepVoting => '계‍속 투‍표';

  @override
  String votingKeystoneMemoLabel(int number, int total) {
    return '$total‍개 중 $number‍번‍째 묶‍음 메‍모';
  }

  @override
  String get votingKeystoneNextBatch => '다‍음 서‍명 묶‍음‍이 준‍비‍됐‍어‍요';

  @override
  String get votingKeystoneNextMemo => '다‍음 묶‍음 메‍모';

  @override
  String get votingKeystoneOneApproval => 'Keystone 승‍인 한 번';

  @override
  String get votingKeystonePreviousMemo => '이‍전 묶‍음 메‍모';

  @override
  String votingKeystoneQrPartial(int count, int total) {
    return '이 QR‍로 남‍은 $total‍개 묶‍음 중 $count‍개‍에 서‍명‍해‍요';
  }

  @override
  String get votingKeystoneScanInstruction =>
      'Keystone‍으‍로 이 화‍면‍의 QR‍을 스‍캔‍하‍세‍요. 그‍런 다‍음 Keystone‍에 표‍시‍된 서‍명‍된 투‍표 QR‍을 이 기‍기‍의 카‍메‍라‍로 스‍캔‍하‍세‍요';

  @override
  String get votingKeystoneScanSignature => '서‍명 스‍캔';

  @override
  String votingKeystoneSignLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '투‍표 묶‍음 $count‍개 서‍명',
      zero: '투‍표 서‍명 준‍비 중',
    );
    return '$_temp0';
  }

  @override
  String get votingKeystoneUnexpectedUr =>
      'Keystone‍에‍서 서‍명‍된 투‍표 QR‍을 열‍고 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String get votingLedgerApprovalNotice =>
      'Ledger‍에‍서 승‍인‍하‍면 이 투‍표 위‍임‍이 승‍인‍돼‍요. 계‍속‍하‍기 전‍에 Vizor‍에‍서 아‍래 메‍모‍를 확‍인‍해 주‍세‍요. 기‍기‍에‍는 이 메‍모‍가 그‍대‍로 표‍시‍되‍지 않‍을 수 있‍어‍요.';

  @override
  String get votingLedgerConfirmOpenBody =>
      'Ledger‍에‍서 Zcash 앱‍을 열‍라‍는 요‍청‍을 승‍인‍해 주‍세‍요.';

  @override
  String get votingLedgerFinishing => '투‍표 위‍임 마‍무‍리 중';

  @override
  String get votingLedgerPanelTitle => '투‍표 위‍임';

  @override
  String get votingLedgerPleaseWait =>
      'Vizor‍가 요‍청‍을 준‍비‍하‍는 동‍안 잠‍시 기‍다‍려 주‍세‍요.';

  @override
  String get votingLedgerPreparing => '투‍표 위‍임 준‍비 중';

  @override
  String get votingLedgerReconnect => 'Ledger‍를 다‍시 연‍결‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingLoadFailedRetry => '잠‍시 후 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String votingMobileAccountLoadFailed(String error) {
    return '계‍정‍을 불‍러‍오‍지 못‍했‍어‍요.\n$error';
  }

  @override
  String get votingMobileHeaderTitle => '투‍표';

  @override
  String get votingMobileKeystoneChecking => '투‍표 서‍명‍을 확‍인‍하‍는 중...';

  @override
  String get votingMobileKeystoneDescription =>
      'Keystone‍으‍로 투‍표 요‍청‍을 스‍캔‍해 승‍인‍한 다‍음, 서‍명‍된 결‍과‍를 이 기‍기‍로 스‍캔‍해 주‍세‍요.';

  @override
  String get votingMobileKeystoneFailedTitle => '투‍표 서‍명‍에 실‍패‍했‍어‍요';

  @override
  String get votingMobileKeystoneNextBundle => '다‍음 투‍표 묶‍음';

  @override
  String get votingMobileKeystonePreviousBundle => '이‍전 투‍표 묶‍음';

  @override
  String get votingMobileKeystoneReading => '투‍표 서‍명‍을 읽‍는 중...';

  @override
  String get votingMobileKeystoneScanCaption =>
      'Keystone‍에 표‍시‍된 서‍명‍된 투‍표 QR‍을 스‍캔‍하‍세‍요';

  @override
  String get votingMobileKeystoneSkipUnsigned => '서‍명‍하‍지 않‍은 묶‍음 건‍너‍뛰‍기';

  @override
  String get votingMobileKeystoneTitle => 'Keystone‍으‍로 투‍표 서‍명';

  @override
  String get votingMobileLeaveWarning => '이 화‍면‍을 벗‍어‍나‍지 마‍세‍요.';

  @override
  String get votingMobileProgressSemantics => '현‍재 투‍표 제‍출 단‍계 진‍행‍률';

  @override
  String get votingMobileProofNotice =>
      '영‍지‍식 증‍명‍을 생‍성‍하‍는 데 약 60‍초‍가 걸‍릴 수 있‍으‍며, 지‍금 닫‍으‍면 진‍행 중‍인 증‍명 작‍업‍이 사‍라‍질 수 있‍어‍요.';

  @override
  String get votingMobileSubmitTitle => '투‍표 제‍출';

  @override
  String get votingMobileSubmittedBody => '투‍표‍를 제‍출‍했‍고 변‍경‍할 수 없‍어‍요.';

  @override
  String get votingMobileSubmittedTitle => '투‍표 제‍출 완‍료';

  @override
  String get votingMobileSubmittingTitle => '투‍표‍를 제‍출‍하‍는 중...';

  @override
  String get votingNavAllAnswered => '모‍든 질‍문‍에 답‍했‍어‍요';

  @override
  String votingNavAnsweredProgress(int answered, int total) {
    return '$total‍개 중 $answered‍개 답‍변';
  }

  @override
  String get votingNavReadyToReview => '답‍변‍을 확‍인‍할 준‍비‍가 됐‍어‍요.';

  @override
  String get votingNavTapToJump => '질‍문‍을 탭‍하‍면 해‍당 질‍문‍으‍로 이‍동‍해‍요.';

  @override
  String votingNavUnansweredCount(int count) {
    return '미‍응‍답 · $count';
  }

  @override
  String get votingNavUnansweredMenu => '미‍응‍답 질‍문';

  @override
  String get votingNoProposalsBody => '이 투‍표 라‍운‍드‍에‍는 안‍건‍이 없‍어‍요.';

  @override
  String get votingNoProposalsTitle => '안‍건‍이 없‍어‍요';

  @override
  String get votingNotAvailable => '사‍용‍할 수 없‍음';

  @override
  String get votingNotEligible => '참‍여‍할 수 없‍음';

  @override
  String get votingOptionChoose => '선‍택';

  @override
  String get votingOptionSelected => '선‍택‍됨';

  @override
  String get votingPendingBody =>
      '이‍번 라‍운‍드‍에‍서 끝‍내‍지 못‍한 투‍표‍가 있‍어‍요. 이‍어‍서 제‍출‍을 완‍료‍해 주‍세‍요.';

  @override
  String get votingPendingTitle => '투‍표 진‍행 중';

  @override
  String votingPirAhead(String expected, String reported) {
    return '설‍정‍된 PIR 엔‍드‍포‍인‍트‍가 이 투‍표 라‍운‍드 스‍냅‍샷‍보‍다 앞‍서 있‍어‍요. 예‍상 스‍냅‍샷 블‍록: $expected, 엔‍드‍포‍인‍트 보‍고 블‍록: $reported.';
  }

  @override
  String votingPirBehind(String expected, String reported) {
    return '이 투‍표 라‍운‍드‍의 PIR 데‍이‍터‍가 아‍직 준‍비‍되‍지 않‍았‍어‍요. 예‍상 스‍냅‍샷 블‍록: $expected, PIR 엔‍드‍포‍인‍트 보‍고 블‍록: $reported. PIR 서‍비‍스‍가 따‍라‍잡‍으‍면 다‍시 시‍도‍해 주‍세‍요.';
  }

  @override
  String votingPirNoMatch(String expected) {
    return '이 투‍표 라‍운‍드 스‍냅‍샷‍과 일‍치‍하‍는 PIR 엔‍드‍포‍인‍트‍가 없‍어‍요. 예‍상 스‍냅‍샷 블‍록: $expected.';
  }

  @override
  String votingPirNoMatchDiagnostics(String expected, String diagnostics) {
    return '이 투‍표 라‍운‍드 스‍냅‍샷‍과 일‍치‍하‍는 PIR 엔‍드‍포‍인‍트‍가 없‍어‍요. 예‍상 스‍냅‍샷 블‍록: $expected. 진‍단 정‍보: $diagnostics.';
  }

  @override
  String get votingPirUnreachable =>
      '설‍정‍된 PIR 엔‍드‍포‍인‍트‍에 연‍결‍하‍지 못‍했‍어‍요. 네‍트‍워‍크 연‍결‍을 확‍인‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingPollAlreadyUsed => '이‍번 라‍운‍드‍에‍서 이‍미 사‍용‍했‍어‍요';

  @override
  String votingPollClosed(String date) {
    return '$date 마‍감‍됨';
  }

  @override
  String votingPollCloses(String date) {
    return '$date 마‍감';
  }

  @override
  String get votingPollNotEligible => '이‍번 라‍운‍드‍에 참‍여‍할 수 없‍어‍요';

  @override
  String votingPollStarts(String date) {
    return '$date 시‍작';
  }

  @override
  String get votingPollsEmptyBody => '아‍직 표‍시‍할 토‍큰 보‍유‍자 투‍표 라‍운‍드‍가 없‍어‍요.';

  @override
  String get votingPollsEmptyTitle => '사‍용‍할 수 있‍는 투‍표 라‍운‍드‍가 없‍어‍요';

  @override
  String get votingPollsLoadFailedTitle => '투‍표 라‍운‍드‍를 불‍러‍오‍지 못‍했‍어‍요';

  @override
  String votingPowerMeta(String amount) {
    return '투‍표‍권 $amount';
  }

  @override
  String get votingPowerUnavailableSentence => '투‍표‍권‍을 확‍인‍할 수 없‍어‍요.';

  @override
  String get votingPowerUnavailableTitle => '투‍표‍권‍을 확‍인‍할 수 없‍어‍요';

  @override
  String get votingPreparingPower => '투‍표‍권‍을 준‍비‍하‍는 중‍이‍에‍요.';

  @override
  String get votingPreparingPowerMeta => '투‍표‍권 준‍비 중';

  @override
  String votingPrivacyTrimNotice(String amount) {
    return '제‍출‍한 투‍표‍가 덜 식‍별‍되‍도‍록 $amount‍만‍큼‍은 이‍번 투‍표‍에‍서 제‍외‍돼‍요.';
  }

  @override
  String votingProgressBundlesProved(int proved, int total) {
    return '$total‍개 중 $proved‍개 묶‍음 증‍명 완‍료';
  }

  @override
  String votingProgressFinalizingDelegation(String suffix) {
    return '위‍임 마‍무‍리 중‍$suffix';
  }

  @override
  String votingProgressReusingProof(String suffix) {
    return '진‍행 중‍인 증‍명‍을 재‍사‍용‍하‍는 중‍$suffix';
  }

  @override
  String votingProgressWaitingConfirmation(String suffix) {
    return '제‍출 및 확‍인 대‍기 중‍$suffix';
  }

  @override
  String get votingReceiptPower => '투‍표‍권';

  @override
  String votingRemainingBundles(int count, int total) {
    return '남‍은 $total‍개 묶‍음 중 $count‍개';
  }

  @override
  String get votingResultsFallbackTitle => '투‍표 결‍과';

  @override
  String get votingResultsHideDescription => '설‍명 숨‍기‍기';

  @override
  String votingResultsLoadFailed(String error) {
    return '결‍과‍를 불‍러‍오‍지 못‍했‍어‍요: $error';
  }

  @override
  String get votingResultsNoProposals => '이‍번 라‍운‍드‍에‍는 안‍건‍이 없‍어‍요.';

  @override
  String get votingResultsPending => '결‍과 집‍계 대‍기 중...';

  @override
  String votingResultsRoundLoadFailed(String error) {
    return '투‍표 라‍운‍드 정‍보‍를 불‍러‍오‍지 못‍했‍어‍요: $error';
  }

  @override
  String get votingResultsShowDescription => '설‍명 보‍기';

  @override
  String votingResultsTotalAmount(String amount) {
    return '합‍계: $amount';
  }

  @override
  String votingResultsVotedFor(String choice) {
    return '투‍표: $choice';
  }

  @override
  String get votingResultsWinner => '최‍다 득‍표';

  @override
  String get votingResultsYourVote => '내 투‍표';

  @override
  String get votingReviewChooseOne => '제‍출‍하‍기 전‍에 하‍나 이‍상 선‍택‍해 주‍세‍요.';

  @override
  String get votingReviewConfirmSubmit => '확‍인‍하‍고 제‍출';

  @override
  String votingReviewLoadFailed(String error) {
    return '검‍토 화‍면‍을 불‍러‍오‍지 못‍했‍어‍요: $error';
  }

  @override
  String get votingReviewSkipped => '건‍너‍뜀';

  @override
  String get votingReviewTitle => '답‍변 확‍인';

  @override
  String get votingScanHold => 'Keystone QR 코‍드‍를 카‍메‍라 앞‍에 고‍정‍해 주‍세‍요';

  @override
  String get votingScanNoCamera =>
      'Keystone 투‍표‍는 카‍메‍라 QR 스‍캔‍만 지‍원‍해‍요. 카‍메‍라‍를 연‍결‍하‍고 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get votingScanTitle => '투‍표 서‍명 스‍캔';

  @override
  String get votingSignedOnlyBody =>
      'Vizor‍는 Keystone‍에‍서 이‍미 스‍캔‍한 서‍명‍만‍으‍로 지‍금 제‍출‍할 수 있‍어‍요.';

  @override
  String get votingSignedOnlyTitle => '서‍명‍한 묶‍음‍만 사‍용‍할‍까‍요?';

  @override
  String get votingSignedOnlyWarning =>
      '서‍명‍하‍지 않‍은 묶‍음‍은 건‍너‍뛰‍어‍서 이‍번 투‍표 라‍운‍드‍의 투‍표‍권‍이 줄‍어‍들‍어‍요.';

  @override
  String get votingSkip => '건‍너‍뛰‍기';

  @override
  String get votingSkipBundles => '묶‍음 건‍너‍뛰‍기';

  @override
  String votingSkipDialogBody(int skipped, int total) {
    return '$total‍개 질‍문 중 $skipped‍개‍에 답‍하‍지 않‍았‍어‍요. 확‍인 화‍면‍에‍서 건‍너‍뜀‍으‍로 표‍시‍되‍며, 건‍너‍뛴 질‍문‍은 제‍출‍되‍지 않‍아‍요.';
  }

  @override
  String get votingSkipDialogTitle => '답‍하‍지 않‍은 질‍문‍을 건‍너‍뛸‍까‍요?';

  @override
  String votingSnapshotBlock(String height) {
    return '스‍냅‍샷 블‍록 $height';
  }

  @override
  String get votingSnapshotUnknown => '투‍표 라‍운‍드 스‍냅‍샷 블‍록';

  @override
  String get votingSoftwareRequiredBody =>
      '토‍큰 보‍유‍자 투‍표‍에‍는 소‍프‍트‍웨‍어 계‍정‍이 필‍요‍해‍요. 이‍번 라‍운‍드‍에‍서 투‍표‍하‍려‍면 소‍프‍트‍웨‍어 계‍정‍으‍로 전‍환‍해 주‍세‍요.';

  @override
  String get votingSoftwareRequiredTitle => '소‍프‍트‍웨‍어 계‍정‍이 필‍요‍해‍요';

  @override
  String get votingStatusActive => '진‍행 중';

  @override
  String get votingStatusBodyKeepOpen =>
      '창‍을 닫‍지 마‍세‍요. 영‍지‍식 증‍명‍을 생‍성‍하‍는 데 시‍간‍이 걸‍릴 수 있‍으‍며, 지‍금 닫‍으‍면 진‍행 중‍인 증‍명 작‍업‍이 사‍라‍질 수 있‍어‍요.';

  @override
  String get votingStatusBodyLedger =>
      'Vizor‍를 열‍어 둔 채‍로 아‍래 안‍내‍에 따‍라 각 투‍표 묶‍음‍을 처‍리‍해 주‍세‍요.';

  @override
  String get votingStatusClosed => '마‍감‍됨';

  @override
  String get votingStatusFailed => '투‍표‍에 실‍패‍했‍어‍요.';

  @override
  String get votingStatusGenericError =>
      '이 계‍정‍으‍로 투‍표‍를 계‍속‍할 수 없‍어‍요. 다‍시 시‍도‍하‍거‍나, 이 계‍정‍이 이‍번 투‍표 라‍운‍드‍에 참‍여‍할 수 없‍다‍면 자‍격‍이 있‍는 계‍정‍으‍로 전‍환‍해 주‍세‍요.';

  @override
  String get votingStatusTallying => '집‍계 중';

  @override
  String get votingStatusTitleLedger => 'Ledger‍로 투‍표';

  @override
  String get votingStatusTitleSubmitting => '투‍표 제‍출 중';

  @override
  String get votingStatusVoted => '투‍표 완‍료';

  @override
  String get votingStepCasting => '투‍표‍하‍고 투‍표 데‍이‍터‍를 제‍출‍하‍는 중';

  @override
  String get votingStepFinalizing => '제‍출 마‍무‍리 중';

  @override
  String get votingStepProving => '투‍표 권‍한 증‍명 중';

  @override
  String get votingStepSigningKeystone => 'Keystone‍으‍로 서‍명 중';

  @override
  String get votingStepSigningLedger => 'Ledger‍로 서‍명 중';

  @override
  String get votingSubmissionInProgress =>
      '투‍표 제‍출‍이 아‍직 진‍행 중‍이‍에‍요. 계‍정‍을 삭‍제‍하‍거‍나 지‍갑‍을 초‍기‍화‍하‍기 전‍에 제‍출‍이 끝‍날 때‍까‍지 기‍다‍려 주‍세‍요.';

  @override
  String get votingSwitchAccount => '계‍정 전‍환';

  @override
  String get votingSwitchEligibleGuidance =>
      '자‍격‍이 있‍는 계‍정‍으‍로 전‍환‍해 투‍표‍해 주‍세‍요.';

  @override
  String votingSyncBlocksRemaining(int count) {
    return '$count 블‍록 남‍음';
  }

  @override
  String votingSyncChainTip(int height) {
    return '체‍인 최‍신 블‍록 $height';
  }

  @override
  String votingSyncSynced(int height) {
    return '블‍록 $height‍까‍지 동‍기‍화‍됨';
  }

  @override
  String get votingSyncWaitingBody =>
      '지‍갑‍이 이‍번 투‍표 라‍운‍드 스‍냅‍샷‍을 따‍라‍잡‍는 중‍이‍에‍요. 지‍갑‍이 스‍냅‍샷 블‍록‍까‍지 동‍기‍화‍되‍면 투‍표‍가 자‍동‍으‍로 이‍어‍져‍요.';

  @override
  String votingTerminalBundle(int number, String reason) {
    return '$number‍번 묶‍음($reason)';
  }

  @override
  String votingTerminalMultiple(String bundles) {
    return '$bundles‍의 위‍임‍은 계‍속‍할 수 없‍어‍요. 거‍래‍가 이‍미 체‍인‍에 있‍을 수 있‍으‍니 다‍시 시‍도‍하‍지 마‍세‍요.';
  }

  @override
  String get votingTerminalReasonDefault => '확‍인 없‍이 종‍료‍됨';

  @override
  String votingTerminalSingle(String bundle) {
    return '위‍임 $bundle‍은 계‍속‍할 수 없‍어‍요. 거‍래‍가 이‍미 체‍인‍에 있‍을 수 있‍으‍니 다‍시 시‍도‍하‍지 마‍세‍요.';
  }

  @override
  String get votingTokenHolderTitle => '토‍큰 보‍유‍자 투‍표';

  @override
  String get votingViewLess => '간‍단‍히 보‍기';

  @override
  String get votingViewMore => '더 보‍기';

  @override
  String get votingVoteLocked => '투‍표 확‍정‍됨';

  @override
  String votingVotedOn(String date) {
    return '$date 투‍표';
  }

  @override
  String walletLinkAccountsFound(int count) {
    return '계‍정 $count‍개‍를 찾‍았‍어‍요';
  }

  @override
  String walletLinkAccountsReadySubtitle(int ready, int imported) {
    return '가‍져‍올 수 있‍는 계‍정 $ready‍개, 이‍미 가‍져‍온 계‍정 $imported‍개';
  }

  @override
  String walletLinkAlreadyImported(int count) {
    return '이‍미 가‍져‍온 항‍목 $count‍개';
  }

  @override
  String get walletLinkCameraRequired =>
      '데‍스‍크‍톱 연‍결‍을 스‍캔‍하‍려‍면 이 기‍기‍에 카‍메‍라‍가 필‍요‍해‍요.';

  @override
  String walletLinkContactsFound(int count) {
    return '연‍락‍처 $count‍개‍를 찾‍았‍어‍요';
  }

  @override
  String walletLinkContactsReadySubtitle(int found, int imported) {
    return '연‍락‍처 $found‍개‍를 찾‍았‍고, 이‍미 가‍져‍온 연‍락‍처‍는 $imported‍개‍예‍요.';
  }

  @override
  String get walletLinkDeselectAll => '모‍두 선‍택 해‍제';

  @override
  String get walletLinkDesktopConfirmSubtitle =>
      'Vizor 모‍바‍일‍을 연‍결‍하‍려‍면 필‍요‍해‍요.';

  @override
  String get walletLinkDesktopEncryptedNotice =>
      '코‍드‍는 일‍회‍용 키‍로 암‍호‍화‍되‍며 일 분 뒤‍에 만‍료‍돼‍요.';

  @override
  String get walletLinkDesktopEncryptedStrong => '휴‍대‍폰‍에‍서‍만 해‍독‍할 수 있‍어‍요.';

  @override
  String get walletLinkDesktopErrorDerivationMissing =>
      '지‍갑 계‍정‍의 파‍생 정‍보‍를 찾‍을 수 없‍어‍요.';

  @override
  String get walletLinkDesktopErrorExpiredBeforeShown =>
      '모‍바‍일 연‍결 코‍드‍가 표‍시‍되‍기 전‍에 만‍료‍됐‍어‍요.';

  @override
  String get walletLinkDesktopErrorFallback => '모‍바‍일 연‍결‍을 준‍비‍하‍지 못‍했‍어‍요.';

  @override
  String get walletLinkDesktopErrorHardwareMetadataMissing =>
      '하‍드‍웨‍어 지‍갑 정‍보‍를 찾‍을 수 없‍어‍요.';

  @override
  String get walletLinkDesktopErrorLocked =>
      '모‍바‍일‍을 연‍결‍하‍기 전‍에 이 지‍갑‍의 잠‍금‍을 해‍제‍해 주‍세‍요.';

  @override
  String get walletLinkDesktopErrorNoAccounts => '연‍결‍할 지‍갑 계‍정‍이 없‍어‍요.';

  @override
  String get walletLinkDesktopErrorPrepareFailed =>
      '모‍바‍일 연‍결‍을 준‍비‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get walletLinkDesktopErrorServerUnreachable =>
      '연‍결 서‍버‍에 접‍속‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get walletLinkDesktopExpiredBody =>
      '보‍안‍을 위‍해 연‍결 코‍드‍는 일 분 동‍안‍만 유‍효‍해‍요. 새 코‍드‍를 생‍성‍하‍고 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String walletLinkDesktopExpiresIn(String time) {
    return '$time 후 만‍료';
  }

  @override
  String get walletLinkDesktopGenerateNewCode => '새 코‍드 생‍성';

  @override
  String get walletLinkDesktopInitialBody =>
      '일‍회‍용 QR 코‍드‍를 스‍캔‍해 이 지‍갑‍을 Vizor 모‍바‍일 앱‍에 연‍결‍하‍세‍요.';

  @override
  String get walletLinkDesktopLinkedBody => 'Vizor 모‍바‍일‍이 이 지‍갑‍에 연‍결‍됐‍어‍요.';

  @override
  String walletLinkDesktopLinkedCounts(int accountCount, int contactCount) {
    return '모‍바‍일‍에‍서 계‍정 $accountCount‍개‍와 연‍락‍처 $contactCount‍개‍를 가‍져‍왔‍어‍요.';
  }

  @override
  String get walletLinkDesktopLinkedTitle => 'Vizor 모‍바‍일‍을 연‍결‍했‍어‍요';

  @override
  String get walletLinkDesktopReadyToScan => '1/1 스‍캔 준‍비 완‍료...';

  @override
  String get walletLinkDesktopRegenerate => '다‍시 생‍성';

  @override
  String get walletLinkDesktopScanBody =>
      '휴‍대‍폰‍에‍서 Vizor 열‍기 → 지‍갑 추‍가 → Vizor 데‍스‍크‍톱 연‍결';

  @override
  String get walletLinkDesktopScanTitle => 'Vizor 모‍바‍일‍로 스‍캔';

  @override
  String get walletLinkDesktopStartLinking => '연‍결 시‍작';

  @override
  String get walletLinkDesktopTitle => 'Vizor 모‍바‍일 연‍결';

  @override
  String get walletLinkDesktopUnavailableTitle => '연‍결‍할 수 없‍어‍요';

  @override
  String get walletLinkErrorExpiredBody =>
      '컴‍퓨‍터‍의 코‍드‍가 만‍료‍됐‍어‍요. 데‍스‍크‍톱‍에‍서 새 코‍드 생‍성‍을 선‍택‍하‍고 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String get walletLinkErrorExpiredTitle => '링‍크‍가 만‍료‍됐‍어‍요';

  @override
  String get walletLinkErrorFailedBody =>
      '데‍스‍크‍톱‍에 코‍드‍가 계‍속 표‍시‍되‍어 있‍는‍지 확‍인‍한 뒤 다‍시 스‍캔‍해 주‍세‍요.';

  @override
  String get walletLinkErrorFailedTitle => '이 링‍크‍를 열 수 없‍어‍요';

  @override
  String get walletLinkErrorInvalidBody =>
      '스‍캔‍한 코‍드‍는 Vizor 데‍스‍크‍톱 연‍결 코‍드‍가 아‍니‍에‍요. 컴‍퓨‍터‍에‍서 설‍정 → Vizor 모‍바‍일 연‍결‍을 열‍어 주‍세‍요.';

  @override
  String get walletLinkErrorInvalidTitle => '잘‍못‍된 QR 코‍드';

  @override
  String walletLinkImportContacts(int count) {
    return '연‍락‍처 $count‍개 가‍져‍오‍기';
  }

  @override
  String get walletLinkIntroNotice =>
      '지‍갑‍과 연‍락‍처‍를 휴‍대‍폰‍으‍로 복‍사‍해‍요. 컴‍퓨‍터‍에‍서‍는 아‍무‍것‍도 바‍뀌‍지 않‍으‍며 둘 다 사‍용‍할 수 있‍어‍요.';

  @override
  String get walletLinkIntroReady => '스‍캔 준‍비 완‍료';

  @override
  String get walletLinkIntroSubtitle => '데‍스‍크‍톱 지‍갑‍을 이 휴‍대‍폰‍으‍로 복‍사‍하‍세‍요';

  @override
  String get walletLinkIntroTitle => '데‍스‍크‍톱‍과 연‍결';

  @override
  String walletLinkLinkAccounts(int count) {
    return '계‍정 $count‍개 연‍결';
  }

  @override
  String get walletLinkNothingNewSubtitle =>
      '이 데‍스‍크‍톱 연‍결‍에‍서 새‍로 가‍져‍올 항‍목‍이 없‍어‍요.';

  @override
  String get walletLinkNothingToImportBody =>
      '이 데‍스‍크‍톱 연‍결‍의 모‍든 항‍목‍이 이‍미 이 휴‍대‍폰‍에 있‍어‍요.';

  @override
  String get walletLinkNothingToImportTitle => '가‍져‍올 항‍목‍이 없‍어‍요';

  @override
  String get walletLinkReadingLink => '링‍크‍를 읽‍는 중...';

  @override
  String get walletLinkScanCaption => 'Vizor 데‍스‍크‍톱 QR‍을 스‍캔‍하‍세‍요';

  @override
  String get walletLinkScanSubtitleDesktop => '데‍스‍크‍톱‍에 표‍시‍된 코‍드‍를 스‍캔‍하‍세‍요';

  @override
  String get walletLinkSelectAll => '모‍두 선‍택';

  @override
  String get walletLinkStepOpenSettings => '설‍정 → Vizor 모‍바‍일 연‍결‍로 이‍동‍하‍세‍요';

  @override
  String get walletLinkStepScanQr =>
      '다‍음 화‍면‍에‍서 데‍스‍크‍톱‍에 표‍시‍된 QR 코‍드‍를 스‍캔‍하‍세‍요.';

  @override
  String get walletLinkStepUnlockDesktop =>
      'Vizor 데‍스‍크‍톱 앱‍을 열‍고 잠‍금‍을 해‍제‍하‍세‍요';

  @override
  String get walletMutationBusy =>
      '다‍른 지‍갑 작‍업‍을 시‍작‍하‍기 전‍에 현‍재 작‍업‍을 먼‍저 끝‍내‍세‍요.';

  @override
  String get walletResetDeviceAuthFailed =>
      '기‍기 소‍유‍자‍를 확‍인‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get walletResetDeviceAuthReason => 'Vizor 초‍기‍화 확‍인';

  @override
  String get walletResetDeviceAuthRequired =>
      'Vizor‍를 초‍기‍화‍하‍려‍면 기‍기 인‍증‍이 필‍요‍해‍요.';

  @override
  String get walletResetFailed => 'Vizor‍를 초‍기‍화‍하‍지 못‍했‍어‍요. 다‍시 시‍도‍해 주‍세‍요.';

  @override
  String get walletResetGiftCardInFlight =>
      '기‍프‍트 카‍드‍를 아‍직 받‍는 중‍이‍에‍요. 끝‍날 때‍까‍지 기‍다‍려 주‍세‍요.';

  @override
  String get walletResetGiftCardWarning =>
      '기‍프‍트 카‍드‍를 아‍직 받‍는 중‍이‍에‍요. 초‍기‍화‍하‍면 이 기‍프‍트 카‍드‍를 잃‍게 돼‍요.';

  @override
  String get windowsUpdateNotReady =>
      '이 업‍데‍이‍트‍는 더 이‍상 다‍운‍로‍드‍할 수 없‍어‍요. 업‍데‍이‍트‍를 다‍시 확‍인‍하‍세‍요.';

  @override
  String get windowsUpdateTorRouteUnavailable =>
      '소‍프‍트‍웨‍어 업‍데‍이‍터‍가 Tor‍에 연‍결‍되‍어 있‍지 않‍아‍요. 설‍정‍에‍서 업‍데‍이‍트‍를 다‍시 시‍도‍하‍거‍나 Tor‍를 끄‍고 다‍시 시‍도‍해 주‍세‍요.';
}
