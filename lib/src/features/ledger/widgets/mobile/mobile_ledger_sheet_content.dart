import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../home/widgets/mobile/shield/shield_hardware_motion.dart';

/// Mobile-only content. The host owns the scrim and MobileModalCard.
class MobileLedgerSheetContent extends StatefulWidget {
  const MobileLedgerSheetContent({
    required this.title,
    required this.onClose,
    required this.children,
    this.action,
    this.onBack,
    super.key,
  });
  final String title;
  final VoidCallback? onClose;
  final List<Widget> children;
  final Widget? action;
  final VoidCallback? onBack;

  @override
  State<MobileLedgerSheetContent> createState() =>
      _MobileLedgerSheetContentState();
}

class _MobileLedgerSheetContentState extends State<MobileLedgerSheetContent> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inline = context
        .dependOnInheritedWidgetOfExactType<LedgerInlinePresentation>();
    if (inline != null) return _inlineContent(context, inline);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MobileModalScaffold(
        title: widget.title,
        titleMaxLines: 3,
        showClose: widget.onClose != null,
        onClose: widget.onClose ?? () {},
        leading: widget.onBack == null ? null : _backButton(),
        constrainBody: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 3,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                ),
              ),
            ),
            if (widget.action != null) widget.action!,
          ],
        ),
      ),
    );
  }

  Widget _inlineContent(BuildContext context, LedgerInlinePresentation inline) {
    final motion = ShieldHardwarePresentation.maybeOf(context);
    final heading = Text(
      widget.title,
      textAlign: TextAlign.center,
      style: AppTypography.headlineSmall.copyWith(
        color: context.colors.text.accent,
      ),
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onBack != null)
          Align(alignment: Alignment.centerLeft, child: _backButton()),
        if (motion == null)
          heading
        else
          ShieldStageTransition(identity: widget.title, child: heading),
        const SizedBox(height: AppSpacing.md),
        ...widget.children,
      ],
    );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.action != null) widget.action!,
        if (widget.onClose != null)
          MobileLedgerAction(inline.closeLabel, onPressed: widget.onClose),
      ],
    );
    if (motion == null) return Column(children: [body, actions]);
    final duration = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 120 : 140,
    );
    final footer = SizedBox(
      width: double.infinity,
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOut,
        clipBehavior: Clip.none,
        child: AnimatedSwitcher(
          duration: duration,
          layoutBuilder: (current, previous) => Stack(
            clipBehavior: Clip.none,
            children: [
              for (final old in previous)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ExcludeFocus(
                    child: ExcludeSemantics(child: IgnorePointer(child: old)),
                  ),
                ),
              ?current,
            ],
          ),
          child: SizedBox(
            key: ValueKey((
              widget.action != null,
              widget.onClose != null,
              inline.closeLabel,
            )),
            width: double.infinity,
            child: actions,
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) => Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 3,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: bounds.maxWidth,
                      minHeight: bounds.maxHeight,
                    ),
                    child: Center(
                      child: Opacity(opacity: motion.mix, child: body),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ExcludeSemantics(
            excluding: !motion.interactive,
            child: ExcludeFocus(
              excluding: !motion.interactive,
              child: IgnorePointer(
                ignoring: !motion.interactive,
                child: Opacity(
                  opacity: motion.footerOpacity,
                  child: Transform.translate(
                    offset: Offset(0, motion.footerDy),
                    child: footer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backButton() => AppButton(
    variant: AppButtonVariant.ghost,
    onPressed: widget.onBack,
    child: Semantics(
      label: 'Back',
      button: true,
      child: const ExcludeSemantics(
        child: AppIcon(AppIcons.chevronBackward, size: 20),
      ),
    ),
  );
}

class MobileLedgerMessage extends StatelessWidget {
  const MobileLedgerMessage(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Text(
    message,
    style: AppTypography.bodyMedium.copyWith(
      color: context.colors.text.secondary,
    ),
  );
}

class MobileLedgerStatus extends StatelessWidget {
  const MobileLedgerStatus(this.label, {this.active = true, super.key});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final motion = ShieldHardwarePresentation.maybeOf(context);
    final labelWidget = Text(
      label,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.accent,
      ),
    );
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: motion == null
                      ? labelWidget
                      : ShieldStageTransition(
                          identity: label,
                          child: labelWidget,
                        ),
                ),
                if (active) ...[
                  const SizedBox(width: AppSpacing.xs),
                  AppIcon(
                    AppIcons.loader,
                    animated: true,
                    size: 20,
                    color: context.colors.icon.regular,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MobileLedgerIdentity extends StatelessWidget {
  const MobileLedgerIdentity(
    this.label, {
    this.topPadding = AppSpacing.md,
    super.key,
  });
  final String label;
  final double topPadding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: topPadding),
    child: Row(
      children: [
        AppIcon(AppIcons.ledger, size: 20, color: context.colors.icon.regular),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    ),
  );
}

class MobileLedgerAction extends StatelessWidget {
  const MobileLedgerAction(this.label, {required this.onPressed, super.key});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: AppButton(
      expand: true,
      constrainContent: true,
      growWithContent: true,
      size: AppButtonSize.large,
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

/// Reuse Ledger owners and guidance inside the shield scene's own layout.
class LedgerInlinePresentation extends InheritedWidget {
  const LedgerInlinePresentation({
    required super.child,
    this.closeLabel = 'Cancel shielding',
    super.key,
  });
  final String closeLabel;
  @override
  bool updateShouldNotify(LedgerInlinePresentation oldWidget) =>
      closeLabel != oldWidget.closeLabel;
}
