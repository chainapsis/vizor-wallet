import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../voting_flow_models.dart';
import 'voting_pane_scroll_area.dart';
import 'voting_auto_advance_indicator.dart';
import 'voting_proposal_navigation.dart';

typedef VotingHeaderBuilder = Widget Function(bool compact, Widget? navigation);

/// A ballot with stable proposal-ID anchors, shared by live and preview routes.
class VotingProposalList extends StatefulWidget {
  const VotingProposalList({
    super.key,
    required this.proposals,
    required this.choices,
    required this.summary,
    required this.cardBuilder,
    required this.reviewAction,
    required this.onReview,
    required this.answerRevision,
    required this.lastEditedProposalId,
    required this.showDesktopToolbar,
    this.navigationEnabled = true,
    this.mobileHeaderBuilder,
  });

  final List<VotingProposalView> proposals;
  final Map<int, int> choices;
  final Widget summary;
  final Widget Function(VotingProposalView, bool advancing) cardBuilder;
  final Widget reviewAction;
  final VoidCallback? onReview;
  final int answerRevision;
  final int? lastEditedProposalId;
  final bool showDesktopToolbar;
  final bool navigationEnabled;
  final VotingHeaderBuilder? mobileHeaderBuilder;

  @override
  State<VotingProposalList> createState() => _VotingProposalListState();
}

