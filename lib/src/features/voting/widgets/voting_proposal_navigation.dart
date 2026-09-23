import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../voting_flow_models.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;

/// Navigation for a ballot. Answer persistence and review eligibility belong
/// to the caller; only explicit answer edits trigger the completion cue.
class VotingProposalNavigation extends StatefulWidget {
  const VotingProposalNavigation({
    super.key,
    required this.proposals,
    required this.choices,
    required this.onJump,
    required this.onReview,
    required this.inlineReviewVisible,
    required this.answerRevision,
  });

  final List<VotingProposalView> proposals;
  final Map<int, int> choices;
  final ValueChanged<int> onJump;
  final VoidCallback? onReview;
  final bool inlineReviewVisible;
  final int answerRevision;

  @override
  State<VotingProposalNavigation> createState() =>
      _VotingProposalNavigationState();
}

class _VotingProposalNavigationState extends State<VotingProposalNavigation> {
  final _progressAnchor = GlobalKey();
  final _progressFocus = FocusNode();
  final _reviewFocus = FocusNode();
  Timer? _completionTimer;
  bool _showCompletionCue = false;
  bool _menuOpen = false;

  List<String> get _topics => widget.proposals.map((p) => p.title).toList();
  List<int> get _unanswered => [
    for (var i = 0; i < widget.proposals.length; i++)
      if (widget.choices[widget.proposals[i].id] == null) i,
  ];

