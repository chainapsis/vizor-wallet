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
  String get onboardingAccountName => '账户名称';

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
  String get onboardingAddressShieldedLabel => '屏蔽地址';

  @override
  String get onboardingAddressShieldedTitleMobile => '屏蔽地址';

  @override
  String get onboardingAddressTransparentDescription =>
      '地址以 t 开头，与 Bitcoin 类似，该地址的余额和交易记录对所有人公开可见。';

  @override
  String get onboardingAddressTransparentLabel => '透明地址';

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
  String get onboardingAddressTypesTitleMobile => 'Zcash 地址类型';

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
  String onboardingBip39PassphrasePreview(String passphrase) {
    return 'BIP39 密码短语：$passphrase';
  }

  @override
  String get onboardingBip39PassphraseTitle => 'BIP39 密码短语';

  @override
  String get onboardingBip39PassphraseTitleOptional => 'BIP39 密码短语（可选）';

  @override
  String get onboardingBirthdayCantRemember => '我不记得了';

  @override
  String get onboardingBirthdayDateHint => 'mm/dd/yyyy';

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
  String get onboardingBirthdayMetadataFailed => '无法加载钱包创建时间数据。';

  @override
  String get onboardingBirthdayMobileEstimateFailed =>
      '无法估算该日期对应的区块高度。请改为输入区块高度。';

  @override
  String get onboardingBirthdayMonthHint => 'mm/yyyy';

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
  String get onboardingBirthdayTitle => '你大约是什么时候创建的钱包？';

  @override
  String get onboardingBlockHeight => '区块高度';

  @override
  String get onboardingCalendarMonthApril => '四月';

  @override
  String get onboardingCalendarMonthAugust => '八月';

  @override
  String get onboardingCalendarMonthDecember => '十二月';

  @override
  String get onboardingCalendarMonthFebruary => '二月';

  @override
  String get onboardingCalendarMonthJanuary => '一月';

  @override
  String get onboardingCalendarMonthJuly => '七月';

  @override
  String get onboardingCalendarMonthJune => '六月';

  @override
  String get onboardingCalendarMonthMarch => '三月';

  @override
  String get onboardingCalendarMonthMay => '五月';

  @override
  String get onboardingCalendarMonthNovember => '十一月';

  @override
  String get onboardingCalendarMonthOctober => '十月';

  @override
  String get onboardingCalendarMonthSeptember => '九月';

  @override
  String get onboardingCalendarMonthShortApr => '四月';

  @override
  String get onboardingCalendarMonthShortAug => '八月';

  @override
  String get onboardingCalendarMonthShortDec => '十二月';

  @override
  String get onboardingCalendarMonthShortFeb => '二月';

  @override
  String get onboardingCalendarMonthShortJan => '一月';

  @override
  String get onboardingCalendarMonthShortJul => '七月';

  @override
  String get onboardingCalendarMonthShortJun => '六月';

  @override
  String get onboardingCalendarMonthShortMar => '三月';

  @override
  String get onboardingCalendarMonthShortMay => '五月';

  @override
  String get onboardingCalendarMonthShortNov => '十一月';

  @override
  String get onboardingCalendarMonthShortOct => '十月';

  @override
  String get onboardingCalendarMonthShortSep => '九月';

  @override
  String get onboardingCalendarWeekdayFri => '周五';

  @override
  String get onboardingCalendarWeekdayMon => '周一';

  @override
  String get onboardingCalendarWeekdaySat => '周六';

  @override
  String get onboardingCalendarWeekdaySun => '周日';

  @override
  String get onboardingCalendarWeekdayThu => '周四';

  @override
  String get onboardingCalendarWeekdayTue => '周二';

  @override
  String get onboardingCalendarWeekdayWed => '周三';

  @override
  String get onboardingChangeProfilePicture => '更换头像';

  @override
  String get onboardingCheckingAccounts => '正在检查账户...';

  @override
  String get onboardingClear => '清除';

  @override
  String get onboardingConfirmPassword => '确认密码';

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
  String get onboardingConnectLedger => '连接 Ledger';

  @override
  String get onboardingContinue => '继续';

  @override
  String get onboardingContinueAnywayDesktop => '仍然继续';

  @override
  String get onboardingContinueAnywayMobile => '仍然继续';

  @override
  String get onboardingCopy => '复制';

  @override
  String get onboardingCopySecretPassphrase => '复制助记词';

  @override
  String get onboardingCreatingWallet => '正在创建钱包...';

  @override
  String get onboardingCustomiseAccount => '自定义账户';

  @override
  String get onboardingCustomiseAccountSubtitle => '设置账户名称并选择头像，为你的账户增添个性。';

  @override
  String get onboardingDiscoverySubtitle => '请选择要导入的其他账户。';

  @override
  String get onboardingDiscoveryTitle => '发现其他账户';

  @override
  String get onboardingEdit => '编辑';

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
  String get onboardingForgotPasscodeProceed => '请自行承担风险后继续。';

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
  String get onboardingGoBackMobile => '返回';

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
  String get onboardingImporting => '正在导入...';

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
  String get onboardingLoading => '加载中';

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
  String get onboardingManualInvalidWord => '助记词中没有这个单词。';

  @override
  String get onboardingManualNextWord => '下一个单词';

  @override
  String get onboardingManualReviewFinish => '检查并完成';

  @override
  String onboardingManualStoppedAt(String word) {
    return '已在 \'$word\' 处停止——它不在助记词单词表中。';
  }

  @override
  String get onboardingManualSubtitle => '支持 12、15、18、21 或 24 个单词';

  @override
  String get onboardingManualTitle => '输入你的助记词';

  @override
  String get onboardingManualUndoLastWord => '撤销上一个单词';

  @override
  String get onboardingNetworkCheckingEndpoint => '正在检查端点…';

  @override
  String onboardingNetworkCurrentEndpoint(String endpoint) {
    return '当前：$endpoint';
  }

  @override
  String get onboardingNetworkCustomEndpoint => '自定义端点';

  @override
  String get onboardingNetworkEndpointHelper =>
      '请使用适用于此钱包所在网络的 lightwalletd 服务器。';

  @override
  String get onboardingNetworkEndpointUpdated => '端点已更新';

  @override
  String get onboardingNetworkSaveFailed => '无法保存端点。请重试。';

  @override
  String get onboardingNetworkSettings => '网络设置';

  @override
  String get onboardingNetworkUpdateEndpoint => '更新端点';

  @override
  String get onboardingNetworkVerifyFailed => '无法验证该端点。请检查地址后重试。';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingNotNow => '暂不';

  @override
  String get onboardingPasscodeConfirmTitle => '确认数字密码';

  @override
  String get onboardingPasscodeCreateTitle => '创建数字密码';

  @override
  String onboardingPasscodeDigitSemantics(int digit) {
    return '数字 $digit';
  }

  @override
  String get onboardingPasscodeIncorrect => '数字密码不正确';

  @override
  String get onboardingPasscodeReEnter => '请再次输入数字密码。';

  @override
  String get onboardingPasscodeSettingUp => '正在设置你的钱包...';

  @override
  String get onboardingPasscodeSixDigits => '6 位数字';

  @override
  String get onboardingPasscodesDidNotMatch => '两次输入的数字密码不一致。请重试。';

  @override
  String get onboardingPassword => '密码';

  @override
  String get onboardingPasswordsDoNotMatch => '两次输入的密码不一致。';

  @override
  String get onboardingQuit => '退出';

  @override
  String get onboardingRandomiseAccountPersona => '随机更换账户名称和头像';

  @override
  String get onboardingRecoveringWallet => '正在恢复钱包...';

  @override
  String get onboardingResetAppFailed => '无法重置应用。请重试。';

  @override
  String get onboardingResetCannotBeUndone => '此操作无法撤销。';

  @override
  String get onboardingResetVizor => '重置 Vizor';

  @override
  String get onboardingResumeSetupFailed => '无法继续设置。请重试。';

  @override
  String get onboardingRetry => '重试';

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
  String get onboardingSave => '保存';

  @override
  String get onboardingSavingWallet => '正在保存钱包...';

  @override
  String get onboardingSecretPassphrase => '助记词';

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
  String get onboardingSelectProfilePicture => '选择头像';

  @override
  String get onboardingSetPassword => '设置密码';

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
  String get onboardingStepCustomiseWallet => '自定义钱包';

  @override
  String get onboardingStepImportContacts => '导入联系人';

  @override
  String get onboardingStepIntroToZcash => 'Zcash 简介';

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
  String get onboardingStorageKeyringLockedTitle => '请解锁密钥环';

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
  String get onboardingStorageStartupFailureTitle => '无法打开 Vizor';

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
  String get onboardingTryAgain => '重试';

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
  String get onboardingUnlockButton => '解锁 Vizor';

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
  String get onboardingUnlockWelcomeBackMobile => '欢迎回来';

  @override
  String get onboardingWelcome => '欢迎';

  @override
  String get onboardingWelcomeActivateGiftCard => '激活礼品卡';

  @override
  String get onboardingWelcomeGetStarted => '开始使用';

  @override
  String get onboardingWelcomeImportWallet => '导入钱包';

  @override
  String get poolShielded => '屏蔽';

  @override
  String get poolTransparent => '透明';

  @override
  String get profilePictureUpdateFailed => '无法更改头像。';

  @override
  String get receiptMessageLabel => '消息';

  @override
  String get settingsAccountChangedPasscode => '所选账户已更改。请重新输入数字密码。';

  @override
  String get settingsAccountChangedPassword => '所选账户已更改。请重新输入密码。';

  @override
  String get settingsAccountSaveFailed => '无法保存账户更改';

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
  String get settingsBip39PassphraseTitle => 'BIP39 密码短语';

  @override
  String settingsBip39PassphraseValue(String passphrase) {
    return 'BIP39 密码短语：$passphrase';
  }

  @override
  String get settingsBirthdayBlockHeight => '创建区块高度';

  @override
  String get settingsBirthdayDate => '创建日期';

  @override
  String get settingsBirthdayDateCopied => '已复制创建日期';

  @override
  String get settingsBirthdayHeightCopied => '已复制创建区块高度';

  @override
  String get settingsChangePasscodeIncorrect => '数字密码错误';

  @override
  String get settingsConfirmAccessSubtitle => '确认你的访问';

  @override
  String get settingsConfirmAccessTitle => '确认访问';

  @override
  String get settingsConfirmPasscodeTitle => '确认数字密码';

  @override
  String get settingsConfirmPasswordLabel => '确认密码';

  @override
  String get settingsContinue => '继续';

  @override
  String get settingsCopy => '复制';

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
  String settingsEndpointCurrent(String endpoint) {
    return '当前：$endpoint';
  }

  @override
  String get settingsEndpointCurrentPrefix => '当前：';

  @override
  String get settingsEndpointCustom => '自定义节点';

  @override
  String get settingsEndpointCustomise => '自定义节点';

  @override
  String get settingsEndpointCustomize => '自定义节点';

  @override
  String get settingsEndpointDefaultMarker => '（默认）';

  @override
  String get settingsEndpointNetworkSettings => '网络设置';

  @override
  String get settingsEndpointSelectFromList => '从列表选择';

  @override
  String get settingsEndpointTitle => '节点';

  @override
  String get settingsEndpointUpdate => '更新节点';

  @override
  String get settingsEndpointUpdatedToast => '节点已更新';

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
  String get settingsExplorerCustomSubtitle => '任何你喜欢的浏览器';

  @override
  String get settingsExplorerSaveFailed => '无法保存该浏览器网址。';

  @override
  String get settingsExplorerTitle => '区块浏览器';

  @override
  String get settingsExplorerUpdate => '更新浏览器';

  @override
  String get settingsExplorerUrlLabel => '浏览器网址';

  @override
  String get settingsIncorrectPasscode => '数字密码错误';

  @override
  String get settingsIncorrectPassword => '密码错误。请重试。';

  @override
  String get settingsKeepAwakeDescription =>
      '防止手机进入休眠，使同步更快完成。应用仍会在闲置 1 分钟后锁定。';

  @override
  String get settingsKeepAwakeLabel => '保持屏幕常亮';

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
  String get settingsPasscodeLengthHint => '6 位数字';

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
  String get settingsPasscodesMismatch => '两次输入的数字密码不一致。请重试。';

  @override
  String get settingsPasswordCheckFailed => '无法验证你的密码。请重试。';

  @override
  String get settingsPasswordHint => '输入密码...';

  @override
  String get settingsPasswordLabel => '密码';

  @override
  String get settingsPasswordMinimumHint => '至少 8 个字符。加入数字和符号，或使用更长的密码，可提高安全性。';

  @override
  String get settingsPasswordRotationRecoveryFailed =>
      '我们无法验证上一次的密码修改。重试前请妥善备好你的助记词。';

  @override
  String get settingsPasswordUpdateFailed => '无法更新你的密码。请重试。';

  @override
  String get settingsPasswordsMismatch => '两次输入的密码不一致。';

  @override
  String get settingsPfpKnight => '骑士';

  @override
  String get settingsPfpSamurai => '武士';

  @override
  String get settingsPfpViking => '维京人';

  @override
  String get settingsPfpWizard => '巫师';

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
  String get settingsPirPingChecking => '检查中...';

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
  String get settingsPrivateQueriesLabel => '隐私查询';

  @override
  String get settingsPrivateQueriesTurnOffBody =>
      'Vizor 将以公开方式重建你的透明交易记录，服务器会获知你的所有地址。';

  @override
  String get settingsPrivateQueriesTurnOffConfirm => '关闭';

  @override
  String get settingsPrivateQueriesTurnOffDisclosure =>
      '服务器会收到每个账户的所有透明地址，以及隐私恢复找到的交易 ID。它可以将这些信息相互关联；不使用 Tor 时，还能与你的 IP 地址关联。';

  @override
  String get settingsPrivateQueriesTurnOffTitle => '要关闭隐私查询吗？';

  @override
  String get settingsProfilePictureCustom => '自定义';

  @override
  String get settingsRowAboutVizor => '关于 Vizor';

  @override
  String get settingsRowAccountName => '账户名称';

  @override
  String get settingsRowAccountNameMobile => '账户名称';

  @override
  String get settingsRowAddressBook => '地址簿';

  @override
  String get settingsRowChangePasscode => '修改数字密码';

  @override
  String get settingsRowChangePassword => '修改密码';

  @override
  String get settingsRowCoinholderVoting => '持币者投票';

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
  String get settingsRowSupportVizor => '支持 Vizor';

  @override
  String get settingsRowUpdates => '更新';

  @override
  String get settingsRowViewingKeyMobile => '查看密钥';

  @override
  String get settingsSecretPassphraseTitle => '助记词';

  @override
  String get settingsSectionAccount => '账户';

  @override
  String get settingsSectionDangerZone => '危险区域';

  @override
  String get settingsSectionMisc => '其他';

  @override
  String get settingsSectionPersonal => '个人';

  @override
  String get settingsSectionSyncing => '同步';

  @override
  String get settingsSectionSystem => '系统';

  @override
  String get settingsSeedBackupSaveFailed => '无法保存。请重试。';

  @override
  String get settingsSeedBiometricReason => '确认访问你的助记词';

  @override
  String get settingsSeedCopiedToast => '已复制助记词';

  @override
  String get settingsSeedCopyLabel => '复制助记词';

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
  String get settingsSeedScreenshotBodyLead => '截图并不可靠';

  @override
  String get settingsSeedScreenshotBodyRest =>
      '。任何能访问你手机或相册的人都能看到你的助记词。请改为将助记词抄写在纸上。';

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
      'Vizor 的网络请求通过 Tor 发送。Vizor 关闭期间，Ironwood 隐私迁移使用直接连接。在其他应用中打开的链接使用这些应用的网络设置。';

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
  String get settingsTorGeneralIosSuffix => ' Vizor 关闭期间，Ironwood 隐私迁移使用直接连接。';

  @override
  String get settingsTorRetryUpdates => '重试更新';

  @override
  String get settingsTorStatusConnected => '已连接';

  @override
  String get settingsTorStatusConnecting => '正在连接…';

  @override
  String get settingsTorStatusConnectionFailed => '连接失败';

  @override
  String get settingsTorStatusDirect => '直接连接';

  @override
  String get settingsTorStatusFailed => '失败';

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
  String get settingsTryAgain => '重试';

  @override
  String settingsUninstallActiveSwaps(int count) {
    return '此钱包有 $count 笔进行中的兑换。请等待它们完成后再卸载。';
  }

  @override
  String get settingsUninstallCannotUndo => '此操作无法撤销。';

  @override
  String get settingsUninstallChecking => '正在检查...';

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
  String get settingsUpdateCheckingButton => '正在检查…';

  @override
  String get settingsUpdateCurrentLabel => '当前';

  @override
  String get settingsUpdateDownloadButton => '下载更新';

  @override
  String get settingsUpdateDownloadingButton => '正在下载…';

  @override
  String get settingsUpdateFailed => '失败';

  @override
  String get settingsUpdatePasswordTitle => '更新密码';

  @override
  String get settingsUpdateRestart => '重启';

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
  String get settingsUpdateStatusFailed => '无法完成更新。请重试。';

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
  String get settingsViewingKeyBiometricReason => '确认访问你的查看密钥';

  @override
  String get settingsViewingKeyChoiceSharingWarning =>
      '仅与可信方分享。两种密钥都可能泄露透明余额和支出。';

  @override
  String get settingsViewingKeyChooseTitle => '选择他人可以查看的内容';

  @override
  String get settingsViewingKeyConfirmAgain => '请再次确认访问，然后重试加载此密钥。';

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
  String get settingsViewingKeyPasswordSubtitle => '以查看查看密钥。';

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
