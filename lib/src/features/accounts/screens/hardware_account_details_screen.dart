import 'dart:async';

import 'package:flutter/material.dart'
    show Dialog, Scaffold, ScaffoldMessenger, SnackBar, showDialog;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../features/ledger/ledger_capability.dart';
import '../../../features/ledger/services/ledger_account_service.dart';
import '../../../features/ledger/services/ledger_mobile_ble_service.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../onboarding/ledger/ledger_desktop_ble_probe_dialog.dart';

const _contentWidth = 396.0;

final hardwareAccountBirthdayBlockTimeProvider = FutureProvider.autoDispose
    .family<int?, int>((ref, height) async {
      if (height <= 0) return null;
      ref.watch(rpcEndpointProvider.select((endpoint) => endpoint.networkName));
      final blockTime = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'birthday block time',
            action: (endpoint) => rust_sync.getBlockTime(
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              height: BigInt.from(height),
            ),
          )
          .timeout(const Duration(seconds: 10));
      return blockTime > BigInt.zero ? blockTime.toInt() : null;
    });

class HardwareAccountDetailsScreen extends ConsumerWidget {
  const HardwareAccountDetailsScreen({required this.accountUuid, super.key});

  final String? accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider).value;
    final account = _targetAccount(accountState, accountUuid);

    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: const AppMainSidebar(),
      pane: AppPaneScrollScaffold(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        toolbar: const AppPaneToolbar(
          key: ValueKey('hardware_account_details_toolbar'),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                AppSpacing.sm,
                0,
                AppSpacing.xl,
              ),
              child: account == null || !account.isHardware
                  ? const _UnavailableAccountDetails()
                  : _HardwareAccountDetails(
                      key: ValueKey(account.uuid),
                      account: account,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  static AccountInfo? _targetAccount(
    AccountState? accountState,
    String? accountUuid,
  ) {
    if (accountState == null) return null;
    final requestedUuid = accountUuid;
    if (requestedUuid == null) return accountState.activeAccount;
    for (final account in accountState.accounts) {
      if (account.uuid == requestedUuid) return account;
    }
    return null;
  }
}

class MobileHardwareAccountDetailsScreen extends ConsumerWidget {
  const MobileHardwareAccountDetailsScreen({
    required this.accountUuid,
    super.key,
  });

  final String? accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider).value;
    final account = HardwareAccountDetailsScreen._targetAccount(
      accountState,
      accountUuid,
    );
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Recovery info',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.xl,
                ),
                child: account == null || !account.isHardware
                    ? const _UnavailableAccountDetails(showHeading: false)
                    : _HardwareAccountDetails(
                        key: ValueKey(account.uuid),
                        account: account,
                        showHeading: false,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HardwareAccountDetails extends ConsumerWidget {
  const _HardwareAccountDetails({
    required this.account,
    this.showHeading = true,
    super.key,
  });
  final AccountInfo account;
  final bool showHeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = account.birthdayHeight;
    final birthday = height == null
        ? const AsyncData<int?>(null)
        : ref.watch(hardwareAccountBirthdayBlockTimeProvider(height));
    final blockTime = birthday.asData?.value;
    final date = blockTime == null ? null : _formatBirthdayDate(blockTime);
    final values = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecoveryValueRow(
          key: const ValueKey('hardware_account_details_account_index'),
          icon: AppIcons.wallet,
          label: 'Account index',
          value: account.zip32AccountIndex?.toString(),
        ),
        const _RecoveryHelper(
          'Use this index to select the same account on your hardware wallet.',
        ),
        const SizedBox(height: AppSpacing.md),
        Container(height: 1, color: context.colors.border.subtle),
        const SizedBox(height: AppSpacing.s),
        _RecoveryValueRow(
          key: const ValueKey('hardware_account_details_birthday_date'),
          icon: AppIcons.calendar,
          label: 'Birthday date',
          value: date,
          loading: birthday.isLoading,
        ),
        const SizedBox(height: AppSpacing.xxs),
        _RecoveryValueRow(
          key: const ValueKey('hardware_account_details_birthday'),
          icon: AppIcons.block,
          label: 'Birthday block height',
          value: height != null && height > 0 ? height.toString() : null,
        ),
        const _RecoveryHelper(
          'Start scanning from this date or block height to restore your transaction history faster.',
        ),
      ],
    );
    return Column(
      key: const ValueKey('hardware_account_details_screen'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text(
            'Recovery information',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (kAppFormFactor == AppFormFactor.mobile)
          MobileSurfaceCard(
            key: const ValueKey('hardware_recovery_information_card'),
            cornerRadius: AppRadii.large,
            child: values,
          )
        else
          Container(
            key: const ValueKey('hardware_recovery_information_card'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: context.colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.large),
              boxShadow: appSurfaceShadow(context.colors),
            ),
            child: values,
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Use these values when restoring this account with your hardware wallet.',
          textAlign: showHeading ? TextAlign.center : TextAlign.start,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _RecoveryHelper extends StatelessWidget {
  const _RecoveryHelper(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.bodySmall.copyWith(
      color: context.colors.text.secondary,
    ),
  );
}

String _formatBirthdayDate(int blockTime) {
  final date = DateTime.fromMillisecondsSinceEpoch(blockTime * 1000).toLocal();
  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month]} ${date.day}, ${date.year}';
}

Future<void> showLedgerAccountConnectionSettings(
  BuildContext context,
  AccountInfo account,
) async {
  final ref = ProviderScope.containerOf(context, listen: false);
  final platform = ref.read(ledgerTargetPlatformProvider);
  if (platform != TargetPlatform.macOS &&
      platform != TargetPlatform.windows &&
      platform != TargetPlatform.linux) {
    return;
  }
  final appTheme = AppTheme.of(context);
  final selection = await showDialog<LedgerConnectionPreference>(
    context: context,
    builder: (_) => AppTheme(
      data: appTheme,
      child: _LedgerConnectionChoiceDialog(
        account: account,
        platform: platform,
      ),
    ),
  );
  if (selection == null || !context.mounted) return;

  if (selection == LedgerConnectionPreference.bluetooth &&
      account.ledgerDeviceId == null) {
    await _setupBluetooth(context, ref, account);
    return;
  }
  await ref
      .read(accountProvider.notifier)
      .updateLedgerConnectionPreference(account.uuid, selection);
}

Future<void> _setupBluetooth(
  BuildContext context,
  ProviderContainer ref,
  AccountInfo account,
) async {
  final accountIndex = account.zip32AccountIndex;
  if (accountIndex == null) {
    _showMessage(
      context,
      'This account does not have a ZIP-32 index for Ledger verification.',
    );
    return;
  }

  try {
    final exported = await showLedgerDesktopBleConnectDialog(
      context: context,
      service: ref.read(ledgerMobileBleServiceProvider),
      connector: ref.read(ledgerBluetoothAccountConnectorProvider),
      accountIndex: accountIndex,
    );
    if (exported == null || !context.mounted) return;
    final endpoint = ref.read(rpcEndpointProvider);
    final storedUfvk = await rust_wallet.getAccountUfvk(
      dbPath: await getWalletDbPath(),
      network: endpoint.networkName,
      accountUuid: account.uuid,
    );
    if (storedUfvk != exported.ufvk) {
      await ref.read(ledgerMobileBleServiceProvider).disconnect();
      if (context.mounted) {
        _showMessage(
          context,
          'This Ledger does not match the selected Vizor account.',
        );
      }
      return;
    }
    final device = exported.device!;
    await ref
        .read(accountProvider.notifier)
        .recordLedgerConnection(
          uuid: account.uuid,
          transport: LedgerConnectionTransport.bluetooth,
          deviceId: device.id,
          deviceName: device.name,
          deviceModel: device.model,
        );
    await ref
        .read(accountProvider.notifier)
        .updateLedgerConnectionPreference(
          account.uuid,
          LedgerConnectionPreference.bluetooth,
        );
    if (context.mounted) {
      _showMessage(context, '${device.model} connected for this account.');
    }
  } catch (error) {
    if (context.mounted) {
      _showMessage(context, 'Could not set up Ledger Bluetooth: $error');
    }
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _RecoveryValueRow extends StatefulWidget {
  const _RecoveryValueRow({
    required this.label,
    required this.icon,
    required this.value,
    this.loading = false,
    super.key,
  });

  final String label;
  final String icon;
  final String? value;
  final bool loading;

  @override
  State<_RecoveryValueRow> createState() => _RecoveryValueRowState();
}

class _RecoveryValueRowState extends State<_RecoveryValueRow> {
  Timer? _copyResetTimer;
  bool _copied = false;

  @override
  void didUpdateWidget(_RecoveryValueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _copyResetTimer?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final value = widget.value;
    if (value == null || widget.loading) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted || widget.value != value) return;
    _copyResetTimer?.cancel();
    setState(() => _copied = true);
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final value = widget.loading ? 'Loading…' : widget.value ?? 'Unavailable';
    final labelStyle = AppTypography.labelMedium.copyWith(
      color: context.colors.text.primary,
    );
    final valueStyle = AppTypography.labelMedium.copyWith(
      color: context.colors.text.accent,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final copySize = kAppFormFactor == AppFormFactor.mobile ? 44.0 : 32.0;
        final copyButton = widget.value == null || widget.loading
            ? const SizedBox.shrink()
            : Semantics(
                label: _copied ? '$label copied' : 'Copy $label',
                child: AppButton(
                  key: ValueKey('copy_$label'),
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.medium,
                  height: copySize,
                  minWidth: copySize,
                  contentPadding: EdgeInsets.zero,
                  constrainContent: false,
                  onPressed: _copy,
                  child: AppIcon(
                    _copied ? AppIcons.check : AppIcons.copy,
                    size: AppIconSize.medium,
                    color: context.colors.icon.muted,
                  ),
                ),
              );
        final labelWidget = Row(
          children: [
            AppIcon(
              widget.icon,
              size: AppIconSize.medium,
              color: context.colors.icon.muted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(child: Text(label, style: labelStyle)),
          ],
        );
        final stacked =
            widthOf(label, labelStyle) +
                AppIconSize.medium +
                AppSpacing.xxs +
                copySize +
                AppSpacing.sm +
                widthOf(value, valueStyle) >
            constraints.maxWidth;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Expanded(child: Text(value, style: valueStyle)),
                  copyButton,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: AppSpacing.sm),
            Text(value, style: valueStyle),
            copyButton,
          ],
        );
      },
    );
  }
}

