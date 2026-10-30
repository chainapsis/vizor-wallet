import 'dart:async';

import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';

/// Desktop Ledger dialogs share a fixed heading/footer and a scrollable body.
class LedgerModalContent extends StatefulWidget {
  const LedgerModalContent({
    required this.title,
    required this.child,
    this.identity,
    this.identityIcon = AppIcons.ledger,
    this.onBack,
    this.backLabel = 'Choose connection',
    this.footer,
    super.key,
  });
  final String title;
  final Widget child;
  final String? identity;
  final String identityIcon;
  final VoidCallback? onBack;
  final String backLabel;
  final Widget? footer;

  @override
  State<LedgerModalContent> createState() => _LedgerModalContentState();
}

class _LedgerModalContentState extends State<LedgerModalContent> {
  final _scroll = ScrollController();
  FocusNode? _returnFocus;

  @override
  void initState() {
    super.initState();
    _returnFocus = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  final _focus = FocusScopeNode(
    debugLabel: 'Ledger modal',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    final target = _returnFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (target?.context?.mounted != true) return;
        final active = FocusManager.instance.primaryFocus?.context;
        // A replacement Ledger dialog owns focus before restoring the caller.
        if (active?.findAncestorWidgetOfExactType<LedgerModalContent>() ==
            null) {
          target!.requestFocus();
        }
      });
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _focus,
    autofocus: true,
    child: BlockSemantics(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: widget.title,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height - 56,
          ),
          child: AppModalCard(
            width: 400,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (widget.onBack != null) ...[
                            AppButton(
                              onPressed: widget.onBack,
                              variant: AppButtonVariant.ghost,
                              size: AppButtonSize.small,
                              child: AppIcon(
                                AppIcons.chevronBackward,
                                size: 16,
                                semanticLabel: widget.backLabel,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          Expanded(
                            child: Text(
                              widget.title,
                              style: AppTypography.bodyLarge.copyWith(
                                color: context.colors.text.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.identity case final identity?) ...[
                        const SizedBox(height: AppSpacing.s),
                        Row(
                          children: [
                            AppIcon(
                              widget.identityIcon,
                              size: 16,
                              color: context.colors.icon.muted,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                identity,
                                style: AppTypography.bodySmall.copyWith(
                                  color: context.colors.text.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          20,
                          24,
                          widget.footer == null ? 24 : 12,
                        ),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
                if (widget.footer case final footer?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
