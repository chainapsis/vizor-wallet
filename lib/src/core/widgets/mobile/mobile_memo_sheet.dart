/// The mobile message (memo) entry sheet, shared by Send's review step and
/// Request ZEC.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../layout/mobile/app_mobile_sheet.dart';
import '../../theme/app_theme.dart';
import '../app_button.dart';
import '../app_icon.dart';

/// Height of the label and counter line above the field.
const _kMemoLabelLineHeight = 17.0;

/// The memo error is the one message here that does not fit on a line at
/// phone width, so its slot holds two.
const _kMemoErrorHeight = _kMemoLabelLineHeight * 2;

/// Opens [MobileMemoSheet] and returns the message it pops: null when it was
/// cancelled, an empty string when the message was cleared.
Future<String?> showMobileMemoSheet(
  BuildContext context, {
  required String initial,
  String? title,
  String? hintText,
  String? clearLabel,
  String Function(String text)? sanitize,
}) {
  return showAppMobileSheet<String>(
    context: context,
    builder: (_) => MobileMemoSheet(
      initial: initial,
      title: title,
      hintText: hintText,
      clearLabel: clearLabel,
      sanitize: sanitize,
    ),
  );
}

/// Memo entry sheet — Figma `Review Add Memo` (4484:62917). Pops the
/// new memo text; popping an empty string clears it.
///
/// Send's review step opens it with its own copy (the defaults). Request ZEC
/// opens the same sheet with its own title, hint and clear label, and a
/// [sanitize] step that drops what a ZIP-321 memo cannot carry.
class MobileMemoSheet extends StatefulWidget {
  const MobileMemoSheet({
    required this.initial,
    this.title,
    this.hintText,
    this.clearLabel,
    this.sanitize,
    super.key,
  });

  final String initial;

  /// The sheet title and the label of its confirm button. Defaults to Send's
  /// "Add memo" copy.
  final String? title;

  /// The placeholder in the empty field: who can read the message.
  final String? hintText;

  /// The label of the primary button when it clears the saved message.
  final String? clearLabel;

  /// Rewrites the typed text as it changes. The result is written back into
  /// the field, so the field, the byte counter and the popped message are
  /// the same string.
  final String Function(String text)? sanitize;

  @override
  State<MobileMemoSheet> createState() => _MobileMemoSheetState();
}

