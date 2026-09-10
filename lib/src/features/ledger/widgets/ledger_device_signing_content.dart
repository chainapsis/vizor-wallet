import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

/// Device-focused presentation only. Signing and recovery remain with the
/// caller. The layout is a header, the device app card, and a status card
/// that carries the current request; the actions follow.
class LedgerDeviceSigningContent extends StatelessWidget {
  const LedgerDeviceSigningContent({
    required this.accountName,
    required this.title,
    required this.statusTitle,
    required this.message,
    required this.busy,
    required this.attention,
    required this.destructive,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.reservedMessages,
    this.appStep,
    this.badge,
    this.detailLabel,
    this.connectionPicker,
    this.showSecondary = true,
    this.pageLayout = false,
    this.complete = false,
    super.key,
  });

  final String accountName;

  /// The headline of the request, next to the Ledger mark.
  final String title;

  /// The status card's own heading: what the device is doing right now.
  final String statusTitle;
  final String message;
  final bool busy;
  final bool attention;
  final bool destructive;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final List<String> reservedMessages;

  /// The device app line above the status card.
  final Widget? appStep;

  /// A small count beside the status heading, such as `1 of 2`.
  final String? badge;
  final String? detailLabel;
  final Widget? connectionPicker;
  final bool showSecondary;
  final bool pageLayout;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final headingColor = destructive
        ? colors.text.destructive
        : colors.text.accent;
    final titleStyle =
        (pageLayout ? AppTypography.headlineMedium : AppTypography.bodyLarge)
            .copyWith(
              color: headingColor,
              fontWeight: pageLayout ? FontWeight.w400 : FontWeight.w600,
            );
    final header = Row(
      key: const ValueKey('ledger_signing_account'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: colors.border.subtle),
          ),
          child: Center(
            child: AppIcon(
              AppIcons.ledger,
              size: 22,
              color: colors.icon.regular,
              semanticLabel: 'Ledger',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A single line that shrinks to fit, at a fixed line height,
              // keeps every state the same height so the cards and actions
              // below never shift.
              SizedBox(
                height:
                    (titleStyle.fontSize ?? 16) * (titleStyle.height ?? 1.25),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title, maxLines: 1, style: titleStyle),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                accountName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final statusIcon = destructive
        ? AppIcons.warningCircle
        : complete
        ? AppIcons.check
        : busy || attention
        ? AppIcons.loader
        : AppIcons.ledger;
    Widget statusCard(String body, {required bool visible}) => Container(
      key: visible ? const ValueKey('ledger_signing_status') : null,
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(
          color: attention && !destructive
              ? colors.border.medium
              : colors.border.subtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: AppIcon(
                statusIcon,
                size: destructive ? 24 : 20,
                color: destructive
                    ? colors.icon.destructive
                    : complete
                    ? colors.icon.success
                    : colors.icon.regular,
                animated: visible && statusIcon == AppIcons.loader,
                semanticLabel: statusTitle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          statusTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: headingColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs - 2,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.full),
                            border: Border.all(color: colors.border.regular),
                          ),
                          child: Text(
                            badge!,
                            style: AppTypography.bodyExtraSmall.copyWith(
                              color: colors.text.secondary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (detailLabel != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    detailLabel!,
                    style: AppTypography.headlineMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs),
                if (visible)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      key: const ValueKey('ledger_action_guidance'),
                      body,
                      style:
                          (pageLayout
                                  ? AppTypography.bodyMedium
                                  : AppTypography.bodySmall)
                              .copyWith(color: colors.text.secondary),
                    ),
                  )
                else
                  Text(
                    body,
                    style:
                        (pageLayout
                                ? AppTypography.bodyMedium
                                : AppTypography.bodySmall)
                            .copyWith(color: colors.text.secondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // The card hugs its own text; the longest messages it can show reserve
    // the height underneath, so the actions stay put while the card itself
    // never carries empty space.
    final status = IndexedStack(
      index: 0,
      alignment: Alignment.topCenter,
      sizing: StackFit.loose,
      children: [
        statusCard(message, visible: true),
        for (final body in reservedMessages)
          ExcludeSemantics(child: statusCard(body, visible: false)),
      ],
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: pageLayout ? AppSpacing.md : AppSpacing.sm),
        if (appStep != null) ...[
          appStep!,
          const SizedBox(height: AppSpacing.xs),
        ],
        status,
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
