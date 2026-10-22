import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import 'wallet_pir_server_settings.dart';

/// Opens the server picker without changing whether private queries are on.
Future<void> showWalletPirServerPopup(BuildContext context) async {
  if (kAppFormFactor == AppFormFactor.mobile) {
    await showAppMobileSheet<void>(
      context: context,
      builder: (context) => MobileModalScaffold(
        title: 'Private query server',
        onClose: () => Navigator.of(context).pop(),
        constrainBody: true,
        child: SingleChildScrollView(
          child: WalletPirServerSettings(
            onSelected: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    return;
  }

  final theme = context.appTheme;
  final container = ProviderScope.containerOf(context, listen: false);
  await showDialog<void>(
    context: context,
    barrierColor: theme.colors.background.neutralScrim,
    builder: (context) => UncontrolledProviderScope(
      container: container,
      child: AppTheme(
        data: theme,
        child: Dialog(
          backgroundColor: const Color(0x00000000),
          elevation: 0,
          insetPadding: const EdgeInsets.all(AppSpacing.md),
          child: const _DesktopServerPanel(),
        ),
      ),
    ),
  );
}

/// A quiet settings action beside Private queries, unavailable while off.
class WalletPirServerSettingsButton extends StatelessWidget {
  const WalletPirServerSettingsButton({required this.enabled, super.key});

  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Private query server settings',
    button: true,
    enabled: enabled,
    child: AppButton(
      key: const ValueKey('wallet_pir_server_settings_button'),
      onPressed: enabled
          ? () => unawaited(showWalletPirServerPopup(context))
          : null,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.small,
      minWidth: kAppFormFactor == AppFormFactor.mobile ? 32 : 24,
      height: kAppFormFactor == AppFormFactor.mobile ? 32 : 20,
      contentPadding: EdgeInsets.zero,
      child: ExcludeSemantics(
        child: AppIcon(
          AppIcons.cog,
          size: 16,
          color: enabled
              ? context.colors.icon.muted
              : context.colors.icon.disabled,
        ),
      ),
    ),
  );
}

class _DesktopServerPanel extends StatelessWidget {
  const _DesktopServerPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: const ValueKey('wallet_pir_server_popup'),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height - AppSpacing.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Private query server',
                      style: AppTypography.headlineMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppIconHoverButton(
                        icon: AppIcons.cross,
                        semanticLabel: 'Close private query server settings',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: WalletPirServerSettings(
                    onSelected: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
