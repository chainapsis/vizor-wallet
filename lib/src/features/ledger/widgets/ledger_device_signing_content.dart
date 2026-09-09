import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'ledger_device_illustration.dart';

/// Device-focused presentation only. Signing and recovery remain with the caller.
class LedgerDeviceSigningContent extends StatelessWidget {
  const LedgerDeviceSigningContent({
    required this.accountName,
    required this.title,
    required this.message,
    required this.busy,
    required this.attention,
    required this.destructive,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.reservedMessages,
    this.approvalLabel,
    this.detailLabel,
    this.connectionPicker,
    this.showSecondary = true,
    this.pageLayout = false,
    this.waitingLabel,
    this.complete = false,
    super.key,
  });

  final String accountName;
  final String title;
  final String message;
  final bool busy;
  final bool attention;
  final bool destructive;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final List<String> reservedMessages;
  final String? approvalLabel;
  final String? detailLabel;
  final Widget? connectionPicker;
  final bool showSecondary;
  final bool pageLayout;
  final String? waitingLabel;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget guidance(String body) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IndexedStack(
          index: 0,
          alignment: Alignment.topCenter,
          children: [
            for (final heading in [
              title,
              'Open the Zcash app',
              'Reconnecting your Ledger',
            ])
              Text(
                heading,
                textAlign: TextAlign.center,
                style:
                    (pageLayout
                            ? AppTypography.headlineLarge
                            : AppTypography.bodyLarge)
                        .copyWith(
                          fontWeight: pageLayout
                              ? FontWeight.w400
                              : FontWeight.w600,
                          color: destructive
                              ? colors.text.destructive
                              : colors.text.accent,
                        ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (detailLabel != null) ...[
          Text(
            detailLabel!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          body,
          textAlign: TextAlign.center,
          style:
              (pageLayout ? AppTypography.bodyLarge : AppTypography.bodyMedium)
                  .copyWith(color: colors.text.secondary),
        ),
      ],
    );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const ValueKey('ledger_signing_account'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(AppIcons.ledger, size: 20, color: colors.text.accent),
            const SizedBox(width: AppSpacing.s),
            Flexible(
              child: Text(
                accountName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: pageLayout ? AppSpacing.md : AppSpacing.sm),
        if (approvalLabel != null) ...[
          Text(
            approvalLabel!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Center(
          child: LedgerDeviceIllustration(
            key: const ValueKey('ledger_signing_device'),
            large: pageLayout,
            busy: busy,
            attention: attention,
            destructive: destructive,
            complete: complete,
          ),
        ),
        SizedBox(height: pageLayout ? AppSpacing.md : AppSpacing.sm),
        Semantics(
          liveRegion: true,
          child: IndexedStack(
            key: const ValueKey('ledger_action_guidance'),
            index: 0,
            children: [
              guidance(message),
              for (final body in reservedMessages) guidance(body),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Visibility(
          visible: waitingLabel != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  waitingLabel ?? 'Waiting for your approval',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppIcon(
                AppIcons.loader,
                size: 14,
                color: colors.text.secondary,
                animated: waitingLabel != null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        if (connectionPicker != null) ...[
          connectionPicker!,
          const SizedBox(height: AppSpacing.s),
        ],
      ],
    );
    final actions = Column(
      key: const ValueKey('ledger_signing_actions'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Visibility(
          visible: primaryLabel != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: AppButton(
            constrainContent: true,
            size: pageLayout ? AppButtonSize.large : AppButtonSize.mediumLarge,
            onPressed: onPrimary,
            child: Text(primaryLabel ?? 'Continue'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Visibility(
          visible: showSecondary,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: AppButton(
            constrainContent: true,
            size: pageLayout ? AppButtonSize.large : AppButtonSize.mediumLarge,
            variant: AppButtonVariant.ghost,
            onPressed: onSecondary,
            child: Text(secondaryLabel),
          ),
        ),
      ],
    );
    if (!pageLayout) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [body, actions],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(child: body),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        actions,
      ],
    );
  }
}
