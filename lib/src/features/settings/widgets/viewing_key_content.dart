import 'dart:async';

import 'package:flutter/material.dart'
    show AdaptiveTextSelectionToolbar, SelectableText;
import 'package:flutter/widgets.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_models.dart';
import '../../../rust/api/wallet.dart' show AccountViewingKeys;
import '../../receive/widgets/request/request_qr_surface.dart';
import '../viewing_key_copy.dart';

enum ViewingKeyType {
  full,
  incoming;

  String get title => switch (this) {
    full => 'Full viewing key',
    incoming => 'Incoming key',
  };
}

enum ViewingKeyFormat { text, qr }

typedef ViewingKeyLayoutBuilder =
    Widget Function(BuildContext context, Widget content, Widget? footer);

class ViewingKeyContent extends StatefulWidget {
  const ViewingKeyContent({
    required this.account,
    required this.viewingKeys,
    required this.onCopy,
    required this.onRetry,
    required this.copyButtonKey,
    required this.keyValueKey,
    this.errorText,
    this.showTitle = false,
    this.showAccountName = false,
    required this.onSelectType,
    this.type,
    this.initialFormat = ViewingKeyFormat.qr,
    this.layoutBuilder,
    super.key,
  });

  final AccountInfo? account;
  final AccountViewingKeys? viewingKeys;
  final String? errorText;
  final Future<void> Function(String) onCopy;
  final VoidCallback onRetry;
  final Key copyButtonKey;
  final Key keyValueKey;
  final bool showTitle;
  final bool showAccountName;
  final ViewingKeyType? type;
  final ValueChanged<ViewingKeyType> onSelectType;
  final ViewingKeyFormat initialFormat;

  /// Hosts the key details and copy footer separately. The footer is
  /// absent on the key choice and load-error pages. The default is inline.
  final ViewingKeyLayoutBuilder? layoutBuilder;

  @override
  State<ViewingKeyContent> createState() => _ViewingKeyContentState();
}

class _ViewingKeyContentState extends State<ViewingKeyContent> {
  late var _format = widget.initialFormat;
  bool _copied = false;
  bool _copyFailed = false;
  TextSelection _selection = const TextSelection.collapsed(offset: -1);
  Timer? _copyResetTimer;

  String? get _value => switch (widget.type) {
    ViewingKeyType.full => widget.viewingKeys?.ufvk,
    ViewingKeyType.incoming => widget.viewingKeys?.uivk,
    null => null,
  };

