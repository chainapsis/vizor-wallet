import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Validates a complete paste before EditableText can replace the draft.
/// Ordinary typing and IME updates continue through the field unchanged.
class ValidatedPasteRegion extends StatefulWidget {
  const ValidatedPasteRegion({
    required this.controller,
    required this.onPaste,
    required this.builder,
    this.pasteContext,
    this.readPasteContext,
    super.key,
  });

  final TextEditingController controller;
  final Object? pasteContext;

  /// Reads live context before/after Clipboard, even before the next frame.
  final Object? Function()? readPasteContext;
  final Future<void> Function(String candidate)? onPaste;
  final Widget Function(EditableTextContextMenuBuilder menuBuilder) builder;

  @override
  State<ValidatedPasteRegion> createState() => _ValidatedPasteRegionState();
}

class _ValidatedPasteRegionState extends State<ValidatedPasteRegion> {
  int _generation = 0;
  Animation<double>? _routeAnimation;

  void _invalidate() => _generation++;

  void _routeStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _invalidate();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_invalidate);
  }

  @override
  void didUpdateWidget(covariant ValidatedPasteRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pasteContext != widget.pasteContext) _invalidate();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_invalidate);
      widget.controller.addListener(_invalidate);
      _invalidate();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _invalidate();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_routeStatusChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_invalidate);
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
    super.dispose();
  }

  Future<void> _paste() async {
    final callback = widget.onPaste;
    if (callback == null) return;
    final generation = ++_generation;
    final controller = widget.controller;
    final before = controller.value;
    final route = ModalRoute.of(context);
    final contextBefore = widget.readPasteContext?.call();
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        generation != _generation ||
        widget.controller != controller ||
        widget.onPaste == null ||
        contextBefore != widget.readPasteContext?.call() ||
        controller.value != before ||
        (route != null &&
            (!route.isCurrent ||
                route.animation?.status == AnimationStatus.reverse))) {
      return;
    }
    final text = clipboard?.text;
    if (text == null || text.isEmpty) return;
    final selection = before.selection;
    final candidate = selection.isValid
        ? before.text.replaceRange(selection.start, selection.end, text)
        : text;
    await callback(candidate);
  }

  Widget _menu(BuildContext context, EditableTextState editable) {
    if (widget.onPaste == null) {
      if (SystemContextMenu.isSupportedByField(editable)) {
        return SystemContextMenu.editableText(editableTextState: editable);
      }
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editable,
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: editable.contextMenuButtonItems.map((item) {
        if (item.type != ContextMenuButtonType.paste) return item;
        return ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            editable.hideToolbar();
            unawaited(_paste());
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(_menu);
    if (widget.onPaste == null) return child;
    return Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            unawaited(_paste());
            return null;
          },
        ),
      },
      child: child,
    );
  }
}
