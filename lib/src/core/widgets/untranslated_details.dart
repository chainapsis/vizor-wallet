import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../layout/app_desktop_shell.dart';
import '../layout/app_form_factor.dart';
import '../layout/content_overlay_inset.dart';
import '../layout/mobile/app_mobile_sheet.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_copy_feedback.dart';
import 'app_modal_shape.dart';
import 'app_pane_modal_overlay.dart';

/// A "Show details" button for the untranslated Rust, SDK or platform text
/// behind an error the screen words in its own copy. It opens the text with a
/// copy button, so the user can see what went wrong and send it to support.
class UntranslatedDetailsButton extends StatelessWidget {
  const UntranslatedDetailsButton({required this.details, super.key});

  final String details;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('untranslated_details_button'),
      onPressed: () => showUntranslatedDetails(context, details),
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.small,
      child: Text(context.l10n.commonShowDetails),
    );
  }
}

/// The button under an error, or nothing when there is no text to show.
/// [alignment] follows the error text above it.
List<Widget> untranslatedDetailsButton(
  String? details, {
  AlignmentGeometry alignment = Alignment.center,
}) {
  final text = details?.trim() ?? '';
  if (text.isEmpty) return const [];
  return [
    const SizedBox(height: AppSpacing.xxs),
    Align(
      alignment: alignment,
      child: UntranslatedDetailsButton(details: text),
    ),
  ];
}

/// Shows [details] in a dialog on desktop and a sheet on mobile.
Future<void> showUntranslatedDetails(BuildContext context, String details) {
  if (kAppFormFactor == AppFormFactor.mobile) {
    return showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
        ),
        child: _UntranslatedDetailsBody(details: details, mobile: true),
      ),
    );
  }
  // The barrier stays transparent and only dismisses; the scrim and the card
  // sit over the content pane, like the pane modals on the screens below.
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (dialogContext) => _ContentPaneDialog(
      child: Dialog(
        key: const ValueKey('untranslated_details_dialog'),
        backgroundColor: dialogContext.colors.background.ground,
        shape: appModalShape(BorderRadius.circular(AppRadii.medium)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _UntranslatedDetailsBody(details: details, mobile: false),
          ),
        ),
      ),
    ),
  );
}

/// Dims and centers [child] over the desktop shell's content pane, or over the
/// whole window when no shell is mounted.
class _ContentPaneDialog extends StatelessWidget {
  const _ContentPaneDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scrim = context.colors.background.neutralScrim;
    return ValueListenableBuilder<EdgeInsets>(
      valueListenable: contentOverlayInsets,
      builder: (context, insets, child) {
        final inPane = insets != EdgeInsets.zero;
        final pane = inPane
            ? EdgeInsets.fromLTRB(
                insets.left,
                kAppDesktopShellMargin,
                insets.right,
                kAppDesktopShellMargin,
              )
            : EdgeInsets.zero;
        return Padding(
          padding: pane,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Taps fall through to the barrier, which closes the dialog.
              IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('untranslated_details_scrim'),
                  decoration: BoxDecoration(
                    color: scrim,
                    borderRadius: inPane
                        ? AppPaneModalOverlay.defaultBorderRadius
                        : null,
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: child,
    );
  }
}

class _UntranslatedDetailsBody extends StatefulWidget {
  const _UntranslatedDetailsBody({required this.details, required this.mobile});

  final String details;
  final bool mobile;

  @override
  State<_UntranslatedDetailsBody> createState() =>
      _UntranslatedDetailsBodyState();
}

class _UntranslatedDetailsBodyState extends State<_UntranslatedDetailsBody> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final mobile = widget.mobile;
    final colors = context.colors;
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.commonErrorDetailsTitle,
          style:
              (mobile
                      ? AppTypography.headlineSmall
                      : AppTypography.bodyMediumStrong)
                  .copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.commonErrorDetailsHint,
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: colors.background.base,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          // A visible thumb shows that long text continues below the box. The
          // platform's own scrollbar is turned off so desktop draws only one.
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.s),
                child: SelectableText(
                  details,
                  key: const ValueKey('untranslated_details_text'),
                  style: AppTypography.codeSmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('untranslated_details_copy'),
          expand: true,
          variant: AppButtonVariant.secondary,
          onPressed: () => copyTextWithToast(
            context,
            text: details,
            toastMessage: l10n.commonCopied,
          ),
          child: Text(l10n.commonCopy),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('untranslated_details_close'),
          expand: true,
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