class _LedgerConnectionChoiceDialog extends StatelessWidget {
  const _LedgerConnectionChoiceDialog({
    required this.account,
    required this.platform,
  });

  final AccountInfo account;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final bluetoothCapability = ledgerBluetoothTransportCapabilityForModel(
      model: account.ledgerDeviceModel,
      platform: platform,
    );
    final bluetoothAllowed =
        bluetoothCapability != LedgerBluetoothCapability.unsupported;
    return Dialog(
      backgroundColor: const Color(0x00000000),
      child: AppModalCard(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ledger connection',
              textAlign: TextAlign.center,
              style: AppTypography.headlineMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Choose how Vizor connects when you approve a request.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ConnectionChoiceButton(
              label: 'Automatic',
              selected:
                  account.ledgerConnectionPreference ==
                  LedgerConnectionPreference.automatic,
              description: 'Recommended. Use your last connection first.',
              onPressed: () => Navigator.of(
                context,
              ).pop(LedgerConnectionPreference.automatic),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ConnectionChoiceButton(
              label: 'USB',
              selected:
                  account.ledgerConnectionPreference ==
                  LedgerConnectionPreference.usb,
              description: 'Use the Ledger connected with a cable.',
              onPressed: () =>
                  Navigator.of(context).pop(LedgerConnectionPreference.usb),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ConnectionChoiceButton(
              label: account.ledgerDeviceId == null
                  ? 'Set up Bluetooth'
                  : 'Bluetooth',
              selected:
                  account.ledgerConnectionPreference ==
                  LedgerConnectionPreference.bluetooth,
              description: bluetoothAllowed
                  ? 'Approve without a cable on a supported Ledger.'
                  : '${account.ledgerDeviceModel} uses USB in Vizor.',
              onPressed: bluetoothAllowed
                  ? () => Navigator.of(
                      context,
                    ).pop(LedgerConnectionPreference.bluetooth)
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bluetooth supports ${ledgerBluetoothSupportedModels(platform)}.',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionChoiceButton extends StatelessWidget {
  const _ConnectionChoiceButton({
    required this.label,
    required this.description,
    required this.onPressed,
    required this.selected,
  });

  final String label;
  final String description;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: AppButton(
        onPressed: onPressed,
        variant: AppButtonVariant.secondary,
        height: 80 * MediaQuery.textScalerOf(context).scale(1),
        expand: true,
        constrainContent: true,
        enabledBorderColor: selected ? context.colors.text.secondary : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            SizedBox(
              width: AppIconSize.medium,
              child: selected
                  ? AppIcon(AppIcons.check, color: context.colors.text.accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(context.colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _UnavailableAccountDetails extends StatelessWidget {
  const _UnavailableAccountDetails({this.showHeading = true});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('hardware_account_details_unavailable'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text(
            'Recovery information',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        _MetadataCard(
          children: [
            Text(
              'Hardware account unavailable',
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Return to Accounts and choose a Keystone or Ledger account.',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
