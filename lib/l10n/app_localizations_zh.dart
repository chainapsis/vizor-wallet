// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

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
  String languageSystemOption(String language) {
    return '系统（$language）';
  }

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
}