  @override
  void didUpdateWidget(ViewingKeyContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account?.uuid != widget.account?.uuid ||
        oldWidget.viewingKeys != widget.viewingKeys ||
        oldWidget.type != widget.type) {
      _copyResetTimer?.cancel();
      _copied = false;
      _copyFailed = false;
      _selection = const TextSelection.collapsed(offset: -1);
      _format = widget.initialFormat;
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final value = _value;
    if (value == null || widget.errorText != null) return;
    try {
      await widget.onCopy(value);
    } catch (_) {
      if (!mounted || value != _value) return;
      _copyResetTimer?.cancel();
      setState(() {
        _copied = false;
        _copyFailed = true;
      });
      return;
    }
    if (!mounted || value != _value) return;
    _copyResetTimer?.cancel();
    setState(() {
      _copied = true;
      _copyFailed = false;
    });
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final account = widget.account;
    final value = _value;
    final hasKeys = widget.errorText == null && widget.viewingKeys != null;
    final incoming = widget.type == ViewingKeyType.incoming;
    final showQr = _format == ViewingKeyFormat.qr;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              widget.type?.title ?? 'Viewing key',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (widget.showAccountName && account != null) ...[
          Text(
            account.name,
            key: const ValueKey('viewing_key_account_name'),
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (hasKeys && widget.type == null)
          _ViewingKeyChoice(onSelected: widget.onSelectType)
        else if (hasKeys && value != null) ...[
          _ViewingKeyFormatTabs(
            selected: _format,
            onChanged: (format) => setState(() => _format = format),
          ),
          const SizedBox(height: AppSpacing.sm),
          KeyedSubtree(
            key: widget.keyValueKey,
            child: ViewingKeyTransition(
              value: _format,
              duration: const Duration(milliseconds: 120),
              animateSize: true,
              child: showQr
                  ? Semantics(
                      container: true,
                      label: incoming
                          ? 'Incoming viewing key QR code'
                          : 'Full viewing key QR code',
                      image: true,
                      child: ExcludeSemantics(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Center(
                            child: RequestQrSurface(
                              data: value,
                              size: (constraints.maxWidth - AppSpacing.xs * 2)
                                  .clamp(
                                    0.0,
                                    kAppFormFactor == AppFormFactor.mobile
                                        ? 240.0
                                        : 200.0,
                                  )
                                  .toDouble(),
                              padding: AppSpacing.xs,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      // A viewing key is longer than the QR surface is tall.
                      // Let all lines determine the height instead of adding
                      // a second scroll area inside the page.
                      constraints: const BoxConstraints(
                        minHeight: 200 + AppSpacing.xs * 2,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: colors.background.ground,
                        borderRadius: BorderRadius.circular(AppRadii.medium),
                        border: Border.all(color: colors.border.subtle),
                      ),
                      child: Actions(
                        actions: {
                          CopySelectionTextIntent:
                              CallbackAction<CopySelectionTextIntent>(
                                onInvoke: (_) {
                                  if (_selection.isValid &&
                                      !_selection.isCollapsed &&
                                      _selection.end <= value.length) {
                                    unawaited(
                                      SensitiveClipboard.copyText(
                                        _selection.textInside(value),
                                      ),
                                    );
                                  }
                                  return null;
                                },
                              ),
                        },
                        child: SelectableText(
                          value,
                          key: const ValueKey('viewing_key_raw_text'),
                          onSelectionChanged: (selection, cause) =>
                              _selection = selection,
                          textDirection: TextDirection.ltr,
                          style: AppTypography.codeSmall.copyWith(
                            color: colors.text.accent,
                          ),
                          contextMenuBuilder: (context, state) =>
                              AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  ContextMenuButtonItem(
                                    type: ContextMenuButtonType.copy,
                                    onPressed: () {
                                      final editing = state.textEditingValue;
                                      final selected = editing.selection
                                          .textInside(editing.text);
                                      state.hideToolbar();
                                      if (selected.isNotEmpty) {
                                        unawaited(
                                          SensitiveClipboard.copyText(selected),
                                        );
                                      }
                                    },
                                  ),
                                  ContextMenuButtonItem(
                                    type: ContextMenuButtonType.selectAll,
                                    onPressed: () => state.selectAll(
                                      SelectionChangedCause.toolbar,
                                    ),
                                  ),
                                ],
                              ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ViewingKeyPrivacyNotice(incoming: incoming),
          if (widget.layoutBuilder == null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildFooter(),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.large),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Couldn't load the viewing key",
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.errorText ??
                        'Confirm access again to try loading this key.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            container: true,
            button: true,
            child: AppButton(
              key: const ValueKey('viewing_key_retry'),
              onPressed: widget.onRetry,
              expand: true,
              constrainContent: true,
              growWithContent: true,
              child: Text(account == null ? 'Back to accounts' : 'Try again'),
            ),
          ),
        ],
      ],
    );
    final layoutBuilder = widget.layoutBuilder;
    return ViewingKeyTransition(
      value: widget.type,
      child: layoutBuilder == null
          ? content
          : layoutBuilder(
              context,
              content,
              hasKeys && value != null ? _buildFooter() : null,
            ),
    );
  }

  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kAppFormFactor == AppFormFactor.desktop
                  ? 196
                  : double.infinity,
            ),
            child: Semantics(
              container: true,
              button: true,
              liveRegion: true,
              child: AppButton(
                key: widget.copyButtonKey,
                onPressed: _copy,
                expand: true,
                constrainContent: true,
                growWithContent: true,
                leading: ExcludeSemantics(
                  child: ViewingKeyTransition(
                    value: _copied,
                    duration: const Duration(milliseconds: 120),
                    child: AppIcon(
                      _copied ? AppIcons.check : AppIcons.copy,
                      size: 20,
                    ),
                  ),
                ),
                child: _ViewingKeyCopyLabel(
                  label: _copyFailed
                      ? 'Try copying again'
                      : _copied
                      ? 'Copied'
                      : 'Copy viewing key',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewingKeyPrivacyNotice extends StatelessWidget {
  const _ViewingKeyPrivacyNotice({required this.incoming});
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kAppFormFactor == AppFormFactor.desktop
              ? 320
              : double.infinity,
        ),
        child: Semantics(
          container: true,
          child: Padding(
            key: ValueKey(
              incoming
                  ? 'incoming_viewing_key_warning'
                  : 'full_viewing_key_warning',
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ExcludeSemantics(
                    child: AppIcon(
                      incoming ? AppIcons.eye : AppIcons.warning,
                      size: 20,
                      color: incoming
                          ? colors.icon.regular
                          : colors.text.warning,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incoming
                            ? incomingViewingKeyWarningTitle
                            : viewingKeyWarningTitle,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: incoming
                              ? colors.text.accent
                              : colors.text.warning,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        incoming
                            ? incomingViewingKeyExplanation
                            : viewingKeyExplanation,
                        key: ValueKey(
                          incoming
                              ? 'incoming_viewing_key_explanation'
                              : 'viewing_key_explanation',
                        ),
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewingKeyChoice extends StatelessWidget {
  const _ViewingKeyChoice({required this.onSelected});
  final ValueChanged<ViewingKeyType> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose what others can view',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        _ViewingKeyChoiceCard(
          type: ViewingKeyType.incoming,
          title: 'Incoming only',
          icon: AppIcons.arrowBottomLeft,
          description: 'Incoming transactions only.',
          onPressed: () => onSelected(ViewingKeyType.incoming),
        ),
        const SizedBox(height: AppSpacing.s),
        _ViewingKeyChoiceCard(
          type: ViewingKeyType.full,
          title: 'Full viewing key',
          icon: AppIcons.history,
          description: 'Balance, incoming and outgoing transactions.',
          onPressed: () => onSelected(ViewingKeyType.full),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ExcludeSemantics(
                  child: AppIcon(
                    AppIcons.warning,
                    size: 20,
                    color: colors.text.warning,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  viewingKeyChoiceSharingWarning,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewingKeyChoiceCard extends StatelessWidget {
  const _ViewingKeyChoiceCard({
    required this.type,
    required this.title,
    required this.icon,
    required this.description,
    required this.onPressed,
  });
  final ViewingKeyType type;
  final String title;
  final String icon;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      button: true,
      child: AppButton(
        key: ValueKey('viewing_key_choose_${type.name}'),
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.small,
        enabledBackgroundColor: colors.background.ground,
        enabledBorderColor: colors.border.subtle,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        contentPadding: const EdgeInsets.all(AppSpacing.sm),
        expand: true,
        constrainContent: true,
        growWithContent: true,
        onPressed: onPressed,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: AppIcon(
                          icon,
                          size: 20,
                          color: colors.icon.regular,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 20 + AppSpacing.s,
                    ),
                    child: Text(
                      description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            ExcludeSemantics(
              child: AppIcon(
                AppIcons.chevronForward,
                size: 16,
                color: colors.icon.regular,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewingKeyFormatTabs extends StatelessWidget {
  const _ViewingKeyFormatTabs({
    required this.selected,
    required this.onChanged,
  });
  final ViewingKeyFormat selected;
  final ValueChanged<ViewingKeyFormat> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: kAppFormFactor == AppFormFactor.mobile ? 248 : 200,
        child: Row(
          children: [
            for (final format in [ViewingKeyFormat.qr, ViewingKeyFormat.text])
              Expanded(
                child: Semantics(
                  container: true,
                  button: true,
                  selected: format == selected,
                  child: AppButton(
                    key: ValueKey('viewing_key_format_${format.name}'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    onPressed: () => onChanged(format),
                    variant: AppButtonVariant.ghost,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    enabledBackgroundColor: format == selected
                        ? colors.background.raised
                        : null,
                    enabledLabelColor: format == selected
                        ? colors.text.accent
                        : colors.text.secondary,
                    size: AppButtonSize.small,
                    height: kAppFormFactor == AppFormFactor.mobile ? 48 : 32,
                    expand: true,
                    constrainContent: true,
                    growWithContent: true,
                    child: Text(
                      format == ViewingKeyFormat.qr ? 'QR code' : 'Text',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewingKeyCopyLabel extends StatelessWidget {
  const _ViewingKeyCopyLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);
    if (MediaQuery.disableAnimationsOf(context)) return text;
    return AnimatedSize(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      clipBehavior: Clip.none,
      child: text,
    );
  }
}

/// Short, interruptible fades for this flow. Outgoing secrets cannot receive
/// pointer, keyboard, or screen-reader input while the next view is entering.
class ViewingKeyTransition extends StatelessWidget {
  const ViewingKeyTransition({
    required this.value,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    this.animateSize = false,
    super.key,
  });
  final Object? value;
  final Widget child;
  final Duration duration;
  final bool animateSize;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final transition = AnimatedSwitcher(
      duration: reducedMotion ? Duration.zero : duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final outgoing in previous)
            IgnorePointer(
              child: ExcludeFocus(child: ExcludeSemantics(child: outgoing)),
            ),
          ?current,
        ],
      ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    );
    if (!animateSize || reducedMotion) return transition;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: transition,
    );
  }
}
