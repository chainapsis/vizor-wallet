// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get accountsActionsLabel => '账户操作';

  @override
  String get accountsAdd => '添加账户';

  @override
  String get accountsAddressLoadFailed => '无法加载账户地址';

  @override
  String get accountsChangeProfilePicture => '更改头像';

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
  String get accountsEditNameLabel => '账户名称';

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
  String get accountsRemoveConfirm => '移除';

  @override
  String get accountsRemoveFailed => '无法移除账户。';

  @override
  String get accountsRemoveFailedToast => '无法移除账户';

  @override
  String get accountsRemoveGiftCardsCheckFailed => '无法检查此账户是否有正在接收的礼品卡。移除前请重试。';

  @override
  String get accountsRemoveMigrationBody =>
      '此账户的迁移将不再在 Vizor 中继续。已提交到 Zcash 网络的交易仍可能完成。重新导入后，请先让该账户完全同步，再重新开始迁移。';

  @override
  String get accountsRemoveModalBody => '确定要移除此账户吗？此操作无法撤销。\n你需要重新导入该账户。';

  @override
  String get accountsRemovePasswordCheckFailed => '无法验证你的密码，请重试。';

  @override
  String get accountsRemovePasswordHint => '请输入密码';

  @override
  String get accountsRemovePasswordIncorrect => '密码不正确，请重试。';

  @override
  String get accountsRemovePasswordLabel => '密码';

  @override
  String get accountsRemoveStoppingSync => '正在停止同步...';

  @override
  String get accountsRemoveSwapsCheckFailed => '无法检查此账户是否有进行中的兑换。移除前请重试。';

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
  String get accountsResetVizor => '重置 Vizor';

  @override
  String get accountsResetting => '正在重置...';

  @override
  String get accountsSaveEdits => '保存更改';

  @override
  String get accountsSaveFailed => '无法保存账户更改';

  @override
  String get accountsSelectProfilePicture => '选择头像';

  @override
  String get accountsSendFailed => '无法开始发送';

  @override
  String get accountsSendZec => '发送 ZEC';

  @override
  String get accountsTitle => '账户';

  @override
  String get accountsUpdatePicture => '更新头像';

  @override
  String get accountsViewSecretPhrase => '查看助记词';

  @override
  String get accountsViewViewingKey => '显示查看密钥';

  @override
  String get appBackAddAccount => '添加账户';

  @override
  String get appBackHardwareWallets => '硬件钱包';

  @override
  String get appBackImportMethods => '导入方式';

  @override
  String get appBackWalletBirthdayHeight => '钱包生日高度';

  @override
  String get appBackWelcome => '欢迎';

  @override
  String get appExitBackHint => '再次返回即可退出';

  @override
  String get appGiftCloseCardFailed => '无法关闭卡片。请重试。';

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
  String get appUpdateDownload => '下载';

  @override
  String get appUpdateDownloading => '下载中';

  @override
  String appUpdateDownloadingMessage(int percent) {
    return '已下载 $percent%。';
  }

  @override
  String get appUpdateDownloadingTitle => '正在下载更新';

  @override
  String get appUpdateFailedMessage => '无法完成更新。请重试。';

  @override
  String get appUpdateFailedTitle => '更新失败';

  @override
  String get appUpdateLater => '稍后';

  @override
  String get appUpdateReadyMessage => '准备好后请重启。';

  @override
  String get appUpdateReadyTitle => '更新已就绪';

  @override
  String get appUpdateRestart => '重启';

  @override
  String get appUpdateRestarting => '重启中';

  @override
  String get appUpdateRestartingTitle => '正在重启 Vizor';

  @override
  String get appUpdateTryAgain => '重试';

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
  String get commonAddressCopied => '地址已复制';

  @override
  String get commonBack => '返回';

  @override
  String commonBackTo(String destination) {
    return '返回$destination';
  }

  @override
  String get commonCancel => '取消';

  @override
  String get commonCancellationFailed => '无法完成取消，请重试。';

  @override
  String get commonClearText => '清除文本';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonCopyAddress => '复制地址';

  @override
  String get commonDismissNotification => '关闭通知';

  @override
  String get commonFeatureInProgress => '此功能仍在开发中。';

  @override
  String get commonInformation => '信息';

  @override
  String get commonNotAvailableYet => '暂不可用';

  @override
  String get commonOk => '好';

  @override
  String get commonSensitiveContentHidden => '敏感内容已隐藏';

  @override
  String get commonUpdate => '更改';

  @override
  String get commonUpdating => '正在更改...';

  @override
  String get homeActivityEmpty => '暂无活动...';

  @override
  String get homeActivityEmptyHint => '不如发起你的第一笔 ZEC 交易？';

  @override
  String get homeActivityEmptyHintMobile => '不如发起你的\n第一笔 ZEC 交易？';

  @override
  String get homeActivityLoading => '正在加载活动';

  @override
  String get homeActivityUnavailable => '无法加载活动。';

  @override
  String get homeBackupSubtitle => '备份你的助记词\n最后一步';

  @override
  String get homeBackupTitle => '保护你的钱包';

  @override
  String get homeDismiss => '忽略';

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
  String get homeKeepAwakeEnable => '保持屏幕常亮';

  @override
  String get homeKeepAwakeLater => '以后再说';

  @override
  String get homeKeepAwakeLockNote => '1 分钟无操作后应用会锁定，同步仍会在锁定状态下继续。';

  @override
  String get homeKeepAwakeSettingsNote => '你可以随时在设置中更改。';

  @override
  String get homeKeepAwakeTitle => '同步时保持屏幕常亮？';

  @override
  String get homeLedgerActionNeeded => '需要操作';

  @override
  String get homeLedgerApprovalNotAccepted => '你的 Ledger 无法接受此次批准。之前的批准已发送。';

  @override
  String get homeLedgerBroadcastNotStored => '屏蔽交易已到达网络，但未保存在本地。在同步确认之前，请勿重试。';

  @override
  String get homeLedgerBroadcastUnknown => '屏蔽交易可能已到达网络。重试前请先查看活动。';

  @override
  String get homeLedgerCancelShielding => '取消屏蔽';

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
  String get homeLedgerSigningFailedTitle => 'Ledger 签名失败';

  @override
  String homeLoadFailed(String details) {
    return '出了点问题，请稍后重试。\n\n详情：$details';
  }

  @override
  String get homeMigrateToIronwood => '迁移到 Ironwood';

  @override
  String get homeMigrationRequired => '需要迁移';

  @override
  String get homeMigrationRequiredTitle => '需要迁移';

  @override
  String homeMigrationStillMigrating(String amount) {
    return '$amount 仍在迁移';
  }

  @override
  String get homeMigrationStoppedByUpgrade => '迁移因网络升级而停止';

  @override
  String get homeMigrationWaitingConfirmation => '正在等待确认...';

  @override
  String get homeNu7FasterBody => '首次确认的平均等待时间从约 75 秒缩短到约 25 秒。';

  @override
  String get homeNu7FasterTitle => '区块速度提升约 3×';

  @override
  String get homeNu7GotIt => '知道了';

  @override
  String get homeNu7ThroughputBody => '每个区块可处理的屏蔽交易增加到 2.3x。';

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
  String get homeSetupCarouselLabel => '钱包设置';

  @override
  String get homeSetupCarouselName => '钱包设置横幅';

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
  String get homeShieldBackToWallet => '返回钱包';

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
  String get homeShieldCameraUnavailable => '相机暂时不可用。';

  @override
  String get homeShieldCancelFailed => '无法完成取消，请重试。';

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
  String get homeShieldErrorGeneric => '屏蔽余额失败，请重试。';

  @override
  String get homeShieldErrorNotFinalized => '无法完成屏蔽交易。';

  @override
  String get homeShieldErrorProvingParams => '无法准备所需的证明参数。';

  @override
  String get homeShieldErrorSignatureNotApplied => '无法应用 Keystone 签名。';

  @override
  String get homeShieldErrorSigningNotPrepared => '无法准备 Keystone 签名。';

  @override
  String get homeShieldErrorSyncFirst => '屏蔽透明余额之前，请先同步钱包。';

  @override
  String get homeShieldErrorTooSmall => '扣除手续费后，透明余额太少，无法屏蔽。';

  @override
  String get homeShieldFailedTitle => '无法完成屏蔽';

  @override
  String get homeShieldGetSignature => '获取签名';

  @override
  String get homeShieldKeepOpen => '交易发送期间请保持 Vizor 打开。';

  @override
  String get homeShieldKeystoneQrSemantics => 'Keystone 交易二维码';

  @override
  String get homeShieldNextStep => '下一步';

  @override
  String get homeShieldNoActiveAccount => '没有活动账户。';

  @override
  String get homeShieldNow => '立即屏蔽';

  @override
  String get homeShieldQueuedTitle => '屏蔽已加入队列';

  @override
  String get homeShieldReadingSignature => '正在读取签名…';

  @override
  String get homeShieldReject => '拒绝';

  @override
  String get homeShieldScanDecodeFailed => '无法将此二维码解码为 Keystone 签名。';

  @override
  String get homeShieldScanHold => '请保持二维码稳定且完整可见。';

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
  String get homeShieldSubmitting => '正在提交交易';

  @override
  String get homeShieldSucceededTitle => '屏蔽成功';

  @override
  String get homeShieldToggleFlashlight => '切换手电筒';

  @override
  String get homeShieldTryAgain => '重试';

  @override
  String get homeShieldedBalance => '屏蔽余额';

  @override
  String get homeShieldingBalance => '正在屏蔽你的余额…';

  @override
  String get homeShieldingProgress => '正在屏蔽...';

  @override
  String homeTransparentBalance(String balance) {
    return '透明：$balance';
  }

  @override
  String get homeVotingSemantics => '打开持币者投票';

  @override
  String get homeVotingSubtitle => '参与塑造网络未来';

  @override
  String get homeVotingTitle => '持币者投票';

  @override
  String get keyringLockedBody =>
      'Vizor 无法访问系统密钥环。请解锁密钥环，然后选择“重试”。系统可能会要求输入密钥环密码。';

  @override
  String get keyringNoResponse => '密钥环没有响应。请重试。';

  @override
  String get keyringOpenFailedTitle => '无法打开 Vizor';

  @override
  String get keyringOpeningTitle => '正在打开 Vizor';

  @override
  String get keyringPromptBody => '请完成系统密钥环提示以继续使用 Vizor。';

  @override
  String get keyringQuit => '退出';

  @override
  String get keyringRestartHint => '请退出并重新启动 Vizor 后重试。';

  @override
  String get keyringRetry => '重试';

  @override
  String get keyringSaveUnconfirmedBody =>
      'Vizor 无法确认您的更改是否已保存。请先退出并重新启动 Vizor 再继续。';

  @override
  String get keyringSaveUnconfirmedTitle => '无法确认保存';

  @override
  String get keyringTryingTitle => '正在尝试访问安全存储';

  @override
  String get keyringUnavailableBody => 'Vizor 无法连接到系统密钥环。请重试，或退出并重新启动 Vizor。';

  @override
  String get keyringUnavailableTitle => '安全存储不可用';

  @override
  String get keyringUnlockTitle => '解锁密钥环';

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
  String get keystoneBackWelcome => '欢迎页';

  @override
  String get keystoneBirthdayDatePlaceholder => 'mm/dd/yyyy';

  @override
  String get keystoneBirthdayEstimateError => '无法估算钱包创建高度。';

  @override
  String get keystoneBirthdayEstimating => '正在估算...';

  @override
  String get keystoneBirthdayHeightHint => '区块高度';

  @override
  String get keystoneBirthdayInvalidHeight => '这似乎不是有效的区块高度。';

  @override
  String get keystoneBirthdayMetadataError => '无法加载钱包创建高度信息。';

  @override
  String get keystoneBirthdayStopSyncing => '正在停止同步...';

  @override
  String get keystoneBirthdaySubtitle => '这有助于我们更快地导入你的钱包。';

  @override
  String get keystoneBirthdayTabBlockHeight => '输入区块高度';

  @override
  String get keystoneBirthdayTabDate => '输入日期';

  @override
  String get keystoneBirthdayTitle => '你大约是什么时候创建钱包的？';

  @override
  String get keystoneBirthdayUnknown => '我不记得了';

  @override
  String get keystoneCameraDeniedBody => '请重新请求，或在系统设置中\n手动开启。';

  @override
  String get keystoneCameraDeniedTitle => '你已拒绝相机权限';

  @override
  String get keystoneCameraEnableBody => '连接 Keystone 需要使用相机。\n你之后可随时在设置中更改。';

  @override
  String get keystoneCameraEnableTitle => '启用相机权限';

  @override
  String get keystoneCameraRequestAgain => '重新请求';

  @override
  String get keystoneCameraRestrictedBody => '屏幕使用时间或设备管理\n正在阻止使用相机。';

  @override
  String get keystoneCameraRestrictedTitle => '相机访问受限';

  @override
  String get keystoneCameraTryAgain => '重试';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone 导入仅支持摄像头扫描二维码。\n请连接摄像头后重试。';

  @override
  String get keystoneCameraUnavailableTitle => '相机不可用';

  @override
  String get keystoneConfirmSelection => '确认选择';

  @override
  String get keystoneConnectTitle => '连接 Keystone';

  @override
  String get keystoneContinue => '继续';

  @override
  String get keystoneFirmwareBody => '请确认你的 Keystone 已升级到最新的 Cypherpunk 固件。 ';

  @override
  String get keystoneFirmwareDownloadSemantics => '下载 Keystone 固件';

  @override
  String get keystoneFirmwareLinkLabel => '链接';

  @override
  String get keystoneFirmwareTitle => '检查 Keystone 固件';

  @override
  String get keystoneImReadyNow => '我已准备好';

  @override
  String get keystoneImporting => '正在导入...';

  @override
  String get keystoneOnVizor => '在 Vizor 中';

  @override
  String get keystoneOnYourKeystone => '在 Keystone 上';

  @override
  String get keystonePrepareSubtitle => '请准备好你的 Keystone 钱包';

  @override
  String get keystonePrepareToConnectTitle => '准备连接';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone 导入仅支持使用摄像头扫描二维码。请连接摄像头后重试。';

  @override
  String get keystoneScanCaption => '扫描 Keystone 账户二维码';

  @override
  String get keystoneScanDecodeFailed => '无法将此二维码解码为 Keystone Zcash 账户。';

  @override
  String get keystoneScanKeepSteady => '请保持二维码稳定并完整显示在画面中。';

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
  String get keystoneScanTitle => '扫描二维码';

  @override
  String get keystoneSelectAccountTitle => '选择账户';

  @override
  String get keystoneStepCustomiseWallet => '自定义钱包';

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
  String get keystoneStepSetPassword => '设置密码';

  @override
  String get keystoneStepWalletBirthdayHeight => '钱包创建高度';

  @override
  String languageSystemOption(String language) {
    return '系统（$language）';
  }

  @override
  String get ledgerAccountIndexHint => '除非此 Ledger 账户使用过其他索引，否则请保持为 0。';

  @override
  String get ledgerAccountIndexLabel => '账户索引（0–100）';

  @override
  String get ledgerAddAccountNote => '你可在 Vizor 中查看余额和活动。交易仍需在 Ledger 上批准。';

  @override
  String get ledgerAddAccountTitle => '添加 Ledger 账户';

  @override
  String get ledgerAdvancedOptions => '高级选项';

  @override
  String get ledgerBackAddAccount => '添加账户';

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
  String get ledgerBluetoothPermissionRequired =>
      '查找 Ledger 需要蓝牙权限。请在设置中允许，然后重试。';

  @override
  String get ledgerCancelFailed => '无法完成取消。请重试。';

  @override
  String get ledgerCancellingRequest => '正在取消请求';

  @override
  String get ledgerCancellingTheRequest => '正在取消 Ledger 请求…';

  @override
  String get ledgerCheckingBluetoothAccess => '正在检查蓝牙权限…';

  @override
  String get ledgerChooseAnother => '选择其他 Ledger';

  @override
  String get ledgerCleanupFailed => '无法完成清理。请重试。';

  @override
  String get ledgerConfirmOpeningZcash => '请在 Ledger 上确认打开 Zcash。';

  @override
  String get ledgerConnect => '连接 Ledger';

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
  String get ledgerCouldNotConnect => '无法连接 Ledger';

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
  String get ledgerErrorViewingKeyDeclined =>
      '[security] 你在 Ledger 上拒绝了查看密钥请求。准备好后请重试。';

  @override
  String get ledgerErrorViewingKeyRejected => '你在 Ledger 上拒绝了查看密钥请求。';

  @override
  String get ledgerFind => '查找 Ledger';

  @override
  String get ledgerFindMyLedger => '查找我的 Ledger';

  @override
  String ledgerKeepAppOpen(String appName) {
    return '请保持 $appName 应用处于打开状态。';
  }

  @override
  String get ledgerKeepConnectedUntilCancelled => '请保持 Ledger 连接，直到当前请求被取消。';

  @override
  String get ledgerKeepConnectedWhileChecking => 'Vizor 检查应用期间，请保持 Ledger 连接。';

  @override
  String get ledgerKeepNearbyUnlocked => '请将 Ledger 放在附近并保持解锁，同时开启蓝牙。';

  @override
  String get ledgerKeepZcashOpen => '请保持 Zcash 应用处于打开状态。';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS 可能会请求蓝牙权限。如果出现提示，请允许 Vizor 访问。';

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
  String get ledgerOpenBluetoothSettingsManually => '请手动打开蓝牙设置以移除旧的配对。';

  @override
  String get ledgerOpenZcashThenTryAgain => '请打开 Zcash 应用，然后重试。';

  @override
  String get ledgerReturningToOptions => '正在返回连接选项…';

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
  String get ledgerStepAddAccount => '添加账户';

  @override
  String get ledgerStepApproveViewingKey => '批准查看密钥';

  @override
  String get ledgerStepCustomiseWallet => '自定义钱包';

  @override
  String ledgerStepOpenApp(String appName) {
    return '打开 $appName';
  }

  @override
  String get ledgerStepOpenZcash => '打开 Zcash';

  @override
  String get ledgerStepSetPassword => '设置密码';

  @override
  String get ledgerStepWalletBirthdayHeight => '钱包创建高度';

  @override
  String get ledgerStoppingSearch => '正在停止搜索';

  @override
  String get ledgerSupportedDevices => '支持的设备';

  @override
  String get ledgerTransportBluetooth => '蓝牙';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerTryAgain => '重试';

  @override
  String get ledgerUnlockBluetoothNearby => '请解锁 Ledger，开启蓝牙，并将其放在附近。';

  @override
  String get ledgerUnlockWithPin => '使用 PIN 码解锁。';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor 正在检查 Zcash 应用。';

  @override
  String get lockBodyPaused => '同步已暂停。解锁 Vizor 以继续。';

  @override
  String get lockBodySynced => '同步成功。解锁 Vizor 以继续。';

  @override
  String get lockCheckingPasscode => '正在验证数字密码...';

  @override
  String get lockConfirmPasscodeSemantics => '确认数字密码以解锁 Vizor';

  @override
  String get lockNavSynced => '已同步';

  @override
  String lockNavSyncing(int percent) {
    return '正在同步 $percent%...';
  }

  @override
  String get lockPasscodeIncorrect => '数字密码不正确';

  @override
  String get lockSyncCompleteTitle => '同步完成';

  @override
  String get lockSyncPausedSemantics => 'Vizor 同步已暂停';

  @override
  String get lockSyncPausedTitle => '同步已暂停';

  @override
  String get lockSyncedSemantics => 'Vizor 已同步';

  @override
  String get lockSyncingMessage => 'Vizor 正在同步';

  @override
  String get lockUnlockToContinue => '解锁以继续';

  @override
  String get lockUnlockToContinueBody => '解锁 Vizor 以继续';

  @override
  String get lockUnlockToContinuePausedBody => '解锁 Vizor 以继续。';

  @override
  String get lockUnlockVizor => '解锁 Vizor';

  @override
  String get lockWelcomeBack => '欢迎回来';

  @override
  String get navActivity => '活动';

  @override
  String get navHome => '首页';

  @override
  String get navPay => '支付';

  @override
  String get navSettings => '设置';

  @override
  String get navSignOut => '退出';

  @override
  String get navSwap => '兑换';

  @override
  String get navVote => '投票';

  @override
  String get poolShielded => '屏蔽';

  @override
  String get poolTransparent => '透明';

  @override
  String get profilePictureUpdateFailed => '无法更改头像。';

  @override
  String get receiptMessageLabel => '消息';

  @override
  String get settingsLanguageLabel => '语言';

  @override
  String get settingsLanguageUpdateFailed => '无法更改语言。';

  @override
  String get sidebarAccountNameFallback => '用户名';

  @override
  String get sidebarAddressCopyFailed => '无法复制地址';

  @override
  String get sidebarCopyShieldedAddress => '复制屏蔽地址';

  @override
  String get sidebarHideBalance => '隐藏余额';

  @override
  String get sidebarImporting => '正在导入...';

  @override
  String get sidebarManageAccounts => '管理';

  @override
  String get sidebarMigrating => '迁移中...';

  @override
  String get sidebarMigrationNeedsInput => '需要操作';

  @override
  String get sidebarMigrationStopped => '迁移已停止';

  @override
  String get sidebarMyAccounts => '我的账户';

  @override
  String get sidebarShieldedAddressCopied => '屏蔽地址已复制';

  @override
  String get sidebarShowBalance => '显示余额';

  @override
  String get syncSynced => '已同步';

  @override
  String syncSyncedAtBlock(String height) {
    return '已同步至区块 $height';
  }

  @override
  String get txFeeInfoDescription =>
      '网络手续费由 Zcash 协议（ZIP 317）根据交易大小确定。Vizor 不收取额外费用。';

  @override
  String get txFeeInfoTitle => '交易手续费';

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
  String get walletLinkContinue => '继续';

  @override
  String get walletLinkDeselectAll => '取消全选';

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
      '你扫描的二维码不是 Vizor 桌面端关联码。请在电脑上打开 设置 → 关联 Vizor 手机端。';

  @override
  String get walletLinkErrorInvalidTitle => '二维码无效';

  @override
  String get walletLinkGoBack => '返回';

  @override
  String walletLinkImportContacts(int count) {
    return '导入 $count 个联系人';
  }

  @override
  String get walletLinkImportContactsTitle => '导入联系人';

  @override
  String get walletLinkImporting => '正在导入...';

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
  String get walletLinkScanAgain => '重新扫描';

  @override
  String get walletLinkScanCaption => '扫描 Vizor 桌面端二维码';

  @override
  String get walletLinkScanSubtitleDesktop => '扫描桌面端上的二维码';

  @override
  String get walletLinkScanTitle => '扫描二维码';

  @override
  String get walletLinkSelectAccountTitle => '选择账户';

  @override
  String get walletLinkSelectAll => '全选';

  @override
  String get walletLinkStepOpenSettings => '前往 设置 → 关联 Vizor 手机端';

  @override
  String get walletLinkStepScanQr => '在下一个屏幕中扫描桌面端上的二维码。';

  @override
  String get walletLinkStepUnlockDesktop => '打开并解锁 Vizor 桌面应用';
}