  @override
  void didUpdateWidget(covariant VotingProposalNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_unanswered.isNotEmpty) {
      _completionTimer?.cancel();
      _showCompletionCue = false;
    } else if (oldWidget.answerRevision != widget.answerRevision &&
        oldWidget.proposals.any((p) => oldWidget.choices[p.id] == null)) {
      _showCompletionCue = true;
      if (_mobile) unawaited(AppHaptics.votingAnswersComplete());
      _completionTimer?.cancel();
      _completionTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _showCompletionCue = false);
      });
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _progressFocus.dispose();
    _reviewFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollbarTheme(
    data: ScrollbarTheme.of(context).copyWith(
      thumbVisibility: const WidgetStatePropertyAll(false),
      thumbColor: WidgetStatePropertyAll(context.colors.surface.scrollbarThumb),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(AppRadii.full),
      crossAxisMargin: 6,
      mainAxisMargin: AppSpacing.xs,
    ),
    child: _buildNavigationControls(),
  );

  Future<void> _showUnanswered() async {
    if (_menuOpen) return;
    final proposals = widget.proposals;
    if (_mobile) {
      setState(() => _menuOpen = true);
      final selected = await showAppMobileSheet<int>(
        context: context,
        builder: (_) =>
            _MobileUnansweredSheet(unanswered: _unanswered, topics: _topics),
      );
      if (!mounted) return;
      setState(() => _menuOpen = false);
      if (selected != null) {
        final id = proposals[selected].id;
        if (widget.proposals.any((p) => p.id == id)) widget.onJump(id);
      }
      return;
    }
    final colors = context.colors;
    setState(() => _menuOpen = true);
    final selected = await showMenu<int>(
      context: _progressAnchor.currentContext!,
      requestFocus: true,
      semanticLabel: 'Unanswered questions',
      menuPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      clipBehavior: Clip.antiAlias,
      color: colors.background.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(color: colors.border.subtle),
      ),
      constraints: BoxConstraints(
        minWidth: 280,
        maxWidth: 360,
        maxHeight: MediaQuery.sizeOf(context).height * .55,
      ),
      positionBuilder: (context, constraints) {
        final anchor =
            (_progressAnchor.currentContext!).findRenderObject()! as RenderBox;
        final overlay =
            Navigator.of(context).overlay!.context.findRenderObject()!
                as RenderBox;
        final topLeft = anchor.localToGlobal(
          Offset(0, anchor.size.height + AppSpacing.xs),
          ancestor: overlay,
        );
        return RelativeRect.fromRect(
          topLeft & Size(anchor.size.width, 0),
          Offset.zero & overlay.size,
        );
      },
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: 40,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            _unanswered.isEmpty
                ? 'All questions answered'
                : 'Unanswered · ${_unanswered.length}',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        for (final index in _unanswered)
          _DesktopUnansweredMenuItem(
            key: ValueKey('unanswered-item-$index'),
            value: index,
            height: 40,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: AppSpacing.xs,
            ),
            child: Tooltip(
              waitDuration: const Duration(milliseconds: 600),
              message: _topics[index],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(28),
                    child: Text(
                      '${index + 1}.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      _topics[index],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected != null) {
      final id = proposals[selected].id;
      if (widget.proposals.any((p) => p.id == id)) widget.onJump(id);
    } else {
      _progressFocus.requestFocus();
    }
  }

  Widget _buildNavigationControls() {
    final complete = _unanswered.isEmpty;
    final showReview = complete && !_showCompletionCue;
    final hidden = showReview && widget.inlineReviewVisible;
    return SizedBox(
      key: const ValueKey('navigation-controls'),
      child: IgnorePointer(
        key: const ValueKey('sticky-review-hit-target'),
        ignoring: hidden,
        child: ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(
            excluding: hidden,
            child: AnimatedOpacity(
              opacity: hidden ? 0 : 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: KeyedSubtree(
                key: _progressAnchor,
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final child in previous)
                        ExcludeFocus(
                          child: ExcludeSemantics(
                            child: IgnorePointer(child: child),
                          ),
                        ),
                      ?current,
                    ],
                  ),
                  child: SizedBox(
                    key: ValueKey(
                      showReview ? 'review-control' : 'progress-control',
                    ),
                    width: double.infinity,
                    child: AppButton(
                      size: _mobile
                          ? AppButtonSize.large
                          : AppButtonSize.medium,
                      focusNode: showReview ? _reviewFocus : _progressFocus,
                      onPressed: complete
                          ? (showReview ? widget.onReview : null)
                          : _showUnanswered,
                      variant: showReview
                          ? AppButtonVariant.primary
                          : AppButtonVariant.secondary,
                      expand: true,
                      growWithContent:
                          _mobile ||
                          MediaQuery.textScalerOf(
                                context,
                              ).scale(AppTypography.labelMedium.fontSize!) >
                              AppTypography.labelMedium.fontSize!,
                      constrainContent: true,
                      height: _mobile ? 44 : 32,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      trailing: _showCompletionCue
                          ? TweenAnimationBuilder<double>(
                              key: const ValueKey('completion-check-entrance'),
                              tween: Tween(begin: 0, end: 1),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Transform.scale(
                                  scale: .8 + .2 * value,
                                  child: child,
                                ),
                              ),
                              child: const AppIcon(
                                AppIcons.check,
                                key: ValueKey('completion-check'),
                              ),
                            )
                          : RotatedBox(
                              quarterTurns: showReview ? 0 : 1,
                              child: const AppIcon(AppIcons.chevronForward),
                            ),
                      child: Text(
                        showReview
                            ? 'Review answers'
                            : '${widget.proposals.length - _unanswered.length} / ${widget.proposals.length} answered',
                        key: ValueKey(
                          showReview
                              ? 'sticky-review-action'
                              : 'answer-progress',
                        ),
                        style: AppTypography.labelMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Keep native menu keyboard handling and semantics while clipping each ink
// surface independently, so hover and focus respect the inset rounded rows.
class _DesktopUnansweredMenuItem extends PopupMenuItem<int> {
  const _DesktopUnansweredMenuItem({
    required super.value,
    required super.child,
    required super.height,
    required super.padding,
    super.key,
  });

  @override
  PopupMenuItemState<int, _DesktopUnansweredMenuItem> createState() =>
      _DesktopUnansweredMenuItemState();
}

class _DesktopUnansweredMenuItemState
    extends PopupMenuItemState<int, _DesktopUnansweredMenuItem> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(AppRadii.small),
      clipBehavior: Clip.antiAlias,
      child: super.build(context),
    ),
  );
}

class _MobileUnansweredSheet extends StatefulWidget {
  const _MobileUnansweredSheet({
    required this.unanswered,
    required this.topics,
  });
  final List<int> unanswered;
  final List<String> topics;

  @override
  State<_MobileUnansweredSheet> createState() => _MobileUnansweredSheetState();
}

class _MobileUnansweredSheetState extends State<_MobileUnansweredSheet> {
  final _scroll = ScrollController();
  final _bodyScroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    key: const ValueKey('mobile-unanswered-sheet'),
    constraints: BoxConstraints(
      maxHeight:
          MediaQuery.sizeOf(context).height *
          (MediaQuery.textScalerOf(context).scale(1) > 1.3 ? .9 : .65),
    ),
    child: MobileModalScaffold(
      title: widget.unanswered.isEmpty
          ? 'All questions answered'
          : 'Unanswered · ${widget.unanswered.length}',
      titleMaxLines: 2,
      onClose: () => Navigator.pop(context),
      constrainBody: true,
      child: _adaptiveSheetBody(context, [
        Text(
          widget.unanswered.isEmpty
              ? 'Your answers are ready to review.'
              : 'Tap a question to jump to it.',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _listRegion(
          context,
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: _listScrollbar(
              context,
              ListView.separated(
                key: const ValueKey('mobile-unanswered-list'),
                controller: _scroll,
                shrinkWrap: true,
                physics: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: EdgeInsets.zero,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xxs),
                itemCount: widget.unanswered.length,
                itemBuilder: (context, position) {
                  final index = widget.unanswered[position];
                  return Material(
                    key: ValueKey('mobile-unanswered-item-$index'),
                    color: context.colors.background.neutralSubtleOpacity,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, index),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s,
                            horizontal: AppSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: MediaQuery.textScalerOf(
                                  context,
                                ).scale(28),
                                child: Text(
                                  '${index + 1}.',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: context.colors.text.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  widget.topics[index],
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: context.colors.text.accent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              AppIcon(
                                AppIcons.chevronForward,
                                color: context.colors.icon.regular,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ]),
    ),
  );

  Widget _listScrollbar(BuildContext context, Widget child) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.3
      ? child
      : _scrollbar(context, _scroll, child);

  Widget _scrollbar(
    BuildContext context,
    ScrollController controller,
    Widget child,
  ) => RawScrollbar(
    controller: controller,
    thumbVisibility: false,
    thickness: 3,
    scrollbarOrientation: ScrollbarOrientation.right,
    mainAxisMargin: AppSpacing.xs,
    crossAxisMargin: 6,
    radius: const Radius.circular(AppRadii.full),
    thumbColor: context.colors.surface.scrollbarThumb,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: child,
      ),
    ),
  );

  Widget _listRegion(BuildContext context, Widget child) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.3
      ? child
      : Flexible(child: child);

  Widget _adaptiveSheetBody(BuildContext context, List<Widget> children) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) return column;
    return _scrollbar(
      context,
      _bodyScroll,
      SingleChildScrollView(controller: _bodyScroll, child: column),
    );
  }
}
