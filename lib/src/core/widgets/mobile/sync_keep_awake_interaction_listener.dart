import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../layout/app_form_factor.dart';
import '../../../providers/sync_keep_awake_provider.dart';

class SyncKeepAwakeInteractionListener extends ConsumerStatefulWidget {
  const SyncKeepAwakeInteractionListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncKeepAwakeInteractionListener> createState() =>
      _SyncKeepAwakeInteractionListenerState();
}

class _SyncKeepAwakeInteractionListenerState
    extends ConsumerState<SyncKeepAwakeInteractionListener> {
  // Focus notifications and showOnScreen can be generated automatically by
  // announcements/rebuilds. Only deliberate actions extend the idle deadline.
  static const _userActions = {
    SemanticsAction.tap,
    SemanticsAction.longPress,
    SemanticsAction.scrollLeft,
    SemanticsAction.scrollRight,
    SemanticsAction.scrollUp,
    SemanticsAction.scrollDown,
    SemanticsAction.scrollToOffset,
    SemanticsAction.increase,
    SemanticsAction.decrease,
    SemanticsAction.moveCursorForwardByCharacter,
    SemanticsAction.moveCursorBackwardByCharacter,
    SemanticsAction.moveCursorForwardByWord,
    SemanticsAction.moveCursorBackwardByWord,
    SemanticsAction.setSelection,
    SemanticsAction.copy,
    SemanticsAction.cut,
    SemanticsAction.paste,
    SemanticsAction.setText,
    SemanticsAction.customAction,
    SemanticsAction.dismiss,
    SemanticsAction.expand,
    SemanticsAction.collapse,
  };

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor != AppFormFactor.mobile) return;
    SemanticsBinding.instance.addSemanticsActionListener(_onSemanticsAction);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    if (kAppFormFactor == AppFormFactor.mobile) {
      SemanticsBinding.instance.removeSemanticsActionListener(
        _onSemanticsAction,
      );
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    super.dispose();
  }

  void _onSemanticsAction(SemanticsActionEvent event) {
    if (!_userActions.contains(event.type) ||
        event.viewId != View.of(context).viewId) {
      return;
    }
    // Ignore stale actions for nodes removed by a lock, and actions that the
    // addressed node does not expose. Observation never consumes the action.
    for (final view in WidgetsBinding.instance.renderViews) {
      if (view.flutterView.viewId != event.viewId) continue;
      final node = view.owner?.semanticsOwner?.getSemanticsNode(event.nodeId);
      if (node?.getSemanticsData().hasAction(event.type) ?? false) {
        _markInteraction();
      }
      break;
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!event.synthesized &&
        (event is KeyDownEvent || event is KeyRepeatEvent)) {
      _markInteraction();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor != AppFormFactor.mobile) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markInteraction(),
      onPointerMove: (_) => _markInteraction(),
      onPointerSignal: (_) => _markInteraction(),
      child: widget.child,
    );
  }

  void _markInteraction() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        ref.read(syncKeepAwakePrivacyLockProvider).isLocked) {
      return;
    }
    ref.read(syncKeepAwakeInteractionProvider.notifier).markInteraction();
  }
}
