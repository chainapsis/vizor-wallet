import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';

/// A mobile Ledger modal over its caller. The operation owner stays mounted
/// across discovery, verification and signing; changing content never pops a
/// route or cancels the operation. Route-backed callers must be non-opaque.
class MobileLedgerSigningSurface extends StatefulWidget {
  const MobileLedgerSigningSurface({
    required this.child,
    required this.onBack,
    required this.canLeave,
    this.title = 'Ledger',
    super.key,
  });
  final Widget child;
  final VoidCallback onBack;
  final bool canLeave;
  final String title;

  @override
  State<MobileLedgerSigningSurface> createState() =>
      _MobileLedgerSigningSurfaceState();
}

class _MobileLedgerSigningSurfaceState
    extends State<MobileLedgerSigningSurface> {
  bool _closing = false;
  double _dragDistance = 0;

  void _dismiss() {
    if (!widget.canLeave || _closing) return;
    _closing = true;
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _dismiss();
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          color: context.colors.background.neutralScrim,
          dismissible: widget.canLeave,
          onDismiss: _dismiss,
          semanticsLabel: 'Close Ledger',
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onVerticalDragStart: (_) => _dragDistance = 0,
              onVerticalDragUpdate: (details) =>
                  _dragDistance += details.delta.dy,
              onVerticalDragEnd: (details) {
                if (_dragDistance > 80 ||
                    (details.primaryVelocity ?? 0) > 700) {
                  _dismiss();
                }
              },
              child: MobileModalCard(child: widget.child),
            ),
          ),
        ),
      ],
    ),
  );
}
