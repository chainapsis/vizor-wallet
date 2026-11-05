// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aboutBuiltByBody =>
      '저⁠희⁠는 Cosmos, Ethereum, Bitcoin⁠에⁠서 수⁠백⁠만 명⁠이 쓰⁠는 지⁠갑 Keplr⁠을 만⁠들⁠었⁠어⁠요. Vizor⁠는 Zcash 지⁠갑⁠이 어⁠떠⁠해⁠야 하⁠는⁠지⁠에 대⁠한 저⁠희⁠의 답⁠이⁠에⁠요.';

  @override
  String get aboutBuiltByHeading => 'Keplr 팀⁠이 만⁠들⁠었⁠어⁠요';

  @override
  String get aboutLegalPlaceholderBody =>
      'Bitcoin⁠이⁠나 Ethereum⁠과 달⁠리 차⁠폐 Zcash 거⁠래⁠는 보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액⁠을 숨⁠겨⁠요.';

  @override
  String get aboutLegalPlaceholderHeading => 'Keplr 지⁠갑⁠을 만⁠든 팀⁠이 만⁠들⁠었⁠어⁠요.';

  @override
  String aboutLinkSemantics(String label) {
    return '$label 링⁠크';
  }

  @override
  String get aboutOpenGithub => 'Vizor GitHub 열⁠기';

  @override
  String get aboutOpenSourceBody =>
      'Vizor⁠는 Apache 라⁠이⁠선⁠스⁠로 공⁠개⁠돼 있⁠어⁠요. 키⁠는 내 기⁠기⁠에⁠만 있⁠어⁠요.\n잔⁠액⁠이⁠나 거⁠래 내⁠역⁠은 저⁠희⁠가 볼 수 없⁠어⁠요.';

  @override
  String get aboutOpenSourceHeading => '오⁠픈 소⁠스, 자⁠기 보⁠관';

  @override
  String get aboutOpenWebsite => 'Vizor 웹⁠사⁠이⁠트 열⁠기';

  @override
  String get aboutShieldedBody =>
      'Vizor⁠는 보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액⁠이 비⁠공⁠개⁠로 유⁠지⁠되⁠는 차⁠폐 거⁠래⁠를 중⁠심⁠으⁠로 만⁠들⁠어⁠졌⁠어⁠요. 투⁠명 Zcash⁠도 쓸 수 있⁠지⁠만 기⁠본⁠은 비⁠공⁠개⁠예⁠요.';

  @override
  String get aboutShieldedHeading => '차⁠폐 Zcash⁠를 위⁠해 설⁠계⁠했⁠어⁠요';

  @override
  String get aboutTermsTitle => '이⁠용 약⁠관';

  @override
  String get aboutTitle => 'Vizor 지⁠갑 정⁠보';

  @override
  String aboutVersionLabel(String version) {
    return '버⁠전: $version 퍼⁠블⁠릭 베⁠타';
  }

  @override
  String get aboutWebsite => '웹⁠사⁠이⁠트';

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
  String get accountsTitle => '계⁠정';

  @override
  String get accountsUpdatePicture => '사⁠진 업⁠데⁠이⁠트';

  @override
  String get accountsViewSecretPhrase => '복⁠구 문⁠구 보⁠기';

  @override
  String get accountsViewViewingKey => '뷰⁠잉 키 보⁠기';

  @override
  String get activityAddressUnified => '통⁠합 주⁠소';

  @override
  String get activityBalanceFromOrchard => 'Orchard 잔⁠액⁠에⁠서';

  @override
  String get activityBalanceFromTransparent => '투⁠명 잔⁠액⁠에⁠서';

  @override
  String get activityBalanceIronwood => 'Ironwood 잔⁠액';

  @override
  String get activityBalanceOrchard => 'Orchard 잔⁠액';

  @override
  String get activityDetailsLoadFailed => '실⁠패⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요';

  @override
  String get activityDetailsLoadPublicly => '공⁠개⁠로 불⁠러⁠오⁠기';

  @override
  String get activityDetailsLoadPubliclyLabel => '전⁠체 상⁠세 정⁠보';

  @override
  String get activityDetailsLoading => '불⁠러⁠오⁠는 중…';

  @override
  String get activityDetailsNotCovered => '비⁠공⁠개 모⁠드⁠에⁠서⁠는 볼 수 없⁠어⁠요';

  @override
  String get activityDetailsOmittedLabel => '표⁠시⁠되⁠지 않⁠음';

  @override
  String get activityDetailsOutputsLabel => '거⁠래 출⁠력';

  @override
  String get activityDetailsOutputsUnattributed => '받⁠는 사⁠람 미⁠확⁠인';

  @override
  String get activityDetailsUnavailable =>
      '상⁠세 정⁠보⁠를 불⁠러⁠올 수 없⁠어⁠요. 서⁠비⁠스⁠에 연⁠결⁠되⁠면 업⁠데⁠이⁠트⁠돼⁠요';

  @override
  String get activityDetailsUnknownRecipient => '알 수 없⁠는 받⁠는 사⁠람';

  @override
  String get activityEtaFunding => '약 2–6⁠분';

  @override
  String get activityEtaNu7 => '약 1⁠분 이⁠내';

  @override
  String get activityEtaNu7Funding => '약 1–2⁠분';

  @override
  String get activityEtaStandard => '약 1–3⁠분';

  @override
  String get activityEtaTakingLonger => '시⁠간⁠이 더 걸⁠리⁠고 있⁠어⁠요';

  @override
  String get activityFeedEmpty => '아⁠직 활⁠동⁠이 없⁠어⁠요';

  @override
  String get activityFeedRetry => '활⁠동 다⁠시 불⁠러⁠오⁠기';

  @override
  String activityGiftBatchBreakdown(
    String cards,
    String fees,
    String feeLabel,
    String fee,
  ) {
    return '카⁠드 $cards ZEC · 사⁠용 수⁠수⁠료 $fees ZEC · $feeLabel $fee';
  }

  @override
  String get activityGiftCreated => '기⁠프⁠트 카⁠드⁠를 만⁠들⁠었⁠어⁠요';

  @override
  String activityGiftCreatedMany(int count) {
    return '기⁠프⁠트 카⁠드 $count⁠장⁠을 만⁠들⁠었⁠어⁠요';
  }

  @override
  String get activityGiftCreating => '카⁠드 생⁠성 중';

  @override
  String activityGiftCreatingMany(int count) {
    return '카⁠드 $count⁠장 생⁠성 중';
  }

  @override
  String get activityGiftCreationFailed => '기⁠프⁠트 카⁠드 생⁠성 실⁠패';

  @override
  String get activityGiftGroupFailed => '기⁠프⁠트 카⁠드 묶⁠음 실⁠패';

  @override
  String get activityGiftRedeemed => '기⁠프⁠트 카⁠드⁠를 사⁠용⁠했⁠어⁠요';

  @override
  String get activityGiftRedeeming => '카⁠드 사⁠용 중';

  @override
  String get activityGiftRedemptionFailed => '기⁠프⁠트 카⁠드 사⁠용 실⁠패';

  @override
  String get activityGiftStatusCreated => '생⁠성⁠됨';

  @override
  String get activityGiftStatusCreating => '생⁠성 중…';

  @override
  String get activityGiftStatusRedeemed => '사⁠용⁠됨';

  @override
  String get activityGiftStatusRedeeming => '사⁠용 중…';

  @override
  String get activityGiftTotalPlanned => '예⁠정 합⁠계';

  @override
  String get activityGiftTotalSpent => '총 사⁠용⁠액';

  @override
  String get activityGiftTotalSubmitted => '제⁠출⁠한 합⁠계';

  @override
  String get activityLoadFailedDesktop => '활⁠동⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get activityLoadFailedMobile =>
      '활⁠동⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 잠⁠시 후 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get activityOmissionLaterOutputs => '두 번⁠째 이⁠후⁠의 출⁠력';

  @override
  String activityOmissionMoreOutputs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '출⁠력 $count⁠개 더',
    );
    return '$_temp0';
  }

  @override
  String get activityOmissionOtherSenders => '다⁠른 보⁠낸 주⁠소';

  @override
  String get activityOmissionOutputAddress => '출⁠력 주⁠소';

  @override
  String get activityOmissionSender => '보⁠낸 주⁠소';

  @override
  String get activityOmissionSharedFunding => '다⁠른 지⁠갑⁠의 입⁠력';

  @override
  String get activityOmissionShieldedFunding => '자⁠금 중 차⁠폐⁠된 부⁠분';

  @override
  String get activityPayFromShielded => '차⁠폐⁠된 ZEC⁠에⁠서';

  @override
  String activityPayFromShieldedOnChain(String network) {
    return '차⁠폐⁠된 ZEC⁠에⁠서 · $network';
  }

  @override
  String get activityPayIncomplete => '결⁠제 미⁠완⁠료';

  @override
  String get activityPayPaid => '결⁠제 완⁠료';

  @override
  String get activityPayPaying => '결⁠제 중 ...';

  @override
  String get activityPoolMixed => '혼⁠합';

  @override
  String get activityPublicLookupBody =>
      'Vizor⁠가 이 거⁠래 하⁠나⁠를 서⁠버⁠에 요⁠청⁠해⁠서 비⁠공⁠개 조⁠회⁠에⁠서 빠⁠진 정⁠보⁠를 보⁠여 드⁠려⁠요.';

  @override
  String get activityPublicLookupTitle => '상⁠세 정⁠보⁠를 공⁠개⁠로 불⁠러⁠올⁠까⁠요?';

  @override
  String get activityPublicLookupWarning =>
      '서⁠버⁠는 이 지⁠갑⁠이 이 거⁠래⁠에 관⁠심⁠이 있⁠다⁠는 사⁠실⁠을 알⁠게 되⁠고, Tor⁠를 쓰⁠지 않⁠으⁠면 IP 주⁠소⁠도 알⁠게 돼⁠요.';

  @override
  String get activityReceiptAmountMigrated => '이⁠전⁠한 금⁠액';

  @override
  String get activityReceiptCardFee => '카⁠드 수⁠수⁠료';

  @override
  String get activityReceiptCards => '카⁠드';

  @override
  String get activityReceiptDetails => '상⁠세 정⁠보';

  @override
  String get activityReceiptDetailsIncomplete => '상⁠세 정⁠보⁠가 완⁠전⁠하⁠지 않⁠아⁠요';

  @override
  String get activityReceiptDetailsIncompleteHelp =>
      '이 거⁠래⁠의 수⁠신⁠자, 메⁠모, 수⁠수⁠료 같⁠은 일⁠부 정⁠보⁠를 아⁠직 알 수 없⁠어⁠요. 표⁠시⁠된 금⁠액⁠이 바⁠뀔 수 있⁠어⁠요.';

  @override
  String get activityReceiptEstimatedNetworkFee => '예⁠상 네⁠트⁠워⁠크 수⁠수⁠료';

  @override
  String get activityReceiptFrom => '보⁠낸 곳';

  @override
  String get activityReceiptIncomplete => '불⁠완⁠전⁠해⁠요';

  @override
  String get activityReceiptLoadFailed => '거⁠래⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get activityReceiptLoading => '거⁠래⁠를 불⁠러⁠오⁠는 중…';

  @override
  String get activityReceiptNetChange => '순⁠변⁠동';

  @override
  String get activityReceiptNetworkFee => '네⁠트⁠워⁠크 수⁠수⁠료';

  @override
  String get activityReceiptOutput => '출⁠력';

  @override
  String get activityReceiptRefreshFailed => '최⁠신 거⁠래 상⁠태⁠를 새⁠로 고⁠치⁠지 못⁠했⁠어⁠요.';

  @override
  String get activityReceiptStatus => '상⁠태';

  @override
  String get activityReceiptUnattributedFeeHelp =>
      '이 거⁠래⁠의 총 수⁠수⁠료⁠예⁠요. 내 계⁠정⁠이 부⁠담⁠한 금⁠액⁠은 알 수 없⁠어⁠요.';

  @override
  String get activityReceiptUnknownFee => '알 수 없⁠음';

  @override
  String activityRowToday(String time) {
    return '오⁠늘 $time';
  }

  @override
  String get activityRowWaitingForConnection => '연⁠결⁠을 기⁠다⁠리⁠는 중';

  @override
  String activityRowYesterday(String time) {
    return '어⁠제 $time';
  }

  @override
  String get activitySectionEarlier => '이⁠전';

  @override
  String get activitySectionThisWeek => '이⁠번 주';

  @override
  String get activitySenderShielded => '차⁠폐⁠된 보⁠낸 사⁠람';

  @override
  String get activitySenderUnknown => '알 수 없⁠는 보⁠낸 사⁠람';

  @override
  String get activityStatusFailedFundsReturned => '실⁠패, 자⁠금⁠이 반⁠환⁠됐⁠어⁠요';

  @override
  String get activityStatusIncompleteDeposit => '입⁠금⁠이 부⁠족⁠해⁠요';

  @override
  String activitySwapAssetOnChain(String symbol, String chain) {
    return '$chain⁠의 $symbol';
  }

  @override
  String activitySwapDepositedAsset(String symbol) {
    return '$symbol 입⁠금⁠됨';
  }

  @override
  String activitySwapMinutesAgo(int minutes) {
    return '$minutes⁠분 전';
  }

  @override
  String activitySwapReceivedAsset(String symbol) {
    return '$symbol 받⁠음';
  }

  @override
  String activitySwapStep(int current, int total) {
    return '$current/$total 진⁠행 중';
  }

  @override
  String get activitySwapSwapped => '스⁠왑 완⁠료';

  @override
  String get activitySwapSwapping => '스⁠왑 중...';

  @override
  String get activitySwapTimeout => '시⁠간 초⁠과';

  @override
  String get activitySwapTitle => '스⁠왑';

  @override
  String get activityTitleMigrated => 'Ironwood⁠로 이⁠전⁠됨';

  @override
  String get activityTitleMigrating => 'Ironwood⁠로 이⁠전⁠하⁠는 중...';

  @override
  String get activityTitleMigratingVerb => 'Ironwood⁠로 이⁠전⁠하⁠는 중';

  @override
  String get activityTitleMigrationFailed => '이⁠전 실⁠패';

  @override
  String get activityTitleReceiveFailed => '받⁠기 실⁠패';

  @override
  String get activityTitleReceiveInProgress => '받⁠는 중...';

  @override
  String get activityTitleReceived => '받⁠음';

  @override
  String get activityTitleReceivedSuccessfully => '받⁠았⁠어⁠요';

  @override
  String get activityTitleReceiving => '받⁠는 중...';

  @override
  String get activityTitleReceivingVerb => '받⁠는 중';

  @override
  String get activityTitleSendingVerb => '보⁠내⁠는 중';

  @override
  String get activityTitleSent => '보⁠냄';

  @override
  String get activityTitleShielded => '차⁠폐⁠됨';

  @override
  String get activityTitleShieldingFailed => '차⁠폐 실⁠패';

  @override
  String get activityTitleShieldingInProgress => '차⁠폐⁠하⁠는 중...';

  @override
  String get activityTitleShieldingVerb => '차⁠폐⁠하⁠는 중';

  @override
  String get activityTitleTransaction => '거⁠래';

  @override
  String get activityToastHashCopiedMobile => '거⁠래 해⁠시⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get addressBookAddContact => '연⁠락⁠처 추⁠가';

  @override
  String get addressBookAddressHintDesktop => '주⁠소⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String get addressBookAddressHintMobile => '주⁠소⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String get addressBookAddressLabel => '주⁠소';

  @override
  String get addressBookAddressMissing => '주⁠소⁠를 입⁠력⁠해 주⁠세⁠요';

  @override
  String get addressBookClearAddress => '주⁠소 지⁠우⁠기';

  @override
  String get addressBookClearName => '이⁠름 지⁠우⁠기';

  @override
  String get addressBookClearSearch => '검⁠색⁠어 지⁠우⁠기';

  @override
  String addressBookContactActions(String label) {
    return '$label 작⁠업';
  }

  @override
  String get addressBookEditContact => '연⁠락⁠처 수⁠정';

  @override
  String get addressBookEmptyBody => '첫 연⁠락⁠처⁠를 추⁠가⁠해 시⁠작⁠해 보⁠세⁠요.';

  @override
  String get addressBookEmptyTitle => '아⁠직 연⁠락⁠처⁠가 없⁠어⁠요';

  @override
  String get addressBookInvalidBitcoin => '올⁠바⁠르⁠지 않⁠은 Bitcoin 주⁠소⁠예⁠요';

  @override
  String get addressBookInvalidEvm => '올⁠바⁠르⁠지 않⁠은 EVM 주⁠소⁠예⁠요';

  @override
  String get addressBookInvalidNear => '올⁠바⁠르⁠지 않⁠은 NEAR 주⁠소⁠예⁠요';

  @override
  String get addressBookInvalidSolana => '올⁠바⁠르⁠지 않⁠은 Solana 주⁠소⁠예⁠요';

  @override
  String get addressBookInvalidZcash => '올⁠바⁠르⁠지 않⁠은 Zcash 주⁠소⁠예⁠요';

  @override
  String get addressBookLabelLength => '1~20⁠자⁠로 입⁠력⁠해 주⁠세⁠요';

  @override
  String get addressBookLabelMissing => '라⁠벨⁠을 입⁠력⁠해 주⁠세⁠요';

  @override
  String get addressBookLoadFailed =>
      '연⁠락⁠처⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나, 계⁠속⁠되⁠면 고⁠객 지⁠원⁠에 문⁠의⁠해 주⁠세⁠요.';

  @override
  String get addressBookNameHint => '이⁠름⁠을 입⁠력⁠하⁠세⁠요';

  @override
  String get addressBookNameLabel => '이⁠름';

  @override
  String get addressBookNearSuffixWarning =>
      'NEAR 계⁠정⁠은 보⁠통 .near⁠로 끝⁠나⁠요. 주⁠소⁠를 다⁠시 확⁠인⁠해 주⁠세⁠요';

  @override
  String get addressBookNetworkLabel => '네⁠트⁠워⁠크';

  @override
  String get addressBookNoNetworks => '네⁠트⁠워⁠크⁠를 찾⁠지 못⁠했⁠어⁠요';

  @override
  String get addressBookNoResultsBody => '검⁠색⁠어⁠를 바⁠꿔 보⁠세⁠요';

  @override
  String get addressBookNoResultsTitle => '연⁠락⁠처⁠를 찾⁠지 못⁠했⁠어⁠요';

  @override
  String get addressBookPickerClose => '연⁠락⁠처 닫⁠기';

  @override
  String get addressBookPickerEmptyTitle => '연⁠락⁠처⁠를 찾⁠지 못⁠했⁠어⁠요';

  @override
  String get addressBookPickerLoadFailed =>
      '연⁠락⁠처⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get addressBookPickerSearchHint => '연⁠락⁠처 검⁠색';

  @override
  String addressBookRemoveBody(String label) {
    return '$label⁠을(를) 연⁠락⁠처⁠에⁠서 삭⁠제⁠해⁠요.';
  }

  @override
  String get addressBookRemoveBodyUnknown => '이 연⁠락⁠처⁠를 삭⁠제⁠해⁠요.';

  @override
  String addressBookRemoveConfirmBody(String label) {
    return '\"$label\"을(를) 연⁠락⁠처⁠에⁠서 삭⁠제⁠해⁠요. 지⁠난 거⁠래⁠에⁠는 영⁠향⁠이 없⁠어⁠요.';
  }

  @override
  String get addressBookRemoveConfirmTitle => '연⁠락⁠처⁠를 삭⁠제⁠할⁠까⁠요?';

  @override
  String get addressBookRemoveContact => '연⁠락⁠처 삭⁠제';

  @override
  String get addressBookRemoveFailed =>
      '연⁠락⁠처⁠를 삭⁠제⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get addressBookRemoveFailedMobile =>
      '연⁠락⁠처⁠를 삭⁠제⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get addressBookSaveFailed =>
      '연⁠락⁠처⁠를 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get addressBookSaveFailedMobile =>
      '연⁠락⁠처⁠를 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get addressBookScanAddressQr => '주⁠소 QR 스⁠캔';

  @override
  String addressBookScanQrTitle(String network) {
    return '$network QR 코⁠드 스⁠캔';
  }

  @override
  String get addressBookSearch => '검⁠색';

  @override
  String get addressBookSearchHint => '라⁠벨 또⁠는 네⁠트⁠워⁠크 검⁠색';

  @override
  String get addressBookSearchNetwork => '네⁠트⁠워⁠크 검⁠색';

  @override
  String get addressBookSelectNetwork => '네⁠트⁠워⁠크 선⁠택';

  @override
  String get addressScanAddressCameraNeeded =>
      '주⁠소 QR⁠을 스⁠캔⁠하⁠려⁠면 이 기⁠기⁠에 카⁠메⁠라⁠가 필⁠요⁠해⁠요.';

  @override
  String addressScanCameraDefaultSuffix(String name) {
    return '$name(기⁠본)';
  }

  @override
  String get addressScanCameraNeeded =>
      'QR⁠을 스⁠캔⁠하⁠려⁠면 이 기⁠기⁠에 카⁠메⁠라⁠가 필⁠요⁠해⁠요.';

  @override
  String get addressScanCameraOff =>
      '카⁠메⁠라 접⁠근⁠이 꺼⁠져 있⁠어⁠요. 주⁠소⁠를 스⁠캔⁠하⁠려⁠면 설⁠정⁠에⁠서 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get addressScanCameraRequired =>
      '주⁠소 QR⁠을 스⁠캔⁠하⁠려⁠면 이 기⁠기⁠에 카⁠메⁠라⁠가 필⁠요⁠해⁠요.';

  @override
  String get addressScanCameraRestricted =>
      '스⁠크⁠린 타⁠임 또⁠는 기⁠기 관⁠리⁠가 이 기⁠기⁠의 카⁠메⁠라⁠를 차⁠단⁠하⁠고 있⁠어⁠요.';

  @override
  String get addressScanCloseScanner => '스⁠캐⁠너 닫⁠기';

  @override
  String get addressScanDefaultCamera => '기⁠본 카⁠메⁠라';

  @override
  String get addressScanDeniedTitle => '카⁠메⁠라 접⁠근⁠을 거⁠부⁠했⁠어⁠요';

  @override
  String get addressScanEnableWindowsAccess => 'Windows 카⁠메⁠라 접⁠근⁠을 켜 주⁠세⁠요';

  @override
  String get addressScanGrantAccess => '카⁠메⁠라 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요';

  @override
  String get addressScanLoadingCamera => '카⁠메⁠라 불⁠러⁠오⁠는 중...';

  @override
  String get addressScanLoadingEllipsis => '불⁠러⁠오⁠는 중...';

  @override
  String get addressScanNoCamera => '카⁠메⁠라⁠를 찾⁠지 못⁠했⁠어⁠요';

  @override
  String get addressScanNoCameraOpened =>
      '카⁠메⁠라⁠를 열 수 없⁠어⁠요. 카⁠메⁠라⁠가 연⁠결⁠되⁠어 있⁠고 다⁠른 앱⁠에⁠서 사⁠용 중⁠이 아⁠닌⁠지 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get addressScanOpenSettings => '설⁠정 열⁠기';

  @override
  String get addressScanTitle => '주⁠소 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get addressScanWindowsAccessHint =>
      'Windows 설⁠정⁠에⁠서 \'카⁠메⁠라 액⁠세⁠스\'와 \'데⁠스⁠크⁠톱 앱⁠에⁠서 카⁠메⁠라⁠에 액⁠세⁠스⁠하⁠도⁠록 허⁠용\'을 켜 주⁠세⁠요.';

  @override
  String get addressScanZcashPrompt => '계⁠속⁠하⁠려⁠면 Zcash QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get appBackDonation => '후⁠원';

  @override
  String get appBackHardwareWallets => '하⁠드⁠웨⁠어 지⁠갑';

  @override
  String get appBackImportMethods => '가⁠져⁠오⁠기 방⁠법';

  @override
  String get appBackReceive => '받⁠기';

  @override
  String get appBackResults => '결⁠과';

  @override
  String get appBackReview => '검⁠토';

  @override
  String get appBackSend => '보⁠내⁠기';

  @override
  String get appBackStatus => '상⁠태';

  @override
  String get appBackSubmitted => '제⁠출 완⁠료';

  @override
  String get appBackTransaction => '거⁠래';

  @override
  String get appBackVotingRound => '투⁠표 회⁠차';

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
  String get commonActionNeeded => '확⁠인 필⁠요';

  @override
  String get commonAddAMessage => '메⁠시⁠지 추⁠가';

  @override
  String get commonAddAccount => '계⁠정 추⁠가';

  @override
  String get commonAddressCopied => '주⁠소⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String commonAddressForChain(String chain) {
    return '$chain 주⁠소';
  }

  @override
  String get commonAddressLabel => '주⁠소 라⁠벨';

  @override
  String get commonAmount => '금⁠액';

  @override
  String get commonBack => '뒤⁠로';

  @override
  String commonBackTo(String destination) {
    return '$destination(으)로 돌⁠아⁠가⁠기';
  }

  @override
  String get commonBackToWallet => '지⁠갑⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get commonCameraDeniedTitle => '카⁠메⁠라 접⁠근⁠을 거⁠부⁠했⁠어⁠요';

  @override
  String get commonCameraRequestAgainHint =>
      '다⁠시 요⁠청⁠하⁠거⁠나\n시⁠스⁠템 설⁠정⁠에⁠서 직⁠접 켜 주⁠세⁠요.';

  @override
  String get commonCameraRestrictedBody =>
      '스⁠크⁠린 타⁠임 또⁠는 기⁠기 관⁠리⁠가\n카⁠메⁠라⁠를 차⁠단⁠하⁠고 있⁠어⁠요.';

  @override
  String get commonCameraRestrictedTitle => '카⁠메⁠라 접⁠근⁠이 제⁠한⁠되⁠어 있⁠어⁠요';

  @override
  String get commonCameraUnavailable => '카⁠메⁠라⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get commonCameraUnavailableNow => '지⁠금⁠은 카⁠메⁠라⁠를 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get commonCancel => '취⁠소';

  @override
  String get commonCancelFailedRetry => '취⁠소⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get commonCancellationFailed =>
      '취⁠소⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get commonCancelling => '취⁠소⁠하⁠는 중…';

  @override
  String get commonCannotBeUndone => '되⁠돌⁠릴 수 없⁠어⁠요.';

  @override
  String get commonChainAndAddress => '체⁠인 및 주⁠소';

  @override
  String get commonChangeContactPicture => '연⁠락⁠처 사⁠진 변⁠경';

  @override
  String get commonChecking => '확⁠인 중...';

  @override
  String get commonCheckingEllipsis => '확⁠인⁠하⁠는 중…';

  @override
  String get commonCheckingStatus => '상⁠태⁠를 확⁠인⁠하⁠는 중';

  @override
  String get commonClear => '지⁠우⁠기';

  @override
  String get commonClearContactLabel => '연⁠락⁠처 라⁠벨 지⁠우⁠기';

  @override
  String get commonClearText => '텍⁠스⁠트 지⁠우⁠기';

  @override
  String get commonClose => '닫⁠기';

  @override
  String get commonCloseMessage => '메⁠시⁠지 닫⁠기';

  @override
  String get commonCoinholderVoting => '코⁠인 보⁠유⁠자 투⁠표';

  @override
  String get commonCompleted => '완⁠료';

  @override
  String get commonContactLabelHint => '1~20⁠자⁠의 라⁠벨⁠을 입⁠력⁠하⁠세⁠요';

  @override
  String get commonContacts => '연⁠락⁠처';

  @override
  String get commonContinue => '계⁠속';

  @override
  String get commonCopied => '복⁠사⁠했⁠어⁠요';

  @override
  String get commonCopy => '복⁠사';

  @override
  String get commonCopyAddress => '주⁠소 복⁠사';

  @override
  String get commonCopyShieldedAddress => '차⁠폐 주⁠소 복⁠사';

  @override
  String get commonDismissNotification => '알⁠림 닫⁠기';

  @override
  String get commonDone => '완⁠료';

  @override
  String get commonDownload => '다⁠운⁠로⁠드';

  @override
  String get commonDurationOneHour => '1⁠시⁠간';

  @override
  String get commonDurationOneMinute => '1⁠분';

  @override
  String get commonEdit => '수⁠정';

  @override
  String get commonEnterAmountInUsd => 'USD 단⁠위⁠로 금⁠액 입⁠력';

  @override
  String get commonFailed => '실⁠패';

  @override
  String get commonFeatureInProgress => '아⁠직 준⁠비 중⁠인 기⁠능⁠이⁠에⁠요.';

  @override
  String get commonFullAddress => '전⁠체 주⁠소';

  @override
  String get commonGetSignature => '서⁠명 가⁠져⁠오⁠기';

  @override
  String get commonGoBack => '돌⁠아⁠가⁠기';

  @override
  String get commonGuaranteedMinimum => '최⁠소 보⁠장 수⁠량';

  @override
  String get commonImporting => '가⁠져⁠오⁠는 중...';

  @override
  String get commonInProgress => '진⁠행 중';

  @override
  String get commonInformation => '안⁠내';

  @override
  String get commonJustNow => '방⁠금';

  @override
  String get commonKeepQrSteady => 'QR 코⁠드⁠가 흔⁠들⁠리⁠지 않⁠고 전⁠부 보⁠이⁠게 해 주⁠세⁠요.';

  @override
  String get commonKeepScreenAwake => '화⁠면 켜 두⁠기';

  @override
  String get commonKeystoneAfterScan => '스⁠캔⁠한 뒤 서⁠명 가⁠져⁠오⁠기⁠를 누⁠르⁠세⁠요.';

  @override
  String get commonKeystoneScanSignatureResult =>
      'Keystone⁠에⁠서 서⁠명 결⁠과 QR⁠을 연 다⁠음 다⁠시 스⁠캔⁠하⁠세⁠요.';

  @override
  String get commonKeystoneScanTransaction =>
      'Keystone 지⁠갑⁠으⁠로 이 거⁠래 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요. 기⁠기⁠의 안⁠내⁠를 따⁠르⁠세⁠요.';

  @override
  String get commonLedgerSigningFailed => 'Ledger 서⁠명⁠에 실⁠패⁠했⁠어⁠요';

  @override
  String get commonLoading => '불⁠러⁠오⁠는 중';

  @override
  String get commonLoadingActivity => '활⁠동⁠을 불⁠러⁠오⁠는 중';

  @override
  String get commonMemo => '메⁠모';

  @override
  String get commonMessage => '메⁠시⁠지';

  @override
  String get commonMessageIsTooLong => '메⁠시⁠지⁠가 너⁠무 길⁠어⁠요';

  @override
  String get commonNetworkConversionFees => '네⁠트⁠워⁠크 + 변⁠환 수⁠수⁠료';

  @override
  String get commonNoActiveAccount => '선⁠택⁠된 계⁠정⁠이 없⁠어⁠요';

  @override
  String get commonNoActiveAccountSentence => '활⁠성 계⁠정⁠이 없⁠어⁠요.';

  @override
  String get commonNotAvailableYet => '아⁠직 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get commonNotEnoughZec => 'ZEC⁠가 부⁠족⁠해⁠요';

  @override
  String get commonOk => '확⁠인';

  @override
  String get commonPayInsufficientZec =>
      '이 결⁠제⁠에 필⁠요⁠한 ZEC⁠가 부⁠족⁠해⁠요. 더 적⁠은 금⁠액⁠으⁠로 시⁠도⁠해 보⁠세⁠요.';

  @override
  String get commonPaymentFailed => '결⁠제⁠에 실⁠패⁠했⁠어⁠요';

  @override
  String get commonPaymentInProgress => '결⁠제 진⁠행 중';

  @override
  String get commonPaymentProgress => '결⁠제 진⁠행 상⁠황';

  @override
  String get commonPaymentRefunded => '결⁠제 환⁠불⁠됨';

  @override
  String get commonPaymentRequest => '결⁠제 요⁠청';

  @override
  String get commonPrivatelyFromShieldedBalance => '차⁠폐⁠된 잔⁠액⁠에⁠서 비⁠공⁠개⁠로';

  @override
  String get commonProvingParamsFailed =>
      '필⁠요⁠한 증⁠명 매⁠개⁠변⁠수⁠를 준⁠비⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get commonQrNoAddress => 'QR 코⁠드⁠에 주⁠소⁠가 없⁠어⁠요.';

  @override
  String get commonQuit => '종⁠료';

  @override
  String get commonRate => '환⁠율';

  @override
  String get commonRecipientGets => '수⁠신⁠자⁠가 받⁠을 금⁠액';

  @override
  String get commonRefundFee => '환⁠불 수⁠수⁠료';

  @override
  String get commonRefundTo => '환⁠불 주⁠소';

  @override
  String commonRefundToAddress(String address) {
    return '환⁠불 주⁠소: $address';
  }

  @override
  String get commonRefunded => '환⁠불⁠됨';

  @override
  String get commonRefundedAmount => '환⁠불 금⁠액';

  @override
  String get commonRemove => '삭⁠제';

  @override
  String get commonRequestAgain => '다⁠시 요⁠청';

  @override
  String get commonResetVizor => 'Vizor 초⁠기⁠화';

  @override
  String get commonRetry => '다⁠시 시⁠도';

  @override
  String get commonRetrySaving => '저⁠장 다⁠시 시⁠도';

  @override
  String get commonReturnHome => '홈⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get commonReviewAndFinish => '검⁠토⁠하⁠고 완⁠료';

  @override
  String get commonReviewPayment => '결⁠제 검⁠토';

  @override
  String get commonReviewQuote => '견⁠적 검⁠토';

  @override
  String get commonReviewSwap => '스⁠왑 검⁠토';

  @override
  String get commonSave => '저⁠장';

  @override
  String get commonSaveContact => '연⁠락⁠처 저⁠장';

  @override
  String get commonScanOriginalQr => '원⁠래 QR 스⁠캔';

  @override
  String get commonScanQrCode => 'QR 코⁠드 스⁠캔';

  @override
  String get commonSelectAccount => '계⁠정 선⁠택';

  @override
  String get commonSelectContactPicture => '연⁠락⁠처 사⁠진 선⁠택';

  @override
  String get commonSelectRecipient => '받⁠는 사⁠람 선⁠택';

  @override
  String get commonSelectedContact => '선⁠택⁠된 연⁠락⁠처';

  @override
  String get commonSendFailed => '보⁠내⁠기 실⁠패';

  @override
  String get commonSendZec => 'ZEC 보⁠내⁠기';

  @override
  String get commonSending => '보⁠내⁠는 중...';

  @override
  String get commonSensitiveContentHidden => '민⁠감⁠한 내⁠용⁠을 가⁠렸⁠어⁠요';

  @override
  String get commonSentSuccessfully => '보⁠냈⁠어⁠요';

  @override
  String get commonShieldedAddress => '차⁠폐 주⁠소';

  @override
  String get commonShieldedBalance => '차⁠폐 잔⁠액';

  @override
  String get commonShieldedSuccessfully => '차⁠폐⁠했⁠어⁠요';

  @override
  String get commonShielding => '차⁠폐⁠하⁠는 중...';

  @override
  String get commonShowFullAddress => '전⁠체 주⁠소 보⁠기';

  @override
  String get commonSigningCancelledBeforeParams =>
      '증⁠명 매⁠개⁠변⁠수⁠를 내⁠려⁠받⁠기 전⁠에 서⁠명⁠이 취⁠소⁠됐⁠어⁠요.';

  @override
  String get commonSigningExpired => '거⁠래⁠가 서⁠명⁠되⁠기 전⁠에 만⁠료⁠됐⁠어⁠요.';

  @override
  String get commonSlippageTolerance => '슬⁠리⁠피⁠지 허⁠용⁠치';

  @override
  String get commonSupportVizor => 'Vizor 후⁠원⁠하⁠기';

  @override
  String get commonSwapFailed => '스⁠왑 실⁠패';

  @override
  String get commonSwapFee => '스⁠왑 수⁠수⁠료';

  @override
  String get commonSwapProgress => '스⁠왑 진⁠행 상⁠황';

  @override
  String get commonSwapRefunded => '스⁠왑 환⁠불⁠됨';

  @override
  String commonSymbolRecipient(String symbol) {
    return '$symbol 수⁠신⁠자';
  }

  @override
  String commonSymbolRefundAddress(String symbol) {
    return '$symbol 환⁠불 주⁠소';
  }

  @override
  String get commonTimestamp => '일⁠시';

  @override
  String get commonTo => '받⁠는 사⁠람';

  @override
  String commonToAddressOnChain(String address, String chain) {
    return '받⁠는 주⁠소: $address ($chain)';
  }

  @override
  String get commonToggleFlashlight => '손⁠전⁠등 켜⁠기/끄⁠기';

  @override
  String get commonTransactionExpired => '거⁠래⁠가 만⁠료⁠됐⁠어⁠요';

  @override
  String get commonTransactionHashCopied => '거⁠래 해⁠시⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get commonTransparentAddress => '투⁠명 주⁠소';

  @override
  String get commonTryAgain => '다⁠시 시⁠도';

  @override
  String get commonTxId => '거⁠래 ID';

  @override
  String get commonUnlockVizor => 'Vizor 잠⁠금 해⁠제';

  @override
  String get commonUpdate => '변⁠경';

  @override
  String get commonUpdating => '변⁠경 중...';

  @override
  String get commonWelcomeBack => '다⁠시 오⁠신 것⁠을 환⁠영⁠해⁠요';

  @override
  String get commonYouPay => '내⁠가 보⁠내⁠는 금⁠액';

  @override
  String get commonYourePaying => '지⁠불⁠하⁠는 금⁠액';

  @override
  String get commonYoureReceiving => '받⁠는 금⁠액';

  @override
  String get commonZcashAddress => 'Zcash 주⁠소';

  @override
  String get donationDonatingTo => '기⁠부 대⁠상';

  @override
  String get donationEnterAmount => '금⁠액⁠을 입⁠력⁠하⁠세⁠요';

  @override
  String get donationPriceUnavailable => '가⁠격⁠을 불⁠러⁠올 수 없⁠어⁠요';

  @override
  String get donationReviewAmountTitle => '금⁠액 확⁠인';

  @override
  String get donationSendingFrom => '보⁠내⁠는 곳';

  @override
  String get donationSendingFromYour => '보⁠내⁠는 곳:';

  @override
  String get donationSwitchCurrency => 'ZEC⁠와 USD 전⁠환';

  @override
  String get donationThanksTitle => 'Vizor⁠를 후⁠원⁠해 주⁠셔⁠서 감⁠사⁠해⁠요';

  @override
  String get donationTotal => '합⁠계';

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
  String get homeShieldErrorBroadcastFailed =>
      '차⁠폐 거⁠래⁠를 전⁠송⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get homeShieldErrorCouldNotShield =>
      '잔⁠액⁠을 차⁠폐⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get homeShieldErrorGeneric =>
      '잔⁠액⁠을 차⁠폐⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get homeShieldErrorNotFinalized => '차⁠폐 거⁠래⁠를 마⁠무⁠리⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get homeShieldErrorSeedUnavailable =>
      '이 계⁠정⁠의 복⁠구 문⁠구⁠를 사⁠용⁠할 수 없⁠어⁠요.';

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
  String get homeShieldErrorWaitForSync => '동⁠기⁠화⁠가 끝⁠난 뒤 차⁠폐⁠해 주⁠세⁠요.';

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
  String get homeShieldNow => '지⁠금 차⁠폐⁠하⁠기';

  @override
  String get homeShieldQueuedForRetry =>
      '차⁠폐⁠를 다⁠시 시⁠도⁠하⁠도⁠록 대⁠기⁠열⁠에 넣⁠었⁠어⁠요. 활⁠동⁠에⁠서 확⁠인⁠해 주⁠세⁠요.';

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
  String get homeShieldWaitingForPrivateRecovery =>
      '비⁠공⁠개 복⁠구⁠가 최⁠신 블⁠록⁠을 따⁠라⁠잡⁠는 중⁠이⁠에⁠요. 잠⁠시 후 다⁠시 시⁠도⁠해 주⁠세⁠요. Keystone 서⁠명⁠은 그⁠대⁠로 보⁠관⁠돼⁠요.';

  @override
  String get homeShieldingBalance => '잔⁠액⁠을 차⁠폐⁠하⁠는 중…';

  @override
  String homeTransparentBalance(String balance) {
    return '투⁠명: $balance';
  }

  @override
  String homeTransparentLastKnown(String amount) {
    return '$amount (마⁠지⁠막 확⁠인)';
  }

  @override
  String homeTransparentLastKnownStopped(String amount) {
    return '$amount (마⁠지⁠막 확⁠인, 복⁠구 중⁠단⁠됨)';
  }

  @override
  String get homeTransparentRecoveryStopped => '복⁠구 중⁠단⁠됨';

  @override
  String get homeTransparentStopLegacyDiscrepancy =>
      '이⁠전⁠의 공⁠개 기⁠록⁠이 비⁠공⁠개 복⁠구 결⁠과⁠와 맞⁠지 않⁠아⁠요. 비⁠공⁠개 조⁠회⁠를 끄⁠면 비⁠공⁠개⁠로 복⁠구⁠한 기⁠록⁠을 버⁠리⁠고 투⁠명 자⁠금⁠을 공⁠개⁠적⁠으⁠로 조⁠회⁠해⁠요.';

  @override
  String get homeTransparentStopOptOutUnfinished =>
      '비⁠공⁠개 조⁠회 끄⁠기⁠가 완⁠료⁠되⁠지 않⁠았⁠어⁠요. 설⁠정⁠에⁠서 다⁠시 끄⁠면 투⁠명 자⁠금⁠을 공⁠개⁠적⁠으⁠로 조⁠회⁠해⁠요.';

  @override
  String get homeTransparentStopQuarantined =>
      '비⁠공⁠개 복⁠구⁠에⁠서 이 계⁠정⁠의 기⁠록⁠이 서⁠로 맞⁠지 않⁠는 것⁠을 발⁠견⁠했⁠어⁠요. 비⁠공⁠개 조⁠회⁠를 끄⁠면 비⁠공⁠개⁠로 복⁠구⁠한 기⁠록⁠을 버⁠리⁠고 투⁠명 자⁠금⁠을 공⁠개⁠적⁠으⁠로 조⁠회⁠해⁠요.';

  @override
  String get homeTransparentStopStalled =>
      '이 계⁠정⁠의 비⁠공⁠개 복⁠구⁠가 진⁠행⁠되⁠지 않⁠고 있⁠어⁠요. Vizor⁠가 나⁠중⁠에 다⁠시 시⁠도⁠해⁠요.';

  @override
  String get homeTransparentStopWithdrawn =>
      '비⁠공⁠개 복⁠구 서⁠비⁠스⁠가 이 계⁠정⁠의 데⁠이⁠터⁠를 철⁠회⁠했⁠어⁠요. Vizor⁠가 나⁠중⁠에 다⁠시 시⁠도⁠해⁠요.';

  @override
  String get homeTransparentUnavailable => '확⁠인⁠할 수 없⁠음';

  @override
  String get homeVotingSemantics => '코⁠인 보⁠유⁠자 투⁠표 열⁠기';

  @override
  String get homeVotingSubtitle => '네⁠트⁠워⁠크⁠의 방⁠향⁠을 함⁠께 정⁠해⁠요';

  @override
  String get incomingLinkGiftBusy =>
      '이 기⁠프⁠트 카⁠드⁠를 열⁠려⁠면 진⁠행 중⁠인 작⁠업⁠을 끝⁠내⁠거⁠나 취⁠소⁠해 주⁠세⁠요.';

  @override
  String get incomingLinkGiftSetup =>
      '이 기⁠프⁠트 카⁠드⁠를 열⁠려⁠면 계⁠정 설⁠정⁠을 마⁠쳐 주⁠세⁠요.';

  @override
  String get incomingLinkHomeBusy =>
      '작⁠업⁠을 끝⁠내⁠거⁠나 취⁠소⁠한 다⁠음 링⁠크⁠를 다⁠시 열⁠어 주⁠세⁠요.';

  @override
  String get incomingLinkHomeSetup => '계⁠정 설⁠정⁠을 마⁠친 다⁠음 링⁠크⁠를 다⁠시 열⁠어 주⁠세⁠요.';

  @override
  String get incomingLinkPaymentBusy =>
      '이 결⁠제 요⁠청⁠을 열⁠려⁠면 진⁠행 중⁠인 작⁠업⁠을 끝⁠내⁠거⁠나 취⁠소⁠해 주⁠세⁠요.';

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
  String get keystoneAllowCamera => '카⁠메⁠라 허⁠용';

  @override
  String get keystoneBatchCannotSignDeposit =>
      '이 입⁠금⁠에⁠는 Keystone 일⁠괄 서⁠명⁠으⁠로 서⁠명⁠할 수 없⁠는 입⁠력⁠이 있⁠어⁠요.';

  @override
  String get keystoneBatchCannotSignTx =>
      '이 거⁠래⁠에⁠는 Keystone 일⁠괄 서⁠명⁠으⁠로 서⁠명⁠할 수 없⁠는 입⁠력⁠이 있⁠어⁠요.';

  @override
  String get keystoneBatchTooManyInputsDeposit =>
      '이 입⁠금⁠은 Keystone 일⁠괄 서⁠명⁠을 하⁠기⁠엔 입⁠력⁠이 너⁠무 많⁠아⁠요. 더 적⁠은 금⁠액⁠으⁠로 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneBatchTooManyInputsTx =>
      '이 거⁠래⁠는 Keystone 일⁠괄 서⁠명⁠을 하⁠기⁠엔 입⁠력⁠이 너⁠무 많⁠아⁠요. 더 적⁠은 금⁠액⁠으⁠로 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneBirthdayInvalidHeight => '올⁠바⁠른 블⁠록 높⁠이⁠가 아⁠닌 것 같⁠아⁠요.';

  @override
  String get keystoneBirthdaySubtitle => '알⁠려 주⁠시⁠면 지⁠갑⁠을 더 빨⁠리 가⁠져⁠올 수 있⁠어⁠요.';

  @override
  String get keystoneCameraDefault => '기⁠본';

  @override
  String get keystoneCameraDeniedTitle => '카⁠메⁠라 접⁠근⁠을 거⁠부⁠했⁠어⁠요';

  @override
  String get keystoneCameraEnableBody =>
      'Keystone⁠을 연⁠결⁠하⁠려⁠면 카⁠메⁠라⁠가 필⁠요⁠해⁠요.\n나⁠중⁠에 설⁠정⁠에⁠서 언⁠제⁠든 되⁠돌⁠릴 수 있⁠어⁠요.';

  @override
  String get keystoneCameraEnableTitle => '카⁠메⁠라 접⁠근 허⁠용';

  @override
  String get keystoneCameraExternal => '외⁠장';

  @override
  String get keystoneCameraFront => '전⁠면';

  @override
  String get keystoneCameraGiftBody =>
      '기⁠프⁠트 카⁠드 QR 코⁠드⁠를 스⁠캔⁠하⁠려⁠면 카⁠메⁠라⁠가 필⁠요⁠해⁠요.\n나⁠중⁠에 설⁠정⁠에⁠서 언⁠제⁠든⁠지 되⁠돌⁠릴 수 있⁠어⁠요.';

  @override
  String get keystoneCameraLabel => '카⁠메⁠라';

  @override
  String keystoneCameraNameDefault(String name) {
    return '$name (기⁠본)';
  }

  @override
  String get keystoneCameraNormal => '일⁠반';

  @override
  String get keystoneCameraOffAllow =>
      '카⁠메⁠라 접⁠근⁠이 꺼⁠져 있⁠어⁠요. Keystone 서⁠명⁠을 스⁠캔⁠하⁠려⁠면 설⁠정⁠에⁠서 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone 가⁠져⁠오⁠기⁠는 카⁠메⁠라 QR 스⁠캔⁠만 지⁠원⁠해⁠요.\n카⁠메⁠라⁠를 연⁠결⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneCameraWide => '광⁠각';

  @override
  String get keystoneCameraZoom => '줌';

  @override
  String get keystoneConfirmSelection => '선⁠택 확⁠인';

  @override
  String get keystoneConfirmWithKeystone => 'Keystone⁠으⁠로 확⁠인';

  @override
  String get keystoneDefaultCamera => '기⁠본 카⁠메⁠라';

  @override
  String get keystoneFirmwareBody =>
      'Keystone⁠이 최⁠신 Cypherpunk 펌⁠웨⁠어⁠인⁠지 확⁠인⁠해 주⁠세⁠요. ';

  @override
  String get keystoneFirmwareDownloadSemantics => 'Keystone 펌⁠웨⁠어 다⁠운⁠로⁠드';

  @override
  String get keystoneFirmwareLinkLabel => '링⁠크';

  @override
  String get keystoneFirmwareOpenPage => 'Keystone 펌⁠웨⁠어 페⁠이⁠지 열⁠기';

  @override
  String get keystoneFirmwareTitle => 'Keystone 펌⁠웨⁠어 확⁠인';

  @override
  String get keystoneFirmwareUpdatePrefix =>
      '최⁠신 Keystone 펌⁠웨⁠어⁠로 업⁠데⁠이⁠트⁠하⁠세⁠요: ';

  @override
  String get keystoneImReadyNow => '준⁠비⁠됐⁠어⁠요';

  @override
  String get keystoneLoadingCamera => '카⁠메⁠라⁠를 불⁠러⁠오⁠는 중...';

  @override
  String get keystoneLoadingQrCode => 'QR 코⁠드⁠를 불⁠러⁠오⁠는 중 ...';

  @override
  String get keystoneNextStep => '다⁠음 단⁠계';

  @override
  String get keystoneNoCameraFound => '카⁠메⁠라⁠를 찾⁠을 수 없⁠어⁠요';

  @override
  String get keystoneNoCameraOpened =>
      '열 수 있⁠는 카⁠메⁠라⁠가 없⁠어⁠요. 카⁠메⁠라⁠가 연⁠결⁠되⁠어 있⁠고 다⁠른 앱⁠에⁠서 사⁠용 중⁠이 아⁠닌⁠지 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get keystoneOnVizor => 'Vizor⁠에⁠서';

  @override
  String get keystoneOnYourKeystone => 'Keystone⁠에⁠서';

  @override
  String get keystoneOpenSettings => '설⁠정 열⁠기';

  @override
  String get keystoneOpenSignedQr =>
      'Keystone⁠에⁠서 서⁠명⁠된 거⁠래 QR⁠을 연 다⁠음 다⁠시 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String get keystonePcztPrepareFailed => 'Keystone 서⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get keystonePrepareSubtitle => 'Keystone 지⁠갑⁠을 준⁠비⁠해 주⁠세⁠요';

  @override
  String get keystonePrepareToConnectTitle => '연⁠결 준⁠비';

  @override
  String get keystonePreparingQr => 'QR 준⁠비 중';

  @override
  String get keystoneReadingQr => 'QR⁠을 읽⁠는 중...';

  @override
  String get keystoneReadingSignature => '서⁠명⁠을 읽⁠는 중...';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone 가⁠져⁠오⁠기⁠는 카⁠메⁠라⁠로 QR⁠을 스⁠캔⁠하⁠는 방⁠식⁠만 지⁠원⁠해⁠요. 카⁠메⁠라⁠를 연⁠결⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get keystoneScanCaption => 'Keystone 계⁠정 QR⁠을 스⁠캔⁠하⁠세⁠요';

  @override
  String get keystoneScanCaptionConfirm =>
      '확⁠인⁠하⁠려⁠면 Keystone⁠의 QR 코⁠드⁠를 스⁠캔⁠해 주⁠세⁠요';

  @override
  String get keystoneScanDecodeFailed =>
      '이 QR 코⁠드⁠를 Keystone Zcash 계⁠정⁠으⁠로 읽⁠지 못⁠했⁠어⁠요.';

  @override
  String get keystoneScanHelpClose => '스⁠캔 도⁠움⁠말 닫⁠기';

  @override
  String get keystoneScanIssuesTitle => '스⁠캔⁠에 문⁠제⁠가 있⁠나⁠요?';

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
  String get keystoneScanPromptOnKeystone => 'Keystone⁠에⁠서 누⁠른 뒤,';

  @override
  String get keystoneScanPromptTap => '다⁠음 버⁠튼⁠을';

  @override
  String get keystoneScanPromptThenScan => '이 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get keystoneScanReadingAccounts => '계⁠정⁠을 읽⁠는 중...';

  @override
  String get keystoneScanWithKeystone => 'Keystone⁠으⁠로 스⁠캔';

  @override
  String get keystoneSelectCamera => '카⁠메⁠라 선⁠택';

  @override
  String get keystoneShowTransactionQr => '거⁠래 QR 보⁠기';

  @override
  String get keystoneSignatureQrNotDecoded =>
      '이 QR 코⁠드⁠를 Keystone 서⁠명⁠으⁠로 해⁠석⁠할 수 없⁠어⁠요.';

  @override
  String get keystoneStepHowToConnect => '연⁠결 방⁠법';

  @override
  String get keystoneStepOneOfTwo => '1/2⁠단⁠계';

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
  String get keystoneStepTwoOfTwo => '2/2⁠단⁠계';

  @override
  String get keystoneSubmittingTransaction => '거⁠래⁠를 제⁠출⁠하⁠는 중';

  @override
  String get keystoneTipContinuityCamera =>
      'Mac⁠에⁠서⁠는 연⁠속⁠성 카⁠메⁠라⁠를 사⁠용⁠해 iPhone⁠으⁠로 대⁠신 스⁠캔⁠할 수 있⁠어⁠요.';

  @override
  String get keystoneTipGiftFullScreen =>
      '다⁠른 기⁠기⁠에⁠서 기⁠프⁠트 카⁠드 QR 코⁠드⁠를 전⁠체 화⁠면⁠으⁠로 열⁠어 보⁠세⁠요.';

  @override
  String get keystoneTipGiftMoveFurther =>
      '카⁠메⁠라⁠가 초⁠점⁠을 맞⁠출 수 있⁠도⁠록 QR 코⁠드⁠를 카⁠메⁠라⁠에⁠서 몇 인⁠치 더 멀⁠리 떨⁠어⁠뜨⁠려 보⁠세⁠요.';

  @override
  String get keystoneTipGlare =>
      '방⁠이 충⁠분⁠히 밝⁠고 QR 코⁠드⁠에 빛⁠이 반⁠사⁠되⁠지 않⁠는⁠지 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get keystoneTipMoveKeystoneFurther =>
      '카⁠메⁠라⁠가 초⁠점⁠을 맞⁠출 수 있⁠도⁠록 Keystone⁠을 카⁠메⁠라⁠에⁠서 몇 인⁠치 더 멀⁠리 떨⁠어⁠뜨⁠려 보⁠세⁠요.';

  @override
  String get keystoneTipTapFullScreen =>
      'Keystone⁠의 QR 코⁠드⁠를 눌⁠러 전⁠체 화⁠면⁠으⁠로 표⁠시⁠해 보⁠세⁠요. 가⁠장 쉬⁠운 해⁠결 방⁠법⁠이⁠에⁠요.';

  @override
  String get keystoneTroubleScanning => '스⁠캔⁠이 안 되⁠나⁠요?';

  @override
  String get keystoneTryAgainWithKeystone => 'Keystone⁠으⁠로 다⁠시 시⁠도';

  @override
  String get keystoneWindowsCameraBody =>
      'Windows 설⁠정⁠에⁠서 카⁠메⁠라 접⁠근⁠과 데⁠스⁠크⁠톱 앱⁠의 카⁠메⁠라 접⁠근 허⁠용⁠을 켜 주⁠세⁠요.';

  @override
  String get keystoneWindowsCameraTitle => 'Windows 카⁠메⁠라 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요';

  @override
  String languageSystemOption(String language) {
    return '시⁠스⁠템 ($language)';
  }

  @override
  String get ledgerAccountIndexFieldLabel => 'Ledger 계⁠정 인⁠덱⁠스 (0–100)';

  @override
  String get ledgerAccountIndexHint =>
      '이 Ledger 계⁠정⁠에 다⁠른 인⁠덱⁠스⁠를 사⁠용⁠한 적⁠이 없⁠다⁠면 0⁠으⁠로 두⁠세⁠요.';

  @override
  String get ledgerAccountIndexLabel => '계⁠정 인⁠덱⁠스 (0–100)';

  @override
  String get ledgerAccountIndexOutOfRange =>
      '계⁠정 인⁠덱⁠스⁠는 0⁠에⁠서 100 사⁠이⁠여⁠야 해⁠요.';

  @override
  String get ledgerAddAccountNote =>
      'Vizor⁠에⁠서 잔⁠액⁠과 활⁠동⁠을 볼 수 있⁠어⁠요. 거⁠래⁠는 여⁠전⁠히 Ledger⁠에⁠서 승⁠인⁠해⁠야 해⁠요.';

  @override
  String get ledgerAddAccountTitle => 'Ledger 계⁠정 추⁠가';

  @override
  String get ledgerAdvancedOptions => '고⁠급 옵⁠션';

  @override
  String ledgerAppSemanticsLabel(String appName) {
    return '$appName 앱';
  }

  @override
  String get ledgerAppUpdateRequiredTitle => 'Ledger 앱 업⁠데⁠이⁠트⁠가 필⁠요⁠해⁠요';

  @override
  String get ledgerApproveShareViewingKey =>
      'Vizor⁠와 뷰⁠잉 키⁠를 공⁠유⁠하⁠는 것⁠을 승⁠인⁠해 주⁠세⁠요.';

  @override
  String ledgerApproveShareViewingKeyForAccount(String number) {
    return '계⁠정 #$number⁠의 뷰⁠잉 키 공⁠유⁠를 승⁠인⁠해 주⁠세⁠요.';
  }

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
  String get ledgerBluetoothModelsList => 'Nano X, Flex, Stax, Nano Gen5';

  @override
  String get ledgerBluetoothPermissionRequired =>
      'Ledger⁠를 찾⁠으⁠려⁠면 블⁠루⁠투⁠스 권⁠한⁠이 필⁠요⁠해⁠요. 설⁠정⁠에⁠서 허⁠용⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtAccessAllowed =>
      '권⁠한⁠이 허⁠용⁠돼 있⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtAccessBluetoothRequestable =>
      'Ledger⁠에 연⁠결⁠하⁠려⁠면 \'권⁠한 허⁠용\'을 선⁠택⁠해 주⁠세⁠요. 안⁠내⁠가 나⁠타⁠나⁠지 않⁠으⁠면 설⁠정⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerBtAccessBluetoothSettings =>
      '기⁠기 설⁠정⁠에⁠서 Vizor⁠의 Bluetooth 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtAccessKindLocation => '위⁠치';

  @override
  String get ledgerBtAccessLocationRequestable =>
      '이 Android 버⁠전⁠에⁠서 Ledger⁠를 찾⁠으⁠려⁠면 위⁠치 권⁠한⁠이 필⁠요⁠해⁠요. \'권⁠한 허⁠용\'을 선⁠택⁠하⁠거⁠나, 안⁠내⁠가 나⁠타⁠나⁠지 않⁠으⁠면 설⁠정⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerBtAccessLocationSettings =>
      '이 Android 버⁠전⁠에⁠서 Ledger⁠를 찾⁠으⁠려⁠면 위⁠치 권⁠한⁠이 필⁠요⁠해⁠요. 설⁠정⁠에⁠서 Vizor⁠의 위⁠치 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtAccessMacosSettings =>
      '시⁠스⁠템 설⁠정 > 개⁠인⁠정⁠보 보⁠호 및 보⁠안 > Bluetooth⁠를 열⁠고 Vizor⁠의 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String ledgerBtAccessRestricted(String kind) {
    return '$kind 접⁠근⁠이 기⁠기 설⁠정 또⁠는 관⁠리⁠자⁠에 의⁠해 제⁠한⁠돼 있⁠어⁠요.';
  }

  @override
  String get ledgerBtAccessTurnOnBluetooth =>
      'Bluetooth⁠를 켠 뒤 접⁠근 권⁠한⁠을 다⁠시 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtAccessTurnOnLocation =>
      '위⁠치 서⁠비⁠스⁠를 켠 뒤 접⁠근 권⁠한⁠을 다⁠시 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtCouldNotCheckAccess =>
      '접⁠근 권⁠한⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 설⁠정⁠을 직⁠접 열⁠고 다⁠시 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtCouldNotOpenSettingsAllow =>
      '설⁠정⁠을 열 수 없⁠어⁠요. 기⁠기 설⁠정⁠을 직⁠접 열⁠어 Vizor⁠의 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtCouldNotOpenSettingsRestricted =>
      '설⁠정⁠을 열 수 없⁠어⁠요. 기⁠기 설⁠정⁠을 직⁠접 열⁠어 Vizor⁠의 접⁠근 권⁠한⁠을 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtLabelAllowAccess => '접⁠근 허⁠용';

  @override
  String get ledgerBtLabelCheckAgain => '다⁠시 확⁠인';

  @override
  String get ledgerBtLabelChecking => '접⁠근 권⁠한 확⁠인 중';

  @override
  String get ledgerBtLabelOpenSettings => '설⁠정 열⁠기';

  @override
  String get ledgerBtLabelReconnect => '다⁠시 연⁠결';

  @override
  String get ledgerBtMsgBluetoothNeeded =>
      'Ledger⁠에 연⁠결⁠하⁠려⁠면 Vizor⁠에 Bluetooth 접⁠근 권⁠한⁠이 필⁠요⁠해⁠요.';

  @override
  String get ledgerBtMsgChecking =>
      'Vizor⁠가 Ledger⁠에 연⁠결⁠할 수 있⁠는⁠지 확⁠인⁠하⁠고 있⁠어⁠요.';

  @override
  String get ledgerBtMsgLocationNeeded =>
      '이 Android 버⁠전⁠에⁠서 Ledger⁠를 찾⁠으⁠려⁠면 위⁠치 접⁠근⁠이 필⁠요⁠해⁠요.';

  @override
  String get ledgerBtMsgReady => '계⁠속⁠하⁠려⁠면 Ledger⁠를 켜⁠고 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtRestrictedGeneric =>
      '설⁠정⁠에⁠서 Vizor⁠의 Bluetooth 접⁠근⁠을 확⁠인⁠해 주⁠세⁠요. 기⁠기 제⁠한⁠이⁠나 관⁠리⁠자⁠가 변⁠경⁠을 막⁠을 수 있⁠어⁠요.';

  @override
  String get ledgerBtRestrictedLocation =>
      '설⁠정⁠에⁠서 Vizor⁠의 위⁠치 접⁠근⁠을 확⁠인⁠해 주⁠세⁠요. 기⁠기 제⁠한⁠이⁠나 관⁠리⁠자⁠가 변⁠경⁠을 막⁠을 수 있⁠어⁠요.';

  @override
  String get ledgerBtRestrictedMacos =>
      '시⁠스⁠템 설⁠정⁠의 개⁠인⁠정⁠보 보⁠호 및 보⁠안 > Bluetooth⁠를 확⁠인⁠해 주⁠세⁠요. 이 제⁠한⁠은 관⁠리⁠자⁠가 변⁠경⁠해⁠야 할 수 있⁠어⁠요.';

  @override
  String get ledgerBtRestrictedNearby =>
      '설⁠정⁠에⁠서 Vizor⁠의 근⁠처 기⁠기 접⁠근⁠을 확⁠인⁠해 주⁠세⁠요. 기⁠기 제⁠한⁠이⁠나 관⁠리⁠자⁠가 변⁠경⁠을 막⁠을 수 있⁠어⁠요.';

  @override
  String get ledgerBtSheetAllowAddAccount =>
      '계⁠정⁠을 추⁠가⁠하⁠려⁠면 휴⁠대⁠폰 설⁠정⁠에⁠서 Vizor⁠의 Bluetooth 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtSheetAllowContinue =>
      '계⁠속⁠하⁠려⁠면 휴⁠대⁠폰 설⁠정⁠에⁠서 Vizor⁠의 Bluetooth 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtSheetAllowSigning =>
      '서⁠명⁠을 이⁠어⁠가⁠려⁠면 휴⁠대⁠폰 설⁠정⁠에⁠서 Vizor⁠의 Bluetooth 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtSheetReadyAddAccount =>
      'Bluetooth⁠를 사⁠용⁠할 수 있⁠어⁠요. 계⁠정⁠을 추⁠가⁠하⁠려⁠면 Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtSheetReadyContinue =>
      'Bluetooth⁠를 사⁠용⁠할 수 있⁠어⁠요. 계⁠속⁠하⁠려⁠면 Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtSheetReadySigning =>
      'Bluetooth⁠를 사⁠용⁠할 수 있⁠어⁠요. 서⁠명⁠을 이⁠어⁠가⁠려⁠면 Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerBtSheetTurnOnAddAccount =>
      '계⁠정⁠을 추⁠가⁠하⁠려⁠면 휴⁠대⁠폰⁠의 Bluetooth⁠를 켜 주⁠세⁠요.';

  @override
  String get ledgerBtSheetTurnOnContinue =>
      '계⁠속⁠하⁠려⁠면 휴⁠대⁠폰⁠의 Bluetooth⁠를 켜 주⁠세⁠요.';

  @override
  String get ledgerBtSheetTurnOnSigning =>
      '서⁠명⁠을 이⁠어⁠가⁠려⁠면 휴⁠대⁠폰⁠의 Bluetooth⁠를 켜 주⁠세⁠요.';

  @override
  String get ledgerBtTitleAllowBluetooth => 'Bluetooth 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요';

  @override
  String get ledgerBtTitleAllowBluetoothSettings =>
      '설⁠정⁠에⁠서 Bluetooth⁠를 허⁠용⁠해 주⁠세⁠요';

  @override
  String get ledgerBtTitleAllowLocation => '위⁠치 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요';

  @override
  String get ledgerBtTitleAllowLocationSettings => '설⁠정⁠에⁠서 위⁠치⁠를 허⁠용⁠해 주⁠세⁠요';

  @override
  String get ledgerBtTitleChecking => 'Bluetooth 접⁠근 권⁠한⁠을 확⁠인⁠하⁠는 중';

  @override
  String get ledgerBtTitleReady => '다⁠시 연⁠결⁠할 준⁠비⁠가 됐⁠어⁠요';

  @override
  String get ledgerBtTitleRestricted => '접⁠근⁠이 제⁠한⁠되⁠어 있⁠어⁠요';

  @override
  String get ledgerBtTitleTurnOnBluetooth => 'Bluetooth⁠를 켜 주⁠세⁠요';

  @override
  String get ledgerBtTitleTurnOnLocation => '위⁠치 서⁠비⁠스⁠를 켜 주⁠세⁠요';

  @override
  String get ledgerButtonCheckingAccount => '계⁠정 확⁠인 중';

  @override
  String get ledgerButtonConnecting => '연⁠결 중';

  @override
  String get ledgerButtonSaving => '저⁠장 중';

  @override
  String get ledgerButtonSearching => '검⁠색 중';

  @override
  String get ledgerCancelFailed => '취⁠소⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerCancelShielding => '차⁠폐 취⁠소';

  @override
  String get ledgerCancellingRequest => '요⁠청⁠을 취⁠소⁠하⁠는 중';

  @override
  String get ledgerCancellingTheRequest => 'Ledger 요⁠청⁠을 취⁠소⁠하⁠는 중…';

  @override
  String get ledgerCapabilityMainnetOnly =>
      'Ledger⁠는 현⁠재 Zcash 메⁠인⁠넷⁠에⁠서⁠만 지⁠원⁠돼⁠요.';

  @override
  String get ledgerCapabilityUnsupportedPlatform =>
      'Vizor⁠에⁠서 Ledger⁠는 macOS, Windows, Linux, iOS, Android⁠에⁠서 지⁠원⁠돼⁠요.';

  @override
  String get ledgerChangedKeepOne =>
      'Ledger⁠가 바⁠뀌⁠었⁠어⁠요. Ledger⁠를 하⁠나⁠만 연⁠결⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerCheckingBluetoothAccess => '블⁠루⁠투⁠스 접⁠근 권⁠한⁠을 확⁠인⁠하⁠는 중…';

  @override
  String get ledgerCheckingUsb => 'USB 연⁠결⁠을 확⁠인⁠하⁠는 중…';

  @override
  String get ledgerChooseAnother => '다⁠른 Ledger 선⁠택';

  @override
  String get ledgerChooseConnection => '연⁠결 방⁠법 선⁠택';

  @override
  String get ledgerChooseDevice => '계⁠속⁠하⁠려⁠면 기⁠기⁠를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get ledgerChooseLedgerForAccount =>
      '이 계⁠정⁠에 사⁠용⁠할 Ledger⁠를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get ledgerCleanupFailed => '정⁠리⁠를 마⁠치⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerComeBackFindLedger =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 둔 채⁠로 아⁠래⁠의 \'Ledger 찾⁠기\'를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get ledgerComeBackFindMyLedger =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 둔 채⁠로 아⁠래⁠의 \'Ledger 찾⁠기\'를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get ledgerComeBackReconnect => '돌⁠아⁠와⁠서 다⁠시 연⁠결';

  @override
  String get ledgerCompletePairingOpenZcash =>
      '안⁠내⁠가 나⁠타⁠나⁠면 페⁠어⁠링⁠을 완⁠료⁠한 뒤 Zcash 앱⁠을 열⁠고 뷰⁠잉 키 공⁠유⁠를 승⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerConfirmOpeningZcash => 'Ledger⁠에⁠서 Zcash 열⁠기⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get ledgerConnectForAccount => '이 계⁠정⁠의 Ledger⁠를 연⁠결⁠해 주⁠세⁠요.';

  @override
  String get ledgerConnectSubtitle => 'Ledger 지⁠갑⁠을 준⁠비⁠해 주⁠세⁠요.';

  @override
  String get ledgerConnectTitle => 'Ledger 연⁠결';

  @override
  String get ledgerConnectUsbCable => 'USB 케⁠이⁠블⁠로 연⁠결⁠하⁠세⁠요.';

  @override
  String ledgerConnectingTo(String device) {
    return '$device⁠에 연⁠결⁠하⁠는 중';
  }

  @override
  String get ledgerConnectionHelp => '연⁠결 도⁠움⁠말';

  @override
  String get ledgerContinueSigning => '서⁠명 이⁠어⁠가⁠기';

  @override
  String get ledgerCouldNotConnect => 'Ledger⁠를 연⁠결⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get ledgerCouldNotStopSearchTryAgain =>
      '검⁠색⁠을 중⁠지⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerDifferentFromSaved => '저⁠장⁠된 연⁠결⁠과 달⁠라⁠요';

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
  String ledgerFailureMsgAppUpdateRequired(String version) {
    return 'Ledger Wallet⁠에⁠서 Ledger⁠와 Zcash 앱⁠을 $version 이⁠상⁠으⁠로 업⁠데⁠이⁠트⁠해 주⁠세⁠요.';
  }

  @override
  String get ledgerFailureMsgBusy =>
      'Ledger⁠가 사⁠용 중⁠이⁠에⁠요. 잠⁠시 후 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgCancelledTryAgain =>
      '요⁠청⁠이 취⁠소⁠됐⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgCheckOpenZcash =>
      'Ledger⁠를 확⁠인⁠하⁠고 Zcash 앱⁠을 연 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgDeclined =>
      'Ledger⁠에⁠서 거⁠부⁠했⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgGiftCardRejected =>
      'Ledger⁠가 이 요⁠청⁠을 수⁠락⁠하⁠지 못⁠했⁠어⁠요. 새 기⁠프⁠트 카⁠드⁠를 만⁠들⁠어 주⁠세⁠요. 아⁠무⁠것⁠도 전⁠송⁠되⁠지 않⁠았⁠어⁠요.';

  @override
  String get ledgerFailureMsgGiftCardTooLarge =>
      'Ledger⁠가 처⁠리⁠하⁠기⁠엔 너⁠무 커⁠요. 더 적⁠은 금⁠액⁠으⁠로 기⁠프⁠트 카⁠드⁠를 만⁠들⁠어 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgInstallZcash =>
      'Ledger Wallet⁠으⁠로 Zcash 앱⁠을 설⁠치⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgMemoHashUnsupported =>
      '비⁠영⁠어 메⁠모⁠에 서⁠명⁠하⁠려⁠면 Ledger⁠의 Zcash 앱⁠을 업⁠데⁠이⁠트⁠해 주⁠세⁠요';

  @override
  String get ledgerFailureMsgMigrationTooLarge =>
      '이 마⁠이⁠그⁠레⁠이⁠션 단⁠계⁠는 Ledger⁠가 서⁠명⁠하⁠기⁠엔 너⁠무 커⁠요. Vizor⁠는 아⁠직 나⁠눌 수 없⁠어⁠요.';

  @override
  String get ledgerFailureMsgOpenZcash => 'Ledger⁠에⁠서 Zcash 앱⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgOrchardChange =>
      'Ledger⁠는 Orchard⁠에 잔⁠돈⁠이 남⁠는 거⁠래⁠에 서⁠명⁠할 수 없⁠어⁠요. 먼⁠저 Orchard 잔⁠액⁠을 Ironwood⁠로 마⁠이⁠그⁠레⁠이⁠션⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgPaymentTooLarge =>
      '새 결⁠제⁠를 시⁠작⁠해 주⁠세⁠요. 이 주⁠소⁠로 더 적⁠은 금⁠액⁠을 보⁠내⁠지 마⁠세⁠요.';

  @override
  String get ledgerFailureMsgReconnectUnlock =>
      'Ledger⁠를 다⁠시 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgRejectedNewRequest =>
      'Ledger⁠가 이 요⁠청⁠을 수⁠락⁠하⁠지 못⁠했⁠어⁠요. 새⁠로 만⁠들⁠어 주⁠세⁠요. 아⁠무⁠것⁠도 전⁠송⁠되⁠지 않⁠았⁠어⁠요.';

  @override
  String get ledgerFailureMsgReopenZcash => 'Zcash 앱⁠을 닫⁠았⁠다⁠가 다⁠시 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgSaplingRecipient =>
      'Ledger⁠는 Sapling 주⁠소⁠로 보⁠낼 수 없⁠어⁠요. 새 요⁠청⁠을 만⁠들⁠어 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgSetPin =>
      'Ledger⁠에⁠서 PIN⁠을 설⁠정⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgShieldTooLarge =>
      'Ledger⁠가 처⁠리⁠하⁠기⁠엔 입⁠력⁠이 너⁠무 많⁠아⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요. 차⁠폐⁠된 것⁠은 없⁠어⁠요.';

  @override
  String get ledgerFailureMsgSwapTooLarge =>
      '더 적⁠은 금⁠액⁠으⁠로 새 스⁠왑⁠을 시⁠작⁠해 주⁠세⁠요. 이 스⁠왑⁠은 폐⁠기⁠됐⁠어⁠요.';

  @override
  String get ledgerFailureMsgTooManyInputs =>
      'Ledger⁠가 처⁠리⁠하⁠기⁠엔 입⁠력⁠이 너⁠무 많⁠아⁠요. 더 적⁠은 금⁠액⁠으⁠로 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgUnexpected =>
      '예⁠상⁠치 못⁠한 Ledger 오⁠류⁠가 발⁠생⁠했⁠어⁠요. Zcash 앱⁠을 다⁠시 열⁠고 시⁠도⁠해 주⁠세⁠요.';

  @override
  String ledgerFailureMsgUnexpectedWithCode(String code) {
    return '예⁠상⁠치 못⁠한 Ledger 오⁠류⁠$code⁠가 발⁠생⁠했⁠어⁠요. Zcash 앱⁠을 다⁠시 열⁠고 시⁠도⁠해 주⁠세⁠요.';
  }

  @override
  String get ledgerFailureMsgUnlock =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgUnsupportedTxType =>
      'Ledger⁠는 이 거⁠래 유⁠형⁠에 서⁠명⁠할 수 없⁠어⁠요. 새 요⁠청⁠을 만⁠들⁠어 주⁠세⁠요.';

  @override
  String ledgerFailureMsgUpdateZcash(String version) {
    return 'Zcash 앱⁠을 $version 이⁠상⁠으⁠로 업⁠데⁠이⁠트⁠해 주⁠세⁠요.';
  }

  @override
  String get ledgerFailureMsgViewingKeyRejected =>
      'Ledger⁠가 이 뷰⁠잉 키 요⁠청⁠을 수⁠락⁠하⁠지 못⁠했⁠어⁠요. 계⁠정 번⁠호⁠를 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureMsgVoteRejected =>
      'Ledger⁠가 이 투⁠표 요⁠청⁠을 수⁠락⁠하⁠지 못⁠했⁠어⁠요. 투⁠표⁠가 서⁠명⁠되⁠지 않⁠았⁠어⁠요.';

  @override
  String get ledgerFailureMsgVoteTooLarge =>
      '이 투⁠표⁠는 Ledger⁠가 서⁠명⁠하⁠기⁠엔 너⁠무 커⁠요.';

  @override
  String get ledgerFailureMsgWrongLedger => '이 계⁠정⁠이 있⁠는 Ledger⁠를 연⁠결⁠해 주⁠세⁠요.';

  @override
  String get ledgerFailureTitleBusy => 'Ledger⁠가 사⁠용 중⁠이⁠에⁠요';

  @override
  String get ledgerFailureTitleCancelled => '요⁠청⁠이 취⁠소⁠됐⁠어⁠요';

  @override
  String get ledgerFailureTitleError => 'Ledger 오⁠류';

  @override
  String get ledgerFailureTitleFailed => '요⁠청⁠에 실⁠패⁠했⁠어⁠요';

  @override
  String get ledgerFailureTitleLocked => 'Ledger⁠가 잠⁠겨 있⁠어⁠요';

  @override
  String get ledgerFailureTitleNotReachable => 'Ledger⁠에 연⁠결⁠할 수 없⁠어⁠요';

  @override
  String get ledgerFailureTitleOpenZcash => 'Zcash 앱⁠을 열⁠어 주⁠세⁠요';

  @override
  String get ledgerFailureTitlePinRequired => 'PIN⁠이 필⁠요⁠해⁠요';

  @override
  String get ledgerFailureTitleRejected => '요⁠청⁠이 수⁠락⁠되⁠지 않⁠았⁠어⁠요';

  @override
  String get ledgerFailureTitleReopenZcash => 'Zcash 앱⁠을 다⁠시 열⁠어 주⁠세⁠요';

  @override
  String get ledgerFailureTitleTooLarge => '요⁠청⁠이 너⁠무 커⁠요';

  @override
  String get ledgerFailureTitleUpdateZcash => 'Zcash 앱⁠을 업⁠데⁠이⁠트⁠해 주⁠세⁠요';

  @override
  String get ledgerFailureTitleWrongLedger => '다⁠른 Ledger⁠예⁠요';

  @override
  String get ledgerFailureTitleZcashMissing => 'Zcash 앱⁠이 없⁠어⁠요';

  @override
  String get ledgerFind => 'Ledger 찾⁠기';

  @override
  String get ledgerFindMyLedger => '내 Ledger 찾⁠기';

  @override
  String get ledgerFollowPromptsOnLedger => 'Ledger⁠의 안⁠내⁠를 따⁠라 주⁠세⁠요.';

  @override
  String get ledgerHelpChecksCloseOtherApps =>
      '다⁠른 지⁠갑 앱⁠을 닫⁠고, 다⁠른 휴⁠대⁠폰⁠이⁠나 컴⁠퓨⁠터⁠에⁠서 Ledger 연⁠결⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerHelpChecksHomeScreen =>
      'Ledger⁠를 홈 화⁠면⁠에 두⁠세⁠요. Vizor⁠가 요⁠청⁠하⁠면 Zcash 앱⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerHelpChecksUnlockClose =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고 Bluetooth⁠를 켠 뒤 휴⁠대⁠폰 가⁠까⁠이⁠에 두⁠세⁠요.';

  @override
  String get ledgerHelpChooseModel => '모⁠델⁠을 선⁠택⁠해 주⁠세⁠요';

  @override
  String get ledgerHelpFindInPhoneBluetooth =>
      '휴⁠대⁠폰⁠의 Bluetooth 설⁠정⁠에⁠서 Ledger⁠를 찾⁠아 주⁠세⁠요.';

  @override
  String get ledgerHelpForgetAndroid =>
      'Bluetooth 설⁠정 > Ledger 옆⁠의 설⁠정 버⁠튼 > 삭⁠제 또⁠는 페⁠어⁠링 해⁠제';

  @override
  String get ledgerHelpForgetIos =>
      '설⁠정 > Bluetooth > Ledger 옆⁠의 정⁠보 버⁠튼 > 이 기⁠기 지⁠우⁠기';

  @override
  String get ledgerHelpKeepUnlockedHome =>
      'Ledger⁠를 잠⁠금 해⁠제⁠하⁠고 Bluetooth⁠를 켠 상⁠태⁠로 홈 화⁠면⁠에 두⁠세⁠요.';

  @override
  String get ledgerHelpModelLabel => 'Ledger 모⁠델';

  @override
  String get ledgerHelpNanoXConfirm =>
      'Ledger⁠에⁠서 확⁠인⁠하⁠고 기⁠기⁠에⁠서 PIN⁠을 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get ledgerHelpNanoXControls =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠세⁠요. 두 버⁠튼⁠을 길⁠게 눌⁠러 제⁠어 메⁠뉴⁠를 연 다⁠음 아⁠래⁠를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get ledgerHelpNanoXMenuPath => 'Settings > Security > Reset pairings';

  @override
  String get ledgerHelpNanoXName =>
      'Nano X⁠에⁠서 두 버⁠튼⁠을 2⁠초 동⁠안 누⁠른 뒤 Device Name⁠을 찾⁠아 주⁠세⁠요.';

  @override
  String get ledgerHelpNextPhoneSettings => '다⁠음: 휴⁠대⁠폰 설⁠정';

  @override
  String get ledgerHelpNextSearchInVizor => '다⁠음: Vizor⁠에⁠서 검⁠색';

  @override
  String get ledgerHelpNextSearchTitle => 'Ledger 찾⁠기';

  @override
  String get ledgerHelpNotResetDevice =>
      'Reset device⁠가 아⁠니⁠라 Bluetooth 페⁠어⁠링 옵⁠션⁠을 사⁠용⁠해 주⁠세⁠요. 지⁠갑⁠과 계⁠정⁠은 그⁠대⁠로 유⁠지⁠돼⁠요.';

  @override
  String get ledgerHelpOpenBluetoothSettings => 'Bluetooth 설⁠정 열⁠기';

  @override
  String ledgerHelpOtherModelName(String model) {
    return '$model⁠에⁠서 Settings > Name⁠을 확⁠인⁠해 주⁠세⁠요.';
  }

  @override
  String get ledgerHelpRemovePairingOnLedger =>
      'Ledger⁠에⁠서 저⁠장⁠된 페⁠어⁠링⁠을 삭⁠제⁠한 뒤 휴⁠대⁠폰⁠에⁠서⁠도 삭⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerHelpRestartBothGuide =>
      '그⁠래⁠도 나⁠타⁠나⁠지 않⁠으⁠면 두 기⁠기⁠를 모⁠두 다⁠시 시⁠작⁠하⁠고 Ledger 공⁠식 Bluetooth 문⁠제 해⁠결 가⁠이⁠드⁠를 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerHelpSearchSelectOpenZcash =>
      'Vizor⁠에⁠서 검⁠색⁠해 Ledger⁠를 선⁠택⁠해 주⁠세⁠요. Vizor⁠가 요⁠청⁠하⁠면 Zcash 앱⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerHelpSelectModelHint =>
      '모⁠델⁠을 선⁠택⁠하⁠면 페⁠어⁠링 삭⁠제 방⁠법⁠을 볼 수 있⁠어⁠요.';

  @override
  String get ledgerHelpShortIdName =>
      'Ledger⁠에 이⁠름⁠을 지⁠정⁠하⁠지 않⁠았⁠다⁠면 01AB 같⁠은 짧⁠은 ID⁠로 표⁠시⁠될 수 있⁠어⁠요. 지⁠정⁠했⁠다⁠면 설⁠정⁠한 이⁠름⁠을 찾⁠아 주⁠세⁠요.';

  @override
  String get ledgerHelpSkipIfNotListed =>
      'Ledger⁠가 목⁠록⁠에 없⁠으⁠면 이 단⁠계⁠를 건⁠너⁠뛰⁠고 계⁠속⁠해 주⁠세⁠요.';

  @override
  String ledgerHelpStepBackInVizor(String step) {
    return '3⁠단⁠계 중 $step⁠단⁠계 · 다⁠시 Vizor⁠에⁠서';
  }

  @override
  String ledgerHelpStepOnLedger(String step) {
    return '3⁠단⁠계 중 $step⁠단⁠계 · Ledger⁠에⁠서';
  }

  @override
  String ledgerHelpStepOnPhone(String step) {
    return '3⁠단⁠계 중 $step⁠단⁠계 · 휴⁠대⁠폰⁠에⁠서';
  }

  @override
  String get ledgerHelpStillNotShowing => '아⁠직 보⁠이⁠지 않⁠나⁠요?';

  @override
  String get ledgerHelpTouchControls =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠세⁠요. 홈 화⁠면⁠에⁠서 설⁠정 아⁠이⁠콘⁠을 누⁠른 다⁠음 아⁠래⁠를 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get ledgerHelpTouchMenuPath => 'Bluetooth > Remove pairing';

  @override
  String get ledgerHelpTryRestart =>
      'Ledger⁠를 다⁠시 시⁠작⁠해 보⁠세⁠요. 계⁠속 보⁠이⁠지 않⁠으⁠면 두 기⁠기⁠에⁠서 저⁠장⁠된 Bluetooth 페⁠어⁠링⁠을 삭⁠제⁠하⁠면 도⁠움⁠이 될 수 있⁠어⁠요.';

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
  String get ledgerKeepItOpen => 'Ledger⁠에⁠서 열⁠어 둔 채⁠로 유⁠지⁠해 주⁠세⁠요.';

  @override
  String get ledgerKeepNearbyUnlocked =>
      'Ledger⁠를 가⁠까⁠이⁠에 두⁠고 잠⁠금⁠을 해⁠제⁠한 상⁠태⁠로 블⁠루⁠투⁠스⁠를 켜 두⁠세⁠요.';

  @override
  String get ledgerKeepNearbyUnlockedShort =>
      'Ledger⁠를 가⁠까⁠이⁠에 두⁠고 잠⁠금⁠을 해⁠제⁠해 두⁠세⁠요.';

  @override
  String get ledgerKeepZcashOpen => 'Zcash 앱⁠을 열⁠어 둔 채⁠로 유⁠지⁠하⁠세⁠요.';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS⁠에⁠서 블⁠루⁠투⁠스 접⁠근 권⁠한⁠을 요⁠청⁠할 수 있⁠어⁠요. 요⁠청⁠이 나⁠타⁠나⁠면 Vizor⁠에 접⁠근⁠을 허⁠용⁠해 주⁠세⁠요.';

  @override
  String get ledgerMismatchChooseHolder =>
      '이 계⁠정⁠이 있⁠는 Ledger⁠를 선⁠택⁠해 주⁠세⁠요. 저⁠장⁠된 연⁠결⁠은 변⁠경⁠되⁠지 않⁠았⁠어⁠요.';

  @override
  String get ledgerMismatchConnectHolder =>
      '이 계⁠정⁠이 있⁠는 Ledger⁠를 연⁠결⁠해 주⁠세⁠요. 저⁠장⁠된 연⁠결⁠은 변⁠경⁠되⁠지 않⁠았⁠어⁠요.';

  @override
  String get ledgerMobileAnotherRequestActive =>
      '다⁠른 Ledger 요⁠청⁠이 아⁠직 진⁠행 중⁠이⁠에⁠요. Ledger⁠에⁠서 완⁠료⁠하⁠거⁠나 거⁠부⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobileCheckBluetoothBelow =>
      '아⁠래⁠에⁠서 Bluetooth 접⁠근 권⁠한⁠을 확⁠인⁠한 뒤 Ledger⁠에 다⁠시 연⁠결⁠해 보⁠세⁠요.';

  @override
  String get ledgerMobileConnectionLost =>
      'Ledger⁠와⁠의 Bluetooth 연⁠결⁠이 끊⁠겼⁠거⁠나 연⁠결⁠할 수 없⁠어⁠요. Ledger⁠를 켜⁠고 잠⁠금⁠을 해⁠제⁠한 뒤 가⁠까⁠이⁠에 두⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobilePairingInvalid =>
      'Bluetooth 페⁠어⁠링⁠이 더 이⁠상 유⁠효⁠하⁠지 않⁠아⁠요. 기⁠기⁠의 Bluetooth 설⁠정⁠에⁠서 이 Ledger⁠를 삭⁠제⁠한 뒤 다⁠시 연⁠결⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobilePairingNotCompleted =>
      'Bluetooth 페⁠어⁠링⁠이 완⁠료⁠되⁠지 않⁠았⁠어⁠요. Ledger⁠를 다⁠시 연⁠결⁠하⁠고 페⁠어⁠링 요⁠청⁠을 승⁠인⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobileRequestCancelled =>
      'Ledger 요⁠청⁠이 취⁠소⁠됐⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobileRequestRejected =>
      'Ledger⁠에⁠서 요⁠청⁠이 거⁠부⁠됐⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobileTurnOnBluetooth => 'Bluetooth⁠를 켠 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerMobileTurnOnLocation =>
      '이 Android 버⁠전⁠에⁠서 Ledger⁠를 찾⁠으⁠려⁠면 위⁠치 서⁠비⁠스⁠를 켠 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

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
  String ledgerOpenAppInstruction(String appName) {
    return '$appName 앱⁠을 열⁠어 주⁠세⁠요';
  }

  @override
  String ledgerOpenAppOnLedger(String appName) {
    return 'Ledger⁠에⁠서 $appName 앱⁠을 열⁠어 주⁠세⁠요.';
  }

  @override
  String get ledgerOpenBluetoothSettingsManually =>
      '블⁠루⁠투⁠스 설⁠정⁠을 직⁠접 열⁠어 기⁠존 페⁠어⁠링⁠을 삭⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerOpenSettings => '설⁠정 열⁠기';

  @override
  String get ledgerOpenZcashThenTryAgain => 'Zcash 앱⁠을 연 다⁠음 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerOpeningConnectionHelp => '연⁠결 도⁠움⁠말⁠을 여⁠는 중…';

  @override
  String get ledgerPairingNoLongerRecognized =>
      'Ledger⁠가 더 이⁠상 이 Bluetooth 페⁠어⁠링⁠을 인⁠식⁠하⁠지 못⁠해⁠요.';

  @override
  String get ledgerPairingNoLongerRecognizedRemove =>
      'Ledger⁠가 더 이⁠상 이 Bluetooth 페⁠어⁠링⁠을 인⁠식⁠하⁠지 못⁠해⁠요. 기⁠존 페⁠어⁠링⁠을 삭⁠제⁠한 뒤 다⁠시 연⁠결⁠해 주⁠세⁠요.';

  @override
  String ledgerProcedureStep(String step, String total) {
    return '$total⁠단⁠계 중 $step⁠단⁠계';
  }

  @override
  String ledgerProcedureStepComplete(String step, String total) {
    return '$total⁠단⁠계 중 $step⁠단⁠계, 완⁠료';
  }

  @override
  String get ledgerReadinessAppNotVerified =>
      'Vizor⁠가 Ledger Zcash 앱⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerReadinessCouldNotPrepare =>
      'Vizor⁠가 Ledger⁠의 Zcash 앱⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerReadinessOpenZcashApp =>
      'Ledger⁠에⁠서 Zcash 앱⁠을 연 다⁠음 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerReadinessOperationCancelled => 'Ledger 작⁠업⁠이 취⁠소⁠됐⁠어⁠요.';

  @override
  String get ledgerReadinessReconnectUnlockTryAgain =>
      'Ledger⁠를 다⁠시 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String ledgerReadinessUpdateApp(String version) {
    return 'Ledger Zcash 앱⁠을 $version 버⁠전 이⁠상⁠으⁠로 업⁠데⁠이⁠트⁠해 주⁠세⁠요.';
  }

  @override
  String get ledgerReadinessUsbPermission =>
      'USB⁠로 Ledger⁠를 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요. 이⁠미 연⁠결⁠되⁠어 있⁠다⁠면 Linux⁠에⁠서⁠는 Ledger udev 규⁠칙⁠을 설⁠치⁠한 뒤 연⁠결⁠을 해⁠제⁠했⁠다⁠가 다⁠시 연⁠결⁠해 주⁠세⁠요.';

  @override
  String get ledgerReadyContinueSigning =>
      'Ledger⁠가 준⁠비⁠됐⁠어⁠요. 준⁠비⁠되⁠면 서⁠명⁠을 이⁠어⁠가⁠세⁠요.';

  @override
  String get ledgerReadyReviewOnLedger =>
      '준⁠비⁠되⁠면 Ledger⁠에⁠서 거⁠래⁠를 검⁠토⁠하⁠도⁠록 계⁠속⁠해 주⁠세⁠요.';

  @override
  String get ledgerReconnectTitle => 'Ledger 다⁠시 연⁠결';

  @override
  String get ledgerRemoveOldPairing => '기⁠존 페⁠어⁠링 삭⁠제';

  @override
  String get ledgerRemovePairingIos =>
      '설⁠정 > Bluetooth⁠를 열⁠어 주⁠세⁠요. Ledger⁠가 목⁠록⁠에 있⁠다⁠면 정⁠보 버⁠튼⁠을 누⁠르⁠고 이 기⁠기⁠를 지⁠워 주⁠세⁠요.';

  @override
  String get ledgerRemovePairingMacos =>
      '시⁠스⁠템 설⁠정 > Bluetooth⁠를 열⁠어 주⁠세⁠요. Ledger⁠가 목⁠록⁠에 있⁠다⁠면 저⁠장⁠된 페⁠어⁠링⁠을 삭⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerRemovePairingOther =>
      'Bluetooth 설⁠정⁠을 열⁠어 주⁠세⁠요. Ledger⁠가 목⁠록⁠에 있⁠다⁠면 저⁠장⁠된 페⁠어⁠링⁠을 삭⁠제⁠해 주⁠세⁠요.';

  @override
  String get ledgerResetBluetoothPairing => 'Bluetooth 페⁠어⁠링 초⁠기⁠화';

  @override
  String get ledgerReturningToOptions => '연⁠결 옵⁠션⁠으⁠로 돌⁠아⁠가⁠는 중…';

  @override
  String get ledgerSavedFindAgain =>
      '이 Ledger⁠는 계⁠정⁠과 일⁠치⁠해⁠요. 계⁠속⁠하⁠려⁠면 다⁠시 찾⁠아 주⁠세⁠요.';

  @override
  String get ledgerSavedMatchesFindAgain =>
      '이 Ledger⁠는 계⁠정⁠과 일⁠치⁠하⁠며 저⁠장⁠됐⁠어⁠요. 계⁠속⁠하⁠려⁠면 다⁠시 찾⁠아 주⁠세⁠요.';

  @override
  String get ledgerSavingVerified =>
      '계⁠정⁠이 일⁠치⁠해⁠요. 확⁠인⁠된 연⁠결⁠을 저⁠장⁠하⁠고 있⁠어⁠요.';

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
  String get ledgerSigningApproveNextSeparately => '다⁠음 거⁠래⁠는 따⁠로 승⁠인⁠하⁠게 돼⁠요.';

  @override
  String get ledgerSigningApproveOrReject =>
      '승⁠인⁠하⁠여 서⁠명⁠하⁠거⁠나, 거⁠부⁠하⁠여 취⁠소⁠해 주⁠세⁠요.';

  @override
  String get ledgerSigningApproveToSign => '승⁠인⁠하⁠여 서⁠명⁠해 주⁠세⁠요.';

  @override
  String get ledgerSigningApproveToSignNext =>
      '승⁠인⁠하⁠여 서⁠명⁠해 주⁠세⁠요.\n\n다⁠음 거⁠래⁠는 따⁠로 승⁠인⁠하⁠게 돼⁠요.';

  @override
  String get ledgerSigningApprovedFinishing =>
      'Ledger⁠에⁠서 승⁠인⁠했⁠어⁠요. Vizor⁠가 거⁠래⁠를 마⁠무⁠리⁠하⁠고 있⁠어⁠요.';

  @override
  String get ledgerSigningChangeConnection => '연⁠결 변⁠경';

  @override
  String get ledgerSigningCheckAmountRecipient =>
      '안⁠내⁠가 나⁠타⁠나⁠면 Ledger⁠에⁠서 금⁠액⁠과 받⁠는 사⁠람⁠을 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerSigningCheckingZcashReady =>
      'Vizor⁠가 Zcash 앱⁠이 준⁠비⁠됐⁠는⁠지 확⁠인⁠하⁠고 있⁠어⁠요.';

  @override
  String get ledgerSigningCloseSemantics => 'Ledger 닫⁠기';

  @override
  String get ledgerSigningConfirmRequestReconnect =>
      'Ledger⁠에⁠서 요⁠청⁠을 확⁠인⁠해 주⁠세⁠요. Vizor⁠가 자⁠동⁠으⁠로 다⁠시 연⁠결⁠해⁠요.';

  @override
  String get ledgerSigningDeclined =>
      'Ledger⁠에⁠서 서⁠명⁠이 거⁠부⁠됐⁠어⁠요. 준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerSigningFinishingRequest => 'Ledger 요⁠청⁠을 마⁠무⁠리⁠하⁠고 있⁠어⁠요.';

  @override
  String get ledgerSigningKeepLedgerConnected =>
      'Ledger⁠를 연⁠결⁠된 상⁠태⁠로 유⁠지⁠해 주⁠세⁠요.';

  @override
  String get ledgerSigningKeepOpenWhileCancelling =>
      'Ledger 요⁠청⁠이 취⁠소⁠되⁠는 동⁠안 Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String get ledgerSigningKeepVizorOpen => 'Vizor⁠를 열⁠어 둔 채⁠로 유⁠지⁠하⁠세⁠요.';

  @override
  String get ledgerSigningKeepVizorOpenShort => 'Vizor⁠를 열⁠어 두⁠세⁠요';

  @override
  String get ledgerSigningMsgPreparing =>
      'Vizor⁠가 거⁠래⁠를 준⁠비⁠하⁠는 동⁠안 잠⁠시 기⁠다⁠려 주⁠세⁠요.';

  @override
  String get ledgerSigningMsgReviewing =>
      'Ledger⁠에⁠서 안⁠내⁠가 나⁠타⁠나⁠면 내⁠용⁠을 검⁠토⁠하⁠고 승⁠인⁠해 주⁠세⁠요.';

  @override
  String ledgerSigningMsgSending(String wait) {
    return '$wait Ledger⁠를 연⁠결⁠된 상⁠태⁠로 유⁠지⁠해 주⁠세⁠요.';
  }

  @override
  String get ledgerSigningSaving => '서⁠명⁠된 거⁠래⁠를 저⁠장⁠하⁠고 있⁠어⁠요.';

  @override
  String get ledgerSigningStatusCheckingDevice => '기⁠기 확⁠인 중';

  @override
  String get ledgerSigningStatusOpeningZcash => 'Zcash 여⁠는 중';

  @override
  String get ledgerSigningStatusPreparing => '서⁠명 준⁠비 중';

  @override
  String get ledgerSigningStatusReview => '기⁠기⁠에⁠서 검⁠토';

  @override
  String get ledgerSigningStatusWait => '잠⁠시⁠만 기⁠다⁠려 주⁠세⁠요';

  @override
  String get ledgerSigningStatusWaitingApproval => '승⁠인⁠을 기⁠다⁠리⁠는 중';

  @override
  String get ledgerSigningStepFinish => '거⁠래 완⁠료';

  @override
  String get ledgerSigningStepPrepare => '거⁠래 준⁠비';

  @override
  String get ledgerSigningStepReview => 'Ledger⁠에⁠서 검⁠토';

  @override
  String get ledgerSigningTitleChecking => 'Ledger⁠를 확⁠인⁠하⁠는 중';

  @override
  String get ledgerSigningTitleConfirmOnLedger => 'Ledger⁠에⁠서 확⁠인⁠해 주⁠세⁠요';

  @override
  String get ledgerSigningTitleConfirmOpening => 'Zcash 열⁠기⁠를 확⁠인⁠해 주⁠세⁠요';

  @override
  String get ledgerSigningTitleFinishing => '거⁠래⁠를 마⁠무⁠리⁠하⁠고 있⁠어⁠요';

  @override
  String get ledgerSigningTitlePreparing => '거⁠래⁠를 준⁠비⁠하⁠고 있⁠어⁠요';

  @override
  String get ledgerSigningTitleReviewing => 'Ledger⁠를 확⁠인⁠해 주⁠세⁠요';

  @override
  String get ledgerSigningTitleSending => 'Ledger⁠에⁠서 처⁠리⁠하⁠고 있⁠어⁠요';

  @override
  String get ledgerSigningTitleSendingTx => '거⁠래⁠를 보⁠내⁠는 중';

  @override
  String get ledgerSigningTitleSign => '거⁠래 서⁠명';

  @override
  String ledgerSigningTransactionProgress(String current, String total) {
    return '거⁠래 $current/$total';
  }

  @override
  String get ledgerSigningWaitInstruction =>
      'Ledger⁠가 서⁠명⁠을 준⁠비⁠하⁠고 있⁠어⁠요. 몇 초 동⁠안 반⁠응⁠이 없⁠는 것⁠처⁠럼 보⁠일 수 있⁠어⁠요.';

  @override
  String get ledgerStatusConnecting => '연⁠결⁠하⁠는 중…';

  @override
  String get ledgerStatusFollowPrompts => 'Ledger⁠의 안⁠내⁠를 따⁠라 주⁠세⁠요';

  @override
  String get ledgerStatusOpeningBluetoothSettings => 'Bluetooth 설⁠정⁠을 여⁠는 중…';

  @override
  String get ledgerStatusSavingConnection => '연⁠결⁠을 저⁠장⁠하⁠는 중…';

  @override
  String get ledgerStatusSearchingNearby => '근⁠처⁠를 검⁠색⁠하⁠는 중…';

  @override
  String get ledgerStatusStillSearching => '계⁠속 근⁠처⁠를 검⁠색⁠하⁠는 중…';

  @override
  String get ledgerStepApproveViewingKey => '뷰⁠잉 키 승⁠인';

  @override
  String ledgerStepOpenApp(String appName) {
    return '$appName 열⁠기';
  }

  @override
  String get ledgerStepOpenZcash => 'Zcash 열⁠기';

  @override
  String get ledgerStopSearchFailedHelp =>
      '검⁠색⁠을 중⁠지⁠하⁠지 못⁠했⁠어⁠요. 연⁠결 도⁠움⁠말⁠을 다⁠시 열⁠어 보⁠세⁠요.';

  @override
  String get ledgerStoppingSearch => '검⁠색⁠을 중⁠지⁠하⁠는 중';

  @override
  String get ledgerSupportedDevices => '지⁠원 기⁠기';

  @override
  String get ledgerTitleConnectingToLedger => 'Ledger⁠에 연⁠결⁠하⁠는 중';

  @override
  String get ledgerTitleFindingLedger => 'Ledger⁠를 찾⁠는 중';

  @override
  String get ledgerTitleLedgerConnected => 'Ledger⁠가 연⁠결⁠됐⁠어⁠요';

  @override
  String get ledgerTitleLedgerSaved => 'Ledger⁠가 저⁠장⁠됐⁠어⁠요';

  @override
  String get ledgerTitleMismatch => '이 Ledger⁠는 일⁠치⁠하⁠지 않⁠아⁠요';

  @override
  String get ledgerTitlePairAgain => 'Ledger⁠를 다⁠시 페⁠어⁠링⁠해 주⁠세⁠요';

  @override
  String get ledgerTitleSavingConnection => '연⁠결⁠을 저⁠장⁠하⁠는 중';

  @override
  String get ledgerTitleSelectYourLedger => 'Ledger⁠를 선⁠택⁠해 주⁠세⁠요';

  @override
  String get ledgerTransportBluetooth => '블⁠루⁠투⁠스';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerUnlockBluetoothNearby =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고 블⁠루⁠투⁠스⁠를 켠 다⁠음 가⁠까⁠이⁠에 두⁠세⁠요.';

  @override
  String get ledgerUnlockEnableBluetoothNearby =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고 Bluetooth⁠를 켠 뒤 가⁠까⁠이⁠에 두⁠세⁠요.';

  @override
  String get ledgerUnlockOpenZcashApprove =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고 Zcash 앱⁠을 열⁠어 주⁠세⁠요. 안⁠내⁠가 나⁠타⁠나⁠면 열⁠기⁠를 승⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerUnlockWithPin => 'PIN⁠으⁠로 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get ledgerUsbApproveOpening => 'Ledger⁠에⁠서 Zcash 앱 열⁠기⁠를 승⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerUsbCheckCableOpenApp =>
      'USB 케⁠이⁠블⁠을 확⁠인⁠하⁠고 Ledger⁠의 잠⁠금⁠을 해⁠제⁠한 뒤 Zcash 앱⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerUsbConnectUnlockOpen =>
      'USB 케⁠이⁠블⁠로 Ledger⁠를 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠한 뒤 Zcash 앱⁠을 열⁠어 주⁠세⁠요.';

  @override
  String get ledgerUsbConnection => 'USB 연⁠결';

  @override
  String get ledgerUsbCouldNotOpen =>
      'Vizor⁠가 Ledger⁠를 찾⁠았⁠지⁠만 열 수 없⁠어⁠요. Ledger⁠를 사⁠용⁠하⁠는 다⁠른 지⁠갑 앱⁠을 닫⁠고 다⁠시 연⁠결⁠한 뒤 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerUsbCouldNotStart =>
      'Vizor⁠가 Ledger⁠의 USB 접⁠근⁠을 시⁠작⁠하⁠지 못⁠했⁠어⁠요. 장⁠치⁠를 다⁠시 연⁠결⁠한 뒤 시⁠도⁠해 주⁠세⁠요.';

  @override
  String ledgerUsbInterrupted(String instruction) {
    return 'Ledger⁠와⁠의 USB 연⁠결⁠이 끊⁠겼⁠어⁠요. Ledger⁠를 다⁠시 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요. $instruction';
  }

  @override
  String get ledgerUsbPermissionLinux =>
      'Vizor⁠가 USB⁠로 Ledger⁠에 접⁠근⁠할 수 없⁠어⁠요. Linux⁠용 Ledger udev 규⁠칙(github.com/LedgerHQ/udev-rules)을 설⁠치⁠한 뒤 Ledger⁠를 다⁠시 연⁠결⁠하⁠고 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerUsbPermissionOther =>
      'Vizor⁠가 USB⁠로 Ledger⁠에 접⁠근⁠할 수 없⁠어⁠요. USB 장⁠치 권⁠한⁠을 확⁠인⁠한 뒤 다⁠시 연⁠결⁠하⁠고 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get ledgerVerifyingNewDevice =>
      '안⁠내⁠가 나⁠타⁠나⁠면 페⁠어⁠링⁠을 완⁠료⁠한 뒤 뷰⁠잉 키 공⁠유⁠를 승⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerVerifyingSavedDevice =>
      'Ledger⁠의 잠⁠금⁠을 해⁠제⁠하⁠고, 안⁠내⁠가 나⁠타⁠나⁠면 Zcash 열⁠기⁠를 확⁠인⁠해 주⁠세⁠요.';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor⁠가 Zcash 앱⁠을 확⁠인⁠하⁠고 있⁠어⁠요.';

  @override
  String get ledgerWaitingForApproval => '승⁠인⁠을 기⁠다⁠리⁠는 중…';

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
  String get lockSyncingMessage => 'Vizor 동⁠기⁠화 중';

  @override
  String get lockUnlockToContinue => '계⁠속⁠하⁠려⁠면 잠⁠금⁠을 해⁠제⁠하⁠세⁠요';

  @override
  String get lockUnlockToContinueBody => '계⁠속⁠하⁠려⁠면 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요';

  @override
  String get lockUnlockToContinuePausedBody =>
      '계⁠속⁠하⁠려⁠면 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String migrationAboutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠분',
    );
    return '$_temp0';
  }

  @override
  String get migrationAnalyzingBalance => '잔⁠액⁠을 분⁠석⁠하⁠는 중...';

  @override
  String get migrationAnalyzingCaption =>
      'Vizor⁠가 이⁠전⁠의 안⁠전, 프⁠라⁠이⁠버⁠시, 속⁠도 사⁠이⁠에⁠서\n최⁠적⁠의 균⁠형⁠을 찾⁠고 있⁠어⁠요';

  @override
  String get migrationAnalyzingFindingBatches => '비⁠공⁠개 배⁠치⁠를 찾⁠는 중...';

  @override
  String get migrationAnalyzingPreparingPlan => '이⁠전 계⁠획⁠을 준⁠비⁠하⁠는 중...';

  @override
  String get migrationAnalyzingSemanticsLabel => '비⁠공⁠개 이⁠전 계⁠획 준⁠비 중';

  @override
  String get migrationAnnouncementBody =>
      'Ironwood⁠는 Zcash⁠의 최⁠신 차⁠폐 풀⁠이⁠에⁠요.\n공⁠식⁠적⁠으⁠로 검⁠증⁠된 최⁠초⁠의 풀⁠로,\n최⁠첨⁠단 암⁠호 기⁠술⁠을 사⁠용⁠해⁠요.';

  @override
  String get migrationAnnouncementReleaseNote => '공⁠식 릴⁠리⁠스 노⁠트';

  @override
  String get migrationAnnouncementStart => '이⁠전 시⁠작';

  @override
  String get migrationBackAbout => '이⁠전 소⁠개';

  @override
  String get migrationBackHome => '홈⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get migrationBackHowItWorks => '이⁠전 방⁠식';

  @override
  String get migrationBackOptions => '이⁠전 옵⁠션';

  @override
  String get migrationBatchBroadcasting => '전⁠송 중...';

  @override
  String migrationBatchCardTitle(String number, String count) {
    return '배⁠치 #$number (노⁠트 $count⁠개)';
  }

  @override
  String get migrationBatchConfirming => '확⁠인 중...';

  @override
  String migrationBlockHeight(String height) {
    return '블⁠록 $height';
  }

  @override
  String migrationBlocksEstimate(String blocks) {
    return '약 $blocks⁠블⁠록';
  }

  @override
  String migrationBroadcastApproxInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠시⁠간 후',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastApproxInMinutes(int count) {
    return '약 $count⁠분 후';
  }

  @override
  String get migrationBroadcastConfirmed => '확⁠인⁠됨';

  @override
  String get migrationBroadcastDueNow => '지⁠금 전⁠송 예⁠정';

  @override
  String migrationBroadcastInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count⁠시⁠간 후',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastInMinutes(int count) {
    return '$count⁠분 후';
  }

  @override
  String get migrationBroadcastPending => '대⁠기 중';

  @override
  String get migrationBroadcastSubmitted => '제⁠출⁠됨';

  @override
  String get migrationCarouselPreparationLabel => '이⁠전 준⁠비 안⁠내';

  @override
  String get migrationCarouselProgressLabel => '이⁠전 안⁠내';

  @override
  String get migrationCompleteBody =>
      '이⁠전⁠이 완⁠료⁠되⁠었⁠어⁠요.\n평⁠소⁠처⁠럼 자⁠금⁠을 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String migrationCompleteTitle(String amount) {
    return '내\n$amount ZEC⁠가\nIronwood⁠에 있⁠어⁠요!';
  }

  @override
  String get migrationConfirming => '확⁠인 중';

  @override
  String get migrationContinueMigration => '이⁠전 계⁠속';

  @override
  String get migrationContinuing => '계⁠속⁠하⁠는 중...';

  @override
  String get migrationCtaStart => 'Ironwood 풀⁠로 이⁠전';

  @override
  String get migrationCtaStopped => '네⁠트⁠워⁠크 업⁠그⁠레⁠이⁠드⁠로 이⁠전⁠이 중⁠단⁠됨';

  @override
  String get migrationCurrentBatch => '현⁠재 배⁠치';

  @override
  String migrationDurationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠일',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationHalfHours(String hours) {
    return '약 $hours.5⁠시⁠간';
  }

  @override
  String migrationDurationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠시⁠간',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠분',
    );
    return '$_temp0';
  }

  @override
  String get migrationErrorBroadcast =>
      '이⁠전 거⁠래⁠를 전⁠송⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationErrorContinue => '이⁠전⁠을 계⁠속⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationErrorKeystonePrepare => 'Keystone 서⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get migrationErrorLedgerExcluded =>
      '현⁠재 흐⁠름⁠은 일⁠괄 서⁠명⁠이 필⁠요⁠해⁠서 Ledger 비⁠공⁠개 이⁠전⁠은 지⁠원⁠하⁠지 않⁠아⁠요.';

  @override
  String get migrationErrorPlanChanged =>
      '금⁠액⁠이⁠나 수⁠수⁠료⁠가 바⁠뀌⁠었⁠어⁠요. 업⁠데⁠이⁠트⁠된 내⁠용⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get migrationErrorStart => '이⁠전⁠을 시⁠작⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationErrorUnlockBeforeContinue =>
      '이⁠전⁠을 계⁠속⁠하⁠기 전⁠에 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get migrationErrorUnlockBeforeStart =>
      '이⁠전⁠을 시⁠작⁠하⁠기 전⁠에 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get migrationErrorWaitForSync =>
      '동⁠기⁠화⁠가 끝⁠날 때⁠까⁠지 기⁠다⁠린 뒤 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationEstimateAfterSigning => '서⁠명 후';

  @override
  String get migrationEstimateComplete => '완⁠료';

  @override
  String migrationEstimateIn(String estimate) {
    return '$estimate 후';
  }

  @override
  String migrationEstimateInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠일 후',
    );
    return '$_temp0';
  }

  @override
  String migrationEstimateInHours(String hours) {
    return '약 $hours⁠시⁠간 후';
  }

  @override
  String migrationEstimateInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠분 후',
    );
    return '$_temp0';
  }

  @override
  String get migrationEstimateInOneHour => '약 1⁠시⁠간 후';

  @override
  String get migrationEstimatedArrivalTime => '도⁠착 예⁠상 시⁠간';

  @override
  String get migrationExpectKeepRunningBody =>
      '다⁠음 이⁠전 거⁠래⁠를 보⁠내⁠려⁠면 컴⁠퓨⁠터⁠의 잠⁠금⁠이 해⁠제⁠되⁠어 있⁠고 Vizor⁠가 실⁠행 중⁠이⁠어⁠야 해⁠요';

  @override
  String get migrationExpectLongBody =>
      '이⁠전 금⁠액⁠에 따⁠라 Ironwood 이⁠전⁠에⁠는 몇 시⁠간⁠에⁠서 이⁠틀 정⁠도⁠까⁠지 걸⁠릴 수 있⁠어⁠요.';

  @override
  String get migrationExpectLongTitle => '이⁠전⁠에⁠는 시⁠간⁠이 오⁠래 걸⁠릴 수 있⁠어⁠요';

  @override
  String get migrationExpectSpendBody =>
      '확⁠인⁠된 Ironwood 금⁠액⁠은 나⁠머⁠지 이⁠전⁠이 진⁠행⁠되⁠는 동⁠안⁠에⁠도 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String get migrationExpectSpendTitle => '자⁠금⁠이 도⁠착⁠하⁠는 대⁠로 쓸 수 있⁠어⁠요';

  @override
  String get migrationExpectTitle => '안⁠내 사⁠항';

  @override
  String get migrationExpectVpnBody =>
      '신⁠뢰⁠할 수 있⁠는 VPN/네⁠트⁠워⁠크 프⁠라⁠이⁠버⁠시 계⁠층⁠을 거⁠쳐 이⁠전⁠하⁠는 것⁠을 권⁠장⁠해⁠요';

  @override
  String get migrationExpectVpnTitle => '추⁠가 프⁠라⁠이⁠버⁠시⁠를 위⁠해 VPN⁠을 사⁠용⁠하⁠세⁠요';

  @override
  String get migrationFlowTitle => 'Ironwood 이⁠전';

  @override
  String get migrationGoHome => '홈⁠으⁠로 이⁠동';

  @override
  String get migrationHowDelayedBody =>
      '추⁠적 가⁠능⁠성⁠을 줄⁠이⁠기 위⁠해 Vizor⁠가 여⁠러 배⁠치⁠에 걸⁠쳐 간⁠격⁠을 두⁠고 천⁠천⁠히 나⁠눠 보⁠내⁠요.';

  @override
  String get migrationHowDelayedTitle => '지⁠연⁠되⁠고 무⁠작⁠위⁠로 진⁠행⁠되⁠는 이⁠전';

  @override
  String get migrationHowFrozenBody =>
      '기⁠존 차⁠폐 잔⁠액⁠을 사⁠용⁠하⁠려⁠면 Ironwood⁠로 한 번 이⁠전⁠해⁠야 해⁠요.';

  @override
  String get migrationHowFrozenTitle => 'Orchard(레⁠거⁠시 차⁠폐) 잔⁠액⁠이 동⁠결⁠돼⁠요';

  @override
  String get migrationHowPreparationBody =>
      '이⁠전⁠하⁠기 전⁠에 Vizor⁠가 전⁠체 잔⁠액⁠을 더 작⁠은 노⁠트(예: 0.1 ZEC / 1 ZEC / 5 ZEC)로 나⁠눠⁠요.';

  @override
  String get migrationHowPreparationTitle => '이⁠전 전 준⁠비';

  @override
  String migrationHowStepLabel(String number) {
    return '$number⁠단⁠계';
  }

  @override
  String migrationHowStepSemanticsCurrent(
    String number,
    String total,
    String title,
    String body,
  ) {
    return '이⁠전 $total⁠단⁠계 중 $number⁠단⁠계. $title. $body';
  }

  @override
  String migrationHowStepSemanticsShow(String number, String total) {
    return '이⁠전 $total⁠단⁠계 중 $number⁠단⁠계 보⁠기';
  }

  @override
  String get migrationHowTitle => '이⁠전 방⁠식';

  @override
  String get migrationImmediateAmount => '금⁠액';

  @override
  String get migrationImmediateAuthoriseAnyway => '그⁠래⁠도 승⁠인';

  @override
  String get migrationImmediateAuthorising => '승⁠인⁠하⁠는 중…';

  @override
  String get migrationImmediateAuthorisingSemantics => '이⁠전 승⁠인⁠하⁠는 중';

  @override
  String get migrationImmediateCalculating => '계⁠산⁠하⁠는 중…';

  @override
  String get migrationImmediateConsiderOther => '다⁠른 옵⁠션 보⁠기';

  @override
  String get migrationImmediateFees => '수⁠수⁠료(예⁠상)';

  @override
  String get migrationImmediateNoBalance =>
      '즉⁠시 이⁠전⁠에 사⁠용⁠할 수 있⁠는 Orchard 잔⁠액⁠이 없⁠어⁠요.';

  @override
  String get migrationImmediatePlanFailed =>
      '즉⁠시 이⁠전 계⁠획⁠을 계⁠산⁠하⁠지 못⁠했⁠어⁠요. 동⁠기⁠화⁠한 뒤 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationImmediateRetryCalculation => '계⁠산 다⁠시 시⁠도';

  @override
  String get migrationImmediateReviewTitle => '이⁠전 계⁠획 검⁠토';

  @override
  String get migrationImmediateTradeoffEmphasis =>
      '내 지⁠갑⁠과 더 쉽⁠게 연⁠결⁠될 수 있⁠어⁠요.';

  @override
  String migrationImmediateTradeoffLead(String amount) {
    return '눈⁠에 보⁠이⁠는 한 번⁠의 단⁠계⁠로 넘⁠어⁠가⁠므⁠로 $amount⁠과(와) 시⁠점⁠이 ';
  }

  @override
  String get migrationImmediateTradeoffLedger =>
      '\nLedger 계⁠정⁠에⁠서⁠는 비⁠공⁠개 이⁠전⁠을 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get migrationImmediateTradeoffPrivate =>
      '\n비⁠공⁠개 이⁠전 옵⁠션⁠을 선⁠택⁠해 보⁠세⁠요.';

  @override
  String get migrationImmediateTradeoffTitle => '프⁠라⁠이⁠버⁠시 절⁠충';

  @override
  String get migrationImmediateUnavailable => '사⁠용⁠할 수 없⁠음';

  @override
  String migrationInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count⁠분 후',
    );
    return '$_temp0';
  }

  @override
  String get migrationIntroAnnouncement => '공⁠식 발⁠표';

  @override
  String get migrationIntroBadge => 'Zcash 네⁠트⁠워⁠크 업⁠그⁠레⁠이⁠드';

  @override
  String migrationIntroBody(String amount) {
    return '현⁠재 $amount ZEC⁠가 Orchard⁠에 있⁠어⁠요.\n이 자⁠금⁠을 계⁠속 차⁠폐 결⁠제⁠에 쓰⁠려⁠면 Ironwood⁠로 옮⁠겨⁠야 해⁠요. 자⁠금⁠이 이⁠동⁠하⁠기 전⁠에 이⁠전 계⁠획⁠을 검⁠토⁠하⁠게 돼⁠요.';
  }

  @override
  String get migrationIntroTagline => 'Zcash⁠를 위⁠한 새⁠로⁠운 차⁠폐 풀.';

  @override
  String get migrationKeystoneAfterScanInstruction =>
      '스⁠캔⁠한 후 \'서⁠명 가⁠져⁠오⁠기\'를 클⁠릭⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneApplyingSignature =>
      'Keystone 서⁠명⁠을 적⁠용⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get migrationKeystoneApplyingToPlan =>
      'Keystone 서⁠명⁠을 이⁠전 계⁠획⁠에 적⁠용⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get migrationKeystoneBackToReview => '검⁠토⁠로 돌⁠아⁠가⁠기';

  @override
  String get migrationKeystoneBackToStatus => '상⁠태⁠로 돌⁠아⁠가⁠기';

  @override
  String get migrationKeystoneBeginSigning => '서⁠명 시⁠작';

  @override
  String get migrationKeystoneCamera => '카⁠메⁠라';

  @override
  String get migrationKeystoneCameraAccess =>
      '서⁠명⁠된 Keystone QR⁠을 스⁠캔⁠하⁠려⁠면 카⁠메⁠라 접⁠근⁠을 허⁠용⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneCameraOnly =>
      'Keystone 이⁠전 서⁠명⁠은 카⁠메⁠라 QR 스⁠캔⁠만 지⁠원⁠해⁠요. 카⁠메⁠라⁠를 연⁠결⁠한 뒤 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneCancelFailed =>
      '서⁠명 요⁠청⁠을 취⁠소⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneClickToEnlarge => 'QR⁠을 클⁠릭⁠해 확⁠대';

  @override
  String get migrationKeystoneConfirmTitle => 'Keystone⁠으⁠로 이⁠전 확⁠인';

  @override
  String get migrationKeystoneEnlargeQr => 'Keystone 요⁠청 QR 확⁠대';

  @override
  String get migrationKeystoneEnlargedQr => '확⁠대⁠된 Keystone 요⁠청 QR';

  @override
  String get migrationKeystoneFirmwareUpdate =>
      'Ironwood 이⁠전⁠에 서⁠명⁠하⁠려⁠면 Keystone 펌⁠웨⁠어⁠를 업⁠데⁠이⁠트⁠한 뒤 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneGetSignature => '서⁠명 가⁠져⁠오⁠기';

  @override
  String get migrationKeystoneKeepQrSteady =>
      'QR 코⁠드⁠를 흔⁠들⁠리⁠지 않⁠게 전⁠부 보⁠이⁠도⁠록 유⁠지⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneMobileTitle => 'Keystone 이⁠전';

  @override
  String get migrationKeystoneNotKeystone =>
      '이 이⁠전⁠에 서⁠명⁠하⁠려⁠면 Keystone 계⁠정⁠을 사⁠용⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneOpenSignedQr =>
      'Keystone⁠에⁠서 서⁠명⁠된 이⁠전 QR⁠을 연 뒤 다⁠시 스⁠캔⁠하⁠세⁠요.';

  @override
  String get migrationKeystonePlanBody =>
      '각 회⁠차⁠마⁠다 움⁠직⁠이⁠는 요⁠청 QR 하⁠나⁠와 서⁠명⁠된 응⁠답 QR 하⁠나⁠를 사⁠용⁠해⁠요.';

  @override
  String get migrationKeystonePlanTitle => 'Keystone 서⁠명 계⁠획';

  @override
  String get migrationKeystonePrepareFailed =>
      'Keystone 서⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationKeystonePrepareWallet => 'Keystone 지⁠갑⁠을 준⁠비⁠하⁠세⁠요';

  @override
  String get migrationKeystonePreparing => '준⁠비 중';

  @override
  String get migrationKeystonePreparingQr => 'QR 코⁠드 준⁠비 중...';

  @override
  String get migrationKeystoneProofFailed =>
      'Vizor⁠가 로⁠컬 증⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 돌⁠아⁠가⁠서 이 요⁠청⁠을 다⁠시 준⁠비⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneProofWaiting =>
      '서⁠명⁠을 받⁠았⁠어⁠요. Vizor⁠가 아⁠직 로⁠컬 증⁠명⁠을 준⁠비⁠하⁠는 중⁠이⁠에⁠요. 이 화⁠면⁠을 열⁠어 두⁠세⁠요.';

  @override
  String migrationKeystoneProofWaitingProgress(String ready, String total) {
    return '서⁠명⁠을 받⁠았⁠어⁠요. Vizor⁠가 아⁠직 로⁠컬 증⁠명⁠을 준⁠비⁠하⁠는 중⁠이⁠에⁠요($ready/$total). 이 화⁠면⁠을 열⁠어 두⁠세⁠요.';
  }

  @override
  String get migrationKeystoneProofsPreparing => '로⁠컬 증⁠명 준⁠비 중';

  @override
  String get migrationKeystoneProofsPreparingEllipsis => '로⁠컬 증⁠명 준⁠비 중...';

  @override
  String migrationKeystoneProofsProgress(String ready, String total) {
    return '로⁠컬 증⁠명 준⁠비 중 $ready/$total';
  }

  @override
  String get migrationKeystoneQrBodyCombined =>
      'Keystone⁠으⁠로 이 요⁠청⁠을 스⁠캔⁠해 준⁠비 거⁠래⁠와 이⁠전 배⁠치⁠를 함⁠께 서⁠명⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneQrBodyImmediate =>
      'Keystone 지⁠갑⁠으⁠로 QR 코⁠드⁠를 스⁠캔⁠해 이⁠전⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneQrBodyRound =>
      'Keystone⁠으⁠로 이 요⁠청 QR⁠을 스⁠캔⁠하⁠세⁠요. 완⁠료⁠되⁠면 Keystone⁠에 서⁠명⁠된 새 QR⁠이 표⁠시⁠돼⁠요.';

  @override
  String get migrationKeystoneReadingSignature => '서⁠명⁠을 읽⁠는 중...';

  @override
  String get migrationKeystoneRequestCancelled =>
      '이 서⁠명 요⁠청⁠이 취⁠소⁠되⁠었⁠어⁠요. 다⁠시 준⁠비⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneRequestExpired =>
      '이 Keystone 서⁠명 요⁠청⁠이 만⁠료⁠되⁠었⁠어⁠요. 다⁠시 준⁠비⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneRequestQr => '요⁠청 QR';

  @override
  String get migrationKeystoneRequestUnusable =>
      '이 Keystone 서⁠명 요⁠청⁠은 더 이⁠상 사⁠용⁠할 수 없⁠어⁠요. 다⁠시 준⁠비⁠하⁠세⁠요.';

  @override
  String migrationKeystoneRound(String current, String total) {
    return '$total⁠회 중 $current⁠회⁠차';
  }

  @override
  String migrationKeystoneRoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'QR 서⁠명 $count⁠회',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneScanIssuesBody =>
      'Keystone Cypherpunk 펌⁠웨⁠어⁠의 새 버⁠전⁠이 있⁠을 수 있⁠어⁠요. 최⁠신 버⁠전⁠인⁠지 확⁠인⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneScanIssuesConfirm => '네, 확⁠인⁠할⁠게⁠요';

  @override
  String get migrationKeystoneScanIssuesTitle => 'QR 코⁠드 스⁠캔⁠에 문⁠제⁠가 있⁠나⁠요?';

  @override
  String get migrationKeystoneScanNewQr =>
      'Keystone⁠에 표⁠시⁠된 새 서⁠명 QR⁠을 스⁠캔⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneScanQrCode => 'QR 코⁠드 스⁠캔';

  @override
  String get migrationKeystoneScanRequest => 'Keystone⁠으⁠로 요⁠청 스⁠캔';

  @override
  String get migrationKeystoneScanSignature => 'Keystone 서⁠명 스⁠캔';

  @override
  String get migrationKeystoneScanSubtitle => 'Keystone⁠으⁠로 스⁠캔⁠하⁠세⁠요';

  @override
  String get migrationKeystoneSignBatch => 'Ironwood 배⁠치 서⁠명';

  @override
  String get migrationKeystoneSignMigration => '이⁠전 서⁠명';

  @override
  String get migrationKeystoneSignPrivateSplit => '비⁠공⁠개 분⁠할 서⁠명';

  @override
  String get migrationKeystoneSignatureFailed =>
      'Keystone 서⁠명⁠을 적⁠용⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String migrationKeystoneSignsAll(String transactions) {
    return '$transactions 서⁠명';
  }

  @override
  String migrationKeystoneSignsSome(String count, String transactions) {
    return '전⁠체 $transactions 중 $count⁠건 서⁠명';
  }

  @override
  String get migrationKeystoneToolbarReview => '이⁠전 검⁠토';

  @override
  String get migrationKeystoneToolbarStatus => '이⁠전 상⁠태';

  @override
  String migrationKeystoneTransactionTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '총 거⁠래 $count⁠건',
    );
    return '$_temp0';
  }

  @override
  String migrationKeystoneTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '거⁠래 $count⁠건',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneTryAfterSync => '동⁠기⁠화⁠가 끝⁠난 후 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneUnavailableTitle =>
      'Keystone 서⁠명⁠을 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get migrationKeystoneUnlockFirst =>
      '이⁠전⁠에 서⁠명⁠하⁠기 전⁠에 Vizor 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get migrationKeystoneWaitingForProofsLong =>
      '서⁠명⁠을 받⁠았⁠어⁠요. 로⁠컬 증⁠명⁠이 준⁠비⁠되⁠면 Vizor⁠가 이⁠어⁠서 진⁠행⁠해⁠요.';

  @override
  String get migrationKeystoneWaitingForProofsShort =>
      '서⁠명⁠을 받⁠았⁠어⁠요. 로⁠컬 증⁠명⁠을 기⁠다⁠리⁠는 중⁠이⁠에⁠요.';

  @override
  String get migrationKeystoneWrongRound =>
      '이 서⁠명⁠된 QR⁠은 다⁠른 회⁠차⁠의 것⁠이⁠에⁠요. 돌⁠아⁠가⁠서 현⁠재 요⁠청⁠을 Keystone⁠으⁠로 스⁠캔⁠한 뒤 새⁠로 서⁠명⁠된 QR⁠을 스⁠캔⁠하⁠세⁠요.';

  @override
  String get migrationLedgerBroadcast => '이⁠전 거⁠래⁠를 전⁠송⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get migrationLedgerConnect =>
      'Ledger⁠를 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠한 뒤 Zcash 앱⁠을 여⁠세⁠요.';

  @override
  String get migrationLedgerFailed => 'Ledger 이⁠전⁠을 완⁠료⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get migrationLedgerFailedTitle => 'Ledger 이⁠전 실⁠패';

  @override
  String get migrationLedgerPlanChanged =>
      '금⁠액⁠이⁠나 수⁠수⁠료⁠가 바⁠뀌⁠었⁠어⁠요. 돌⁠아⁠가⁠서 업⁠데⁠이⁠트⁠된 계⁠획⁠을 검⁠토⁠하⁠세⁠요.';

  @override
  String get migrationLedgerProofs => 'Vizor⁠가 이⁠전 증⁠명 준⁠비⁠를 마⁠치⁠지 못⁠했⁠어⁠요.';

  @override
  String get migrationLedgerRejected => 'Ledger⁠에⁠서 이⁠전 거⁠래⁠가 거⁠부⁠되⁠었⁠어⁠요.';

  @override
  String get migrationLedgerTitle => 'Ledger⁠로 이⁠전';

  @override
  String migrationLeftToTransfer(String amount) {
    return '남⁠은 전⁠송: $amount';
  }

  @override
  String get migrationManage => '관⁠리';

  @override
  String get migrationManageCancelling => '취⁠소⁠하⁠는 중...';

  @override
  String get migrationManageCannotCancel => '이 이⁠전⁠은 더 이⁠상 취⁠소⁠할 수 없⁠어⁠요.';

  @override
  String get migrationManageConfirm => '확⁠인';

  @override
  String get migrationManageImmediateBullet1 =>
      '남⁠은 분⁠할 노⁠트⁠는 즉⁠시 이⁠전⁠으⁠로 처⁠리⁠되⁠어 추⁠적 가⁠능⁠성⁠이 약⁠간 높⁠아⁠져⁠요';

  @override
  String get migrationManageImmediateBullet2 =>
      '이⁠미 전⁠송⁠된 거⁠래⁠는 되⁠돌⁠려⁠지⁠지 않⁠아⁠요';

  @override
  String get migrationManageImmediateBullet3 => '즉⁠시 이⁠전⁠은 되⁠돌⁠릴 방⁠법⁠이 없⁠어⁠요';

  @override
  String get migrationManageImmediateIntro => '남⁠은 이⁠전⁠을 즉⁠시 처⁠리⁠해⁠요.';

  @override
  String get migrationManageLoading => '불⁠러⁠오⁠는 중...';

  @override
  String get migrationManageNoBalance => '이⁠전⁠할 Orchard 잔⁠액⁠이 남⁠아 있⁠지 않⁠아⁠요.';

  @override
  String get migrationManageStop => '이⁠전 중⁠단';

  @override
  String get migrationManageStopBody =>
      '예⁠약⁠된 나⁠머⁠지 이⁠전 거⁠래⁠가 취⁠소⁠돼⁠요. 홈 화⁠면⁠에⁠서 이⁠전⁠을 다⁠시 시⁠작⁠할 수 있⁠어⁠요.';

  @override
  String get migrationManageStopTitle => '정⁠말 중⁠단⁠할⁠까⁠요?';

  @override
  String get migrationManageStopping => '중⁠단⁠하⁠는 중...';

  @override
  String get migrationManageSwitchImmediate => '즉⁠시 이⁠전⁠으⁠로 전⁠환';

  @override
  String get migrationManageTitle => '이⁠전 관⁠리';

  @override
  String get migrationManageUpdateFailed =>
      '이⁠전⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationMobileActionAllTransactions => '모⁠든 거⁠래';

  @override
  String migrationMobileActionBatch(int number) {
    return '배⁠치 #$number';
  }

  @override
  String get migrationMobileActionInProgress => '이⁠전 작⁠업 진⁠행 중';

  @override
  String get migrationMobileActionNeedSignature => '서⁠명⁠이 필⁠요⁠한 거⁠래';

  @override
  String migrationMobileActionPrepareBatch(int number) {
    return '배⁠치 #$number 준⁠비';
  }

  @override
  String migrationMobileActionPreparingBatch(int number) {
    return '배⁠치 #$number 준⁠비 중...';
  }

  @override
  String get migrationMobileActionResign => '이⁠전 거⁠래 다⁠시 서⁠명';

  @override
  String get migrationMobileActionSign => '이⁠전 거⁠래 서⁠명';

  @override
  String migrationMobileActionSignBatch(int number) {
    return '배⁠치 #$number 서⁠명';
  }

  @override
  String get migrationMobileActionSubmitScheduled => '예⁠약⁠된 거⁠래 제⁠출';

  @override
  String get migrationMobileActionSubmittingScheduled =>
      '예⁠약⁠된 거⁠래⁠를 제⁠출⁠하⁠는 중...';

  @override
  String get migrationMobileAnnouncementBody =>
      'Zcash⁠의 최⁠신 차⁠폐 풀⁠로, 최⁠첨⁠단 암⁠호⁠학⁠과 형⁠식 검⁠증⁠을 갖⁠췄⁠어⁠요.\n\n차⁠폐 잔⁠액⁠은 Ironwood⁠로 한 번 이⁠전⁠해⁠야 해⁠요.';

  @override
  String get migrationMobileAnnouncementOfficial => '공⁠식 발⁠표';

  @override
  String get migrationMobileAnnouncementUpgrade => 'Ironwood⁠로 업⁠그⁠레⁠이⁠드';

  @override
  String get migrationMobileAttentionContinueTitle => '이⁠전⁠을 계⁠속⁠하⁠세⁠요';

  @override
  String get migrationMobileAttentionLateTitle => '이⁠전 거⁠래⁠를 확⁠인⁠해⁠야 해⁠요';

  @override
  String get migrationMobileAttentionLater => '나⁠중⁠에 할⁠게⁠요';

  @override
  String get migrationMobileAttentionOpen => '이⁠전 페⁠이⁠지⁠로 이⁠동';

  @override
  String get migrationMobileAttentionProofTitle => '다⁠음 이⁠전 배⁠치⁠가 준⁠비⁠됐⁠어⁠요';

  @override
  String migrationMobileAttentionSignatureSheet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노⁠트 $count⁠개⁠에 서⁠명⁠할 준⁠비⁠가 됐⁠어⁠요',
    );
    return '$_temp0';
  }

  @override
  String get migrationMobileAttentionStoppedTitle =>
      '네⁠트⁠워⁠크 업⁠그⁠레⁠이⁠드⁠로 이⁠전⁠이 중⁠단⁠됐⁠어⁠요';

  @override
  String get migrationMobileBackHome => '홈⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get migrationMobileBackToHome => '홈⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get migrationMobileBannerInProgress => '이⁠전 진⁠행 중';

  @override
  String get migrationMobileBannerLate => '이⁠전 확⁠인⁠이 필⁠요⁠해⁠요';

  @override
  String get migrationMobileBannerPreparing => '이⁠전 준⁠비 중';

  @override
  String get migrationMobileBannerProof => '다⁠음 이⁠전 배⁠치⁠가 준⁠비⁠됐⁠어⁠요';

  @override
  String migrationMobileBannerRemaining(String amount) {
    return '$amount ZEC 이⁠전 중';
  }

  @override
  String migrationMobileBannerSignature(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노⁠트 $count⁠개⁠에 서⁠명⁠할 수 있⁠어⁠요',
    );
    return '$_temp0';
  }

  @override
  String get migrationMobileBannerStart => 'Ironwood⁠로 이⁠전';

  @override
  String get migrationMobileBannerStopped => '이⁠전⁠이 중⁠단⁠됐⁠어⁠요';

  @override
  String get migrationMobileBannerWaiting => '확⁠인⁠을 기⁠다⁠리⁠는 중...';

  @override
  String migrationMobileBatchProgress(int completed, int total) {
    return '배⁠치 $completed/$total';
  }

  @override
  String get migrationMobileCanLeave => '이 화⁠면⁠을 나⁠가⁠도 돼⁠요.';

  @override
  String get migrationMobileCompleteBody =>
      '이⁠전⁠이 성⁠공⁠적⁠으⁠로 끝⁠났⁠어⁠요. 이⁠제 평⁠소⁠처⁠럼 자⁠금⁠을 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String migrationMobileCompleteHeading(String amount) {
    return '$amount⁠가\nIronwood⁠에\n도⁠착⁠했⁠어⁠요!';
  }

  @override
  String get migrationMobileCompleteTitle => '모⁠든 준⁠비⁠가 끝⁠났⁠어⁠요!';

  @override
  String get migrationMobileContinueError =>
      '이⁠전⁠을 계⁠속⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileContinueThisError =>
      '이 이⁠전⁠을 계⁠속⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileCredentialsRestore =>
      '계⁠속⁠하⁠기 전⁠에 이⁠전 자⁠격 증⁠명⁠을 복⁠원⁠해⁠야 해⁠요.';

  @override
  String get migrationMobileErrorBroadcast =>
      '이⁠전 거⁠래⁠를 전⁠송⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileErrorPlanChanged =>
      '금⁠액⁠이⁠나 수⁠수⁠료⁠가 바⁠뀌⁠었⁠어⁠요. 업⁠데⁠이⁠트⁠된 내⁠용⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get migrationMobileErrorStart =>
      '이⁠전⁠을 시⁠작⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileErrorSyncFirst =>
      '동⁠기⁠화⁠가 끝⁠날 때⁠까⁠지 기⁠다⁠린 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileErrorUnlock =>
      '이⁠전⁠을 시⁠작⁠하⁠기 전⁠에 Vizor⁠의 잠⁠금⁠을 해⁠제⁠하⁠세⁠요.';

  @override
  String get migrationMobileEstCompletion => '예⁠상 완⁠료';

  @override
  String get migrationMobileFastConsiderOther => '다⁠른 방⁠법 알⁠아⁠보⁠기';

  @override
  String get migrationMobileFastContinueAnyway => '그⁠래⁠도 계⁠속';

  @override
  String get migrationMobileFastDurationRow => '이⁠전 완⁠료⁠까⁠지';

  @override
  String get migrationMobileFastFeesRow => '수⁠수⁠료(예⁠상)';

  @override
  String get migrationMobileFastNoBalance =>
      '즉⁠시 이⁠전⁠에 사⁠용⁠할 수 있⁠는 Orchard 잔⁠액⁠이 없⁠어⁠요.';

  @override
  String get migrationMobileFastPlanCalculating => '계⁠산 중…';

  @override
  String get migrationMobileFastPlanError =>
      '즉⁠시 이⁠전 수⁠수⁠료⁠를 계⁠산⁠하⁠지 못⁠했⁠어⁠요. 동⁠기⁠화⁠한 뒤 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileFastPlanUnavailable => '사⁠용⁠할 수 없⁠음';

  @override
  String get migrationMobileFastPrivacyBodyHighlight =>
      '내 지⁠갑⁠과 연⁠결⁠되⁠기 더 쉬⁠워⁠요';

  @override
  String migrationMobileFastPrivacyBodyLead(String amount) {
    return '한 번⁠에 눈⁠에 띄⁠는 단⁠계⁠로 건⁠너⁠가⁠요. $amount⁠와 시⁠점⁠이 ';
  }

  @override
  String get migrationMobileFastPrivacyConsiderPrivate =>
      '비⁠공⁠개 이⁠전 옵⁠션⁠을 선⁠택⁠해 보⁠세⁠요.';

  @override
  String get migrationMobileFastPrivacyLedger =>
      'Ledger 계⁠정⁠에⁠서⁠는 비⁠공⁠개 이⁠전⁠을 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get migrationMobileFastPrivacyTitle => '프⁠라⁠이⁠버⁠시 상⁠충';

  @override
  String get migrationMobileFastRetryCalculation => '다⁠시 계⁠산';

  @override
  String migrationMobileFastSubmittedBody(String amount) {
    return '$amount⁠를 Ironwood⁠로 보⁠내⁠는 중⁠이⁠에⁠요.';
  }

  @override
  String get migrationMobileFastSubmittedTitle => '이⁠전⁠을 제⁠출⁠했⁠어⁠요';

  @override
  String get migrationMobileFastTitle => '빠⁠른 이⁠전';

  @override
  String get migrationMobileGoHome => '홈⁠으⁠로';

  @override
  String get migrationMobileHeroBadge => '이⁠전';

  @override
  String get migrationMobileHeroIronwoodPool => 'Ironwood 풀';

  @override
  String get migrationMobileHeroLegacy => '(기⁠존)';

  @override
  String get migrationMobileHeroOrchardPool => 'Orchard 풀';

  @override
  String get migrationMobileHowItWorksNavTitle => '안⁠내';

  @override
  String get migrationMobileHowItWorksTitle => '이⁠전 방⁠식';

  @override
  String migrationMobileIntroBody(String amount) {
    return '현⁠재 $amount ZEC⁠가 Orchard⁠에 있⁠어⁠요. 이 자⁠금⁠을 계⁠속 차⁠폐 결⁠제⁠에 쓰⁠려⁠면 Ironwood⁠로 옮⁠겨⁠야 해⁠요. 자⁠금⁠을 옮⁠기⁠기 전⁠에 이⁠전 계⁠획⁠을 먼⁠저 확⁠인⁠할 수 있⁠어⁠요.';
  }

  @override
  String get migrationMobileIntroReleaseNote => '공⁠식 릴⁠리⁠스 노⁠트';

  @override
  String get migrationMobileIntroTagline => 'Zcash⁠의 새⁠로⁠운 차⁠폐 풀⁠이⁠에⁠요.';

  @override
  String get migrationMobileIntroTitle => 'Zcash 네⁠트⁠워⁠크 업⁠데⁠이⁠트';

  @override
  String get migrationMobileKeepOpenUnlocked =>
      'Vizor⁠를 열⁠어 두⁠고 잠⁠금⁠을 해⁠제⁠한 상⁠태⁠로 유⁠지⁠하⁠세⁠요.';

  @override
  String get migrationMobileKeepRunning =>
      '단, Vizor⁠는 열⁠어 두⁠고 실⁠행 상⁠태⁠로 유⁠지⁠하⁠세⁠요.';

  @override
  String get migrationMobileKeystoneConfirmPrepSemantics =>
      'Keystone⁠으⁠로 이⁠전 준⁠비 확⁠인';

  @override
  String get migrationMobileKeystoneConfirmTitle => 'Keystone⁠으⁠로 이⁠전 확⁠인';

  @override
  String get migrationMobileKeystoneConfirmTransferSemantics =>
      'Keystone⁠으⁠로 이⁠전 전⁠송 확⁠인';

  @override
  String get migrationMobileKeystoneHelpPrompt =>
      'Keystone⁠에⁠서 QR⁠을 탭⁠한 다⁠음,\n이 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요.';

  @override
  String get migrationMobileKeystoneHelpSemantics => 'Keystone QR 스⁠캔 도⁠움⁠말';

  @override
  String get migrationMobileKeystoneLoadingQrSemantics => 'QR 코⁠드 불⁠러⁠오⁠는 중';

  @override
  String get migrationMobileKeystoneLoadingQrText => 'QR 코⁠드⁠를 불⁠러⁠오⁠는 중 ...';

  @override
  String get migrationMobileKeystoneNextStep => '다⁠음 단⁠계';

  @override
  String get migrationMobileKeystonePromptOnDevice => 'Keystone⁠에⁠서 탭⁠하⁠고,';

  @override
  String get migrationMobileKeystonePromptTap => '먼⁠저';

  @override
  String get migrationMobileKeystonePromptThenScan => '이 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get migrationMobileKeystoneReconnect =>
      '이 이⁠전⁠을 계⁠속⁠하⁠려⁠면 Keystone 계⁠정⁠을 다⁠시 연⁠결⁠하⁠거⁠나 다⁠시 가⁠져⁠오⁠세⁠요.';

  @override
  String get migrationMobileKeystoneRequestQrSemantics => 'Keystone 요⁠청 QR 코⁠드';

  @override
  String get migrationMobileKeystoneRequiredStatus => 'Keystone 계⁠정 필⁠요';

  @override
  String get migrationMobileKeystoneResignMessage =>
      '계⁠속⁠하⁠려⁠면 다⁠시 만⁠든 이⁠전 거⁠래⁠를 Keystone⁠으⁠로 서⁠명⁠하⁠세⁠요.';

  @override
  String get migrationMobileKeystoneScanCaption =>
      'Keystone⁠의 QR 코⁠드⁠를\n스⁠캔⁠해 확⁠인⁠하⁠세⁠요';

  @override
  String get migrationMobileKeystoneScanPrepSemantics =>
      'Keystone⁠에⁠서 서⁠명⁠된 이⁠전 준⁠비⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get migrationMobileKeystoneScanProgress => '스⁠캔 진⁠행⁠률';

  @override
  String get migrationMobileKeystoneScanTitle => 'Keystone⁠으⁠로 스⁠캔';

  @override
  String get migrationMobileKeystoneScanTransferSemantics =>
      'Keystone⁠에⁠서 서⁠명⁠된 이⁠전 전⁠송⁠을 스⁠캔⁠하⁠세⁠요';

  @override
  String get migrationMobileKeystoneShowTxQr => '거⁠래 QR 보⁠기';

  @override
  String get migrationMobileKeystoneStep1 => '1/2⁠단⁠계';

  @override
  String get migrationMobileKeystoneStep2 => '2/2⁠단⁠계';

  @override
  String get migrationMobileLeftToMigrate => '남⁠은 이⁠전 금⁠액';

  @override
  String get migrationMobileManageCheckError =>
      '이⁠전 상⁠태⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileManageChecking => '이⁠전 상⁠태⁠를 확⁠인⁠하⁠는 중...';

  @override
  String get migrationMobileManageConfirm => '확⁠인';

  @override
  String get migrationMobileManageNoRevert =>
      '이⁠미 전⁠송⁠된 거⁠래⁠는 되⁠돌⁠려⁠지⁠지 않⁠아⁠요.';

  @override
  String get migrationMobileManageRetryStatus => '상⁠태 다⁠시 확⁠인';

  @override
  String get migrationMobileManageStopAction => '이⁠전 중⁠단';

  @override
  String get migrationMobileManageStopBody =>
      '남⁠은 이⁠전⁠을 중⁠단⁠해⁠요. 이⁠미 이⁠전⁠된 자⁠금⁠은 Ironwood⁠에 그⁠대⁠로 있⁠어⁠요.';

  @override
  String get migrationMobileManageStopTitle => '이⁠전⁠을 중⁠단⁠할⁠까⁠요?';

  @override
  String get migrationMobileManageStopping => '중⁠단⁠하⁠는 중...';

  @override
  String get migrationMobileManageSwitchAction => '빠⁠른 이⁠전⁠으⁠로 전⁠환';

  @override
  String get migrationMobileManageSwitchBody =>
      '비⁠공⁠개 일⁠정⁠을 중⁠단⁠하⁠고 남⁠은 잔⁠액⁠에 대⁠한 빠⁠른 이⁠전⁠을 검⁠토⁠해⁠요. 빠⁠른 이⁠전⁠은 추⁠적 가⁠능⁠성⁠을 높⁠이⁠며, 한 번 제⁠출⁠하⁠면 되⁠돌⁠릴 수 없⁠어⁠요.';

  @override
  String get migrationMobileManageSwitchTitle => '빠⁠른 이⁠전⁠으⁠로 전⁠환⁠할⁠까⁠요?';

  @override
  String get migrationMobileManageTitle => '이⁠전 관⁠리';

  @override
  String get migrationMobileManageUnavailable => '이 이⁠전⁠은 더 이⁠상 관⁠리⁠할 수 없⁠어⁠요.';

  @override
  String get migrationMobileManageUpdateError =>
      '이⁠전⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileManageWaitingBroadcast =>
      '진⁠행 중⁠인 전⁠송⁠이 끝⁠나⁠기⁠를 기⁠다⁠린 뒤 남⁠은 이⁠전⁠을 중⁠단⁠해⁠요.';

  @override
  String get migrationMobileNextConfirmationsArriving =>
      '확⁠인⁠이 아⁠직 도⁠착⁠하⁠는 중⁠이⁠에⁠요.\nVizor⁠를 나⁠갔⁠다⁠가 나⁠중⁠에 다⁠시 확⁠인⁠해⁠도 돼⁠요.';

  @override
  String migrationMobileNextExpectedIn(String timing) {
    return '다⁠음 이⁠전 단⁠계 예⁠상 시⁠점:\n$timing.';
  }

  @override
  String get migrationMobileNextMigration => '다⁠음 이⁠전';

  @override
  String migrationMobileNextNotificationsOffBlock(int height, String timing) {
    return '알⁠림⁠이 꺼⁠져 있⁠어⁠요. $height 블⁠록($timing) 이⁠후⁠에 Vizor⁠를 열⁠어 다⁠음 이⁠전 배⁠치⁠를 승⁠인⁠하⁠세⁠요.';
  }

  @override
  String get migrationMobileNextNotificationsOffNoTiming =>
      '알⁠림⁠이 꺼⁠져 있⁠어⁠요. 시⁠간 정⁠보⁠가 나⁠오⁠면 Vizor⁠를 다⁠시 열⁠어 다⁠음 이⁠전 배⁠치⁠를 승⁠인⁠하⁠세⁠요.';

  @override
  String get migrationMobileNextNotificationsOffOpen =>
      '알⁠림⁠이 꺼⁠져 있⁠어⁠요. 계⁠속⁠하⁠려⁠면 Vizor⁠를 다⁠시 여⁠세⁠요.';

  @override
  String get migrationMobileNextNotificationsOnLeave =>
      '알⁠림⁠이 켜⁠져 있⁠어⁠요. Vizor⁠를 나⁠갔⁠다⁠가 나⁠중⁠에 다⁠시 확⁠인⁠해⁠도 돼⁠요.';

  @override
  String get migrationMobileNextOnTheWay => '다⁠음 이⁠전 단⁠계⁠가 곧 시⁠작⁠돼⁠요.';

  @override
  String get migrationMobileNextReadyAuto =>
      '예⁠약⁠된 거⁠래⁠를 자⁠동⁠으⁠로 제⁠출⁠할 준⁠비⁠가 됐⁠어⁠요. Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String get migrationMobileNextStepReady =>
      '다⁠음 이⁠전 단⁠계⁠가 준⁠비⁠됐⁠어⁠요. 계⁠속⁠하⁠려⁠면 Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String migrationMobileNextTimingUntil(String timing) {
    return '다⁠음 이⁠전 단⁠계⁠까⁠지 $timing.\n알⁠림⁠이 켜⁠져 있⁠어⁠요. Vizor⁠를 나⁠갔⁠다⁠가 나⁠중⁠에 다⁠시 확⁠인⁠해⁠도 돼⁠요.';
  }

  @override
  String get migrationMobileNextTorDisclosure =>
      'Vizor⁠가 닫⁠혀 있⁠는 동⁠안⁠에⁠는 이⁠전⁠이 직⁠접 연⁠결⁠로 계⁠속⁠돼⁠요.';

  @override
  String get migrationMobileNotifyAllow => '알⁠림 허⁠용';

  @override
  String get migrationMobileNotifyBody =>
      '일⁠부 이⁠전 단⁠계⁠는 승⁠인⁠이 필⁠요⁠해⁠요. 때⁠가 되⁠면 알⁠려 드⁠릴 테⁠니 빠⁠르⁠게 응⁠답⁠해 불⁠필⁠요⁠한 지⁠연⁠을 피⁠하⁠세⁠요.';

  @override
  String get migrationMobileNotifyConfirmBody =>
      '알⁠림⁠이 없⁠으⁠면 Vizor⁠를 주⁠기⁠적⁠으⁠로 열⁠어 준⁠비⁠된 다⁠음 이⁠전 단⁠계⁠를 직⁠접 승⁠인⁠해⁠야 해⁠요.';

  @override
  String get migrationMobileNotifyConfirmNote =>
      '그⁠렇⁠지 않⁠으⁠면 이⁠전⁠에 더 오⁠래 걸⁠릴 수 있⁠어⁠요.';

  @override
  String get migrationMobileNotifyConfirmTitle => '알⁠림 없⁠이 계⁠속⁠할⁠까⁠요?';

  @override
  String get migrationMobileNotifyContinueWithout => '알⁠림 없⁠이 계⁠속';

  @override
  String get migrationMobileNotifyHeading => '이⁠전 일⁠정⁠을 놓⁠치⁠지 마⁠세⁠요';

  @override
  String get migrationMobileNotifyStillOff =>
      '알⁠림⁠이 아⁠직 꺼⁠져 있⁠어⁠요. 설⁠정⁠에⁠서 허⁠용⁠하⁠거⁠나 알⁠림 없⁠이 계⁠속⁠하⁠세⁠요.';

  @override
  String get migrationMobileNotifyTitle => '알⁠림 켜⁠기';

  @override
  String migrationMobileOptionImmediateBody(String estimate) {
    return '전⁠체 잔⁠액⁠을 한 번⁠에 이⁠전⁠해⁠요. 빠⁠르⁠지⁠만($estimate) 프⁠라⁠이⁠버⁠시⁠는 낮⁠아⁠요.';
  }

  @override
  String get migrationMobileOptionImmediateTitle => '즉⁠시';

  @override
  String get migrationMobileOptionPrivateBody =>
      '거⁠래⁠를 여⁠러 부⁠분⁠으⁠로 나⁠눠 추⁠적 가⁠능⁠성⁠을 최⁠소⁠화⁠하⁠지⁠만 몇 시⁠간⁠에⁠서 며⁠칠⁠이 걸⁠려⁠요.';

  @override
  String get migrationMobileOptionPrivateTitle => '비⁠공⁠개';

  @override
  String get migrationMobileOptionPrivateUnavailableAndroid =>
      'Android⁠에⁠서⁠는 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get migrationMobileOptionPrivateUnavailableLedger =>
      'Ledger 계⁠정⁠에⁠서⁠는 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get migrationMobileOptionsNavTitle => '이⁠전 방⁠법';

  @override
  String get migrationMobileOptionsOpenError =>
      '이⁠전 준⁠비⁠를 열⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileOptionsSubtitle =>
      '시⁠간⁠을 들⁠여 더 높⁠은 프⁠라⁠이⁠버⁠시⁠를 얻⁠을⁠지, 더 빠⁠르⁠게 이⁠전⁠할⁠지 선⁠택⁠하⁠세⁠요. 자⁠금⁠을 옮⁠기⁠기 전⁠에 자⁠세⁠한 내⁠용⁠을 확⁠인⁠할 수 있⁠어⁠요.';

  @override
  String get migrationMobileOptionsSubtitleAndroid =>
      'Android⁠에⁠서⁠는 비⁠공⁠개 이⁠전⁠을 일⁠시⁠적⁠으⁠로 사⁠용⁠할 수 없⁠어⁠요. 계⁠속⁠하⁠려⁠면 즉⁠시 이⁠전⁠을 선⁠택⁠하⁠세⁠요.';

  @override
  String migrationMobileOptionsSubtitleAndroidRest(String amount) {
    return '$amount ZEC⁠가 아⁠직 Orchard⁠에 있⁠어⁠요. Android⁠에⁠서⁠는 비⁠공⁠개 이⁠전⁠을 일⁠시⁠적⁠으⁠로 사⁠용⁠할 수 없⁠어⁠요. 계⁠속⁠하⁠려⁠면 즉⁠시 이⁠전⁠을 선⁠택⁠하⁠세⁠요.';
  }

  @override
  String get migrationMobileOptionsSubtitleLedger =>
      'Ledger 계⁠정⁠에⁠서⁠는 비⁠공⁠개 이⁠전⁠을 사⁠용⁠할 수 없⁠어⁠요. 계⁠속⁠하⁠려⁠면 즉⁠시 이⁠전⁠을 선⁠택⁠하⁠세⁠요.';

  @override
  String migrationMobileOptionsSubtitleLedgerRest(String amount) {
    return '$amount ZEC⁠가 아⁠직 Orchard⁠에 있⁠어⁠요. Ledger 계⁠정⁠에⁠서⁠는 비⁠공⁠개 이⁠전⁠을 사⁠용⁠할 수 없⁠어⁠요. 계⁠속⁠하⁠려⁠면 즉⁠시 이⁠전⁠을 선⁠택⁠하⁠세⁠요.';
  }

  @override
  String migrationMobileOptionsSubtitleRest(String amount) {
    return '$amount ZEC⁠가 아⁠직 Orchard⁠에 있⁠어⁠요. 시⁠간⁠을 들⁠여 더 높⁠은 프⁠라⁠이⁠버⁠시⁠를 얻⁠을⁠지, 더 빠⁠르⁠게 이⁠전⁠할⁠지 선⁠택⁠하⁠세⁠요.';
  }

  @override
  String get migrationMobileOptionsTitle => '이⁠전 방⁠법 선⁠택';

  @override
  String get migrationMobileOptionsTitleRest => '나⁠머⁠지 이⁠전 방⁠법';

  @override
  String migrationMobilePartConfirming(int count, int target) {
    return '확⁠인 중 · $count/$target';
  }

  @override
  String migrationMobilePartLabel(int number) {
    return '$number⁠단⁠계';
  }

  @override
  String migrationMobilePartProgress(String part, int percent) {
    return '$part 진⁠행⁠률 $percent%';
  }

  @override
  String get migrationMobilePartQueued => '대⁠기 중';

  @override
  String get migrationMobilePartsPlaceholder =>
      '거⁠래⁠가 준⁠비⁠되⁠면 이⁠전 단⁠계⁠가 여⁠기⁠에 표⁠시⁠돼⁠요.';

  @override
  String get migrationMobilePrepAdvancing =>
      '다⁠음 거⁠래⁠를 준⁠비⁠하⁠고 있⁠어⁠요. Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String get migrationMobilePrepBackgroundTracking =>
      '백⁠그⁠라⁠운⁠드⁠에⁠서 확⁠인⁠하⁠는 중⁠이⁠에⁠요. Vizor⁠를 닫⁠아⁠도 돼⁠요.';

  @override
  String get migrationMobilePrepBackgroundUnsupported =>
      '이 기⁠기⁠는 백⁠그⁠라⁠운⁠드⁠에⁠서 확⁠인⁠할 수 없⁠어⁠요. Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String get migrationMobilePrepContinue => '준⁠비 계⁠속';

  @override
  String get migrationMobilePrepContinueKeystone => 'Keystone⁠으⁠로 계⁠속';

  @override
  String get migrationMobilePrepDoneBody =>
      '준⁠비⁠가 완⁠료⁠됐⁠어⁠요. 이⁠전 상⁠태⁠에⁠서 진⁠행 상⁠황⁠과 필⁠요⁠한 조⁠치⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get migrationMobilePrepDoneTitle => '준⁠비⁠가 끝⁠났⁠어⁠요';

  @override
  String get migrationMobilePrepDuration => '준⁠비⁠에⁠는\n10~20⁠분 걸⁠려⁠요';

  @override
  String get migrationMobilePrepInfoOrganizing =>
      '잔⁠액⁠을 흔⁠한 크⁠기⁠의 여⁠러 부⁠분⁠으⁠로 정⁠리⁠하⁠고 있⁠어⁠요. 이⁠렇⁠게 하⁠면 이⁠전⁠을 연⁠결⁠해 알⁠아⁠내⁠기 더 어⁠려⁠워⁠져⁠요.';

  @override
  String get migrationMobilePrepInfoThenBegin =>
      '준⁠비⁠가 끝⁠나⁠면 이⁠전⁠을 시⁠작⁠할 수 있⁠어⁠요.';

  @override
  String get migrationMobilePrepKeystoneSignature =>
      '준⁠비⁠를 계⁠속⁠하⁠려⁠면 Keystone 서⁠명⁠이 한 번 더 필⁠요⁠해⁠요.';

  @override
  String get migrationMobilePrepNotificationsDisabled =>
      '백⁠그⁠라⁠운⁠드⁠에⁠서 계⁠속⁠하⁠려⁠면 알⁠림⁠을 허⁠용⁠하⁠거⁠나 Vizor⁠를 열⁠어 두⁠세⁠요.';

  @override
  String get migrationMobilePrepPausedLeft => '나⁠가⁠셔⁠서 준⁠비⁠가 일⁠시 중⁠지⁠됐⁠어⁠요.';

  @override
  String get migrationMobilePrepSyncingWallet => '지⁠갑⁠을 동⁠기⁠화⁠하⁠는 중…';

  @override
  String get migrationMobilePreparingBody =>
      '이⁠전⁠을 위⁠해 잔⁠액⁠을 준⁠비⁠하⁠고 있⁠어⁠요. 보⁠통 10~20⁠분 걸⁠려⁠요.';

  @override
  String get migrationMobilePreparingTitle => '이⁠전 준⁠비 중';

  @override
  String get migrationMobileProcessChooseBody =>
      '프⁠라⁠이⁠버⁠시⁠에 최⁠적⁠화⁠된 일⁠정⁠과 더 빠⁠른 이⁠전⁠을 비⁠교⁠해 보⁠세⁠요.';

  @override
  String get migrationMobileProcessChooseTitle => '이⁠전 방⁠법 선⁠택';

  @override
  String get migrationMobileProcessMoveBody =>
      '프⁠라⁠이⁠버⁠시⁠에 최⁠적⁠화⁠된 이⁠전⁠은 각 부⁠분⁠을 시⁠차⁠를 두⁠고 보⁠내 연⁠결 가⁠능⁠성⁠을 줄⁠여⁠요.';

  @override
  String get migrationMobileProcessMoveTitle => 'Ironwood⁠로 이⁠동';

  @override
  String get migrationMobileProcessPrepareBody =>
      '이⁠전⁠을 시⁠작⁠하⁠기 전⁠에 Vizor⁠가 잔⁠액⁠을 흔⁠한 크⁠기⁠의 여⁠러 부⁠분⁠으⁠로 재⁠구⁠성⁠해⁠요.';

  @override
  String get migrationMobileProcessPrepareTitle => '잔⁠액 준⁠비';

  @override
  String get migrationMobileProcessSpendBody =>
      '확⁠인⁠된 Ironwood 금⁠액⁠은 나⁠머⁠지 이⁠전⁠이 진⁠행⁠되⁠는 동⁠안⁠에⁠도 바⁠로 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String get migrationMobileProcessSpendTitle => '도⁠착⁠하⁠는 대⁠로 사⁠용';

  @override
  String get migrationMobileProgressAllClear => '문⁠제⁠없⁠어⁠요. 이⁠전⁠이 진⁠행 중⁠이⁠에⁠요';

  @override
  String migrationMobileProgressAllClearBatch(int number) {
    return '문⁠제⁠없⁠어⁠요. 배⁠치 #$number⁠를 처⁠리⁠하⁠는 중';
  }

  @override
  String migrationMobileProgressBatchReady(int number) {
    return '배⁠치 #$number⁠가 준⁠비⁠됐⁠어⁠요.';
  }

  @override
  String get migrationMobileProgressConfirmations => '확⁠인⁠을 기⁠다⁠리⁠는 중';

  @override
  String get migrationMobileProgressNextStep => '다⁠음 이⁠전 단⁠계⁠를 기⁠다⁠리⁠는 중';

  @override
  String get migrationMobileProgressReadyNow => '지⁠금 준⁠비⁠됨';

  @override
  String get migrationMobileProgressScheduledReady => '예⁠약⁠된 거⁠래 준⁠비⁠됨';

  @override
  String get migrationMobileProgressSyncing => '동⁠기⁠화 중';

  @override
  String get migrationMobileProgressSyncingBody =>
      '최⁠신 확⁠인 수⁠와 이⁠전 상⁠태⁠를 확⁠인⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get migrationMobileProgressSyncingTitle => '이⁠전 진⁠행 상⁠황 동⁠기⁠화 중';

  @override
  String get migrationMobileProgressWaitingWindowBody =>
      '준⁠비⁠는 끝⁠났⁠지⁠만\n다⁠음⁠으⁠로 서⁠명⁠할 수 있⁠는 구⁠간⁠을 기⁠다⁠리⁠고 있⁠어⁠요.\n조⁠치⁠할 때⁠가 되⁠면 알⁠려 드⁠릴⁠게⁠요.';

  @override
  String get migrationMobileProgressYourConfirmation => '내 확⁠인⁠을 기⁠다⁠리⁠는 중';

  @override
  String get migrationMobileRebuildAction => '다⁠시 만⁠들⁠기';

  @override
  String get migrationMobileRebuildBody =>
      'Vizor⁠가 먼⁠저 대⁠기 중⁠인 거⁠래⁠가 전⁠송⁠되⁠지 않⁠았⁠는⁠지 확⁠인⁠해⁠요. 그⁠런 다⁠음 남⁠은 잔⁠액⁠에 대⁠해⁠서⁠만 이⁠전⁠을 다⁠시 만⁠들⁠어⁠요. 이⁠미 확⁠인⁠된 이⁠전⁠은 그⁠대⁠로 유⁠지⁠돼⁠요.';

  @override
  String get migrationMobileRebuildTitle => '이⁠전⁠을 다⁠시 만⁠들⁠까⁠요?';

  @override
  String get migrationMobileRecommended => '추⁠천';

  @override
  String get migrationMobileRecover => '복⁠구';

  @override
  String get migrationMobileRecovering => '복⁠구⁠하⁠는 중...';

  @override
  String get migrationMobileRecoveryRequired => '이⁠전⁠을 복⁠구⁠해⁠야 해⁠요.';

  @override
  String get migrationMobileResume => '재⁠개';

  @override
  String get migrationMobileResuming => '재⁠개⁠하⁠는 중...';

  @override
  String get migrationMobileRetryAutomatically =>
      'Vizor⁠가 자⁠동⁠으⁠로 다⁠시 시⁠도⁠해⁠요.';

  @override
  String get migrationMobileRetrying => '다⁠시 시⁠도⁠하⁠는 중...';

  @override
  String get migrationMobileReviewPlanTitle => '이⁠전 계⁠획 검⁠토';

  @override
  String get migrationMobileSavedTxError => '저⁠장⁠된 거⁠래 두 건⁠을 다⁠시 열⁠지 못⁠했⁠어⁠요.';

  @override
  String get migrationMobileScheduleCalculating => '계⁠산 중';

  @override
  String get migrationMobileScheduleChange => '거⁠스⁠름⁠돈';

  @override
  String migrationMobileScheduleConfirming(int count, int target) {
    return '확⁠인 중 $count/$target';
  }

  @override
  String get migrationMobileScheduleCurrentBlock => '현⁠재 블⁠록';

  @override
  String get migrationMobileScheduleDueNow => '지⁠금 예⁠정';

  @override
  String get migrationMobileScheduleDuration => '소⁠요 시⁠간';

  @override
  String get migrationMobileScheduleLoading => '이⁠전 일⁠정⁠을 불⁠러⁠오⁠는 중';

  @override
  String get migrationMobileScheduleManage => '관⁠리';

  @override
  String get migrationMobileScheduleMigrating => '이⁠전 중…';

  @override
  String get migrationMobileScheduleMigrationNote => '이⁠전⁠용 노⁠트';

  @override
  String get migrationMobileScheduleNextRound => '다⁠음 회⁠차';

  @override
  String migrationMobileScheduleOf(int current, int total) {
    return '$total⁠개 중 $current⁠개';
  }

  @override
  String get migrationMobileScheduleOverdue => '기⁠한 초⁠과';

  @override
  String get migrationMobileSchedulePending => '일⁠정 대⁠기 중';

  @override
  String get migrationMobileSchedulePreparationProgress => '준⁠비 진⁠행 상⁠황';

  @override
  String get migrationMobileSchedulePreparationTitle => '준⁠비 일⁠정';

  @override
  String get migrationMobileSchedulePreparing => '일⁠정⁠을 준⁠비⁠하⁠는 중';

  @override
  String get migrationMobileSchedulePreparingState => '준⁠비 중';

  @override
  String get migrationMobileScheduleReadyIn => '준⁠비 완⁠료⁠까⁠지';

  @override
  String get migrationMobileScheduleReadyToSign => '서⁠명 준⁠비⁠됨';

  @override
  String get migrationMobileScheduleReturn => '돌⁠아⁠가⁠기';

  @override
  String migrationMobileScheduleRound(int round) {
    return '$round⁠회⁠차';
  }

  @override
  String get migrationMobileScheduleRoundsRemaining => '남⁠은 회⁠차';

  @override
  String get migrationMobileScheduleScheduled => '예⁠약⁠됨';

  @override
  String get migrationMobileScheduleSpendable => 'Ironwood 사⁠용 가⁠능';

  @override
  String migrationMobileScheduleSplitRound(int round) {
    return '분⁠할 $round⁠회⁠차';
  }

  @override
  String get migrationMobileScheduleTitle => '이⁠전 일⁠정';

  @override
  String get migrationMobileScheduleUnavailableBody =>
      'Vizor⁠가 최⁠신 일⁠정⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 저⁠장⁠된 이⁠전 상⁠태⁠는 그⁠대⁠로⁠예⁠요.';

  @override
  String get migrationMobileScheduleUnavailableTitle =>
      '이⁠전 일⁠정⁠을 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String get migrationMobileScheduleWaitingMined => '블⁠록 포⁠함 대⁠기 중';

  @override
  String migrationMobileScheduleWindow(String height) {
    return '구⁠간 #$height';
  }

  @override
  String get migrationMobileSpendableBalance => '현⁠재 사⁠용 가⁠능⁠한 잔⁠액';

  @override
  String get migrationMobileStartErrorFallback => '준⁠비⁠되⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get migrationMobileStartErrorTitle => '이⁠전⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get migrationMobileStartLoadingBody =>
      'Vizor⁠가 이⁠전⁠을 준⁠비⁠하⁠고 있⁠어⁠요. 잠⁠시 걸⁠릴 수 있⁠어⁠요.';

  @override
  String get migrationMobileStartMessageOrganizing => '이⁠전 배⁠치⁠를 정⁠리⁠하⁠는 중...';

  @override
  String get migrationMobileStartMessagePlan => '이⁠전 계⁠획⁠을 준⁠비⁠하⁠는 중...';

  @override
  String get migrationMobileStartMessagePreparing => '이⁠전⁠을 준⁠비⁠하⁠는 중...';

  @override
  String get migrationMobileStartReadyBody =>
      '계⁠속⁠하⁠면 Keystone⁠으⁠로 준⁠비 거⁠래⁠와 이⁠전 배⁠치⁠를 함⁠께 서⁠명⁠해⁠요.';

  @override
  String get migrationMobileStartReadyTitle => '서⁠명⁠할 준⁠비⁠가 됐⁠어⁠요';

  @override
  String migrationMobileStatusNotesCount(int count) {
    return '노⁠트 $count⁠개';
  }

  @override
  String get migrationMobileStatusNotesLead => '이⁠전 ';

  @override
  String get migrationMobileStatusTitle => 'Ironwood 이⁠전';

  @override
  String get migrationMobileStoppedMoved => 'Ironwood⁠로 이⁠전⁠됨';

  @override
  String get migrationMobileStoppedRemaining => '아⁠직 Orchard⁠에 있⁠음';

  @override
  String get migrationMobileSyncingProgress =>
      '이⁠전 진⁠행 상⁠황⁠을 동⁠기⁠화⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get migrationMobileTimingUpdating => '시⁠간⁠을 업⁠데⁠이⁠트⁠하⁠는 중';

  @override
  String get migrationMobileViewSchedule => '일⁠정 보⁠기';

  @override
  String get migrationMobileWaitAutoStart =>
      '노⁠트 분⁠할⁠이 끝⁠나⁠면 이⁠전⁠이 자⁠동⁠으⁠로 시⁠작⁠돼⁠요.';

  @override
  String migrationMobileWaitBlocks(int count, int target) {
    return '$count/$target 블⁠록';
  }

  @override
  String get migrationMobileWaitConfirmation => '확⁠인 대⁠기';

  @override
  String get migrationMobileWaitKeystoneAgain =>
      '이 확⁠인⁠이 끝⁠나⁠면 Keystone⁠에⁠서 한 번 더 승⁠인⁠해⁠야 해⁠요.';

  @override
  String get migrationMobileWaitLoopBatch => ' 거⁠래 배⁠치';

  @override
  String get migrationMobileWaitLoopCaption =>
      '여⁠러 번 반⁠복⁠되⁠며\n기⁠다⁠리⁠는 데 2~10⁠시⁠간\n걸⁠릴 수 있⁠어⁠요';

  @override
  String get migrationMobileWaitLoopForWindow => ' 서⁠명 구⁠간⁠까⁠지';

  @override
  String get migrationMobileWaitLoopSign => '서⁠명⁠하⁠기';

  @override
  String get migrationMobileWaitLoopWait => '기⁠다⁠리⁠기';

  @override
  String get migrationMobileWaitNoteSplit => '노⁠트 분⁠할';

  @override
  String get migrationMobileWaitSafeBlock =>
      '안⁠전⁠한 블⁠록⁠이 나⁠올 때⁠까⁠지 기⁠다⁠리⁠는 중⁠이⁠에⁠요.';

  @override
  String migrationMobileWaitSplitInto(int count) {
    return '노⁠트⁠를 이⁠전 $count⁠단⁠계⁠로 분⁠할';
  }

  @override
  String get migrationNextActionDetailAllNotesCompleted => '모⁠든 노⁠트 완⁠료';

  @override
  String get migrationNextActionDetailAt => '블⁠록';

  @override
  String get migrationNextActionDetailExpectedAt => '예⁠상 블⁠록';

  @override
  String get migrationNextActionDetailPreparing => '이⁠전 준⁠비 중';

  @override
  String get migrationNextActionDetailReadyToSign => '서⁠명 준⁠비⁠됨';

  @override
  String get migrationNextActionDetailSendingNow => '지⁠금 전⁠송 중';

  @override
  String get migrationNextActionDetailWaitingForConfirmations => '확⁠인 대⁠기 중';

  @override
  String get migrationNextActionDetailWaitingForSync => '지⁠갑 동⁠기⁠화 대⁠기 중';

  @override
  String get migrationNextActionLabelAwaitingMining => '블⁠록 포⁠함 대⁠기 중';

  @override
  String get migrationNextActionLabelComplete => '이⁠전 완⁠료';

  @override
  String get migrationNextActionLabelFinalizing => '이⁠전 마⁠무⁠리 중';

  @override
  String get migrationNextActionLabelNext => '다⁠음 이⁠전';

  @override
  String get migrationNextActionLabelNextWindow => '다⁠음 이⁠전 구⁠간';

  @override
  String get migrationNextActionLabelOpeningWindow => '이⁠전 구⁠간 여⁠는 중';

  @override
  String get migrationNextActionLabelSending => '이⁠전 전⁠송 중';

  @override
  String get migrationNextActionLabelWindowReady => '이⁠전 구⁠간 준⁠비⁠됨';

  @override
  String get migrationNotScheduled => '예⁠약 안 됨';

  @override
  String migrationNotesAwaitingConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노⁠트 $count⁠개 확⁠인 대⁠기 중',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesBroadcast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노⁠트 $count⁠개 전⁠송⁠됨',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '노⁠트 $count⁠개 남⁠음',
    );
    return '$_temp0';
  }

  @override
  String get migrationOptionImmediate => '즉⁠시';

  @override
  String get migrationOptionImmediateBody =>
      '전⁠체 잔⁠액⁠을 한 번⁠에 이⁠전⁠해⁠요. 빠⁠르⁠지⁠만 프⁠라⁠이⁠버⁠시⁠는 낮⁠아⁠요.';

  @override
  String get migrationOptionPrivate => '비⁠공⁠개';

  @override
  String get migrationOptionPrivateBody =>
      '추⁠적 가⁠능⁠성⁠을 최⁠소⁠화⁠하⁠려⁠고 거⁠래⁠를 여⁠러 부⁠분⁠으⁠로 나⁠누⁠지⁠만 시⁠간⁠이 더 걸⁠려⁠요.';

  @override
  String get migrationOptionPrivateLedger => 'Ledger 계⁠정⁠에⁠서⁠는 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get migrationOptionRecommended => '추⁠천';

  @override
  String get migrationOptionsBody =>
      '시⁠간⁠을 들⁠여 프⁠라⁠이⁠버⁠시⁠를 높⁠일⁠지, 더 빠⁠르⁠게 이⁠전⁠할⁠지 선⁠택⁠하⁠세⁠요. 자⁠금⁠이 이⁠동⁠하⁠기 전⁠에 세⁠부 내⁠용⁠을 검⁠토⁠할 수 있⁠어⁠요.';

  @override
  String migrationOptionsBodyMoveRest(String amount) {
    return '$amount ZEC⁠가 아⁠직 Orchard⁠에 있⁠어⁠요. 시⁠간⁠을 들⁠여 프⁠라⁠이⁠버⁠시⁠를 높⁠일⁠지, 더 빠⁠르⁠게 이⁠전⁠할⁠지 선⁠택⁠하⁠세⁠요.';
  }

  @override
  String get migrationOptionsSelectReview => '선⁠택 및 검⁠토';

  @override
  String get migrationOptionsTitle => '이⁠전 방⁠식 선⁠택';

  @override
  String get migrationOptionsTitleMoveRest => '나⁠머⁠지⁠를 옮⁠기⁠는 방⁠법';

  @override
  String get migrationOverallCalculatingTotal => '총⁠계 계⁠산 중';

  @override
  String migrationOverallProgress(String completed, String total) {
    return '$total⁠개 중 $completed⁠개 완⁠료';
  }

  @override
  String migrationPlannedBatches(String count) {
    return '예⁠정⁠된 배⁠치 $count⁠개';
  }

  @override
  String get migrationPoolIronwood => 'Ironwood 풀';

  @override
  String get migrationPoolLegacy => '(레⁠거⁠시)';

  @override
  String get migrationPoolOrchard => 'Orchard 풀';

  @override
  String migrationPreparationConfirmations(String confirmed, String target) {
    return '확⁠인 $confirmed/$target';
  }

  @override
  String migrationPreparationSplitProgress(String current, String total) {
    return '분⁠할 $current/$total 준⁠비 중';
  }

  @override
  String migrationPreparationSplitStep(String current, String total) {
    return '분⁠할 $current/$total';
  }

  @override
  String get migrationPreparationSplitTransactions => '분⁠할 거⁠래 준⁠비 중';

  @override
  String get migrationPreparationTipDelay =>
      '준⁠비⁠가 끝⁠나⁠면 의⁠도⁠적⁠으⁠로 긴 지⁠연 후⁠에 이⁠전⁠이 자⁠동⁠으⁠로 시⁠작⁠돼⁠요.';

  @override
  String get migrationPreparationTipOrganizing =>
      '잔⁠액⁠을 흔⁠한 크⁠기⁠로 나⁠누⁠고 있⁠어⁠요. 이⁠전⁠을 연⁠결⁠해 알⁠아⁠내⁠기 어⁠려⁠워⁠져⁠요.';

  @override
  String get migrationPreparationTipRounds =>
      '잔⁠액⁠에 따⁠라 노⁠트 분⁠할⁠을 여⁠러 차⁠례 해⁠야 할 수 있⁠어⁠요.';

  @override
  String get migrationPreparingBatch => '배⁠치 준⁠비 중...';

  @override
  String get migrationPrivacyLockDescription =>
      '10⁠분 동⁠안 사⁠용⁠하⁠지 않⁠아 Vizor⁠를 자⁠동⁠으⁠로 잠⁠갔⁠어⁠요.';

  @override
  String get migrationPrivacyLockInProgress => '이⁠전 진⁠행 중';

  @override
  String migrationProgressTipBlockTime(String seconds) {
    return 'Zcash 블⁠록⁠은 하⁠나 만⁠드⁠는 데 약 $seconds⁠초⁠가 걸⁠리⁠지⁠만 네⁠트⁠워⁠크 상⁠황⁠에 따⁠라 달⁠라⁠질 수 있⁠어⁠요.';
  }

  @override
  String get migrationProgressTipClose =>
      '언⁠제⁠든⁠지 Vizor⁠를 닫⁠아⁠도 돼⁠요. 이⁠전⁠이 일⁠시 중⁠지⁠되⁠고, 돌⁠아⁠오⁠면 다⁠시 시⁠작⁠할 수 있⁠어⁠요.';

  @override
  String get migrationProgressTipKeepRunning =>
      'Vizor⁠를 계⁠속 실⁠행⁠해 두⁠면 이⁠전⁠이 백⁠그⁠라⁠운⁠드⁠에⁠서 자⁠동⁠으⁠로 진⁠행⁠돼⁠요.';

  @override
  String get migrationReadyNow => '지⁠금 가⁠능';

  @override
  String get migrationRetryMigration => '이⁠전 다⁠시 시⁠도';

  @override
  String get migrationRetrying => '다⁠시 시⁠도⁠하⁠는 중...';

  @override
  String get migrationReviewAmountToMigrate => '이⁠전⁠할 금⁠액';

  @override
  String get migrationReviewAnalyzeErrorTitle => '이 잔⁠액⁠을 분⁠석⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get migrationReviewCompleteIn => '이⁠전 완⁠료⁠까⁠지';

  @override
  String get migrationReviewKeepRunningBody =>
      '앱⁠을 최⁠소⁠화⁠해⁠도 준⁠비⁠가 계⁠속⁠되⁠고, 이⁠후 이⁠전⁠이 자⁠동⁠으⁠로 시⁠작⁠돼⁠요.';

  @override
  String get migrationReviewKeepRunningTitle => 'Vizor⁠를 계⁠속 실⁠행⁠하⁠세⁠요';

  @override
  String get migrationReviewStart => '이⁠전 시⁠작';

  @override
  String get migrationReviewStarting => '시⁠작⁠하⁠는 중…';

  @override
  String get migrationRingAllSplitsCompleted => '모⁠든 분⁠할 완⁠료';

  @override
  String get migrationRingConfirmingSplit => '분⁠할 확⁠인 중';

  @override
  String get migrationRingNextSplit => '다⁠음 분⁠할';

  @override
  String get migrationRingPreparationComplete => '준⁠비 완⁠료';

  @override
  String get migrationRingPreparingSchedule => '일⁠정 준⁠비 중';

  @override
  String get migrationRingScheduled => '예⁠약⁠됨';

  @override
  String get migrationRingSplitInProgress => '분⁠할 진⁠행 중';

  @override
  String get migrationRingStatusCompleted => '완⁠료⁠됨';

  @override
  String get migrationRingStatusConfirming => '확⁠인 중';

  @override
  String get migrationRingStatusMigrating => '이⁠전 중';

  @override
  String get migrationRingStatusNeedsInput => '서⁠명 필⁠요';

  @override
  String get migrationRingStatusNotStarted => '시⁠작 전';

  @override
  String get migrationRingStatusPreparing => '준⁠비 중';

  @override
  String get migrationRingStatusScheduled => '예⁠약⁠됨';

  @override
  String get migrationRingWaitingForBlock => '블⁠록 대⁠기 중';

  @override
  String get migrationRingWaitingForPreviousSplit => '이⁠전 분⁠할 대⁠기 중';

  @override
  String get migrationRouteNotAvailable => '이 계⁠정⁠에⁠서⁠는 이⁠전⁠을 사⁠용⁠할 수 없⁠어⁠요.';

  @override
  String get migrationRouteNotNeeded => '이 계⁠정⁠은 이⁠전⁠이 필⁠요⁠하⁠지 않⁠아⁠요.';

  @override
  String get migrationRouteStatusFailed => '이⁠전 상⁠태⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get migrationRouteSyncFailed =>
      '동⁠기⁠화⁠를 마⁠치⁠지 못⁠했⁠어⁠요. Vizor⁠가 동⁠기⁠화⁠된 후 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationScheduleBroadcasting => '전⁠송 중';

  @override
  String get migrationScheduleCalculating => '계⁠산 중';

  @override
  String migrationScheduleCompletedAtBlock(String height) {
    return '블⁠록 $height⁠에⁠서 완⁠료⁠됨';
  }

  @override
  String migrationScheduleConfirmingProgress(String count, String target) {
    return '확⁠인 중 $count/$target';
  }

  @override
  String get migrationScheduleCurrentRound => '현⁠재 회⁠차';

  @override
  String migrationScheduleExpected(String height) {
    return '예⁠상 #$height';
  }

  @override
  String get migrationScheduleOutputChange => 'Orchard⁠에 남⁠음';

  @override
  String migrationScheduleOutputContinuation(String round) {
    return '$round⁠회⁠차⁠에⁠서 사⁠용';
  }

  @override
  String get migrationScheduleOutputMigration => '이⁠전⁠용';

  @override
  String get migrationSchedulePending => '일⁠정 대⁠기 중';

  @override
  String get migrationSchedulePreparing => '준⁠비 중';

  @override
  String get migrationScheduleReadyToMigrate => '이⁠전 준⁠비 완⁠료 시⁠점';

  @override
  String get migrationScheduleRecalculating => '다⁠시 계⁠산 중';

  @override
  String migrationScheduleRescheduled(String height) {
    return '재⁠예⁠약⁠됨 #$height';
  }

  @override
  String migrationScheduleRoundProgress(String current, String total) {
    return '$total⁠회 중 $current⁠회';
  }

  @override
  String migrationScheduleScheduledAt(String height) {
    return '예⁠약⁠됨 #$height';
  }

  @override
  String migrationScheduleSemanticsAwaiting(String height) {
    return '이⁠전 분⁠할⁠을 기⁠다⁠리⁠는 중, 예⁠상 블⁠록 $height';
  }

  @override
  String migrationScheduleSemanticsBroadcast(String height) {
    return '전⁠송⁠됨, 블⁠록 포⁠함 대⁠기 중, 예⁠상 완⁠료 블⁠록 $height';
  }

  @override
  String get migrationScheduleSemanticsCompleted => '완⁠료⁠됨';

  @override
  String migrationScheduleSemanticsCompletedAt(String height) {
    return '블⁠록 $height⁠에⁠서 완⁠료⁠됨';
  }

  @override
  String get migrationScheduleSemanticsDue => '지⁠금 전⁠송 예⁠정';

  @override
  String get migrationScheduleSemanticsMigrating => '전⁠송⁠됨, 블⁠록 포⁠함 대⁠기 중';

  @override
  String migrationScheduleSemanticsNote(
    String number,
    String amount,
    String state,
  ) {
    return '노⁠트 $number, $amount ZEC, $state.';
  }

  @override
  String migrationScheduleSemanticsNoteConfirming(String count, String target) {
    return '확⁠인 중, 확⁠인 $count/$target';
  }

  @override
  String migrationScheduleSemanticsNoteConfirmingMined(
    String count,
    String target,
    String height,
  ) {
    return '확⁠인 중, 확⁠인 $count/$target, 블⁠록 $height⁠에⁠서 포⁠함⁠됨';
  }

  @override
  String migrationScheduleSemanticsOutput(String amount, String destination) {
    return '$amount ZEC, $destination';
  }

  @override
  String get migrationScheduleSemanticsOutputChange => 'Orchard⁠에 남⁠음';

  @override
  String migrationScheduleSemanticsOutputContinuation(String round) {
    return '$round⁠회⁠차⁠에⁠서 사⁠용';
  }

  @override
  String get migrationScheduleSemanticsOutputMigration => '이⁠전⁠용';

  @override
  String migrationScheduleSemanticsOutputs(String outputs) {
    return '출⁠력: $outputs.';
  }

  @override
  String get migrationScheduleSemanticsPending => '일⁠정 대⁠기 중';

  @override
  String get migrationScheduleSemanticsReadyToSign => '서⁠명 준⁠비⁠됨';

  @override
  String migrationScheduleSemanticsRescheduled(String from, String to) {
    return '블⁠록 $from⁠에⁠서 블⁠록 $to⁠로 재⁠예⁠약⁠됨';
  }

  @override
  String migrationScheduleSemanticsScheduled(String height) {
    return '블⁠록 $height⁠에 예⁠약⁠됨';
  }

  @override
  String migrationScheduleSemanticsSplit(
    String number,
    String amount,
    String state,
  ) {
    return '분⁠할 $number, $amount ZEC, $state.';
  }

  @override
  String migrationScheduleSemanticsSplitConfirming(
    String count,
    String target,
    String height,
  ) {
    return '확⁠인 중, 확⁠인 $count/$target, 예⁠상 완⁠료 블⁠록 $height';
  }

  @override
  String migrationScheduleSemanticsWaitingWindow(String height) {
    return '블⁠록 $height⁠의 구⁠간⁠을 기⁠다⁠리⁠는 중';
  }

  @override
  String migrationScheduleSplitRound(String number) {
    return '분⁠할 $number⁠회⁠차';
  }

  @override
  String get migrationScheduleTitle => '이⁠전 일⁠정';

  @override
  String get migrationScheduleTitlePreparation => '준⁠비 일⁠정';

  @override
  String get migrationScheduleUnavailableBody =>
      'Vizor⁠가 최⁠신 이⁠전 일⁠정⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 저⁠장⁠된 이⁠전 상⁠태⁠는 그⁠대⁠로⁠예⁠요.';

  @override
  String get migrationScheduleUnavailableTitle => '이⁠전 일⁠정⁠을 불⁠러⁠올 수 없⁠어⁠요';

  @override
  String get migrationScheduleWaitingToBeMined => '블⁠록 포⁠함 대⁠기 중';

  @override
  String migrationScheduleWindow(String height) {
    return '구⁠간 #$height';
  }

  @override
  String migrationSemanticsNote(String number, String amount, String status) {
    return '노⁠트 $number: $amount ZEC, $status.';
  }

  @override
  String get migrationSemanticsNotesOrder =>
      '예⁠상 처⁠리 순⁠서⁠대⁠로 나⁠열⁠한 이⁠전 노⁠트⁠예⁠요.';

  @override
  String get migrationSemanticsPreparingNotes => '이⁠전 노⁠트⁠를 준⁠비⁠하⁠고 있⁠어⁠요.';

  @override
  String migrationSignBatch(String number) {
    return '배⁠치 #$number 서⁠명';
  }

  @override
  String get migrationSignWithKeystone => 'Keystone⁠으⁠로 서⁠명';

  @override
  String get migrationStageFinish => '마⁠무⁠리';

  @override
  String get migrationStageMigration => '이⁠전';

  @override
  String get migrationStagePreparation => '준⁠비';

  @override
  String get migrationStatusAttentionBody =>
      'Ironwood 전⁠환⁠을 마⁠치⁠기 전⁠에 Vizor⁠에⁠서 복⁠구 가⁠능⁠한 이⁠전 오⁠류⁠가 발⁠생⁠했⁠어⁠요.';

  @override
  String get migrationStatusAttentionFooter =>
      '자⁠금⁠은 잃⁠지 않⁠았⁠어⁠요. Vizor⁠가 동⁠기⁠화⁠되⁠어 온⁠라⁠인⁠인⁠지 확⁠인⁠한 뒤 이⁠전⁠을 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get migrationStatusAttentionTitle => '이⁠전 확⁠인 필⁠요';

  @override
  String get migrationStatusBroadcasted => '전⁠송⁠됨';

  @override
  String get migrationStatusBroadcastingBody =>
      'Vizor⁠가 준⁠비⁠된 Ironwood 이⁠전 거⁠래⁠를 전⁠송⁠하⁠고 있⁠어⁠요.';

  @override
  String get migrationStatusBroadcastingButton => '전⁠송 중';

  @override
  String get migrationStatusCompleteBody => '자⁠금⁠이 Ironwood 풀⁠로 이⁠동⁠했⁠어⁠요.';

  @override
  String get migrationStatusCompleteFooter =>
      '홈⁠으⁠로 돌⁠아⁠가 Vizor⁠를 계⁠속 사⁠용⁠할 수 있⁠어⁠요.';

  @override
  String get migrationStatusCompleteTitle => '이⁠전 완⁠료';

  @override
  String get migrationStatusConfirmingBody =>
      '이⁠전 거⁠래⁠를 전⁠송⁠했⁠어⁠요. Vizor⁠가 네⁠트⁠워⁠크 확⁠인⁠을 기⁠다⁠리⁠고 있⁠어⁠요.';

  @override
  String get migrationStatusDefaultBody =>
      'Vizor⁠가 현⁠재 Ironwood 이⁠전 상⁠태⁠를 추⁠적⁠하⁠고 있⁠어⁠요.';

  @override
  String get migrationStatusDefaultButton => '이⁠전 진⁠행 중';

  @override
  String get migrationStatusDefaultFooter =>
      '이 상⁠태⁠는 이⁠전 흐⁠름⁠을 연⁠결⁠하⁠는 동⁠안 진⁠단⁠용⁠으⁠로 표⁠시⁠돼⁠요.';

  @override
  String get migrationStatusDefaultTitle => '이⁠전 상⁠태';

  @override
  String get migrationStatusLeaveFooter =>
      '이 화⁠면⁠을 나⁠가⁠도 돼⁠요.\n단, Vizor⁠는 계⁠속 열⁠어 두⁠세⁠요.';

  @override
  String get migrationStatusLedgerUnsupported =>
      '이 흐⁠름⁠은 일⁠괄 서⁠명⁠이 필⁠요⁠해⁠서 Ledger 비⁠공⁠개 이⁠전⁠은 지⁠원⁠하⁠지 않⁠아⁠요.';

  @override
  String get migrationStatusMigratingTitle => '이⁠전 중...';

  @override
  String get migrationStatusPausedBody =>
      '비⁠공⁠개 이⁠전⁠이 다⁠음 작⁠업 전⁠에 일⁠시 중⁠지⁠되⁠었⁠어⁠요.';

  @override
  String get migrationStatusPausedButton => '일⁠시 중⁠지⁠됨';

  @override
  String get migrationStatusPausedFooter =>
      '이⁠전 실⁠행⁠을 다⁠시 시⁠작⁠할 때⁠까⁠지 새 거⁠래⁠를 준⁠비⁠하⁠지 않⁠아⁠요.';

  @override
  String get migrationStatusPausedTitle => '이⁠전 일⁠시 중⁠지⁠됨';

  @override
  String get migrationStatusPendingBroadcasts => '전⁠송 대⁠기';

  @override
  String get migrationStatusPreparingBody => '분⁠할 한 번⁠에 보⁠통 약 30⁠분⁠이 걸⁠려⁠요.';

  @override
  String get migrationStatusPreparingTitle => '준⁠비 중...';

  @override
  String get migrationStatusReadyBody =>
      '비⁠공⁠개 분⁠할⁠이 준⁠비⁠되⁠었⁠어⁠요. 다⁠음 단⁠계⁠에⁠서 Ironwood 이⁠전 배⁠치⁠를 준⁠비⁠해⁠요.';

  @override
  String get migrationStatusReadyFooter =>
      '이⁠전⁠을 계⁠속⁠하⁠면 예⁠정⁠된 시⁠점⁠에 Ironwood 거⁠래⁠를 준⁠비⁠하⁠고 전⁠송⁠해⁠요.';

  @override
  String get migrationStatusReadyTitle => '이⁠전 준⁠비 완⁠료';

  @override
  String get migrationStatusScheduledBody =>
      '이⁠전 거⁠래⁠가 준⁠비⁠되⁠었⁠고 예⁠약⁠된 전⁠송 시⁠간⁠을 기⁠다⁠리⁠고 있⁠어⁠요.';

  @override
  String get migrationStatusScheduledFooter =>
      'Vizor⁠가 열⁠려 있⁠는 동⁠안 이⁠전 작⁠업⁠기⁠가 예⁠약⁠된 전⁠송⁠을 진⁠행⁠해⁠요.';

  @override
  String get migrationStatusScheduledTitle => '전⁠송 예⁠약⁠됨';

  @override
  String get migrationStatusSplitProgress => '분⁠할 진⁠행';

  @override
  String get migrationStatusUnavailableBody =>
      'Vizor⁠가 현⁠재 Ironwood 이⁠전 상⁠태⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 상⁠태⁠를 확⁠인⁠할 수 있⁠을 때⁠까⁠지 새 이⁠전⁠은 시⁠작⁠되⁠지 않⁠아⁠요.';

  @override
  String get migrationStatusUnavailableHint =>
      '홈⁠으⁠로 돌⁠아⁠가 동⁠기⁠화⁠가 새⁠로 고⁠쳐⁠진 뒤 다⁠시 시⁠도⁠하⁠세⁠요. 이⁠미 진⁠행 중⁠인 이⁠전⁠이 있⁠다⁠면 저⁠장⁠된 상⁠태⁠를 읽⁠을 수 있⁠게 된 후 Vizor⁠가 이⁠어⁠서 진⁠행⁠해⁠요.';

  @override
  String get migrationStatusUnavailableTitle => '이⁠전 상⁠태⁠를 확⁠인⁠할 수 없⁠어⁠요';

  @override
  String get migrationSummaryCurrentBlock => '현⁠재 블⁠록';

  @override
  String get migrationSummaryEstCompletion => '예⁠상 완⁠료';

  @override
  String get migrationSummaryLeftToMigrate => '남⁠은 이⁠전 금⁠액';

  @override
  String get migrationSummaryOverallProgress => '전⁠체 진⁠행⁠률';

  @override
  String migrationTransactionOrdinal(String ordinal) {
    return '거⁠래 $ordinal';
  }

  @override
  String migrationTransactionOrdinalOfTotal(String ordinal, String total) {
    return '거⁠래 $ordinal/$total';
  }

  @override
  String get migrationUpgradeStopBody =>
      '업⁠그⁠레⁠이⁠드 전⁠에 서⁠명⁠한 전⁠송⁠은 업⁠그⁠레⁠이⁠드 후⁠에 보⁠낼 수 없⁠어⁠요. 자⁠금⁠은 안⁠전⁠해⁠요.';

  @override
  String get migrationUpgradeStopMoveRemainingLabel => '남⁠은 잔⁠액 이⁠전⁠하⁠기';

  @override
  String get migrationUpgradeStopMovedLabel => 'Ironwood⁠로 이⁠전⁠됨';

  @override
  String get migrationUpgradeStopRemainingLabel => '아⁠직 Orchard⁠에 있⁠음';

  @override
  String get migrationUpgradeStopRingMessage => '네⁠트⁠워⁠크\n업⁠그⁠레⁠이⁠드⁠로 중⁠단⁠됨';

  @override
  String get migrationView => '보⁠기';

  @override
  String get migrationViewSchedule => '일⁠정 보⁠기';

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
  String get onboardingAddressShieldedTitleMobile => '차⁠폐 주⁠소';

  @override
  String get onboardingAddressTransparentDescription =>
      '주⁠소⁠는 t⁠로 시⁠작⁠하⁠며 Bitcoin⁠과 비⁠슷⁠해⁠요. 이 주⁠소⁠의 잔⁠액⁠과 거⁠래 내⁠역⁠은 누⁠구⁠나 볼 수 있⁠어⁠요.';

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
  String get payAddToContacts => '연⁠락⁠처⁠에 추⁠가';

  @override
  String payAddressSemantics(String address) {
    return '주⁠소 $address';
  }

  @override
  String get payAmountChooseAsset => '결⁠제 자⁠산 선⁠택';

  @override
  String payAmountEnterIn(String symbol) {
    return '$symbol 단⁠위⁠로 금⁠액 입⁠력';
  }

  @override
  String get payAmountEstimated => '예⁠상:';

  @override
  String get payAmountEstimatedSpend => '예⁠상 지⁠출';

  @override
  String get payAmountPayingFrom => '결⁠제 출⁠처';

  @override
  String get payAmountPayingIn => '결⁠제 자⁠산';

  @override
  String get payBackHome => '홈';

  @override
  String get payFetchingQuote => '견⁠적 가⁠져⁠오⁠는 중';

  @override
  String get payNewAddressDetected => '새 주⁠소⁠가 감⁠지⁠되⁠었⁠어⁠요.';

  @override
  String get payNewAddressWarning => '이 주⁠소⁠와 거⁠래⁠한 적⁠이 없⁠어⁠요.';

  @override
  String payRecentDaysAgo(int days) {
    return '$days⁠일 전';
  }

  @override
  String payRecentHoursAgo(int hours) {
    return '$hours⁠시⁠간 전';
  }

  @override
  String payRecentMinutesAgo(int minutes) {
    return '$minutes⁠분 전';
  }

  @override
  String get payRecentlySent => '최⁠근 보⁠낸 주⁠소';

  @override
  String get payRecents => '최⁠근';

  @override
  String get payRecipientAddressHint => '주⁠소⁠를 붙⁠여⁠넣⁠거⁠나 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get payRecipientAddressLabel => '받⁠는 주⁠소';

  @override
  String get payRecipientScanQr => 'QR 코⁠드 스⁠캔';

  @override
  String get payRefreshingQuote => '견⁠적 새⁠로⁠고⁠침 중';

  @override
  String get payReviewConfirmPay => '확⁠인 및 결⁠제';

  @override
  String get payReviewConvertedAmount => '변⁠환 금⁠액';

  @override
  String get payReviewPaying => '결⁠제 금⁠액';

  @override
  String get payReviewQuoteExpired => '견⁠적⁠이 만⁠료⁠되⁠었⁠어⁠요';

  @override
  String get payReviewQuoteExpiresIn => '견⁠적 만⁠료⁠까⁠지 ';

  @override
  String get payReviewRefreshQuote => '견⁠적 새⁠로⁠고⁠침';

  @override
  String get payReviewRefreshTheQuote => '견⁠적 새⁠로⁠고⁠침';

  @override
  String get payReviewReturnToPay => '결⁠제⁠로 돌⁠아⁠가⁠기';

  @override
  String get payReviewUnknownAddress => '알 수 없⁠는 주⁠소';

  @override
  String get paySaveContactError => '연⁠락⁠처⁠를 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get paySaving => '저⁠장 중';

  @override
  String get payScanBarrierDismiss => '닫⁠기';

  @override
  String get payScanCaption => '받⁠는 주⁠소 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get payScanPermissionTitle => '받⁠는 주⁠소 스⁠캔';

  @override
  String get payScanQrSubtitle => '카⁠메⁠라⁠로 주⁠소⁠를 스⁠캔⁠해⁠요';

  @override
  String get payScanQrTitle => 'QR 코⁠드 스⁠캔';

  @override
  String get paySelectRecipient => '받⁠는 사⁠람 선⁠택';

  @override
  String get payStepRecipient => '받⁠는 사⁠람';

  @override
  String get payStepReview => '검⁠토';

  @override
  String get paySubmittedFailedBody =>
      '결⁠제⁠를 제⁠출⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get paySubmittedGoToActivity => '활⁠동 내⁠역⁠으⁠로 이⁠동';

  @override
  String get paySubmittedStatusUncertainNotice =>
      '결⁠제 상⁠태⁠가 확⁠실⁠하⁠지 않⁠아⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 활⁠동 내⁠역⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get paySubmittedSubmittingBody => '결⁠제⁠를 네⁠트⁠워⁠크⁠에 제⁠출⁠하⁠고 있⁠어⁠요...';

  @override
  String get paySubmittedSubmittingTitle => '결⁠제 제⁠출 중...';

  @override
  String get paySubmittedSucceededBody =>
      '곧 온⁠체⁠인⁠에⁠서 확⁠인⁠될 거⁠예⁠요.\n활⁠동 내⁠역⁠에⁠서 확⁠인⁠해 보⁠세⁠요.';

  @override
  String get paySubmittedSucceededTitle => '결⁠제⁠를\n제⁠출⁠했⁠어⁠요';

  @override
  String get paySubmittedUnavailableNotice =>
      '이 결⁠제⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 최⁠신 상⁠태⁠는 활⁠동 내⁠역⁠에⁠서 확⁠인⁠하⁠세⁠요.';

  @override
  String get paySubmittedUnavailableTitle => '결⁠제⁠를 불⁠러⁠올 수 없⁠어⁠요';

  @override
  String get paySubmittedUncertainTitle => '결⁠제 상⁠태⁠가\n확⁠실⁠하⁠지 않⁠아⁠요';

  @override
  String payTitleAmount(String symbol) {
    return '$symbol⁠로 결⁠제';
  }

  @override
  String get paymentUriExpired =>
      '이 요⁠청 링⁠크⁠의 유⁠효 시⁠간⁠이 지⁠났⁠어⁠요. 결⁠제⁠하⁠려⁠면 다⁠시 열⁠어 주⁠세⁠요.';

  @override
  String get paymentUriMalformed =>
      '이 요⁠청 링⁠크⁠가 올⁠바⁠르⁠지 않⁠아⁠요. 보⁠낸 사⁠람⁠에⁠게 새 링⁠크⁠를 요⁠청⁠해 주⁠세⁠요.';

  @override
  String get paymentUriMigrationSendGate =>
      '요⁠청 링⁠크⁠를 열⁠기 전⁠에 Ironwood 마⁠이⁠그⁠레⁠이⁠션⁠을 마⁠쳐 주⁠세⁠요.';

  @override
  String get paymentUriNoWallet =>
      '요⁠청 링⁠크⁠를 열⁠기 전⁠에 지⁠갑⁠을 설⁠정⁠하⁠거⁠나 가⁠져⁠와 주⁠세⁠요.';

  @override
  String get paymentUriOnboarding => '요⁠청 링⁠크⁠를 열⁠기 전⁠에 지⁠갑 설⁠정⁠을 마⁠쳐 주⁠세⁠요.';

  @override
  String get paymentUriReplaced =>
      '가⁠장 최⁠근 요⁠청 링⁠크⁠만 남⁠아 있⁠어⁠요. 이⁠전 요⁠청⁠을 결⁠제⁠하⁠려⁠면 해⁠당 링⁠크⁠를 다⁠시 열⁠어 주⁠세⁠요.';

  @override
  String get paymentUriUnavailable =>
      'Vizor⁠에⁠서 이 요⁠청 링⁠크⁠를 열 수 없⁠었⁠어⁠요. 지⁠갑⁠이 로⁠드⁠된 후 다⁠시 열⁠어 주⁠세⁠요.';

  @override
  String get paymentUriUnsupported =>
      '이 요⁠청 링⁠크⁠는 Vizor⁠가 아⁠직 지⁠원⁠하⁠지 않⁠는 기⁠능⁠을 사⁠용⁠해⁠요.';

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
  String get receiveAboutAddressType => '이 주⁠소 유⁠형 알⁠아⁠보⁠기';

  @override
  String get receiveAddressCouldNotLoad =>
      '주⁠소⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get receiveAddressLoadFailed =>
      '주⁠소⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 잠⁠시 후 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get receiveCopyTransparentAddress => '투⁠명 주⁠소 복⁠사';

  @override
  String receiveErrorWithDetails(String message, String details) {
    return '$message\n세⁠부 정⁠보: $details';
  }

  @override
  String get receiveGenerateNewShieldedAddress => '새 차⁠폐 주⁠소 만⁠들⁠기';

  @override
  String get receiveInfoShieldedDiversified =>
      '새 주⁠소⁠는 모⁠두 같⁠은 키⁠에⁠서 파⁠생⁠된 다⁠변⁠화 주⁠소⁠예⁠요. 모⁠두 같⁠은 지⁠갑⁠으⁠로 받⁠아⁠요.';

  @override
  String get receiveInfoShieldedHiddenDesktop =>
      '거⁠래 세⁠부 정⁠보(보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액)는 온⁠체⁠인⁠에⁠서 암⁠호⁠화⁠되⁠어 숨⁠겨⁠져⁠요.';

  @override
  String get receiveInfoShieldedHiddenMobile =>
      '거⁠래 세⁠부 정⁠보(보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액)는 온⁠체⁠인⁠에⁠서 암⁠호⁠화⁠되⁠어 숨⁠겨⁠져⁠요.';

  @override
  String get receiveInfoShieldedRenewClick =>
      '새 Zcash 차⁠폐 주⁠소⁠는 갱⁠신 버⁠튼⁠을 클⁠릭⁠할 때⁠만 만⁠들⁠어⁠져⁠요.';

  @override
  String get receiveInfoShieldedRenewTap =>
      '새 Zcash 차⁠폐 주⁠소⁠는 갱⁠신 버⁠튼⁠을 탭⁠할 때⁠만 만⁠들⁠어⁠져⁠요.';

  @override
  String get receiveInfoShieldedSubtitle =>
      '기⁠본⁠적⁠으⁠로 강⁠력⁠한 프⁠라⁠이⁠버⁠시⁠를 제⁠공⁠해⁠요.';

  @override
  String get receiveInfoTransparentExchanges =>
      '투⁠명⁠성⁠이⁠나 규⁠제⁠상 명⁠확⁠성⁠이 필⁠요⁠한 거⁠래⁠소⁠에⁠서 흔⁠히 사⁠용⁠해⁠요. 여⁠러 지⁠갑⁠과⁠의 호⁠환⁠성⁠을 위⁠한 기⁠본⁠값⁠이⁠기⁠도 해⁠요.';

  @override
  String get receiveInfoTransparentPublicDesktop =>
      '모⁠든 거⁠래 세⁠부 정⁠보(보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액)가 온⁠체⁠인⁠에 공⁠개⁠돼⁠요.';

  @override
  String get receiveInfoTransparentPublicMobile =>
      '모⁠든 거⁠래 세⁠부 정⁠보(보⁠낸 사⁠람, 받⁠는 사⁠람, 금⁠액)가 온⁠체⁠인⁠에 공⁠개⁠돼⁠요.';

  @override
  String get receiveInfoTransparentRotates =>
      '이 주⁠소⁠로 ZEC⁠를 받⁠고 Vizor⁠가 동⁠기⁠화⁠하⁠면 다⁠음 투⁠명 주⁠소⁠로 자⁠동⁠으⁠로 바⁠뀌⁠어⁠요. 이⁠전 주⁠소⁠도 계⁠속 이 지⁠갑⁠에 속⁠해⁠요.';

  @override
  String receiveInfoTransparentShieldFirst(String ticker) {
    return '투⁠명 주⁠소⁠로 $ticker⁠를 받⁠은 뒤⁠에⁠는 Vizor⁠가 잔⁠액⁠을 차⁠폐⁠하⁠도⁠록 안⁠내⁠해⁠요. 차⁠폐⁠하⁠지 않⁠으⁠면 보⁠낼 수 없⁠어⁠요.';
  }

  @override
  String get receiveInfoTransparentSubtitle => '공⁠개⁠적⁠으⁠로 보⁠여⁠요';

  @override
  String get receiveQrSaveFailed =>
      'QR 이⁠미⁠지⁠를 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 다⁠른 폴⁠더⁠를 선⁠택⁠하⁠거⁠나 요⁠청 링⁠크⁠를 대⁠신 복⁠사⁠해 주⁠세⁠요.';

  @override
  String receiveQrSaved(String folder) {
    return 'QR 이⁠미⁠지⁠를 $folder⁠에 저⁠장⁠했⁠어⁠요';
  }

  @override
  String get receiveQrUnavailable => 'QR⁠을 표⁠시⁠할 수 없⁠어⁠요';

  @override
  String get receiveRenewAddressError =>
      '차⁠폐 주⁠소⁠를 새⁠로 만⁠들⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 현⁠재 주⁠소⁠를 계⁠속 사⁠용⁠해 주⁠세⁠요.';

  @override
  String get receiveRequestAmountDecimalsError =>
      '소⁠수⁠점⁠은 8⁠자⁠리⁠까⁠지 입⁠력⁠해 주⁠세⁠요';

  @override
  String get receiveRequestAmountFormatError => '0.5⁠처⁠럼 금⁠액⁠을 입⁠력⁠해 주⁠세⁠요';

  @override
  String get receiveRequestAmountSupplyError => '금⁠액⁠이 ZEC 총 공⁠급⁠량⁠을 넘⁠어⁠요';

  @override
  String receiveRequestButton(String ticker) {
    return '$ticker 요⁠청⁠하⁠기';
  }

  @override
  String get receiveRequestCloseRequest => '요⁠청 닫⁠기';

  @override
  String get receiveRequestCopyFailed =>
      '요⁠청 링⁠크⁠를 복⁠사⁠하⁠지 못⁠했⁠어⁠요. 대⁠신 공⁠유⁠해 보⁠세⁠요.';

  @override
  String get receiveRequestCopyLink => '링⁠크 복⁠사';

  @override
  String get receiveRequestCopyRequestLink => '요⁠청 링⁠크 복⁠사';

  @override
  String get receiveRequestCreate => '요⁠청 만⁠들⁠기';

  @override
  String get receiveRequestEnterZec => 'ZEC⁠로 금⁠액 입⁠력';

  @override
  String get receiveRequestLinkCopied => '요⁠청 링⁠크⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String get receiveRequestMessageHelp =>
      '차⁠폐 주⁠소⁠에⁠서⁠만 쓸 수 있⁠어⁠요. 이 링⁠크⁠를 가⁠진 사⁠람⁠은 누⁠구⁠나 읽⁠을 수 있⁠어⁠요.';

  @override
  String get receiveRequestMessageHint =>
      '링⁠크⁠를 받⁠은 사⁠람⁠은 누⁠구⁠나 이 내⁠용⁠을 읽⁠을 수 있⁠어⁠요';

  @override
  String get receiveRequestSaveQr => 'QR 이⁠미⁠지 저⁠장';

  @override
  String get receiveRequestShare => '요⁠청 공⁠유';

  @override
  String get receiveRequestShareFailed =>
      '이 요⁠청⁠을 공⁠유⁠하⁠지 못⁠했⁠어⁠요. 대⁠신 링⁠크⁠를 복⁠사⁠해 주⁠세⁠요.';

  @override
  String get receiveRequestZecButton => 'ZEC 요⁠청⁠하⁠기';

  @override
  String get receiveShareAddress => '주⁠소 공⁠유';

  @override
  String get receiveShareFailed => '이 주⁠소⁠를 공⁠유⁠하⁠지 못⁠했⁠어⁠요. 대⁠신 복⁠사⁠해 주⁠세⁠요.';

  @override
  String get receiveShareShieldedAddress => '차⁠폐 주⁠소 공⁠유';

  @override
  String get receiveShareTransparentAddress => '투⁠명 주⁠소 공⁠유';

  @override
  String receiveTitle(String ticker) {
    return '$ticker 받⁠기';
  }

  @override
  String get secretPassphraseCopy => '복⁠구 문⁠구 복⁠사';

  @override
  String get secretPassphraseTitle => '복⁠구 문⁠구';

  @override
  String get sendAddMemo => '메⁠모 추⁠가';

  @override
  String get sendAddressTypeTex => 'TEX 주⁠소';

  @override
  String get sendAddressValidationFailed => '주⁠소⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sendAmountCtaEnterAmount => '계⁠속⁠하⁠려⁠면 금⁠액⁠을 입⁠력⁠하⁠세⁠요';

  @override
  String get sendBroadcastCancelledBeforeParams =>
      '증⁠명 매⁠개⁠변⁠수⁠를 내⁠려⁠받⁠기 전⁠에 보⁠내⁠기⁠가 취⁠소⁠됐⁠어⁠요.';

  @override
  String get sendBroadcastDependentIncomplete =>
      '첫 번⁠째 거⁠래⁠는 수⁠락⁠됐⁠지⁠만 이⁠어⁠지⁠는 거⁠래⁠가 완⁠료⁠되⁠지 않⁠았⁠어⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendBroadcastFirstUnknown =>
      '첫 번⁠째 거⁠래⁠는 로⁠컬⁠에 저⁠장⁠됐⁠고 네⁠트⁠워⁠크⁠에 도⁠달⁠했⁠을 수 있⁠지⁠만 확⁠인⁠이 시⁠간 초⁠과⁠됐⁠어⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendBroadcastHardwareExpired =>
      '하⁠드⁠웨⁠어 서⁠명 요⁠청⁠이 전⁠송⁠되⁠기 전⁠에 만⁠료⁠됐⁠어⁠요. 지⁠갑⁠으⁠로 돌⁠아⁠가 동⁠기⁠화⁠가 끝⁠나⁠길 기⁠다⁠린 다⁠음 결⁠제⁠를 다⁠시 검⁠토⁠하⁠고 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendBroadcastIncomplete =>
      '거⁠래 전⁠송⁠이 완⁠료⁠되⁠지 않⁠았⁠어⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendBroadcastLedgerFirstUnknown =>
      '첫 번⁠째 거⁠래⁠가 네⁠트⁠워⁠크⁠에 도⁠달⁠했⁠을 수 있⁠지⁠만 확⁠인⁠이 시⁠간 초⁠과⁠됐⁠어⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendBroadcastLedgerNotStored =>
      '거⁠래⁠가 네⁠트⁠워⁠크⁠에 도⁠달⁠했⁠지⁠만 Vizor⁠가 로⁠컬⁠에 저⁠장⁠하⁠지 못⁠했⁠어⁠요. 동⁠기⁠화⁠나 탐⁠색⁠기⁠에⁠서 최⁠신 상⁠태⁠를 확⁠인⁠하⁠기 전⁠에⁠는 다⁠시 보⁠내⁠지 마⁠세⁠요.';

  @override
  String get sendBroadcastLedgerRejected =>
      '네⁠트⁠워⁠크⁠가 거⁠래⁠를 거⁠부⁠했⁠어⁠요. 나⁠중⁠에 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendBroadcastLocalRetry =>
      '거⁠래⁠가 로⁠컬⁠에⁠서 만⁠들⁠어⁠졌⁠지⁠만 전⁠송⁠하⁠지 못⁠했⁠어⁠요. 네⁠트⁠워⁠크⁠가 연⁠결⁠되⁠면 자⁠동⁠으⁠로 다⁠시 시⁠도⁠해⁠요. 이 거⁠래⁠가 만⁠료⁠되⁠기 전⁠에⁠는 다⁠시 보⁠내⁠지 마⁠세⁠요.';

  @override
  String get sendBroadcastMnemonicMissing => '이 계⁠정⁠의 복⁠구 문⁠구⁠를 찾⁠을 수 없⁠어⁠요.';

  @override
  String get sendBroadcastPartial =>
      '일⁠부 거⁠래⁠는 전⁠송⁠됐⁠고 나⁠머⁠지⁠는 자⁠동⁠으⁠로 다⁠시 시⁠도⁠해⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendBroadcastProofParamsRequired =>
      '서⁠명⁠된 이 거⁠래⁠를 다⁠시 시⁠도⁠하⁠려⁠면 증⁠명 매⁠개⁠변⁠수⁠가 필⁠요⁠해⁠요.';

  @override
  String get sendBroadcastRejectedLocal =>
      '거⁠래⁠가 로⁠컬⁠에⁠서 만⁠들⁠어⁠졌⁠지⁠만 네⁠트⁠워⁠크⁠에 도⁠달⁠하⁠지 않⁠았⁠어⁠요. 지⁠갑⁠이 만⁠료⁠될 때⁠까⁠지 계⁠속 다⁠시 시⁠도⁠해⁠요. 이 거⁠래⁠가 만⁠료⁠되⁠기 전⁠에⁠는 다⁠시 보⁠내⁠지 마⁠세⁠요.';

  @override
  String get sendBroadcastTrackingFailed =>
      '거⁠래⁠가 네⁠트⁠워⁠크⁠에 도⁠달⁠했⁠지⁠만 로⁠컬 추⁠적⁠에 실⁠패⁠했⁠어⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동⁠이⁠나 탐⁠색⁠기⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendCalculatingMax => '최⁠대 금⁠액⁠을 계⁠산⁠하⁠고 있⁠어⁠요';

  @override
  String get sendContactPickerEmpty => 'Zcash 연⁠락⁠처⁠가 없⁠어⁠요';

  @override
  String get sendContactPickerTitle => 'Zcash 연⁠락⁠처';

  @override
  String get sendDonationAddressTitle => 'Vizor 후⁠원 주⁠소';

  @override
  String get sendEnterAddressToContinue => '계⁠속⁠하⁠려⁠면 주⁠소⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String sendEnterAmountInCurrency(String currency) {
    return '$currency⁠로 금⁠액 입⁠력';
  }

  @override
  String get sendEnterValidAddress => '올⁠바⁠른 주⁠소⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String get sendErrorCouldNotBeSent =>
      '거⁠래⁠를 보⁠내⁠지 못⁠했⁠어⁠요. 지⁠갑⁠으⁠로 돌⁠아⁠가 최⁠신 상⁠태⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendErrorDonationFailed => '후⁠원⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendErrorExpiredBeforeSent => '거⁠래⁠가 전⁠송⁠되⁠기 전⁠에 만⁠료⁠됐⁠어⁠요.';

  @override
  String get sendErrorExpiredTryAgain =>
      '거⁠래⁠가 전⁠송⁠되⁠기 전⁠에 만⁠료⁠됐⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendErrorInsufficientShielded =>
      '금⁠액⁠과 수⁠수⁠료⁠를 낼 차⁠폐 잔⁠액⁠이 부⁠족⁠해⁠요.';

  @override
  String get sendErrorNetwork =>
      '네⁠트⁠워⁠크 오⁠류⁠예⁠요. 연⁠결⁠을 확⁠인⁠하⁠고 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendErrorPartiallySent =>
      '거⁠래⁠의 일⁠부⁠가 이⁠미 전⁠송⁠됐⁠어⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 활⁠동⁠에⁠서 전⁠송⁠된 내⁠역⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendErrorRejectedTryAgain =>
      '네⁠트⁠워⁠크⁠가 이 거⁠래⁠를 거⁠부⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendErrorRejectedTryLater =>
      '네⁠트⁠워⁠크⁠가 이 거⁠래⁠를 거⁠부⁠했⁠어⁠요. 나⁠중⁠에 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendErrorSendFailed => '보⁠내⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendErrorSyncFinishing =>
      '지⁠갑 동⁠기⁠화⁠를 마⁠무⁠리⁠하⁠는 중⁠이⁠에⁠요. 잠⁠시 후 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendFeeAboutSemantics => '거⁠래 수⁠수⁠료 안⁠내';

  @override
  String get sendFeeUnavailableTryAgain =>
      '수⁠수⁠료⁠를 확⁠인⁠할 수 없⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendFeeUpdatedAfterSync =>
      '동⁠기⁠화 후 수⁠수⁠료⁠가 바⁠뀌⁠었⁠어⁠요. 다⁠시 검⁠토⁠하⁠고 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendFinishingSync => '지⁠갑 동⁠기⁠화⁠를 마⁠무⁠리⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get sendInsufficientBalanceIncludingFeeShielded =>
      '수⁠수⁠료⁠를 포⁠함⁠하⁠면 차⁠폐 잔⁠액⁠이 부⁠족⁠해⁠요';

  @override
  String get sendInsufficientBalanceIncludingFeeTex =>
      '수⁠수⁠료⁠를 포⁠함⁠하⁠면 잔⁠액⁠이 부⁠족⁠해⁠요';

  @override
  String get sendInsufficientBalanceSentenceShielded => '차⁠폐 잔⁠액⁠이 부⁠족⁠해⁠요.';

  @override
  String get sendInsufficientBalanceSentenceTex => '잔⁠액⁠이 부⁠족⁠해⁠요.';

  @override
  String get sendInsufficientBalanceShielded => '차⁠폐 잔⁠액⁠이 부⁠족⁠해⁠요';

  @override
  String get sendInsufficientBalanceTex => '잔⁠액⁠이 부⁠족⁠해⁠요';

  @override
  String get sendInsufficientBalanceToCoverFeeShielded =>
      '수⁠수⁠료⁠를 낼 차⁠폐 잔⁠액⁠이 부⁠족⁠해⁠요';

  @override
  String get sendInsufficientBalanceToCoverFeeTex => '수⁠수⁠료⁠를 낼 잔⁠액⁠이 부⁠족⁠해⁠요';

  @override
  String sendInsufficientBalanceWithFeeShielded(String fee) {
    return '차⁠폐 잔⁠액⁠이 부⁠족⁠해⁠요 (수⁠수⁠료: $fee)';
  }

  @override
  String sendInsufficientBalanceWithFeeTex(String fee) {
    return '잔⁠액⁠이 부⁠족⁠해⁠요 (수⁠수⁠료: $fee)';
  }

  @override
  String get sendInvalidAddress => '올⁠바⁠르⁠지 않⁠은 주⁠소⁠예⁠요';

  @override
  String get sendInvalidAmount => '올⁠바⁠르⁠지 않⁠은 금⁠액⁠이⁠에⁠요';

  @override
  String get sendKeystoneConfirmTitle => 'Keystone⁠으⁠로 확⁠인';

  @override
  String get sendKeystonePrepareFailedGoBack =>
      'Keystone 서⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 뒤⁠로 가⁠서 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendKeystonePrepareFailedReturnToSend =>
      'Keystone 서⁠명⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 보⁠내⁠기⁠로 돌⁠아⁠가 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendKeystonePreparing => '준⁠비⁠하⁠는 중';

  @override
  String get sendKeystoneQrMismatch =>
      '이 QR 코⁠드⁠는 현⁠재 Keystone 서⁠명 요⁠청⁠과 일⁠치⁠하⁠지 않⁠아⁠요.';

  @override
  String get sendKeystoneScanCameraOnly =>
      'Keystone 서⁠명⁠은 카⁠메⁠라 QR 스⁠캔⁠만 지⁠원⁠해⁠요. 카⁠메⁠라⁠를 연⁠결⁠하⁠고 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendKeystoneScanDecodeFailed =>
      '이 QR 코⁠드⁠를 Keystone 거⁠래 서⁠명⁠으⁠로 해⁠석⁠할 수 없⁠어⁠요.';

  @override
  String get sendKeystoneScanHoldSteady => 'QR 코⁠드⁠를 카⁠메⁠라 앞⁠에 고⁠정⁠해 주⁠세⁠요';

  @override
  String get sendKeystoneScanNow =>
      '지⁠금 스⁠캔⁠하⁠세⁠요. 증⁠명⁠이 준⁠비⁠되⁠면 서⁠명 가⁠져⁠오⁠기⁠가 활⁠성⁠화⁠돼⁠요.';

  @override
  String get sendKeystoneScanReading => '서⁠명⁠을 읽⁠는 중...';

  @override
  String get sendKeystoneScanSubtitle => 'Keystone⁠으⁠로 스⁠캔⁠하⁠세⁠요';

  @override
  String get sendKeystoneScanToFinish =>
      '보⁠내⁠기⁠를 마⁠치⁠려⁠면 Keystone⁠의 QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get sendKeystoneScanUnexpectedTransaction =>
      'Keystone⁠에⁠서 서⁠명⁠된 거⁠래 QR⁠을 연 다⁠음 다⁠시 스⁠캔⁠하⁠세⁠요.';

  @override
  String sendKeystoneTexTwoApprovals(int index) {
    return '이 TEX 보⁠내⁠기⁠는 Keystone⁠에⁠서 두 번 승⁠인⁠해⁠야 해⁠요. $index/2⁠번⁠째 거⁠래⁠를 스⁠캔⁠하⁠세⁠요.';
  }

  @override
  String sendKeystoneTransactionOfTwo(int index) {
    return '거⁠래 $index/2';
  }

  @override
  String sendLedgerConnectAndUnlock(String instruction) {
    return 'Ledger⁠를 연⁠결⁠하⁠고 잠⁠금⁠을 해⁠제⁠하⁠세⁠요. $instruction';
  }

  @override
  String get sendLedgerCouldNotFinishTitle => '거⁠래⁠를 완⁠료⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sendLedgerCouldNotPrepare =>
      'Vizor⁠가 거⁠래⁠를 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendLedgerCouldNotSaveTitle => '서⁠명⁠한 거⁠래⁠를 저⁠장⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sendLedgerCouldNotVerifySaved =>
      'Vizor⁠가 저⁠장⁠된 거⁠래⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 서⁠명⁠하⁠거⁠나 보⁠내⁠지 마⁠세⁠요.';

  @override
  String get sendLedgerCreateNewTransaction => '새 거⁠래 만⁠들⁠기';

  @override
  String get sendLedgerExpiredMessage =>
      '이 거⁠래⁠는 더 이⁠상 서⁠명⁠할 수 없⁠어⁠요. 새 거⁠래⁠를 만⁠들⁠어 검⁠토⁠하⁠세⁠요.';

  @override
  String get sendLedgerKeepOpenRetry =>
      'Vizor⁠를 열⁠어 둔 채⁠로 다⁠시 시⁠도⁠하⁠세⁠요. Ledger⁠에⁠서 다⁠시 승⁠인⁠하⁠지 않⁠아⁠도 돼⁠요.';

  @override
  String get sendLedgerKeepOpenRetrySaving =>
      'Vizor⁠를 열⁠어 둔 채⁠로 저⁠장⁠을 다⁠시 시⁠도⁠하⁠세⁠요. Ledger⁠에⁠서 다⁠시 승⁠인⁠하⁠지 않⁠아⁠도 돼⁠요.';

  @override
  String get sendLedgerNeedsAttentionTitle => 'Ledger 확⁠인⁠이 필⁠요⁠해⁠요';

  @override
  String get sendLedgerRejectedOnDevice => 'Ledger⁠에⁠서 거⁠래⁠가 거⁠부⁠됐⁠어⁠요.';

  @override
  String get sendLedgerSignaturePreservedMessage =>
      'Ledger 서⁠명⁠이 보⁠존⁠돼 있⁠어⁠요. 다⁠른 거⁠래⁠를 승⁠인⁠하⁠지 말⁠고 저⁠장⁠만 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendLedgerSignedNeedsAttentionTitle => '서⁠명⁠한 거⁠래⁠를 확⁠인⁠해⁠야 해⁠요';

  @override
  String get sendLedgerSigningIncomplete =>
      'Ledger 서⁠명⁠을 완⁠료⁠하⁠지 못⁠했⁠어⁠요. 기⁠기⁠를 확⁠인⁠하⁠고 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendLedgerSigningUnavailableTitle => 'Ledger⁠로 서⁠명⁠할 수 없⁠어⁠요';

  @override
  String get sendLedgerStatusNewTransactionRequired => '새 거⁠래⁠가 필⁠요⁠해⁠요';

  @override
  String get sendLedgerStatusRecoveryRequired => '복⁠구⁠가 필⁠요⁠해⁠요';

  @override
  String get sendLedgerStatusSignaturePreserved => '서⁠명⁠이 보⁠존⁠돼 있⁠어⁠요';

  @override
  String get sendLedgerStatusUnsupportedTransaction => '지⁠원⁠하⁠지 않⁠는 거⁠래⁠예⁠요';

  @override
  String sendLoadError(String error) {
    return '문⁠제⁠가 생⁠겼⁠어⁠요. 잠⁠시 후 다⁠시 시⁠도⁠하⁠세⁠요.\n\n자⁠세⁠한 내⁠용: $error';
  }

  @override
  String get sendMaxButton => '최⁠대';

  @override
  String get sendMaxNeedsAddress => '최⁠대 금⁠액⁠을 쓰⁠려⁠면 올⁠바⁠른 주⁠소⁠를 입⁠력⁠하⁠세⁠요';

  @override
  String get sendMaxUnavailable => '최⁠대 금⁠액⁠을 확⁠인⁠할 수 없⁠어⁠요';

  @override
  String get sendMemoAddShortEncrypted => '짧⁠은 암⁠호⁠화 메⁠시⁠지 추⁠가';

  @override
  String get sendMemoClear => '메⁠모 지⁠우⁠기';

  @override
  String get sendMemoCollapse => '접⁠기';

  @override
  String get sendMemoEncryptedHint => '암⁠호⁠화⁠되⁠며 차⁠폐 주⁠소⁠에⁠서⁠만 쓸 수 있⁠어⁠요.';

  @override
  String get sendMemoRecipientOnly => '받⁠는 사⁠람⁠만 읽⁠을 수 있⁠어⁠요';

  @override
  String get sendMemoSheetAdd => '메⁠모 추⁠가';

  @override
  String get sendMemoShieldedOnly => '메⁠시⁠지⁠는 차⁠폐 주⁠소⁠에⁠서⁠만 쓸 수 있⁠어⁠요';

  @override
  String get sendMemoWhitespaceOnly => '공⁠백⁠만 있⁠어⁠요';

  @override
  String get sendOpenContacts => '연⁠락⁠처 열⁠기';

  @override
  String get sendPasteAction => '붙⁠여⁠넣⁠기';

  @override
  String get sendPaymentRequestAmountNotSpecified => '금⁠액⁠이 지⁠정⁠되⁠지 않⁠았⁠어⁠요';

  @override
  String get sendPaymentRequestCheckAgain => '다⁠시 확⁠인';

  @override
  String get sendPaymentRequestCheckBeforePayBody =>
      '다⁠른 앱⁠이 요⁠청 링⁠크⁠의 주⁠소⁠나 금⁠액⁠을 바⁠꿀 수 있⁠어⁠요.';

  @override
  String get sendPaymentRequestCheckBeforePayTitle => '결⁠제⁠하⁠기 전⁠에 확⁠인⁠하⁠세⁠요';

  @override
  String get sendPaymentRequestCheckFailed => '이 요⁠청⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sendPaymentRequestCheckGeneric =>
      '이 요⁠청⁠을 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 내⁠용⁠을 수⁠정⁠해 주⁠세⁠요';

  @override
  String get sendPaymentRequestCheckNetwork =>
      '네⁠트⁠워⁠크⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요. 연⁠결 상⁠태⁠를 확⁠인⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요';

  @override
  String get sendPaymentRequestCheckNoAccount =>
      '선⁠택⁠된 계⁠정⁠이 없⁠어⁠요. 계⁠정⁠을 선⁠택⁠한 다⁠음 이 링⁠크⁠를 다⁠시 열⁠어 주⁠세⁠요';

  @override
  String get sendPaymentRequestCheckNoAmount =>
      '이 링⁠크⁠에⁠는 결⁠제⁠할 수 있⁠는 금⁠액⁠이 없⁠어⁠요. 금⁠액⁠을 입⁠력⁠하⁠고 계⁠속⁠해 주⁠세⁠요';

  @override
  String get sendPaymentRequestCheckUpgradeHold =>
      '네⁠트⁠워⁠크 업⁠그⁠레⁠이⁠드⁠를 위⁠해 일⁠시 중⁠지⁠됐⁠어⁠요. 몇 분 후⁠에 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get sendPaymentRequestCheckUpgradeScheduleChanged =>
      '네⁠트⁠워⁠크 업⁠그⁠레⁠이⁠드⁠로 마⁠이⁠그⁠레⁠이⁠션 일⁠정⁠이 바⁠뀌⁠었⁠어⁠요. 계⁠획⁠을 확⁠인⁠한 다⁠음 다⁠시 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get sendPaymentRequestClose => '결⁠제 요⁠청 닫⁠기';

  @override
  String get sendPaymentRequestConfirmWithSender =>
      '보⁠낸 사⁠람⁠에⁠게 내⁠용⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendPaymentRequestEnterAmount => '금⁠액 입⁠력';

  @override
  String get sendPaymentRequestHideFullAddress => '받⁠는 전⁠체 주⁠소 숨⁠기⁠기';

  @override
  String get sendPaymentRequestHidePaymentDetails => '결⁠제 상⁠세 숨⁠기⁠기';

  @override
  String get sendPaymentRequestHideRequesterInfo => '요⁠청⁠자 정⁠보 숨⁠기⁠기';

  @override
  String sendPaymentRequestHideRequesterInfoFor(String name) {
    return '$name⁠의 요⁠청⁠자 정⁠보 숨⁠기⁠기';
  }

  @override
  String get sendPaymentRequestInsufficientFunds =>
      '이 금⁠액⁠과 네⁠트⁠워⁠크 수⁠수⁠료⁠를 낼 ZEC⁠가 부⁠족⁠해⁠요';

  @override
  String sendPaymentRequestInsufficientFundsWithSpendable(String spendable) {
    return '이 금⁠액⁠과 네⁠트⁠워⁠크 수⁠수⁠료⁠를 낼 ZEC⁠가 부⁠족⁠해⁠요 ($spendable 사⁠용 가⁠능)';
  }

  @override
  String get sendPaymentRequestInvalidAddress => '받⁠는 주⁠소⁠가 올⁠바⁠르⁠지 않⁠아⁠요';

  @override
  String get sendPaymentRequestLinkDifferentAddress => '링⁠크⁠의 주⁠소⁠가 달⁠랐⁠어⁠요';

  @override
  String get sendPaymentRequestLinkDifferentAmount => '링⁠크⁠의 금⁠액⁠이 달⁠랐⁠어⁠요';

  @override
  String get sendPaymentRequestLinkDifferentDetails => '링⁠크⁠의 내⁠용⁠이 달⁠랐⁠어⁠요';

  @override
  String get sendPaymentRequestLinkDifferentMemo => '링⁠크⁠의 메⁠모⁠가 달⁠랐⁠어⁠요';

  @override
  String get sendPaymentRequestMatchesLink => '링⁠크⁠와 일⁠치⁠해⁠요';

  @override
  String get sendPaymentRequestMemoIncluded => '메⁠모 포⁠함';

  @override
  String get sendPaymentRequestMemoIncludedHint =>
      '메⁠모⁠가 포⁠함⁠되⁠어 있⁠어⁠요. 거⁠래 메⁠모⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendPaymentRequestNameDisclaimer =>
      '이 이⁠름⁠은 요⁠청⁠에 포⁠함⁠된 것⁠이⁠에⁠요. 받⁠는 주⁠소⁠의 주⁠인⁠을 확⁠인⁠해 주⁠지⁠는 않⁠아⁠요.';

  @override
  String get sendPaymentRequestNameSuppliedInRequest =>
      '요⁠청⁠에 포⁠함⁠된 이⁠름⁠이⁠에⁠요.';

  @override
  String get sendPaymentRequestNoteFromRequester => '요⁠청⁠자⁠의 메⁠모';

  @override
  String get sendPaymentRequestPaymentDetails => '결⁠제 상⁠세';

  @override
  String get sendPaymentRequestRecipient => '받⁠는 사⁠람';

  @override
  String get sendPaymentRequestReplacedNotice => '이⁠전 링⁠크⁠를 대⁠체⁠했⁠어⁠요';

  @override
  String get sendPaymentRequestRequestFrom => '요⁠청⁠한 사⁠람';

  @override
  String get sendPaymentRequestReviewLinkDetails => '링⁠크 상⁠세 검⁠토';

  @override
  String get sendPaymentRequestReviewPayment => '결⁠제 검⁠토';

  @override
  String get sendPaymentRequestScanOriginalHint =>
      '원⁠래 QR 코⁠드⁠를 Vizor⁠에⁠서 직⁠접 스⁠캔⁠하⁠세⁠요.';

  @override
  String get sendPaymentRequestShowFullAddress => '받⁠는 전⁠체 주⁠소 보⁠기';

  @override
  String get sendPaymentRequestShowRequesterInfo => '요⁠청⁠자 정⁠보 보⁠기';

  @override
  String sendPaymentRequestShowRequesterInfoFor(String name) {
    return '$name⁠의 요⁠청⁠자 정⁠보 보⁠기';
  }

  @override
  String get sendPaymentRequestSyncStalled =>
      '아⁠직 동⁠기⁠화⁠하⁠는 중⁠이⁠에⁠요. 지⁠갑⁠이 최⁠신 상⁠태⁠가 되⁠면 다⁠시 확⁠인⁠하⁠세⁠요';

  @override
  String get sendPaymentRequestSyncing =>
      '지⁠갑⁠을 아⁠직 동⁠기⁠화⁠하⁠는 중⁠이⁠에⁠요. 끝⁠나⁠면 자⁠동⁠으⁠로 업⁠데⁠이⁠트⁠돼⁠요';

  @override
  String get sendPaymentRequestTransactionMemo => '거⁠래 메⁠모';

  @override
  String sendPaymentRequestUnavailableLabel(String label) {
    return '$label, 사⁠용⁠할 수 없⁠음';
  }

  @override
  String sendPaymentRequestUnavailableWithReason(String label, String reason) {
    return '$label, 사⁠용⁠할 수 없⁠음. $reason';
  }

  @override
  String get sendPaymentRequestUsingQrInstead =>
      '대⁠신 QR 코⁠드⁠를 사⁠용⁠해⁠요. 링⁠크⁠가 바⁠뀌⁠었⁠을 수 있⁠어⁠요.';

  @override
  String get sendPaymentRequestViewNote => '메⁠모 보⁠기';

  @override
  String get sendPaymentRequestYourAccount => '내 계⁠정';

  @override
  String get sendQrScannerOpenFailed =>
      'QR 스⁠캐⁠너⁠를 열⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendRecentsSection => '최⁠근 보⁠낸 곳';

  @override
  String get sendRecipientHint => '주⁠소 또⁠는 요⁠청 링⁠크';

  @override
  String get sendRecipientLabel => '받⁠는 사⁠람';

  @override
  String get sendRecipientUnreadableRequestLink => '이 요⁠청 링⁠크⁠를 읽⁠을 수 없⁠어⁠요';

  @override
  String get sendRecipientWrongNetwork => '이 주⁠소⁠는 다⁠른 Zcash 네⁠트⁠워⁠크⁠의 주⁠소⁠예⁠요';

  @override
  String get sendRequestScanCheckFailed =>
      '이 QR 코⁠드⁠를 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendRequestScanInvalidAddress =>
      '이 QR 코⁠드⁠는 올⁠바⁠른 Zcash 주⁠소⁠가 아⁠니⁠에⁠요.';

  @override
  String get sendRequestScanInvalidRequest =>
      '이 QR 코⁠드⁠에⁠는 올⁠바⁠른 결⁠제 요⁠청⁠이 들⁠어 있⁠지 않⁠아⁠요.';

  @override
  String get sendRequestScanNotRequest =>
      '이 QR 코⁠드⁠는 Zcash 주⁠소⁠나 결⁠제 요⁠청⁠이 아⁠니⁠에⁠요.';

  @override
  String get sendRequestScanPermission =>
      '결⁠제 요⁠청 QR 코⁠드⁠를 스⁠캔⁠하⁠려⁠면 카⁠메⁠라⁠가 필⁠요⁠해⁠요.\n카⁠메⁠라 접⁠근 권⁠한⁠은 언⁠제⁠든 설⁠정⁠에⁠서 바⁠꿀 수 있⁠어⁠요.';

  @override
  String get sendRequestScanSubtitle =>
      '요⁠청⁠한 사⁠람⁠의 원⁠래 QR 코⁠드⁠를 카⁠메⁠라⁠에 보⁠여 주⁠세⁠요';

  @override
  String get sendRequestScanTipContinuity =>
      'Mac⁠에⁠서⁠는 연⁠속⁠성 카⁠메⁠라⁠로 iPhone⁠을 대⁠신 사⁠용⁠해 스⁠캔⁠할 수 있⁠어⁠요.';

  @override
  String get sendRequestScanTipDistance =>
      '카⁠메⁠라⁠가 초⁠점⁠을 맞⁠출 수 있⁠게 QR 코⁠드⁠를 몇 센⁠티⁠미⁠터 더 멀⁠리 두⁠세⁠요.';

  @override
  String get sendRequestScanTipLight =>
      '방⁠이 밝⁠은⁠지, QR 코⁠드⁠에 빛⁠이 반⁠사⁠되⁠지 않⁠는⁠지 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendRequestScanTipOriginal =>
      '다⁠른 기⁠기⁠에⁠서 요⁠청⁠한 사⁠람⁠의 원⁠래 QR 코⁠드⁠를 전⁠체 화⁠면⁠으⁠로 여⁠세⁠요.';

  @override
  String get sendRequestScanUnavailable =>
      '카⁠메⁠라⁠를 연⁠결⁠하⁠거⁠나 뒤⁠로 가⁠서 링⁠크 상⁠세⁠를 검⁠토⁠하⁠세⁠요.';

  @override
  String get sendRequestScanWrongNetwork => '이 주⁠소⁠는 다⁠른 네⁠트⁠워⁠크⁠의 주⁠소⁠예⁠요.';

  @override
  String get sendReviewAction => '검⁠토';

  @override
  String get sendReviewCalculatingFee => '수⁠수⁠료⁠를 계⁠산⁠하⁠는 중...';

  @override
  String get sendReviewConfirmAndSend => '확⁠인⁠하⁠고 보⁠내⁠기';

  @override
  String get sendReviewConfirmAndSendMobile => '확⁠인⁠하⁠고 보⁠내⁠기';

  @override
  String get sendReviewConfirmDonation => '후⁠원 확⁠인';

  @override
  String get sendReviewConfirmWithLedger => 'Ledger⁠로 확⁠인';

  @override
  String get sendReviewFeeUnavailable => '수⁠수⁠료⁠를 확⁠인⁠할 수 없⁠어⁠요';

  @override
  String get sendReviewFinishingSyncButton => '지⁠갑 동⁠기⁠화⁠를 마⁠무⁠리⁠하⁠는 중...';

  @override
  String get sendReviewPreparing => '준⁠비⁠하⁠는 중...';

  @override
  String sendReviewRequestedAmount(String amount) {
    return '요⁠청 금⁠액 $amount';
  }

  @override
  String get sendReviewRequestedBy => '요⁠청⁠한 사⁠람';

  @override
  String get sendReviewTitle => '보⁠내⁠기 검⁠토';

  @override
  String get sendSaplingDownloadBody =>
      '이 비⁠공⁠개 거⁠래⁠를 만⁠들⁠려⁠면 지⁠갑⁠이 약 50MB⁠의 암⁠호⁠화 매⁠개⁠변⁠수⁠를 내⁠려⁠받⁠아⁠야 해⁠요.';

  @override
  String get sendSaplingDownloadNote =>
      '한 번⁠만 내⁠려⁠받⁠으⁠면 돼⁠요.\n데⁠이⁠터 요⁠금⁠이 발⁠생⁠할 수 있⁠어⁠요.';

  @override
  String get sendSaplingDownloadTitle => '다⁠운⁠로⁠드⁠가 필⁠요⁠해⁠요';

  @override
  String get sendScanDowngradePastedMalformedRequest =>
      '주⁠소⁠만 붙⁠여⁠넣⁠었⁠어⁠요. 결⁠제 요⁠청⁠을 읽⁠을 수 없⁠었⁠어⁠요';

  @override
  String get sendScanDowngradePastedMultipleRecipients =>
      '첫 번⁠째 받⁠는 사⁠람⁠만 붙⁠여⁠넣⁠었⁠어⁠요. 이 요⁠청⁠에⁠는 받⁠는 사⁠람⁠이 여⁠러 명⁠이⁠에⁠요';

  @override
  String get sendScanDowngradePastedUnsupportedMemo =>
      '주⁠소⁠만 붙⁠여⁠넣⁠었⁠어⁠요. 요⁠청⁠의 메⁠시⁠지⁠를 읽⁠을 수 없⁠었⁠어⁠요';

  @override
  String get sendScanDowngradeScannedMalformedRequest =>
      '주⁠소⁠만 스⁠캔⁠했⁠어⁠요. 결⁠제 요⁠청⁠을 읽⁠을 수 없⁠었⁠어⁠요';

  @override
  String get sendScanDowngradeScannedMultipleRecipients =>
      '첫 번⁠째 받⁠는 사⁠람⁠만 스⁠캔⁠했⁠어⁠요. 이 요⁠청⁠에⁠는 받⁠는 사⁠람⁠이 여⁠러 명⁠이⁠에⁠요';

  @override
  String get sendScanDowngradeScannedUnsupportedMemo =>
      '주⁠소⁠만 스⁠캔⁠했⁠어⁠요. 요⁠청⁠의 메⁠시⁠지⁠를 읽⁠을 수 없⁠었⁠어⁠요';

  @override
  String get sendScanNotZcashAddress => '이 QR 코⁠드⁠는 Zcash 주⁠소⁠가 아⁠니⁠에⁠요.';

  @override
  String get sendScanQrSubtitle => '주⁠소 또⁠는 결⁠제 요⁠청 스⁠캔';

  @override
  String get sendScanQrTitle => 'QR 코⁠드 스⁠캔';

  @override
  String get sendSendingToLabel => '받⁠는 사⁠람';

  @override
  String get sendSignConfirmTransaction => '거⁠래 확⁠인';

  @override
  String sendSignConfirmTransactionOfTwo(int index) {
    return '거⁠래 확⁠인 ($index/2)';
  }

  @override
  String get sendSpendableInfoLabel => '사⁠용 가⁠능⁠한 잔⁠액 정⁠보';

  @override
  String get sendSpendableTooltipBody =>
      '자⁠금⁠은 사⁠용⁠하⁠기 전⁠에 확⁠인⁠이 필⁠요⁠해⁠요. 내 지⁠갑⁠에⁠서 돌⁠아⁠온 잔⁠돈⁠은 3⁠번, 다⁠른 사⁠람⁠에⁠게 받⁠은 자⁠금⁠은 6⁠번⁠이⁠에⁠요. 차⁠폐⁠된 노⁠트⁠도 모⁠두 스⁠캔⁠되⁠어⁠야 해⁠요. 곧 사⁠용⁠할 수 있⁠게 돼⁠요.';

  @override
  String get sendSpendableTooltipTitle =>
      '사⁠용 가⁠능⁠한 잔⁠액⁠이 전⁠체 잔⁠액⁠보⁠다 적⁠을 수 있⁠어⁠요.';

  @override
  String get sendStatusDonationFailed => '후⁠원⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get sendStatusDonationInProgress => '후⁠원⁠하⁠는 중...';

  @override
  String sendStatusFailureSummary(String amount, String recipient) {
    return '$recipient⁠에⁠게 $amount';
  }

  @override
  String get sendStatusMobileConfirmSoon =>
      '곧 블⁠록⁠체⁠인⁠에⁠서 확⁠인⁠돼⁠요. 활⁠동⁠에⁠서 진⁠행 상⁠황⁠을 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendStatusMobileDonationQueued => '후⁠원⁠이 대⁠기 중⁠이⁠에⁠요';

  @override
  String get sendStatusMobileDonationSupport =>
      '보⁠내 주⁠신 후⁠원⁠이 Vizor⁠를 계⁠속 움⁠직⁠이⁠게 해⁠요.';

  @override
  String get sendStatusMobileDonationThanks => 'Vizor⁠를\n후⁠원⁠해 주⁠셔⁠서 감⁠사⁠해⁠요';

  @override
  String get sendStatusMobileNothingSent =>
      '아⁠무⁠것⁠도 보⁠내⁠지 않⁠았⁠고 자⁠금⁠은 그⁠대⁠로⁠예⁠요. 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendStatusMobilePendingDefault =>
      '거⁠래⁠가 만⁠들⁠어⁠졌⁠고 자⁠동⁠으⁠로 제⁠출⁠돼⁠요. 다⁠시 보⁠내⁠기 전⁠에 활⁠동 페⁠이⁠지⁠를 확⁠인⁠하⁠세⁠요.';

  @override
  String get sendStatusMobileQueued => '보⁠내⁠기 대⁠기 중';

  @override
  String get sendStatusMobileReturnToSettings => '설⁠정⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get sendStatusMobileSendingDonation => '후⁠원⁠을 보⁠내⁠는 중...';

  @override
  String get sendStatusMobileSent => '보⁠냈⁠어⁠요!';

  @override
  String get sendStatusMobileSubmitting => '거⁠래⁠를 네⁠트⁠워⁠크⁠에 제⁠출⁠하⁠는 중...';

  @override
  String get sendStatusRetryAfterSync =>
      '지⁠갑 동⁠기⁠화⁠가 끝⁠날 때⁠까⁠지 기⁠다⁠린 다⁠음 서⁠명⁠된 이 거⁠래⁠를 다⁠시 시⁠도⁠하⁠세⁠요.';

  @override
  String get sendStatusRowStatus => '상⁠태';

  @override
  String get sendStatusScanKeystoneTitle => 'Keystone QR 코⁠드⁠를 스⁠캔⁠하⁠세⁠요';

  @override
  String get sendStatusTitleInProgress => '보⁠내⁠는 중...';

  @override
  String get sendStepEnterAmount => '금⁠액 입⁠력';

  @override
  String get sendStepReviewDonation => '후⁠원 검⁠토';

  @override
  String get sendStepReviewSend => '보⁠내⁠기 검⁠토';

  @override
  String sendTitle(String currency) {
    return '$currency 보⁠내⁠기';
  }

  @override
  String get sendUseMax => '최⁠대 사⁠용';

  @override
  String sendUseMaxSemantics(String spendable) {
    return '사⁠용 가⁠능⁠한 최⁠대 잔⁠액 사⁠용, $spendable 사⁠용 가⁠능';
  }

  @override
  String get sendUseMaxSemanticsShort => '사⁠용 가⁠능⁠한 최⁠대 잔⁠액 사⁠용';

  @override
  String sendVerifyAddressPreviousTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이⁠전 거⁠래 $count⁠건',
    );
    return '$_temp0';
  }

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
  String get settingsUpdateCurrentLabel => '현⁠재';

  @override
  String get settingsUpdateDownloadButton => '업⁠데⁠이⁠트 다⁠운⁠로⁠드';

  @override
  String get settingsUpdateDownloadingButton => '다⁠운⁠로⁠드 중…';

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
  String get swapActionAddRecipientAddress => '받⁠는 주⁠소 추⁠가';

  @override
  String get swapActionAddRefundAddress => '환⁠불 주⁠소 추⁠가';

  @override
  String get swapActionContinueToReview => '검⁠토⁠로 이⁠동';

  @override
  String get swapActionGettingQuote => '견⁠적 가⁠져⁠오⁠는 중';

  @override
  String swapActivityAddressBookRefund(String symbol) {
    return '$symbol 환⁠불';
  }

  @override
  String swapActivityDeadlineHours(int hours) {
    return '$hours⁠시⁠간';
  }

  @override
  String swapActivityDeadlineMinutes(int minutes) {
    return '$minutes⁠분';
  }

  @override
  String get swapActivityDepositAmount => '입⁠금 금⁠액';

  @override
  String get swapActivityDepositAssetFallback => '입⁠금 자⁠산';

  @override
  String swapActivityDepositInstructionDepositLabel(String symbol) {
    return '$symbol 입⁠금';
  }

  @override
  String get swapActivityDepositInstructionReuseWarning =>
      '이 주⁠소⁠를 다⁠시 사⁠용⁠하⁠지 마⁠세⁠요';

  @override
  String swapActivityDepositInstructionSendFromSource(String symbol) {
    return '출⁠발 체⁠인⁠에⁠서 $symbol 보⁠내⁠기';
  }

  @override
  String swapActivityDepositInstructionSourceDepositLabel(String symbol) {
    return '$symbol 출⁠발 체⁠인 입⁠금';
  }

  @override
  String swapActivityDepositInstructionSubmit(String symbol) {
    return '$symbol 입⁠금 제⁠출';
  }

  @override
  String swapActivityDepositInstructionTxHashHint(String symbol) {
    return '$symbol 출⁠발 체⁠인 거⁠래 해⁠시';
  }

  @override
  String swapActivityDepositInstructionTxHashLabel(String symbol) {
    return '$symbol 입⁠금 거⁠래 해⁠시';
  }

  @override
  String get swapActivityDetailConfiguredQuote => '견⁠적 설⁠정⁠값';

  @override
  String swapActivityDetailDeliveryTx(String symbol) {
    return '$symbol 전⁠달 거⁠래';
  }

  @override
  String get swapActivityDetailDepositDeadline => '입⁠금 기⁠한';

  @override
  String swapActivityDetailDepositTo(String symbol) {
    return '$symbol 입⁠금 주⁠소';
  }

  @override
  String swapActivityDetailDepositTx(String symbol) {
    return '$symbol 입⁠금 거⁠래';
  }

  @override
  String get swapActivityDetailDetectedDeposit => '확⁠인⁠된 입⁠금⁠액';

  @override
  String get swapActivityDetailFees => '수⁠수⁠료';

  @override
  String get swapActivityDetailIncluded => '포⁠함⁠됨';

  @override
  String get swapActivityDetailIncludedInRate => '표⁠시⁠된 환⁠율⁠에 포⁠함⁠됨';

  @override
  String get swapActivityDetailMissingDeposit => '부⁠족⁠한 입⁠금⁠액';

  @override
  String get swapActivityDetailRealizedSlippage => '실⁠제 슬⁠리⁠피⁠지';

  @override
  String get swapActivityDetailRequiredDeposit => '필⁠요⁠한 입⁠금⁠액';

  @override
  String swapActivityDetailSourceTxShielded(String symbol) {
    return '$symbol 거⁠래(차⁠폐)';
  }

  @override
  String get swapActivityDetailTotalFees => '총 수⁠수⁠료';

  @override
  String get swapActivityExpectedToReceive => '예⁠상 수⁠령 금⁠액';

  @override
  String get swapActivityIncompleteDeposit => '입⁠금⁠이 완⁠료⁠되⁠지 않⁠았⁠어⁠요';

  @override
  String get swapActivityIncompletePayment => '결⁠제⁠가 완⁠료⁠되⁠지 않⁠았⁠어⁠요';

  @override
  String get swapActivityLastCheckJustNow => '마⁠지⁠막 확⁠인: 방⁠금 전';

  @override
  String swapActivityLastCheckMinutesAgo(int minutes) {
    return '마⁠지⁠막 확⁠인: $minutes⁠분 전';
  }

  @override
  String get swapActivityNotReported => '보⁠고⁠되⁠지 않⁠음';

  @override
  String get swapActivityPaidSuccessfullyTitle => '결⁠제⁠를 완⁠료⁠했⁠어⁠요';

  @override
  String get swapActivityPayInProgressTitle => '결⁠제 진⁠행 중...';

  @override
  String get swapActivityPaymentComplete => '결⁠제 완⁠료';

  @override
  String swapActivityPickerNoRecipients(String symbol) {
    return '저⁠장⁠된 $symbol 수⁠신⁠자⁠가 없⁠어⁠요';
  }

  @override
  String swapActivityPickerNoRefunds(String symbol) {
    return '저⁠장⁠된 $symbol 환⁠불 주⁠소⁠가 없⁠어⁠요';
  }

  @override
  String swapActivityPickerRecipientsTitle(String symbol) {
    return '$symbol 수⁠신⁠자';
  }

  @override
  String swapActivityPickerRefundsTitle(String symbol) {
    return '$symbol 환⁠불';
  }

  @override
  String get swapActivityReceiveAssetFallback => '수⁠령 자⁠산';

  @override
  String get swapActivityRecipientReceived => '수⁠신⁠자⁠가 받⁠은 금⁠액';

  @override
  String swapActivityStateAddressOrAccountHint(String chain) {
    return '$chain 주⁠소 또⁠는 계⁠정';
  }

  @override
  String swapActivityStateAssetUnsupported(String symbol, String chain) {
    return '$chain⁠의 $symbol⁠은(는) 현⁠재 지⁠원⁠되⁠지 않⁠아⁠요.';
  }

  @override
  String swapActivityStateDecimalPlaces(String symbol, int decimals) {
    return '$symbol⁠은(는) 소⁠수⁠점 $decimals⁠자⁠리⁠까⁠지 지⁠원⁠해⁠요.';
  }

  @override
  String get swapActivityStateDestination => '받⁠는 주⁠소';

  @override
  String swapActivityStateQuoteHigher(String percent) {
    return '실⁠시⁠간 견⁠적⁠이 이⁠전 예⁠상⁠보⁠다 $percent% 높⁠아⁠요. 계⁠속⁠하⁠기 전⁠에 최⁠소 보⁠장 수⁠량⁠을 확⁠인⁠하⁠세⁠요.';
  }

  @override
  String swapActivityStateQuoteLower(String percent) {
    return '실⁠시⁠간 견⁠적⁠이 이⁠전 예⁠상⁠보⁠다 $percent% 낮⁠아⁠요. 계⁠속⁠하⁠기 전⁠에 최⁠소 보⁠장 수⁠량⁠을 확⁠인⁠하⁠세⁠요.';
  }

  @override
  String swapActivityStateQuoteUsesDifferentSell(
    String liveAmount,
    String estimateAmount,
    String symbol,
  ) {
    return '실⁠시⁠간 견⁠적⁠은 $estimateAmount $symbol 대⁠신 $liveAmount $symbol⁠을(를) 사⁠용⁠해⁠요. 계⁠속⁠하⁠기 전⁠에 최⁠소 보⁠장 수⁠량⁠을 확⁠인⁠하⁠세⁠요.';
  }

  @override
  String get swapActivityStatusAwaitingDeposit => '입⁠금 대⁠기 중';

  @override
  String get swapActivityStatusAwaitingExternalDeposit => '외⁠부 입⁠금 대⁠기 중';

  @override
  String get swapActivityStatusComplete => '완⁠료';

  @override
  String get swapActivityStatusDepositObserved => '입⁠금 확⁠인⁠됨';

  @override
  String get swapActivityStatusExpired => '만⁠료⁠됨';

  @override
  String get swapActivityStatusProcessing => '처⁠리 중';

  @override
  String get swapActivityStepConvert => '변⁠환';

  @override
  String get swapActivityStepConvertDescription =>
      '차⁠폐⁠된 지⁠출⁠을 결⁠제 자⁠산⁠으⁠로 변⁠환⁠하⁠고 있⁠어⁠요.';

  @override
  String get swapActivityStepConverting => '변⁠환 중...';

  @override
  String swapActivityStepDeliver(String symbol) {
    return '$symbol 전⁠달';
  }

  @override
  String swapActivityStepDeliverActive(String symbol) {
    return '$symbol 전⁠달...';
  }

  @override
  String get swapActivityStepDeliverPayDescription =>
      '결⁠제 금⁠액⁠을 받⁠는 주⁠소⁠로 전⁠달⁠하⁠고 있⁠어⁠요.';

  @override
  String get swapActivityStepDeliverSwapDescription =>
      '받⁠을 자⁠산⁠을 받⁠는 주⁠소⁠로 전⁠달⁠하⁠고 있⁠어⁠요.';

  @override
  String swapActivityStepDelivering(String symbol) {
    return '$symbol 전⁠달 중...';
  }

  @override
  String swapActivityStepDeposit(String symbol) {
    return '$symbol 입⁠금';
  }

  @override
  String get swapActivityStepDepositConfirmation => '입⁠금 확⁠인';

  @override
  String get swapActivityStepDepositConfirmationActive => '입⁠금 확⁠인 중...';

  @override
  String get swapActivityStepDepositConfirmationDescription =>
      '스⁠왑 경⁠로⁠를 시⁠작⁠하⁠기 전⁠에 입⁠금⁠을 확⁠인⁠하⁠고 있⁠어⁠요.';

  @override
  String swapActivityStepDeposited(String symbol) {
    return '$symbol 입⁠금 완⁠료';
  }

  @override
  String swapActivityStepDepositing(String symbol) {
    return '$symbol 입⁠금 중...';
  }

  @override
  String get swapActivityStepRecipientReceives => '수⁠신⁠자 수⁠령';

  @override
  String swapActivityStepRecipientReceivesAsset(String symbol) {
    return '수⁠신⁠자⁠가 $symbol 수⁠령 중...';
  }

  @override
  String get swapActivityStepRecipientReceivesDescription =>
      '수⁠신⁠자 쪽 결⁠제⁠를 확⁠인⁠하⁠고 있⁠어⁠요.';

  @override
  String swapActivityStepSend(String symbol) {
    return '$symbol 보⁠내⁠기';
  }

  @override
  String swapActivityStepSendActive(String symbol) {
    return '$symbol 보⁠내⁠는 중...';
  }

  @override
  String swapActivityStepSending(String symbol) {
    return '$symbol 보⁠내⁠는 중...';
  }

  @override
  String swapActivityStepSent(String symbol) {
    return '$symbol 전⁠송 완⁠료';
  }

  @override
  String get swapActivityStepSourceDescription =>
      '출⁠발 체⁠인⁠과 제⁠공⁠자⁠가 입⁠금⁠을 인⁠식⁠할 때⁠까⁠지 기⁠다⁠리⁠고 있⁠어⁠요';

  @override
  String swapActivityStepSpend(String symbol) {
    return '$symbol 사⁠용';
  }

  @override
  String get swapActivityStepSpendDescription => '차⁠폐⁠된 잔⁠액⁠에⁠서 사⁠용⁠하⁠고 있⁠어⁠요.';

  @override
  String swapActivityStepSpending(String symbol) {
    return '$symbol 사⁠용 중...';
  }

  @override
  String swapActivityStepSpent(String symbol) {
    return '$symbol 사⁠용 완⁠료';
  }

  @override
  String get swapActivityStepSwap => '스⁠왑';

  @override
  String get swapActivityStepSwapActive => '스⁠왑 중...';

  @override
  String get swapActivityStepSwapDescription =>
      '제⁠공⁠자⁠가 스⁠왑 경⁠로⁠를 실⁠행⁠하⁠고 있⁠어⁠요.';

  @override
  String get swapActivitySwapCompleted => '스⁠왑 완⁠료';

  @override
  String get swapActivitySwapInProgress => '스⁠왑 진⁠행 중...';

  @override
  String get swapActivityTooltipFees =>
      '당⁠사 수⁠수⁠료⁠와 경⁠로 제⁠공⁠자⁠가 이 스⁠왑⁠을 처⁠리⁠하⁠는 데 드⁠는 비⁠용⁠이 포⁠함⁠돼⁠요. 위 환⁠율⁠에 이⁠미 반⁠영⁠되⁠어 있⁠어⁠요.';

  @override
  String swapActivityTooltipMinimumReceive(String symbol) {
    return '슬⁠리⁠피⁠지⁠가 반⁠영⁠된 $symbol 최⁠소 수⁠령 금⁠액⁠이⁠에⁠요. 더 받⁠을 수⁠는 있⁠지⁠만 이⁠보⁠다 적⁠게 받⁠지⁠는 않⁠아⁠요.';
  }

  @override
  String get swapActivityTooltipMinimumReceiveGeneric =>
      '슬⁠리⁠피⁠지⁠가 반⁠영⁠된 최⁠소 수⁠령 금⁠액⁠이⁠에⁠요. 더 받⁠을 수⁠는 있⁠지⁠만 이⁠보⁠다 적⁠게 받⁠지⁠는 않⁠아⁠요.';

  @override
  String get swapActivityTooltipPriceProtection =>
      '슬⁠리⁠피⁠지 허⁠용⁠치⁠가 보⁠호⁠하⁠는 수⁠령 금⁠액⁠의 범⁠위⁠예⁠요. 환⁠율⁠이 이 범⁠위⁠를 넘⁠어 변⁠하⁠면 스⁠왑⁠이 환⁠불⁠돼⁠요.';

  @override
  String get swapActivityTooltipStatusDetail =>
      '최⁠신 스⁠왑 기⁠록⁠과 제⁠공⁠자 상⁠태⁠를 바⁠탕⁠으⁠로 한 정⁠보⁠예⁠요.';

  @override
  String get swapActivityYouPaid => '지⁠불⁠한 금⁠액';

  @override
  String get swapActivityYouReceived => '받⁠은 금⁠액';

  @override
  String swapAddressRecipientDescription(String symbol) {
    return '$symbol⁠이(가) 이 주⁠소⁠로 전⁠송⁠돼⁠요.';
  }

  @override
  String get swapAddressRecipientFieldLabel => '받⁠는 주⁠소';

  @override
  String swapAddressRecipientTitle(String symbol) {
    return '$symbol 받⁠는 주⁠소';
  }

  @override
  String swapAddressRefundDescription(String symbol, String chain) {
    return '스⁠왑⁠이 실⁠패⁠하⁠거⁠나 환⁠율⁠이 변⁠동⁠되⁠면 수⁠수⁠료⁠를 제⁠외⁠한 금⁠액⁠을 $chain⁠의 $symbol(으)로 환⁠불⁠해 드⁠려⁠요.';
  }

  @override
  String get swapAddressRememberRecipient => '받⁠는 주⁠소⁠로 이 주⁠소 기⁠억⁠하⁠기';

  @override
  String get swapAddressRememberRefund => '환⁠불 주⁠소⁠로 이 주⁠소 기⁠억⁠하⁠기';

  @override
  String get swapAssetSelectorEmpty => '토⁠큰⁠이⁠나 체⁠인⁠을 찾⁠을 수 없⁠어⁠요';

  @override
  String get swapAssetSelectorSearchHint => '토⁠큰 또⁠는 체⁠인 검⁠색';

  @override
  String get swapAssetSelectorTitle => '자⁠산 선⁠택';

  @override
  String get swapComposerAddRecipientAddressEllipsis => '받⁠는 주⁠소 추⁠가...';

  @override
  String get swapComposerAddRefundAddressEllipsis => '환⁠불 주⁠소 추⁠가...';

  @override
  String swapComposerMaxAmount(String amount) {
    return '최⁠대: $amount';
  }

  @override
  String get swapComposerYouReceive => '내⁠가 받⁠는 금⁠액';

  @override
  String get swapContactAlreadyInAddressBook => '이⁠미 주⁠소⁠록⁠에 있⁠어⁠요';

  @override
  String get swapContactAlreadySaved => '이⁠미 연⁠락⁠처⁠에 있⁠어⁠요';

  @override
  String get swapDepositAmountCopiedDesktop => '금⁠액⁠을 복⁠사⁠했⁠어⁠요';

  @override
  String get swapDepositAmountCopiedMobile => '금⁠액⁠을 복⁠사⁠했⁠어⁠요';

  @override
  String get swapDepositAmountToDeposit => '입⁠금⁠할 금⁠액';

  @override
  String get swapDepositChecking => '확⁠인 중';

  @override
  String get swapDepositDoneDesktop => '입⁠금⁠했⁠어⁠요';

  @override
  String get swapDepositDoneMobile => '토⁠큰⁠을 입⁠금⁠했⁠어⁠요';

  @override
  String swapDepositHoursMany(int count) {
    return '$count⁠시⁠간';
  }

  @override
  String get swapDepositMemoCopied => '메⁠모⁠를 복⁠사⁠했⁠어⁠요';

  @override
  String swapDepositMinutesMany(int count) {
    return '$count⁠분';
  }

  @override
  String get swapDepositOneTimeAddress => '일⁠회⁠용 주⁠소';

  @override
  String swapDepositSendOnly(String symbol, String chain) {
    return '$chain⁠의 $symbol⁠만 보⁠내⁠세⁠요';
  }

  @override
  String get swapDepositTimeoutBody =>
      '이 입⁠금 주⁠소⁠는 더 이⁠상 유⁠효⁠하⁠지 않⁠아⁠요.\n새 스⁠왑⁠을 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get swapDepositTitle => '토⁠큰 입⁠금';

  @override
  String get swapDepositWithin => '입⁠금 기⁠한';

  @override
  String get swapDepositZecButton => 'ZEC 입⁠금';

  @override
  String get swapDismissBarrierLabel => '닫⁠기';

  @override
  String get swapKeystoneBroadcastFailed => '거⁠래⁠를 전⁠송⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get swapKeystoneBroadcastingTitle => 'ZEC 입⁠금 전⁠송 중';

  @override
  String get swapKeystoneFailedTitle => 'Keystone 서⁠명⁠에 실⁠패⁠했⁠어⁠요';

  @override
  String get swapKeystoneFinalizing => 'ZEC 입⁠금 전⁠송 중...';

  @override
  String get swapKeystoneIncomplete => 'ZEC 입⁠금 서⁠명⁠을 완⁠료⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get swapKeystoneNoTex => 'Keystone⁠은 아⁠직 TEX 전⁠송⁠을 지⁠원⁠하⁠지 않⁠아⁠요.';

  @override
  String get swapKeystoneQrMismatch =>
      '이 QR 코⁠드⁠는 현⁠재 Keystone 요⁠청⁠과 일⁠치⁠하⁠지 않⁠아⁠요.';

  @override
  String get swapKeystoneScanCaption =>
      'Keystone⁠의 QR 코⁠드⁠를 스⁠캔⁠해 ZEC 입⁠금⁠을 마⁠무⁠리⁠하⁠세⁠요';

  @override
  String get swapKeystoneScanToSign => '스⁠캔⁠하⁠여 서⁠명';

  @override
  String get swapKeystoneSignTitle => 'Keystone⁠에⁠서 ZEC 입⁠금 서⁠명';

  @override
  String get swapKeystoneStatusUncertain =>
      '거⁠래 상⁠태⁠가 확⁠실⁠하⁠지 않⁠아⁠요. 다⁠시 시⁠도⁠하⁠기 전⁠에 활⁠동⁠을 새⁠로⁠고⁠침⁠해 주⁠세⁠요.';

  @override
  String get swapLedgerBackToActivity => '활⁠동⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get swapLedgerBroadcastFailed => 'ZEC 입⁠금⁠을 전⁠송⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get swapLedgerDeclined => 'Ledger⁠에⁠서 ZEC 입⁠금⁠이 거⁠부⁠됐⁠어⁠요.';

  @override
  String get swapLedgerMessageBackground =>
      'Vizor⁠가 이⁠미 백⁠그⁠라⁠운⁠드⁠에⁠서 이 거⁠래⁠를 마⁠무⁠리⁠하⁠고 있⁠어⁠요.';

  @override
  String get swapLedgerMessageExpired =>
      '거⁠래⁠가 전⁠송⁠되⁠기 전⁠에 만⁠료⁠됐⁠어⁠요. Vizor⁠가 예⁠약⁠된 자⁠금⁠을 아⁠직 해⁠제⁠해⁠야 해⁠요.';

  @override
  String get swapLedgerMessageSentNotSaved =>
      '거⁠래⁠는 전⁠송⁠됐⁠지⁠만 Vizor⁠가 저⁠장⁠을 마⁠치⁠지 못⁠했⁠어⁠요.';

  @override
  String get swapLedgerMessageUncertain =>
      '거⁠래⁠가 전⁠송⁠됐⁠는⁠지 Vizor⁠가 확⁠인⁠하⁠지 못⁠했⁠어⁠요. 상⁠태⁠를 아⁠직 저⁠장⁠해⁠야 해⁠요.';

  @override
  String get swapLedgerRetryCleanup => '정⁠리 다⁠시 시⁠도';

  @override
  String get swapLedgerSigningIncomplete => 'Ledger 서⁠명⁠을 완⁠료⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get swapLedgerStatusCleanup => '정⁠리 필⁠요';

  @override
  String get swapLedgerStatusSaving => '거⁠래 저⁠장 중';

  @override
  String get swapLedgerStatusWait => '잠⁠시⁠만 기⁠다⁠려 주⁠세⁠요';

  @override
  String get swapLedgerTitlePending => '거⁠래 상⁠태 확⁠인 중';

  @override
  String get swapLedgerTitleRecovery => '거⁠래 복⁠구 진⁠행 중';

  @override
  String get swapLedgerTitleSent => '거⁠래⁠를 보⁠냈⁠어⁠요';

  @override
  String get swapNoticeAffectedNetworks => '영⁠향⁠받⁠는 네⁠트⁠워⁠크';

  @override
  String get swapNoticeAllChains => '모⁠든 체⁠인';

  @override
  String get swapNoticeCloseLabel => '서⁠비⁠스 안⁠내 닫⁠기';

  @override
  String swapNoticeExpectedEnd(String time) {
    return '종⁠료 예⁠정: $time';
  }

  @override
  String get swapNoticeListOfMaintenance => '점⁠검 목⁠록';

  @override
  String get swapNoticeMaintenanceIntro => 'NEAR Intents⁠가 점⁠검 중⁠이⁠에⁠요.';

  @override
  String get swapNoticeMaintenanceTitle => '점⁠검 안⁠내';

  @override
  String swapNoticeMaintenanceWindow(String networks) {
    return '점⁠검 대⁠상: $networks';
  }

  @override
  String get swapNoticeOk => '확⁠인';

  @override
  String get swapNoticePaymentsMayFail => '지⁠금⁠은 결⁠제⁠가 되⁠지 않⁠을 수 있⁠어⁠요.';

  @override
  String get swapNoticeServiceTitle => '서⁠비⁠스 안⁠내';

  @override
  String swapNoticeStart(String time) {
    return '시⁠작: $time';
  }

  @override
  String get swapNoticeStatusPage => 'NEAR Intents 상⁠태 페⁠이⁠지';

  @override
  String get swapNoticeSwapsMayFail => '지⁠금⁠은 스⁠왑⁠이 되⁠지 않⁠을 수 있⁠어⁠요.';

  @override
  String get swapPageTitle => '스⁠왑';

  @override
  String get swapPanelDepositChecking => 'ZEC 입⁠금⁠을 확⁠인⁠하⁠는 중';

  @override
  String get swapPanelDepositSent => 'ZEC 입⁠금⁠을 보⁠냈⁠어⁠요';

  @override
  String get swapPanelLoadFailedBody =>
      '활⁠동⁠으⁠로 돌⁠아⁠가 저⁠장⁠된 스⁠왑⁠을 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get swapPanelLoadFailedTitle =>
      '이 스⁠왑⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나 아⁠래⁠로 당⁠겨 새⁠로⁠고⁠침⁠해 주⁠세⁠요.';

  @override
  String swapPanelRecipientTo(String recipient) {
    return '받⁠는 사⁠람: $recipient';
  }

  @override
  String get swapPayStatusConvertedFrom => '변⁠환 전 금⁠액';

  @override
  String get swapPayStatusNewAddress => '새 주⁠소';

  @override
  String get swapPayStatusSourceAmount => '원⁠래 금⁠액';

  @override
  String get swapPoweredByLabel => '제⁠공:';

  @override
  String get swapReviewBackPay => '결⁠제';

  @override
  String get swapReviewConfirmAndSwap => '확⁠인 후 스⁠왑';

  @override
  String get swapReviewConfirmPaymentTitle => '결⁠제 확⁠인';

  @override
  String get swapReviewConfirmSwap => '스⁠왑 확⁠인';

  @override
  String swapReviewFromAddress(String address) {
    return '보⁠내⁠는 주⁠소: $address';
  }

  @override
  String get swapReviewInsufficientZecSwap =>
      '이 스⁠왑⁠에 필⁠요⁠한 ZEC⁠가 부⁠족⁠해⁠요. 더 적⁠은 금⁠액⁠으⁠로 시⁠도⁠해 주⁠세⁠요.';

  @override
  String swapReviewPayAmount(String amount) {
    return '$amount 결⁠제';
  }

  @override
  String get swapReviewQuoteExpired =>
      '견⁠적⁠이 만⁠료⁠됐⁠어⁠요. 최⁠신 환⁠율⁠로 다⁠시 검⁠토⁠해 주⁠세⁠요.';

  @override
  String get swapReviewQuoteHolds => '견⁠적 유⁠지 시⁠간';

  @override
  String get swapReviewQuoteInactive => '이 견⁠적⁠은 더 이⁠상 유⁠효⁠하⁠지 않⁠아⁠요.';

  @override
  String get swapReviewReturnToSwap => '스⁠왑⁠으⁠로 돌⁠아⁠가⁠기';

  @override
  String get swapReviewReviewAgain => '다⁠시 검⁠토';

  @override
  String get swapReviewStartingLockingQuote => '견⁠적 고⁠정 중';

  @override
  String get swapReviewStartingPaying => '결⁠제 중';

  @override
  String get swapReviewStartingSending => '보⁠내⁠는 중';

  @override
  String swapReviewToAddress(String address) {
    return '받⁠는 주⁠소: $address';
  }

  @override
  String get swapSignPayment => '결⁠제 서⁠명';

  @override
  String get swapSignZecDeposit => 'ZEC 입⁠금 서⁠명';

  @override
  String get swapSlippageCustom => '직⁠접 입⁠력';

  @override
  String get swapSlippageDescriptionPay =>
      '견⁠적⁠이 변⁠동⁠될 때 실⁠행⁠이 실⁠패⁠하⁠기 전⁠까⁠지 이⁠만⁠큼⁠의 추⁠가 ZEC⁠를 허⁠용⁠해⁠요. 네⁠트⁠워⁠크 수⁠수⁠료⁠는 별⁠도⁠예⁠요.';

  @override
  String get swapSlippageDescriptionSwap =>
      '허⁠용⁠할 최⁠대 환⁠율 변⁠동⁠폭⁠을 설⁠정⁠해⁠요. 네⁠트⁠워⁠크 수⁠수⁠료⁠는 별⁠도⁠예⁠요.';

  @override
  String get swapSlippageRangeError => '슬⁠리⁠피⁠지⁠는 0.1 - 5%여⁠야 해⁠요';

  @override
  String get swapSlippageTitle => '슬⁠리⁠피⁠지';

  @override
  String get swapStatusBadgeNeedsAttention => '확⁠인 필⁠요';

  @override
  String get swapStatusDetailsTab => '거⁠래 상⁠세';

  @override
  String get swapStatusRowLabel => '상⁠태';

  @override
  String get swapTimeoutBody => '새 스⁠왑⁠을 시⁠작⁠해 주⁠세⁠요.';

  @override
  String get swapTimeoutHeadline => '이 입⁠금 주⁠소⁠는 더 이⁠상 유⁠효⁠하⁠지 않⁠아⁠요';

  @override
  String get swapTimeoutRestart => '스⁠왑 다⁠시 시⁠작';

  @override
  String get swapTimeoutTitle => '시⁠간⁠이 지⁠났⁠어⁠요';

  @override
  String get swapViewOnNearIntents => 'NEAR Intents⁠에⁠서 보⁠기';

  @override
  String syncCheckingPercentSemantics(String percent) {
    return '$percent⁠퍼⁠센⁠트 확⁠인 중';
  }

  @override
  String syncCheckingProgress(String percent) {
    return '$percent% 확⁠인 중';
  }

  @override
  String get syncConnectingToTor => 'Tor⁠에 연⁠결⁠하⁠는 중…';

  @override
  String get syncConnectingToTorSemantics => 'Tor⁠에 연⁠결⁠하⁠는 중';

  @override
  String get syncErrorChainRecovery => '체⁠인 복⁠구';

  @override
  String get syncErrorData => '데⁠이⁠터 오⁠류';

  @override
  String get syncErrorEndpoint => '엔⁠드⁠포⁠인⁠트 오⁠류';

  @override
  String get syncErrorNetwork => '네⁠트⁠워⁠크 오⁠류';

  @override
  String get syncErrorPrivateLookup => '비⁠공⁠개 조⁠회';

  @override
  String get syncErrorUnknown => '알 수 없⁠는 오⁠류';

  @override
  String get syncErrorWalletData => '지⁠갑 데⁠이⁠터 오⁠류';

  @override
  String get syncErrorWalletDataBusy => '지⁠갑 데⁠이⁠터 사⁠용 중';

  @override
  String syncFailed(String reason) {
    return '동⁠기⁠화 실⁠패. $reason...';
  }

  @override
  String syncFailedSemantics(String reason) {
    return '동⁠기⁠화 실⁠패. $reason';
  }

  @override
  String get syncSynced => '동⁠기⁠화 완⁠료';

  @override
  String syncSyncedAtBlock(String height) {
    return '$height 블⁠록⁠까⁠지 동⁠기⁠화 완⁠료';
  }

  @override
  String syncSyncingPercentSemantics(String percent) {
    return '$percent⁠퍼⁠센⁠트 동⁠기⁠화 중';
  }

  @override
  String syncSyncingProgress(String percent) {
    return '$percent% 동⁠기⁠화 중...';
  }

  @override
  String get syncTorFailed => 'Tor⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요...';

  @override
  String get syncTorFailedSemantics => 'Tor⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요';

  @override
  String get syncVizorSynced => 'Vizor 동⁠기⁠화⁠됨';

  @override
  String get txFeeHelpTooltip =>
      '이 거⁠래⁠를 처⁠리⁠하⁠도⁠록 Zcash 네⁠트⁠워⁠크⁠에 내⁠는 수⁠수⁠료⁠예⁠요.';

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
  String get votingActionResume => '이⁠어⁠하⁠기';

  @override
  String get votingActionRetryEligibility => '자⁠격 다⁠시 확⁠인';

  @override
  String get votingActionReview => '확⁠인';

  @override
  String get votingActionReviewAnswers => '답⁠변 확⁠인';

  @override
  String get votingActionUnavailable => '사⁠용⁠할 수 없⁠음';

  @override
  String get votingActionView => '보⁠기';

  @override
  String get votingActionViewResults => '결⁠과 보⁠기';

  @override
  String get votingActive => '투⁠표 진⁠행 중';

  @override
  String get votingAlreadyUsedNotice =>
      '이 자⁠금⁠은 이⁠미 이⁠번 라⁠운⁠드⁠에⁠서 사⁠용⁠됐⁠어⁠요. 이 기⁠기⁠에⁠서⁠는 투⁠표⁠를 다⁠시 시⁠작⁠할 수 없⁠어⁠요.';

  @override
  String get votingAutoAdvanceSemantics => '다⁠음 미⁠응⁠답 질⁠문⁠으⁠로 이⁠동⁠하⁠는 중';

  @override
  String get votingBallotCasting => '투⁠표⁠하⁠는 중';

  @override
  String get votingBallotDelivering => '응⁠답⁠을 전⁠달⁠하⁠는 중';

  @override
  String get votingBallotPreparing => '투⁠표⁠용⁠지⁠를 준⁠비⁠하⁠는 중';

  @override
  String get votingBallotWaitingChain => '체⁠인 확⁠인 대⁠기 중';

  @override
  String get votingBetaSemantics => '베⁠타';

  @override
  String votingBundleCount(int count) {
    return '투⁠표 묶⁠음 $count⁠개';
  }

  @override
  String votingBundleOf(int number, int total) {
    return '$total⁠개 중 $number⁠번⁠째 묶⁠음';
  }

  @override
  String get votingCheckAgain => '다⁠시 확⁠인';

  @override
  String votingChoiceFallback(int number) {
    return '선⁠택 $number';
  }

  @override
  String get votingConfigAddCustomSource => '사⁠용⁠자 지⁠정 소⁠스 추⁠가';

  @override
  String get votingConfigBadgeDefault => '기⁠본';

  @override
  String get votingConfigCloseSettings => '투⁠표 설⁠정 닫⁠기';

  @override
  String get votingConfigCopyUrl => '소⁠스 URL 복⁠사';

  @override
  String get votingConfigCustomSource => '사⁠용⁠자 지⁠정 소⁠스';

  @override
  String votingConfigDeleteNamed(String name) {
    return '$name 삭⁠제';
  }

  @override
  String get votingConfigDeleteSaved => '저⁠장⁠된 소⁠스 삭⁠제';

  @override
  String get votingConfigDuplicate => '이⁠미 추⁠가⁠된 소⁠스 URL⁠이⁠에⁠요.';

  @override
  String get votingConfigEditCustomSource => '사⁠용⁠자 지⁠정 소⁠스 편⁠집';

  @override
  String votingConfigEditNamed(String name) {
    return '$name 편⁠집';
  }

  @override
  String get votingConfigEditSaved => '저⁠장⁠된 소⁠스 편⁠집';

  @override
  String get votingConfigEnterTitleAndUrl => '제⁠목⁠과 소⁠스 URL⁠을 입⁠력⁠해 주⁠세⁠요.';

  @override
  String get votingConfigFieldStaticUrl => '정⁠적 설⁠정 URL';

  @override
  String get votingConfigFieldTitle => '제⁠목';

  @override
  String get votingConfigLoadFailed => '해⁠당 소⁠스⁠에⁠서 투⁠표 설⁠정⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get votingConfigMobileFieldUrl => '소⁠스 URL';

  @override
  String get votingConfigMobileIntro =>
      'Vizor⁠가 인⁠증⁠된 투⁠표 라⁠운⁠드⁠를 가⁠져⁠올 곳⁠을 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get votingConfigMobileSave => '소⁠스 저⁠장';

  @override
  String get votingConfigMobileTestRoundsHint =>
      '[TEST]로 표⁠시⁠된 인⁠증⁠된 라⁠운⁠드⁠를 포⁠함⁠해⁠요.';

  @override
  String get votingConfigMobileTitle => '투⁠표 설⁠정';

  @override
  String get votingConfigMobileUpdateFailed =>
      '투⁠표 설⁠정⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요. 소⁠스⁠를 확⁠인⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get votingConfigSaving => '저⁠장 중...';

  @override
  String get votingConfigSettings => '투⁠표 설⁠정 열⁠기';

  @override
  String get votingConfigShowTestRounds => '테⁠스⁠트 라⁠운⁠드 표⁠시';

  @override
  String get votingConfigShowTestRoundsHint =>
      '제⁠목⁠이 [TEST]로 시⁠작⁠하⁠는 인⁠증⁠된 라⁠운⁠드⁠를 표⁠시⁠해⁠요.';

  @override
  String get votingConfigSources => '소⁠스';

  @override
  String get votingConfigTestVisibilityFailed =>
      '테⁠스⁠트 라⁠운⁠드 표⁠시 설⁠정⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String votingConfigTitleTooLong(int max) {
    return '제⁠목⁠은 $max⁠자 이⁠하⁠여⁠야 해⁠요.';
  }

  @override
  String get votingConfigTooltip => '투⁠표 설⁠정';

  @override
  String get votingConfigUpdateFailed => '투⁠표 설⁠정⁠을 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get votingConfigUrlCopied => '소⁠스 URL⁠을 복⁠사⁠했⁠어⁠요.';

  @override
  String get votingConfigValidating => '확⁠인 중...';

  @override
  String get votingConfirmationCheckingEligibility =>
      '이 계⁠정⁠의 투⁠표 자⁠격⁠을 확⁠인⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get votingConfirmationConfirmedBody =>
      '투⁠표⁠가 성⁠공⁠적⁠으⁠로 게⁠시⁠됐⁠고 변⁠경⁠할 수 없⁠어⁠요.';

  @override
  String get votingConfirmationConfirmedTitle => '제⁠출⁠이 확⁠인⁠됐⁠어⁠요!';

  @override
  String get votingConfirmationEligibilityUnconfirmed =>
      '이 계⁠정⁠의 투⁠표 자⁠격⁠이 확⁠인⁠되⁠지 않⁠았⁠어⁠요.';

  @override
  String get votingConfirmationIncompleteTitle => '제⁠출⁠이 완⁠료⁠되⁠지 않⁠았⁠어⁠요';

  @override
  String votingConfirmationLoadFailed(String error) {
    return '제⁠출 내⁠역⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요: $error';
  }

  @override
  String get votingConfirmationNotCompleted =>
      '이 계⁠정⁠은 이⁠번 투⁠표 라⁠운⁠드⁠의 제⁠출⁠을 완⁠료⁠하⁠지 않⁠았⁠어⁠요.';

  @override
  String get votingConfirmationUpdateFailed =>
      '투⁠표 라⁠운⁠드⁠를 업⁠데⁠이⁠트⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get votingConfirmationUpdatingRounds => '투⁠표 라⁠운⁠드⁠를 업⁠데⁠이⁠트⁠하⁠는 중...';

  @override
  String get votingContinueToReview => '확⁠인 화⁠면⁠으⁠로 계⁠속';

  @override
  String get votingContinueVoting => '투⁠표 이⁠어⁠하⁠기';

  @override
  String votingDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days⁠일 남⁠음',
      zero: '오⁠늘 종⁠료',
    );
    return '$_temp0';
  }

  @override
  String get votingDetailLoadFailedTitle => '투⁠표 라⁠운⁠드⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요';

  @override
  String get votingDetailUnavailableBody =>
      '선⁠택⁠한 투⁠표 라⁠운⁠드⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요.';

  @override
  String get votingDetailUnavailableTitle => '투⁠표 라⁠운⁠드⁠를 사⁠용⁠할 수 없⁠어⁠요';

  @override
  String votingEnds(String date) {
    return '$date 종⁠료';
  }

  @override
  String get votingErrorLedgerCancelled => 'Ledger⁠에⁠서 투⁠표 승⁠인⁠을 취⁠소⁠했⁠어⁠요.';

  @override
  String votingErrorLedgerLocked(String instruction) {
    return 'Ledger⁠의 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요. $instruction';
  }

  @override
  String get votingErrorLedgerRejected =>
      'Ledger⁠에⁠서 투⁠표 서⁠명⁠을 거⁠부⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 서⁠명⁠해 주⁠세⁠요.';

  @override
  String votingErrorLedgerWrongApp(String instruction) {
    return '$instruction 그⁠런 다⁠음 다⁠시 시⁠도⁠해 주⁠세⁠요.';
  }

  @override
  String votingErrorMinimumWeight(String amount, String snapshot) {
    return '투⁠표⁠하⁠려⁠면 $snapshot⁠에 $amount 이⁠상⁠의 자⁠격 있⁠는 차⁠폐 노⁠트 묶⁠음⁠이 하⁠나 이⁠상 필⁠요⁠해⁠요. 자⁠격⁠이 있⁠는 계⁠정⁠으⁠로 전⁠환⁠해 투⁠표⁠해 주⁠세⁠요.';
  }

  @override
  String votingErrorNoSpendableNotes(String snapshot) {
    return '이 계⁠정⁠은 이⁠번 투⁠표 라⁠운⁠드⁠에 참⁠여⁠할 수 없⁠어⁠요. $snapshot⁠에 투⁠표 자⁠격⁠이 있⁠는 차⁠폐 자⁠금⁠이 없⁠었⁠어⁠요. 자⁠격⁠이 있⁠는 계⁠정⁠으⁠로 전⁠환⁠해 투⁠표⁠해 주⁠세⁠요.';
  }

  @override
  String get votingErrorSessionFailed => '투⁠표 작⁠업⁠에 실⁠패⁠했⁠어⁠요.';

  @override
  String get votingForumDiscussion => '포⁠럼 토⁠론';

  @override
  String get votingGuardAccountLoadFailed => '계⁠정⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요';

  @override
  String get votingIneligibleTitle => '이⁠번 투⁠표 라⁠운⁠드⁠에 참⁠여⁠할 수 없⁠어⁠요';

  @override
  String get votingKeepSigning => '계⁠속 서⁠명';

  @override
  String get votingKeepVoting => '계⁠속 투⁠표';

  @override
  String votingKeystoneMemoLabel(int number, int total) {
    return '$total⁠개 중 $number⁠번⁠째 묶⁠음 메⁠모';
  }

  @override
  String get votingKeystoneNextBatch => '다⁠음 서⁠명 묶⁠음⁠이 준⁠비⁠됐⁠어⁠요';

  @override
  String get votingKeystoneNextMemo => '다⁠음 묶⁠음 메⁠모';

  @override
  String get votingKeystoneOneApproval => 'Keystone 승⁠인 한 번';

  @override
  String get votingKeystonePreviousMemo => '이⁠전 묶⁠음 메⁠모';

  @override
  String votingKeystoneQrPartial(int count, int total) {
    return '이 QR⁠로 남⁠은 $total⁠개 묶⁠음 중 $count⁠개⁠에 서⁠명⁠해⁠요';
  }

  @override
  String get votingKeystoneScanInstruction =>
      'Keystone⁠으⁠로 이 화⁠면⁠의 QR⁠을 스⁠캔⁠하⁠세⁠요. 그⁠런 다⁠음 Keystone⁠에 표⁠시⁠된 서⁠명⁠된 투⁠표 QR⁠을 이 기⁠기⁠의 카⁠메⁠라⁠로 스⁠캔⁠하⁠세⁠요';

  @override
  String get votingKeystoneScanSignature => '서⁠명 스⁠캔';

  @override
  String votingKeystoneSignLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '투⁠표 묶⁠음 $count⁠개 서⁠명',
      zero: '투⁠표 서⁠명 준⁠비 중',
    );
    return '$_temp0';
  }

  @override
  String get votingKeystoneUnexpectedUr =>
      'Keystone⁠에⁠서 서⁠명⁠된 투⁠표 QR⁠을 열⁠고 다⁠시 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String get votingLedgerApprovalNotice =>
      'Ledger⁠에⁠서 승⁠인⁠하⁠면 이 투⁠표 위⁠임⁠이 승⁠인⁠돼⁠요. 계⁠속⁠하⁠기 전⁠에 Vizor⁠에⁠서 아⁠래 메⁠모⁠를 확⁠인⁠해 주⁠세⁠요. 기⁠기⁠에⁠는 이 메⁠모⁠가 그⁠대⁠로 표⁠시⁠되⁠지 않⁠을 수 있⁠어⁠요.';

  @override
  String votingLedgerBundleOf(int number, int total) {
    return '$total⁠개 중 $number⁠번⁠째 묶⁠음';
  }

  @override
  String get votingLedgerChecking => 'Ledger 확⁠인 중';

  @override
  String get votingLedgerCheckingBody =>
      'Vizor⁠가 Zcash 앱⁠이 준⁠비⁠됐⁠는⁠지 확⁠인⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get votingLedgerConfirmOpen => 'Zcash 열⁠기 확⁠인';

  @override
  String get votingLedgerConfirmOpenBody =>
      'Ledger⁠에⁠서 Zcash 앱⁠을 열⁠라⁠는 요⁠청⁠을 승⁠인⁠해 주⁠세⁠요.';

  @override
  String get votingLedgerFinishing => '투⁠표 위⁠임 마⁠무⁠리 중';

  @override
  String get votingLedgerNeedsAttention => 'Ledger 확⁠인⁠이 필⁠요⁠해⁠요';

  @override
  String get votingLedgerPanelTitle => '투⁠표 위⁠임';

  @override
  String get votingLedgerPleaseWait =>
      'Vizor⁠가 요⁠청⁠을 준⁠비⁠하⁠는 동⁠안 잠⁠시 기⁠다⁠려 주⁠세⁠요.';

  @override
  String get votingLedgerPreparing => '투⁠표 위⁠임 준⁠비 중';

  @override
  String get votingLedgerReconnect => 'Ledger⁠를 다⁠시 연⁠결⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String votingMobileAccountLoadFailed(String error) {
    return '계⁠정⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요.\n$error';
  }

  @override
  String get votingMobileGoHome => '홈⁠으⁠로';

  @override
  String get votingMobileHeaderTitle => '투⁠표';

  @override
  String get votingMobileKeystoneChecking => '투⁠표 서⁠명⁠을 확⁠인⁠하⁠는 중...';

  @override
  String get votingMobileKeystoneDescription =>
      'Keystone⁠으⁠로 투⁠표 요⁠청⁠을 스⁠캔⁠해 승⁠인⁠한 다⁠음, 서⁠명⁠된 결⁠과⁠를 이 기⁠기⁠로 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String get votingMobileKeystoneFailedTitle => '투⁠표 서⁠명⁠에 실⁠패⁠했⁠어⁠요';

  @override
  String get votingMobileKeystoneNextBundle => '다⁠음 투⁠표 묶⁠음';

  @override
  String get votingMobileKeystonePreviousBundle => '이⁠전 투⁠표 묶⁠음';

  @override
  String get votingMobileKeystoneReading => '투⁠표 서⁠명⁠을 읽⁠는 중...';

  @override
  String get votingMobileKeystoneScanCaption =>
      'Keystone⁠에 표⁠시⁠된 서⁠명⁠된 투⁠표 QR⁠을 스⁠캔⁠하⁠세⁠요';

  @override
  String get votingMobileKeystoneSkipUnsigned => '서⁠명⁠하⁠지 않⁠은 묶⁠음 건⁠너⁠뛰⁠기';

  @override
  String get votingMobileKeystoneTitle => 'Keystone⁠으⁠로 투⁠표 서⁠명';

  @override
  String get votingMobileLeaveWarning => '이 화⁠면⁠을 벗⁠어⁠나⁠지 마⁠세⁠요.';

  @override
  String get votingMobileProgressSemantics => '현⁠재 투⁠표 제⁠출 단⁠계 진⁠행⁠률';

  @override
  String get votingMobileProofNotice =>
      '영⁠지⁠식 증⁠명⁠을 생⁠성⁠하⁠는 데 약 60⁠초⁠가 걸⁠릴 수 있⁠으⁠며, 지⁠금 닫⁠으⁠면 진⁠행 중⁠인 증⁠명 작⁠업⁠이 사⁠라⁠질 수 있⁠어⁠요.';

  @override
  String get votingMobileSubmitTitle => '투⁠표 제⁠출';

  @override
  String get votingMobileSubmittedBody => '투⁠표⁠를 제⁠출⁠했⁠고 변⁠경⁠할 수 없⁠어⁠요.';

  @override
  String get votingMobileSubmittedTitle => '투⁠표 제⁠출 완⁠료';

  @override
  String get votingMobileSubmittingTitle => '투⁠표⁠를 제⁠출⁠하⁠는 중...';

  @override
  String get votingNavAllAnswered => '모⁠든 질⁠문⁠에 답⁠했⁠어⁠요';

  @override
  String votingNavAnsweredProgress(int answered, int total) {
    return '$total⁠개 중 $answered⁠개 답⁠변';
  }

  @override
  String get votingNavReadyToReview => '답⁠변⁠을 확⁠인⁠할 준⁠비⁠가 됐⁠어⁠요.';

  @override
  String get votingNavTapToJump => '질⁠문⁠을 탭⁠하⁠면 해⁠당 질⁠문⁠으⁠로 이⁠동⁠해⁠요.';

  @override
  String votingNavUnansweredCount(int count) {
    return '미⁠응⁠답 · $count';
  }

  @override
  String get votingNavUnansweredMenu => '미⁠응⁠답 질⁠문';

  @override
  String get votingNoProposalsBody => '이 투⁠표 라⁠운⁠드⁠에⁠는 안⁠건⁠이 없⁠어⁠요.';

  @override
  String get votingNoProposalsTitle => '안⁠건⁠이 없⁠어⁠요';

  @override
  String get votingNotAvailable => '사⁠용⁠할 수 없⁠음';

  @override
  String get votingNotEligible => '참⁠여⁠할 수 없⁠음';

  @override
  String get votingOptionChoose => '선⁠택';

  @override
  String get votingOptionSelected => '선⁠택⁠됨';

  @override
  String get votingPendingBody =>
      '이⁠번 라⁠운⁠드⁠에⁠서 끝⁠내⁠지 못⁠한 투⁠표⁠가 있⁠어⁠요. 이⁠어⁠서 제⁠출⁠을 완⁠료⁠해 주⁠세⁠요.';

  @override
  String get votingPendingTitle => '투⁠표 진⁠행 중';

  @override
  String votingPirAhead(String expected, String reported) {
    return '설⁠정⁠된 PIR 엔⁠드⁠포⁠인⁠트⁠가 이 투⁠표 라⁠운⁠드 스⁠냅⁠샷⁠보⁠다 앞⁠서 있⁠어⁠요. 예⁠상 스⁠냅⁠샷 블⁠록⁠은 $expected⁠이⁠고 엔⁠드⁠포⁠인⁠트⁠는 $reported(으)로 보⁠고⁠해⁠요.';
  }

  @override
  String votingPirBehind(String expected, String reported) {
    return '이 투⁠표 라⁠운⁠드⁠의 PIR 데⁠이⁠터⁠가 아⁠직 준⁠비⁠되⁠지 않⁠았⁠어⁠요. 예⁠상 스⁠냅⁠샷 블⁠록⁠은 $expected⁠이⁠고 PIR 엔⁠드⁠포⁠인⁠트⁠는 $reported(으)로 보⁠고⁠해⁠요. PIR 서⁠비⁠스⁠가 따⁠라⁠잡⁠으⁠면 다⁠시 시⁠도⁠해 주⁠세⁠요.';
  }

  @override
  String votingPirNoMatch(String expected) {
    return '이 투⁠표 라⁠운⁠드 스⁠냅⁠샷⁠과 일⁠치⁠하⁠는 PIR 엔⁠드⁠포⁠인⁠트⁠가 없⁠어⁠요. 예⁠상 스⁠냅⁠샷 블⁠록⁠은 $expected⁠이⁠에⁠요.';
  }

  @override
  String votingPirNoMatchDiagnostics(String expected, String diagnostics) {
    return '이 투⁠표 라⁠운⁠드 스⁠냅⁠샷⁠과 일⁠치⁠하⁠는 PIR 엔⁠드⁠포⁠인⁠트⁠가 없⁠어⁠요. 예⁠상 스⁠냅⁠샷 블⁠록⁠은 $expected⁠이⁠에⁠요. 진⁠단 정⁠보: $diagnostics.';
  }

  @override
  String get votingPirUnreachable =>
      '설⁠정⁠된 PIR 엔⁠드⁠포⁠인⁠트⁠에 연⁠결⁠하⁠지 못⁠했⁠어⁠요. 네⁠트⁠워⁠크 연⁠결⁠을 확⁠인⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get votingPollAlreadyUsed => '이⁠번 라⁠운⁠드⁠에⁠서 이⁠미 사⁠용⁠했⁠어⁠요';

  @override
  String votingPollClosed(String date) {
    return '$date 마⁠감⁠됨';
  }

  @override
  String votingPollCloses(String date) {
    return '$date 마⁠감';
  }

  @override
  String get votingPollNotEligible => '이⁠번 라⁠운⁠드⁠에 참⁠여⁠할 수 없⁠어⁠요';

  @override
  String votingPollStarts(String date) {
    return '$date 시⁠작';
  }

  @override
  String get votingPollsEmptyBody => '아⁠직 표⁠시⁠할 토⁠큰 보⁠유⁠자 투⁠표 라⁠운⁠드⁠가 없⁠어⁠요.';

  @override
  String get votingPollsEmptyTitle => '진⁠행 중⁠인 투⁠표 라⁠운⁠드⁠가 없⁠어⁠요';

  @override
  String get votingPollsLoadFailedTitle => '투⁠표 라⁠운⁠드⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요';

  @override
  String votingPowerMeta(String amount) {
    return '투⁠표⁠권 $amount';
  }

  @override
  String get votingPowerUnavailableSentence => '투⁠표⁠권⁠을 확⁠인⁠할 수 없⁠어⁠요.';

  @override
  String get votingPowerUnavailableTitle => '투⁠표⁠권⁠을 확⁠인⁠할 수 없⁠어⁠요';

  @override
  String get votingPreparingEllipsis => '준⁠비 중...';

  @override
  String get votingPreparingPower => '투⁠표⁠권⁠을 준⁠비⁠하⁠는 중⁠이⁠에⁠요.';

  @override
  String get votingPreparingPowerMeta => '투⁠표⁠권 준⁠비 중';

  @override
  String votingPrivacyTrimNotice(String amount) {
    return '제⁠출⁠한 투⁠표⁠를 덜 식⁠별⁠되⁠게 하⁠려⁠고 $amount⁠은(는) 이⁠번 투⁠표⁠에⁠서 제⁠외⁠돼⁠요.';
  }

  @override
  String votingProgressBundlesProved(int proved, int total) {
    return '$total⁠개 중 $proved⁠개 묶⁠음 증⁠명 완⁠료';
  }

  @override
  String votingProgressFinalizingDelegation(String suffix) {
    return '위⁠임 마⁠무⁠리 중⁠$suffix';
  }

  @override
  String votingProgressReusingProof(String suffix) {
    return '진⁠행 중⁠인 증⁠명⁠을 재⁠사⁠용⁠하⁠는 중⁠$suffix';
  }

  @override
  String get votingProgressUnknown => '알 수 없⁠음';

  @override
  String votingProgressWaitingConfirmation(String suffix) {
    return '제⁠출 및 확⁠인 대⁠기 중⁠$suffix';
  }

  @override
  String get votingReceiptPower => '투⁠표⁠권';

  @override
  String get votingReceiptRound => '투⁠표 라⁠운⁠드';

  @override
  String votingRemainingBundles(int count, int total) {
    return '남⁠은 $total⁠개 묶⁠음 중 $count⁠개';
  }

  @override
  String get votingResultsFallbackTitle => '투⁠표 결⁠과';

  @override
  String get votingResultsHeading => '결⁠과';

  @override
  String get votingResultsHideDescription => '설⁠명 숨⁠기⁠기';

  @override
  String votingResultsLoadFailed(String error) {
    return '결⁠과⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요: $error';
  }

  @override
  String get votingResultsNoProposals => '이⁠번 라⁠운⁠드⁠에⁠는 안⁠건⁠이 없⁠어⁠요.';

  @override
  String get votingResultsPending => '결⁠과 집⁠계 대⁠기 중...';

  @override
  String votingResultsRoundLoadFailed(String error) {
    return '투⁠표 라⁠운⁠드 정⁠보⁠를 불⁠러⁠오⁠지 못⁠했⁠어⁠요: $error';
  }

  @override
  String get votingResultsShowDescription => '설⁠명 보⁠기';

  @override
  String get votingResultsTotal => '합⁠계';

  @override
  String votingResultsTotalAmount(String amount) {
    return '합⁠계: $amount';
  }

  @override
  String get votingResultsVoted => '투⁠표⁠함';

  @override
  String votingResultsVotedFor(String choice) {
    return '투⁠표: $choice';
  }

  @override
  String get votingResultsWinner => '우⁠승';

  @override
  String get votingResultsYourVote => '내 투⁠표';

  @override
  String get votingReviewChooseOne => '제⁠출⁠하⁠기 전⁠에 하⁠나 이⁠상 선⁠택⁠해 주⁠세⁠요.';

  @override
  String get votingReviewConfirmSubmit => '확⁠인 및 제⁠출';

  @override
  String votingReviewLoadFailed(String error) {
    return '검⁠토 화⁠면⁠을 불⁠러⁠오⁠지 못⁠했⁠어⁠요: $error';
  }

  @override
  String get votingReviewSkipped => '건⁠너⁠뜀';

  @override
  String get votingReviewTitle => '답⁠변 확⁠인';

  @override
  String get votingScanHold => 'Keystone QR 코⁠드⁠를 카⁠메⁠라 앞⁠에 고⁠정⁠해 주⁠세⁠요';

  @override
  String get votingScanNoCamera =>
      'Keystone 투⁠표⁠는 카⁠메⁠라 QR 스⁠캔⁠만 지⁠원⁠해⁠요. 카⁠메⁠라⁠를 연⁠결⁠하⁠고 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get votingScanReading => '서⁠명⁠을 읽⁠는 중...';

  @override
  String get votingScanSteady => 'QR 코⁠드⁠가 흔⁠들⁠리⁠지 않⁠고 전⁠부 보⁠이⁠게 해 주⁠세⁠요.';

  @override
  String get votingScanTitle => '투⁠표 서⁠명 스⁠캔';

  @override
  String get votingSignedOnlyBody =>
      'Vizor⁠는 Keystone⁠에⁠서 이⁠미 스⁠캔⁠한 서⁠명⁠만⁠으⁠로 지⁠금 제⁠출⁠할 수 있⁠어⁠요.';

  @override
  String get votingSignedOnlyTitle => '서⁠명⁠한 묶⁠음⁠만 사⁠용⁠할⁠까⁠요?';

  @override
  String get votingSignedOnlyWarning =>
      '서⁠명⁠하⁠지 않⁠은 묶⁠음⁠은 건⁠너⁠뛰⁠며, 이⁠번 투⁠표 라⁠운⁠드⁠의 투⁠표⁠권⁠이 줄⁠어⁠들⁠어⁠요.';

  @override
  String get votingSkip => '건⁠너⁠뛰⁠기';

  @override
  String get votingSkipBundles => '묶⁠음 건⁠너⁠뛰⁠기';

  @override
  String votingSkipDialogBody(int skipped, int total) {
    return '$total⁠개 질⁠문 중 $skipped⁠개⁠에 답⁠하⁠지 않⁠았⁠어⁠요. 확⁠인 화⁠면⁠에⁠서 건⁠너⁠뜀⁠으⁠로 표⁠시⁠되⁠며, 건⁠너⁠뛴 질⁠문⁠은 제⁠출⁠되⁠지 않⁠아⁠요.';
  }

  @override
  String get votingSkipDialogTitle => '답⁠하⁠지 않⁠은 질⁠문⁠을 건⁠너⁠뛸⁠까⁠요?';

  @override
  String votingSnapshotBlock(String height) {
    return '스⁠냅⁠샷 블⁠록 $height';
  }

  @override
  String get votingSnapshotUnknown => '투⁠표 라⁠운⁠드 스⁠냅⁠샷 블⁠록';

  @override
  String get votingSoftwareRequiredBody =>
      '토⁠큰 보⁠유⁠자 투⁠표⁠에⁠는 소⁠프⁠트⁠웨⁠어 계⁠정⁠이 필⁠요⁠해⁠요. 이⁠번 라⁠운⁠드⁠에⁠서 투⁠표⁠하⁠려⁠면 소⁠프⁠트⁠웨⁠어 계⁠정⁠으⁠로 전⁠환⁠해 주⁠세⁠요.';

  @override
  String get votingSoftwareRequiredTitle => '소⁠프⁠트⁠웨⁠어 계⁠정⁠이 필⁠요⁠해⁠요';

  @override
  String get votingStatusActive => '진⁠행 중';

  @override
  String get votingStatusBodyKeepOpen =>
      '창⁠을 닫⁠지 마⁠세⁠요. 영⁠지⁠식 증⁠명⁠을 생⁠성⁠하⁠는 데 시⁠간⁠이 걸⁠릴 수 있⁠으⁠며, 지⁠금 닫⁠으⁠면 진⁠행 중⁠인 증⁠명 작⁠업⁠이 사⁠라⁠질 수 있⁠어⁠요.';

  @override
  String get votingStatusBodyLedger =>
      'Vizor⁠를 열⁠어 둔 채⁠로 아⁠래 안⁠내⁠에 따⁠라 각 투⁠표 묶⁠음⁠을 처⁠리⁠해 주⁠세⁠요.';

  @override
  String get votingStatusClosed => '마⁠감⁠됨';

  @override
  String get votingStatusFailed => '투⁠표⁠에 실⁠패⁠했⁠어⁠요.';

  @override
  String get votingStatusGenericError =>
      '이 계⁠정⁠으⁠로 투⁠표⁠를 계⁠속⁠할 수 없⁠어⁠요. 다⁠시 시⁠도⁠하⁠거⁠나, 이 계⁠정⁠이 이⁠번 투⁠표 라⁠운⁠드⁠에 참⁠여⁠할 수 없⁠다⁠면 자⁠격⁠이 있⁠는 계⁠정⁠으⁠로 전⁠환⁠해 주⁠세⁠요.';

  @override
  String get votingStatusTallying => '집⁠계 중';

  @override
  String get votingStatusTitleLedger => 'Ledger⁠로 투⁠표';

  @override
  String get votingStatusTitleSubmitting => '투⁠표 제⁠출 중';

  @override
  String get votingStatusVoted => '투⁠표 완⁠료';

  @override
  String get votingStepCasting => '투⁠표 및 지⁠분 제⁠출 중';

  @override
  String get votingStepFinalizing => '제⁠출 마⁠무⁠리 중';

  @override
  String get votingStepProving => '투⁠표 권⁠한 증⁠명 중';

  @override
  String get votingStepSigningKeystone => 'Keystone⁠으⁠로 서⁠명 중';

  @override
  String get votingStepSigningLedger => 'Ledger⁠로 서⁠명 중';

  @override
  String get votingSwitchAccount => '계⁠정 전⁠환';

  @override
  String get votingSwitchEligibleGuidance =>
      '자⁠격⁠이 있⁠는 계⁠정⁠으⁠로 전⁠환⁠해 투⁠표⁠해 주⁠세⁠요.';

  @override
  String votingSyncBlocksRemaining(int count) {
    return '$count⁠개 블⁠록 남⁠음';
  }

  @override
  String votingSyncChainTip(int height) {
    return '체⁠인 최⁠신 블⁠록 $height';
  }

  @override
  String votingSyncSynced(int height) {
    return '블⁠록 $height⁠까⁠지 동⁠기⁠화⁠됨';
  }

  @override
  String get votingSyncWaitingBody =>
      '지⁠갑⁠이 이⁠번 투⁠표 라⁠운⁠드 스⁠냅⁠샷⁠을 따⁠라⁠잡⁠는 중⁠이⁠에⁠요. 지⁠갑⁠이 스⁠냅⁠샷 블⁠록⁠까⁠지 동⁠기⁠화⁠되⁠면 투⁠표⁠가 자⁠동⁠으⁠로 이⁠어⁠져⁠요.';

  @override
  String get votingSyncWaitingTitle => '지⁠갑 동⁠기⁠화 대⁠기 중';

  @override
  String votingTerminalBundle(int number, String reason) {
    return '$number⁠번 묶⁠음($reason)';
  }

  @override
  String votingTerminalMultiple(String bundles) {
    return '$bundles⁠의 위⁠임⁠은 계⁠속⁠할 수 없⁠어⁠요. 거⁠래⁠가 이⁠미 체⁠인⁠에 있⁠을 수 있⁠으⁠니 다⁠시 시⁠도⁠하⁠지 마⁠세⁠요.';
  }

  @override
  String get votingTerminalReasonDefault => '확⁠인 없⁠이 종⁠료⁠됐⁠어⁠요';

  @override
  String votingTerminalSingle(String bundle) {
    return '위⁠임 $bundle⁠은(는) 계⁠속⁠할 수 없⁠어⁠요. 거⁠래⁠가 이⁠미 체⁠인⁠에 있⁠을 수 있⁠으⁠니 다⁠시 시⁠도⁠하⁠지 마⁠세⁠요.';
  }

  @override
  String get votingTokenHolderTitle => '토⁠큰 보⁠유⁠자 투⁠표';

  @override
  String get votingViewLess => '간⁠단⁠히 보⁠기';

  @override
  String get votingViewMore => '더 보⁠기';

  @override
  String get votingVoteLocked => '투⁠표 확⁠정⁠됨';

  @override
  String votingVotedOn(String date) {
    return '$date 투⁠표';
  }

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
  String get walletLinkDesktopConfirmSubtitle =>
      'Vizor 모⁠바⁠일⁠을 연⁠결⁠하⁠려⁠면 필⁠요⁠해⁠요.';

  @override
  String get walletLinkDesktopEncryptedNotice =>
      '코⁠드⁠는 일⁠회⁠용 키⁠로 암⁠호⁠화⁠되⁠며 일 분 뒤⁠에 만⁠료⁠돼⁠요.';

  @override
  String get walletLinkDesktopEncryptedStrong => '휴⁠대⁠폰⁠에⁠서⁠만 해⁠독⁠할 수 있⁠어⁠요.';

  @override
  String get walletLinkDesktopErrorDerivationMissing =>
      '지⁠갑 계⁠정⁠의 파⁠생 정⁠보⁠를 찾⁠을 수 없⁠어⁠요.';

  @override
  String get walletLinkDesktopErrorExpiredBeforeShown =>
      '모⁠바⁠일 연⁠결 코⁠드⁠가 표⁠시⁠되⁠기 전⁠에 만⁠료⁠됐⁠어⁠요.';

  @override
  String get walletLinkDesktopErrorFallback => '모⁠바⁠일 연⁠결⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요.';

  @override
  String get walletLinkDesktopErrorHardwareMetadataMissing =>
      '하⁠드⁠웨⁠어 지⁠갑 정⁠보⁠를 찾⁠을 수 없⁠어⁠요.';

  @override
  String get walletLinkDesktopErrorLocked =>
      '모⁠바⁠일⁠을 연⁠결⁠하⁠기 전⁠에 이 지⁠갑⁠의 잠⁠금⁠을 해⁠제⁠해 주⁠세⁠요.';

  @override
  String get walletLinkDesktopErrorNoAccounts => '연⁠결⁠할 지⁠갑 계⁠정⁠이 없⁠어⁠요.';

  @override
  String get walletLinkDesktopErrorPrepareFailed =>
      '모⁠바⁠일 연⁠결⁠을 준⁠비⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get walletLinkDesktopErrorServerUnreachable =>
      '연⁠결 서⁠버⁠에 접⁠속⁠하⁠지 못⁠했⁠어⁠요. 다⁠시 시⁠도⁠해 주⁠세⁠요.';

  @override
  String get walletLinkDesktopExpiredBody =>
      '보⁠안⁠을 위⁠해 연⁠결 코⁠드⁠는 일 분 동⁠안⁠만 유⁠효⁠해⁠요. 새 코⁠드⁠를 생⁠성⁠하⁠고 다⁠시 스⁠캔⁠해 주⁠세⁠요.';

  @override
  String get walletLinkDesktopExpiredTitle => '시⁠간⁠이 다 됐⁠어⁠요';

  @override
  String walletLinkDesktopExpiresIn(String time) {
    return '$time 후 만⁠료';
  }

  @override
  String get walletLinkDesktopGenerateNewCode => '새 코⁠드 생⁠성';

  @override
  String get walletLinkDesktopInitialBody =>
      '일⁠회⁠용 QR 코⁠드⁠를 스⁠캔⁠해 이 지⁠갑⁠을 Vizor 모⁠바⁠일 앱⁠에 연⁠결⁠하⁠세⁠요.';

  @override
  String get walletLinkDesktopLinkedBody => 'Vizor 모⁠바⁠일⁠이 이 지⁠갑⁠에 연⁠결⁠됐⁠어⁠요.';

  @override
  String walletLinkDesktopLinkedCounts(int accountCount, int contactCount) {
    return '모⁠바⁠일⁠에⁠서 계⁠정 $accountCount⁠개⁠와 연⁠락⁠처 $contactCount⁠개⁠를 가⁠져⁠왔⁠어⁠요.';
  }

  @override
  String get walletLinkDesktopLinkedTitle => 'Vizor 모⁠바⁠일⁠을 연⁠결⁠했⁠어⁠요';

  @override
  String get walletLinkDesktopPreparing => '준⁠비 중';

  @override
  String get walletLinkDesktopReadyToScan => '1/1 스⁠캔 준⁠비 완⁠료...';

  @override
  String get walletLinkDesktopRegenerate => '다⁠시 생⁠성';

  @override
  String get walletLinkDesktopScanBody =>
      '휴⁠대⁠폰⁠에⁠서 Vizor 열⁠기 → 지⁠갑 추⁠가 → Vizor 데⁠스⁠크⁠톱 연⁠결';

  @override
  String get walletLinkDesktopScanTitle => 'Vizor 모⁠바⁠일⁠로 스⁠캔';

  @override
  String get walletLinkDesktopStartLinking => '연⁠결 시⁠작';

  @override
  String get walletLinkDesktopTitle => 'Vizor 모⁠바⁠일 연⁠결';

  @override
  String get walletLinkDesktopUnavailableTitle => '연⁠결⁠할 수 없⁠어⁠요';

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