class _VotingProposalListState extends State<VotingProposalList>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _reviewAnchor = GlobalKey();
  Timer? _advanceTimer;
  int? _advancingProposalId;
  // Clearing a choice must not make an already visited question new again.
  final _answeredProposalIds = <int>{};
  bool _autoScrolling = false;
  bool _compact = false;
  final _anchors = <int, GlobalKey>{};
  final _focus = <int, FocusNode>{};
  Timer? _highlightTimer;
  int? _highlighted;
  int _jumpGeneration = 0;
  bool _reviewVisible = false;

  @override
  void initState() {
    super.initState();
    _syncAnchors();
    _answeredProposalIds.addAll(widget.choices.keys);
    _scroll.addListener(_handleScroll);
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(covariant VotingProposalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnchors();
    final id = widget.lastEditedProposalId;
    final firstAnswer =
        id != null &&
        widget.choices[id] != null &&
        !_answeredProposalIds.contains(id);
    _answeredProposalIds.addAll(widget.choices.keys);
    if (!widget.navigationEnabled) _cancelAutoAdvance();
    if (widget.answerRevision == oldWidget.answerRevision) return;
    _cancelAutoAdvance();
    if (id == null ||
        !firstAnswer ||
        !widget.navigationEnabled ||
        oldWidget.choices[id] != null ||
        widget.choices[id] == null) {
      return;
    }
    final index = widget.proposals.indexWhere((proposal) => proposal.id == id);
    if (index < 0 ||
        !widget.proposals
            .skip(index + 1)
            .any((proposal) => widget.choices[proposal.id] == null)) {
      return;
    }
    _advancingProposalId = id;
    _advanceTimer = Timer(votingAutoAdvanceDelay, () {
      _clearAdvanceCue();
      if (!mounted ||
          !widget.navigationEnabled ||
          widget.choices[id] == null ||
          ModalRoute.of(context)?.isCurrent == false ||
          !_isVisible(id)) {
        return;
      }
      final index = widget.proposals.indexWhere(
        (proposal) => proposal.id == id,
      );
      if (index < 0) return;
      final next = widget.proposals
          .skip(index + 1)
          .where((proposal) => widget.choices[proposal.id] == null)
          .firstOrNull;
      if (next != null) unawaited(_jump(next.id, automatic: true));
    });
  }

  bool _isVisible(int id) {
    final viewport = _viewport.currentContext?.findRenderObject();
    final card = _anchors[id]?.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        card is! RenderBox ||
        !viewport.hasSize ||
        !card.hasSize) {
      return false;
    }
    final top = card.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return top < viewport.size.height && top + card.size.height > 0;
  }

  void _handleScroll() {
    // Any movement during the confirmation pause supersedes the scheduled jump.
    _clearAdvanceCue();
    _updateReviewVisibility();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _cancelAutoAdvance();
    return KeyEventResult.ignored;
  }

  void _clearAdvanceCue() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (_advancingProposalId != null && mounted) {
      setState(() => _advancingProposalId = null);
    }
  }

  void _cancelAutoAdvance() {
    _clearAdvanceCue();
    if (_autoScrolling) {
      _autoScrolling = false;
      ++_jumpGeneration;
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelAutoAdvance();
  }

  void _syncAnchors() {
    final ids = widget.proposals.map((p) => p.id).toSet();
    for (final id in _anchors.keys.toList()) {
      if (!ids.contains(id)) {
        _anchors.remove(id);
        _focus.remove(id)?.dispose();
      }
    }
    for (final id in ids) {
      _anchors.putIfAbsent(id, GlobalKey.new);
      _focus.putIfAbsent(id, FocusNode.new);
    }
  }

  void _updateReviewVisibility() {
    if (!mounted) return;
    final viewport = _viewport.currentContext?.findRenderObject();
    final action = _reviewAnchor.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        action is! RenderBox ||
        !viewport.hasSize ||
        !action.hasSize) {
      return;
    }
    if (kAppFormFactor == AppFormFactor.mobile && widget.proposals.isNotEmpty) {
      final first = _anchors[widget.proposals.first.id]?.currentContext
          ?.findRenderObject();
      if (first is RenderBox && first.hasSize) {
        final firstTop = first
            .localToGlobal(Offset.zero, ancestor: viewport)
            .dy;
        final compact = firstTop <= (_compact ? AppSpacing.sm : 0);
        if (compact != _compact) setState(() => _compact = compact);
      }
    }
    final top = action.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final margin = _reviewVisible ? 0.0 : AppSpacing.xs;
    final visible =
        top >= margin &&
        top + action.size.height <= viewport.size.height - margin;
    if (visible != _reviewVisible) setState(() => _reviewVisible = visible);
  }

  Future<void> _jump(int id, {bool automatic = false}) async {
    _cancelAutoAdvance();
    final object = _anchors[id]?.currentContext?.findRenderObject();
    if (object == null || !_scroll.hasClients) return;
    _autoScrolling = automatic;
    final generation = ++_jumpGeneration;
    // Desktop cards need breathing room below the fixed toolbar after a jump.
    const topInset = kAppFormFactor == AppFormFactor.desktop
        ? AppSpacing.sm
        : 0.0;
    final target =
        (RenderAbstractViewport.of(object).getOffsetToReveal(object, 0).offset -
                topInset)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    if (generation == _jumpGeneration) _autoScrolling = false;
    if (!mounted ||
        generation != _jumpGeneration ||
        !_anchors.containsKey(id) ||
        (automatic && ModalRoute.of(context)?.isCurrent == false)) {
      return;
    }
    _highlightTimer?.cancel();
    _focus[id]?.requestFocus();
    setState(() => _highlighted = id);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    _highlightTimer?.cancel();
    _scroll.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateReviewVisibility(),
    );
    final navigation = SizedBox(
      width: mobile ? null : 220,
      child: VotingProposalNavigation(
        proposals: widget.proposals,
        choices: widget.choices,
        onJump: _jump,
        onReview: widget.onReview,
        inlineReviewVisible: _reviewVisible,
        answerRevision: widget.answerRevision,
      ),
    );
    return Listener(
      onPointerDown: (_) => _cancelAutoAdvance(),
      onPointerSignal: (_) => _cancelAutoAdvance(),
      onPointerPanZoomStart: (_) => _cancelAutoAdvance(),
      child: Column(
        children: [
          if (mobile)
            if (widget.mobileHeaderBuilder != null)
              widget.mobileHeaderBuilder!(
                _compact,
                widget.navigationEnabled ? navigation : null,
              )
            else if (widget.navigationEnabled)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: navigation,
              ),
          if (!mobile)
            if (widget.showDesktopToolbar)
              Stack(
                children: [
                  // Keep the back link on the shared 48 px toolbar baseline.
                  // Enlarged navigation can grow the band without moving it.
                  const AppPaneToolbar(backLinkMinWidth: 60),
                  if (widget.navigationEnabled)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        right: AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        heightFactor: 1,
                        child: navigation,
                      ),
                    ),
                ],
              )
            else if (widget.navigationEnabled)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: navigation,
                ),
              ),
          Expanded(
            child: Stack(
              key: _viewport,
              children: [
                VotingPaneScrollbar(
                  controller: _scroll,
                  builder: (context, controller) => SingleChildScrollView(
                    controller: controller,
                    primary: false,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            mobile ? AppSpacing.sm : AppSpacing.md,
                            mobile ? AppSpacing.s : AppSpacing.sm,
                            mobile ? AppSpacing.sm : AppSpacing.md,
                            AppSpacing.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              widget.summary,
                              const SizedBox(height: AppSpacing.md),
                              for (final proposal in widget.proposals) ...[
                                Focus(
                                  key: _anchors[proposal.id],
                                  focusNode: _focus[proposal.id],
                                  child: Stack(
                                    children: [
                                      widget.cardBuilder(
                                        proposal,
                                        _advancingProposalId == proposal.id,
                                      ),
                                      if (_highlighted == proposal.id)
                                        Positioned.fill(
                                          key: ValueKey(
                                            'jump-highlight-${proposal.id}',
                                          ),
                                          child: IgnorePointer(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: context
                                                      .colors
                                                      .text
                                                      .accent
                                                      .withValues(alpha: .35),
                                                  width: 1.5,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      mobile
                                                          ? AppRadii.large
                                                          : AppRadii.medium,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (proposal != widget.proposals.last)
                                  const SizedBox(height: AppSpacing.xs),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              SizedBox(
                                key: _reviewAnchor,
                                child: widget.reviewAction,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
