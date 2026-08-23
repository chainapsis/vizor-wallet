import 'package:flutter/material.dart'
    show Dialog, Scaffold, ScaffoldMessenger, SnackBar, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../features/ledger/ledger_capability.dart';
import '../../../features/ledger/services/ledger_account_service.dart';
import '../../../features/ledger/services/ledger_mobile_ble_service.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../onboarding/ledger/ledger_desktop_ble_probe_dialog.dart';

const _contentWidth = 420.0;

class HardwareAccountDetailsScreen extends ConsumerWidget {
  const HardwareAccountDetailsScreen({required this.accountUuid, super.key});

  final String? accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider).value;
    final account = _targetAccount(accountState, accountUuid);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        backgroundColor: const Color(0x00000000),
        child: AppPaneScrollScaffold(
          toolbar: const AppPaneToolbar(
            key: ValueKey('hardware_account_details_toolbar'),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.xl,
                ),
                child: account == null || !account.isHardware
                    ? const _UnavailableAccountDetails()
                    : _HardwareAccountDetails(account: account),
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
              title: 'Account Details',
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
  });

  final AccountInfo account;
  final bool showHeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signerKind = account.hardwareSignerKind!;
    final signerName = switch (signerKind) {
      HardwareSignerKind.keystone => 'Keystone',
      HardwareSignerKind.ledger => 'Ledger',
    };
    final signerIcon = switch (signerKind) {
      HardwareSignerKind.keystone => AppIcons.keystone,
      HardwareSignerKind.ledger => AppIcons.ledger,
    };

    return Column(
      key: const ValueKey('hardware_account_details_screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text(
            'Account details',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        _AccountIdentityCard(
          account: account,
          signerName: signerName,
          signerIcon: signerIcon,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Wallet metadata',
          style: AppTypography.labelMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _MetadataCard(
          children: [
            _MetadataRow(
              key: const ValueKey('hardware_account_details_birthday'),
              label: 'Wallet birthday height',
              value: _valueOrUnavailable(account.birthdayHeight),
              description:
                  'Vizor starts scanning this account from this block height.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _MetadataRow(
              key: const ValueKey('hardware_account_details_account_index'),
              label: 'ZIP-32 account index',
              value: _valueOrUnavailable(account.zip32AccountIndex),
              description:
                  'Identifies the account derived on your $signerName device.',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'These values are public wallet metadata. They do not give Vizor '
          'spending authority or reveal your recovery phrase.',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        if (account.isLedger) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Ledger connection',
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _LedgerConnectionCard(
            account: account,
            platform: ref.watch(ledgerTargetPlatformProvider),
            onChange: () => _changeConnection(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _changeConnection(BuildContext context, WidgetRef ref) async {
    final platform = ref.read(ledgerTargetPlatformProvider);
    if (platform != TargetPlatform.macOS) return;
    final selection = await showDialog<LedgerConnectionPreference>(
      context: context,
      builder: (_) =>
          _LedgerConnectionChoiceDialog(account: account, platform: platform),
    );
    if (selection == null || !context.mounted) return;

    if (selection == LedgerConnectionPreference.bluetooth &&
        account.ledgerDeviceId == null) {
      await _setupBluetooth(context, ref);
      return;
    }
    await ref
        .read(accountProvider.notifier)
        .updateLedgerConnectionPreference(account.uuid, selection);
  }

  Future<void> _setupBluetooth(BuildContext context, WidgetRef ref) async {
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

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _valueOrUnavailable(int? value) =>
      value == null ? 'Unavailable' : value.toString();
}

class _LedgerConnectionCard extends StatelessWidget {
  const _LedgerConnectionCard({
    required this.account,
    required this.platform,
    required this.onChange,
  });

  final AccountInfo account;
  final TargetPlatform platform;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final mobile = isLedgerMobilePlatform(platform);
    final preference = mobile
        ? 'Bluetooth'
        : switch (account.ledgerConnectionPreference) {
            LedgerConnectionPreference.automatic => 'Automatic',
            LedgerConnectionPreference.usb => 'USB',
            LedgerConnectionPreference.bluetooth => 'Bluetooth',
          };
    final device = account.ledgerDeviceModel ?? 'Not recorded';
    final description = mobile
        ? 'Ledger connections on this mobile platform use Bluetooth.'
        : account.ledgerConnectionPreference ==
              LedgerConnectionPreference.automatic
        ? 'Vizor tries the last successful connection, then another available connection.'
        : 'Vizor uses this connection first when requesting a signature.';

    return _MetadataCard(
      children: [
        _MetadataRow(
          key: const ValueKey('ledger_connection_preference'),
          label: 'Connection preference',
          value: preference,
          description: description,
        ),
        const SizedBox(height: AppSpacing.sm),
        _MetadataRow(
          key: const ValueKey('ledger_device_model'),
          label: 'Bluetooth device',
          value: device,
          description: account.ledgerDeviceId == null
              ? 'Bluetooth has not been verified for this account.'
              : account.ledgerDeviceName ?? 'Verified Ledger device',
        ),
        if (!mobile) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('ledger_change_connection_button'),
            onPressed: onChange,
            variant: AppButtonVariant.secondary,
            expand: true,
            child: const Text('Change connection'),
          ),
        ],
      ],
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
              style: AppTypography.headlineMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Automatic is recommended. This Vizor build supports Bluetooth on ${ledgerBluetoothSupportedModels(platform)}.',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ConnectionChoiceButton(
              label: 'Automatic',
              description: 'Use the last successful connection and fall back.',
              onPressed: () => Navigator.of(
                context,
              ).pop(LedgerConnectionPreference.automatic),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ConnectionChoiceButton(
              label: 'USB',
              description: 'Use the Ledger connected with a cable.',
              onPressed: () =>
                  Navigator.of(context).pop(LedgerConnectionPreference.usb),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ConnectionChoiceButton(
              label: account.ledgerDeviceId == null
                  ? 'Set up Bluetooth'
                  : 'Bluetooth',
              description: bluetoothAllowed
                  ? 'Connect to a verified Bluetooth-capable Ledger.'
                  : '${account.ledgerDeviceModel} is not supported over Bluetooth by this Vizor build.',
              onPressed: bluetoothAllowed
                  ? () => Navigator.of(
                      context,
                    ).pop(LedgerConnectionPreference.bluetooth)
                  : null,
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
  });

  final String label;
  final String description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onPressed,
      variant: AppButtonVariant.secondary,
      height: 80,
      expand: true,
      constrainContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Text(
            description,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountIdentityCard extends StatelessWidget {
  const _AccountIdentityCard({
    required this.account,
    required this.signerName,
    required this.signerIcon,
  });

  final AccountInfo account;
  final String signerName;
  final String signerIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(context.colors),
      ),
      child: Row(
        children: [
          AppProfilePicture(
            profilePictureId: account.profilePictureId,
            size: AppProfilePictureSize.large,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  key: const ValueKey('hardware_account_details_signer'),
                  children: [
                    AppIcon(
                      signerIcon,
                      size: AppIconSize.medium,
                      color: context.colors.icon.regular,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        '$signerName hardware wallet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: ShapeDecoration(
              color: context.colors.background.neutralSubtleOpacity,
              shape: const StadiumBorder(),
            ),
            child: Text(
              'Watch-only',
              style: AppTypography.labelSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
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

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    required this.description,
    super.key,
  });

  final String label;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          description,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ],
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
            'Account details',
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
