// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get aboutBuiltByBody =>
      '我们打造了 Keplr，这款钱包被 Cosmos、Ethereum 和 Bitcoin 生态中的数百万用户使用。Vizor 是我们对 Zcash 钱包应有体验的诠释。';

  @override
  String get aboutBuiltByHeading => '由 Keplr 团队打造';

  @override
  String get aboutLegalPlaceholderBody =>
      '与 Bitcoin 或 Ethereum 不同，屏蔽 Zcash 交易会隐藏发送方、接收方和金额。';

  @override
  String get aboutLegalPlaceholderHeading => '来自打造 Keplr 钱包的团队。';

  @override
  String aboutLinkSemantics(String label) {
    return '$label链接';
  }

  @override
  String get aboutOpenGithub => '打开 Vizor GitHub';

  @override
  String get aboutOpenSourceBody =>
      'Vizor 采用 Apache 许可证。你的密钥只保存在你的设备上。\n我们看不到你的余额或交易。';

  @override
  String get aboutOpenSourceHeading => '开源，自主托管';

  @override
  String get aboutOpenWebsite => '打开 Vizor 网站';

  @override
  String get aboutShieldedBody =>
      'Vizor 围绕屏蔽交易构建，发送方、接收方和金额均保持私密。也支持透明 Zcash，但默认是私密的。';

  @override
  String get aboutShieldedHeading => '为屏蔽 Zcash 而设计';

  @override
  String get aboutTermsTitle => '使用条款';

  @override
  String get aboutTitle => '关于 Vizor 钱包';

  @override
  String aboutVersionLabel(String version) {
    return '版本：$version 公测版';
  }

  @override
  String get aboutWebsite => '网站';

  @override
  String get accountNameLabel => '账户名称';

  @override
  String get accountNameTooLong => '名称最多 20 个字符。';

  @override
  String get accountsActionsLabel => '账户操作';

  @override
  String get accountsAddressLoadFailed => '无法加载账户地址';

  @override
  String get accountsClearName => '清除账户名称';

  @override
  String get accountsCurrent => '当前账户';

  @override
  String get accountsEdit => '编辑账户';

  @override
  String get accountsEditFailed => '无法更新账户。';

  @override
  String get accountsEditNameHint => '1-20 个字符';

  @override
  String get accountsManage => '管理账户';

  @override
  String accountsOptionsFor(String name) {
    return '$name 的账户选项';
  }

  @override
  String get accountsOther => '其他账户';

  @override
  String get accountsOtherAccounts => '其他账户';

  @override
  String get accountsRemove => '移除账户';

  @override
  String get accountsRemoveBackupWarning => '如果你尚未备份此账户的助记词，移除后将无法找回其资金。';

  @override
  String accountsRemoveBlockedByGiftCards(int count) {
    return '此账户正在接收 $count 张礼品卡。移除此账户前，请等待完成。';
  }

  @override
  String accountsRemoveBlockedBySwaps(int count) {
    return '此账户有 $count 个进行中的兑换。移除此账户前，请先在兑换活动中完成或移除它们。';
  }

  @override
  String get accountsRemoveBody => '移除此账户会从 Vizor 中删除其本地数据。继续之前，请确保你可以重新导入该账户。';

  @override
  String get accountsRemoveCheckingGiftCards => '正在检查此账户在移除前是否有正在接收的礼品卡。';

  @override
  String get accountsRemoveCheckingPassword => '正在验证密码...';

  @override
  String get accountsRemoveCheckingSwaps => '正在检查此账户在移除前是否有进行中的兑换。';

  @override
  String get accountsRemoveFailed => '无法移除账户。';

  @override
  String get accountsRemoveFailedToast => '无法移除账户';

  @override
  String get accountsRemoveGiftCardsCheckFailed => '无法检查此账户是否有正在接收的礼品卡。移除前请重试。';

  @override
  String get accountsRemoveGiftCardsMoreFunded => '更多礼品卡链接已充值。请查看警告并再次确认。';

  @override
  String get accountsRemoveGiftCardsRecheckFailed => '无法重新检查礼品卡链接。请查看警告并再次确认。';

  @override
  String get accountsRemoveMigrationBody =>
      '此账户的迁移将不再在 Vizor 中继续。已提交到 Zcash 网络的交易仍可能完成。重新导入后，请先让该账户完全同步，再重新开始迁移。';

  @override
  String get accountsRemoveModalBody => '确定要移除此账户吗？此操作无法撤销。\n你需要重新导入该账户。';

  @override
  String get accountsRemovePasswordHint => '请输入密码';

  @override
  String get accountsRemoveStoppingSync => '正在停止同步...';

  @override
  String get accountsRemoveSwapsCheckFailed => '无法检查此账户是否有进行中的兑换。移除前请重试。';

  @override
  String get accountsRemoveWaitForGiftCards => '请等待正在接收的礼品卡完成后再删除此账户。';

  @override
  String get accountsRemoving => '正在移除账户...';

  @override
  String get accountsResetBody =>
      '重置 Vizor 会删除所有账户和全部本地钱包数据。继续之前，请确保你可以重新导入账户。';

  @override
  String get accountsResetFailed => '无法重置 Vizor。';

  @override
  String get accountsResetFailedToast => '无法重置 Vizor';

  @override
  String get accountsResetMigrationBody =>
      '重置 Vizor 会停止此设备上的迁移，并删除所有账户和全部本地钱包数据。已提交到 Zcash 网络的交易仍可能完成。重新导入后，请先让每个账户完全同步，再重新开始迁移。';

  @override
  String get accountsResetModalBody =>
      '移除此账户将彻底重置 Vizor 应用，即删除所有账户，并需要重新导入账户。\n未分享的礼品卡链接也将永久丢失。\n此操作无法撤销。';

  @override
  String get accountsResetting => '正在重置...';

  @override
  String get accountsSaveEdits => '保存更改';

  @override
  String get accountsSaveFailed => '无法保存账户更改';

  @override
  String get accountsSendFailed => '无法开始发送';

  @override
  String get accountsTitle => '账户';

  @override
  String get accountsUpdatePicture => '更新头像';

  @override
  String get accountsViewSecretPhrase => '查看助记词';

  @override
  String get accountsViewViewingKey => '显示查看密钥';

  @override
  String get activityAddressUnified => '统一地址';

  @override
  String get activityBalanceFromOrchard => '来自 Orchard 余额';

  @override
  String get activityBalanceFromTransparent => '来自透明余额';

  @override
  String get activityBalanceIronwood => 'Ironwood 余额';

  @override
  String get activityBalanceOrchard => 'Orchard 余额';

  @override
  String get activityDetailsLoadFailed => '失败，请重试';

  @override
  String get activityDetailsLoadPublicly => '公开加载';

  @override
  String get activityDetailsLoadPubliclyLabel => '完整详情';

  @override
  String get activityDetailsLoading => '加载中…';

  @override
  String get activityDetailsNotCovered => '隐私模式下不可用';

  @override
  String get activityDetailsOmittedLabel => '未显示';

  @override
  String get activityDetailsOutputsLabel => '交易输出';

  @override
  String get activityDetailsOutputsUnattributed => '收款方未确认';

  @override
  String get activityDetailsUnavailable => '详情暂不可用，服务恢复连接后将自动更新';

  @override
  String get activityDetailsUnknownRecipient => '未知收款方';

  @override
  String get activityEtaFunding => '预计 2–6 分钟';

  @override
  String get activityEtaNu7 => '预计 1 分钟内';

  @override
  String get activityEtaNu7Funding => '预计 1–2 分钟';

  @override
  String get activityEtaStandard => '预计 1–3 分钟';

  @override
  String get activityEtaTakingLonger => '耗时较长';

  @override
  String get activityFeedEmpty => '暂无活动';

  @override
  String get activityFeedRetry => '重新加载活动';

  @override
  String activityGiftBatchBreakdown(
    String cards,
    String fees,
    String feeLabel,
    String fee,
  ) {
    return '卡片 $cards ZEC · 领取手续费 $fees ZEC · $feeLabel $fee';
  }

  @override
  String get activityGiftCreated => '已创建礼品卡';

  @override
  String activityGiftCreatedMany(int count) {
    return '已创建 $count 张礼品卡';
  }

  @override
  String get activityGiftCreating => '正在创建卡片';

  @override
  String activityGiftCreatingMany(int count) {
    return '正在创建 $count 张卡片';
  }

  @override
  String get activityGiftCreationFailed => '礼品卡创建失败';

  @override
  String get activityGiftGroupFailed => '礼品卡批量创建失败';

  @override
  String get activityGiftRedeemed => '已领取礼品卡';

  @override
  String get activityGiftRedeeming => '正在领取卡片';

  @override
  String get activityGiftRedemptionFailed => '礼品卡领取失败';

  @override
  String get activityGiftStatusRedeemed => '已领取';

  @override
  String get activityGiftStatusRedeeming => '领取中…';

  @override
  String get activityGiftTotalPlanned => '计划总额';

  @override
  String get activityGiftTotalSpent => '总支出';

  @override
  String get activityGiftTotalSubmitted => '已提交总额';

  @override
  String get activityLoadFailedDesktop => '无法加载活动。';

  @override
  String get activityLoadFailedMobile => '无法加载活动，请稍后重试。';

  @override
  String get activityOmissionLaterOutputs => '第二个之后的输出';

  @override
  String activityOmissionMoreOutputs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '另有 $count 个输出',
    );
    return '$_temp0';
  }

  @override
  String get activityOmissionOtherSenders => '其他发送地址';

  @override
  String get activityOmissionOutputAddress => '输出地址';

  @override
  String get activityOmissionSender => '发送地址';

  @override
  String get activityOmissionSharedFunding => '来自其他钱包的输入';

  @override
  String get activityOmissionShieldedFunding => '资金中的屏蔽部分';

  @override
  String get activityPayFromShielded => '来自屏蔽 ZEC';

  @override
  String activityPayFromShieldedOnChain(String network) {
    return '来自屏蔽 ZEC · $network';
  }

  @override
  String get activityPayIncomplete => '支付未完成';

  @override
  String get activityPayPaid => '已支付';

  @override
  String get activityPayPaying => '支付中 ...';

  @override
  String get activityPoolMixed => '混合';

  @override
  String get activityPublicLookupBody => 'Vizor 会向服务器请求这一笔交易，以显示隐私查询未包含的信息。';

  @override
  String get activityPublicLookupTitle => '要公开加载详情吗？';

  @override
  String get activityPublicLookupWarning =>
      '服务器会得知此钱包对这笔交易感兴趣，如果没有使用 Tor，还会得知你的 IP 地址。';

  @override
  String get activityReceiptAmountMigrated => '迁移金额';

  @override
  String get activityReceiptCardFee => '卡片手续费';

  @override
  String get activityReceiptDetails => '详情';

  @override
  String get activityReceiptDetailsIncomplete => '详情不完整';

  @override
  String get activityReceiptDetailsIncompleteHelp =>
      '此交易的部分详情（如收款方、备注或手续费）尚不明确，显示的金额可能会变化。';

  @override
  String get activityReceiptEstimatedNetworkFee => '预估网络手续费';

  @override
  String get activityReceiptFrom => '来自';

  @override
  String get activityReceiptIncomplete => '不完整';

  @override
  String get activityReceiptLoadFailed => '无法加载交易。';

  @override
  String get activityReceiptLoading => '正在加载交易…';

  @override
  String get activityReceiptNetChange => '净变动';

  @override
  String get activityReceiptOutput => '输出';

  @override
  String get activityReceiptRefreshFailed => '无法刷新最新的交易状态。';

  @override
  String get activityReceiptStatus => '状态';

  @override
  String get activityReceiptUnattributedFeeHelp => '此交易的总手续费。你的账户承担的部分未知。';

  @override
  String activityRowToday(String time) {
    return '今天 $time';
  }

  @override
  String get activityRowWaitingForConnection => '等待连接';

  @override
  String activityRowYesterday(String time) {
    return '昨天 $time';
  }

  @override
  String get activitySectionEarlier => '更早';

  @override
  String get activitySectionThisWeek => '本周';

  @override
  String get activitySenderShielded => '屏蔽发送方';

  @override
  String get activitySenderUnknown => '未知发送方';

  @override
  String get activityStatusFailedFundsReturned => '失败，资金已退回';

  @override
  String get activityStatusIncompleteDeposit => '存入不足';

  @override
  String activitySwapAssetOnChain(String symbol, String chain) {
    return '$chain 上的 $symbol';
  }

  @override
  String activitySwapDepositedAsset(String symbol) {
    return '已存入 $symbol';
  }

  @override
  String activitySwapMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String activitySwapReceivedAsset(String symbol) {
    return '已接收 $symbol';
  }

  @override
  String activitySwapStep(int current, int total) {
    return '$current/$total 进行中';
  }

  @override
  String get activitySwapSwapped => '兑换完成';

  @override
  String get activitySwapSwapping => '兑换中...';

  @override
  String get activitySwapTimeout => '已超时';

  @override
  String get activitySwapTitle => '兑换';

  @override
  String get activityTitleMigrated => '已迁移到 Ironwood';

  @override
  String get activityTitleMigrating => '正在迁移到 Ironwood...';

  @override
  String get activityTitleMigratingVerb => '正在迁移到 Ironwood';

  @override
  String get activityTitleMigrationFailed => '迁移失败';

  @override
  String get activityTitleReceiveFailed => '接收失败';

  @override
  String get activityTitleReceiveInProgress => '接收中...';

  @override
  String get activityTitleReceivedSuccessfully => '接收成功';

  @override
  String get activityTitleReceiving => '接收中...';

  @override
  String get activityTitleReceivingVerb => '接收中';

  @override
  String get activityTitleSendingVerb => '发送中';

  @override
  String get activityTitleSent => '已发送';

  @override
  String get activityTitleShielded => '已屏蔽';

  @override
  String get activityTitleShieldingFailed => '屏蔽失败';

  @override
  String get activityTitleShieldingInProgress => '屏蔽中...';

  @override
  String get activityTitleShieldingVerb => '屏蔽中';

  @override
  String get activityTitleTransaction => '交易';

  @override
  String get activityToastHashCopiedMobile => '交易哈希已复制';

  @override
  String get addressBookAddContact => '添加联系人';

  @override
  String get addressBookAddressHintDesktop => '添加地址';

  @override
  String get addressBookAddressHintMobile => '添加地址';

  @override
  String get addressBookAddressLabel => '地址';

  @override
  String get addressBookAddressMissing => '请添加地址';

  @override
  String get addressBookClearAddress => '清除地址';

  @override
  String get addressBookClearName => '清除名称';

  @override
  String get addressBookClearSearch => '清除搜索';

  @override
  String addressBookContactActions(String label) {
    return '$label 操作';
  }

  @override
  String get addressBookEditContact => '编辑联系人';

  @override
  String get addressBookEmptyBody => '添加你的第一个联系人即可开始。';

  @override
  String get addressBookEmptyTitle => '还没有联系人';

  @override
  String get addressBookInvalidBitcoin => '无效的 Bitcoin 地址';

  @override
  String get addressBookInvalidEvm => '无效的 EVM 地址';

  @override
  String get addressBookInvalidNear => '无效的 NEAR 地址';

  @override
  String get addressBookInvalidSolana => '无效的 Solana 地址';

  @override
  String get addressBookInvalidZcash => '无效的 Zcash 地址';

  @override
  String get addressBookLabelLength => '请使用 1-20 个字符';

  @override
  String get addressBookLabelMissing => '请添加标签';

  @override
  String get addressBookLoadFailed => '无法加载你的联系人。请重试；如果问题持续，请联系支持团队。';

  @override
  String get addressBookNameHint => '添加名称';

  @override
  String get addressBookNameLabel => '名称';

  @override
  String get addressBookNearSuffixWarning => 'NEAR 账户通常以 .near 结尾——请再次核对此地址';

  @override
  String get addressBookNetworkLabel => '网络';

  @override
  String get addressBookNoNetworks => '未找到网络';

  @override
  String get addressBookNoResultsBody => '请尝试修改搜索内容';

  @override
  String get addressBookNoResultsTitle => '未找到联系人';

  @override
  String get addressBookPickerClose => '关闭联系人';

  @override
  String get addressBookPickerEmptyTitle => '未找到联系人';

  @override
  String get addressBookPickerLoadFailed => '无法加载联系人。请重试。';

  @override
  String get addressBookPickerSearchHint => '搜索联系人';

  @override
  String addressBookRemoveBody(String label) {
    return '将从你的联系人中删除 $label。';
  }

  @override
  String get addressBookRemoveBodyUnknown => '将删除此联系人。';

  @override
  String addressBookRemoveConfirmBody(String label) {
    return '将从你的联系人中删除“$label”。这不会影响任何过往交易。';
  }

  @override
  String get addressBookRemoveConfirmTitle => '要删除联系人吗？';

  @override
  String get addressBookRemoveContact => '删除联系人';

  @override
  String get addressBookRemoveFailed => '无法删除联系人。请重试。';

  @override
  String get addressBookRemoveFailedMobile => '无法删除联系人。请重试。';

  @override
  String get addressBookSaveFailed => '无法保存联系人。请重试。';

  @override
  String get addressBookSaveFailedMobile => '无法保存联系人。请重试。';

  @override
  String get addressBookScanAddressQr => '扫描地址二维码';

  @override
  String addressBookScanQrTitle(String network) {
    return '扫描 $network 二维码';
  }

  @override
  String get addressBookSearch => '搜索';

  @override
  String get addressBookSearchHint => '搜索标签或网络';

  @override
  String get addressBookSearchNetwork => '搜索网络';

  @override
  String get addressBookSelectNetwork => '选择网络';

  @override
  String get addressScanAddressCameraNeeded => '扫描地址二维码需要此设备配备摄像头。';

  @override
  String addressScanCameraDefaultSuffix(String name) {
    return '$name（默认）';
  }

  @override
  String get addressScanCameraNeeded => '扫描二维码需要此设备配备摄像头。';

  @override
  String get addressScanCameraOff => '摄像头访问已关闭。请在设置中允许以扫描地址。';

  @override
  String get addressScanCameraRequired => '扫描地址二维码需要此设备配备摄像头。';

  @override
  String get addressScanCameraRestricted => '屏幕使用时间或设备管理正在阻止此设备使用摄像头。';

  @override
  String get addressScanCloseScanner => '关闭扫描器';

  @override
  String get addressScanDeniedTitle => '你已拒绝摄像头访问';

  @override
  String get addressScanGrantAccess => '请授予摄像头访问权限';

  @override
  String get addressScanTitle => '扫描地址二维码';

  @override
  String get addressScanZcashPrompt => '请扫描 Zcash 二维码以继续';

  @override
  String get appBackDonation => '捐赠';

  @override
  String get appBackHardwareWallets => '硬件钱包';

  @override
  String get appBackImportMethods => '导入方式';

  @override
  String get appBackReceive => '接收';

  @override
  String get appBackReview => '确认';

  @override
  String get appBackSend => '发送';

  @override
  String get appBackStatus => '状态';

  @override
  String get appBackSubmitted => '已提交';

  @override
  String get appBackTransaction => '交易';

  @override
  String get appExitBackHint => '再次返回即可退出';

  @override
  String appLinuxUpdateAvailable(String version) {
    return 'Vizor $version 已发布。';
  }

  @override
  String appLinuxUpdateAvailableTor(String version) {
    return 'Vizor $version 已发布。发布页面将在浏览器中打开，不经过 Vizor 的 Tor 连接。';
  }

  @override
  String get appLinuxUpdateOpenInBrowser => '在浏览器中打开';

  @override
  String get appLinuxUpdateViewRelease => '查看发布';

  @override
  String get appOpenFailedTitle => '无法打开 Vizor';

  @override
  String get appPrivacyPolicyTitle => '隐私政策';

  @override
  String get appTermsOfUseTitle => '使用条款';

  @override
  String get appUpdateApplyingMessage => '将在 Vizor 关闭后应用。';

  @override
  String get appUpdateAvailableMessage => '可立即下载，也可继续使用。';

  @override
  String get appUpdateAvailableTitle => '有可用更新';

  @override
  String appUpdateAvailableVersionTitle(String version) {
    return '有可用更新 $version';
  }

  @override
  String get appUpdateDismiss => '关闭';

  @override
  String get appUpdateDownloading => '下载中';

  @override
  String appUpdateDownloadingMessage(int percent) {
    return '已下载 $percent%。';
  }

  @override
  String get appUpdateDownloadingTitle => '正在下载更新';

  @override
  String get appUpdateLater => '稍后';

  @override
  String get appUpdateReadyMessage => '准备好后请重启。';

  @override
  String get appUpdateReadyTitle => '更新已就绪';

  @override
  String get appUpdateRestarting => '重启中';

  @override
  String get appUpdateRestartingTitle => '正在重启 Vizor';

  @override
  String biometricChangedMessage(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID 已更改。请输入数字密码。',
      'touchId': 'Touch ID 已更改。请输入数字密码。',
      'fingerprint': '指纹已更改。请输入数字密码。',
      'other': '生物识别已更改。请输入数字密码。',
    });
    return '$_temp0';
  }

  @override
  String biometricEnableLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': '启用 Face ID',
      'touchId': '启用 Touch ID',
      'fingerprint': '启用指纹',
      'other': '启用生物识别',
    });
    return '$_temp0';
  }

  @override
  String biometricNameInline(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID',
      'touchId': 'Touch ID',
      'fingerprint': '指纹',
      'other': '生物识别',
    });
    return '$_temp0';
  }

  @override
  String biometricNameOnboardingTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID',
      'touchId': 'Touch ID',
      'fingerprint': '指纹',
      'other': '生物识别',
    });
    return '$_temp0';
  }

  @override
  String biometricNameStandalone(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID',
      'touchId': 'Touch ID',
      'fingerprint': '指纹',
      'other': '生物识别',
    });
    return '$_temp0';
  }

  @override
  String biometricSignInLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': '使用 Face ID 登录',
      'touchId': '使用 Touch ID 登录',
      'fingerprint': '使用指纹登录',
      'other': '使用生物识别登录',
    });
    return '$_temp0';
  }

  @override
  String biometricUnlockFeatureInline(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID 解锁',
      'touchId': 'Touch ID 解锁',
      'fingerprint': '指纹解锁',
      'other': '生物识别解锁',
    });
    return '$_temp0';
  }

  @override
  String biometricUnlockFeatureLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': 'Face ID 解锁',
      'touchId': 'Touch ID 解锁',
      'fingerprint': '指纹解锁',
      'other': '生物识别解锁',
    });
    return '$_temp0';
  }

  @override
  String biometricUseNextTimeLabel(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'face': '下次使用 Face ID',
      'touchId': '下次使用 Touch ID',
      'fingerprint': '下次使用指纹',
      'other': '下次使用生物识别',
    });
    return '$_temp0';
  }

  @override
  String get bip39PassphraseTitle => 'BIP39 密码短语';

  @override
  String bip39PassphraseValue(String passphrase) {
    return 'BIP39 密码短语：$passphrase';
  }

  @override
  String get capsLockWarning => '大写锁定已开启';

  @override
  String carouselPageSemantics(
    String name,
    int page,
    int count,
    String message,
  ) {
    return '$name，第 $page 项，共 $count 项。$message';
  }

  @override
  String carouselShowPage(String name, int page, int count) {
    return '显示$name第 $page 项，共 $count 项';
  }

  @override
  String get commonActionNeeded => '需要操作';

  @override
  String get commonAddAMessage => '添加留言';

  @override
  String get commonAddAccount => '添加账户';

  @override
  String get commonAddressCopied => '地址已复制';

  @override
  String commonAddressForChain(String chain) {
    return '$chain 地址';
  }

  @override
  String get commonAddressLabel => '地址标签';

  @override
  String get commonAmount => '金额';

  @override
  String get commonBack => '返回';

  @override
  String commonBackTo(String destination) {
    return '返回$destination';
  }

  @override
  String get commonBackToWallet => '返回钱包';

  @override
  String get commonCalculatingEllipsis => '正在计算…';

  @override
  String get commonCalculatingTotal => '正在计算总数';

  @override
  String get commonCamera => '摄像头';

  @override
  String get commonCameraDeniedTitle => '你已拒绝摄像头访问';

  @override
  String get commonCameraRequestAgainHint => '请重新请求，或在\n系统设置中手动开启。';

  @override
  String get commonCameraRestrictedBody => '屏幕使用时间或设备管理\n正在阻止使用摄像头。';

  @override
  String get commonCameraRestrictedTitle => '摄像头访问受限';

  @override
  String get commonCameraUnavailable => '摄像头不可用';

  @override
  String get commonCameraUnavailableNow => '摄像头目前不可用。';

  @override
  String get commonCancel => '取消';

  @override
  String get commonCancelFailedRetry => '无法完成取消，请重试。';

  @override
  String get commonCancelShielding => '取消屏蔽';

  @override
  String get commonCancellationFailed => '无法完成取消，请重试。';

  @override
  String get commonCancelling => '正在取消…';

  @override
  String get commonCannotBeUndone => '此操作无法撤销。';

  @override
  String get commonCards => '卡片';

  @override
  String get commonChainAndAddress => '链和地址';

  @override
  String get commonChangeContactPicture => '更换联系人头像';

  @override
  String get commonCheckAgain => '重新检查';

  @override
  String get commonChecking => '正在检查...';

  @override
  String get commonCheckingEllipsis => '正在检查…';

  @override
  String get commonCheckingStatus => '正在检查状态';

  @override
  String get commonCheckingYourLedger => '正在检查你的 Ledger';

  @override
  String get commonClear => '清除';

  @override
  String get commonClearContactLabel => '清除联系人标签';

  @override
  String get commonClearText => '清除文本';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCloseMessage => '关闭留言';

  @override
  String get commonCoinholderVoting => '持币者投票';

  @override
  String get commonCompleted => '已完成';

  @override
  String get commonConfirmOpeningZcash => '请确认打开 Zcash';

  @override
  String get commonConfirmWithKeystone => '使用 Keystone 确认';

  @override
  String get commonConfirming => '确认中';

  @override
  String get commonConnectLedger => '连接 Ledger';

  @override
  String get commonConnecting => '正在连接…';

  @override
  String get commonContactLabelHint => '添加 1-20 个字符的标签';

  @override
  String get commonContacts => '联系人';

  @override
  String get commonContinue => '继续';

  @override
  String get commonContinueAnyway => '仍然继续';

  @override
  String get commonContinueToReview => '继续查看';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonCopy => '复制';

  @override
  String get commonCopyAddress => '复制地址';

  @override
  String get commonCopyLink => '复制链接';

  @override
  String get commonCopyShieldedAddress => '复制屏蔽地址';

  @override
  String get commonCouldnTCloseTheCardTry => '无法关闭卡片。请重试。';

  @override
  String get commonCreated => '已创建';

  @override
  String get commonCreating => '创建中…';

  @override
  String get commonCustomiseAccount => '自定义账户';

  @override
  String get commonCustomiseWallet => '自定义钱包';

  @override
  String get commonDefault => '默认';

  @override
  String get commonDefaultCamera => '默认摄像头';

  @override
  String get commonDismissNotification => '关闭通知';

  @override
  String get commonDone => '完成';

  @override
  String get commonDownload => '下载';

  @override
  String get commonDurationOneHour => '1 小时';

  @override
  String get commonDurationOneMinute => '1 分钟';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonEnableWindowsCameraAccess => '请启用 Windows 摄像头访问';

  @override
  String get commonEnterAmount => '输入金额';

  @override
  String commonEnterAmountIn(String currency) {
    return '以 $currency 输入金额';
  }

  @override
  String get commonEnterAmountInUsd => '以 USD 输入金额';

  @override
  String get commonFailed => '失败';

  @override
  String get commonFeatureInProgress => '此功能仍在开发中。';

  @override
  String get commonFullAddress => '完整地址';

  @override
  String get commonGetSignature => '获取签名';

  @override
  String get commonGoBack => '返回';

  @override
  String get commonGoHome => '返回首页';

  @override
  String get commonGuaranteedMinimum => '保证最低金额';

  @override
  String get commonImporting => '正在导入...';

  @override
  String get commonInProgress => '进行中';

  @override
  String get commonInformation => '信息';

  @override
  String get commonJustNow => '刚刚';

  @override
  String get commonKeepQrSteady => '请保持二维码稳定且完整可见。';

  @override
  String get commonKeepScreenAwake => '保持屏幕常亮';

  @override
  String get commonKeepVizorOpenWhileTheTransaction => '交易发送期间请保持 Vizor 打开。';

  @override
  String get commonKeystoneAfterScan => '扫描后，请点击“获取签名”。';

  @override
  String commonKeystoneScanPrompt(String icon) {
    return '在你的 Keystone 上点按 $icon，\n然后扫描此二维码';
  }

  @override
  String get commonKeystoneScanSignatureResult =>
      '请在 Keystone 上打开签名结果二维码，然后重新扫描。';

  @override
  String get commonKeystoneScanTransaction =>
      '请用 Keystone 钱包扫描此交易二维码，并按设备上的步骤操作。';

  @override
  String get commonKeystoneSignatureCouldNotBeApplied => '无法应用 Keystone 签名。';

  @override
  String get commonKeystoneSigningCouldNotBePrepared => '无法准备 Keystone 签名。';

  @override
  String get commonKnight => '骑士';

  @override
  String get commonLedgerNeedsAttention => 'Ledger 需要处理';

  @override
  String get commonLedgerSigningCouldNotBeCompleted =>
      '无法完成 Ledger 签名。请检查设备后重试。';

  @override
  String get commonLedgerSigningFailed => 'Ledger 签名失败';

  @override
  String get commonLoading => '加载中';

  @override
  String get commonLoadingActivity => '正在加载活动';

  @override
  String get commonLoadingCamera => '正在加载摄像头...';

  @override
  String get commonLoadingDots => '正在加载...';

  @override
  String get commonLoadingQRCode => '正在加载二维码 ...';

  @override
  String get commonMakeSureTheRoomIsWell => '请确保房间光线充足，且二维码没有反光。';

  @override
  String get commonManage => '管理';

  @override
  String get commonMemo => '备注';

  @override
  String get commonMessage => '留言';

  @override
  String get commonMessageIsTooLong => '留言太长';

  @override
  String get commonMigrateToIronwood => '迁移到 Ironwood';

  @override
  String get commonMigrating => '正在迁移...';

  @override
  String get commonMigrationStopped => '迁移已停止';

  @override
  String get commonMigrationStoppedByNetworkUpgrade => '迁移因网络升级而停止';

  @override
  String get commonMoveTheQRCodeAFew => '请将二维码移到离摄像头稍远几英寸的位置，以便对焦。';

  @override
  String get commonNetworkConversionFees => '网络 + 兑换手续费';

  @override
  String get commonNetworkFee => '网络手续费';

  @override
  String get commonNextStep => '下一步';

  @override
  String get commonNoActiveAccount => '未选择账户';

  @override
  String get commonNoActiveAccountSentence => '未选择账户。';

  @override
  String get commonNoCameraCouldBeOpenedCheck => '无法打开摄像头。请确认摄像头已连接且未被其他应用占用。';

  @override
  String get commonNoCameraFound => '未找到摄像头';

  @override
  String get commonNotAvailableYet => '暂不可用';

  @override
  String get commonNotEnoughZec => 'ZEC 不足';

  @override
  String get commonOk => '好';

  @override
  String get commonOnAMacYouCanUse => '在 Mac 上，你也可以使用连续互通相机，改用 iPhone 进行扫描。';

  @override
  String get commonOnYourKeystone => 'on your Keystone,';

  @override
  String get commonOpenSettings => '打开设置';

  @override
  String get commonOpenTheSignedTransactionQROn =>
      '请在 Keystone 上打开已签名交易的二维码，然后重新扫描。';

  @override
  String get commonPausedForNetworkUpgrade => '因网络升级已暂停';

  @override
  String get commonPayInsufficientZec => '你的 ZEC 不足以完成此支付。请尝试较小的金额。';

  @override
  String get commonPaymentFailed => '支付失败';

  @override
  String get commonPaymentInProgress => '支付进行中';

  @override
  String get commonPaymentProgress => '支付进度';

  @override
  String get commonPaymentRefunded => '支付已退款';

  @override
  String get commonPaymentRequest => '收款请求';

  @override
  String get commonPending => '待处理';

  @override
  String get commonPleaseWait => '请稍候';

  @override
  String get commonPrepareYourKeystoneWallet => '请准备好你的 Keystone 钱包';

  @override
  String get commonPreparing => '准备中';

  @override
  String get commonPreparingDots => '准备中...';

  @override
  String get commonPreparingEllipsis => '准备中…';

  @override
  String get commonPrivatelyFromShieldedBalance => '从屏蔽余额私密支付';

  @override
  String get commonProvingParamsFailed => '无法准备所需的证明参数。';

  @override
  String get commonQrNoAddress => '二维码中不包含地址。';

  @override
  String get commonQuit => '退出';

  @override
  String get commonRate => '汇率';

  @override
  String get commonReadingSignature => '正在读取签名...';

  @override
  String get commonReadingSignatureEllipsis => '正在读取签名…';

  @override
  String get commonReceived => '已接收';

  @override
  String get commonRecipientGets => '收款方将收到金额';

  @override
  String get commonRefundFee => '退款手续费';

  @override
  String get commonRefundTo => '退款至';

  @override
  String commonRefundToAddress(String address) {
    return '退款地址：$address';
  }

  @override
  String get commonRefunded => '已退款';

  @override
  String get commonRefundedAmount => '退款金额';

  @override
  String get commonRemove => '移除';

  @override
  String get commonRequestAgain => '重新请求';

  @override
  String get commonResetVizor => '重置 Vizor';

  @override
  String get commonResults => '结果';

  @override
  String get commonResume => '继续';

  @override
  String get commonRetry => '重试';

  @override
  String get commonRetrySaving => '重试保存';

  @override
  String get commonReturnHome => '返回首页';

  @override
  String get commonReviewAndFinish => '检查并完成';

  @override
  String get commonReviewPayment => '确认支付';

  @override
  String get commonReviewQuote => '查看报价';

  @override
  String get commonReviewSwap => '查看兑换';

  @override
  String get commonSave => '保存';

  @override
  String get commonSaveContact => '保存联系人';

  @override
  String get commonSaving => '正在保存';

  @override
  String get commonScanAgain => '重新扫描';

  @override
  String get commonScanOriginalQr => '扫描原始二维码';

  @override
  String get commonScanQrCode => '扫描二维码';

  @override
  String get commonScanQrCodeSentenceCase => '扫描二维码';

  @override
  String get commonScanToSign => '扫码签名';

  @override
  String get commonScanWithKeystone => '使用 Keystone 扫描';

  @override
  String get commonScanWithYourKeystone => '使用你的 Keystone 扫描';

  @override
  String get commonSelectAccount => '选择账户';

  @override
  String get commonSelectContactPicture => '选择联系人头像';

  @override
  String get commonSelectRecipient => '选择收款方';

  @override
  String get commonSelectedContact => '已选联系人';

  @override
  String get commonSendFailed => '发送失败';

  @override
  String get commonSendZec => '发送 ZEC';

  @override
  String get commonSending => '发送中...';

  @override
  String get commonSensitiveContentHidden => '敏感内容已隐藏';

  @override
  String get commonSentSuccessfully => '发送成功';

  @override
  String get commonShieldedAddress => '屏蔽地址';

  @override
  String get commonShieldedBalance => '屏蔽余额';

  @override
  String get commonShieldedSuccessfully => '屏蔽成功';

  @override
  String get commonShielding => '屏蔽中...';

  @override
  String get commonShowFullAddress => '显示完整地址';

  @override
  String get commonShowTransactionQR => '显示交易二维码';

  @override
  String get commonSigningCancelledBeforeParams => '在下载证明参数之前，签名已取消。';

  @override
  String get commonSigningExpired => '交易在签名前已过期。';

  @override
  String get commonSlippageTolerance => '滑点容忍度';

  @override
  String get commonStepOneOfTwo => '第 1/2 步';

  @override
  String get commonStepTwoOfTwo => '第 2/2 步';

  @override
  String get commonSubmittingTransaction => '正在提交交易';

  @override
  String get commonSupportVizor => '支持 Vizor';

  @override
  String get commonSwapFailed => '兑换失败';

  @override
  String get commonSwapFee => '兑换手续费';

  @override
  String get commonSwapProgress => '兑换进度';

  @override
  String get commonSwapRefunded => '兑换已退款';

  @override
  String commonSymbolRecipient(String symbol) {
    return '$symbol 收款方';
  }

  @override
  String commonSymbolRefundAddress(String symbol) {
    return '$symbol 退款地址';
  }

  @override
  String get commonSyncing => '正在同步';

  @override
  String get commonTap => 'Tap';

  @override
  String get commonThenScanThisQRCode => 'then scan this QR code';

  @override
  String get commonThisQRCodeCouldNotBe => '无法将此二维码解码为 Keystone 签名。';

  @override
  String get commonThisQRCodeDoesNotMatch => '此二维码与当前 Keystone 请求不匹配。';

  @override
  String get commonTimeSUp => '时间到了';

  @override
  String get commonTimestamp => '时间';

  @override
  String get commonTo => '收款方';

  @override
  String commonToAddressOnChain(String address, String chain) {
    return '至：$address（$chain）';
  }

  @override
  String get commonToggleFlashlight => '切换手电筒';

  @override
  String get commonTotal => '合计';

  @override
  String get commonTransactionExpired => '交易已过期';

  @override
  String get commonTransactionHashCopied => '交易哈希已复制';

  @override
  String get commonTransparentAddress => '透明地址';

  @override
  String get commonTryAgain => '重试';

  @override
  String get commonTurnOnCameraAccessAndLet =>
      '请在 Windows 设置中开启“摄像头访问”和“允许桌面应用访问你的摄像头”。';

  @override
  String get commonTxId => '交易 ID';

  @override
  String get commonUnknown => '未知';

  @override
  String get commonUnlockVizor => '解锁 Vizor';

  @override
  String get commonUpdate => '更改';

  @override
  String get commonUpdateFailed => '更新失败';

  @override
  String get commonUpdating => '正在更改...';

  @override
  String get commonView => '查看';

  @override
  String get commonVizorIsCheckingWhetherTheZcash =>
      'Vizor 正在检查 Zcash 应用是否已就绪。';

  @override
  String get commonVotingRound => '投票轮次';

  @override
  String get commonWaitingForConfirmation => '正在等待确认...';

  @override
  String get commonWaitingForWalletSync => '等待钱包同步';

  @override
  String get commonWelcomeBack => '欢迎回来';

  @override
  String get commonWizard => '巫师';

  @override
  String get commonYouPay => '你支付';

  @override
  String get commonYourePaying => '正在支付金额';

  @override
  String get commonYoureReceiving => '正在接收金额';

  @override
  String get commonZcashAddress => 'Zcash 地址';

  @override
  String get donationDonatingTo => '捐赠对象';

  @override
  String get donationEnterAmount => '输入金额';

  @override
  String get donationPriceUnavailable => '价格不可用';

  @override
  String get donationReviewAmountTitle => '确认金额';

  @override
  String get donationSendingFrom => '发送自';

  @override
  String get donationSendingFromYour => '发送自你的';

  @override
  String get donationSwitchCurrency => '在 ZEC 和 USD 之间切换';

  @override
  String get donationThanksTitle => '感谢你支持 Vizor';

  @override
  String endpointCurrent(String endpoint) {
    return '当前：$endpoint';
  }

  @override
  String get endpointCustom => '自定义节点';

  @override
  String get endpointFailoverSwitchedBack => '所选节点已恢复，已切换回来。';

  @override
  String get endpointFailoverSwitchedToFallback => '所选节点不稳定，已切换到备用节点。';

  @override
  String get endpointLatencyUnavailable => '不可用';

  @override
  String get endpointLatencyWrongNetwork => '网络不匹配';

  @override
  String endpointRegionName(String region) {
    String _temp0 = intl.Intl.selectLogic(region, {
      'standard': '默认',
      'europe': '欧洲',
      'global': '全球',
      'americas': '美洲',
      'asiaPacific': '亚太',
      'community': '社区',
      'testnet': '测试网',
      'regtest': 'Regtest',
      'other': '其他',
    });
    return '$_temp0';
  }

  @override
  String get endpointUpdate => '更新节点';

  @override
  String get endpointUpdated => '节点已更新';

  @override
  String get enhancePirChanging => '正在更改设置…';

  @override
  String get enhancePirOptOutPending => '隐私查询仍处于开启状态。请再次尝试关闭。';

  @override
  String get enhancePirRaisePending => '隐私查询已开启。透明资金的私密恢复暂时无法启动，稍后会重试。';

  @override
  String get enhancePirUnchanged => '设置未更改。请重试。';

  @override
  String get homeActivityEmpty => '暂无活动...';

  @override
  String get homeActivityEmptyHint => '不如发起你的第一笔 ZEC 交易？';

  @override
  String get homeActivityEmptyHintMobile => '不如发起你的\n第一笔 ZEC 交易？';

  @override
  String get homeActivityUnavailable => '无法加载活动。';

  @override
  String get homeBackupSubtitle => '备份你的助记词\n最后一步';

  @override
  String get homeBackupTitle => '保护你的钱包';

  @override
  String get homeDismiss => '关闭';

  @override
  String get homeEducationSubtitle => '隐私、地址类型及注意事项';

  @override
  String get homeEducationTitle => '了解 Zcash';

  @override
  String get homeImportingBodyMobile => '请稍候...这可能需要一些时间。请保持 Vizor 打开并运行。';

  @override
  String get homeImportingDetail => '这可能需要一些时间。\n请保持 Vizor 打开并运行。';

  @override
  String homeImportingDetailNamed(String name) {
    return '正在导入 $name\n请保持 Vizor 打开并运行。';
  }

  @override
  String get homeImportingTitle => '正在导入\n你的钱包...';

  @override
  String get homeImportingTitleMobile => '正在导入你的钱包...';

  @override
  String get homeKeepAwakeBody => '屏幕关闭时，手机会暂停同步。保持常亮可让同步更快完成。';

  @override
  String get homeKeepAwakeLater => '以后再说';

  @override
  String get homeKeepAwakeLockNote => '1 分钟无操作后应用会锁定，同步仍会在锁定状态下继续。';

  @override
  String get homeKeepAwakeSettingsNote => '你可以随时在设置中更改。';

  @override
  String get homeKeepAwakeTitle => '同步时保持屏幕常亮？';

  @override
  String get homeLedgerApprovalNotAccepted => '你的 Ledger 无法接受此次批准。之前的批准已发送。';

  @override
  String get homeLedgerBroadcastNotStored => '屏蔽交易已到达网络，但未保存在本地。在同步确认之前，请勿重试。';

  @override
  String get homeLedgerBroadcastUnknown => '屏蔽交易可能已到达网络。重试前请先查看活动。';

  @override
  String get homeLedgerContextChanged => '所选账户或网络已更改。请返回钱包。';

  @override
  String get homeLedgerInputsRemaining => '仍有剩余输入';

  @override
  String get homeLedgerNoFundsRemain => '没有可花费的透明资金。请返回钱包。';

  @override
  String get homeLedgerNoSapling => '此 Ledger 预览版不支持 Sapling 输入或输出。';

  @override
  String get homeLedgerPausedBelowThreshold => '剩余资金低于屏蔽门槛。';

  @override
  String get homeLedgerPausedTitle => '屏蔽已暂停';

  @override
  String get homeLedgerPausedWalletChanges => '钱包更改完成期间，屏蔽已暂停。请返回钱包。';

  @override
  String get homeLedgerRejected => '屏蔽交易已在你的 Ledger 上被拒绝。';

  @override
  String get homeLedgerRoundFeeNotice => '每次批准都会创建一笔单独的交易，并各自产生网络手续费。';

  @override
  String homeLedgerRoundSentBelowThreshold(int round) {
    return '第 $round 轮已发送。剩余资金低于屏蔽门槛。';
  }

  @override
  String homeLedgerRoundSentNoReduction(int round) {
    return '第 $round 轮已发送，但无法确认可花费输入是否减少。请等待同步完成后再次屏蔽。';
  }

  @override
  String homeLedgerRoundSentUnchecked(int round) {
    return '第 $round 轮已发送，但无法检查剩余资金。请返回钱包，同步后重试。';
  }

  @override
  String get homeLedgerShieldTitle => '使用 Ledger 屏蔽';

  @override
  String get homeLedgerShieldingFailed => '无法使用 Ledger 完成屏蔽。';

  @override
  String homeLoadFailed(String details) {
    return '出了点问题，请稍后重试。\n\n详情：$details';
  }

  @override
  String get homeMigrationRequired => '需要迁移';

  @override
  String get homeMigrationRequiredTitle => '需要迁移';

  @override
  String homeMigrationStillMigrating(String amount) {
    return '$amount 仍在迁移';
  }

  @override
  String get homeNu7FasterBody => '首次确认的平均等待时间从约 75 秒缩短到约 25 秒。';

  @override
  String get homeNu7FasterTitle => '区块速度提升约 3×';

  @override
  String get homeNu7GotIt => '知道了';

  @override
  String get homeNu7ThroughputBody => '网络每个区块可处理的屏蔽交易数量提升至 2.3 倍。';

  @override
  String get homeNu7ThroughputTitle => '屏蔽交易吞吐量提高';

  @override
  String get homeNu7Title => 'NU7 升级已上线。\n这意味着什么？';

  @override
  String get homePasswordChangeUnverified => '无法确认之前的密码更改。请重试或重新启动 Vizor。';

  @override
  String get homePayInUsdc => '使用 USDC 支付';

  @override
  String get homeReceive => '接收';

  @override
  String get homeReceiveFirstZec => '接收你的第一笔 ZEC';

  @override
  String get homeRecentActivity => '最近活动';

  @override
  String get homeSeeAll => '查看全部';

  @override
  String get homeSend => '发送';

  @override
  String get homeSetupBackupMessage => '请备份你的钱包，并妥善保管助记词。';

  @override
  String get homeSetupCarouselLabel => '钱包初始设置';

  @override
  String get homeSetupCarouselName => '钱包初始设置横幅';

  @override
  String get homeSetupEducationMessage => '了解 Zcash 如何保护你的隐私，以及该使用哪种地址。';

  @override
  String get homeShield => '屏蔽';

  @override
  String get homeShieldAfterScan => '扫描后，请点击“获取签名”。';

  @override
  String get homeShieldApproveTitle => '在 Keystone 上批准';

  @override
  String get homeShieldAttentionTitle => '屏蔽需要处理';

  @override
  String get homeShieldBackToWalletTitleCase => '返回钱包';

  @override
  String get homeShieldBalanceTitle => '透明余额';

  @override
  String get homeShieldBroadcastNotStored =>
      '屏蔽交易已到达网络，但 Vizor 无法将其保存在本地。在同步或区块浏览器确认最新状态之前，请勿重试。';

  @override
  String get homeShieldBroadcastUnknown => '屏蔽交易可能已到达网络，但确认超时。重试前请先查看活动。';

  @override
  String get homeShieldBroadcastingTitle => '正在广播屏蔽交易';

  @override
  String get homeShieldCameraDenied => '请在设置中允许访问相机，以扫描 Keystone 签名。';

  @override
  String get homeShieldCancelled => '屏蔽已取消。';

  @override
  String get homeShieldCancelledBeforeParams => '在下载证明参数之前，屏蔽已取消。';

  @override
  String get homeShieldComplete => '完成';

  @override
  String get homeShieldDrag => '拖动以屏蔽';

  @override
  String get homeShieldErrorBroadcast => '无法广播屏蔽交易。';

  @override
  String get homeShieldErrorBroadcastFailed => '无法广播你的屏蔽交易。请重试。';

  @override
  String get homeShieldErrorCouldNotShield => '无法屏蔽你的余额。请重试。';

  @override
  String get homeShieldErrorGeneric => '屏蔽余额失败，请重试。';

  @override
  String get homeShieldErrorNotFinalized => '无法完成屏蔽交易。';

  @override
  String get homeShieldErrorSeedUnavailable => '此账户的助记词不可用。';

  @override
  String get homeShieldErrorSyncFirst => '屏蔽透明余额之前，请先同步钱包。';

  @override
  String get homeShieldErrorTooSmall => '扣除手续费后，透明余额太少，无法屏蔽。';

  @override
  String get homeShieldErrorWaitForSync => '请等待同步完成后再屏蔽。';

  @override
  String get homeShieldFailedTitle => '无法完成屏蔽';

  @override
  String get homeShieldGetSignature => '获取签名';

  @override
  String get homeShieldKeystoneQrSemantics => 'Keystone 交易二维码';

  @override
  String get homeShieldNow => '立即屏蔽';

  @override
  String get homeShieldQueuedForRetry => '屏蔽已排队等待重试。请查看活动。';

  @override
  String get homeShieldQueuedTitle => '屏蔽已加入队列';

  @override
  String get homeShieldReject => '拒绝';

  @override
  String get homeShieldScanTitle => '扫描 Keystone 签名';

  @override
  String get homeShieldScanToSign => '扫描二维码进行签名';

  @override
  String get homeShieldScanWrongQr => '请在 Keystone 上打开已签名的屏蔽二维码，然后重新扫描。';

  @override
  String homeShieldScanning(int progress) {
    return '正在扫描… $progress%';
  }

  @override
  String get homeShieldShowQr => '显示二维码';

  @override
  String get homeShieldSignTitle => '在 Keystone 上签名交易';

  @override
  String get homeShieldStatusUncertain => '屏蔽交易的状态不确定。重试前请先查看活动。';

  @override
  String get homeShieldWaitingForPrivateRecovery =>
      '私密恢复正在追赶最新区块。请稍后重试；你的 Keystone 签名已保留。';

  @override
  String get homeShieldingBalance => '正在屏蔽你的余额…';

  @override
  String homeTransparentBalance(String balance) {
    return '透明：$balance';
  }

  @override
  String homeTransparentLastKnown(String amount) {
    return '$amount（上次已知）';
  }

  @override
  String homeTransparentLastKnownStopped(String amount) {
    return '$amount（上次已知，恢复已停止）';
  }

  @override
  String get homeTransparentRecoveryStopped => '恢复已停止';

  @override
  String get homeTransparentStopLegacyDiscrepancy =>
      '之前的公开记录与私密恢复结果不一致。关闭隐私查询会丢弃私密恢复的记录，并公开查询透明资金。';

  @override
  String get homeTransparentStopOptOutUnfinished =>
      '关闭隐私查询未完成。请在设置中再次关闭，以公开查询透明资金。';

  @override
  String get homeTransparentStopQuarantined =>
      '私密恢复发现此账户的记录相互冲突。关闭隐私查询会丢弃私密恢复的记录，并公开查询透明资金。';

  @override
  String get homeTransparentStopStalled => '此账户的私密恢复无法继续。Vizor 稍后会重试。';

  @override
  String get homeTransparentStopWithdrawn => '私密恢复服务撤回了此账户的数据。Vizor 稍后会重试。';

  @override
  String get homeTransparentUnavailable => '不可用';

  @override
  String get homeVotingSemantics => '打开持币者投票';

  @override
  String get homeVotingSubtitle => '参与塑造网络未来';

  @override
  String get incomingLinkGiftBusy => '请先完成或取消当前操作，再打开此礼品卡。';

  @override
  String get incomingLinkGiftSetup => '请先完成账户设置，再打开此礼品卡。';

  @override
  String get incomingLinkHomeBusy => '请先完成或取消当前操作，然后重新打开链接。';

  @override
  String get incomingLinkHomeSetup => '请先完成账户设置，然后重新打开链接。';

  @override
  String get incomingLinkPaymentBusy => '请先完成或取消当前操作，再打开此收款请求。';

  @override
  String get keyringLockedBody =>
      'Vizor 无法访问系统密钥环。请解锁密钥环，然后选择“重试”。系统可能会要求输入密钥环密码。';

  @override
  String get keyringNoResponse => '密钥环没有响应。请重试。';

  @override
  String get keyringOpeningTitle => '正在打开 Vizor';

  @override
  String get keyringPromptBody => '请完成系统密钥环提示以继续使用 Vizor。';

  @override
  String get keyringRestartHint => '请退出并重新启动 Vizor 后重试。';

  @override
  String get keyringSaveUnconfirmedBody =>
      'Vizor 无法确认你的更改是否已保存。请先退出并重新启动 Vizor 再继续。';

  @override
  String get keyringSaveUnconfirmedTitle => '无法确认保存';

  @override
  String get keyringTryingTitle => '正在尝试访问安全存储';

  @override
  String get keyringUnavailableBody => 'Vizor 无法连接到系统密钥环。请重试，或退出并重新启动 Vizor。';

  @override
  String get keyringUnavailableTitle => '安全存储不可用';

  @override
  String get keyringUnlockTitle => '请解锁密钥环';

  @override
  String get keyringUnreadableBody =>
      'Vizor 无法读取系统密钥环中的数据。请在恢复访问后重试，或退出 Vizor。';

  @override
  String get keyringUnreadableTitle => '无法读取安全存储';

  @override
  String keystoneAccountsFound(int count) {
    return '找到 $count 个账户';
  }

  @override
  String get keystoneAllowCamera => '允许使用摄像头';

  @override
  String get keystoneBatchCannotSignDeposit => '此笔存入包含 Keystone 批量签名无法签署的输入。';

  @override
  String get keystoneBatchCannotSignTx => '此交易包含 Keystone 批量签名无法签署的输入。';

  @override
  String get keystoneBatchTooManyInputsDeposit =>
      '此笔存入的输入过多，超出 Keystone 批量签名的上限。请尝试较小的金额。';

  @override
  String get keystoneBatchTooManyInputsTx =>
      '此交易的输入过多，超出 Keystone 批量签名的上限。请尝试较小的金额。';

  @override
  String get keystoneBirthdayInvalidHeight => '这似乎不是有效的区块高度。';

  @override
  String get keystoneBirthdaySubtitle => '这有助于我们更快地导入你的钱包。';

  @override
  String get keystoneCameraDeniedTitle => '你已拒绝摄像头权限';

  @override
  String get keystoneCameraEnableBody => '连接 Keystone 需要使用相机。\n你之后可随时在设置中更改。';

  @override
  String get keystoneCameraEnableTitle => '启用相机权限';

  @override
  String get keystoneCameraExternal => '外接';

  @override
  String get keystoneCameraFront => '前置';

  @override
  String get keystoneCameraGiftBody => '扫描礼品卡二维码需要使用摄像头。\n你之后可以随时在设置中更改。';

  @override
  String keystoneCameraNameDefault(String name) {
    return '$name（默认）';
  }

  @override
  String get keystoneCameraNormal => '标准';

  @override
  String get keystoneCameraOffAllow => '摄像头权限已关闭。请在设置中允许，以扫描 Keystone 签名。';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone 导入仅支持摄像头扫描二维码。\n请连接摄像头后重试。';

  @override
  String get keystoneCameraWide => '广角';

  @override
  String get keystoneCameraZoom => '变焦';

  @override
  String get keystoneConfirmSelection => '确认选择';

  @override
  String get keystoneFirmwareBody => '请确认你的 Keystone 已升级到最新的 Cypherpunk 固件。 ';

  @override
  String get keystoneFirmwareDownloadSemantics => '下载 Keystone 固件';

  @override
  String get keystoneFirmwareLinkLabel => '链接';

  @override
  String get keystoneFirmwareOpenPage => '打开 Keystone 固件页面';

  @override
  String get keystoneFirmwareTitle => '检查 Keystone 固件';

  @override
  String keystoneFirmwareUpdate(String link) {
    return '请更新到最新的 Keystone 固件：$link';
  }

  @override
  String get keystoneFirmwareUpdatePrefix =>
      'Update to the latest Keystone firmware at ';

  @override
  String get keystoneImReadyNow => '我已准备好';

  @override
  String get keystoneOnVizor => '在 Vizor 中';

  @override
  String get keystoneOnYourKeystone => '在 Keystone 上';

  @override
  String get keystonePrepareToConnectTitle => '准备连接';

  @override
  String get keystonePreparingQr => '正在准备二维码';

  @override
  String get keystoneReadingQr => '正在读取二维码...';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone 导入仅支持使用摄像头扫描二维码。请连接摄像头后重试。';

  @override
  String get keystoneScanCaption => '扫描 Keystone 账户二维码';

  @override
  String get keystoneScanCaptionConfirm => '请扫描 Keystone 上的二维码以确认';

  @override
  String get keystoneScanDecodeFailed => '无法将此二维码解码为 Keystone Zcash 账户。';

  @override
  String get keystoneScanHelpClose => '关闭扫描帮助';

  @override
  String get keystoneScanIssuesTitle => '扫描有问题？';

  @override
  String get keystoneScanNoAccounts => '在此 Keystone 二维码中未找到 Zcash 账户。';

  @override
  String get keystoneScanOpenAccountQr => '请在 Keystone 上打开 Zcash 账户二维码，然后重新扫描。';

  @override
  String keystoneScanProgress(int progress) {
    return '正在扫描... $progress%';
  }

  @override
  String get keystoneScanReadingAccounts => '正在读取账户...';

  @override
  String get keystoneSelectCamera => '选择摄像头';

  @override
  String get keystoneStepHowToConnect => '连接方法';

  @override
  String get keystoneStepOpenSoftwareWallet =>
      '点击右上角的 •••，然后选择 Connect software wallet。';

  @override
  String get keystoneStepScanDynamicQr => '扫描 Keystone 上显示的动态二维码。';

  @override
  String get keystoneStepSelectAccount => '选择账户';

  @override
  String get keystoneStepSelectVizor => '选择 Vizor（或 ZODL）';

  @override
  String get keystoneSubmittingTransaction => '正在提交交易';

  @override
  String get keystoneTipGiftFullScreen => '请在另一台设备上全屏打开礼品卡二维码。';

  @override
  String get keystoneTipMoveKeystoneFurther =>
      '请将 Keystone 移到离摄像头稍远几英寸的位置，以便对焦。';

  @override
  String get keystoneTipTapFullScreen => '点按 Keystone 上的二维码即可全屏显示。这是最简单的解决办法。';

  @override
  String get keystoneTroubleScanning => '扫描遇到问题？';

  @override
  String get keystoneTryAgainWithKeystone => '使用 Keystone 重试';

  @override
  String languageSystemOption(String language) {
    return '系统（$language）';
  }

  @override
  String get ledgerAccountIndexFieldLabel => 'Ledger 账户索引（0–100）';

  @override
  String get ledgerAccountIndexHint => '除非此 Ledger 账户使用过其他索引，否则请保持为 0。';

  @override
  String get ledgerAccountIndexLabel => '账户索引（0–100）';

  @override
  String get ledgerAccountIndexOutOfRange => '账户索引必须在 0 到 100 之间。';

  @override
  String get ledgerAddAccountNote => '你可在 Vizor 中查看余额和活动。交易仍需在 Ledger 上批准。';

  @override
  String get ledgerAddAccountTitle => '添加 Ledger 账户';

  @override
  String get ledgerAdvancedOptions => '高级选项';

  @override
  String ledgerAppSemanticsLabel(String appName) {
    return '$appName 应用';
  }

  @override
  String get ledgerAppUpdateRequiredTitle => '需要更新 Ledger 应用';

  @override
  String get ledgerApproveShareViewingKey => '请批准与 Vizor 共享你的查看密钥。';

  @override
  String ledgerApproveShareViewingKeyForAccount(String number) {
    return '请批准共享账户 #$number 的查看密钥。';
  }

  @override
  String get ledgerBalanceActivityNote => '在 Vizor 中查看余额和活动。\n在 Ledger 上批准交易。';

  @override
  String get ledgerBleDeclinedOpen => '你在 Ledger 上拒绝了打开 Zcash。准备好后请重试。';

  @override
  String get ledgerBleDeclinedShare => '你在 Ledger 上拒绝了共享。准备好后请重试。';

  @override
  String get ledgerBleReadFailedTryAgain => 'Vizor 无法读取此 Ledger 账户。请重试。';

  @override
  String get ledgerBleReadFailedUsb =>
      'Vizor 无法读取此 Ledger 账户。请用 USB 数据线重新连接 Ledger，使用 PIN 码解锁，并打开 Zcash 应用，然后重试。';

  @override
  String get ledgerBluetoothConnection => '蓝牙连接';

  @override
  String get ledgerBluetoothModelsList => 'Nano X、Flex、Stax 和 Nano Gen5';

  @override
  String get ledgerBluetoothPermissionRequired =>
      '查找 Ledger 需要蓝牙权限。请在设置中允许，然后重试。';

  @override
  String get ledgerBtAccessAllowed => '权限已允许。准备好后请重试。';

  @override
  String get ledgerBtAccessBluetoothRequestable =>
      '请选择“允许权限”以连接 Ledger。如果没有弹出提示，请打开设置。';

  @override
  String get ledgerBtAccessBluetoothSettings => '请在设备设置中允许 Vizor 使用蓝牙。';

  @override
  String get ledgerBtAccessKindLocation => '定位';

  @override
  String get ledgerBtAccessLocationRequestable =>
      '此 Android 版本需要定位权限才能查找 Ledger。请选择“允许权限”，如果没有弹出提示，请打开设置。';

  @override
  String get ledgerBtAccessLocationSettings =>
      '此 Android 版本需要定位权限才能查找 Ledger。请在设置中允许 Vizor 访问定位。';

  @override
  String get ledgerBtAccessMacosSettings =>
      '请打开“系统设置”>“隐私与安全性”>“蓝牙”，并允许 Vizor 访问。';

  @override
  String ledgerBtAccessRestricted(String kind) {
    return '$kind权限受到设备设置或管理员限制。';
  }

  @override
  String get ledgerBtAccessTurnOnBluetooth => '请开启蓝牙，然后再次检查权限。';

  @override
  String get ledgerBtAccessTurnOnLocation => '请开启定位服务，然后再次检查权限。';

  @override
  String get ledgerBtCouldNotCheckAccess => '无法检查权限。请手动打开设置，然后再次检查。';

  @override
  String get ledgerBtCouldNotOpenSettingsAllow =>
      '无法打开设置。请手动打开设备设置并允许 Vizor 访问。';

  @override
  String get ledgerBtCouldNotOpenSettingsRestricted =>
      '无法打开设置。请手动打开设备设置，查看 Vizor 的权限。';

  @override
  String get ledgerBtLabelAllowAccess => '允许访问';

  @override
  String get ledgerBtLabelChecking => '正在检查权限';

  @override
  String get ledgerBtLabelReconnect => '重新连接';

  @override
  String get ledgerBtMsgBluetoothNeeded => 'Vizor 需要蓝牙权限才能连接你的 Ledger。';

  @override
  String get ledgerBtMsgChecking => '正在检查 Vizor 能否连接你的 Ledger。';

  @override
  String get ledgerBtMsgLocationNeeded => '此 Android 版本需要定位权限才能查找 Ledger。';

  @override
  String get ledgerBtMsgReady => '请开启并解锁 Ledger 以继续。';

  @override
  String get ledgerBtRestrictedGeneric =>
      '请在设置中查看 Vizor 的蓝牙权限。设备限制或管理员可能会阻止更改。';

  @override
  String get ledgerBtRestrictedLocation =>
      '请在设置中查看 Vizor 的定位权限。设备限制或管理员可能会阻止更改。';

  @override
  String get ledgerBtRestrictedMacos =>
      '请在“系统设置”中查看“隐私与安全性”>“蓝牙”。此限制可能需要由管理员更改。';

  @override
  String get ledgerBtRestrictedNearby =>
      '请在设置中查看 Vizor 的“附近设备”权限。设备限制或管理员可能会阻止更改。';

  @override
  String get ledgerBtSheetAllowAddAccount => '请在手机设置中允许 Vizor 使用蓝牙以添加你的账户。';

  @override
  String get ledgerBtSheetAllowContinue => '请在手机设置中允许 Vizor 使用蓝牙以继续。';

  @override
  String get ledgerBtSheetAllowSigning => '请在手机设置中允许 Vizor 使用蓝牙以继续签名。';

  @override
  String get ledgerBtSheetReadyAddAccount => '蓝牙可用。请解锁 Ledger 以添加你的账户。';

  @override
  String get ledgerBtSheetReadyContinue => '蓝牙可用。请解锁 Ledger 以继续。';

  @override
  String get ledgerBtSheetReadySigning => '蓝牙可用。请解锁 Ledger 以继续签名。';

  @override
  String get ledgerBtSheetTurnOnAddAccount => '请开启手机蓝牙以添加你的账户。';

  @override
  String get ledgerBtSheetTurnOnContinue => '请开启手机蓝牙以继续。';

  @override
  String get ledgerBtSheetTurnOnSigning => '请开启手机蓝牙以继续签名。';

  @override
  String get ledgerBtTitleAllowBluetooth => '请允许使用蓝牙';

  @override
  String get ledgerBtTitleAllowBluetoothSettings => '请在设置中允许蓝牙';

  @override
  String get ledgerBtTitleAllowLocation => '请允许访问定位';

  @override
  String get ledgerBtTitleAllowLocationSettings => '请在设置中允许定位';

  @override
  String get ledgerBtTitleChecking => '正在检查蓝牙权限';

  @override
  String get ledgerBtTitleReady => '可以重新连接';

  @override
  String get ledgerBtTitleRestricted => '权限受到限制';

  @override
  String get ledgerBtTitleTurnOnBluetooth => '请开启蓝牙';

  @override
  String get ledgerBtTitleTurnOnLocation => '请开启定位服务';

  @override
  String get ledgerButtonCheckingAccount => '正在检查账户';

  @override
  String get ledgerButtonConnecting => '正在连接';

  @override
  String get ledgerButtonSearching => '正在搜索';

  @override
  String get ledgerCancelFailed => '无法完成取消。请重试。';

  @override
  String get ledgerCancellingRequest => '正在取消请求';

  @override
  String get ledgerCancellingTheRequest => '正在取消 Ledger 请求…';

  @override
  String get ledgerCapabilityMainnetOnly => '目前仅支持在 Zcash 主网上使用 Ledger。';

  @override
  String get ledgerCapabilityUnsupportedPlatform =>
      'Vizor 支持在 macOS、Windows、Linux、iOS 和 Android 上使用 Ledger。';

  @override
  String get ledgerChangedKeepOne => 'Ledger 已更换。请只连接一个 Ledger，然后重试。';

  @override
  String get ledgerCheckingBluetoothAccess => '正在检查蓝牙权限…';

  @override
  String get ledgerCheckingUsb => '正在检查 USB 连接…';

  @override
  String get ledgerChooseAnother => '选择其他 Ledger';

  @override
  String get ledgerChooseConnection => '选择连接方式';

  @override
  String get ledgerChooseDevice => '请选择一台设备以继续。';

  @override
  String get ledgerChooseLedgerForAccount => '请选择要用于此账户的 Ledger。';

  @override
  String get ledgerCleanupFailed => '无法完成清理。请重试。';

  @override
  String get ledgerComeBackFindLedger =>
      '请保持 Ledger 处于解锁状态，然后选择下方的“查找 Ledger”。';

  @override
  String get ledgerComeBackFindMyLedger =>
      '请保持 Ledger 处于解锁状态，然后选择下方的“查找我的 Ledger”。';

  @override
  String get ledgerComeBackReconnect => '返回并重新连接';

  @override
  String get ledgerCompletePairingOpenZcash =>
      '如有提示请完成配对，然后打开 Zcash 应用并批准共享查看密钥。';

  @override
  String get ledgerConfirmOpeningZcash => '请在 Ledger 上确认打开 Zcash。';

  @override
  String get ledgerConnectForAccount => '请连接此账户的 Ledger。';

  @override
  String get ledgerConnectSubtitle => '请准备好你的 Ledger 钱包。';

  @override
  String get ledgerConnectUsbCable => '使用 USB 数据线连接。';

  @override
  String ledgerConnectingTo(String device) {
    return '正在连接 $device';
  }

  @override
  String get ledgerConnectionHelp => '连接帮助';

  @override
  String get ledgerConnectionRequiredBluetooth => '请开启并解锁你的 Ledger，然后通过蓝牙重新连接。';

  @override
  String get ledgerConnectionRequiredUsb => '请通过 USB 连接并解锁你的 Ledger，然后重试。';

  @override
  String get ledgerContinueSigning => '继续签名';

  @override
  String get ledgerCouldNotConnect => '无法连接 Ledger';

  @override
  String get ledgerCouldNotStopSearchTryAgain => '无法停止搜索。请重试。';

  @override
  String get ledgerDifferentFromSaved => '与已保存的连接不同';

  @override
  String get ledgerDiscoveryErrorFallback => '请重试。';

  @override
  String get ledgerDiscoveryErrorTitle => '无法连接到你的 Ledger';

  @override
  String get ledgerDiscoveryFailed => 'Vizor 未能找到 Ledger 设备。请重试。';

  @override
  String get ledgerEnableBluetoothNearby => '开启蓝牙，并将 Ledger 放在附近。';

  @override
  String get ledgerErrorAlreadyAdded => '此 Ledger 账户已在 Vizor 中。';

  @override
  String get ledgerErrorCannotReadCheckConnection =>
      'Vizor 无法读取此 Ledger 账户。请检查连接后重试。';

  @override
  String ledgerErrorCannotReadWithInstruction(String instruction) {
    return 'Vizor 无法读取此 Ledger 账户。$instruction然后请重试。';
  }

  @override
  String ledgerErrorConnectAndUnlock(String instruction) {
    return '请连接并解锁你的 Ledger。$instruction';
  }

  @override
  String ledgerErrorUnlock(String instruction) {
    return '请解锁你的 Ledger。$instruction';
  }

  @override
  String get ledgerErrorViewingKeyDeclined => '你在 Ledger 上拒绝了查看密钥请求。准备好后请重试。';

  @override
  String get ledgerErrorViewingKeyRejected => '你在 Ledger 上拒绝了查看密钥请求。';

  @override
  String ledgerFailureMsgAppUpdateRequired(String version) {
    return '请在 Ledger Wallet 中将你的 Ledger 及其 Zcash 应用更新到 $version 或更高版本。';
  }

  @override
  String get ledgerFailureMsgBusy => 'Ledger 正忙。请稍后重试。';

  @override
  String get ledgerFailureMsgCancelledTryAgain => '请求已取消。准备好后请重试。';

  @override
  String get ledgerFailureMsgCheckOpenZcash => '请检查 Ledger 并打开 Zcash 应用，然后重试。';

  @override
  String get ledgerFailureMsgDeclined => '已在 Ledger 上拒绝。准备好后请重试。';

  @override
  String get ledgerFailureMsgGiftCardRejected =>
      'Ledger 无法接受此请求。请创建新的礼品卡。未发送任何内容。';

  @override
  String get ledgerFailureMsgGiftCardTooLarge => '对 Ledger 来说过大。请创建金额较小的礼品卡。';

  @override
  String get ledgerFailureMsgInstallZcash => '请使用 Ledger Wallet 安装 Zcash 应用。';

  @override
  String get ledgerFailureMsgMemoHashUnsupported =>
      '请更新 Ledger 的 Zcash 应用以签署非英文备注';

  @override
  String get ledgerFailureMsgMigrationTooLarge =>
      '此迁移步骤过大，Ledger 无法签名。Vizor 暂时无法拆分。';

  @override
  String get ledgerFailureMsgOpenZcash => '请在 Ledger 上打开 Zcash 应用。';

  @override
  String get ledgerFailureMsgOrchardChange =>
      'Ledger 无法签署在 Orchard 中保留找零的交易。请先将你的 Orchard 余额迁移到 Ironwood。';

  @override
  String get ledgerFailureMsgPaymentTooLarge => '请发起新的支付。不要向此地址发送较小的金额。';

  @override
  String get ledgerFailureMsgReconnectUnlock => '请重新连接并解锁 Ledger。';

  @override
  String get ledgerFailureMsgRejectedNewRequest =>
      'Ledger 无法接受此请求。请重新创建。未发送任何内容。';

  @override
  String get ledgerFailureMsgReopenZcash => '请关闭并重新打开 Zcash 应用。';

  @override
  String get ledgerFailureMsgSaplingRecipient =>
      'Ledger 无法向 Sapling 地址发送。请创建新请求。';

  @override
  String get ledgerFailureMsgSetPin => '请在 Ledger 上设置 PIN，然后重试。';

  @override
  String get ledgerFailureMsgShieldTooLarge => '输入过多，Ledger 无法处理。请重试。未屏蔽任何资金。';

  @override
  String get ledgerFailureMsgSwapTooLarge => '请用较小的金额发起新的兑换。此次兑换已作废。';

  @override
  String get ledgerFailureMsgTooManyInputs => '输入过多，Ledger 无法处理。请尝试较小的金额。';

  @override
  String get ledgerFailureMsgUnexpected => 'Ledger 出现意外错误。请重新打开 Zcash 应用后重试。';

  @override
  String ledgerFailureMsgUnexpectedWithCode(String code) {
    return 'Ledger 出现意外错误$code。请重新打开 Zcash 应用后重试。';
  }

  @override
  String get ledgerFailureMsgUnlock => '请解锁 Ledger，然后重试。';

  @override
  String get ledgerFailureMsgUnsupportedTxType => 'Ledger 无法签署此类交易。请创建新请求。';

  @override
  String ledgerFailureMsgUpdateZcash(String version) {
    return '请将 Zcash 应用更新到 $version 或更高版本。';
  }

  @override
  String get ledgerFailureMsgViewingKeyRejected =>
      'Ledger 无法接受此查看密钥请求。请检查账户编号。';

  @override
  String get ledgerFailureMsgVoteRejected => 'Ledger 无法接受此投票请求。你的投票未被签名。';

  @override
  String get ledgerFailureMsgVoteTooLarge => '此投票过大，Ledger 无法签名。';

  @override
  String get ledgerFailureMsgWrongLedger => '请连接保存此账户的 Ledger。';

  @override
  String get ledgerFailureTitleBusy => 'Ledger 正忙';

  @override
  String get ledgerFailureTitleCancelled => '请求已取消';

  @override
  String get ledgerFailureTitleError => 'Ledger 错误';

  @override
  String get ledgerFailureTitleFailed => '请求失败';

  @override
  String get ledgerFailureTitleLocked => 'Ledger 已锁定';

  @override
  String get ledgerFailureTitleNotReachable => '无法连接 Ledger';

  @override
  String get ledgerFailureTitleOpenZcash => '请打开 Zcash 应用';

  @override
  String get ledgerFailureTitlePinRequired => '需要 PIN';

  @override
  String get ledgerFailureTitleRejected => '请求未被接受';

  @override
  String get ledgerFailureTitleReopenZcash => '请重新打开 Zcash 应用';

  @override
  String get ledgerFailureTitleTooLarge => '请求过大';

  @override
  String get ledgerFailureTitleUpdateZcash => '请更新 Zcash 应用';

  @override
  String get ledgerFailureTitleWrongLedger => 'Ledger 不匹配';

  @override
  String get ledgerFailureTitleZcashMissing => '缺少 Zcash 应用';

  @override
  String get ledgerFind => '查找 Ledger';

  @override
  String get ledgerFindMyLedger => '查找我的 Ledger';

  @override
  String get ledgerFollowPromptsOnLedger => '请按照 Ledger 上的提示操作。';

  @override
  String get ledgerHelpChecksCloseOtherApps =>
      '请关闭其他钱包应用，并断开 Ledger 与其他手机或电脑的连接。';

  @override
  String get ledgerHelpChecksHomeScreen =>
      '请让 Ledger 停留在主屏幕。Vizor 提示时再打开 Zcash 应用。';

  @override
  String get ledgerHelpChecksUnlockClose => '请解锁 Ledger，开启蓝牙，并将其放在手机附近。';

  @override
  String get ledgerHelpChooseModel => '请选择你的型号';

  @override
  String get ledgerHelpFindInPhoneBluetooth => '请在手机的蓝牙设置中找到你的 Ledger。';

  @override
  String get ledgerHelpForgetAndroid => '蓝牙设置 > Ledger 旁边的设置按钮 > 忽略或取消配对';

  @override
  String get ledgerHelpForgetIos => '设置 > 蓝牙 > Ledger 旁边的信息按钮 > 忽略此设备';

  @override
  String get ledgerHelpKeepUnlockedHome => '请保持 Ledger 解锁并开启蓝牙，让它停留在主屏幕。';

  @override
  String get ledgerHelpModelLabel => 'Ledger 型号';

  @override
  String get ledgerHelpNanoXConfirm => '请在 Ledger 上确认，并在设备上输入你的 PIN。';

  @override
  String get ledgerHelpNanoXControls => '请解锁 Ledger。按住两个按钮打开控制菜单，然后选择：';

  @override
  String get ledgerHelpNanoXMenuPath => 'Settings > Security > Reset pairings';

  @override
  String get ledgerHelpNanoXName => '在 Nano X 上同时按住两个按钮 2 秒，然后找到 Device Name。';

  @override
  String get ledgerHelpNextPhoneSettings => '下一步：手机设置';

  @override
  String get ledgerHelpNextSearchInVizor => '下一步：在 Vizor 中搜索';

  @override
  String get ledgerHelpNextSearchTitle => '查找你的 Ledger';

  @override
  String get ledgerHelpNotResetDevice =>
      '请使用蓝牙配对选项，而不是 Reset device。你的钱包和账户不会受到影响。';

  @override
  String get ledgerHelpOpenBluetoothSettings => '打开蓝牙设置';

  @override
  String ledgerHelpOtherModelName(String model) {
    return '在 $model 上查看 Settings > Name。';
  }

  @override
  String get ledgerHelpRemovePairingOnLedger => '请先在 Ledger 上移除已保存的配对，再在手机上移除。';

  @override
  String get ledgerHelpRestartBothGuide =>
      '如果仍未出现，请重启两台设备，并查看 Ledger 官方的蓝牙故障排除指南。';

  @override
  String get ledgerHelpSearchSelectOpenZcash =>
      '请在 Vizor 中搜索并选择你的 Ledger。Vizor 提示时再打开 Zcash 应用。';

  @override
  String get ledgerHelpSelectModelHint => '选择型号后即可查看移除配对的说明。';

  @override
  String get ledgerHelpShortIdName =>
      '如果你没有为 Ledger 命名，它可能显示为类似 01AB 的短 ID。否则请查找你设置的名称。';

  @override
  String get ledgerHelpSkipIfNotListed => '如果列表中没有 Ledger，请跳过此步骤并继续。';

  @override
  String ledgerHelpStepBackInVizor(String step) {
    return '第 $step 步，共 3 步 · 返回 Vizor';
  }

  @override
  String ledgerHelpStepOnLedger(String step) {
    return '第 $step 步，共 3 步 · 在你的 Ledger 上';
  }

  @override
  String ledgerHelpStepOnPhone(String step) {
    return '第 $step 步，共 3 步 · 在你的手机上';
  }

  @override
  String get ledgerHelpStillNotShowing => '仍未显示？';

  @override
  String get ledgerHelpTouchControls => '请解锁 Ledger。在主屏幕上点按设置图标，然后选择：';

  @override
  String get ledgerHelpTouchMenuPath => 'Bluetooth > Remove pairing';

  @override
  String get ledgerHelpTryRestart =>
      '请尝试重启 Ledger。如果仍然找不到，在两台设备上移除已保存的蓝牙配对可能会有帮助。';

  @override
  String ledgerKeepAppOpen(String appName) {
    return '请保持 $appName 应用处于打开状态。';
  }

  @override
  String get ledgerKeepConnectedUntilCancelled => '请保持 Ledger 连接，直到当前请求被取消。';

  @override
  String get ledgerKeepConnectedWhileChecking => 'Vizor 检查应用期间，请保持 Ledger 连接。';

  @override
  String get ledgerKeepItOpen => '请在 Ledger 上保持其打开。';

  @override
  String get ledgerKeepNearbyUnlocked => '请将 Ledger 放在附近并保持解锁，同时开启蓝牙。';

  @override
  String get ledgerKeepNearbyUnlockedShort => '请将 Ledger 放在附近并保持解锁。';

  @override
  String get ledgerKeepZcashOpen => '请保持 Zcash 应用处于打开状态。';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS 可能会请求蓝牙权限。如果出现提示，请允许 Vizor 访问。';

  @override
  String get ledgerMismatchChooseHolder => '请选择保存此账户的 Ledger。已保存的连接未更改。';

  @override
  String get ledgerMismatchChooseHolderMobile => '请选择保存此账户的 Ledger。已保存的连接未更改。';

  @override
  String get ledgerMismatchConnectHolder => '请连接保存此账户的 Ledger。已保存的连接未更改。';

  @override
  String get ledgerMobileAnotherRequestActive =>
      '另一个 Ledger 请求仍在进行。请在 Ledger 上完成或拒绝该请求，然后重试。';

  @override
  String get ledgerMobileCheckBluetoothBelow => '请在下方检查蓝牙权限，然后重新尝试连接 Ledger。';

  @override
  String get ledgerMobileConnectionLost =>
      '与 Ledger 的蓝牙连接已断开或无法建立。请开启并解锁 Ledger，将其放在附近，然后重试。';

  @override
  String get ledgerMobilePairingInvalid =>
      '蓝牙配对已失效。请在设备的蓝牙设置中忽略此 Ledger，然后重新连接。';

  @override
  String get ledgerMobilePairingNotCompleted =>
      '蓝牙配对未完成。请重新连接 Ledger 并批准配对请求，然后重试。';

  @override
  String get ledgerMobileRequestCancelled => 'Ledger 请求已取消。准备好后请重试。';

  @override
  String get ledgerMobileRequestRejected => '请求已在 Ledger 上被拒绝。准备好后请重试。';

  @override
  String get ledgerMobileTurnOnBluetooth => '请开启蓝牙，然后重试。';

  @override
  String get ledgerMobileTurnOnLocation =>
      '在此 Android 版本上查找 Ledger 需要开启定位服务，请开启后重试。';

  @override
  String get ledgerMobileUnavailable =>
      'Vizor 无法连接你的 Ledger。请确认它已开启、已解锁且在附近，然后重试。';

  @override
  String get ledgerNoDevicesFound => '未找到 Ledger 设备';

  @override
  String get ledgerNoDevicesFoundHint => '请确认 Ledger 已解锁，然后重试。';

  @override
  String get ledgerNoneFoundDesktop =>
      '未找到 Ledger。请解锁 Ledger，开启蓝牙并将其放在附近，然后重新搜索。';

  @override
  String get ledgerOnYourLedger => '在 Ledger 上';

  @override
  String ledgerOpenAppInstruction(String appName) {
    return '请打开 $appName 应用';
  }

  @override
  String ledgerOpenAppOnLedger(String appName) {
    return '请在 Ledger 上打开 $appName 应用。';
  }

  @override
  String get ledgerOpenBluetoothSettingsManually => '请手动打开蓝牙设置以移除旧的配对。';

  @override
  String get ledgerOpenZcashThenTryAgain => '请打开 Zcash 应用，然后重试。';

  @override
  String get ledgerOpeningConnectionHelp => '正在打开连接帮助…';

  @override
  String get ledgerPairingNoLongerRecognized => '你的 Ledger 不再识别此蓝牙配对。';

  @override
  String get ledgerPairingNoLongerRecognizedRemove =>
      '你的 Ledger 不再识别此蓝牙配对。请移除旧的配对，然后重新连接。';

  @override
  String ledgerProcedureStep(String step, String total) {
    return '第 $step 步，共 $total 步';
  }

  @override
  String ledgerProcedureStepComplete(String step, String total) {
    return '第 $step 步，共 $total 步，已完成';
  }

  @override
  String get ledgerReadinessAppNotVerified =>
      'Vizor 无法验证 Ledger 上的 Zcash 应用。请重试。';

  @override
  String get ledgerReadinessCouldNotPrepare =>
      'Vizor 无法准备 Ledger 上的 Zcash 应用。请重试。';

  @override
  String get ledgerReadinessOpenZcashApp => '请在 Ledger 上打开 Zcash 应用，然后重试。';

  @override
  String get ledgerReadinessOperationCancelled => 'Ledger 操作已取消。';

  @override
  String get ledgerReadinessReconnectUnlockTryAgain => '请重新连接并解锁 Ledger，然后重试。';

  @override
  String ledgerReadinessUpdateApp(String version) {
    return '请将 Ledger 上的 Zcash 应用更新到 $version 或更高版本。';
  }

  @override
  String get ledgerReadinessUsbPermission =>
      '请通过 USB 连接并解锁 Ledger。如果已连接，请在 Linux 上安装 Ledger udev 规则，然后拔下并重新连接。';

  @override
  String get ledgerReadyContinueSigning => '你的 Ledger 已就绪。准备好后请继续签名。';

  @override
  String get ledgerReadyReviewOnLedger => '准备好后请继续，在 Ledger 上查看交易。';

  @override
  String get ledgerReconnectTitle => '重新连接 Ledger';

  @override
  String get ledgerRemoveOldPairing => '移除旧的配对';

  @override
  String get ledgerRemovePairingIos =>
      '请打开“设置”>“蓝牙”。如果列表中有你的 Ledger，请点按其信息按钮并忽略此设备。';

  @override
  String get ledgerRemovePairingMacos =>
      '请打开“系统设置”>“蓝牙”。如果列表中有你的 Ledger，请移除其已保存的配对。';

  @override
  String get ledgerRemovePairingOther => '请打开蓝牙设置。如果列表中有你的 Ledger，请移除其已保存的配对。';

  @override
  String get ledgerResetBluetoothPairing => '重置蓝牙配对';

  @override
  String get ledgerReturningToOptions => '正在返回连接选项…';

  @override
  String get ledgerSavedFindAgain => '此 Ledger 与你的账户匹配。请再次查找以继续。';

  @override
  String get ledgerSavedMatchesFindAgain => '此 Ledger 与你的账户匹配，现已保存。请再次查找以继续。';

  @override
  String get ledgerSavingVerified => '账户匹配。正在保存已验证的连接。';

  @override
  String get ledgerSearchAgain => '重新搜索';

  @override
  String get ledgerSearchTakesAWhile => '这可能需要几秒钟。';

  @override
  String get ledgerSearchingDevices => '正在搜索 Ledger 设备…';

  @override
  String get ledgerSearchingNearby => '正在搜索附近的 Ledger…';

  @override
  String get ledgerSelectYourLedger => '请选择你的 Ledger。';

  @override
  String get ledgerSheetAddFailedTitle => '无法添加 Ledger 账户';

  @override
  String get ledgerSheetCancelFailedTitle => '无法取消 Ledger 请求';

  @override
  String get ledgerSheetDeclinedTitle => '请求已被拒绝';

  @override
  String get ledgerSigningApproveNextSeparately => '下一笔交易需要单独批准。';

  @override
  String get ledgerSigningApproveOrReject => '请批准以进行签名，或拒绝以取消。';

  @override
  String get ledgerSigningApproveToSign => '请批准以进行签名。';

  @override
  String get ledgerSigningApproveToSignNext => '请批准以进行签名。\n\n下一笔交易需要单独批准。';

  @override
  String get ledgerSigningApprovedFinishing => '已在 Ledger 上批准。Vizor 正在完成交易。';

  @override
  String get ledgerSigningChangeConnection => '更改连接方式';

  @override
  String get ledgerSigningCheckAmountRecipient => '出现提示时，请在 Ledger 上核对金额和收款方。';

  @override
  String get ledgerSigningCloseSemantics => '关闭 Ledger';

  @override
  String get ledgerSigningConfirmRequestReconnect =>
      '请在 Ledger 上确认该请求。Vizor 将自动重新连接。';

  @override
  String get ledgerSigningDeclined => '已在 Ledger 上拒绝签名。准备好后请重试。';

  @override
  String get ledgerSigningFinishingRequest => '正在完成 Ledger 请求。';

  @override
  String get ledgerSigningKeepLedgerConnected => '请保持 Ledger 已连接。';

  @override
  String get ledgerSigningKeepOpenWhileCancelling =>
      '请在取消 Ledger 请求期间保持 Vizor 处于打开状态。';

  @override
  String get ledgerSigningKeepVizorOpen => '请保持 Vizor 处于打开状态。';

  @override
  String get ledgerSigningKeepVizorOpenShort => '保持 Vizor 打开';

  @override
  String get ledgerSigningMsgPreparing => '请稍候，Vizor 正在准备你的交易。';

  @override
  String get ledgerSigningMsgReviewing => '出现提示时，请在 Ledger 上查看并批准。';

  @override
  String ledgerSigningMsgSending(String wait) {
    return '$wait请保持 Ledger 已连接。';
  }

  @override
  String get ledgerSigningSaving => '正在保存已签名的交易。';

  @override
  String get ledgerSigningStatusCheckingDevice => '正在检查设备';

  @override
  String get ledgerSigningStatusOpeningZcash => '正在打开 Zcash';

  @override
  String get ledgerSigningStatusPreparing => '正在准备签名';

  @override
  String get ledgerSigningStatusReview => '在设备上查看';

  @override
  String get ledgerSigningStatusWaitingApproval => '正在等待你的批准';

  @override
  String get ledgerSigningStepFinish => '完成交易';

  @override
  String get ledgerSigningStepPrepare => '准备交易';

  @override
  String get ledgerSigningStepReview => '在 Ledger 上查看';

  @override
  String get ledgerSigningTitleConfirmOnLedger => '请在 Ledger 上确认';

  @override
  String get ledgerSigningTitleFinishing => '正在完成交易';

  @override
  String get ledgerSigningTitlePreparing => '正在准备交易';

  @override
  String get ledgerSigningTitleReviewing => '请查看你的 Ledger';

  @override
  String get ledgerSigningTitleSending => '正在通过 Ledger 处理';

  @override
  String get ledgerSigningTitleSendingTx => '正在发送交易';

  @override
  String get ledgerSigningTitleSign => '签署交易';

  @override
  String ledgerSigningTransactionProgress(String current, String total) {
    return '第 $current 笔交易，共 $total 笔';
  }

  @override
  String get ledgerSigningWaitInstruction => 'Ledger 正在准备签名。几秒钟内可能看起来没有响应。';

  @override
  String get ledgerStatusFollowPrompts => '请按照 Ledger 上的提示操作';

  @override
  String get ledgerStatusOpeningBluetoothSettings => '正在打开蓝牙设置…';

  @override
  String get ledgerStatusSavingConnection => '正在保存连接…';

  @override
  String get ledgerStatusSearchingNearby => '正在搜索附近的设备…';

  @override
  String get ledgerStatusStillSearching => '仍在搜索附近的设备…';

  @override
  String get ledgerStepApproveViewingKey => '批准查看密钥';

  @override
  String ledgerStepOpenApp(String appName) {
    return '打开 $appName';
  }

  @override
  String get ledgerStepOpenZcash => '打开 Zcash';

  @override
  String get ledgerStopSearchFailedHelp => '无法停止搜索。请尝试再次打开连接帮助。';

  @override
  String get ledgerStoppingSearch => '正在停止搜索';

  @override
  String get ledgerSupportedDevices => '支持的设备';

  @override
  String get ledgerTitleConnectingToLedger => '正在连接你的 Ledger';

  @override
  String get ledgerTitleFindingLedger => '正在查找你的 Ledger';

  @override
  String get ledgerTitleLedgerConnected => '你的 Ledger 已连接';

  @override
  String get ledgerTitleLedgerSaved => 'Ledger 已保存';

  @override
  String get ledgerTitleMismatch => '此 Ledger 不匹配';

  @override
  String get ledgerTitlePairAgain => '请重新配对你的 Ledger';

  @override
  String get ledgerTitleSavingConnection => '正在保存你的连接';

  @override
  String get ledgerTitleSelectYourLedger => '请选择你的 Ledger';

  @override
  String get ledgerTransportBluetooth => '蓝牙';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerUnlockBluetoothNearby => '请解锁 Ledger，开启蓝牙，并将其放在附近。';

  @override
  String get ledgerUnlockEnableBluetoothNearby => '请解锁 Ledger，开启蓝牙并将其放在附近。';

  @override
  String get ledgerUnlockOpenZcashApprove =>
      '请解锁 Ledger 并打开 Zcash 应用。如有提示请批准打开。';

  @override
  String get ledgerUnlockWithPin => '使用 PIN 码解锁。';

  @override
  String get ledgerUsbApproveOpening => '请在 Ledger 上批准打开 Zcash 应用。';

  @override
  String get ledgerUsbCheckCableOpenApp => '请检查 USB 线缆，解锁 Ledger 并打开 Zcash 应用。';

  @override
  String get ledgerUsbConnectUnlockOpen => '请用 USB 线缆连接 Ledger，解锁后打开 Zcash 应用。';

  @override
  String get ledgerUsbConnection => 'USB 连接';

  @override
  String get ledgerUsbCouldNotOpen =>
      'Vizor 找到了你的 Ledger，但无法打开。请关闭其他使用 Ledger 的钱包应用，重新连接后重试。';

  @override
  String get ledgerUsbCouldNotStart =>
      'Vizor 无法启动对 Ledger 的 USB 访问。请重新连接设备后重试。';

  @override
  String ledgerUsbInterrupted(String instruction) {
    return '与 Ledger 的 USB 连接已中断。请重新连接并解锁 Ledger。$instruction';
  }

  @override
  String get ledgerUsbPermissionLinux =>
      'Vizor 无法通过 USB 访问你的 Ledger。请安装适用于 Linux 的 Ledger udev 规则（github.com/LedgerHQ/udev-rules），然后重新连接 Ledger 并重试。';

  @override
  String get ledgerUsbPermissionOther =>
      'Vizor 无法通过 USB 访问你的 Ledger。请检查 USB 设备权限，然后重新连接并重试。';

  @override
  String get ledgerVerifyingNewDevice => '如有提示请完成配对，然后批准共享你的查看密钥。';

  @override
  String get ledgerVerifyingSavedDevice => '请解锁 Ledger，如有提示请确认打开 Zcash。';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor 正在检查 Zcash 应用。';

  @override
  String get ledgerWaitingForApproval => '正在等待批准…';

  @override
  String get lockBodyPaused => '同步已暂停。解锁 Vizor 以继续。';

  @override
  String get lockBodySynced => '同步成功。解锁 Vizor 以继续。';

  @override
  String get lockCheckingPasscode => '正在验证数字密码...';

  @override
  String get lockConfirmPasscodeSemantics => '确认数字密码以解锁 Vizor';

  @override
  String lockNavSyncing(int percent) {
    return '$percent% 同步中...';
  }

  @override
  String get lockSyncCompleteTitle => '同步完成';

  @override
  String get lockSyncPausedSemantics => 'Vizor 同步已暂停';

  @override
  String get lockSyncPausedTitle => '同步已暂停';

  @override
  String get lockSyncingMessage => 'Vizor 正在同步';

  @override
  String get lockUnlockToContinue => '解锁以继续';

  @override
  String get lockUnlockToContinueBody => '解锁 Vizor 以继续';

  @override
  String get lockUnlockToContinuePausedBody => '解锁 Vizor 以继续。';

  @override
  String migrationAboutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 分钟',
    );
    return '$_temp0';
  }

  @override
  String get migrationAnalyzingBalance => '正在分析你的余额...';

  @override
  String get migrationAnalyzingCaption => 'Vizor 正在为你的迁移寻找安全、隐私\n与速度之间的最佳平衡';

  @override
  String get migrationAnalyzingFindingBatches => '正在寻找私密批次...';

  @override
  String get migrationAnalyzingPreparingPlan => '正在准备你的迁移计划...';

  @override
  String get migrationAnalyzingSemanticsLabel => '正在准备私密迁移计划';

  @override
  String get migrationAnnouncementBody =>
      'Ironwood 是 Zcash 最新的屏蔽资金池。\n它是首个经过形式化验证的资金池，\n采用前沿密码学技术。';

  @override
  String get migrationAnnouncementReleaseNote => '官方发布说明';

  @override
  String get migrationAnnouncementStart => '开始迁移';

  @override
  String get migrationBackAbout => '关于迁移';

  @override
  String get migrationBackHome => '返回首页';

  @override
  String get migrationBackHowItWorks => '迁移的工作方式';

  @override
  String get migrationBackOptions => '迁移选项';

  @override
  String get migrationBatchBroadcasting => '正在广播...';

  @override
  String migrationBatchCardTitle(String number, String count) {
    return '批次 #$number（$count 个票据）';
  }

  @override
  String get migrationBatchConfirming => '确认中...';

  @override
  String migrationBlockHeight(String height) {
    return '区块 $height';
  }

  @override
  String migrationBlocksEstimate(String blocks) {
    return '约 $blocks 个区块';
  }

  @override
  String migrationBroadcastApproxInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 小时后',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastApproxInMinutes(int count) {
    return '约 $count 分钟后';
  }

  @override
  String get migrationBroadcastConfirmed => '已确认';

  @override
  String get migrationBroadcastDueNow => '即将发送';

  @override
  String migrationBroadcastInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 小时后',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastInMinutes(int count) {
    return '$count 分钟后';
  }

  @override
  String get migrationBroadcastSubmitted => '已提交';

  @override
  String get migrationCarouselPreparationLabel => '迁移准备说明';

  @override
  String get migrationCarouselProgressLabel => '迁移说明';

  @override
  String get migrationCompleteBody => '迁移已成功完成，\n你可以像往常一样使用资金。';

  @override
  String migrationCompleteTitle(String amount) {
    return '你的 $amount ZEC\n已在 Ironwood 上！';
  }

  @override
  String get migrationContinueMigration => '继续迁移';

  @override
  String get migrationContinuing => '正在继续...';

  @override
  String get migrationCtaStart => '迁移到 Ironwood 资金池';

  @override
  String get migrationCurrentBatch => '当前批次';

  @override
  String migrationDurationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 天',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationHalfHours(String hours) {
    return '约 $hours.5 小时';
  }

  @override
  String migrationDurationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 小时',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 分钟',
    );
    return '$_temp0';
  }

  @override
  String get migrationErrorBroadcast => '无法广播迁移交易，请重试。';

  @override
  String get migrationErrorContinue => '无法继续迁移，请重试。';

  @override
  String get migrationErrorKeystonePrepare => '无法准备 Keystone 签名。';

  @override
  String get migrationErrorLedgerExcluded => '当前流程需要批量签名，因此不支持 Ledger 私密迁移。';

  @override
  String get migrationErrorPlanChanged => '金额或手续费已变更，请查看更新后的详情。';

  @override
  String get migrationErrorStart => '无法开始迁移，请重试。';

  @override
  String get migrationErrorUnlockBeforeContinue => '继续迁移前请先解锁 Vizor。';

  @override
  String get migrationErrorUnlockBeforeStart => '开始迁移前请先解锁 Vizor。';

  @override
  String get migrationErrorWaitForSync => '请等待同步完成后重试。';

  @override
  String get migrationEstimateAfterSigning => '签名后';

  @override
  String get migrationEstimateComplete => '已完成';

  @override
  String migrationEstimateIn(String estimate) {
    return '$estimate后';
  }

  @override
  String migrationEstimateInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 天后',
    );
    return '$_temp0';
  }

  @override
  String migrationEstimateInHours(String hours) {
    return '约 $hours 小时后';
  }

  @override
  String migrationEstimateInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 分钟后',
    );
    return '$_temp0';
  }

  @override
  String get migrationEstimateInOneHour => '约 1 小时后';

  @override
  String get migrationEstimatedArrivalTime => '预计到达时间';

  @override
  String get migrationExpectKeepRunningBody =>
      '你的电脑需要保持解锁且 Vizor 正在运行，这样我们才能发送下一笔迁移交易';

  @override
  String get migrationExpectLongBody => '根据迁移金额的不同，Ironwood 迁移可能需要数小时到几天不等。';

  @override
  String get migrationExpectLongTitle => '迁移可能需要很长时间';

  @override
  String get migrationExpectSpendBody => '每笔已确认的 Ironwood 金额在其余迁移继续进行时即可花费。';

  @override
  String get migrationExpectSpendTitle => '资金到账后即可花费';

  @override
  String get migrationExpectTitle => '须知';

  @override
  String get migrationExpectVpnBody => '建议在可信的 VPN/网络隐私层之后运行迁移';

  @override
  String get migrationExpectVpnTitle => '使用 VPN 获得额外隐私';

  @override
  String get migrationFlowTitle => 'Ironwood 迁移';

  @override
  String get migrationHowDelayedBody => '为降低可追踪性，Vizor 会分多个批次、错开时间间隔缓慢发送各部分。';

  @override
  String get migrationHowDelayedTitle => '延迟且随机的迁移';

  @override
  String get migrationHowFrozenBody => '要使用你现有的屏蔽余额，需要一次性迁移到 Ironwood。';

  @override
  String get migrationHowFrozenTitle => 'Orchard（旧版屏蔽）余额已冻结';

  @override
  String get migrationHowPreparationBody =>
      '迁移前，Vizor 会将你的全部余额拆分为许多较小的票据（例如 0.1 ZEC / 1 ZEC / 5 ZEC）。';

  @override
  String get migrationHowPreparationTitle => '迁移前的准备';

  @override
  String migrationHowStepLabel(String number) {
    return '第 $number 步';
  }

  @override
  String migrationHowStepSemanticsCurrent(
    String number,
    String total,
    String title,
    String body,
  ) {
    return '迁移共 $total 步，第 $number 步。$title。$body';
  }

  @override
  String migrationHowStepSemanticsShow(String number, String total) {
    return '显示迁移共 $total 步中的第 $number 步';
  }

  @override
  String get migrationHowTitle => '迁移的工作方式';

  @override
  String get migrationImmediateAuthoriseAnyway => '仍然授权';

  @override
  String get migrationImmediateAuthorising => '正在授权…';

  @override
  String get migrationImmediateAuthorisingSemantics => '正在授权迁移';

  @override
  String get migrationImmediateConsiderOther => '考虑其他选项';

  @override
  String get migrationImmediateFees => '手续费（预估）';

  @override
  String get migrationImmediateNoBalance => '没有可用于即时迁移的可花费 Orchard 余额。';

  @override
  String get migrationImmediatePlanFailed => '无法计算即时迁移计划，请同步后重试。';

  @override
  String get migrationImmediateRetryCalculation => '重试计算';

  @override
  String get migrationImmediateReviewTitle => '查看迁移计划';

  @override
  String migrationImmediateTradeoffBody(String amount, String highlight) {
    return '将在一个可见的步骤中完成，你的 $amount 和时间点会$highlight。';
  }

  @override
  String get migrationImmediateTradeoffEmphasis =>
      'easier to associate with your wallet.';

  @override
  String get migrationImmediateTradeoffHighlight => '更容易与你的钱包关联';

  @override
  String migrationImmediateTradeoffLead(String amount) {
    return 'Crosses in one visible step — your $amount and timing are ';
  }

  @override
  String get migrationImmediateTradeoffLedger => '\nLedger 账户无法使用私密迁移。';

  @override
  String get migrationImmediateTradeoffPrivate => '\n建议选择私密迁移选项。';

  @override
  String get migrationImmediateTradeoffTitle => '隐私权衡';

  @override
  String get migrationImmediateUnavailable => '不可用';

  @override
  String migrationInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '约 $count 分钟后',
    );
    return '$_temp0';
  }

  @override
  String get migrationIntroAnnouncement => '官方公告';

  @override
  String get migrationIntroBadge => 'Zcash 网络升级';

  @override
  String migrationIntroBody(String amount) {
    return '你的 $amount ZEC 目前在 Orchard 中。\n要继续将这些资金用于屏蔽支付，你需要将其迁移到 Ironwood。资金转移前，你会先查看迁移计划。';
  }

  @override
  String get migrationIntroTagline => 'Zcash 全新的屏蔽资金池。';

  @override
  String get migrationKeystoneApplyingSignature => '正在应用 Keystone 签名。';

  @override
  String get migrationKeystoneApplyingToPlan => '正在将 Keystone 签名应用到你的迁移计划。';

  @override
  String get migrationKeystoneBackToReview => '返回查看';

  @override
  String get migrationKeystoneBackToStatus => '返回状态';

  @override
  String get migrationKeystoneBeginSigning => '开始签名';

  @override
  String get migrationKeystoneCameraAccess => '请允许访问摄像头以扫描已签名的 Keystone 二维码。';

  @override
  String get migrationKeystoneCameraOnly =>
      'Keystone 迁移签名仅支持摄像头扫描二维码。请连接摄像头后重试。';

  @override
  String get migrationKeystoneCancelFailed => '无法取消签名请求，请重试。';

  @override
  String get migrationKeystoneClickToEnlarge => '点击二维码可放大';

  @override
  String get migrationKeystoneConfirmTitle => '使用 Keystone 确认迁移';

  @override
  String get migrationKeystoneEnlargeQr => '放大 Keystone 请求二维码';

  @override
  String get migrationKeystoneEnlargedQr => '放大的 Keystone 请求二维码';

  @override
  String get migrationKeystoneFirmwareUpdate =>
      '请更新 Keystone 固件以签署 Ironwood 迁移，然后重试。';

  @override
  String get migrationKeystoneMobileTitle => 'Keystone 迁移';

  @override
  String get migrationKeystoneNotKeystone => '请使用 Keystone 账户签署此迁移。';

  @override
  String get migrationKeystoneOpenSignedQr =>
      '请在 Keystone 上打开已签名的迁移二维码，然后重新扫描。';

  @override
  String get migrationKeystonePlanBody => '每一轮使用一个动态请求二维码和一个已签名的响应二维码。';

  @override
  String get migrationKeystonePlanTitle => 'Keystone 签名计划';

  @override
  String get migrationKeystonePrepareFailed => '无法准备 Keystone 签名，请重试。';

  @override
  String get migrationKeystonePreparingQr => '正在准备二维码...';

  @override
  String get migrationKeystoneProofFailed => 'Vizor 无法准备本地证明。请返回并重新准备此请求。';

  @override
  String get migrationKeystoneProofWaiting => '已获取签名。Vizor 仍在准备本地证明，请保持此页面打开。';

  @override
  String migrationKeystoneProofWaitingProgress(String ready, String total) {
    return '已获取签名。Vizor 仍在准备本地证明（$ready/$total），请保持此页面打开。';
  }

  @override
  String get migrationKeystoneProofsPreparing => '正在准备本地证明';

  @override
  String get migrationKeystoneProofsPreparingEllipsis => '正在准备本地证明...';

  @override
  String migrationKeystoneProofsProgress(String ready, String total) {
    return '正在准备本地证明 $ready/$total';
  }

  @override
  String get migrationKeystoneQrBodyCombined =>
      '使用 Keystone 扫描此请求，一并签署准备交易和迁移批次。';

  @override
  String get migrationKeystoneQrBodyImmediate => '使用 Keystone 钱包扫描二维码以确认迁移。';

  @override
  String get migrationKeystoneQrBodyRound =>
      '使用 Keystone 扫描此请求二维码。完成后，Keystone 会显示新的已签名二维码。';

  @override
  String get migrationKeystoneRequestCancelled => '此签名请求已取消，请重新准备。';

  @override
  String get migrationKeystoneRequestExpired => '此 Keystone 签名请求已过期，请重新准备。';

  @override
  String get migrationKeystoneRequestQr => '请求二维码';

  @override
  String get migrationKeystoneRequestUnusable => '此 Keystone 签名请求已无法使用，请重新准备。';

  @override
  String migrationKeystoneRound(String current, String total) {
    return '第 $current/$total 轮';
  }

  @override
  String migrationKeystoneRoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 轮二维码签名',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneScanIssuesBody =>
      'Keystone Cypherpunk 固件可能有新版本。请检查是否已是最新版本。';

  @override
  String get migrationKeystoneScanIssuesConfirm => '好的，我去检查';

  @override
  String get migrationKeystoneScanIssuesTitle => '扫描二维码遇到问题？';

  @override
  String get migrationKeystoneScanNewQr => '请扫描 Keystone 上显示的新已签名二维码。';

  @override
  String get migrationKeystoneScanRequest => '使用 Keystone 扫描请求';

  @override
  String get migrationKeystoneScanSignature => '扫描 Keystone 签名';

  @override
  String get migrationKeystoneSignBatch => '签署 Ironwood 批次';

  @override
  String get migrationKeystoneSignMigration => '签署迁移';

  @override
  String get migrationKeystoneSignPrivateSplit => '签署私密拆分';

  @override
  String migrationKeystoneSignsAll(String transactions) {
    return '签署 $transactions';
  }

  @override
  String migrationKeystoneSignsSome(String count, String transactions) {
    return '签署 $transactions中的 $count 笔';
  }

  @override
  String get migrationKeystoneToolbarReview => '查看迁移';

  @override
  String get migrationKeystoneToolbarStatus => '迁移状态';

  @override
  String migrationKeystoneTransactionTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '共 $count 笔交易',
    );
    return '$_temp0';
  }

  @override
  String migrationKeystoneTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 笔交易',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneTryAfterSync => '请在同步完成后重试。';

  @override
  String get migrationKeystoneUnavailableTitle => '无法使用 Keystone 签名';

  @override
  String get migrationKeystoneUnlockFirst => '签署迁移前请先解锁 Vizor。';

  @override
  String get migrationKeystoneWaitingForProofsLong =>
      '已获取签名。本地证明准备好后，Vizor 会继续。';

  @override
  String get migrationKeystoneWaitingForProofsShort => '已获取签名，正在等待本地证明。';

  @override
  String get migrationKeystoneWrongRound =>
      '此已签名二维码来自另一轮。请返回，用 Keystone 扫描当前请求，然后扫描其新的已签名二维码。';

  @override
  String get migrationLedgerBroadcast => '无法广播迁移交易。';

  @override
  String get migrationLedgerConnect => '请连接并解锁你的 Ledger，然后打开 Zcash 应用。';

  @override
  String get migrationLedgerFailed => '无法完成 Ledger 迁移。';

  @override
  String get migrationLedgerFailedTitle => 'Ledger 迁移失败';

  @override
  String get migrationLedgerPlanChanged => '金额或手续费已变更。请返回并查看更新后的计划。';

  @override
  String get migrationLedgerProofs => 'Vizor 无法完成迁移证明的准备。';

  @override
  String get migrationLedgerRejected => '迁移交易已在你的 Ledger 上被拒绝。';

  @override
  String get migrationLedgerTitle => '使用 Ledger 迁移';

  @override
  String migrationLeftToTransfer(String amount) {
    return '待转移：$amount';
  }

  @override
  String get migrationManageCancelling => '正在取消...';

  @override
  String get migrationManageCannotCancel => '此迁移已无法取消。';

  @override
  String get migrationManageConfirm => '确认';

  @override
  String get migrationManageImmediateBullet1 => '剩余的拆分票据将作为即时迁移处理，可追踪性会略有提高';

  @override
  String get migrationManageImmediateBullet2 => '已广播的交易不会被撤销';

  @override
  String get migrationManageImmediateBullet3 => '即时迁移无法撤销';

  @override
  String get migrationManageImmediateIntro => '立即处理剩余的迁移。';

  @override
  String get migrationManageNoBalance => '没有剩余的 Orchard 余额可迁移。';

  @override
  String get migrationManageStop => '停止迁移';

  @override
  String get migrationManageStopBody => '这将取消剩余已安排的迁移交易。你可以在首页重新开始迁移。';

  @override
  String get migrationManageStopTitle => '确定要停止吗？';

  @override
  String get migrationManageStopping => '正在停止...';

  @override
  String get migrationManageSwitchImmediate => '切换为即时迁移';

  @override
  String get migrationManageTitle => '管理迁移';

  @override
  String get migrationManageUpdateFailed => '无法更新迁移，请重试。';

  @override
  String get migrationMobileActionAllTransactions => '所有交易';

  @override
  String migrationMobileActionBatch(int number) {
    return '批次 #$number';
  }

  @override
  String get migrationMobileActionInProgress => '迁移操作进行中';

  @override
  String get migrationMobileActionNeedSignature => '需要签名的交易';

  @override
  String migrationMobileActionPrepareBatch(int number) {
    return '准备批次 #$number';
  }

  @override
  String migrationMobileActionPreparingBatch(int number) {
    return '正在准备批次 #$number...';
  }

  @override
  String get migrationMobileActionResign => '重新签署迁移交易';

  @override
  String get migrationMobileActionSign => '签署迁移交易';

  @override
  String migrationMobileActionSignBatch(int number) {
    return '签署批次 #$number';
  }

  @override
  String get migrationMobileActionSubmitScheduled => '提交计划的交易';

  @override
  String get migrationMobileActionSubmittingScheduled => '正在提交计划的交易...';

  @override
  String get migrationMobileAnnouncementBody =>
      'Zcash 最新的屏蔽资金池，采用前沿密码学和形式化验证。\n\n你的屏蔽余额需要一次性迁移到 Ironwood。';

  @override
  String get migrationMobileAnnouncementOfficial => '官方公告';

  @override
  String get migrationMobileAnnouncementUpgrade => '升级到 Ironwood';

  @override
  String get migrationMobileAttentionContinueTitle => '继续你的迁移';

  @override
  String get migrationMobileAttentionLateTitle => '有一笔迁移交易需要你处理';

  @override
  String get migrationMobileAttentionLater => '稍后再去';

  @override
  String get migrationMobileAttentionOpen => '前往迁移页面';

  @override
  String get migrationMobileAttentionProofTitle => '你的下一个迁移批次已就绪';

  @override
  String migrationMobileAttentionSignatureSheet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个票据已准备好等待你签名',
    );
    return '$_temp0';
  }

  @override
  String get migrationMobileBackToHome => '返回首页';

  @override
  String get migrationMobileBannerLate => '迁移需要处理';

  @override
  String get migrationMobileBannerProof => '下一个迁移批次已就绪';

  @override
  String migrationMobileBannerRemaining(String amount) {
    return '$amount ZEC 仍在迁移';
  }

  @override
  String migrationMobileBannerSignature(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个票据可以签名',
    );
    return '$_temp0';
  }

  @override
  String migrationMobileBatchProgress(int completed, int total) {
    return '批次 $completed/$total';
  }

  @override
  String get migrationMobileCanLeave => '你可以离开此屏幕。';

  @override
  String get migrationMobileCompleteBody => '迁移已成功完成，你可以像往常一样花费资金。';

  @override
  String migrationMobileCompleteHeading(String amount) {
    return '你的\n$amount\n已到达 Ironwood！';
  }

  @override
  String get migrationMobileCompleteTitle => '全部完成！';

  @override
  String get migrationMobileContinueThisError => '无法继续此迁移。请重试。';

  @override
  String get migrationMobileCredentialsRestore => '继续之前，需要先恢复你的迁移凭据。';

  @override
  String get migrationMobileFastPlanError => '无法计算即时迁移的手续费。请同步后重试。';

  @override
  String get migrationMobileFastPlanUnavailable => '不可用';

  @override
  String get migrationMobileFastPrivacyBodyHighlight =>
      'easier to associate with your wallet';

  @override
  String get migrationMobileFastPrivacyConsiderPrivate => '建议选择私密迁移选项。';

  @override
  String get migrationMobileFastPrivacyLedger => 'Ledger 账户不支持私密迁移。';

  @override
  String migrationMobileFastSubmittedBody(String amount) {
    return '$amount 正在前往 Ironwood 的途中。';
  }

  @override
  String get migrationMobileFastSubmittedTitle => '迁移已提交';

  @override
  String get migrationMobileFastTitle => '快速迁移';

  @override
  String get migrationMobileHowItWorksNavTitle => '关于';

  @override
  String migrationMobileIntroBody(String amount) {
    return '你的 $amount ZEC 目前在 Orchard 中。要继续将这些资金用于屏蔽支付，你需要将其迁移到 Ironwood。在任何资金移动之前，你会先查看迁移计划。';
  }

  @override
  String get migrationMobileIntroReleaseNote => '官方发布说明';

  @override
  String get migrationMobileIntroTitle => 'Zcash 网络升级';

  @override
  String get migrationMobileKeepOpenUnlocked => '请保持 Vizor 打开且处于解锁状态。';

  @override
  String get migrationMobileKeepRunning => '但请保持 Vizor 打开并运行。';

  @override
  String get migrationMobileKeystoneConfirmPrepSemantics =>
      '使用 Keystone 确认迁移准备';

  @override
  String get migrationMobileKeystoneConfirmTransferSemantics =>
      '使用 Keystone 确认迁移转账';

  @override
  String get migrationMobileKeystoneHelpPrompt =>
      '在你的 Keystone 上点击 QR，\n然后扫描此二维码。';

  @override
  String get migrationMobileKeystoneHelpSemantics => 'Keystone 二维码扫描帮助';

  @override
  String get migrationMobileKeystoneLoadingQrSemantics => '正在加载二维码';

  @override
  String get migrationMobileKeystoneReconnect =>
      '请重新连接或重新导入你的 Keystone 账户以继续此迁移。';

  @override
  String get migrationMobileKeystoneRequestQrSemantics => 'Keystone 请求二维码';

  @override
  String get migrationMobileKeystoneRequiredStatus => '需要 Keystone 账户';

  @override
  String get migrationMobileKeystoneResignMessage =>
      '请使用 Keystone 签署重建的迁移交易以继续。';

  @override
  String get migrationMobileKeystoneScanCaption => '扫描 Keystone 上的\n二维码进行确认';

  @override
  String get migrationMobileKeystoneScanPrepSemantics =>
      '扫描 Keystone 上已签名的迁移准备';

  @override
  String get migrationMobileKeystoneScanProgress => '扫描进度';

  @override
  String get migrationMobileKeystoneScanTransferSemantics =>
      '扫描 Keystone 上已签名的迁移转账';

  @override
  String get migrationMobileManageCheckError => '无法检查迁移状态。请重试。';

  @override
  String get migrationMobileManageChecking => '正在检查迁移状态...';

  @override
  String get migrationMobileManageNoRevert => '已广播的交易不会被撤销。';

  @override
  String get migrationMobileManageRetryStatus => '重试状态检查';

  @override
  String get migrationMobileManageStopAction => '停止迁移';

  @override
  String get migrationMobileManageStopBody => '停止剩余的迁移。已迁移的资金将保留在 Ironwood 中。';

  @override
  String get migrationMobileManageStopTitle => '停止迁移？';

  @override
  String get migrationMobileManageSwitchAction => '切换到快速迁移';

  @override
  String get migrationMobileManageSwitchBody =>
      '停止私密计划，并为剩余余额查看快速迁移。快速迁移会增加可追踪性，一旦提交便无法撤销。';

  @override
  String get migrationMobileManageSwitchTitle => '切换到快速迁移？';

  @override
  String get migrationMobileManageTitle => '管理迁移';

  @override
  String get migrationMobileManageUnavailable => '此迁移已无法管理。';

  @override
  String get migrationMobileManageWaitingBroadcast => '正在等待进行中的广播完成，然后停止剩余的迁移。';

  @override
  String get migrationMobileNextConfirmationsArriving =>
      '确认仍在陆续到达。\n你可以离开 Vizor，稍后再来查看。';

  @override
  String migrationMobileNextExpectedIn(String timing) {
    return '预计下一个迁移步骤将在\n$timing。';
  }

  @override
  String migrationMobileNextNotificationsOffBlock(int height, String timing) {
    return '通知已关闭。请在区块 $height（$timing）之后打开 Vizor 并批准下一个迁移批次。';
  }

  @override
  String get migrationMobileNextNotificationsOffNoTiming =>
      '通知已关闭。待时间信息可用后，请再次打开 Vizor 并批准下一个迁移批次。';

  @override
  String get migrationMobileNextNotificationsOffOpen =>
      '通知已关闭。请再次打开 Vizor 以继续。';

  @override
  String get migrationMobileNextNotificationsOnLeave =>
      '通知已开启。你可以离开 Vizor，稍后再来查看。';

  @override
  String get migrationMobileNextOnTheWay => '下一个迁移步骤即将开始。';

  @override
  String get migrationMobileNextReadyAuto => '计划的交易已准备好自动提交。请保持 Vizor 打开。';

  @override
  String get migrationMobileNextStepReady => '下一个迁移步骤已准备就绪。请保持 Vizor 打开以继续。';

  @override
  String migrationMobileNextTimingUntil(String timing) {
    return '距离下一个迁移步骤还有 $timing。\n通知已开启；你可以离开 Vizor，稍后再来查看。';
  }

  @override
  String get migrationMobileNextTorDisclosure => 'Vizor 关闭期间，迁移将通过直接连接继续进行。';

  @override
  String get migrationMobileNotifyAllow => '允许通知';

  @override
  String get migrationMobileNotifyBody =>
      '部分迁移步骤需要你的批准。轮到你时我们会通知你，让你能及时响应，避免不必要的延迟。';

  @override
  String get migrationMobileNotifyConfirmBody =>
      '没有通知时，你需要记得定期打开 Vizor，并在下一个迁移步骤就绪时批准它。';

  @override
  String get migrationMobileNotifyConfirmNote => '否则，你的迁移可能需要更长时间。';

  @override
  String get migrationMobileNotifyConfirmTitle => '不使用通知继续吗？';

  @override
  String get migrationMobileNotifyContinueWithout => '不使用通知继续';

  @override
  String get migrationMobileNotifyHeading => '让迁移按计划进行';

  @override
  String get migrationMobileNotifyStillOff =>
      '通知仍处于关闭状态。请在“设置”中允许，或在不使用通知的情况下继续。';

  @override
  String get migrationMobileNotifyTitle => '启用通知';

  @override
  String migrationMobileOptionImmediateBody(String estimate) {
    return '一次性迁移你的全部余额。速度快（$estimate），但隐私性较低。';
  }

  @override
  String get migrationMobileOptionPrivateBody =>
      '将交易拆分为多个部分以尽量降低可追踪性，但需要数小时到数天。';

  @override
  String get migrationMobileOptionPrivateUnavailableAndroid => 'Android 上不可用。';

  @override
  String get migrationMobileOptionsNavTitle => '迁移方式';

  @override
  String get migrationMobileOptionsOpenError => '无法打开迁移准备。请重试。';

  @override
  String get migrationMobileOptionsSubtitleAndroid =>
      'Android 上暂时无法使用私密迁移。请选择“即时”以继续。';

  @override
  String migrationMobileOptionsSubtitleAndroidRest(String amount) {
    return '$amount ZEC 仍在 Orchard 中。Android 上暂时无法使用私密迁移。请选择“即时”以继续。';
  }

  @override
  String get migrationMobileOptionsSubtitleLedger =>
      'Ledger 账户不支持私密迁移。请选择“即时”以继续。';

  @override
  String migrationMobileOptionsSubtitleLedgerRest(String amount) {
    return '$amount ZEC 仍在 Orchard 中。Ledger 账户不支持私密迁移。请选择“即时”以继续。';
  }

  @override
  String get migrationMobileOptionsTitle => '选择迁移方式';

  @override
  String get migrationMobileOptionsTitleRest => '如何迁移剩余部分';

  @override
  String migrationMobilePartConfirming(int count, int target) {
    return '确认中 · $count/$target';
  }

  @override
  String migrationMobilePartLabel(int number) {
    return '第 $number 部分';
  }

  @override
  String migrationMobilePartProgress(String part, int percent) {
    return '$part进度 $percent%';
  }

  @override
  String get migrationMobilePartQueued => '排队中';

  @override
  String get migrationMobilePartsPlaceholder => '随着交易准备就绪，迁移部分将显示在此处。';

  @override
  String get migrationMobilePrepAdvancing => '正在准备下一批交易。请保持 Vizor 打开。';

  @override
  String get migrationMobilePrepBackgroundTracking => '正在后台确认。你可以关闭 Vizor。';

  @override
  String get migrationMobilePrepBackgroundUnsupported =>
      '此设备无法在后台确认。请保持 Vizor 打开。';

  @override
  String get migrationMobilePrepContinue => '继续准备';

  @override
  String get migrationMobilePrepContinueKeystone => '使用 Keystone 继续';

  @override
  String get migrationMobilePrepDoneBody => '准备已完成。请在迁移状态中查看进度和所需的操作。';

  @override
  String get migrationMobilePrepDoneTitle => '准备已完成';

  @override
  String get migrationMobilePrepDuration => '准备大约需要\n10–20 分钟';

  @override
  String get migrationMobilePrepInfoThenBegin => '准备完成后，你的迁移即可开始。';

  @override
  String get migrationMobilePrepKeystoneSignature => '准备工作需要再次使用 Keystone 签名。';

  @override
  String get migrationMobilePrepNotificationsDisabled =>
      '请允许通知以在后台继续，或保持 Vizor 打开。';

  @override
  String get migrationMobilePrepPausedLeft => '由于你离开了应用，准备已暂停。';

  @override
  String get migrationMobilePrepSyncingWallet => '正在同步你的钱包…';

  @override
  String get migrationMobilePreparingBody => '正在为迁移准备你的余额。此步骤通常需要 10-20 分钟。';

  @override
  String get migrationMobilePreparingTitle => '正在准备迁移';

  @override
  String get migrationMobileProcessChooseBody => '比较注重隐私的计划与更快的迁移。';

  @override
  String get migrationMobileProcessChooseTitle => '选择迁移方式';

  @override
  String get migrationMobileProcessMoveBody => '注重隐私的迁移会错开时间发送各个部分，以降低可关联性。';

  @override
  String get migrationMobileProcessMoveTitle => '迁移到 Ironwood';

  @override
  String get migrationMobileProcessPrepareBody =>
      '迁移开始前，Vizor 会将你的余额重新整理为常见大小的若干部分。';

  @override
  String get migrationMobileProcessPrepareTitle => '准备你的余额';

  @override
  String get migrationMobileProcessSpendBody =>
      '每笔已确认的 Ironwood 金额在其余部分继续迁移时即可花费。';

  @override
  String get migrationMobileProcessSpendTitle => '资金到账即可花费';

  @override
  String get migrationMobileProgressAllClear => '一切正常。迁移正在进行';

  @override
  String migrationMobileProgressAllClearBatch(int number) {
    return '一切正常。正在处理批次 #$number';
  }

  @override
  String migrationMobileProgressBatchReady(int number) {
    return '批次 #$number 已就绪。';
  }

  @override
  String get migrationMobileProgressNextStep => '正在等待下一个迁移步骤';

  @override
  String get migrationMobileProgressReadyNow => '现已就绪';

  @override
  String get migrationMobileProgressScheduledReady => '计划的交易已就绪';

  @override
  String get migrationMobileProgressSyncingBody => '正在检查最新的确认和迁移状态。';

  @override
  String get migrationMobileProgressSyncingTitle => '正在同步迁移进度';

  @override
  String get migrationMobileProgressWaitingWindowBody =>
      '准备已完成，但我们正在等待\n下一个可用的签名窗口。\n轮到你操作时我们会通知你。';

  @override
  String get migrationMobileProgressYourConfirmation => '正在等待你的确认';

  @override
  String get migrationMobileRebuildAction => '重建';

  @override
  String get migrationMobileRebuildBody =>
      'Vizor 会先确认待处理的交易尚未发送，然后仅针对你的剩余余额重建迁移。任何已确认的转账都将保持不变。';

  @override
  String get migrationMobileRebuildTitle => '重建迁移？';

  @override
  String get migrationMobileRecover => '恢复';

  @override
  String get migrationMobileRecovering => '正在恢复...';

  @override
  String get migrationMobileRecoveryRequired => '需要恢复迁移。';

  @override
  String get migrationMobileResuming => '正在恢复...';

  @override
  String get migrationMobileRetryAutomatically => 'Vizor 将自动重试。';

  @override
  String get migrationMobileSavedTxError => '无法重新打开两笔已保存的交易。';

  @override
  String get migrationMobileScheduleChange => '找零';

  @override
  String migrationMobileScheduleConfirming(int count, int target) {
    return '确认中 $count/$target';
  }

  @override
  String get migrationMobileScheduleDuration => '持续时间';

  @override
  String get migrationMobileScheduleLoading => '正在加载迁移时间表';

  @override
  String get migrationMobileScheduleMigrating => '迁移中…';

  @override
  String get migrationMobileScheduleMigrationNote => '迁移票据';

  @override
  String get migrationMobileScheduleNextRound => '下一轮';

  @override
  String migrationMobileScheduleOf(int current, int total) {
    return '$current / $total';
  }

  @override
  String get migrationMobileScheduleOverdue => '已逾期';

  @override
  String get migrationMobileSchedulePreparationProgress => '准备进度';

  @override
  String get migrationMobileScheduleReadyIn => '准备就绪还需';

  @override
  String get migrationMobileScheduleReturn => '返回';

  @override
  String migrationMobileScheduleRound(int round) {
    return '第 $round 轮';
  }

  @override
  String get migrationMobileScheduleRoundsRemaining => '剩余轮次';

  @override
  String get migrationMobileScheduleSpendable => 'Ironwood 可花费';

  @override
  String migrationMobileScheduleSplitRound(int round) {
    return '第 $round 轮拆分';
  }

  @override
  String get migrationMobileScheduleUnavailableBody =>
      'Vizor 无法加载最新时间表。你已保存的迁移状态保持不变。';

  @override
  String get migrationMobileSpendableBalance => '当前可花费余额';

  @override
  String get migrationMobileStartErrorFallback => '准备好后请重试。';

  @override
  String get migrationMobileStartErrorTitle => '无法准备你的迁移';

  @override
  String get migrationMobileStartLoadingBody => 'Vizor 正在准备你的迁移。这可能需要一点时间。';

  @override
  String get migrationMobileStartMessageOrganizing => '正在整理迁移批次...';

  @override
  String get migrationMobileStartMessagePreparing => '正在准备你的迁移...';

  @override
  String get migrationMobileStartReadyBody => '继续以使用 Keystone 一并签署准备交易和迁移批次。';

  @override
  String migrationMobileStatusNotesCount(int count) {
    return '$count 个票据';
  }

  @override
  String get migrationMobileStatusNotesLead => 'Migration ';

  @override
  String migrationMobileStatusNotesTitle(String notes) {
    return '迁移 $notes';
  }

  @override
  String get migrationMobileSyncingProgress => '正在同步迁移进度。';

  @override
  String get migrationMobileTimingUpdating => '时间正在更新';

  @override
  String get migrationMobileViewSchedule => '查看时间表';

  @override
  String get migrationMobileWaitAutoStart => '票据拆分完成后，迁移将自动开始。';

  @override
  String migrationMobileWaitBlocks(int count, int target) {
    return '$count/$target 个区块';
  }

  @override
  String get migrationMobileWaitConfirmation => '等待确认';

  @override
  String get migrationMobileWaitKeystoneAgain => '这些确认完成后，还需要再次在 Keystone 上批准。';

  @override
  String get migrationMobileWaitLoopBatch => ' the batch of transactions';

  @override
  String get migrationMobileWaitLoopCaption => '需重复多次，\n等待可能需要 2–10\n小时';

  @override
  String get migrationMobileWaitLoopForWindow => ' for the window';

  @override
  String get migrationMobileWaitLoopSign => '签署';

  @override
  String migrationMobileWaitLoopSignLine(String highlight) {
    return '$highlight该批交易';
  }

  @override
  String get migrationMobileWaitLoopWait => '等待';

  @override
  String migrationMobileWaitLoopWaitLine(String highlight) {
    return '$highlight窗口';
  }

  @override
  String get migrationMobileWaitNoteSplit => '票据拆分';

  @override
  String get migrationMobileWaitSafeBlock => '正在等待安全区块以继续。';

  @override
  String migrationMobileWaitSplitInto(int count) {
    return '将票据拆分为 $count 个迁移部分';
  }

  @override
  String get migrationNextActionDetailAllNotesCompleted => '所有票据已完成';

  @override
  String get migrationNextActionDetailAt => '区块高度';

  @override
  String get migrationNextActionDetailExpectedAt => '预计区块高度';

  @override
  String get migrationNextActionDetailPreparing => '正在准备迁移';

  @override
  String get migrationNextActionDetailReadyToSign => '待签名';

  @override
  String get migrationNextActionDetailSendingNow => '正在发送';

  @override
  String get migrationNextActionDetailWaitingForConfirmations => '等待确认';

  @override
  String get migrationNextActionLabelAwaitingMining => '等待打包';

  @override
  String get migrationNextActionLabelComplete => '迁移完成';

  @override
  String get migrationNextActionLabelFinalizing => '正在完成迁移';

  @override
  String get migrationNextActionLabelNext => '下一次迁移';

  @override
  String get migrationNextActionLabelNextWindow => '下一个迁移窗口';

  @override
  String get migrationNextActionLabelOpeningWindow => '正在开启迁移窗口';

  @override
  String get migrationNextActionLabelSending => '正在发送迁移';

  @override
  String get migrationNextActionLabelWindowReady => '迁移窗口已就绪';

  @override
  String get migrationNotScheduled => '未安排';

  @override
  String migrationNotesAwaitingConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个票据等待确认',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesBroadcast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已广播 $count 个票据',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '剩余 $count 个票据',
    );
    return '$_temp0';
  }

  @override
  String get migrationOptionImmediate => '即时';

  @override
  String get migrationOptionImmediateBody => '一次性迁移全部余额。速度快，但隐私性较低。';

  @override
  String get migrationOptionPrivate => '私密';

  @override
  String get migrationOptionPrivateBody => '将交易拆分为多个部分以尽量降低可追踪性，但耗时更长。';

  @override
  String get migrationOptionPrivateLedger => 'Ledger 账户不可用。';

  @override
  String get migrationOptionRecommended => '推荐';

  @override
  String get migrationOptionsBody => '请选择随时间推移获得更高隐私，还是更快完成迁移。在资金转移前，你可以先查看详情。';

  @override
  String migrationOptionsBodyMoveRest(String amount) {
    return '$amount ZEC 仍在 Orchard 中。请选择随时间推移获得更高隐私，还是更快完成迁移。';
  }

  @override
  String get migrationOptionsSelectReview => '选择并查看';

  @override
  String get migrationOptionsTitle => '选择迁移方式';

  @override
  String get migrationOptionsTitleMoveRest => '如何迁移剩余部分';

  @override
  String migrationOverallProgress(String completed, String total) {
    return '已完成 $completed/$total';
  }

  @override
  String migrationPlannedBatches(String count) {
    return '计划批次 $count 个';
  }

  @override
  String get migrationPoolIronwood => 'Ironwood 资金池';

  @override
  String get migrationPoolLegacy => '（旧版）';

  @override
  String get migrationPoolOrchard => 'Orchard 资金池';

  @override
  String migrationPreparationConfirmations(String confirmed, String target) {
    return '已确认 $confirmed/$target';
  }

  @override
  String migrationPreparationSplitProgress(String current, String total) {
    return '正在准备第 $current/$total 笔拆分';
  }

  @override
  String migrationPreparationSplitStep(String current, String total) {
    return '拆分 $current/$total';
  }

  @override
  String get migrationPreparationSplitTransactions => '正在准备拆分交易';

  @override
  String get migrationPreparationTipDelay => '准备完成后，迁移会在一段刻意设置的较长延迟后自动开始。';

  @override
  String get migrationPreparationTipOrganizing =>
      '我们正在把你的余额整理成常见大小的部分，这样迁移更难被关联。';

  @override
  String get migrationPreparationTipRounds => '根据你的余额，可能需要进行多轮票据拆分。';

  @override
  String get migrationPreparingBatch => '正在准备批次...';

  @override
  String get migrationPrivacyLockDescription => '由于 10 分钟无操作，我们已自动锁定 Vizor。';

  @override
  String migrationProgressTipBlockTime(String seconds) {
    return '每个 Zcash 区块大约需要 $seconds 秒生成，但实际时间会随网络状况而变化。';
  }

  @override
  String get migrationProgressTipClose => '你可以随时关闭 Vizor。迁移会暂停，返回后可以重新开始。';

  @override
  String get migrationProgressTipKeepRunning => '保持 Vizor 运行，迁移会在后台自动进行。';

  @override
  String get migrationReadyNow => '现在可以开始';

  @override
  String get migrationRetryMigration => '重试迁移';

  @override
  String get migrationRetrying => '正在重试...';

  @override
  String get migrationReviewAmountToMigrate => '待迁移金额';

  @override
  String get migrationReviewAnalyzeErrorTitle => '无法分析此余额';

  @override
  String get migrationReviewCompleteIn => '迁移完成时间';

  @override
  String get migrationReviewKeepRunningBody => '应用最小化时准备仍会继续，之后迁移会自动开始。';

  @override
  String get migrationReviewKeepRunningTitle => '请保持 Vizor 运行';

  @override
  String get migrationReviewStart => '开始迁移';

  @override
  String get migrationReviewStarting => '正在开始…';

  @override
  String get migrationRingAllSplitsCompleted => '所有拆分已完成';

  @override
  String get migrationRingConfirmingSplit => '正在确认拆分';

  @override
  String get migrationRingNextSplit => '下一次拆分';

  @override
  String get migrationRingPreparationComplete => '准备完成';

  @override
  String get migrationRingPreparingSchedule => '正在准备时间表';

  @override
  String get migrationRingScheduled => '已安排';

  @override
  String get migrationRingSplitInProgress => '拆分进行中';

  @override
  String get migrationRingStatusCompleted => '已完成';

  @override
  String get migrationRingStatusConfirming => '确认中';

  @override
  String get migrationRingStatusMigrating => '迁移中';

  @override
  String get migrationRingStatusNeedsInput => '需要签名';

  @override
  String get migrationRingStatusNotStarted => '未开始';

  @override
  String get migrationRingStatusPreparing => '准备中';

  @override
  String get migrationRingStatusScheduled => '已安排';

  @override
  String get migrationRingWaitingForBlock => '等待区块';

  @override
  String get migrationRingWaitingForPreviousSplit => '等待上一次拆分';

  @override
  String get migrationRouteNotAvailable => '此账户无法使用迁移。';

  @override
  String get migrationRouteNotNeeded => '此账户无需迁移。';

  @override
  String get migrationRouteStatusFailed => '无法确认迁移状态。';

  @override
  String get migrationRouteSyncFailed => '同步未能完成。请在 Vizor 同步后重试。';

  @override
  String get migrationScheduleBroadcasting => '广播中';

  @override
  String get migrationScheduleCalculating => '计算中';

  @override
  String migrationScheduleCompletedAtBlock(String height) {
    return '已在区块 $height 完成';
  }

  @override
  String migrationScheduleConfirmingProgress(String count, String target) {
    return '确认中 $count/$target';
  }

  @override
  String get migrationScheduleCurrentRound => '当前轮次';

  @override
  String migrationScheduleExpected(String height) {
    return '预计 #$height';
  }

  @override
  String get migrationScheduleOutputChange => '留在 Orchard 中';

  @override
  String migrationScheduleOutputContinuation(String round) {
    return '用于第 $round 轮';
  }

  @override
  String get migrationScheduleOutputMigration => '用于迁移';

  @override
  String get migrationSchedulePending => '时间待定';

  @override
  String get migrationScheduleReadyToMigrate => '迁移就绪时间';

  @override
  String get migrationScheduleRecalculating => '重新计算中';

  @override
  String migrationScheduleRescheduled(String height) {
    return '已重新安排 #$height';
  }

  @override
  String migrationScheduleRoundProgress(String current, String total) {
    return '第 $current/$total 轮';
  }

  @override
  String migrationScheduleScheduledAt(String height) {
    return '已安排 #$height';
  }

  @override
  String migrationScheduleSemanticsAwaiting(String height) {
    return '等待上一次拆分，预计区块 $height';
  }

  @override
  String migrationScheduleSemanticsBroadcast(String height) {
    return '已广播，等待打包，预计在区块 $height 完成';
  }

  @override
  String migrationScheduleSemanticsCompletedAt(String height) {
    return '已在区块 $height 完成';
  }

  @override
  String get migrationScheduleSemanticsDue => '即将发送';

  @override
  String get migrationScheduleSemanticsMigrating => '已广播，等待打包';

  @override
  String migrationScheduleSemanticsNote(
    String number,
    String amount,
    String state,
  ) {
    return '票据 $number，$amount ZEC，$state。';
  }

  @override
  String migrationScheduleSemanticsNoteConfirming(String count, String target) {
    return '确认中，已确认 $count/$target';
  }

  @override
  String migrationScheduleSemanticsNoteConfirmingMined(
    String count,
    String target,
    String height,
  ) {
    return '确认中，已确认 $count/$target，已在区块 $height 打包';
  }

  @override
  String migrationScheduleSemanticsOutput(String amount, String destination) {
    return '$amount ZEC，$destination';
  }

  @override
  String get migrationScheduleSemanticsOutputChange => '留在 Orchard 中';

  @override
  String migrationScheduleSemanticsOutputContinuation(String round) {
    return '用于第 $round 轮';
  }

  @override
  String get migrationScheduleSemanticsOutputMigration => '用于迁移';

  @override
  String migrationScheduleSemanticsOutputs(String outputs) {
    return '输出：$outputs。';
  }

  @override
  String get migrationScheduleSemanticsPending => '时间待定';

  @override
  String get migrationScheduleSemanticsReadyToSign => '可以签名';

  @override
  String migrationScheduleSemanticsRescheduled(String from, String to) {
    return '已从区块 $from 重新安排到区块 $to';
  }

  @override
  String migrationScheduleSemanticsScheduled(String height) {
    return '已安排在区块 $height';
  }

  @override
  String migrationScheduleSemanticsSplit(
    String number,
    String amount,
    String state,
  ) {
    return '拆分 $number，$amount ZEC，$state。';
  }

  @override
  String migrationScheduleSemanticsSplitConfirming(
    String count,
    String target,
    String height,
  ) {
    return '确认中，已确认 $count/$target，预计在区块 $height 完成';
  }

  @override
  String migrationScheduleSemanticsWaitingWindow(String height) {
    return '等待区块 $height 的窗口';
  }

  @override
  String migrationScheduleSplitRound(String number) {
    return '第 $number 轮拆分';
  }

  @override
  String get migrationScheduleTitle => '迁移时间表';

  @override
  String get migrationScheduleTitlePreparation => '准备时间表';

  @override
  String get migrationScheduleUnavailableBody =>
      'Vizor 无法加载最新的迁移时间表。你已保存的迁移状态保持不变。';

  @override
  String get migrationScheduleUnavailableTitle => '无法获取迁移时间表';

  @override
  String get migrationScheduleWaitingToBeMined => '等待打包';

  @override
  String migrationScheduleWindow(String height) {
    return '窗口 #$height';
  }

  @override
  String migrationSemanticsNote(String number, String amount, String status) {
    return '票据 $number：$amount ZEC，$status。';
  }

  @override
  String get migrationSemanticsNotesOrder => '迁移票据按预计处理顺序排列。';

  @override
  String get migrationSemanticsPreparingNotes => '正在准备迁移票据。';

  @override
  String migrationSignBatch(String number) {
    return '签署批次 #$number';
  }

  @override
  String get migrationSignWithKeystone => '使用 Keystone 签名';

  @override
  String get migrationStageFinish => '完成';

  @override
  String get migrationStageMigration => '迁移';

  @override
  String get migrationStagePreparation => '准备';

  @override
  String get migrationStatusAttentionBody =>
      '在完成 Ironwood 过渡之前，Vizor 遇到了可恢复的迁移错误。';

  @override
  String get migrationStatusAttentionFooter => '资金不会丢失。请确认 Vizor 已同步且在线后重试迁移。';

  @override
  String get migrationStatusAttentionTitle => '迁移需要处理';

  @override
  String get migrationStatusBroadcasted => '已广播';

  @override
  String get migrationStatusBroadcastingBody =>
      'Vizor 正在广播已准备好的 Ironwood 迁移交易。';

  @override
  String get migrationStatusCompleteBody => '你的资金已转入 Ironwood 资金池。';

  @override
  String get migrationStatusCompleteFooter => '你可以返回首页继续使用 Vizor。';

  @override
  String get migrationStatusCompleteTitle => '迁移完成';

  @override
  String get migrationStatusConfirmingBody => '迁移交易已广播。Vizor 正在等待网络确认。';

  @override
  String get migrationStatusDefaultBody => 'Vizor 正在跟踪当前的 Ironwood 迁移状态。';

  @override
  String get migrationStatusDefaultButton => '迁移进行中';

  @override
  String get migrationStatusDefaultFooter => '此状态仅在迁移流程接入期间用于诊断显示。';

  @override
  String get migrationStatusDefaultTitle => '迁移状态';

  @override
  String get migrationStatusLeaveFooter => '你可以离开此页面。\n但请保持 Vizor 打开并运行。';

  @override
  String get migrationStatusLedgerUnsupported => '此流程需要批量签名，因此不支持 Ledger 私密迁移。';

  @override
  String get migrationStatusPausedBody => '私密迁移已在下一步之前暂停。';

  @override
  String get migrationStatusPausedButton => '已暂停';

  @override
  String get migrationStatusPausedFooter => '在恢复迁移之前，不会准备新的交易。';

  @override
  String get migrationStatusPausedTitle => '迁移已暂停';

  @override
  String get migrationStatusPendingBroadcasts => '待广播';

  @override
  String get migrationStatusPreparingBody => '每次拆分通常需要约 30 分钟。';

  @override
  String get migrationStatusReadyBody => '私密拆分已就绪。下一步将准备 Ironwood 迁移批次。';

  @override
  String get migrationStatusReadyFooter => '继续迁移，以便在到期时准备并广播 Ironwood 交易。';

  @override
  String get migrationStatusReadyTitle => '可以开始迁移';

  @override
  String get migrationStatusScheduledBody => '你的迁移交易已准备好，正在等待预定的广播时间。';

  @override
  String get migrationStatusScheduledFooter => 'Vizor 打开期间，迁移程序会推进已安排的广播。';

  @override
  String get migrationStatusScheduledTitle => '广播已安排';

  @override
  String get migrationStatusSplitProgress => '拆分进度';

  @override
  String get migrationStatusUnavailableBody =>
      'Vizor 无法确认当前的 Ironwood 迁移状态。在能够检查状态之前，不会开始新的迁移。';

  @override
  String get migrationStatusUnavailableHint =>
      '请返回首页，待同步刷新后重试。如果已有迁移正在进行，Vizor 会在能够读取已保存的状态后继续。';

  @override
  String get migrationStatusUnavailableTitle => '无法获取迁移状态';

  @override
  String get migrationSummaryCurrentBlock => '当前区块';

  @override
  String get migrationSummaryEstCompletion => '预计完成';

  @override
  String get migrationSummaryLeftToMigrate => '待迁移金额';

  @override
  String get migrationSummaryOverallProgress => '总体进度';

  @override
  String migrationTransactionOrdinal(String ordinal) {
    return '交易 $ordinal';
  }

  @override
  String migrationTransactionOrdinalOfTotal(String ordinal, String total) {
    return '交易 $ordinal/$total';
  }

  @override
  String get migrationUpgradeStopBody => '升级前已签名的转账在升级后无法发送。你的资金是安全的。';

  @override
  String get migrationUpgradeStopMoveRemainingLabel => '迁移剩余余额';

  @override
  String get migrationUpgradeStopMovedLabel => '已迁移到 Ironwood';

  @override
  String get migrationUpgradeStopRemainingLabel => '仍在 Orchard 中';

  @override
  String get migrationUpgradeStopRingMessage => '因网络升级\n而中止';

  @override
  String get migrationViewSchedule => '查看时间表';

  @override
  String get nativeBiometricEnableTitle => '启用指纹解锁';

  @override
  String get nativeBiometricUsePasscode => '使用数字密码';

  @override
  String get nativeIronwoodContinueBody => '打开 Vizor 准备下一笔迁移转账。';

  @override
  String get nativeIronwoodContinueTitle => '继续你的 Ironwood 迁移';

  @override
  String get nativeIronwoodNeedsAttentionBody => '打开 Vizor 查看并继续你的迁移。';

  @override
  String get nativeIronwoodNeedsAttentionTitle => 'Ironwood 迁移需要处理';

  @override
  String get nativeLedgerApduArgumentsInvalid => 'Ledger APDU 参数无效。';

  @override
  String get nativeLedgerApduListInvalid => 'Ledger 签名 APDU 列表为空或无效。';

  @override
  String get nativeLedgerAppSwitchTimedOut => '打开 Zcash 应用后，Vizor 无法继续。请重试。';

  @override
  String get nativeLedgerBleUnsupported => '此设备不支持蓝牙 LE。';

  @override
  String get nativeLedgerBleUnsupportedAndroid => '此 Android 设备不支持蓝牙 LE。';

  @override
  String get nativeLedgerBluetoothUnavailable => '蓝牙不可用。';

  @override
  String get nativeLedgerCommunicationFailed => '无法与 Ledger 通信。请重试。';

  @override
  String get nativeLedgerDiscoveryFailed => '无法发现 Ledger 设备。请重试。';

  @override
  String get nativeLedgerInvalidResponse => 'Ledger 返回了无效的响应。';

  @override
  String nativeLedgerOperationFailed(String reason) {
    return 'Ledger 操作失败：$reason';
  }

  @override
  String get nativeLedgerPermissionRequestActive => '已有一个 Ledger 权限请求正在进行。';

  @override
  String get nativeLedgerZcashAppNotInstalled => '此 Ledger 上未安装 Zcash 应用。';

  @override
  String nativeMigrationAccountsNeedAttentionBody(String count) {
    return '$count 个账户需要处理。打开 Vizor 以继续。';
  }

  @override
  String get nativeMigrationNeedsAttentionTitle => '迁移需要处理';

  @override
  String get nativeMigrationStoppedByUpgradeBody => '打开 Vizor 转移剩余余额。';

  @override
  String get nativeMigrationStoppedByUpgradeTitle => '迁移因网络升级而停止';

  @override
  String get nativeMigrationTransfersSentBody => '所有计划的转账都已提交。打开 Vizor 查看状态。';

  @override
  String get nativeMigrationTransfersSentTitle => '迁移转账已发送';

  @override
  String get nativeMigrationUpdatesTitle => '迁移动态';

  @override
  String get nativeOpenToContinue => '打开 Vizor 以继续。';

  @override
  String get nativePrepAccountsChanged => '钱包账户已变更';

  @override
  String nativePrepAccountsReadyBody(String count) {
    return '$count 个账户已可进行下一步。打开 Vizor 以继续。';
  }

  @override
  String get nativePrepCheckingConfirmations => '正在检查交易确认数';

  @override
  String get nativePrepCompleteTitle => '迁移准备已完成';

  @override
  String get nativePrepConfirmedTitle => '准备交易已确认';

  @override
  String get nativePrepOpenToContinueMigration => '打开 Vizor 继续迁移';

  @override
  String get nativePrepOpenToResume => '打开 Vizor 以恢复';

  @override
  String get nativePrepOpenToStartNextStep => '打开 Vizor 开始下一步';

  @override
  String get nativePrepOpenToStartNextStepBody => '打开 Vizor 开始下一步。';

  @override
  String nativePrepProgress(String completed, String total) {
    return '已确认 $completed/$total 笔准备交易';
  }

  @override
  String get nativePrepStoppedTitle => '准备已停止';

  @override
  String get nativePrepTaskTitle => '正在准备迁移';

  @override
  String get nativePrepTrackingPausedBody => '打开 Vizor 以恢复迁移准备。';

  @override
  String get nativePrepTrackingPausedTitle => '准备跟踪已暂停';

  @override
  String get nativePrepUpdatesTitle => '迁移准备动态';

  @override
  String get navActivity => '活动';

  @override
  String get navHome => '首页';

  @override
  String get navPay => '支付';

  @override
  String get navSettings => '设置';

  @override
  String get navSignOut => '退出登录';

  @override
  String get navSwap => '兑换';

  @override
  String get navVote => '投票';

  @override
  String get networkPrivacyFinishUpdateBeforeTorOff => '关闭 Tor 之前，请先完成当前的软件更新。';

  @override
  String get networkPrivacyFinishUpdateBeforeTorOn => '开启 Tor 之前，请先完成当前的软件更新。';

  @override
  String get networkPrivacyTorStartupFailed => '无法连接到 Tor。网络请求已暂停。';

  @override
  String get networkPrivacyTorUpdatesUnavailable =>
      'Tor 已连接，但软件更新不可用。请关闭 Tor 以直接更新。';

  @override
  String get networkPrivacyUpdatesUnavailable => '软件更新不可用。其他网络请求仍使用直接连接。';

  @override
  String get networkSettingsTitle => '网络设置';

  @override
  String get onboardingAdd => '添加';

  @override
  String get onboardingAddBip39PassphraseOptional => '添加 BIP39 密码短语（可选）';

  @override
  String get onboardingAddBip39PassphraseSemantics => '添加 BIP39 密码短语';

  @override
  String get onboardingAddressShieldedBodyMobile =>
      '地址以 u1 开头（旧版为 zs）。\n只有你能看到账户余额和交易记录。';

  @override
  String onboardingAddressShieldedDescription(
    String unifiedPrefix,
    String legacyPrefix,
  ) {
    return '地址以 $unifiedPrefix 开头（旧版为 $legacyPrefix）。只有你能看到账户余额和交易记录。';
  }

  @override
  String get onboardingAddressShieldedTitleMobile => '屏蔽地址';

  @override
  String get onboardingAddressTransparentDescription =>
      '地址以 t 开头，与 Bitcoin 类似，该地址的余额和交易记录对所有人公开可见。';

  @override
  String get onboardingAddressTransparentTitleMobile => '透明地址';

  @override
  String get onboardingAddressTypesSubtitle => 'Zcash 有两种地址类型。\n一种用于隐私，一种用于透明。';

  @override
  String get onboardingAddressTypesSubtitleMobile =>
      'Zcash 有两种地址类型。\n一种用于隐私，一种用于透明。';

  @override
  String get onboardingAddressTypesTitle => 'Zcash 地址类型';

  @override
  String onboardingBiometricEnableFailed(String method) {
    return '无法启用 $method。你可以稍后在设置中重试。';
  }

  @override
  String onboardingBiometricSetUpFirst(String method) {
    return '请先在设备设置中设置 $method。';
  }

  @override
  String get onboardingBiometricSubtitle => '这是一种便捷快速的登录方式。\n你随时可以切换回数字密码。';

  @override
  String onboardingBiometricTitle(String method) {
    return '使用 $method\n解锁你的钱包';
  }

  @override
  String get onboardingBip39PassphraseClear => '清除 BIP39 密码短语';

  @override
  String get onboardingBip39PassphraseExplanation =>
      '添加可选的密码短语（“第 25 个单词”），即可用同一助记词创建/导入另一个独立的钱包。';

  @override
  String get onboardingBip39PassphraseFieldLabel => 'BIP39 密码短语';

  @override
  String get onboardingBip39PassphraseHint => '1–100 个字符';

  @override
  String get onboardingBip39PassphraseTitleOptional => 'BIP39 密码短语（可选）';

  @override
  String get onboardingBirthdayCantRemember => '我不记得了';

  @override
  String get onboardingBirthdayDateHint => 'yyyy/mm/dd';

  @override
  String get onboardingBirthdayDontRemember => '我不记得了';

  @override
  String get onboardingBirthdayEnterBlockHeight => '输入区块高度';

  @override
  String get onboardingBirthdayEnterDate => '输入日期';

  @override
  String get onboardingBirthdayEnterMonth => '输入月份';

  @override
  String get onboardingBirthdayEstimateFailed => '无法估算钱包创建高度。';

  @override
  String onboardingBirthdayHeightAtLeast(String height) {
    return '至少为 $height。';
  }

  @override
  String onboardingBirthdayHeightBetween(String min, String max) {
    return '介于 $min 和 $max 之间。';
  }

  @override
  String get onboardingBirthdayInvalidHeight => '这似乎不是有效的区块高度';

  @override
  String get onboardingBirthdayMetadataFailed => '无法加载钱包创建高度信息。';

  @override
  String get onboardingBirthdayMobileEstimateFailed =>
      '无法估算该日期对应的区块高度。请改为输入区块高度。';

  @override
  String get onboardingBirthdayMonthHint => 'yyyy/mm';

  @override
  String get onboardingBirthdayPickDate => '选择日期';

  @override
  String get onboardingBirthdayPickMonth => '选择月份';

  @override
  String get onboardingBirthdaySelectDate => '选择日期';

  @override
  String get onboardingBirthdaySelectMonth => '选择月份';

  @override
  String get onboardingBirthdayStatusEstimating => '正在估算高度...';

  @override
  String get onboardingBirthdayStatusImporting => '正在导入钱包...';

  @override
  String get onboardingBirthdayStatusPausingSync => '正在暂停同步...';

  @override
  String get onboardingBirthdaySubtitleMobile => '大概时间就够了——\n将从那时开始同步。';

  @override
  String get onboardingBirthdayTitle => '你大约是什么时候创建钱包的？';

  @override
  String get onboardingBlockHeight => '区块高度';

  @override
  String get onboardingBlockHeightRequired =>
      '创建钱包需要当前的 Zcash 区块高度。请检查网络连接后重试。';

  @override
  String get onboardingCheckingAccounts => '正在检查账户...';

  @override
  String get onboardingConnectHardwareSubtitleDesktop => '请选择你的硬件钱包。';

  @override
  String get onboardingConnectHardwareSubtitleMobile => '请选择你的硬件设备。';

  @override
  String get onboardingConnectHardwareTitle => '连接\n硬件钱包';

  @override
  String get onboardingConnectHardwareWallet => '连接硬件钱包';

  @override
  String get onboardingConnectKeystone => '连接 Keystone';

  @override
  String get onboardingContinueAnywayDesktop => '仍然继续';

  @override
  String get onboardingCreatingWallet => '正在创建钱包...';

  @override
  String get onboardingCustomiseAccountSubtitle => '设置账户名称并选择头像，为你的账户增添个性。';

  @override
  String get onboardingDiscoverySubtitle => '请选择要导入的其他账户。';

  @override
  String get onboardingDiscoveryTitle => '发现其他账户';

  @override
  String get onboardingEditBip39Passphrase => '编辑 BIP39 密码短语';

  @override
  String get onboardingEnterPassword => '输入密码';

  @override
  String get onboardingEstimating => '正在估算...';

  @override
  String get onboardingFinishSetup => '完成设置';

  @override
  String get onboardingForgotPasscodeAreYouSure => '确定要继续吗？';

  @override
  String get onboardingForgotPasscodeBody =>
      '如果你记不起数字密码，恢复账户的唯一方法是完全重置 Vizor 应用，这意味着删除所有账户，并需要你重新导入账户。未分享的礼品卡链接将永久丢失。';

  @override
  String get onboardingForgotPasscodeCantBeUndone => '此操作无法撤销。\n';

  @override
  String get onboardingForgotPasscodeContinueToReset => '继续重置 Vizor';

  @override
  String get onboardingForgotPasscodeProceed => '继续操作的后果需由你自行承担。';

  @override
  String get onboardingForgotPasscodeTitle => '忘记数字密码？';

  @override
  String get onboardingForgotPasscodeUnbackedWarning =>
      '如果你没有备份某个账户的助记词，重置 Vizor 后将无法找回该账户的资金。';

  @override
  String get onboardingForgotPassword => '忘记密码？';

  @override
  String get onboardingGiftEducationClosing =>
      '你的钱包已准备就绪。了解 Zcash 如何保护你的隐私，以及应使用哪种地址。';

  @override
  String get onboardingGiftEducationSaveFailed => '无法保存你的进度。请重试。';

  @override
  String get onboardingGoBackDesktop => '返回';

  @override
  String get onboardingHardwareKeystoneOnly => 'Keystone 钱包';

  @override
  String get onboardingHardwareLedgerOrKeystone => 'Ledger 或 Keystone 钱包';

  @override
  String get onboardingIKnowHowToUseZcash => '我已了解 Zcash 用法';

  @override
  String get onboardingImport => '导入';

  @override
  String get onboardingImportAcceptWordCounts => '支持 12、15、18、21 或 24 个单词。';

  @override
  String get onboardingImportCheckFailedError => '无法检查助记词';

  @override
  String get onboardingImportClipboardEmpty => '剪贴板为空';

  @override
  String get onboardingImportClipboardReadError => '无法读取剪贴板';

  @override
  String get onboardingImportEnterManuallySemantics => '手动输入助记词';

  @override
  String get onboardingImportFromKeystone => '从 Keystone 钱包导入';

  @override
  String get onboardingImportFromLedger => '从 Ledger 钱包导入';

  @override
  String get onboardingImportInvalidPhraseError => '助记词无效';

  @override
  String get onboardingImportInvalidSecretPassphrase =>
      '请输入由 12、15、18、21 或 24 个单词组成的有效助记词。';

  @override
  String get onboardingImportManualCardSubtitle => '逐个单词输入。';

  @override
  String get onboardingImportManualCardTitle => '手动输入\n助记词';

  @override
  String get onboardingImportMethodSubtitle => '请选择你想要的方式。';

  @override
  String get onboardingImportMethodTitle => '将账户\n导入 Vizor';

  @override
  String get onboardingImportNoPhraseError => '未找到助记词';

  @override
  String get onboardingImportPasteFromClipboard => '或从剪贴板粘贴';

  @override
  String get onboardingImportPasteHelper => '支持 12、15、18、21 或 24 个单词的\n助记词';

  @override
  String get onboardingImportReadingClipboard => '正在读取剪贴板...';

  @override
  String get onboardingImportSecretPassphrase => '导入助记词';

  @override
  String get onboardingImportSecretPassphraseDescriptionDesktop =>
      'Vizor 或任何其他 Zcash 钱包';

  @override
  String get onboardingImportSecretPassphraseDescriptionMobile =>
      'Vizor、ZODL 或任何其他钱包';

  @override
  String get onboardingImportWalletTitle => '导入钱包';

  @override
  String get onboardingImportWalletTitleMobile => '导入钱包';

  @override
  String get onboardingIntroCard =>
      '与 Bitcoin 或 Ethereum 不同，屏蔽的 Zcash 交易会隐藏发送方、接收方和金额——由密码学验证，而非依赖信任。';

  @override
  String get onboardingIntroClosing => '距离你的第一个隐私钱包只差几步。\n让我们开始设置吧。';

  @override
  String get onboardingIntroClosingMobile => '距离你的第一个隐私钱包只差几步。让我们开始设置吧。';

  @override
  String get onboardingIntroSubtitle => 'Zcash（ZEC）围绕金融隐私与自主托管而构建。';

  @override
  String get onboardingIntroSubtitleMobile => 'Zcash（ZEC）围绕金融隐私\n与自主托管而构建。';

  @override
  String get onboardingIntroTitle => '屏蔽世界';

  @override
  String get onboardingLinkVizorDesktop => '关联 Vizor 桌面版';

  @override
  String get onboardingLinkVizorDesktopDescription => '扫码并连接 Vizor 桌面版';

  @override
  String onboardingLostPasswordBody(String resetAction, String importAction) {
    return '如果你忘记了密码，恢复账户的唯一方法是$resetAction。\n这会删除所有账户和未分享的礼品卡链接。\n你需要$importAction。';
  }

  @override
  String get onboardingLostPasswordImportAction => '重新导入账户';

  @override
  String get onboardingLostPasswordResetAction => '完全重置 Vizor 应用';

  @override
  String onboardingLostPasswordResetCountdown(int seconds) {
    return '$seconds 秒后重置...';
  }

  @override
  String get onboardingLostPasswordTitle => '忘记密码？';

  @override
  String get onboardingManualInvalidWord => '无效的助记词单词。';

  @override
  String get onboardingManualNextWord => '下一个单词';

  @override
  String onboardingManualStoppedAt(String word) {
    return '已在“$word”处停止——它不在助记词单词表中。';
  }

  @override
  String get onboardingManualSubtitle => '支持 12、15、18、21 或 24 个单词';

  @override
  String get onboardingManualTitle => '输入你的助记词';

  @override
  String get onboardingManualUndoLastWord => '撤销上一个单词';

  @override
  String get onboardingNetworkCheckingEndpoint => '正在检查节点…';

  @override
  String get onboardingNetworkEndpointHelper =>
      '请使用适用于此钱包所在网络的 lightwalletd 服务器。';

  @override
  String get onboardingNetworkSaveFailed => '无法保存节点。请重试。';

  @override
  String get onboardingNetworkVerifyFailed => '无法验证该节点。请检查地址后重试。';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingNotNow => '暂不';

  @override
  String get onboardingPasscodeCreateTitle => '创建数字密码';

  @override
  String onboardingPasscodeDigitSemantics(int digit) {
    return '数字 $digit';
  }

  @override
  String get onboardingPasscodeReEnter => '请再次输入数字密码。';

  @override
  String get onboardingPasscodeSettingUp => '正在设置你的钱包...';

  @override
  String get onboardingRandomiseAccountPersona => '随机更换账户名称和头像';

  @override
  String get onboardingRecoveringWallet => '正在恢复钱包...';

  @override
  String get onboardingResetAppFailed => '无法重置应用。请重试。';

  @override
  String get onboardingResumeSetupFailed => '无法继续设置。请重试。';

  @override
  String get onboardingRetrySetup => '重试设置';

  @override
  String get onboardingRetrying => '正在重试';

  @override
  String get onboardingReviewClearSecretPassphrase => '清除助记词';

  @override
  String get onboardingReviewConfirmContinue => '确认并继续';

  @override
  String get onboardingReviewImportSubtitle => '开始导入前\n请检查你的助记词。';

  @override
  String get onboardingReviewImportTitle => '检查导入内容';

  @override
  String get onboardingSavingWallet => '正在保存钱包...';

  @override
  String get onboardingSecretPassphraseAboutToSee => '你即将看到你的助记词。';

  @override
  String get onboardingSecretPassphraseAboutToSeeMobile => '你即将看到\n你的助记词。';

  @override
  String get onboardingSecretPassphraseReveal => '显示助记词';

  @override
  String get onboardingSecretPassphraseRevealMobile => '显示助记词';

  @override
  String get onboardingSecretPassphraseSubtitleDesktop => '你钱包的主密钥。';

  @override
  String get onboardingSecretPassphraseSubtitleMobile => '你钱包的主密钥。';

  @override
  String get onboardingSecretPassphraseWarning =>
      '此助记词是你资金的主密钥。请妥善保管，切勿泄露。一旦丢失，任何人都无法帮你恢复钱包，我们也无能为力。';

  @override
  String get onboardingSeedWordHint => '单词';

  @override
  String get onboardingSetPasswordAndFinish => '设置密码并完成';

  @override
  String get onboardingSetPasswordPlaceholder => '至少 8 个字符，包含符号';

  @override
  String get onboardingSetPasswordSubtitle => '设置用于登录 Vizor 钱包的密码。';

  @override
  String get onboardingSettingPassword => '正在设置密码...';

  @override
  String get onboardingSetupInterrupted => '设置已中断。请重试以恢复你的钱包。';

  @override
  String get onboardingStepAddressTypes => '地址类型';

  @override
  String get onboardingStepImportContacts => '导入联系人';

  @override
  String get onboardingStepIntroToZcash => 'Zcash 简介';

  @override
  String get onboardingStepSetPassword => '设置密码';

  @override
  String get onboardingStepWalletBirthdayHeight => '钱包创建高度';

  @override
  String get onboardingStopSyncing => '正在停止同步...';

  @override
  String get onboardingStorageDbMigrationBody =>
      '打开此版本前，Vizor 需要先更新本地钱包数据库。请重试，或退出后重新启动 Vizor。';

  @override
  String get onboardingStorageDbMigrationTitle => '无法更新钱包数据库';

  @override
  String get onboardingStorageKeyringLockedBody =>
      '打开钱包前，Vizor 需要访问系统密钥环。请解锁密钥环后重试。';

  @override
  String get onboardingStorageRetrySecureStorageFailed => '安全存储仍然不可用。';

  @override
  String get onboardingStorageRetryWalletDbFailed => '钱包数据库更新仍然失败。';

  @override
  String get onboardingStorageSecureStorageLockedBody =>
      '打开钱包前，Vizor 需要访问安全存储。请解锁安全存储后重试。';

  @override
  String get onboardingStorageSecureStorageLockedTitle => '安全存储已锁定';

  @override
  String get onboardingStorageStartupFailureBody =>
      'Vizor 无法加载本地启动状态。请重试，或退出后重新启动 Vizor。';

  @override
  String get onboardingStorageStartupFailureDetail => 'Vizor 无法加载其启动状态。';

  @override
  String get onboardingTellMeHowZcashWorks => '了解 Zcash 如何运作';

  @override
  String get onboardingThingsKeepPrivacyBody =>
      '部分交易所无法向屏蔽地址转账。如果从交易所提现，请使用你的透明地址，ZEC 到账后再进行屏蔽。';

  @override
  String get onboardingThingsKeepPrivacyTitle => '如何保持隐私';

  @override
  String get onboardingThingsSubtitleMobile => '开始之前请了解以下内容。';

  @override
  String get onboardingThingsTimeToSyncBody =>
      '你的钱包直接与 Zcash 网络同步，而不依赖服务器。这样可以保护你的隐私，但需要一点时间。应用同步期间，你的资金是安全的。';

  @override
  String get onboardingThingsTimeToSyncTitle => '同步时间';

  @override
  String get onboardingThingsToKnow => '须知';

  @override
  String get onboardingUnknownHeightBody =>
      '如果在没有钱包创建高度的情况下继续，Vizor 将从受支持的最早屏蔽高度开始扫描。这是安全的，但首次同步可能需要很长时间。';

  @override
  String get onboardingUnknownHeightHint => '即使只选一个大概的日期，速度也会快得多。';

  @override
  String get onboardingUnknownHeightTitle => '从最早的区块高度开始导入吗？';

  @override
  String get onboardingUnlockBiometricReason => '解锁你的钱包';

  @override
  String get onboardingUnlockDescription => '输入密码以打开 Vizor。';

  @override
  String get onboardingUnlockEnterPasscode => '输入数字密码以打开 Vizor';

  @override
  String get onboardingUnlockIncorrectPassword => '密码不正确。请重试。';

  @override
  String get onboardingUnlockOpenFailed => '无法打开你的钱包。请重试。';

  @override
  String get onboardingUnlockOpening => '正在打开你的钱包...';

  @override
  String get onboardingUnlockWelcomeBack => '欢迎回来';

  @override
  String get onboardingWelcome => '欢迎页';

  @override
  String get onboardingWelcomeActivateGiftCard => '激活礼品卡';

  @override
  String get onboardingWelcomeGetStarted => '开始使用';

  @override
  String get onboardingWelcomeImportWallet => '导入钱包';

  @override
  String get passcodeConfirmTitle => '确认数字密码';

  @override
  String get passcodeIncorrect => '数字密码不正确';

  @override
  String get passcodeSixDigits => '6 位数字';

  @override
  String get passcodesDidNotMatch => '两次输入的数字密码不一致。请重试。';

  @override
  String get passwordCheckFailed => '无法验证你的密码，请重试。';

  @override
  String get passwordConfirmLabel => '确认密码';

  @override
  String get passwordIncorrect => '密码不正确，请重试。';

  @override
  String get passwordLabel => '密码';

  @override
  String get passwordPolicyAscii => '仅可使用英文字母、数字和符号。';

  @override
  String passwordPolicyMinLength(int min) {
    return '密码至少需要 $min 个字符。';
  }

  @override
  String get passwordPolicyMustDiffer => '请使用不同的密码。';

  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致。';

  @override
  String get payAddToContacts => '添加到联系人';

  @override
  String payAddressSemantics(String address) {
    return '地址 $address';
  }

  @override
  String get payAmountChooseAsset => '选择支付资产';

  @override
  String payAmountEnterIn(String symbol) {
    return '以 $symbol 输入金额';
  }

  @override
  String get payAmountEstimated => '预估：';

  @override
  String get payAmountEstimatedSpend => '预估支出';

  @override
  String get payAmountPayingFrom => '从你的';

  @override
  String get payAmountPayingIn => '支付币种';

  @override
  String get payBackHome => '首页';

  @override
  String get payFetchingQuote => '正在获取报价';

  @override
  String get payNewAddressDetected => '检测到新地址。';

  @override
  String get payNewAddressWarning => '你之前未与此地址交互过。';

  @override
  String payRecentDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String payRecentHoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String payRecentMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String get payRecentlySent => '最近发送';

  @override
  String get payRecents => '最近';

  @override
  String get payRecipientAddressHint => '粘贴地址或扫描二维码';

  @override
  String get payRecipientAddressLabel => '收款地址';

  @override
  String get payRefreshingQuote => '正在刷新报价';

  @override
  String get payReviewConfirmPay => '确认并支付';

  @override
  String get payReviewConvertedAmount => '兑换金额';

  @override
  String get payReviewPaying => '支付金额';

  @override
  String get payReviewQuoteExpired => '报价已过期';

  @override
  String get payReviewQuoteExpiresIn => '报价剩余有效时间 ';

  @override
  String get payReviewRefreshQuote => '刷新报价';

  @override
  String get payReviewRefreshTheQuote => '刷新报价';

  @override
  String get payReviewReturnToPay => '返回支付';

  @override
  String get payReviewUnknownAddress => '未知地址';

  @override
  String get paySaveContactError => '无法保存此联系人。请重试。';

  @override
  String get payScanBarrierDismiss => '关闭';

  @override
  String get payScanCaption => '扫描收款地址二维码';

  @override
  String get payScanPermissionTitle => '扫描收款地址';

  @override
  String get payScanQrSubtitle => '使用相机扫描地址';

  @override
  String get payScanQrTitle => '扫描二维码';

  @override
  String get paySelectRecipient => '选择收款方';

  @override
  String get payStepRecipient => '收款方';

  @override
  String get payStepReview => '确认';

  @override
  String get paySubmittedFailedBody => '无法提交支付。请重试。';

  @override
  String get paySubmittedGoToActivity => '前往活动记录';

  @override
  String get paySubmittedStatusUncertainNotice => '支付状态不确定。重试之前请先查看活动记录。';

  @override
  String get paySubmittedSubmittingBody => '正在将你的支付提交到网络...';

  @override
  String get paySubmittedSubmittingTitle => '正在提交支付...';

  @override
  String get paySubmittedSucceededBody => '很快将在链上确认。\n可在活动记录中跟踪。';

  @override
  String get paySubmittedSucceededTitle => '支付\n已提交';

  @override
  String get paySubmittedUnavailableNotice => '无法加载此支付。请在活动记录中查看最新状态。';

  @override
  String get paySubmittedUnavailableTitle => '支付不可用';

  @override
  String get paySubmittedUncertainTitle => '支付状态\n不确定';

  @override
  String payTitleAmount(String symbol) {
    return '使用 $symbol 支付';
  }

  @override
  String get paymentLinkAboveMaximumZec => '超过你的最大 ZEC 额度';

  @override
  String get paymentLinkAccountChangedRedeemAgain =>
      '当前账户已更改。请重新领取此礼品卡，以便在新账户中接收。';

  @override
  String get paymentLinkAccountChangedReviewAmount => '当前账户已更改。请重新检查礼品卡金额和手续费。';

  @override
  String get paymentLinkActiveAccountChangedReviewAmount => '当前账户已更改。请检查金额后重试。';

  @override
  String get paymentLinkAlmostReadyHeading => '礼品卡\n即将准备好！';

  @override
  String get paymentLinkAlmostReadyReceivedHeading => '你的礼品卡\n即将准备好！';

  @override
  String paymentLinkAmountCurrencyDisabledSemantic(
    String currency,
    String reason,
  ) {
    return '以 $currency 输入金额。$reason';
  }

  @override
  String get paymentLinkAmountEnterDollars => '输入美元金额';

  @override
  String get paymentLinkAmountInputSemantic => '礼品卡金额输入';

  @override
  String get paymentLinkAmountStepSubtitleDesktop => '输入金额并选择设计。';

  @override
  String get paymentLinkAmountStepSubtitleMobile => '输入金额并选择设计。';

  @override
  String get paymentLinkApproveAndCreate => '确认并创建';

  @override
  String paymentLinkArchivedCount(int count) {
    return '已归档（$count）';
  }

  @override
  String get paymentLinkArchivedHeading => '已归档';

  @override
  String get paymentLinkArtworkChestCave => '水晶洞穴中的宝箱';

  @override
  String get paymentLinkArtworkChestLava => '熔岩洞穴中的宝箱';

  @override
  String get paymentLinkArtworkCoin => 'Zcash 硬币';

  @override
  String get paymentLinkArtworkCrystal => '水晶';

  @override
  String get paymentLinkArtworkDiamond => '钻石';

  @override
  String get paymentLinkArtworkDragon => '巨龙';

  @override
  String get paymentLinkArtworkGift => '礼盒';

  @override
  String get paymentLinkArtworkKnightMagic => '魔法骑士';

  @override
  String get paymentLinkArtworkRogueCat => '盗贼猫';

  @override
  String get paymentLinkArtworkRuby => '红宝石';

  @override
  String get paymentLinkAvailabilityCheckingDescription => '领取结果尚未确认。请稍后再查看。';

  @override
  String get paymentLinkAvailabilityCheckingResult => '正在检查结果';

  @override
  String get paymentLinkAvailabilityClaim => '领取';

  @override
  String get paymentLinkAvailabilityClaimFailed => '领取失败';

  @override
  String get paymentLinkAvailabilityFailedDescription => '领取未完成。重试前请先检查卡片。';

  @override
  String get paymentLinkAvailabilityNoBalance => '无余额';

  @override
  String get paymentLinkAvailabilityNoBalanceDescription => '目前没有可领取的余额。';

  @override
  String get paymentLinkAvailabilityReadyDescription => '此礼品卡可以领取。';

  @override
  String get paymentLinkAvailabilityRejectedDescription =>
      '网络未接受此次领取。重试前请先检查其状态。';

  @override
  String get paymentLinkBackToGiftCard => '返回礼品卡';

  @override
  String get paymentLinkBatchAddCard => '增加一张卡片';

  @override
  String get paymentLinkBatchCardsInGroup => '此组中的卡片';

  @override
  String get paymentLinkBatchCheckFailed => '无法检查所有卡片';

  @override
  String get paymentLinkBatchCheckingUse => '正在检查卡片使用情况…';

  @override
  String get paymentLinkBatchChooseLocation => '选择位置';

  @override
  String paymentLinkBatchCopyLinkSemantic(String number) {
    return '复制卡片 $number 的链接';
  }

  @override
  String paymentLinkBatchCountSemantic(int max) {
    return '卡片数量，2 至 $max';
  }

  @override
  String paymentLinkBatchCreated(String date) {
    return '创建于 $date';
  }

  @override
  String get paymentLinkBatchDetailsNotSaved => '无法保存卡片详情。请重试。';

  @override
  String get paymentLinkBatchFeeChanged => '网络手续费已变化。请检查新的总额。';

  @override
  String get paymentLinkBatchFundedNotSaved => '充值已发送，但无法保存卡片。关闭 Vizor 前请重试。';

  @override
  String paymentLinkBatchGiftCardsCount(int count) {
    return '$count 张礼品卡';
  }

  @override
  String get paymentLinkBatchLinksShareableLater => '付款确认后即可分享链接。';

  @override
  String get paymentLinkBatchMessageOptional => '留言（可选）';

  @override
  String get paymentLinkBatchMessageOptionalEveryCard => '留言（可选），会显示在每张卡片上';

  @override
  String get paymentLinkBatchNoneFunded => '没有卡片完成充值。请检查金额后重试。';

  @override
  String get paymentLinkBatchNotAllReady => '此卡片组中并非所有卡片都已就绪。在全部就绪之前，请勿分享任何链接。';

  @override
  String get paymentLinkBatchOverBalance => '请减少金额或卡片数量，以符合你的可用余额。';

  @override
  String get paymentLinkBatchPaymentUnconfirmed =>
      'Vizor 尚未确认付款已发送。请保留这些卡片，并在分享任何链接前再次检查。';

  @override
  String get paymentLinkBatchPrepareFailed => '无法准备这些卡片。';

  @override
  String get paymentLinkBatchPreviousAccount => '这些卡片是在上一个账户下创建的。请切换回去查看。';

  @override
  String get paymentLinkBatchQuoteNotReady => '可用余额仍在加载。请在钱包同步后重试。';

  @override
  String get paymentLinkBatchRemoveCard => '减少一张卡片';

  @override
  String paymentLinkBatchRowSemantic(
    String number,
    String status,
    String failed,
  ) {
    String _temp0 = intl.Intl.selectLogic(failed, {
      'true': '，更新失败',
      'other': '',
    });
    return '卡片 $number，$status$_temp0';
  }

  @override
  String paymentLinkBatchRowTitle(String number) {
    return '卡片 $number';
  }

  @override
  String get paymentLinkBatchRowUpdateFailed => '无法更新';

  @override
  String get paymentLinkBatchSaveAllCsv => '将所有链接保存为 CSV';

  @override
  String get paymentLinkBatchSaveLinksTitle => '保存礼品卡链接';

  @override
  String get paymentLinkBatchSaveLinksWarning =>
      '任何拥有此文件的人都可以领取这些卡片。请将其保存在私密位置。';

  @override
  String paymentLinkBatchShowQrSemantic(String number) {
    return '显示卡片 $number 的二维码';
  }

  @override
  String get paymentLinkBatchUncertain =>
      'Vizor 无法确认付款是否已发送。创建其他卡片组前，请先在礼品卡中检查此卡片组。';

  @override
  String get paymentLinkBatchUseNotChecked => '尚未检查卡片使用情况';

  @override
  String get paymentLinkBulkAmountPerCard => '每张卡片金额';

  @override
  String get paymentLinkBulkBalanceLoading => '正在加载余额';

  @override
  String get paymentLinkBulkCardDesign => '卡片设计';

  @override
  String paymentLinkBulkCountSemantic(int count) {
    return '$count 张卡片';
  }

  @override
  String paymentLinkBulkCreateCards(int count) {
    return '创建 $count 张卡片';
  }

  @override
  String get paymentLinkBulkCreateMultiple => '创建多张卡片';

  @override
  String get paymentLinkBulkDifferentDesign => '每张卡片使用不同设计';

  @override
  String get paymentLinkBulkEditCards => '编辑卡片';

  @override
  String paymentLinkBulkLedgerLimit(int max) {
    return '使用 Ledger 一次最多可创建 $max 张卡片。';
  }

  @override
  String paymentLinkBulkReviewCards(int count) {
    return '检查 $count 张卡片';
  }

  @override
  String paymentLinkBulkZecAvailable(String amount) {
    return '可用 $amount ZEC';
  }

  @override
  String get paymentLinkCardAmountLabel => '卡片金额';

  @override
  String get paymentLinkCardBalanceCheckFailed => '无法检查卡片余额。请重试。';

  @override
  String paymentLinkCardDesignSemantic(String design) {
    return '$design卡片设计';
  }

  @override
  String get paymentLinkCardFeeHelpText => '包含创建手续费和为领取预留的手续费。';

  @override
  String get paymentLinkCardFeeLabel => '卡片手续费（充值 + 领取）';

  @override
  String get paymentLinkCardRemoveFailed => '无法移除卡片。请重试。';

  @override
  String get paymentLinkCardStatusCheckFailed => '无法检查卡片状态。请重试。';

  @override
  String get paymentLinkCardUnreadable => '无法读取此卡片。';

  @override
  String get paymentLinkCardUpdateFailed => '无法更新卡片。请重试。';

  @override
  String get paymentLinkCardsLoadFailed => '无法加载礼品卡。';

  @override
  String paymentLinkCheckProgress(String phase, String percent) {
    String _temp0 = intl.Intl.selectLogic(phase, {
      'finding': '正在查找礼物',
      'other': '正在检查礼物',
    });
    return '$_temp0… $percent%';
  }

  @override
  String get paymentLinkCheckStatus => '检查状态';

  @override
  String paymentLinkCheckedHoursAgo(int hours) {
    return '$hours 小时前检查';
  }

  @override
  String get paymentLinkCheckedJustNow => '刚刚检查';

  @override
  String paymentLinkCheckedMinutesAgo(int minutes) {
    return '$minutes 分钟前检查';
  }

  @override
  String paymentLinkCheckedOnDate(String date) {
    return '检查于 $date';
  }

  @override
  String get paymentLinkCheckingGiftEllipsis => '正在检查礼物…';

  @override
  String get paymentLinkCheckingGiftFull => '正在检查礼物… 100%';

  @override
  String get paymentLinkChooseReceivingAccount => '选择接收账户';

  @override
  String get paymentLinkClaimAccountPrepareFailed => '无法准备这份礼物。请重试或选择其他账户。';

  @override
  String get paymentLinkClaimActionCreateAccount => '创建账户并领取';

  @override
  String get paymentLinkClaimActionCreateWallet => '创建钱包并领取';

  @override
  String get paymentLinkClaimActionExistingWallet => '使用已有钱包领取';

  @override
  String get paymentLinkClaimCheckingDescription => '正在检查这张礼品卡\n是否已被领取。';

  @override
  String get paymentLinkClaimCheckingHeading => '正在检查\n你的礼品卡';

  @override
  String get paymentLinkClaimFailedMaybePending => '礼品卡领取失败。它可能仍在等待确认，或已被使用。';

  @override
  String get paymentLinkClaimFailureToast => '无法领取你的礼品卡。';

  @override
  String get paymentLinkClaimGiftButton => '领取礼物';

  @override
  String get paymentLinkClaimQueueFull => '等待中的礼品卡过多。请先完成另一张卡片。';

  @override
  String get paymentLinkClaimResultNotConfirmed => '领取结果尚未确认。请检查其状态。';

  @override
  String get paymentLinkClaimSaveFailed => '无法保存卡片。请重试。';

  @override
  String get paymentLinkClaimStatusAlreadyClaimed => '这份礼物已被领取。';

  @override
  String get paymentLinkClaimStatusAskSender => '请向发送者索取新的礼品卡。';

  @override
  String get paymentLinkClaimStatusCheckConnection => '请检查网络连接后重试。';

  @override
  String get paymentLinkClaimStatusCreateAccountNow => '现在可以创建你的账户。';

  @override
  String get paymentLinkClaimStatusCreateAccountOrUseOne => '创建账户或使用已有账户即可领取。';

  @override
  String get paymentLinkClaimStatusCreateWalletNow => '现在可以创建你的钱包。';

  @override
  String get paymentLinkClaimStatusCreateWalletOrUseOne => '创建钱包或使用已有钱包即可领取。';

  @override
  String get paymentLinkClaimStatusGiftFound => '找到礼物';

  @override
  String get paymentLinkClaimStatusMayNotBeFunded => '发送者可能尚未充值。';

  @override
  String get paymentLinkClaimStatusNetworkUnreachable => '无法连接到网络。';

  @override
  String get paymentLinkClaimStatusOtherNetwork => '此礼品卡适用于其他网络。';

  @override
  String paymentLinkClaimStatusWaitingDeposit(int count, int target) {
    return '等待充值确认 · $count/$target';
  }

  @override
  String get paymentLinkClaimSubmitted => '礼物领取已提交';

  @override
  String get paymentLinkClaimTheGift => '领取礼物';

  @override
  String get paymentLinkClaimTheGiftCard => '领取礼品卡';

  @override
  String get paymentLinkClaimWaitingDescription => '礼物马上就可以领取。';

  @override
  String get paymentLinkClaimedElsewhereDescription =>
      '此卡已先在另一个钱包中领取。你的余额没有变化。';

  @override
  String get paymentLinkClaimedElsewhereLabel => '已在别处领取';

  @override
  String get paymentLinkClaiming => '正在领取…';

  @override
  String get paymentLinkClearClipboardLabel => '清除剪贴板';

  @override
  String get paymentLinkClickToRevealMessage => '点击卡片即可查看留言。';

  @override
  String get paymentLinkClickToRevealShort => '点击卡片即可查看';

  @override
  String get paymentLinkConfirmGiftCardTitle => '确认礼品卡';

  @override
  String get paymentLinkCopyLinkAgainHint => '你可以在“设置 → 我的礼品卡”中再次复制此链接。';

  @override
  String get paymentLinkCopyLinkSemanticLabel => '复制礼品卡链接';

  @override
  String get paymentLinkCopying => '正在复制…';

  @override
  String get paymentLinkCostAdditionalZecNeeded => '还需要的 ZEC';

  @override
  String paymentLinkCostAtLeast(String amount) {
    return '至少 $amount';
  }

  @override
  String get paymentLinkCostCalculatingFee => '正在计算网络手续费';

  @override
  String paymentLinkCostCardsMultiplier(int count) {
    return '× $count 张卡片';
  }

  @override
  String get paymentLinkCostMessageOnEveryCard => '每张卡片上的留言';

  @override
  String get paymentLinkCostPerCard => '每张卡片';

  @override
  String paymentLinkCostPerCardBreakdown(String amount, String fee) {
    return '$amount ZEC + 领取手续费 $fee ZEC';
  }

  @override
  String get paymentLinkCostWaitingForSync => '等待同步';

  @override
  String get paymentLinkCostYouWillSpend => '你将花费';

  @override
  String get paymentLinkCreateCardButton => '创建卡片';

  @override
  String get paymentLinkCreateCardLabel => '创建礼品卡';

  @override
  String get paymentLinkCreateGiftCardTitle => '创建礼品卡';

  @override
  String get paymentLinkCreateNewCard => '创建新卡片';

  @override
  String get paymentLinkCreationFailed => '创建礼品卡失败。请重试。';

  @override
  String get paymentLinkDeleteMessageSemantic => '删除礼品卡留言';

  @override
  String get paymentLinkEmptyTitle => '还没有礼品卡';

  @override
  String get paymentLinkEnterValidAmount => '请输入有效的礼品卡金额。';

  @override
  String get paymentLinkEntryExplainAccountDesktop =>
      '领取卡片后，将在你的钱包中创建一个包含卡片余额的新账户。';

  @override
  String get paymentLinkEntryExplainWalletDesktop =>
      '领取卡片后，我们会创建一个包含卡片余额的新 Vizor 钱包。';

  @override
  String get paymentLinkEntryExplanationAccount => '创建新账户以接收卡片余额。';

  @override
  String get paymentLinkEntryExplanationWallet => '创建新的 Vizor 钱包以接收卡片余额。';

  @override
  String get paymentLinkEntrySubtitle => '复制收到的卡片链接，\n并粘贴到下方。';

  @override
  String get paymentLinkEntryTitleAccount => '领取 Vizor 礼品卡以创建账户';

  @override
  String get paymentLinkEntryTitleWallet => '领取 Vizor 礼品卡以创建钱包';

  @override
  String get paymentLinkExportNotReady => '导出链接前，所有卡片都必须就绪。';

  @override
  String get paymentLinkExportStatusChanged => '账户或卡片状态已更改。请检查卡片后重试。';

  @override
  String get paymentLinkFeeEstimateFailed => '无法估算卡片手续费。请重试。';

  @override
  String get paymentLinkFeeEstimatedAfterSync => '钱包同步完成后将估算卡片手续费。';

  @override
  String get paymentLinkFeeHelpSemantic => '关于礼品卡手续费';

  @override
  String get paymentLinkFeeHelpTextLong => '包含为礼品卡充值的手续费，以及为接收人领取预留的手续费。';

  @override
  String get paymentLinkFeeUpdateFailed => '无法更新卡片手续费。请返回金额步骤后重试。';

  @override
  String get paymentLinkFiatLoadingSemantic => '正在加载法币价值';

  @override
  String get paymentLinkFlipCardSemanticLabel => '翻转礼品卡';

  @override
  String get paymentLinkFundingExpired => '礼品卡充值已过期。请重新创建。';

  @override
  String get paymentLinkFundingIncompleteStatus => '充值未完成';

  @override
  String get paymentLinkFundingNeedsAttention => '礼品卡充值需要处理';

  @override
  String get paymentLinkFundingSentCardNotSaved =>
      '充值已发送，但无法保存礼品卡。关闭 Vizor 前请重试。';

  @override
  String get paymentLinkFundingStillVerifying => '仍在验证充值。Vizor 将继续检查。';

  @override
  String get paymentLinkFundingStorageNeedsSync => '充值已发送，但本地交易存储需要同步。';

  @override
  String get paymentLinkGiftAmountLabel => '礼物金额';

  @override
  String paymentLinkGiftCardDesignSemantic(String design) {
    return '礼品卡，$design设计';
  }

  @override
  String get paymentLinkGiftCardMessageSemantic => '礼品卡留言';

  @override
  String get paymentLinkGiftCardsLowerBreadcrumb => '礼品卡';

  @override
  String get paymentLinkGiftCardsTitle => '礼品卡';

  @override
  String get paymentLinkGiftMessageLabel => '礼物留言';

  @override
  String get paymentLinkGroupConfirmingPayment => '正在确认付款';

  @override
  String get paymentLinkGroupEntryForGroup => '送给多人';

  @override
  String get paymentLinkGroupEntryGroupSemantic => '为多人创建卡片';

  @override
  String paymentLinkGroupEntryLedgerSemantic(int max) {
    return '创建多张卡片，使用 Ledger 最多 $max 张';
  }

  @override
  String get paymentLinkGroupEntryMultipleCards => '多张卡片';

  @override
  String paymentLinkGroupEntryUpToWithLedger(int max) {
    return '使用 Ledger 最多 $max 张';
  }

  @override
  String get paymentLinkGroupNotFunded => '此卡片组未完成充值。请重新创建。';

  @override
  String get paymentLinkGroupOtherAccount => '此卡片组属于其他账户。请切换账户后查看。';

  @override
  String get paymentLinkGroupPaymentPending => '付款状态待确认';

  @override
  String get paymentLinkGroupSomeNotReady => '部分卡片尚未就绪';

  @override
  String get paymentLinkGroupsHeading => '卡片组';

  @override
  String get paymentLinkHideCard => '隐藏卡片';

  @override
  String get paymentLinkHowDesktopStepCreate =>
      '输入赠送金额，选择设计，添加留言（可选），一键创建你的卡片。';

  @override
  String get paymentLinkHowDesktopStepRedeem =>
      '接收人可使用链接在其 Vizor 钱包中领取卡片。发送者承担充值和领取手续费，因此接收人将收到完整的卡片金额。';

  @override
  String get paymentLinkHowDesktopStepShare =>
      '卡片创建后，你会得到一个包含领取密钥的专属链接。请只将其发送给预期的接收人。';

  @override
  String get paymentLinkHowGiftCardsWork => '礼品卡使用说明';

  @override
  String get paymentLinkHowItWorksSubtitle => '庆祝任何时刻的绝佳方式。';

  @override
  String get paymentLinkHowItWorksTitle => '礼品卡使用说明';

  @override
  String get paymentLinkHowStepCreate => '输入金额，选择设计，并可添加留言。';

  @override
  String get paymentLinkHowStepRedeem =>
      '接收人在 Vizor 中打开链接并领取全部卡片金额。发送者承担两笔手续费。';

  @override
  String get paymentLinkHowStepShare => '充值到达网络后，复制专属链接，并且只发送给预期的接收人。';

  @override
  String get paymentLinkHowTheCardWorks => '礼品卡使用说明';

  @override
  String get paymentLinkIntakeCouldNotOpen => '无法打开支付链接。';

  @override
  String get paymentLinkIntakeQueueFull => '等待打开的支付链接过多。';

  @override
  String get paymentLinkInterruptedCheckMessage => '卡片检查已中断。请重试。';

  @override
  String get paymentLinkInvalidSubtitle => '请重新复制链接后再试';

  @override
  String get paymentLinkInvalidTitle => '这个链接看起来不对。';

  @override
  String get paymentLinkKeystoneBroadcastFailed => '无法广播礼品卡充值。';

  @override
  String get paymentLinkKeystoneBroadcastingTitle => '正在广播礼品卡充值';

  @override
  String get paymentLinkKeystoneCreatingGiftCard => '正在创建你的礼品卡…';

  @override
  String get paymentLinkKeystoneFundingUncertain => '充值状态不确定。重试前请先查看活动记录。';

  @override
  String get paymentLinkKeystoneScanCaption => '扫描 Keystone 上的二维码以完成创建';

  @override
  String get paymentLinkKeystoneSignTitle => '在 Keystone 上签署礼品卡';

  @override
  String get paymentLinkKeystoneSigningFailed => '无法完成礼品卡签名。';

  @override
  String get paymentLinkLeaveSaveMany => '离开此页面前，请先保存这些礼品卡。';

  @override
  String get paymentLinkLeaveSaveOne => '离开此页面前，请先保存这张礼品卡。';

  @override
  String get paymentLinkLedgerFundingExpired => '此礼品卡交易已过期或被拒绝。请返回并创建新的礼品卡。';

  @override
  String get paymentLinkLedgerFundingRejected => '已在你的 Ledger 上拒绝礼品卡充值。';

  @override
  String get paymentLinkLedgerSavedForRecovery =>
      '礼品卡充值已保存以便恢复。请重试以检查其状态并完成保存。';

  @override
  String get paymentLinkLinkCopied => '已复制礼品链接';

  @override
  String get paymentLinkLinkCopiedStatusFailed => '已复制礼品链接，但无法更新其状态。';

  @override
  String get paymentLinkLinkCopyFailed => '无法复制礼品链接。';

  @override
  String get paymentLinkLinksSaveFailed => '无法保存礼品卡链接。请重试。';

  @override
  String get paymentLinkLinksSaved => '已保存礼品卡链接';

  @override
  String get paymentLinkLoadingGiftCard => '正在加载礼品卡';

  @override
  String get paymentLinkLongSyncBody =>
      'Vizor 需要扫描比平时更多的历史记录才能验证余额。这样做是安全的，但可能需要很长时间。';

  @override
  String get paymentLinkLongSyncConfirm => '检查礼品卡';

  @override
  String get paymentLinkLongSyncSupporting => '你可以返回，不会开始扫描。';

  @override
  String get paymentLinkLongSyncTitle => '此礼品卡可能需要较长时间';

  @override
  String get paymentLinkMemoOptionalSubtitle => '可附上一条简短的加密备注（可选）。';

  @override
  String get paymentLinkMessageAttachedTitle => '已附上留言。';

  @override
  String get paymentLinkMessageInputSemantic => '礼品卡留言输入';

  @override
  String get paymentLinkMessageStepTitle => '输入留言';

  @override
  String get paymentLinkMessageTooLarge => '留言过长。请尝试减少复杂表情符号。';

  @override
  String get paymentLinkMyCards => '我的卡片';

  @override
  String get paymentLinkNewGiftCardRequired => '需要新的礼品卡';

  @override
  String get paymentLinkNoActiveAccountAvailable => '当前没有可用的账户。';

  @override
  String get paymentLinkNoCreatedCardsText => '还没有创建的卡片。';

  @override
  String get paymentLinkNoReceivedCardsText => '还没有接收的卡片。';

  @override
  String get paymentLinkOpenGroupChecking => '检查中';

  @override
  String paymentLinkOpenGroupCreated(String date) {
    return '创建于 $date';
  }

  @override
  String paymentLinkOpenGroupEach(String amount) {
    return '每张 $amount';
  }

  @override
  String paymentLinkOpenGroupSemantic(int count) {
    return '打开包含 $count 张礼品卡的卡片组';
  }

  @override
  String get paymentLinkPasteLabel => '粘贴卡片链接';

  @override
  String get paymentLinkPrivacyModeOff => '关闭隐私模式';

  @override
  String get paymentLinkPrivacyModeOn => '开启隐私模式';

  @override
  String get paymentLinkQrCardHeading => '你收到了\nZEC';

  @override
  String get paymentLinkQrCardScanToRedeem => '扫码领取';

  @override
  String get paymentLinkQrCardSemantic => '礼品卡二维码';

  @override
  String get paymentLinkQrCouldNotBeGenerated => '无法生成二维码';

  @override
  String get paymentLinkQrSaveFailed => '无法保存礼品卡二维码。';

  @override
  String get paymentLinkQrSaved => '已保存礼品卡二维码';

  @override
  String get paymentLinkQrSavedStatusFailed => '已保存礼品卡二维码，但无法更新其状态。';

  @override
  String get paymentLinkReadyHeading => '已可分享';

  @override
  String get paymentLinkReceiveFinishFailed => '无法完成接收这份礼物。请重试以检查其状态。';

  @override
  String get paymentLinkReceiveToLabel => '接收账户';

  @override
  String get paymentLinkReceivedCardsLoadFailed => '无法加载已接收的礼品卡。';

  @override
  String get paymentLinkReceivedGiftHeading => '你收到了一份礼物！';

  @override
  String get paymentLinkReceivedHeadingDesktop => '你收到了\n一张礼品卡！';

  @override
  String get paymentLinkReceivingAccountChangedReopen => '接收账户已更改。请重新打开礼品卡以继续。';

  @override
  String get paymentLinkReceivingAccountChangedRetry => '接收账户已更改。请重试以检查此礼物。';

  @override
  String get paymentLinkReceivingStatus => '接收中…';

  @override
  String get paymentLinkRedeemCardLabel => '领取礼品卡';

  @override
  String get paymentLinkRedeemCardStepTitle => '领取礼品卡';

  @override
  String get paymentLinkRedeemPasteOrScan => '粘贴卡片链接或扫描其二维码。';

  @override
  String get paymentLinkRedeemSubtitle => '复制收到的卡片链接，并粘贴到下方。';

  @override
  String get paymentLinkRedeemTheCardTitle => '领取礼品卡';

  @override
  String paymentLinkRemovalWarningCheckFailed(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'reset': '重置 Vizor',
      'other': '移除此账户',
    });
    return '无法检查是否有未分享的礼品卡链接。在$_temp0之前，请复制仍需要的链接。';
  }

  @override
  String paymentLinkRemovalWarningUnshared(int count, String subject) {
    String _temp0 = intl.Intl.selectLogic(subject, {
      'reset': '重置 Vizor',
      'other': '移除此账户',
    });
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个已充值的礼品卡链接尚未分享。$_temp0会丢失这些链接。请先复制链接。',
    );
    return '$_temp1';
  }

  @override
  String get paymentLinkRemoveCardLabel => '移除卡片';

  @override
  String get paymentLinkRemoveCardSupporting => '此操作无法撤销。';

  @override
  String get paymentLinkRemoveCardTitle => '移除此卡？';

  @override
  String get paymentLinkRestoreCard => '恢复卡片';

  @override
  String get paymentLinkRevealMessageSemanticLabel => '显示礼品卡留言';

  @override
  String get paymentLinkReviewAndConfirm => '检查并确认';

  @override
  String get paymentLinkReviewCardTitle => '检查卡片';

  @override
  String get paymentLinkSaveQrCode => '保存二维码';

  @override
  String get paymentLinkSaving => '正在保存…';

  @override
  String get paymentLinkScanAgainOrPaste => '请重新扫描或粘贴其他卡片链接。';

  @override
  String get paymentLinkScanCameraHint => '请连接摄像头扫描礼品卡二维码，或返回粘贴卡片链接。';

  @override
  String get paymentLinkScanSheetSemantic => '扫描礼品卡二维码';

  @override
  String get paymentLinkScanSheetTitle => '扫描礼品卡二维码';

  @override
  String get paymentLinkScanShowQrToCamera => '请将礼品卡二维码对准摄像头';

  @override
  String paymentLinkSenderMessageSemantic(String message) {
    return '发送者留言：$message；显示礼品卡正面';
  }

  @override
  String get paymentLinkShareCard => '分享卡片';

  @override
  String get paymentLinkShareFailed => '无法分享礼品链接。';

  @override
  String get paymentLinkShareFailedCopyInstead => '无法分享这张礼品卡。请改为复制链接。';

  @override
  String get paymentLinkShareGiftCardTitle => '分享礼品卡';

  @override
  String get paymentLinkShareLinkInstruction =>
      '请只将此链接分享给预期的接收人，对方即可在 Vizor 应用中领取卡片。';

  @override
  String get paymentLinkShareLinkInstructionDesktop =>
      '请只将此链接分享给预期的接收人，\n对方即可在 Vizor 应用中领取卡片。';

  @override
  String get paymentLinkShareSheetTitle => '分享礼品卡';

  @override
  String get paymentLinkShareWaitingDescription => '正在准备你的礼品卡以便分享。';

  @override
  String get paymentLinkSharedStatusFailed => '已分享礼品卡，但无法更新其状态。';

  @override
  String get paymentLinkSharing => '正在分享…';

  @override
  String get paymentLinkShowCardFrontSemantic => '显示礼品卡正面';

  @override
  String get paymentLinkShowHowCardsWork => '显示礼品卡使用说明';

  @override
  String get paymentLinkShowQrSemantic => '显示礼品卡二维码';

  @override
  String get paymentLinkSkipMessage => '跳过留言';

  @override
  String get paymentLinkStartTyping => '开始输入…';

  @override
  String get paymentLinkStartWritingMessage => '开始撰写礼品卡留言';

  @override
  String get paymentLinkStepAddMessage => '添加留言';

  @override
  String get paymentLinkStepCreate => '创建';

  @override
  String get paymentLinkStepReview => '检查';

  @override
  String get paymentLinkStillNotSaved => '仍然无法保存礼品卡。关闭 Vizor 前请重试。';

  @override
  String get paymentLinkTapToRevealMessage => '点按卡片即可查看留言。';

  @override
  String get paymentLinkTapToRevealMessageTwoLines => '点按卡片\n即可查看留言。';

  @override
  String get paymentLinkTotalAmountHelpSemantic => '关于礼品卡总金额';

  @override
  String get paymentLinkTotalDeductedLabel => '扣除总额';

  @override
  String get paymentLinkTrySavingAgain => '重试保存';

  @override
  String get paymentLinkUnusedSectionLabel => '未使用';

  @override
  String get paymentLinkUsageAllUsed => '全部已使用';

  @override
  String get paymentLinkUsageAmountMismatch => '检测到的充值金额与预期的卡片充值金额不一致。';

  @override
  String get paymentLinkUsageAwaitingConfirmation => '链接已可分享。充值交易确认后将开始追踪使用情况。';

  @override
  String paymentLinkUsageCardUse(String label, String suffix) {
    String _temp0 = intl.Intl.selectLogic(suffix, {
      'checking': ' · 检查中…',
      'failed': ' · 更新失败',
      'other': '',
    });
    return '卡片使用状态：$label$_temp0';
  }

  @override
  String get paymentLinkUsageFundingNotObserved => '尚未能在追踪记录中验证充值交易。';

  @override
  String paymentLinkUsageLastChecked(String time) {
    return '上次检查：$time';
  }

  @override
  String get paymentLinkUsageMissingFundingInfo => '已保存的充值信息不完整，无法验证使用情况。';

  @override
  String get paymentLinkUsageNotEnoughInfo => '目前信息不足，无法验证此卡是否已被使用。';

  @override
  String get paymentLinkUsageScanIncomplete => '追踪记录尚未扫描到充值交易。';

  @override
  String paymentLinkUsageSemantics(
    String label,
    String state,
    String hasExplanation,
    String explanation,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'checking': '。检查中',
      'failed': '。更新失败',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(hasExplanation, {
      'true': '。$explanation',
      'other': '',
    });
    return '卡片使用状态：$label$_temp0$_temp1';
  }

  @override
  String paymentLinkUsageUnusedOfCount(int unused, int count) {
    return '$count 张中未使用 $unused 张';
  }

  @override
  String get paymentLinkUsageUnverified => '未验证';

  @override
  String get paymentLinkUsageUseDetected => '检测到已使用';

  @override
  String paymentLinkUsageUsedOfCount(int used, int count) {
    return '$count 张中已使用 $used 张';
  }

  @override
  String get paymentLinkUsdAmountTooSmall => '金额过小，无法以 USD 输入。';

  @override
  String get paymentLinkUsdFetchingPrice => '正在获取 USD 价格…';

  @override
  String get paymentLinkUsdPriceUnavailable => 'USD 价格不可用';

  @override
  String paymentLinkUseMaxCurrencySemantic(String amount, String currency) {
    return '使用最大金额：$amount $currency';
  }

  @override
  String paymentLinkUseMaxSemantic(String amount) {
    return '使用最大金额：$amount';
  }

  @override
  String get paymentLinkUsedSectionLabel => '已使用';

  @override
  String get paymentLinkViewCardAction => '查看卡片';

  @override
  String paymentLinkWaitToClaim(int minutes, String seconds) {
    return '请等待 $minutes:$seconds 后领取';
  }

  @override
  String get paymentLinkWaitToClaimSample => '请等待 3:45 后领取';

  @override
  String paymentLinkWaitToGetLink(int minutes, String seconds) {
    return '请等待 $minutes:$seconds 后获取链接';
  }

  @override
  String get paymentLinkWaitingDescription => '这可能需要一点时间。';

  @override
  String get paymentLinkWaitingStatusLabel => '请等待 1:15 后获取链接';

  @override
  String get paymentLinkWalletSaveRecoveryFailed => '无法完成钱包保存。请重试。';

  @override
  String get paymentUriExpired => '该请求链接已超时。请重新打开以支付。';

  @override
  String get paymentUriMalformed => '此请求链接无效。请向发送方索取新的链接。';

  @override
  String get paymentUriMigrationSendGate => '打开请求链接前，请先完成 Ironwood 迁移。';

  @override
  String get paymentUriNoWallet => '打开请求链接前，请先设置或导入钱包。';

  @override
  String get paymentUriOnboarding => '打开请求链接前，请先完成钱包设置。';

  @override
  String get paymentUriReplaced => '仅保留了最新的请求链接。如需支付之前的请求，请重新打开该链接。';

  @override
  String get paymentUriUnavailable => 'Vizor 无法打开此请求链接。请在钱包加载完成后重新打开。';

  @override
  String get paymentUriUnsupported => '此请求链接使用了 Vizor 尚不支持的功能。';

  @override
  String get poolShielded => '屏蔽';

  @override
  String get poolTransparent => '透明';

  @override
  String get privateQueriesOptOutUnfinished => '关闭隐私查询未完成。请在设置中再次关闭，以使用透明资金。';

  @override
  String get profilePictureChange => '更换头像';

  @override
  String profilePictureName(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'p01': '骑士',
      'p02': '维京人',
      'p03': '武士',
      'p04': '君主',
      'p05': '铁盔',
      'p06': '浪人',
      'p07': '骷髅骑士',
      'p08': '先知',
      'p09': '狂战士',
      'p10': '盗贼',
      'p11': '法师',
      'p12': '蒙面猫',
      'p13': '守卫',
      'p14': '青铜盔',
      'p15': '鱼骑士',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get profilePictureSelect => '选择头像';

  @override
  String get profilePictureUpdateFailed => '无法更改头像。';

  @override
  String get receiveAboutAddressType => '关于此地址类型';

  @override
  String get receiveAddressCouldNotLoad => '无法加载地址。请重试。';

  @override
  String get receiveAddressLoadFailed => '无法加载你的地址。请稍后重试。';

  @override
  String get receiveCopyTransparentAddress => '复制透明地址';

  @override
  String receiveErrorWithDetails(String message, String details) {
    return '$message\n详细信息：$details';
  }

  @override
  String get receiveGenerateNewShieldedAddress => '生成新的屏蔽地址';

  @override
  String get receiveInfoShieldedDiversified =>
      '每个新地址都是由同一密钥派生的多样化地址，所有地址都会收款到同一个钱包。';

  @override
  String get receiveInfoShieldedHiddenDesktop =>
      '交易详情——发送方、接收方和金额——在链上经过加密并被隐藏。';

  @override
  String get receiveInfoShieldedHiddenMobile =>
      '交易详情——发送方、接收方和金额——在链上经过加密并被隐藏。';

  @override
  String get receiveInfoShieldedRenewClick => '只有在你点击刷新按钮时，才会生成新的 Zcash 屏蔽地址。';

  @override
  String get receiveInfoShieldedRenewTap => '只有在你点按刷新按钮时，才会生成新的 Zcash 屏蔽地址。';

  @override
  String get receiveInfoShieldedSubtitle => '默认提供强隐私保护。';

  @override
  String get receiveInfoTransparentExchanges =>
      '常用于要求透明度或监管明确性的交易所，也是许多钱包兼容时的默认选项。';

  @override
  String get receiveInfoTransparentPublicDesktop =>
      '所有交易详情——发送方、接收方和金额——在链上公开可见。';

  @override
  String get receiveInfoTransparentPublicMobile =>
      '所有交易详情——发送方、接收方和金额——在链上公开可见。';

  @override
  String get receiveInfoTransparentRotates =>
      '此地址收到 ZEC 且 Vizor 同步后，你的下一个透明地址会自动更换。之前的地址仍属于此钱包。';

  @override
  String receiveInfoTransparentShieldFirst(String ticker) {
    return '向透明地址收到 $ticker 后，Vizor 会引导你屏蔽该余额，否则你将无法发送。';
  }

  @override
  String get receiveInfoTransparentSubtitle => '公开可见';

  @override
  String get receiveQrSaveFailed => '无法保存二维码图片。请尝试其他文件夹，或改为复制请求链接。';

  @override
  String receiveQrSaved(String folder) {
    return '二维码图片已保存到 $folder';
  }

  @override
  String get receiveQrUnavailable => '二维码不可用';

  @override
  String get receiveRenewAddressError => '无法刷新你的屏蔽地址。请重试，或继续使用当前地址。';

  @override
  String get receiveRequestAmountDecimalsError => '最多输入 8 位小数';

  @override
  String get receiveRequestAmountFormatError => '请输入类似 0.5 的金额';

  @override
  String get receiveRequestAmountSupplyError => '金额超过 ZEC 总供应量';

  @override
  String receiveRequestButton(String ticker) {
    return '请求 $ticker';
  }

  @override
  String get receiveRequestCloseRequest => '关闭请求';

  @override
  String get receiveRequestCopyFailed => '无法复制请求链接。请改为分享。';

  @override
  String get receiveRequestCopyRequestLink => '复制请求链接';

  @override
  String get receiveRequestCreate => '创建请求';

  @override
  String get receiveRequestEnterZec => '以 ZEC 输入金额';

  @override
  String get receiveRequestLinkCopied => '已复制请求链接';

  @override
  String get receiveRequestMessageHelp => '仅限屏蔽地址——任何拿到此链接的人都能读取。';

  @override
  String get receiveRequestMessageHint => '任何收到链接的人都能读取此内容';

  @override
  String get receiveRequestSaveQr => '保存二维码图片';

  @override
  String get receiveRequestShare => '分享请求';

  @override
  String get receiveRequestShareFailed => '无法分享此请求。请改为复制链接。';

  @override
  String get receiveRequestZecButton => '请求 ZEC';

  @override
  String get receiveShareAddress => '分享地址';

  @override
  String get receiveShareFailed => '无法分享此地址。请改为复制。';

  @override
  String get receiveShareShieldedAddress => '分享屏蔽地址';

  @override
  String get receiveShareTransparentAddress => '分享透明地址';

  @override
  String receiveTitle(String ticker) {
    return '接收 $ticker';
  }

  @override
  String get secretPassphraseCopy => '复制助记词';

  @override
  String get secretPassphraseTitle => '助记词';

  @override
  String get sendAddMemo => '添加备注';

  @override
  String get sendAddressTypeTex => 'TEX 地址';

  @override
  String get sendAddressValidationFailed => '地址验证失败';

  @override
  String get sendAmountCtaEnterAmount => '输入金额以继续';

  @override
  String get sendBroadcastCancelledBeforeParams => '在下载证明参数之前，发送已取消。';

  @override
  String get sendBroadcastDependentIncomplete =>
      '第一笔交易已被接受，但后续交易未完成。再次发送前请先查看“活动”。';

  @override
  String get sendBroadcastFirstUnknown =>
      '第一笔交易已保存在本地，可能已到达网络，但确认超时。再次发送前请先查看“活动”。';

  @override
  String get sendBroadcastHardwareExpired =>
      '硬件签名请求在广播前已过期。请返回钱包，等待同步完成后重新确认付款并重试。';

  @override
  String get sendBroadcastIncomplete => '交易广播未完成。再次发送前请先查看“活动”。';

  @override
  String get sendBroadcastLedgerFirstUnknown =>
      '第一笔交易可能已到达网络，但确认超时。再次发送前请先查看“活动”。';

  @override
  String get sendBroadcastLedgerNotStored =>
      '交易已到达网络，但 Vizor 无法将其保存在本地。在同步或区块浏览器确认最新状态之前，请勿再次发送。';

  @override
  String get sendBroadcastLedgerRejected => '交易被网络拒绝。请稍后重试。';

  @override
  String get sendBroadcastLocalRetry =>
      '交易已在本地创建，但无法广播。网络可用时将自动重试。除非此交易过期，否则请勿再次发送。';

  @override
  String get sendBroadcastMnemonicMissing => '找不到发送账户的助记词。';

  @override
  String get sendBroadcastPartial => '部分交易已广播，其余交易将自动重试。再次发送前请先查看活动。';

  @override
  String get sendBroadcastProofParamsRequired => '重试这笔已签名的交易需要证明参数。';

  @override
  String get sendBroadcastRejectedLocal =>
      '交易已在本地创建，但未到达网络。钱包会持续重试直至其过期。除非此交易过期，否则请勿再次发送。';

  @override
  String get sendBroadcastTrackingFailed =>
      '交易已到达网络，但本地追踪失败。再次发送前请先查看“活动”或区块浏览器。';

  @override
  String get sendCalculatingMax => '正在计算最大金额';

  @override
  String get sendContactPickerEmpty => '没有 Zcash 联系人';

  @override
  String get sendContactPickerTitle => 'Zcash 联系人';

  @override
  String get sendDonationAddressTitle => 'Vizor 捐赠地址';

  @override
  String get sendEnterAddressToContinue => '输入地址以继续';

  @override
  String get sendEnterValidAddress => '请输入有效地址';

  @override
  String get sendErrorCouldNotBeSent => '无法发送交易。请返回钱包查看最新状态。';

  @override
  String get sendErrorDonationFailed => '捐赠失败。请重试。';

  @override
  String get sendErrorExpiredBeforeSent => '交易在发送前已过期。';

  @override
  String get sendErrorExpiredTryAgain => '交易在发送前已过期。请重试。';

  @override
  String get sendErrorInsufficientShielded => '屏蔽余额不足以支付金额和手续费。';

  @override
  String get sendErrorNetwork => '网络错误。请检查网络连接后重试。';

  @override
  String get sendErrorPartiallySent => '此交易的部分内容已发送。重试前，请在“活动”中查看已完成的部分。';

  @override
  String get sendErrorRejectedTryAgain => '网络拒绝了此交易。请重试。';

  @override
  String get sendErrorRejectedTryLater => '网络拒绝了此交易。请稍后重试。';

  @override
  String get sendErrorSendFailed => '发送失败。请重试。';

  @override
  String get sendErrorSyncFinishing => '正在完成钱包同步，请稍后重试。';

  @override
  String get sendFeeAboutSemantics => '关于交易手续费';

  @override
  String get sendFeeUnavailableTryAgain => '无法获取手续费。请重试。';

  @override
  String get sendFeeUpdatedAfterSync => '同步后手续费已更新。请重新确认后再继续。';

  @override
  String get sendFinishingSync => '正在完成钱包同步。';

  @override
  String get sendInsufficientBalanceIncludingFeeShielded => '含手续费后屏蔽余额不足';

  @override
  String get sendInsufficientBalanceIncludingFeeTex => '含手续费后余额不足';

  @override
  String get sendInsufficientBalanceSentenceShielded => '屏蔽余额不足。';

  @override
  String get sendInsufficientBalanceSentenceTex => '余额不足。';

  @override
  String get sendInsufficientBalanceShielded => '屏蔽余额不足';

  @override
  String get sendInsufficientBalanceTex => '余额不足';

  @override
  String get sendInsufficientBalanceToCoverFeeShielded => '屏蔽余额不足以支付手续费';

  @override
  String get sendInsufficientBalanceToCoverFeeTex => '余额不足以支付手续费';

  @override
  String sendInsufficientBalanceWithFeeShielded(String fee) {
    return '屏蔽余额不足（手续费：$fee）';
  }

  @override
  String sendInsufficientBalanceWithFeeTex(String fee) {
    return '余额不足（手续费：$fee）';
  }

  @override
  String get sendInvalidAddress => '地址无效';

  @override
  String get sendInvalidAmount => '金额无效';

  @override
  String get sendKeystonePrepareFailedGoBack => '无法准备 Keystone 签名。请返回后重试。';

  @override
  String get sendKeystonePrepareFailedReturnToSend =>
      '无法准备 Keystone 签名。请返回发送页面重试。';

  @override
  String get sendKeystoneQrMismatch => '此二维码与当前的 Keystone 签名请求不匹配。';

  @override
  String get sendKeystoneScanCameraOnly => 'Keystone 签名仅支持摄像头扫描二维码。请连接摄像头后重试。';

  @override
  String get sendKeystoneScanDecodeFailed => '无法将此二维码解码为 Keystone 交易签名。';

  @override
  String get sendKeystoneScanHoldSteady => '请将二维码稳定地对准摄像头';

  @override
  String get sendKeystoneScanNow => '请立即扫描。证明准备好后即可导入签名。';

  @override
  String get sendKeystoneScanToFinish => '请扫描 Keystone 上的二维码以完成发送';

  @override
  String sendKeystoneTexTwoApprovals(int index) {
    return '此 TEX 发送需要在 Keystone 上确认两次。请扫描第 $index 笔交易，共 2 笔。';
  }

  @override
  String sendKeystoneTransactionOfTwo(int index) {
    return '第 $index 笔交易，共 2 笔';
  }

  @override
  String sendLedgerConnectAndUnlock(String instruction) {
    return '请连接并解锁你的 Ledger。$instruction';
  }

  @override
  String get sendLedgerCouldNotFinishTitle => '无法完成交易';

  @override
  String get sendLedgerCouldNotPrepare => 'Vizor 无法准备交易，请重试。';

  @override
  String get sendLedgerCouldNotSaveTitle => '无法保存已签名的交易';

  @override
  String get sendLedgerCouldNotVerifySaved => 'Vizor 无法验证已保存的交易。请勿再次签名或发送。';

  @override
  String get sendLedgerCreateNewTransaction => '新建交易';

  @override
  String get sendLedgerExpiredMessage => '此交易无法再签名。请新建并确认交易。';

  @override
  String get sendLedgerKeepOpenRetry => '请保持 Vizor 打开并重试。无需再次在 Ledger 上确认。';

  @override
  String get sendLedgerKeepOpenRetrySaving =>
      '请保持 Vizor 打开并重试保存。无需再次在 Ledger 上确认。';

  @override
  String get sendLedgerRejectedOnDevice => '交易已在 Ledger 上被拒绝。';

  @override
  String get sendLedgerSignaturePreservedMessage =>
      '你的 Ledger 签名已保留。请重试保存，无需再确认其他交易。';

  @override
  String get sendLedgerSignedNeedsAttentionTitle => '已签名的交易需要处理';

  @override
  String get sendLedgerSigningUnavailableTitle => '无法使用 Ledger 签名';

  @override
  String get sendLedgerStatusNewTransactionRequired => '需要新建交易';

  @override
  String get sendLedgerStatusRecoveryRequired => '需要恢复';

  @override
  String get sendLedgerStatusSignaturePreserved => '签名已保留';

  @override
  String get sendLedgerStatusUnsupportedTransaction => '不支持的交易';

  @override
  String sendLoadError(String error) {
    return '出了点问题，请稍后重试。\n\n详情：$error';
  }

  @override
  String get sendMaxButton => '最大';

  @override
  String get sendMaxNeedsAddress => '请输入有效地址以使用最大金额';

  @override
  String get sendMaxUnavailable => '无法获取最大金额';

  @override
  String get sendMemoAddShortEncrypted => '添加简短的加密留言';

  @override
  String get sendMemoClear => '清除备注';

  @override
  String get sendMemoCollapse => '收起';

  @override
  String get sendMemoEncryptedHint => '已加密，仅适用于屏蔽地址。';

  @override
  String get sendMemoRecipientOnly => '仅收款方可以阅读';

  @override
  String get sendMemoSheetAdd => '添加备注';

  @override
  String get sendMemoShieldedOnly => '仅屏蔽地址支持留言';

  @override
  String get sendMemoWhitespaceOnly => '仅含空白字符';

  @override
  String get sendOpenContacts => '打开联系人';

  @override
  String get sendPasteAction => '粘贴';

  @override
  String get sendPaymentRequestAmountNotSpecified => '未指定金额';

  @override
  String get sendPaymentRequestCheckBeforePayBody => '其他应用可能会更改请求链接中的地址或金额。';

  @override
  String get sendPaymentRequestCheckBeforePayTitle => '付款前请核对';

  @override
  String get sendPaymentRequestCheckFailed => '无法检查此请求';

  @override
  String get sendPaymentRequestCheckGeneric => '无法检查此请求——请重试或修改详情';

  @override
  String get sendPaymentRequestCheckNetwork => '无法连接到网络——请检查网络连接后重试';

  @override
  String get sendPaymentRequestCheckNoAccount => '未选择账户——请先选择一个，然后重新打开此链接';

  @override
  String get sendPaymentRequestCheckNoAmount => '此链接未提供可支付的金额——请输入金额后继续';

  @override
  String get sendPaymentRequestCheckUpgradeHold => '因网络升级已暂停。请几分钟后重试。';

  @override
  String get sendPaymentRequestCheckUpgradeScheduleChanged =>
      '网络升级改变了迁移时间。请查看迁移计划后重新开始。';

  @override
  String get sendPaymentRequestClose => '关闭收款请求';

  @override
  String get sendPaymentRequestConfirmWithSender => '请与发送者确认详情。';

  @override
  String get sendPaymentRequestHideFullAddress => '隐藏完整收款地址';

  @override
  String get sendPaymentRequestHidePaymentDetails => '隐藏付款详情';

  @override
  String get sendPaymentRequestHideRequesterInfo => '隐藏请求方信息';

  @override
  String sendPaymentRequestHideRequesterInfoFor(String name) {
    return '隐藏 $name 的请求方信息';
  }

  @override
  String get sendPaymentRequestInsufficientFunds => 'ZEC 不足以支付此金额和网络手续费';

  @override
  String sendPaymentRequestInsufficientFundsWithSpendable(String spendable) {
    return 'ZEC 不足以支付此金额和网络手续费（可用 $spendable）';
  }

  @override
  String get sendPaymentRequestInvalidAddress => '收款地址看起来不对';

  @override
  String get sendPaymentRequestLinkDifferentAddress => '链接中的地址不同';

  @override
  String get sendPaymentRequestLinkDifferentAmount => '链接中的金额不同';

  @override
  String get sendPaymentRequestLinkDifferentDetails => '链接的详情不同';

  @override
  String get sendPaymentRequestLinkDifferentMemo => '链接中的备注不同';

  @override
  String get sendPaymentRequestMatchesLink => '与链接一致';

  @override
  String get sendPaymentRequestMemoIncluded => '包含备注';

  @override
  String get sendPaymentRequestMemoIncludedHint => '包含备注。查看交易备注。';

  @override
  String get sendPaymentRequestNameDisclaimer => '此名称来自请求，并不能证明谁拥有收款地址。';

  @override
  String get sendPaymentRequestNameSuppliedInRequest => '请求中提供的名称。';

  @override
  String get sendPaymentRequestNoteFromRequester => '请求方的留言';

  @override
  String get sendPaymentRequestPaymentDetails => '付款详情';

  @override
  String get sendPaymentRequestRecipient => '收款方';

  @override
  String get sendPaymentRequestReplacedNotice => '已替换之前的链接';

  @override
  String get sendPaymentRequestRequestFrom => '请求来自';

  @override
  String get sendPaymentRequestReviewLinkDetails => '查看链接详情';

  @override
  String get sendPaymentRequestReviewPayment => '查看付款确认';

  @override
  String get sendPaymentRequestScanOriginalHint => '请直接在 Vizor 中扫描原始二维码。';

  @override
  String get sendPaymentRequestShowFullAddress => '显示完整收款地址';

  @override
  String get sendPaymentRequestShowRequesterInfo => '显示请求方信息';

  @override
  String sendPaymentRequestShowRequesterInfoFor(String name) {
    return '显示 $name 的请求方信息';
  }

  @override
  String get sendPaymentRequestSyncStalled => '仍在同步——钱包同步到最新后请再次检查';

  @override
  String get sendPaymentRequestSyncing => '钱包仍在同步——同步完成后将自动更新';

  @override
  String get sendPaymentRequestTransactionMemo => '交易备注';

  @override
  String sendPaymentRequestUnavailableLabel(String label) {
    return '$label，不可用';
  }

  @override
  String sendPaymentRequestUnavailableWithReason(String label, String reason) {
    return '$label，不可用。$reason';
  }

  @override
  String get sendPaymentRequestUsingQrInstead => '改用二维码——链接可能已被更改。';

  @override
  String get sendPaymentRequestViewNote => '查看留言';

  @override
  String get sendPaymentRequestYourAccount => '你的账户';

  @override
  String get sendQrScannerOpenFailed => '无法打开二维码扫描器，请重试。';

  @override
  String get sendRecentsSection => '最近';

  @override
  String get sendRecipientHint => '地址或请求链接';

  @override
  String get sendRecipientLabel => '发送至';

  @override
  String get sendRecipientUnreadableRequestLink => '无法读取此请求链接';

  @override
  String get sendRecipientWrongNetwork => '此地址属于另一个 Zcash 网络';

  @override
  String get sendRequestScanCheckFailed => '无法检查此二维码，请重试。';

  @override
  String get sendRequestScanInvalidAddress => '此二维码不是有效的 Zcash 地址。';

  @override
  String get sendRequestScanInvalidRequest => '此二维码不包含有效的收款请求。';

  @override
  String get sendRequestScanNotRequest => '此二维码不是 Zcash 地址或收款请求。';

  @override
  String get sendRequestScanPermission =>
      '扫描收款请求二维码需要使用摄像头。\n你可以随时在设置中更改摄像头权限。';

  @override
  String get sendRequestScanSubtitle => '请将请求方的原始二维码对准摄像头';

  @override
  String get sendRequestScanTipOriginal => '请在另一台设备上全屏打开请求方的原始二维码。';

  @override
  String get sendRequestScanUnavailable => '请连接摄像头，或返回查看链接详情。';

  @override
  String get sendRequestScanWrongNetwork => '此地址属于另一个网络。';

  @override
  String get sendReviewAction => '查看确认';

  @override
  String get sendReviewCalculatingFee => '正在计算手续费...';

  @override
  String get sendReviewConfirmAndSend => '确认并发送';

  @override
  String get sendReviewConfirmAndSendMobile => '确认并发送';

  @override
  String get sendReviewConfirmDonation => '确认捐赠';

  @override
  String get sendReviewConfirmWithLedger => '使用 Ledger 确认';

  @override
  String get sendReviewFeeUnavailable => '无法获取手续费';

  @override
  String get sendReviewFinishingSyncButton => '正在完成钱包同步...';

  @override
  String sendReviewRequestedAmount(String amount) {
    return '请求金额 $amount';
  }

  @override
  String get sendReviewRequestedBy => '请求方';

  @override
  String get sendReviewTitle => '查看发送确认';

  @override
  String get sendSaplingDownloadBody => '要创建这笔隐私交易，钱包需要下载约 50MB 的加密参数。';

  @override
  String get sendSaplingDownloadNote => '只需下载一次。\n可能会产生流量费用。';

  @override
  String get sendSaplingDownloadTitle => '需要下载';

  @override
  String get sendScanDowngradePastedMalformedRequest => '仅粘贴了地址——无法读取此收款请求';

  @override
  String get sendScanDowngradePastedMultipleRecipients =>
      '仅粘贴了第一位收款人——此请求包含多位收款人';

  @override
  String get sendScanDowngradePastedUnsupportedMemo => '仅粘贴了地址——无法读取此请求中的留言';

  @override
  String get sendScanDowngradeScannedMalformedRequest => '仅扫描了地址——无法读取此收款请求';

  @override
  String get sendScanDowngradeScannedMultipleRecipients =>
      '仅扫描了第一位收款人——此请求包含多位收款人';

  @override
  String get sendScanDowngradeScannedUnsupportedMemo => '仅扫描了地址——无法读取此请求中的留言';

  @override
  String get sendScanNotZcashAddress => '此二维码不是 Zcash 地址。';

  @override
  String get sendScanQrSubtitle => '扫描地址或收款请求';

  @override
  String get sendScanQrTitle => '扫描二维码';

  @override
  String get sendSendingToLabel => '发送至';

  @override
  String get sendSignConfirmTransaction => '确认交易';

  @override
  String sendSignConfirmTransactionOfTwo(int index) {
    return '确认交易（第 $index 笔，共 2 笔）';
  }

  @override
  String get sendSpendableInfoLabel => '可用余额说明';

  @override
  String get sendSpendableTooltipBody =>
      '资金需要先获得确认才能使用：来自自己钱包的找零需要 3 次确认，收到的他人转账需要 6 次确认。屏蔽票据还需要完整扫描。它们很快就会可用。';

  @override
  String get sendSpendableTooltipTitle => '可用余额可能低于总余额。';

  @override
  String get sendStatusDonationFailed => '捐赠失败';

  @override
  String get sendStatusDonationInProgress => '正在捐赠...';

  @override
  String sendStatusFailureSummary(String amount, String recipient) {
    return '$amount 发送给 $recipient';
  }

  @override
  String get sendStatusMobileConfirmSoon => '交易即将在链上确认。可在“活动”中追踪。';

  @override
  String get sendStatusMobileDonationQueued => '捐赠已排队';

  @override
  String get sendStatusMobileDonationSupport => '你的支持让 Vizor 得以持续发展。';

  @override
  String get sendStatusMobileDonationThanks => '感谢你\n支持 Vizor';

  @override
  String get sendStatusMobileNothingSent => '未发送任何内容，你的资金没有变动。请重试。';

  @override
  String get sendStatusMobilePendingDefault => '交易已创建，将自动提交。再次发送前，请先查看“活动”页面。';

  @override
  String get sendStatusMobileQueued => '已排队等待发送';

  @override
  String get sendStatusMobileReturnToSettings => '返回设置';

  @override
  String get sendStatusMobileSendingDonation => '正在发送捐赠...';

  @override
  String get sendStatusMobileSent => '已发送！';

  @override
  String get sendStatusMobileSubmitting => '正在向网络提交你的交易...';

  @override
  String get sendStatusRetryAfterSync => '请等待钱包同步完成，然后重试这笔已签名的交易。';

  @override
  String get sendStatusRowStatus => '状态';

  @override
  String get sendStatusScanKeystoneTitle => '请扫描 Keystone 二维码';

  @override
  String get sendStatusTitleInProgress => '正在发送...';

  @override
  String get sendStepEnterAmount => '输入金额';

  @override
  String get sendStepReviewDonation => '查看捐赠确认';

  @override
  String get sendStepReviewSend => '查看发送确认';

  @override
  String sendTitle(String currency) {
    return '发送 $currency';
  }

  @override
  String get sendUseMax => '最大';

  @override
  String sendUseMaxSemantics(String spendable) {
    return '使用最大可用余额，可用 $spendable';
  }

  @override
  String get sendUseMaxSemanticsShort => '使用最大可用余额';

  @override
  String sendVerifyAddressPreviousTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 笔历史交易',
    );
    return '$_temp0';
  }

  @override
  String get settingsAccountChangedPasscode => '所选账户已更改。请重新输入数字密码。';

  @override
  String get settingsAccountChangedPassword => '所选账户已更改。请重新输入密码。';

  @override
  String get settingsAccountUnavailable => '所选账户已不可用。';

  @override
  String get settingsBackToAccounts => '返回账户';

  @override
  String settingsBiometricOffToast(String feature) {
    return '$feature已关闭';
  }

  @override
  String settingsBiometricOnToast(String feature) {
    return '$feature已开启';
  }

  @override
  String settingsBiometricSetupFirst(String biometric) {
    return '请先在设备设置中设置$biometric。';
  }

  @override
  String settingsBiometricTurnOffBody(String feature) {
    return '你将使用数字密码解锁 Vizor。你可以随时在设置中重新开启$feature。';
  }

  @override
  String settingsBiometricTurnOffTitle(String feature) {
    return '要关闭$feature吗？';
  }

  @override
  String settingsBiometricUpdateFailed(String feature) {
    return '无法更新$feature。';
  }

  @override
  String get settingsBip39PassphraseCopied => '已复制 BIP39 密码短语';

  @override
  String get settingsBip39PassphraseCopy => '复制 BIP39 密码短语';

  @override
  String get settingsBirthdayBlockHeight => '创建区块高度';

  @override
  String get settingsBirthdayDate => '创建日期';

  @override
  String get settingsBirthdayDateCopied => '已复制创建日期';

  @override
  String get settingsBirthdayHeightCopied => '已复制创建区块高度';

  @override
  String get settingsConfirmAccessSubtitle => '请验证你的身份';

  @override
  String get settingsConfirmAccessTitle => '验证身份';

  @override
  String settingsCopyLabel(String label) {
    return '复制$label';
  }

  @override
  String settingsCopyLabelCopied(String label) {
    return '已复制$label';
  }

  @override
  String settingsEndpointBalanceNote(String ticker) {
    return '钱包将显示上次成功连接时的余额，不会显示你最近收到的 $ticker。';
  }

  @override
  String get settingsEndpointCloseSettings => '关闭节点设置';

  @override
  String get settingsEndpointConnectFailed => '无法连接到该节点。请检查主机和端口。';

  @override
  String get settingsEndpointCurrentPrefix => '当前：';

  @override
  String get settingsEndpointCustomise => '自定义节点';

  @override
  String get settingsEndpointCustomize => '自定义节点';

  @override
  String get settingsEndpointDefaultMarker => '（默认）';

  @override
  String get settingsEndpointSelectFromList => '从列表选择';

  @override
  String get settingsEndpointTitle => '节点';

  @override
  String get settingsEndpointUpdating => '正在更新节点...';

  @override
  String get settingsEndpointWarningBlockchain =>
      '如果节点配置错误，你的钱包将无法与 Zcash 区块链同步。';

  @override
  String get settingsEndpointWarningNetwork => '如果节点配置错误，你的钱包将无法与 Zcash 网络同步。';

  @override
  String get settingsEndpointsTitle => '节点';

  @override
  String get settingsEnterCurrentPasswordAgain => '请重新输入当前密码。';

  @override
  String get settingsEnterCurrentPasswordFirst => '请先输入当前密码。';

  @override
  String get settingsEnterPasscodeTitle => '输入数字密码';

  @override
  String settingsExplorerCurrent(String explorer) {
    return '当前：$explorer';
  }

  @override
  String settingsExplorerCurrentDefault(String host) {
    return '当前：$host（默认）';
  }

  @override
  String get settingsExplorerCustom => '自定义';

  @override
  String get settingsExplorerCustomSubtitle => '任何你喜欢的区块浏览器';

  @override
  String get settingsExplorerPrivacyCopy =>
      '交易链接会在此区块浏览器中打开。你可以使用 ZecBlock 或其他你喜欢的网站。发送后打开公共区块浏览器，可能会将你的 IP 地址与该交易关联。';

  @override
  String get settingsExplorerSaveFailed => '无法保存该区块浏览器网址。';

  @override
  String settingsExplorerTemplateHint(String txid, String txHash) {
    return '在路径中使用 $txid 或 $txHash，或只输入域名。';
  }

  @override
  String get settingsExplorerTitle => '区块浏览器';

  @override
  String get settingsExplorerUpdate => '更新区块浏览器';

  @override
  String get settingsExplorerUrlLabel => '区块浏览器网址';

  @override
  String get settingsIncorrectPasscode => '数字密码错误';

  @override
  String get settingsKeepAwakeDescription =>
      '防止手机进入休眠，使同步更快完成。应用仍会在闲置 1 分钟后锁定。';

  @override
  String get settingsKeepAwakeUpdateFailed => '无法更新屏幕常亮设置。';

  @override
  String get settingsLanguageLabel => '语言';

  @override
  String get settingsLanguageUpdateFailed => '无法更改语言。';

  @override
  String get settingsNewBadge => '新';

  @override
  String get settingsNoActiveAccount => '未选择任何账户。';

  @override
  String get settingsPasscodeCheckFailed => '无法验证你的数字密码。请重试。';

  @override
  String get settingsPasscodeMustDiffer => '新数字密码必须与当前不同。';

  @override
  String get settingsPasscodeRotationRecoveryFailed =>
      '我们无法验证上一次的数字密码修改。重试前请妥善备好你的助记词。';

  @override
  String get settingsPasscodeUpdateFailed => '无法更新你的数字密码。请重试。';

  @override
  String get settingsPasscodeUpdatedToast => '数字密码已更新';

  @override
  String get settingsPasscodeVerifyFailed => '无法验证数字密码。请重试。';

  @override
  String get settingsPasswordHint => '输入密码...';

  @override
  String get settingsPasswordMinimumHint => '至少 8 个字符。加入数字和符号，或使用更长的密码，可提高安全性。';

  @override
  String get settingsPasswordRotationRecoveryFailed =>
      '我们无法验证上一次的密码修改。重试前请妥善备好你的助记词。';

  @override
  String get settingsPasswordUpdateFailed => '无法更新你的密码。请重试。';

  @override
  String get settingsPfpSamurai => '武士';

  @override
  String get settingsPfpViking => '维京人';

  @override
  String get settingsPirCheckingUpdates => '正在检查更新…';

  @override
  String get settingsPirChooseServer => '选择服务器';

  @override
  String get settingsPirConfigOpenFailed => '无法打开配置仓库。';

  @override
  String get settingsPirCustomInvalid => '已保存的自定义服务器无效。请编辑它或选择其他服务器。';

  @override
  String get settingsPirCustomServer => '自定义服务器';

  @override
  String get settingsPirCustomServerEllipsis => '自定义服务器…';

  @override
  String get settingsPirCustomUrlInvalid => '请输入不含凭据、查询参数或片段的 HTTPS 基础网址。';

  @override
  String get settingsPirEditCustomServer => '编辑自定义服务器…';

  @override
  String get settingsPirListLoadFailed => '无法加载服务器列表。请重试或输入自定义服务器。';

  @override
  String get settingsPirListUpdateFailed => '无法更新服务器列表。正在使用上次加载的列表。';

  @override
  String get settingsPirListUpdateFailedCustom => '无法更新列表。你的自定义服务器仍处于选中状态。';

  @override
  String get settingsPirLoadingServers => '正在加载服务器列表…';

  @override
  String get settingsPirNoServers => '暂无可用服务器。你可以输入自定义服务器。';

  @override
  String get settingsPirServerChangeFailed => '无法更换服务器。请重试。';

  @override
  String get settingsPirServerCloseLabel => '关闭隐私查询服务器设置';

  @override
  String get settingsPirServerRemoved => '你选择的服务器已不再提供。请选择其他服务器以恢复隐私查询。';

  @override
  String get settingsPirServerSettingsLabel => '隐私查询服务器设置';

  @override
  String get settingsPirServerTitle => '隐私查询服务器';

  @override
  String get settingsPirSettingsReadFailed => '无法读取隐私查询服务器设置。';

  @override
  String get settingsPirShareServer => '分享你的服务器';

  @override
  String get settingsPirUnavailable => '此网络不支持隐私查询。';

  @override
  String get settingsPirUpdatingServer => '正在更新服务器…';

  @override
  String get settingsPirUseCustomServer => '使用自定义服务器';

  @override
  String get settingsPrivacyTitle => '隐私';

  @override
  String get settingsPrivateQueriesCopy =>
      '实验性功能。以隐私方式恢复透明资金，使服务器无法得知你的透明地址。查询受支持的交易时不会向服务器透露其 ID。';

  @override
  String get settingsPrivateQueriesIosNote => '开启期间，仅在 Vizor 打开时才会检查迁移确认。';

  @override
  String get settingsPrivateQueriesLabel => '隐私查询';

  @override
  String get settingsPrivateQueriesTurnOffBody =>
      'Vizor 将以公开方式重建你的透明交易记录，服务器会获知你的所有地址。';

  @override
  String get settingsPrivateQueriesTurnOffDisclosure =>
      '服务器会收到每个账户的所有透明地址，以及私密恢复找到的交易 ID。它可以将这些信息相互关联；不使用 Tor 时，还能与你的 IP 地址关联。';

  @override
  String get settingsPrivateQueriesTurnOffTitle => '要关闭隐私查询吗？';

  @override
  String get settingsProfilePictureCustom => '自定义';

  @override
  String get settingsRowAboutVizor => '关于 Vizor';

  @override
  String get settingsRowAccountNameMobile => '账户名称';

  @override
  String get settingsRowAddressBook => '地址簿';

  @override
  String get settingsRowChangePasscode => '修改数字密码';

  @override
  String get settingsRowChangePassword => '修改密码';

  @override
  String get settingsRowLinkMobile => '关联 Vizor 手机端';

  @override
  String get settingsRowMyGiftCards => '我的礼品卡';

  @override
  String get settingsRowProfilePicture => '头像';

  @override
  String get settingsRowProfilePictureMobile => '头像';

  @override
  String get settingsRowSecretPassphrase => '助记词';

  @override
  String get settingsRowUpdates => '更新';

  @override
  String get settingsRowViewingKeyMobile => '查看密钥';

  @override
  String get settingsSectionAccount => '账户';

  @override
  String get settingsSectionDangerZone => '危险区域';

  @override
  String get settingsSectionMisc => '其他';

  @override
  String get settingsSectionPersonal => '个人';

  @override
  String get settingsSectionSystem => '系统';

  @override
  String get settingsSeedBackupSaveFailed => '无法保存。请重试。';

  @override
  String get settingsSeedBiometricReason => '验证身份以访问你的助记词';

  @override
  String get settingsSeedCopiedToast => '已复制助记词';

  @override
  String get settingsSeedHeadingSubtitle => '这是你钱包的主密钥。\n请勿与任何人分享。';

  @override
  String get settingsSeedLoadFailed => '无法加载你的助记词。请重试。';

  @override
  String get settingsSeedPasswordSubtitle => '以查看助记词。';

  @override
  String get settingsSeedRemindLater => '稍后提醒我';

  @override
  String get settingsSeedScreenshotAck => '我明白了';

  @override
  String settingsSeedScreenshotBody(String highlight) {
    return '$highlight。任何能访问你手机或相册的人都能看到你的助记词。请改为将助记词抄写在纸上。';
  }

  @override
  String get settingsSeedScreenshotBodyLead => '截图并不可靠';

  @override
  String get settingsSeedScreenshotBodyRest =>
      '. Anyone who has access to your phone or your photo library will be able to see your Secret Passphrase. Write down your Phrase on a piece of paper instead.';

  @override
  String get settingsSeedScreenshotTitle => '请勿截取助记词的屏幕截图';

  @override
  String get settingsSeedUnavailableAccount => '此账户没有助记词。';

  @override
  String get settingsSeedUnavailableHardware => '硬件账户没有助记词。';

  @override
  String get settingsSeedWrittenDown => '我已抄写';

  @override
  String get settingsSetNewPasscodeTitle => '设置新数字密码';

  @override
  String get settingsStatusOff => '已关闭';

  @override
  String get settingsStatusOn => '已开启';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeSystem => '系统';

  @override
  String get settingsThemeSystemAuto => '跟随系统（自动）';

  @override
  String get settingsThemeTitle => '主题';

  @override
  String get settingsThemeUpdateFailed => '无法更新主题。';

  @override
  String get settingsTorDescBootstrapFailed =>
      'Vizor 无法连接到 Tor。在连接成功或你关闭 Tor 之前，请求会一直被阻止。';

  @override
  String get settingsTorDescConnected =>
      'Vizor 的网络请求通过 Tor 发送。在其他应用中打开的链接使用这些应用的网络设置。';

  @override
  String get settingsTorDescConnectedIos =>
      'Vizor 的网络请求通过 Tor 发送。Vizor 关闭期间，Ironwood 私密迁移使用直接连接。在其他应用中打开的链接使用这些应用的网络设置。';

  @override
  String get settingsTorDescConnectedNoUpdates =>
      'Vizor 的网络请求通过 Tor 发送，但无法进行软件更新。';

  @override
  String get settingsTorDescConnecting =>
      '新请求会等待 Tor 连接就绪。关闭 Tor 可停止连接并使用直接连接。';

  @override
  String get settingsTorDescConnectingLinux =>
      '新请求会等待 Tor 连接就绪。关闭 Tor 可停止连接并使用直接连接。在其他应用中打开的更新页面和下载将使用该应用的连接。';

  @override
  String get settingsTorDescConnectionFailed => '直接请求仍被阻止。请重试或关闭 Tor。';

  @override
  String get settingsTorDescDirectNoUpdates => '网络请求直接连接。无法进行软件更新。';

  @override
  String get settingsTorDescDisableNotSaved =>
      '请求现在使用直接连接，但 Vizor 无法保存此更改。下次打开应用时 Tor 将重新开启。';

  @override
  String get settingsTorDescEnableNotSaved =>
      'Vizor 无法保存此更改，因此未开启 Tor。请求仍使用直接连接。';

  @override
  String get settingsTorDescOff => 'Tor 已关闭。对 Zcash 网络、应用内服务和软件更新的请求均直接连接。';

  @override
  String get settingsTorDescOffLinux =>
      'Tor 已关闭。Vizor 的请求（包括软件更新检查）直接连接。更新页面和下载会在其他应用中打开。';

  @override
  String get settingsTorDescOffMobile =>
      '钱包同步和应用内请求直接连接。开启 Tor 可向 Vizor 所连接的服务器隐藏你的 IP 地址。';

  @override
  String get settingsTorDescSwitchFailed => 'Vizor 无法切换为直接连接。请重试。';

  @override
  String get settingsTorDescSwitchFailedStillOn =>
      'Vizor 无法切换为直接连接。Tor 仍处于开启状态，请求继续通过 Tor 发送。';

  @override
  String get settingsTorDescSwitching => 'Vizor 正在将网络请求和软件更新切换为直接连接。';

  @override
  String get settingsTorDescSwitchingLinux => 'Vizor 正在将其请求（包括软件更新检查）切换为直接连接。';

  @override
  String get settingsTorDescSwitchingMobile => 'Vizor 正在将网络请求切换为直接连接。';

  @override
  String get settingsTorGeneralDescription =>
      '使用 Tor 可向服务器隐藏你的 IP 地址。其他应用使用各自的网络设置。';

  @override
  String get settingsTorGeneralIosSuffix => ' Vizor 关闭期间，Ironwood 私密迁移使用直接连接。';

  @override
  String get settingsTorRetryUpdates => '重试更新';

  @override
  String get settingsTorStatusConnected => '已连接';

  @override
  String get settingsTorStatusConnectionFailed => '连接失败';

  @override
  String get settingsTorStatusDirect => '直接连接';

  @override
  String get settingsTorStatusNotSaved => '设置未保存';

  @override
  String get settingsTorStatusSwitchFailed => '切换失败';

  @override
  String get settingsTorStatusSwitching => '正在切换…';

  @override
  String get settingsTorStatusSwitchingDirect => '正在切换为直接连接…';

  @override
  String get settingsTorStopConnecting => '停止连接 Tor';

  @override
  String get settingsTorTryDirect => '重试直接连接';

  @override
  String get settingsTorUse => '使用 Tor';

  @override
  String get settingsTurnOffConfirm => '关闭';

  @override
  String settingsUninstallActiveSwaps(int count) {
    return '此钱包有 $count 笔进行中的兑换。请等待它们完成后再卸载。';
  }

  @override
  String get settingsUninstallClaimCheckFailed => '无法检查正在接收的礼品卡。卸载前请重试。';

  @override
  String get settingsUninstallCloseApp => '关闭 Vizor';

  @override
  String get settingsUninstallDeviceGeneric => '此设备';

  @override
  String get settingsUninstallDeviceMac => '这台 Mac';

  @override
  String get settingsUninstallDevicePc => '这台电脑';

  @override
  String get settingsUninstallDoneTitle => '你的数据已被删除';

  @override
  String get settingsUninstallFinishGeneric => '要完成卸载，请从此设备移除 Vizor 应用。';

  @override
  String get settingsUninstallFinishMac => '要完成卸载，请从“应用程序”中移除 Vizor 应用。';

  @override
  String get settingsUninstallFinishWindows => '要完成卸载，请在 Windows 设置中卸载 Vizor。';

  @override
  String get settingsUninstallPasswordSubtitle => '以卸载 Vizor。';

  @override
  String get settingsUninstallRemovingTitle => '正在删除数据...';

  @override
  String get settingsUninstallSwapCheckFailed => '无法检查进行中的兑换。卸载前请重试。';

  @override
  String get settingsUninstallTitle => '卸载 Vizor';

  @override
  String get settingsUninstallWipeFailed => '无法完成数据删除。请重试。';

  @override
  String settingsUninstallWipeSubtitle(String device) {
    return 'Vizor 将从$device删除钱包数据和安全存储。尚未分享的礼品卡链接将永久丢失。';
  }

  @override
  String get settingsUpdateApplying => '应用中';

  @override
  String get settingsUpdateAvailable => '可用';

  @override
  String get settingsUpdateCheck => '检查';

  @override
  String get settingsUpdateCheckForUpdates => '检查更新';

  @override
  String get settingsUpdateChecking => '检查中';

  @override
  String get settingsUpdateCurrentLabel => '当前';

  @override
  String get settingsUpdateDownloadButton => '下载更新';

  @override
  String get settingsUpdateDownloadingButton => '正在下载…';

  @override
  String get settingsUpdatePasswordTitle => '更新密码';

  @override
  String get settingsUpdateRestartButton => '重启以更新';

  @override
  String get settingsUpdateRestartingButton => '正在重启…';

  @override
  String settingsUpdateStatusAvailable(String version) {
    return '版本 $version 可用。';
  }

  @override
  String get settingsUpdateStatusChecking => '正在检查更新。';

  @override
  String settingsUpdateStatusDownloading(String percent) {
    return '正在下载 $percent%。';
  }

  @override
  String get settingsUpdateStatusIdle => '可以检查更新了。';

  @override
  String settingsUpdateStatusReady(String version) {
    return '版本 $version 已就绪。';
  }

  @override
  String get settingsUpdateStatusRestarting => '正在重启 Vizor。';

  @override
  String get settingsUpdateStatusUnsupported => '已安装的 Windows 应用支持更新。';

  @override
  String get settingsUpdateStatusUpToDate => 'Vizor 已是最新版本。';

  @override
  String get settingsUpdateUnavailable => '不可用';

  @override
  String get settingsUpdateUpToDate => '已是最新';

  @override
  String get settingsUpdatingPassword => '正在更新密码...';

  @override
  String settingsVersionFooterLabel(String version) {
    return 'Vizor，版本 $version';
  }

  @override
  String get settingsViewingKeyBiometricReason => '验证身份以访问你的查看密钥';

  @override
  String get settingsViewingKeyChoiceSharingWarning =>
      '仅与可信方分享。两种密钥都可能泄露透明余额和支出。';

  @override
  String get settingsViewingKeyChooseTitle => '选择他人可以查看的内容';

  @override
  String get settingsViewingKeyConfirmAgain => '请再次验证身份，然后重试加载此密钥。';

  @override
  String get settingsViewingKeyCopy => '复制查看密钥';

  @override
  String get settingsViewingKeyExplanation => '会泄露你的余额以及所有过去和未来的交易。它无法花费 ZEC。';

  @override
  String get settingsViewingKeyFormatQr => '二维码';

  @override
  String get settingsViewingKeyFormatText => '文本';

  @override
  String get settingsViewingKeyFullDescription => '可查看余额以及收入和支出的交易。';

  @override
  String get settingsViewingKeyIncomingExplanation =>
      '会泄露过去和未来收到的付款。它无法花费 ZEC。';

  @override
  String get settingsViewingKeyIncomingOnly => '仅收款';

  @override
  String get settingsViewingKeyIncomingOnlyDescription => '仅可查看收到的交易。';

  @override
  String get settingsViewingKeyIncomingWarningTitle => '此密钥会泄露收到的付款';

  @override
  String get settingsViewingKeyLoadFailedTitle => '无法加载查看密钥';

  @override
  String get settingsViewingKeyPasswordSubtitle => '以显示查看密钥。';

  @override
  String get settingsViewingKeyQrFull => '完整查看密钥二维码';

  @override
  String get settingsViewingKeyQrIncoming => '仅收款查看密钥二维码';

  @override
  String get settingsViewingKeyTitle => '查看密钥';

  @override
  String get settingsViewingKeyTryCopyAgain => '重新复制';

  @override
  String get settingsViewingKeyTypeFull => '完整查看密钥';

  @override
  String get settingsViewingKeyTypeIncoming => '仅收款密钥';

  @override
  String get settingsViewingKeyWarningTitle => '此密钥会泄露你的交易';

  @override
  String get settingsWalletSessionChanged => '钱包会话已更改。请重新输入密码。';

  @override
  String get settingsWinUpdateContinueTor => '继续使用 Tor';

  @override
  String get settingsWinUpdateStartFailedTitle => '无法开始更新';

  @override
  String get settingsWinUpdateTorBlockedBody =>
      'Vizor 已继续阻止直接请求。请在设置中重试更新，或关闭 Tor 后重新下载。';

  @override
  String get settingsWinUpdateTorBlockedTitle => '无法通过 Tor 进行软件更新';

  @override
  String get settingsWinUpdateTorChoiceBody =>
      '通过 Tor 更新可能耗时更长。关闭 Tor 会将 Vizor 的所有网络请求切换为直接连接。';

  @override
  String get settingsWinUpdateTorChoiceTitle => '此次更新是否使用 Tor？';

  @override
  String get settingsWinUpdateTorOffFailedBody =>
      'Tor 仍处于开启状态，因此 Vizor 继续阻止更新。请重试，或在设置中关闭 Tor 后再下载。';

  @override
  String get settingsWinUpdateTorOffFailedTitle => '无法关闭 Tor';

  @override
  String get settingsWinUpdateTurnOffTorAndUpdate => '关闭 Tor 并更新';

  @override
  String get settingsWinUpdateUnavailableBody =>
      'Tor 已关闭，但仍无法进行软件更新。下载前请在设置中重试更新。';

  @override
  String get settingsWinUpdateUnavailableTitle => '无法进行软件更新';

  @override
  String get sidebarAccountNameFallback => '用户名';

  @override
  String get sidebarAddressCopyFailed => '无法复制地址';

  @override
  String get sidebarHideBalance => '隐藏余额';

  @override
  String get sidebarMigrationNeedsInput => '需要操作';

  @override
  String get sidebarMyAccounts => '我的账户';

  @override
  String get sidebarShieldedAddressCopied => '屏蔽地址已复制';

  @override
  String get sidebarShowBalance => '显示余额';

  @override
  String get swapActionAddRecipientAddress => '添加收款地址';

  @override
  String get swapActionAddRefundAddress => '添加退款地址';

  @override
  String get swapActionGettingQuote => '正在获取报价';

  @override
  String swapActivityAddressBookRefund(String symbol) {
    return '$symbol 退款';
  }

  @override
  String swapActivityDeadlineHours(int hours) {
    return '$hours 小时';
  }

  @override
  String swapActivityDeadlineMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get swapActivityDepositAmount => '存入金额';

  @override
  String get swapActivityDepositAssetFallback => '存入资产';

  @override
  String swapActivityDepositInstructionDepositLabel(String symbol) {
    return '$symbol 存入';
  }

  @override
  String get swapActivityDepositInstructionReuseWarning => '请勿重复使用此地址';

  @override
  String swapActivityDepositInstructionSendFromSource(String symbol) {
    return '从源链发送 $symbol';
  }

  @override
  String swapActivityDepositInstructionSourceDepositLabel(String symbol) {
    return '$symbol 源链存入';
  }

  @override
  String swapActivityDepositInstructionSubmit(String symbol) {
    return '提交 $symbol 存入';
  }

  @override
  String swapActivityDepositInstructionTxHashHint(String symbol) {
    return '$symbol 源链交易哈希';
  }

  @override
  String swapActivityDepositInstructionTxHashLabel(String symbol) {
    return '$symbol 存入交易哈希';
  }

  @override
  String get swapActivityDetailConfiguredQuote => '报价设置';

  @override
  String swapActivityDetailDeliveryTx(String symbol) {
    return '$symbol 交付交易';
  }

  @override
  String get swapActivityDetailDepositDeadline => '存入截止时间';

  @override
  String swapActivityDetailDepositTo(String symbol) {
    return '$symbol 存入地址';
  }

  @override
  String swapActivityDetailDepositTx(String symbol) {
    return '$symbol 存入交易';
  }

  @override
  String get swapActivityDetailDetectedDeposit => '检测到的存入金额';

  @override
  String get swapActivityDetailFees => '手续费';

  @override
  String get swapActivityDetailIncluded => '已包含';

  @override
  String get swapActivityDetailIncludedInRate => '已包含在所示汇率中';

  @override
  String get swapActivityDetailMissingDeposit => '缺少的存入金额';

  @override
  String get swapActivityDetailRealizedSlippage => '实际滑点';

  @override
  String get swapActivityDetailRequiredDeposit => '所需存入金额';

  @override
  String swapActivityDetailSourceTxShielded(String symbol) {
    return '$symbol 交易（屏蔽）';
  }

  @override
  String get swapActivityDetailTotalFees => '总手续费';

  @override
  String get swapActivityExpectedToReceive => '预计收到金额';

  @override
  String get swapActivityIncompleteDeposit => '存入不足';

  @override
  String get swapActivityIncompletePayment => '支付未完成';

  @override
  String get swapActivityLastCheckJustNow => '上次检查：刚刚';

  @override
  String swapActivityLastCheckMinutesAgo(int minutes) {
    return '上次检查：$minutes 分钟前';
  }

  @override
  String get swapActivityNotReported => '未提供';

  @override
  String get swapActivityPaidSuccessfullyTitle => '支付成功';

  @override
  String get swapActivityPayInProgressTitle => '支付进行中...';

  @override
  String get swapActivityPaymentComplete => '支付完成';

  @override
  String swapActivityPickerNoRecipients(String symbol) {
    return '没有已保存的 $symbol 收款方';
  }

  @override
  String swapActivityPickerNoRefunds(String symbol) {
    return '没有已保存的 $symbol 退款地址';
  }

  @override
  String swapActivityPickerRecipientsTitle(String symbol) {
    return '$symbol 收款方';
  }

  @override
  String swapActivityPickerRefundsTitle(String symbol) {
    return '$symbol 退款';
  }

  @override
  String get swapActivityReceiveAssetFallback => '接收资产';

  @override
  String get swapActivityRecipientReceived => '收款方已收到金额';

  @override
  String swapActivityStateAddressOrAccountHint(String chain) {
    return '$chain 地址或账户';
  }

  @override
  String swapActivityStateAssetUnsupported(String symbol, String chain) {
    return '目前不支持 $chain 上的 $symbol。';
  }

  @override
  String swapActivityStateDecimalPlaces(String symbol, int decimals) {
    return '$symbol 最多支持 $decimals 位小数。';
  }

  @override
  String get swapActivityStateDestination => '收款地址';

  @override
  String swapActivityStateQuoteHigher(String percent) {
    return '实时报价比之前的预估高 $percent%。继续之前请确认保证最低金额。';
  }

  @override
  String swapActivityStateQuoteLower(String percent) {
    return '实时报价比之前的预估低 $percent%。继续之前请确认保证最低金额。';
  }

  @override
  String swapActivityStateQuoteUsesDifferentSell(
    String liveAmount,
    String estimateAmount,
    String symbol,
  ) {
    return '实时报价使用 $liveAmount $symbol，而非 $estimateAmount $symbol。继续之前请确认保证最低金额。';
  }

  @override
  String get swapActivityStatusAwaitingDeposit => '等待存入';

  @override
  String get swapActivityStatusAwaitingExternalDeposit => '等待外部存入';

  @override
  String get swapActivityStatusComplete => '已完成';

  @override
  String get swapActivityStatusDepositObserved => '已检测到存入';

  @override
  String get swapActivityStatusExpired => '已过期';

  @override
  String get swapActivityStatusProcessing => '处理中';

  @override
  String get swapActivityStepConvert => '兑换';

  @override
  String get swapActivityStepConvertDescription => '正在将屏蔽支出兑换为支付资产。';

  @override
  String get swapActivityStepConverting => '兑换中...';

  @override
  String swapActivityStepDeliver(String symbol) {
    return '交付 $symbol';
  }

  @override
  String swapActivityStepDeliverActive(String symbol) {
    return '交付 $symbol...';
  }

  @override
  String get swapActivityStepDeliverPayDescription => '正在将付款交付到收款地址。';

  @override
  String get swapActivityStepDeliverSwapDescription => '正在将兑换所得资产交付到收款地址。';

  @override
  String swapActivityStepDelivering(String symbol) {
    return '正在交付 $symbol...';
  }

  @override
  String swapActivityStepDeposit(String symbol) {
    return '存入 $symbol';
  }

  @override
  String get swapActivityStepDepositConfirmation => '存入确认';

  @override
  String get swapActivityStepDepositConfirmationActive => '存入确认中...';

  @override
  String get swapActivityStepDepositConfirmationDescription => '兑换路径开始前正在确认存入。';

  @override
  String swapActivityStepDeposited(String symbol) {
    return '已存入 $symbol';
  }

  @override
  String swapActivityStepDepositing(String symbol) {
    return '正在存入 $symbol...';
  }

  @override
  String get swapActivityStepRecipientReceives => '收款方接收';

  @override
  String swapActivityStepRecipientReceivesAsset(String symbol) {
    return '收款方正在接收 $symbol...';
  }

  @override
  String get swapActivityStepRecipientReceivesDescription => '正在确认收款方的到账。';

  @override
  String swapActivityStepSend(String symbol) {
    return '发送 $symbol';
  }

  @override
  String swapActivityStepSendActive(String symbol) {
    return '发送 $symbol...';
  }

  @override
  String swapActivityStepSending(String symbol) {
    return '正在发送 $symbol...';
  }

  @override
  String swapActivityStepSent(String symbol) {
    return '已发送 $symbol';
  }

  @override
  String get swapActivityStepSourceDescription => '等待源链和服务商确认存入';

  @override
  String swapActivityStepSpend(String symbol) {
    return '花费 $symbol';
  }

  @override
  String get swapActivityStepSpendDescription => '正在从屏蔽余额中支付。';

  @override
  String swapActivityStepSpending(String symbol) {
    return '正在花费 $symbol...';
  }

  @override
  String swapActivityStepSpent(String symbol) {
    return '已花费 $symbol';
  }

  @override
  String get swapActivityStepSwap => '兑换';

  @override
  String get swapActivityStepSwapActive => '兑换中...';

  @override
  String get swapActivityStepSwapDescription => '服务商正在执行兑换路径。';

  @override
  String get swapActivitySwapCompleted => '兑换完成';

  @override
  String get swapActivitySwapInProgress => '兑换进行中...';

  @override
  String get swapActivityTooltipFees => '包含我们的手续费以及路径服务商处理此兑换的成本。已计入上方汇率。';

  @override
  String swapActivityTooltipMinimumReceive(String symbol) {
    return '滑点后你最少会收到的 $symbol 数量。可能更多，但不会更少。';
  }

  @override
  String get swapActivityTooltipMinimumReceiveGeneric =>
      '滑点后你最少会收到的数量。可能更多，但不会更少。';

  @override
  String get swapActivityTooltipPriceProtection =>
      '滑点容忍度所保护的接收金额范围。若汇率变动超出此范围，兑换将被退款。';

  @override
  String get swapActivityTooltipStatusDetail => '详情基于最新的兑换记录和服务商状态。';

  @override
  String get swapActivityYouPaid => '已支付金额';

  @override
  String get swapActivityYouReceived => '已收到金额';

  @override
  String swapAddressRecipientDescription(String symbol) {
    return '你的 $symbol 将发送到此地址。';
  }

  @override
  String get swapAddressRecipientFieldLabel => '收款方';

  @override
  String swapAddressRecipientTitle(String symbol) {
    return '$symbol 收款地址';
  }

  @override
  String swapAddressRefundDescription(String symbol, String chain) {
    return '如果兑换失败或汇率变动，将扣除手续费后以 $chain 上的 $symbol 退款。';
  }

  @override
  String get swapAddressRememberRecipient => '记住此地址作为收款地址';

  @override
  String get swapAddressRememberRefund => '记住此地址作为退款地址';

  @override
  String get swapAssetSelectorEmpty => '未找到代币或链';

  @override
  String get swapAssetSelectorSearchHint => '搜索代币或链';

  @override
  String get swapAssetSelectorTitle => '选择资产';

  @override
  String get swapComposerAddRecipientAddressEllipsis => '添加收款地址...';

  @override
  String get swapComposerAddRefundAddressEllipsis => '添加退款地址...';

  @override
  String swapComposerMaxAmount(String amount) {
    return '最多：$amount';
  }

  @override
  String get swapComposerYouReceive => '你收到';

  @override
  String get swapContactAlreadyInAddressBook => '已在你的地址簿中';

  @override
  String get swapContactAlreadySaved => '已在你的联系人中';

  @override
  String get swapDepositAmountCopiedDesktop => '已复制金额';

  @override
  String get swapDepositAmountCopiedMobile => '已复制金额';

  @override
  String get swapDepositAmountToDeposit => '存入金额';

  @override
  String get swapDepositChecking => '正在检查';

  @override
  String get swapDepositDoneDesktop => '我已存入';

  @override
  String get swapDepositDoneMobile => '我已存入代币';

  @override
  String swapDepositHoursMany(int count) {
    return '$count 小时';
  }

  @override
  String get swapDepositMemoCopied => '已复制备注';

  @override
  String swapDepositMinutesMany(int count) {
    return '$count 分钟';
  }

  @override
  String get swapDepositOneTimeAddress => '一次性地址';

  @override
  String swapDepositSendOnly(String symbol, String chain) {
    return '仅发送 $chain 上的 $symbol';
  }

  @override
  String get swapDepositTimeoutBody => '此存入地址已失效。\n请重新发起一笔兑换。';

  @override
  String get swapDepositTitle => '存入代币';

  @override
  String get swapDepositWithin => '存入时限';

  @override
  String get swapDepositZecButton => '存入 ZEC';

  @override
  String get swapDismissBarrierLabel => '关闭';

  @override
  String get swapFailureAmountPrecision => '金额的小数位数过多。\n请减少小数位数后重试。';

  @override
  String get swapFailureAmountTooLowPay => '此笔支付的金额过低。\n请尝试更大的金额。';

  @override
  String get swapFailureAmountTooLowSwap => '此笔兑换的金额过低。\n请尝试更大的金额。';

  @override
  String get swapFailureAssetUnavailable => '此资产目前无法兑换。\n请选择其他资产或稍后重试。';

  @override
  String get swapFailureDepositNotIndexed => '存入尚未被索引。\n请几分钟后再查看。';

  @override
  String get swapFailureDepositRejected => '存入交易被拒绝。\n请检查地址、备注和交易哈希。';

  @override
  String get swapFailureDepositSubmitFailed => '无法提交存入状态。\n请稍后重试。';

  @override
  String get swapFailureNoQuote => '此路线或金额暂无可用报价。\n请调整金额、滑点或资产后重试。';

  @override
  String get swapFailureQuoteTimeout => '报价请求超时。\n请检查网络连接后重试。';

  @override
  String get swapFailureQuoteUnavailable => '目前无法获取报价。\n请稍后重试。';

  @override
  String get swapFailureQuoteUnverified => '无法验证报价响应。\n请稍后重试。';

  @override
  String get swapFailureRefreshFailed => '无法刷新兑换状态。\n请稍后重试。';

  @override
  String get swapFailureRequestTimeout => '请求超时。\n请检查网络连接后重试。';

  @override
  String get swapFailureResponseUnverified => '无法验证兑换响应。\n请稍后重试。';

  @override
  String get swapFailureRouteRejected => '此路线或地址被拒绝。\n请修改详情并重新获取报价。';

  @override
  String get swapFailureServiceUnavailable => '兑换服务暂时不可用。\n请稍后重试。';

  @override
  String get swapFailureStartFailed => '无法开始兑换。\n请稍后重试。';

  @override
  String get swapFailureStatusAssetUnsupported =>
      '兑换状态使用了不受支持的资产对。\n请勿重新发送资金。请稍后重试。';

  @override
  String get swapFailureStatusAutoRefresh => '无法刷新最新状态。\n我们会继续尝试，并自动更新此页面。';

  @override
  String get swapFailureStillProcessing => '兑换服务仍在处理中。\n请稍候再试。';

  @override
  String get swapFailureTokensUnavailable => '无法加载兑换代币。\n请稍后重试。';

  @override
  String get swapFailureTorBlockedPay =>
      '该服务阻止了此连接，因此无法通过 Tor 支付。\n如需支付，请在设置中关闭 Tor。';

  @override
  String get swapFailureTorBlockedSwap =>
      '该服务阻止了此连接，因此无法通过 Tor 兑换。\n如需兑换，请在设置中关闭 Tor。';

  @override
  String get swapFailureZecDepositFunding =>
      '可用 ZEC 不足以支付此笔兑换及其网络手续费。\n请尝试更小的金额，或使用最大值。';

  @override
  String get swapFailureZecDepositPreflight => '无法准备 ZEC 存入。\n请检查余额后重试。';

  @override
  String get swapFailureZecDepositSendFailed => '无法发送 ZEC 存入。\n请稍后重试。';

  @override
  String get swapKeystoneBroadcastFailed => '无法广播交易。';

  @override
  String get swapKeystoneBroadcastingTitle => '正在广播 ZEC 存入';

  @override
  String get swapKeystoneFailedTitle => 'Keystone 签名失败';

  @override
  String get swapKeystoneFinalizing => '正在广播 ZEC 存入...';

  @override
  String get swapKeystoneIncomplete => '无法完成 ZEC 存入签名。';

  @override
  String get swapKeystoneNoTex => 'Keystone 暂不支持 TEX 发送。';

  @override
  String get swapKeystoneScanCaption => '扫描 Keystone 上的二维码以完成 ZEC 存入';

  @override
  String get swapKeystoneSignTitle => '在 Keystone 上签署 ZEC 存入';

  @override
  String get swapKeystoneStatusUncertain => '交易状态不确定。请先刷新活动再重试。';

  @override
  String get swapLedgerBackToActivity => '返回活动';

  @override
  String get swapLedgerBroadcastFailed => '无法广播 ZEC 存入。';

  @override
  String get swapLedgerDeclined => 'ZEC 存入已在你的 Ledger 上被拒绝。';

  @override
  String get swapLedgerMessageBackground => 'Vizor 正在后台完成此交易。';

  @override
  String get swapLedgerMessageExpired => '交易在发送前已过期。Vizor 仍需释放其保留的资金。';

  @override
  String get swapLedgerMessageSentNotSaved => '交易已发送，但 Vizor 未能完成保存。';

  @override
  String get swapLedgerMessageUncertain => 'Vizor 无法确认交易是否已发送，仍需保存其状态。';

  @override
  String get swapLedgerRetryCleanup => '重试清理';

  @override
  String get swapLedgerSigningIncomplete => '无法完成 Ledger 签名。';

  @override
  String get swapLedgerStatusCleanup => '需要清理';

  @override
  String get swapLedgerStatusSaving => '正在保存交易';

  @override
  String get swapLedgerTitlePending => '交易状态待确认';

  @override
  String get swapLedgerTitleRecovery => '交易恢复进行中';

  @override
  String get swapLedgerTitleSent => '交易已发送';

  @override
  String get swapNoticeAccountChanged => '当前账户已更改。开始前请重新查看报价。';

  @override
  String get swapNoticeAffectedNetworks => '受影响的网络';

  @override
  String get swapNoticeAllChains => '所有链';

  @override
  String get swapNoticeBroadcastNotStored =>
      '交易已到达网络，但 Vizor 无法在本地保存。在同步或区块浏览器确认最新状态之前，请勿重试。';

  @override
  String get swapNoticeBroadcastPartial => '部分存入交易可能已到达网络。重试前请先查看活动。';

  @override
  String get swapNoticeBroadcastPending => '存入已在本地创建，但无法广播。重试前请先查看活动。';

  @override
  String get swapNoticeBroadcastUncertain => '存入状态不确定。重试前请先查看活动。';

  @override
  String get swapNoticeBroadcastUnknown => '交易可能已到达网络，但确认超时。重试前请先查看活动。';

  @override
  String get swapNoticeCloseLabel => '关闭服务通知';

  @override
  String get swapNoticeDepositIntentMissing =>
      'ZEC 存入已广播，但找不到已保存的兑换记录。离开此页面前，请复制交易哈希。';

  @override
  String swapNoticeExpectedEnd(String time) {
    return '预计结束：$time';
  }

  @override
  String get swapNoticeListOfMaintenance => '维护列表';

  @override
  String get swapNoticeMaintenanceIntro => 'NEAR Intents 正在维护中。';

  @override
  String get swapNoticeMaintenanceTitle => '维护通知';

  @override
  String swapNoticeMaintenanceWindow(String networks) {
    return '维护窗口：$networks';
  }

  @override
  String get swapNoticeOk => '好的';

  @override
  String get swapNoticePaymentsMayFail => '支付目前可能无法使用。';

  @override
  String get swapNoticeReceiveAddressUnavailable =>
      '无法准备新的钱包接收地址。请在钱包同步后重试，或在获取新报价前关闭处理中的旧兑换。';

  @override
  String get swapNoticeServiceTitle => '服务通知';

  @override
  String swapNoticeStart(String time) {
    return '开始：$time';
  }

  @override
  String get swapNoticeStatusPage => 'NEAR Intents 状态页面';

  @override
  String get swapNoticeSwapsMayFail => '兑换目前可能无法使用。';

  @override
  String get swapPageTitle => '兑换';

  @override
  String get swapPanelDepositChecking => '正在确认 ZEC 存入';

  @override
  String get swapPanelDepositSent => 'ZEC 存入已发送';

  @override
  String get swapPanelLoadFailedBody => '请返回“活动”并选择已保存的兑换。';

  @override
  String get swapPanelLoadFailedTitle => '无法加载此兑换。请重试或下拉刷新。';

  @override
  String swapPanelRecipientTo(String recipient) {
    return '收款方：$recipient';
  }

  @override
  String get swapPayStatusConvertedFrom => '兑换自';

  @override
  String get swapPayStatusNewAddress => '新地址';

  @override
  String get swapPayStatusSourceAmount => '原始金额';

  @override
  String get swapPoweredByLabel => '由以下提供支持';

  @override
  String swapQuoteExpiresAt(String time) {
    return '$time 到期';
  }

  @override
  String get swapQuoteExpiryPending => '报价到期时间待定';

  @override
  String get swapQuoteRatePending => '汇率待定';

  @override
  String get swapReviewBackPay => '支付';

  @override
  String get swapReviewConfirmAndSwap => '确认并兑换';

  @override
  String get swapReviewConfirmPaymentTitle => '确认支付';

  @override
  String get swapReviewConfirmSwap => '确认兑换';

  @override
  String swapReviewFromAddress(String address) {
    return '来自：$address';
  }

  @override
  String get swapReviewInsufficientZecSwap => '你的 ZEC 不足以完成此次兑换。请尝试较小的金额。';

  @override
  String swapReviewPayAmount(String amount) {
    return '支付 $amount';
  }

  @override
  String get swapReviewQuoteExpired => '报价已过期。请重新查看以获取最新汇率。';

  @override
  String get swapReviewQuoteHolds => '报价有效期';

  @override
  String get swapReviewQuoteInactive => '此报价已失效。';

  @override
  String get swapReviewReturnToSwap => '返回兑换';

  @override
  String get swapReviewReviewAgain => '重新查看';

  @override
  String get swapReviewStartingLockingQuote => '正在锁定报价';

  @override
  String get swapReviewStartingPaying => '支付中';

  @override
  String get swapReviewStartingSending => '发送中';

  @override
  String swapReviewToAddress(String address) {
    return '收款至：$address';
  }

  @override
  String get swapSignPayment => '签署支付';

  @override
  String get swapSignZecDeposit => '签署 ZEC 存入';

  @override
  String get swapSlippageCustom => '自定义';

  @override
  String get swapSlippageDescriptionPay =>
      '在执行失败之前，允许报价波动所需的额外 ZEC 数额。网络手续费另计。';

  @override
  String get swapSlippageDescriptionSwap => '设置你可接受的最大汇率变动。网络手续费另计。';

  @override
  String get swapSlippageRangeError => '滑点必须在 0.1 - 5% 之间';

  @override
  String get swapSlippageTitle => '滑点';

  @override
  String get swapStatusBadgeNeedsAttention => '需要处理';

  @override
  String get swapStatusDetailsTab => '交易详情';

  @override
  String get swapStatusRowLabel => '状态';

  @override
  String get swapTimeoutBody => '请重新发起一笔兑换。';

  @override
  String get swapTimeoutHeadline => '此存入地址已失效';

  @override
  String get swapTimeoutRestart => '重新开始兑换';

  @override
  String get swapViewOnNearIntents => '在 NEAR Intents 中查看';

  @override
  String syncCheckingPercentSemantics(String percent) {
    return '检查中，$percent%';
  }

  @override
  String syncCheckingProgress(String percent) {
    return '$percent% 检查中';
  }

  @override
  String get syncConnectingToTor => '正在连接 Tor…';

  @override
  String get syncConnectingToTorSemantics => '正在连接 Tor';

  @override
  String get syncErrorChainRecovery => '链恢复';

  @override
  String get syncErrorData => '数据错误';

  @override
  String get syncErrorEndpoint => '节点错误';

  @override
  String get syncErrorNetwork => '网络错误';

  @override
  String get syncErrorPrivateLookup => '隐私查询';

  @override
  String get syncErrorUnknown => '未知错误';

  @override
  String get syncErrorWalletData => '钱包数据错误';

  @override
  String get syncErrorWalletDataBusy => '钱包数据繁忙';

  @override
  String syncFailed(String reason) {
    return '同步失败。$reason...';
  }

  @override
  String syncFailedSemantics(String reason) {
    return '同步失败。$reason';
  }

  @override
  String get syncFailureChainRecovery => '同步期间区块链发生了变化。我们会继续尝试恢复。';

  @override
  String get syncFailureDatabaseBusy => '钱包数据正忙。我们会自动重新同步。';

  @override
  String get syncFailureDatabaseFatal => '无法读取钱包数据。请重启应用并重试同步。';

  @override
  String get syncFailureEndpoint => '无法连接到已配置的 Zcash 节点。请检查你的节点设置。';

  @override
  String get syncFailureNetwork => '网络连接已断开。我们会自动继续尝试。';

  @override
  String get syncFailureParse => '无法处理同步数据。请重试同步或检查你的节点。';

  @override
  String get syncFailurePrivateStatus =>
      '隐私交易查询无法确定某笔交易的状态。请在设置中关闭实验性隐私查询，以继续同步。';

  @override
  String get syncFailureTor => 'Tor 无法连接。请重试，或在设置中关闭 Tor。';

  @override
  String get syncFailureUnknown => '同步失败。请重试同步以继续。';

  @override
  String get syncSynced => '已同步';

  @override
  String syncSyncedAtBlock(String height) {
    return '已同步至区块 $height';
  }

  @override
  String syncSyncingPercentSemantics(String percent) {
    return '同步中，$percent%';
  }

  @override
  String syncSyncingProgress(String percent) {
    return '$percent% 同步中...';
  }

  @override
  String get syncTorFailed => 'Tor 无法连接...';

  @override
  String get syncTorFailedSemantics => 'Tor 无法连接';

  @override
  String get syncVizorSynced => 'Vizor 已同步';

  @override
  String get transparentLedgerNeedsNewerBuild => '此钱包的透明资金需要更新版本的 Vizor 才能使用。';

  @override
  String get transparentRecoveryIncomplete => '在私密恢复完成之前，透明资金不可用。';

  @override
  String get txFeeHelpTooltip => '支付给 Zcash 网络、用于处理此交易的手续费。';

  @override
  String get txFeeInfoDescription =>
      '网络手续费由 Zcash 协议（ZIP 317）根据交易大小确定。Vizor 不收取额外费用。';

  @override
  String get txFeeInfoTitle => '交易手续费';

  @override
  String get updateFailedMessage => '无法完成更新。请重试。';

  @override
  String get updateRestart => '重启';

  @override
  String get votingActionRetryEligibility => '重新检查资格';

  @override
  String get votingActionReview => '查看';

  @override
  String get votingActionReviewAnswers => '确认答案';

  @override
  String get votingActionUnavailable => '不可用';

  @override
  String get votingActionViewResults => '查看结果';

  @override
  String get votingActive => '投票进行中';

  @override
  String get votingAlreadyUsedNotice => '这些资金已在本轮中使用。无法在此设备上重新开始投票。';

  @override
  String get votingAutoAdvanceSemantics => '正在前往下一个未回答的问题';

  @override
  String get votingBallotCasting => '正在投票';

  @override
  String get votingBallotDelivering => '正在发送你的答案';

  @override
  String get votingBallotPreparing => '正在准备你的选票';

  @override
  String get votingBallotWaitingChain => '正在等待链上确认';

  @override
  String get votingBetaSemantics => '测试版';

  @override
  String votingBundleCount(int count) {
    return '$count 个投票票据包';
  }

  @override
  String votingBundleOf(int number, int total) {
    return '第 $number/$total 个票据包';
  }

  @override
  String votingChoiceFallback(int number) {
    return '选项 $number';
  }

  @override
  String get votingConfigAddCustomSource => '添加自定义来源';

  @override
  String get votingConfigCloseSettings => '关闭投票配置设置';

  @override
  String get votingConfigCopyUrl => '复制来源网址';

  @override
  String get votingConfigCustomSource => '自定义来源';

  @override
  String votingConfigDeleteNamed(String name) {
    return '删除 $name';
  }

  @override
  String get votingConfigDeleteSaved => '删除已保存的来源';

  @override
  String get votingConfigDuplicate => '此来源网址已添加。';

  @override
  String get votingConfigEditCustomSource => '编辑自定义来源';

  @override
  String votingConfigEditNamed(String name) {
    return '编辑 $name';
  }

  @override
  String get votingConfigEditSaved => '编辑已保存的来源';

  @override
  String get votingConfigEnterTitleAndUrl => '请输入标题和来源网址。';

  @override
  String get votingConfigFieldStaticUrl => '静态配置网址';

  @override
  String get votingConfigFieldTitle => '标题';

  @override
  String get votingConfigLoadFailed => '无法从该来源加载投票配置。';

  @override
  String get votingConfigMobileFieldUrl => '来源网址';

  @override
  String get votingConfigMobileIntro => '选择 Vizor 从何处获取已认证的投票轮次。';

  @override
  String get votingConfigMobileSave => '保存来源';

  @override
  String get votingConfigMobileTestRoundsHint => '包含标有 [TEST] 的已认证轮次。';

  @override
  String get votingConfigMobileTitle => '投票配置';

  @override
  String get votingConfigMobileUpdateFailed => '无法更新投票配置。请检查来源后重试。';

  @override
  String get votingConfigSaving => '正在保存...';

  @override
  String get votingConfigSettings => '投票配置设置';

  @override
  String get votingConfigShowTestRounds => '显示测试轮次';

  @override
  String get votingConfigShowTestRoundsHint => '显示标题以 [TEST] 开头的已认证轮次。';

  @override
  String get votingConfigSources => '来源';

  @override
  String get votingConfigTestVisibilityFailed => '无法更新测试轮次显示设置。';

  @override
  String votingConfigTitleTooLong(int max) {
    return '标题不能超过 $max 个字符。';
  }

  @override
  String get votingConfigTooltip => '投票配置';

  @override
  String get votingConfigUpdateFailed => '无法更新投票配置。';

  @override
  String get votingConfigUrlCopied => '已复制来源网址。';

  @override
  String get votingConfigValidating => '正在验证...';

  @override
  String get votingConfirmationCheckingEligibility => '正在检查此账户的投票资格。';

  @override
  String get votingConfirmationConfirmedBody => '你的投票已成功发布，无法更改。';

  @override
  String get votingConfirmationConfirmedTitle => '提交已确认！';

  @override
  String get votingConfirmationEligibilityUnconfirmed => '尚未确认此账户的投票资格。';

  @override
  String get votingConfirmationIncompleteTitle => '提交未完成';

  @override
  String votingConfirmationLoadFailed(String error) {
    return '无法加载提交详情：$error';
  }

  @override
  String get votingConfirmationNotCompleted => '此账户尚未完成本轮投票的提交。';

  @override
  String get votingConfirmationUpdateFailed => '无法更新投票轮次。请重试。';

  @override
  String get votingConfirmationUpdatingRounds => '正在更新投票轮次...';

  @override
  String get votingContinueVoting => '继续投票';

  @override
  String votingDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '剩余 $days 天',
      zero: '今天结束',
    );
    return '$_temp0';
  }

  @override
  String get votingDetailLoadFailedTitle => '无法加载投票轮次';

  @override
  String get votingDetailUnavailableBody => '无法加载所选的投票轮次。';

  @override
  String get votingDetailUnavailableTitle => '投票轮次不可用';

  @override
  String votingEnds(String date) {
    return '$date结束';
  }

  @override
  String get votingErrorChainCancelled => '链上提交已取消。';

  @override
  String get votingErrorChainNoUsableTransaction => '链上提交已结束，但没有生成可用的交易。';

  @override
  String get votingErrorChainRecoveryPending => '链上提交的恢复仍在进行中。';

  @override
  String get votingErrorChainRejected => '链上提交被拒绝。';

  @override
  String get votingErrorChainSubmittedWithoutHash => '提交可能已到达链上，但未返回交易哈希。请勿重试。';

  @override
  String votingErrorDelegationFailed(String details) {
    return '委托票据包处理失败：$details';
  }

  @override
  String get votingErrorHotkeyMissing => '缺少投票热密钥。请先完成本轮委托再投票。';

  @override
  String get votingErrorImmediateShareExpired =>
      '在辅助服务器确认即时份额之前，投票轮次已结束。重试前请先查看投票状态。';

  @override
  String get votingErrorKeystoneAccountOnly => 'Keystone 投票仅适用于 Keystone 账户。';

  @override
  String get votingErrorKeystoneHardwareOnly => 'Keystone 投票仅适用于硬件钱包账户。';

  @override
  String get votingErrorKeystoneInvalidSignature =>
      'Keystone 返回的投票签名无效。请扫描此处所示二维码对应的结果。';

  @override
  String get votingErrorKeystoneNoSignatures => 'Keystone 没有返回投票签名。请重新扫描结果。';

  @override
  String get votingErrorKeystoneNoSigningRequest => '没有等待签名的 Keystone 签名请求。';

  @override
  String votingErrorKeystoneQrPrepareFailed(String reason) {
    return '无法准备 Keystone 投票二维码：$reason';
  }

  @override
  String get votingErrorKeystoneResultMismatch =>
      '此 Keystone 结果与此处显示的投票二维码不匹配。请扫描对应的结果后重试。';

  @override
  String get votingErrorKeystoneSignatureConflict =>
      '此 Keystone 结果与已为此投票请求保存的签名冲突。请重新开始 Keystone 签名并扫描新生成的结果。';

  @override
  String get votingErrorKeystoneSignatureMismatch =>
      'Keystone 返回的签名与此投票请求不匹配。请扫描此处所示二维码对应的结果。';

  @override
  String get votingErrorKeystoneSignatureSaveFailed =>
      '无法保存 Keystone 签名。请重新扫描同一个 Keystone 结果。';

  @override
  String get votingErrorKeystoneSkipNeedsSignature =>
      '请至少签名一个 Keystone 票据包，然后再跳过其余票据包。';

  @override
  String get votingErrorLedgerCancelled => '已取消在 Ledger 上批准投票。';

  @override
  String votingErrorLedgerLocked(String instruction) {
    return '请解锁你的 Ledger。$instruction';
  }

  @override
  String get votingErrorLedgerNoPendingBundle => '没有等待批准的 Ledger 投票票据包。';

  @override
  String get votingErrorLedgerRejected => '你已在 Ledger 上拒绝投票签名。请重试并再次签名。';

  @override
  String get votingErrorLedgerSignatureConflict =>
      '此 Ledger 签名与已为此投票票据包保存的签名冲突。';

  @override
  String get votingErrorLedgerSignatureSaveFailed =>
      '无法保存 Ledger 投票签名。请重试此票据包。';

  @override
  String votingErrorLedgerWrongApp(String instruction) {
    return '$instruction然后重试。';
  }

  @override
  String votingErrorMinimumWeight(String amount, String snapshot) {
    return '投票要求截至$snapshot，至少拥有一个包含 $amount 的符合条件的屏蔽票据包。请切换到符合条件的账户后再投票。';
  }

  @override
  String votingErrorMinimumWeightReason(String amount, String snapshot) {
    return '投票要求截至$snapshot，至少拥有一个包含 $amount 的符合条件的屏蔽票据包';
  }

  @override
  String get votingErrorNoActiveAccount => '没有可用于投票会话的当前账户。';

  @override
  String votingErrorNoSpendableNotes(String snapshot) {
    return '此账户没有资格参与本轮投票。截至$snapshot，没有符合条件的屏蔽资金。请切换到符合条件的账户后再投票。';
  }

  @override
  String votingErrorNoSpendableNotesReason(String snapshot) {
    return '此账户没有资格参与本轮投票。截至$snapshot，没有符合条件的屏蔽资金';
  }

  @override
  String get votingErrorNoVoteChosen => '请在提交前至少选择一项投票。';

  @override
  String get votingErrorPirEndpointResolveFailed => '无法确定 PIR 服务器。';

  @override
  String get votingErrorPirEndpointUnresolved => '尚未确定 PIR 服务器。';

  @override
  String get votingErrorRoundDetailsUnavailable => '投票轮次详情尚不可用。请稍后重试。';

  @override
  String get votingErrorRoundEndTimeUnavailable => '无法获取投票轮次的结束时间。请稍后重试。';

  @override
  String get votingErrorSessionFailed => '投票操作失败。';

  @override
  String votingErrorSignBundleFirst(int bundle, String signer) {
    return '提交前请使用 $signer 签名委托票据包 $bundle。';
  }

  @override
  String votingErrorSignBundlesFirst(String signer) {
    return '提交前请使用 $signer 签名委托票据包。';
  }

  @override
  String votingErrorSignerAccountOnly(String signer) {
    return '$signer 投票仅适用于对应的硬件钱包账户。';
  }

  @override
  String get votingErrorSoftwareMnemonicRequired =>
      '软件委托需要此账户的助记词。请解锁此账户，或切换到可以访问助记词的账户。';

  @override
  String votingErrorVoteCastingFailed(String details) {
    return '投票失败：$details';
  }

  @override
  String votingErrorWalletSyncTimeout(
    String duration,
    String scanned,
    String snapshot,
  ) {
    return '钱包同步未能在 $duration 内到达本轮投票的快照。已扫描到区块 $scanned，快照区块为 $snapshot。请等待钱包同步追上后重试。';
  }

  @override
  String get votingForumDiscussion => '论坛讨论';

  @override
  String get votingGuardAccountLoadFailed => '无法加载账户';

  @override
  String get votingIneligibleTitle => '没有资格参与本轮投票';

  @override
  String get votingKeepSigning => '继续签名';

  @override
  String get votingKeepVoting => '继续投票';

  @override
  String votingKeystoneMemoLabel(int number, int total) {
    return '第 $number/$total 个票据包的备注';
  }

  @override
  String get votingKeystoneNextBatch => '下一批签名已就绪';

  @override
  String get votingKeystoneNextMemo => '下一个票据包的备注';

  @override
  String get votingKeystoneOneApproval => '只需 Keystone 批准一次';

  @override
  String get votingKeystonePreviousMemo => '上一个票据包的备注';

  @override
  String votingKeystoneQrPartial(int count, int total) {
    return '此二维码可签名剩余 $total 个票据包中的 $count 个';
  }

  @override
  String get votingKeystoneScanInstruction =>
      '用 Keystone 扫描此屏幕上的二维码，然后用本设备的摄像头扫描 Keystone 上显示的已签名投票二维码';

  @override
  String get votingKeystoneScanSignature => '扫描签名';

  @override
  String votingKeystoneSignLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '签名 $count 个投票票据包',
      zero: '正在准备投票签名',
    );
    return '$_temp0';
  }

  @override
  String get votingKeystoneUnexpectedUr => '请在 Keystone 上打开已签名的投票二维码，然后重新扫描。';

  @override
  String get votingLedgerApprovalNotice =>
      '在 Ledger 上批准即授权此投票委托。继续之前，请在 Vizor 中查看下方备注；设备可能不会逐字显示此备注。';

  @override
  String get votingLedgerConfirmOpenBody => '请在你的 Ledger 上批准打开 Zcash 应用的请求。';

  @override
  String get votingLedgerFinishing => '正在完成投票委托';

  @override
  String get votingLedgerPanelTitle => '投票委托';

  @override
  String get votingLedgerPleaseWait => '请稍候，Vizor 正在准备你的请求。';

  @override
  String get votingLedgerPreparing => '正在准备投票委托';

  @override
  String get votingLedgerReconnect => '请重新连接你的 Ledger 并重试。';

  @override
  String votingMobileAccountLoadFailed(String error) {
    return '无法加载账户。\n$error';
  }

  @override
  String get votingMobileHeaderTitle => '投票';

  @override
  String get votingMobileKeystoneChecking => '正在检查投票签名...';

  @override
  String get votingMobileKeystoneDescription =>
      '用 Keystone 扫描投票请求并批准，然后用本设备扫描已签名的结果。';

  @override
  String get votingMobileKeystoneFailedTitle => '投票签名失败';

  @override
  String get votingMobileKeystoneNextBundle => '下一个投票票据包';

  @override
  String get votingMobileKeystonePreviousBundle => '上一个投票票据包';

  @override
  String get votingMobileKeystoneReading => '正在读取投票签名...';

  @override
  String get votingMobileKeystoneScanCaption => '请扫描 Keystone 上显示的已签名投票二维码';

  @override
  String get votingMobileKeystoneSkipUnsigned => '跳过未签名的票据包';

  @override
  String get votingMobileKeystoneTitle => '使用 Keystone 签署投票';

  @override
  String get votingMobileLeaveWarning => '请勿离开此窗口。';

  @override
  String get votingMobileProgressSemantics => '当前投票提交步骤的进度';

  @override
  String get votingMobileProofNotice => '生成零知识证明可能需要约 60 秒，现在关闭可能会丢失正在进行的证明工作。';

  @override
  String get votingMobileSubmitTitle => '提交投票';

  @override
  String get votingMobileSubmittedBody => '你的投票已提交，无法更改。';

  @override
  String get votingMobileSubmittedTitle => '投票已提交';

  @override
  String get votingMobileSubmittingTitle => '正在提交投票...';

  @override
  String get votingNavAllAnswered => '所有问题均已回答';

  @override
  String votingNavAnsweredProgress(int answered, int total) {
    return '已回答 $answered/$total';
  }

  @override
  String get votingNavReadyToReview => '你的答案已可确认。';

  @override
  String get votingNavTapToJump => '点按问题即可跳转。';

  @override
  String votingNavUnansweredCount(int count) {
    return '未回答 · $count';
  }

  @override
  String get votingNavUnansweredMenu => '未回答的问题';

  @override
  String get votingNoProposalsBody => '此投票轮次不包含任何提案。';

  @override
  String get votingNoProposalsTitle => '没有提案';

  @override
  String get votingNotAvailable => '不可用';

  @override
  String get votingNotEligible => '没有资格';

  @override
  String get votingOptionChoose => '选择';

  @override
  String get votingOptionSelected => '已选择';

  @override
  String get votingPendingBody => '你在本轮有一次未完成的投票。请继续以完成提交。';

  @override
  String get votingPendingTitle => '投票进行中';

  @override
  String votingPirAhead(String expected, String reported) {
    return '已配置的 PIR 服务器领先于本轮投票的快照。预期快照区块为 $expected，服务器报告为 $reported。';
  }

  @override
  String votingPirBehind(String expected, String reported) {
    return '本轮投票的 PIR 数据尚未就绪。预期快照区块为 $expected，PIR 服务器报告为 $reported。请在 PIR 服务追上后重试。';
  }

  @override
  String votingPirNoMatch(String expected) {
    return '没有与本轮投票快照匹配的 PIR 服务器。预期快照区块为 $expected。';
  }

  @override
  String votingPirNoMatchDiagnostics(String expected, String diagnostics) {
    return '没有与本轮投票快照匹配的 PIR 服务器。预期快照区块为 $expected。诊断信息：$diagnostics。';
  }

  @override
  String get votingPirUnreachable => '无法连接到任何已配置的 PIR 服务器。请检查网络连接后重试。';

  @override
  String get votingPollAlreadyUsed => '本轮已使用';

  @override
  String votingPollClosed(String date) {
    return '$date已截止';
  }

  @override
  String votingPollCloses(String date) {
    return '$date截止';
  }

  @override
  String get votingPollNotEligible => '没有资格参与本轮';

  @override
  String votingPollStarts(String date) {
    return '$date开始';
  }

  @override
  String get votingPollsEmptyBody => '目前还没有可显示的代币持有者投票轮次。';

  @override
  String get votingPollsEmptyTitle => '暂无投票轮次';

  @override
  String get votingPollsLoadFailedTitle => '无法加载投票轮次';

  @override
  String votingPowerMeta(String amount) {
    return '投票权 $amount';
  }

  @override
  String get votingPowerUnavailableSentence => '无法获取投票权。';

  @override
  String get votingPowerUnavailableTitle => '无法获取投票权';

  @override
  String get votingPreparingPower => '正在准备投票权。';

  @override
  String get votingPreparingPowerMeta => '正在准备投票权';

  @override
  String votingPrivacyTrimNotice(String amount) {
    return '为降低你的提交被识别的可能性，$amount 不计入本次投票。';
  }

  @override
  String votingProgressBundlesProved(int proved, int total) {
    return '已证明 $proved/$total 个票据包';
  }

  @override
  String votingProgressFinalizingDelegation(String suffix) {
    return '正在完成委托$suffix';
  }

  @override
  String votingProgressReusingProof(String suffix) {
    return '正在复用进行中的证明$suffix';
  }

  @override
  String votingProgressWaitingConfirmation(String suffix) {
    return '正在等待提交和确认$suffix';
  }

  @override
  String get votingReceiptPower => '投票权';

  @override
  String votingRemainingBundles(int count, int total) {
    return '剩余 $total 个票据包中的 $count 个';
  }

  @override
  String get votingResultsFallbackTitle => '投票结果';

  @override
  String get votingResultsHideDescription => '收起说明';

  @override
  String votingResultsLoadFailed(String error) {
    return '无法加载结果：$error';
  }

  @override
  String get votingResultsNoProposals => '本轮没有提案。';

  @override
  String get votingResultsPending => '结果待公布...';

  @override
  String votingResultsRoundLoadFailed(String error) {
    return '无法加载投票轮次详情：$error';
  }

  @override
  String get votingResultsShowDescription => '展开说明';

  @override
  String votingResultsTotalAmount(String amount) {
    return '总计：$amount';
  }

  @override
  String votingResultsVotedFor(String choice) {
    return '已投：$choice';
  }

  @override
  String get votingResultsWinner => '获胜';

  @override
  String get votingResultsYourVote => '你的投票';

  @override
  String get votingReviewChooseOne => '提交前请至少选择一个选项。';

  @override
  String get votingReviewConfirmSubmit => '确认并提交';

  @override
  String votingReviewLoadFailed(String error) {
    return '无法加载确认页面：$error';
  }

  @override
  String get votingReviewSkipped => '已跳过';

  @override
  String get votingReviewTitle => '确认你的答案';

  @override
  String get votingScanHold => '请将 Keystone 二维码稳定地对准摄像头';

  @override
  String get votingScanNoCamera => 'Keystone 投票仅支持摄像头扫描二维码。请连接摄像头后重试。';

  @override
  String get votingScanTitle => '扫描投票签名';

  @override
  String get votingSignedOnlyBody => 'Vizor 现在可以仅使用已从 Keystone 扫描的签名进行提交。';

  @override
  String get votingSignedOnlyTitle => '仅使用已签名的票据包？';

  @override
  String get votingSignedOnlyWarning => '未签名的票据包将被跳过，这会降低本轮投票的投票权。';

  @override
  String get votingSkip => '跳过';

  @override
  String get votingSkipBundles => '跳过票据包';

  @override
  String votingSkipDialogBody(int skipped, int total) {
    return '你有 $skipped/$total 个问题尚未回答。确认页面会将它们标记为已跳过，已跳过的问题不会被提交。';
  }

  @override
  String get votingSkipDialogTitle => '跳过未回答的问题？';

  @override
  String votingSnapshotBlock(String height) {
    return '快照区块 $height';
  }

  @override
  String get votingSnapshotUnknown => '投票轮次快照区块';

  @override
  String get votingSoftwareRequiredBody => '代币持有者投票需要软件账户。要参与本轮投票，请切换到软件账户。';

  @override
  String get votingSoftwareRequiredTitle => '需要软件账户';

  @override
  String get votingStatusActive => '进行中';

  @override
  String get votingStatusBodyKeepOpen =>
      '请勿关闭窗口。生成零知识证明可能需要一些时间；现在关闭可能会丢失正在进行的证明工作。';

  @override
  String get votingStatusBodyLedger => '请保持 Vizor 打开，并按下方说明处理每个投票票据包。';

  @override
  String get votingStatusClosed => '已截止';

  @override
  String get votingStatusFailed => '投票失败。';

  @override
  String get votingStatusGenericError =>
      '此账户无法继续投票。请重试；如果此账户没有资格参与本轮投票，请切换到符合条件的账户。';

  @override
  String get votingStatusTallying => '计票中';

  @override
  String get votingStatusTitleLedger => '使用 Ledger 投票';

  @override
  String get votingStatusTitleSubmitting => '正在提交投票';

  @override
  String get votingStatusVoted => '已投票';

  @override
  String get votingStepCasting => '正在投票并提交份额';

  @override
  String get votingStepFinalizing => '正在完成提交';

  @override
  String get votingStepProving => '正在证明投票权限';

  @override
  String get votingStepSigningKeystone => '正在使用 Keystone 签名';

  @override
  String get votingStepSigningLedger => '正在使用 Ledger 签名';

  @override
  String get votingSubmissionInProgress => '投票仍在提交中。请等待提交完成后再删除账户或重置钱包。';

  @override
  String get votingSwitchAccount => '切换账户';

  @override
  String get votingSwitchEligibleGuidance => '请切换到符合条件的账户后再投票。';

  @override
  String votingSyncBlocksRemaining(int count) {
    return '剩余 $count 个区块';
  }

  @override
  String votingSyncChainTip(int height) {
    return '链顶区块 $height';
  }

  @override
  String votingSyncSynced(int height) {
    return '已同步至区块 $height';
  }

  @override
  String get votingSyncWaitingBody => '你的钱包正在追赶本轮投票的快照。钱包同步到快照区块后，投票将自动继续。';

  @override
  String votingTerminalBundle(int number, String reason) {
    return '第 $number 个票据包（$reason）';
  }

  @override
  String votingTerminalMultiple(String bundles) {
    return '$bundles 的委托无法继续。请勿重试，该交易可能已在链上。';
  }

  @override
  String get votingTerminalReasonDefault => '未经确认即已结束';

  @override
  String votingTerminalSingle(String bundle) {
    return '委托 $bundle 无法继续。请勿重试，该交易可能已在链上。';
  }

  @override
  String get votingTokenHolderTitle => '代币持有者投票';

  @override
  String get votingViewLess => '收起';

  @override
  String get votingViewMore => '展开';

  @override
  String get votingVoteLocked => '投票已锁定';

  @override
  String votingVotedOn(String date) {
    return '$date已投票';
  }

  @override
  String walletLinkAccountsFound(int count) {
    return '找到 $count 个账户';
  }

  @override
  String walletLinkAccountsReadySubtitle(int ready, int imported) {
    return '$ready 个账户可导入，$imported 个已导入。';
  }

  @override
  String walletLinkAlreadyImported(int count) {
    return '已导入 $count 个';
  }

  @override
  String get walletLinkCameraRequired => '扫描桌面端关联码需要此设备带有摄像头。';

  @override
  String walletLinkContactsFound(int count) {
    return '找到 $count 个联系人';
  }

  @override
  String walletLinkContactsReadySubtitle(int found, int imported) {
    return '找到 $found 个联系人，$imported 个已导入。';
  }

  @override
  String get walletLinkDeselectAll => '取消全选';

  @override
  String get walletLinkDesktopConfirmSubtitle => '以关联 Vizor 手机端。';

  @override
  String get walletLinkDesktopEncryptedNotice => '该二维码使用一次性密钥加密，一分钟后失效。';

  @override
  String get walletLinkDesktopEncryptedStrong => '只有你的手机能够解码。';

  @override
  String get walletLinkDesktopErrorDerivationMissing => '无法获取钱包账户的派生信息。';

  @override
  String get walletLinkDesktopErrorExpiredBeforeShown => '手机端关联码在显示前已过期。';

  @override
  String get walletLinkDesktopErrorFallback => '无法准备手机端关联。';

  @override
  String get walletLinkDesktopErrorHardwareMetadataMissing => '无法获取硬件钱包信息。';

  @override
  String get walletLinkDesktopErrorLocked => '关联手机端前，请先解锁此钱包。';

  @override
  String get walletLinkDesktopErrorNoAccounts => '没有可关联的钱包账户。';

  @override
  String get walletLinkDesktopErrorPrepareFailed => '无法准备手机端关联。请重试。';

  @override
  String get walletLinkDesktopErrorServerUnreachable => '无法连接到关联服务器。请重试。';

  @override
  String get walletLinkDesktopExpiredBody => '为了你的安全，关联码仅在一分钟内有效。请生成新二维码并重新扫描。';

  @override
  String walletLinkDesktopExpiresIn(String time) {
    return '$time后过期';
  }

  @override
  String get walletLinkDesktopGenerateNewCode => '生成新二维码';

  @override
  String get walletLinkDesktopInitialBody => '扫描一次性二维码，将此钱包连接到 Vizor 手机应用。';

  @override
  String get walletLinkDesktopLinkedBody => 'Vizor 手机端已与此钱包关联。';

  @override
  String walletLinkDesktopLinkedCounts(int accountCount, int contactCount) {
    return '已在手机端导入 $accountCount 个账户和 $contactCount 个联系人。';
  }

  @override
  String get walletLinkDesktopLinkedTitle => 'Vizor 手机端关联成功';

  @override
  String get walletLinkDesktopReadyToScan => '1/1 已可扫描...';

  @override
  String get walletLinkDesktopRegenerate => '重新生成';

  @override
  String get walletLinkDesktopScanBody => '在手机上打开 Vizor → 添加钱包 → 关联 Vizor 桌面版';

  @override
  String get walletLinkDesktopScanTitle => '用 Vizor 手机端扫描';

  @override
  String get walletLinkDesktopStartLinking => '开始关联';

  @override
  String get walletLinkDesktopTitle => '关联 Vizor 手机端';

  @override
  String get walletLinkDesktopUnavailableTitle => '无法关联';

  @override
  String get walletLinkErrorExpiredBody => '电脑上的二维码已超时。请在桌面端选择“生成新二维码”，然后重新扫描。';

  @override
  String get walletLinkErrorExpiredTitle => '链接已过期';

  @override
  String get walletLinkErrorFailedBody => '请确认桌面端上的二维码仍然显示，然后重新扫描。';

  @override
  String get walletLinkErrorFailedTitle => '无法打开此链接';

  @override
  String get walletLinkErrorInvalidBody =>
      '你扫描的二维码不是 Vizor 桌面端关联码。请在电脑上打开“设置 → 关联 Vizor 手机端”。';

  @override
  String get walletLinkErrorInvalidTitle => '二维码无效';

  @override
  String walletLinkImportContacts(int count) {
    return '导入 $count 个联系人';
  }

  @override
  String get walletLinkIntroNotice => '这会将钱包和联系人复制到手机。电脑上的内容不会有任何变化，两者均可继续使用。';

  @override
  String get walletLinkIntroReady => '我已准备好扫描';

  @override
  String get walletLinkIntroSubtitle => '将桌面端钱包复制到这部手机';

  @override
  String get walletLinkIntroTitle => '与桌面端关联';

  @override
  String walletLinkLinkAccounts(int count) {
    return '关联 $count 个账户';
  }

  @override
  String get walletLinkNothingNewSubtitle => '此桌面端关联码中没有可导入的新内容。';

  @override
  String get walletLinkNothingToImportBody => '此桌面端关联码中的所有内容都已在这部手机上。';

  @override
  String get walletLinkNothingToImportTitle => '没有可导入的内容';

  @override
  String get walletLinkReadingLink => '正在读取链接...';

  @override
  String get walletLinkScanCaption => '扫描 Vizor 桌面端二维码';

  @override
  String get walletLinkScanSubtitleDesktop => '扫描桌面端上的二维码';

  @override
  String get walletLinkSelectAll => '全选';

  @override
  String get walletLinkStepOpenSettings => '前往“设置 → 关联 Vizor 手机端”';

  @override
  String get walletLinkStepScanQr => '在下一个屏幕中扫描桌面端上的二维码。';

  @override
  String get walletLinkStepUnlockDesktop => '打开并解锁 Vizor 桌面应用';

  @override
  String get walletMutationBusy => '请先完成当前的钱包操作，再开始其他操作。';

  @override
  String get walletResetDeviceAuthFailed => '无法验证设备所有权，请重试。';

  @override
  String get walletResetDeviceAuthReason => '确认重置 Vizor';

  @override
  String get walletResetDeviceAuthRequired => '重置 Vizor 需要进行设备验证。';

  @override
  String get walletResetFailed => '无法重置 Vizor，请重试。';

  @override
  String get walletResetGiftCardInFlight => '仍在接收礼品卡，请等待完成。';

  @override
  String get walletResetGiftCardWarning => '仍在接收礼品卡，重置将导致其丢失。';

  @override
  String get windowsUpdateNotReady => '此更新已无法下载。请重新检查更新。';

  @override
  String get windowsUpdateTorRouteUnavailable =>
      '软件更新程序未连接到 Tor。请在设置中重试更新，或关闭 Tor 后重试。';
}