class _MobileMemoSheetState extends State<MobileMemoSheet> {
  static const _memoByteLimit = 512;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_handleFocus);

  @override
  void initState() {
    super.initState();
    // Raise the keyboard after the sheet has opened, not during its entrance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusWhenMobileSheetOpens(context, _focusNode);
    });
  }

  String get _initialMemo => widget.initial.trim();

  String get _currentMemo => _controller.text.trim();

  bool get _showClearMemo =>
      _initialMemo.isNotEmpty && _currentMemo == _initialMemo;

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() {});
  }

  int get _usedBytes => utf8.encode(_currentMemo).length;

  void _handleChanged(String value) {
    final sanitized = widget.sanitize?.call(value) ?? value;
    if (sanitized != value) {
      final offset = _controller.selection.baseOffset;
      _controller.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(
          offset: offset < 0 || offset > sanitized.length
              ? sanitized.length
              : offset,
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overLimit = _usedBytes > _memoByteLimit;
    final error = overLimit ? context.l10n.commonMessageIsTooLong : null;
    final labelStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.secondary,
      fontWeight: FontWeight.w400,
    );
    final primaryIsClear = _showClearMemo;
    final title = widget.title ?? context.l10n.sendMemoSheetAdd;
    final primaryDisabled = error != null && !primaryIsClear;

    return MobileModalScaffold(
      title: title,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('mobile_send_memo_text_area'),
            height: 222,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  SizedBox(
                    height: _kMemoLabelLineHeight,
                    child: Row(
                      children: [
                        Text(context.l10n.commonMessage, style: labelStyle),
                        const Spacer(),
                        Text(
                          // Used/total bytes, like the Add Memo frame's
                          // "51/512".
                          '$_usedBytes/$_memoByteLimit',
                          style: labelStyle.copyWith(
                            color: overLimit
                                ? colors.text.destructive
                                : colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MemoTextArea(
                    key: const ValueKey('mobile_send_memo_field'),
                    controller: _controller,
                    focusNode: _focusNode,
                    hintText:
                        widget.hintText ?? context.l10n.sendMemoRecipientOnly,
                    onChanged: _handleChanged,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: _kMemoErrorHeight,
                    child: Align(
                      // Top, so a one-line message keeps the position it had
                      // before this slot grew.
                      alignment: Alignment.topLeft,
                      child: error != null
                          ? Text(
                              error,
                              maxLines: 2,
                              style: labelStyle.copyWith(
                                color: colors.text.destructive,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            key: const ValueKey('mobile_send_memo_buttons'),
            height: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: ValueKey(
                    primaryIsClear
                        ? 'mobile_send_memo_clear'
                        : 'mobile_send_memo_save',
                  ),
                  expand: true,
                  leading: primaryIsClear
                      ? const AppIcon(AppIcons.trash)
                      : null,
                  onPressed: primaryDisabled
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(primaryIsClear ? '' : _currentMemo),
                  child: Text(
                    primaryIsClear
                        ? widget.clearLabel ?? context.l10n.sendMemoClear
                        : title,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('mobile_send_memo_cancel'),
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.commonCancel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoTextArea extends StatefulWidget {
  const _MemoTextArea({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<_MemoTextArea> createState() => _MemoTextAreaState();
}

class _MemoTextAreaState extends State<_MemoTextArea> {
  late final ScrollController _scrollController = ScrollController();
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleCanScrollUpdate);
    _scrollController.addListener(_scheduleCanScrollUpdate);
    _scheduleCanScrollUpdate();
  }

  @override
  void didUpdateWidget(covariant _MemoTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleCanScrollUpdate);
      widget.controller.addListener(_scheduleCanScrollUpdate);
      _scheduleCanScrollUpdate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleCanScrollUpdate);
    _scrollController.removeListener(_scheduleCanScrollUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCanScrollUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nextCanScroll =
          _scrollController.hasClients &&
          _scrollController.position.hasContentDimensions &&
          _scrollController.position.maxScrollExtent > 0.5;
      if (_canScroll == nextCanScroll) return;
      setState(() {
        _canScroll = nextCanScroll;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final focused = widget.focusNode.hasFocus;

    return Container(
      // The memo error slot below holds two lines, and the sheet keeps its
      // height: the second line comes from here. This area scrolls.
      height: 148 - _kMemoLabelLineHeight,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(
          color: focused
              ? colors.background.inverse
              : colors.background.ground.withValues(alpha: 0),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _scheduleCanScrollUpdate();
                return false;
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: TextField(
                    key: const ValueKey('mobile_send_memo_editable'),
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: _scrollController,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                    cursorColor: colors.text.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hintText,
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 12,
            child: _MemoTextAreaScrollbar(
              visible: _canScroll,
              controller: _scrollController,
              thumbColor: colors.background.overlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoTextAreaScrollbar extends StatefulWidget {
  const _MemoTextAreaScrollbar({
    required this.visible,
    required this.controller,
    required this.thumbColor,
  });

  final bool visible;
  final ScrollController controller;
  final Color thumbColor;

  @override
  State<_MemoTextAreaScrollbar> createState() => _MemoTextAreaScrollbarState();
}

class _MemoTextAreaScrollbarState extends State<_MemoTextAreaScrollbar> {
  static const _horizontalInset = 3.0;
  static const _topInset = 8.0;
  static const _bottomInset = 8.0;
  static const _minThumbHeight = 24.0;
  static const _maxThumbHeight = 62.0;
  static const _thumbWidth = 6.0;

  double? _dragThumbOffset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _MemoTextAreaScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleScrollChanged);
      widget.controller.addListener(_handleScrollChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScrollChanged);
    super.dispose();
  }

  void _handleScrollChanged() {
    if (mounted) setState(() {});
  }

  _MemoScrollbarGeometry? _geometry(double height) {
    if (!widget.visible) return null;
    if (height <= 0) return null;
    if (!widget.controller.hasClients) return null;
    final position = widget.controller.position;
    if (!position.hasContentDimensions) return null;
    final maxScrollExtent = position.maxScrollExtent;
    if (maxScrollExtent <= 0) return null;

    final trackHeight = height - _topInset - _bottomInset;
    final viewportExtent = position.viewportDimension;
    final contentExtent = viewportExtent + maxScrollExtent;
    if (trackHeight <= 0 || viewportExtent <= 0 || contentExtent <= 0) {
      return null;
    }

    final maxThumbHeight = trackHeight < _maxThumbHeight
        ? trackHeight
        : _maxThumbHeight;
    if (maxThumbHeight <= 0) return null;
    final thumbHeight = (trackHeight * viewportExtent / contentExtent)
        .clamp(_minThumbHeight, maxThumbHeight)
        .toDouble();
    final thumbTravel = trackHeight - thumbHeight;
    final scrollFraction = thumbTravel <= 0
        ? 0.0
        : (position.pixels / maxScrollExtent).clamp(0.0, 1.0).toDouble();
    final thumbTop = _topInset + scrollFraction * thumbTravel;

    return _MemoScrollbarGeometry(
      trackHeight: trackHeight,
      thumbTop: thumbTop,
      thumbHeight: thumbHeight,
      thumbTravel: thumbTravel,
      maxScrollExtent: maxScrollExtent,
    );
  }

  void _jumpToLocalY(double localY, _MemoScrollbarGeometry geometry) {
    if (geometry.thumbTravel <= 0) return;
    final dragOffset = _dragThumbOffset ?? geometry.thumbHeight / 2;
    final targetThumbTop = localY - dragOffset;
    final scrollFraction = ((targetThumbTop - _topInset) / geometry.thumbTravel)
        .clamp(0.0, 1.0)
        .toDouble();
    widget.controller.jumpTo(scrollFraction * geometry.maxScrollExtent);
  }

  void _handlePointerDown(PointerDownEvent event, double height) {
    final geometry = _geometry(height);
    if (geometry == null) return;
    final localY = event.localPosition.dy;
    final hitThumb =
        localY >= geometry.thumbTop &&
        localY <= geometry.thumbTop + geometry.thumbHeight;
    _dragThumbOffset = hitThumb
        ? localY - geometry.thumbTop
        : geometry.thumbHeight / 2;
    _jumpToLocalY(localY, geometry);
  }

  void _handlePointerMove(PointerMoveEvent event, double height) {
    final geometry = _geometry(height);
    if (geometry == null) return;
    _jumpToLocalY(event.localPosition.dy, geometry);
  }

  void _clearDrag() {
    _dragThumbOffset = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final geometry = _geometry(height);
        if (geometry == null) return const SizedBox.shrink();

        return Listener(
          key: const ValueKey('mobile_send_memo_scrollbar'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handlePointerDown(event, height),
          onPointerMove: (event) => _handlePointerMove(event, height),
          onPointerUp: (_) => _clearDrag(),
          onPointerCancel: (_) => _clearDrag(),
          child: Stack(
            children: [
              Positioned(
                key: const ValueKey('mobile_send_memo_scrollbar_thumb'),
                left: _horizontalInset,
                top: geometry.thumbTop,
                width: _thumbWidth,
                height: geometry.thumbHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.thumbColor,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemoScrollbarGeometry {
  const _MemoScrollbarGeometry({
    required this.trackHeight,
    required this.thumbTop,
    required this.thumbHeight,
    required this.thumbTravel,
    required this.maxScrollExtent,
  });

  final double trackHeight;
  final double thumbTop;
  final double thumbHeight;
  final double thumbTravel;
  final double maxScrollExtent;
}
