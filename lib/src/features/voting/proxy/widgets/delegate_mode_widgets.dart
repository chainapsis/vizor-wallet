import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_form_factor.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_modal_shape.dart';
import '../delegate_mode_presentation.dart';
import '../proxy_delegation_repository.dart';
import 'proxy_delegate_widgets.dart';

/// A delegate key: its identicon, or the delegate's pinned picture, and
/// its display form, `#17 · xxxx-xxxx-…` once the entry has an index. The
/// avatar is decoration, not verification.
class DelegateKeyLine extends StatelessWidget {
  /// Creates the line.
  const DelegateKeyLine({
    required this.keyInfo,
    this.delegateIndex,
    this.label,
    this.trailing,
    this.picture,
    super.key,
  });

  /// The key.
  final DelegateKeyInfo keyInfo;

  /// The entry's index, once registered.
  final int? delegateIndex;

  /// Caption above the key, for example its state.
  final String? label;

  /// Widget after the text, for example an action.
  final Widget? trailing;

  /// The delegate's pinned picture, shown in place of the identicon.
  final ProxyDelegatePicture? picture;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = this.label;
    final trailing = this.trailing;
    return Row(
      children: [
        ProxyDelegateAvatar(
          fingerprint: keyInfo.fingerprint,
          picture: picture,
          size: 32,
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              Text(
                formatDelegateKey(keyInfo, delegateIndex: delegateIndex),
                style: AppTypography.codeSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          trailing,
        ],
      ],
    );
  }
}

/// One choice in a mutually exclusive group.
class DelegateRadioOption extends StatelessWidget {
  /// Creates the option.
  const DelegateRadioOption({
    required this.label,
    required this.selected,
    this.onTap,
    super.key,
  });

  /// Option text.
  final String label;

  /// Whether this option is chosen.
  final bool selected;

  /// Chooses the option; null disables it.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? colors.text.accent
                    : enabled
                    ? colors.text.secondary
                    : colors.text.disabled,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: enabled ? colors.text.accent : colors.text.disabled,
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

/// One step of a running operation: a spinner while active, a check when
/// done.
class DelegateStepRow extends StatelessWidget {
  /// Creates the row.
  const DelegateStepRow({
    required this.label,
    required this.active,
    required this.complete,
    super.key,
  });

  /// Step text.
  final String label;

  /// The step is running.
  final bool active;

  /// The step finished.
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: label,
      value: complete
          ? context.l10n.commonDone
          : active
          ? context.l10n.commonInProgress
          : null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: active
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(
                      complete
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: complete
                          ? colors.text.success
                          : colors.text.secondary,
                    ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMedium.copyWith(
                  color: active || complete
                      ? colors.text.accent
                      : colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned actions stacked with the pane's spacing.
class DelegateActionStack extends StatelessWidget {
  /// Creates the stack.
  const DelegateActionStack({required this.children, super.key});

  /// Buttons, primary first.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ],
    );
  }
}

/// Shows [builder] under [title] as a dialog on desktop and a sheet on
/// mobile, the way the app presents confirmations on each form factor.
/// Content closes it with `Navigator.of(context).pop(value)`; a modal that
/// is not [dismissible] closes only that way.
Future<T?> showDelegateModal<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  if (kAppFormFactor == AppFormFactor.mobile) {
    return showAppMobileSheet<T>(
      context: context,
      isDismissible: dismissible,
      enableDrag: dismissible,
      builder: (sheetContext) => MobileModalScaffold(
        title: title,
        titleMaxLines: 2,
        constrainBody: true,
        showClose: dismissible,
        onClose: () => Navigator.of(sheetContext).maybePop(),
        child: SingleChildScrollView(child: builder(sheetContext)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return Dialog(
        backgroundColor: colors.background.ground,
        shape: appModalShape(BorderRadius.circular(AppRadii.large)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  builder(dialogContext),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Rebuilds a state when a ballot deadline crosses a warning boundary, so
/// the 5-minute warning and the 60-second confirm appear on time.
mixin DelegateDeadlineTicker<T extends StatefulWidget> on State<T> {
  Timer? _deadlineTimer;
  DateTime? _deadlineAt;

  /// Schedules one rebuild at the next urgency change of [voteEnds].
  void armDeadlineTicker(DateTime now, Iterable<DateTime> voteEnds) {
    DateTime? next;
    for (final voteEnd in voteEnds) {
      final change = delegateNextUrgencyChange(now: now, voteEnd: voteEnd);
      if (change != null && (next == null || change.isBefore(next))) {
        next = change;
      }
    }
    if (next == _deadlineAt) return;
    _deadlineTimer?.cancel();
    _deadlineAt = next;
    if (next == null) return;
    _deadlineTimer = Timer(next.difference(now), () {
      _deadlineAt = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }
}
