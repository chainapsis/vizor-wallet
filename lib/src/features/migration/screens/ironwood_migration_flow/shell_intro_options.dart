part of '../ironwood_migration_flow_screen.dart';

class _RedirectTo extends StatefulWidget {
  const _RedirectTo(this.location);

  final String location;

  @override
  State<_RedirectTo> createState() => _RedirectToState();
}

class _RedirectToState extends State<_RedirectTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IronwoodMigrationLoadingShell extends StatelessWidget {
  const _IronwoodMigrationLoadingShell({required this.step});

  final IronwoodMigrationFlowStep step;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _IronwoodMigrationShell extends ConsumerWidget {
  const _IronwoodMigrationShell({
    required this.step,
    required this.data,
    this.previewPrivatePlan,
    this.previewImmediatePlan,
    this.previewCustomPlan,
    this.previewReviewStage = IronwoodMigrationReviewPreviewStage.review,
    this.onOpenReleaseNotesOverride,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final rust_sync.OrchardMigrationPrivatePlan? previewCustomPlan;
  final IronwoodMigrationReviewPreviewStage previewReviewStage;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final content = switch (step) {
      IronwoodMigrationFlowStep.prepare => const Center(
        child: CircularProgressIndicator(),
      ),
      IronwoodMigrationFlowStep.intro => _IronwoodMigrationIntroContent(
        data: data,
        onOpenReleaseNotes: () =>
            _openReleaseNotes(context, override: onOpenReleaseNotesOverride),
      ),
      IronwoodMigrationFlowStep.howItWorks =>
        _IronwoodMigrationHowItWorksContent(data: data),
      IronwoodMigrationFlowStep.whatToExpect =>
        const _IronwoodMigrationWhatToExpectContent(),
      IronwoodMigrationFlowStep.options => _IronwoodMigrationOptionsContent(
        data: data,
      ),
      IronwoodMigrationFlowStep.review =>
        _IronwoodMigrationPrivateReviewContent(
          data: data,
          previewPlan:
              previewReviewStage ==
                  IronwoodMigrationReviewPreviewStage.analyzing
              ? null
              : previewPrivatePlan,
          forceAnalyzing:
              previewReviewStage ==
              IronwoodMigrationReviewPreviewStage.analyzing,
        ),
      IronwoodMigrationFlowStep.immediateReview =>
        _IronwoodMigrationImmediateReviewContent(
          data: data,
          previewPlan: previewImmediatePlan,
        ),
      IronwoodMigrationFlowStep.custom => IronwoodMigrationCustomContent(
        data: data,
        previewPlan: previewCustomPlan,
      ),
    };

    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: content,
    );
  }
}

Future<void> _openReleaseNotes(
  BuildContext context, {
  VoidCallback? override,
}) async {
  if (override != null) {
    override();
    return;
  }
  final uri = Uri.parse(kIronwoodMigrationReleaseNotesUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget _toolbarFor(BuildContext context, IronwoodMigrationFlowStep step) {
  return AppPaneToolbar(
    leading: AppBackLink(
      label: switch (step) {
        IronwoodMigrationFlowStep.prepare => 'Home',
        IronwoodMigrationFlowStep.intro => 'Home',
        IronwoodMigrationFlowStep.howItWorks => 'Ironwood Pool',
        IronwoodMigrationFlowStep.whatToExpect => 'How Migration Works',
        IronwoodMigrationFlowStep.options => 'About Migration',
        IronwoodMigrationFlowStep.review => 'Migration Options',
        IronwoodMigrationFlowStep.immediateReview => 'Migration Options',
        IronwoodMigrationFlowStep.custom => 'Migration Options',
      },
      onTap: () {
        switch (step) {
          case IronwoodMigrationFlowStep.prepare:
            context.go('/home');
          case IronwoodMigrationFlowStep.intro:
            context.go('/home');
          case IronwoodMigrationFlowStep.howItWorks:
            context.go('/migration/intro');
          case IronwoodMigrationFlowStep.whatToExpect:
            context.go('/migration/how-it-works');
          case IronwoodMigrationFlowStep.options:
            context.go('/migration/what-to-expect');
          case IronwoodMigrationFlowStep.review:
            context.go('/migration/options');
          case IronwoodMigrationFlowStep.immediateReview:
            context.go('/migration/options');
          case IronwoodMigrationFlowStep.custom:
            context.go('/migration/options');
        }
      },
    ),
  );
}

Widget _privateStatusToolbar(BuildContext context) {
  return AppPaneToolbar(
    leading: AppBackLink(
      label: 'Ironwood Pool',
      onTap: () => context.go('/home'),
    ),
  );
}

class _IronwoodMigrationFrame extends StatelessWidget {
  const _IronwoodMigrationFrame({
    required this.toolbar,
    required this.child,
    required this.disableSidebarActions,
    this.overlay,
  });

  final Widget toolbar;
  final Widget child;
  final bool disableSidebarActions;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: AppMainSidebar(
        disabledRoutePaths: disableSidebarActions
            ? const {'/swap', '/voting'}
            : const {},
      ),
      pane: Stack(
        fit: StackFit.expand,
        children: [
          AppPaneScrollScaffold(
            toolbar: toolbar,
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
          ?overlay,
        ],
      ),
    );
  }
}

class _IronwoodMigrationIntroContent extends StatelessWidget {
  const _IronwoodMigrationIntroContent({
    required this.data,
    required this.onOpenReleaseNotes,
  });

  final IronwoodMigrationFlowData data;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = data.amountText;
    final isDark = colors.background.window == AppColors.dark.background.window;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 26,
            width: 420,
            height: 200,
            child: _PoolMigrationHero(data: data),
          ),
          Positioned(
            left: 0,
            top: 257,
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _DarkBadge(label: 'Zcash Network Upgrade'),
                const SizedBox(height: 24),
                SvgPicture.asset(
                  'assets/illustrations/ironwood_wordmark.svg',
                  width: 290,
                  height: 39,
                  colorFilter: ColorFilter.mode(
                    colors.text.accent,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 352,
                  child: Text(
                    'A new shielded pool for Zcash.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 328,
                  child: Text(
                    'Your $amount ZEC is currently in Orchard.\n'
                    'To keep using these funds for shielded payments, '
                    'you will need to move them to Ironwood. You will '
                    'review the migration plan before any funds move.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? colors.text.muted : colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 548,
            width: 230,
            child: _FlowButtons(
              primaryKey: const ValueKey(
                'ironwood_migration_intro_continue_button',
              ),
              primaryLabel: 'Next',
              onPrimary: () => context.go('/migration/how-it-works'),
              secondaryLabel: 'Official Announcement',
              onSecondary: onOpenReleaseNotes,
              secondaryLeading: const AppIcon(AppIcons.link, size: 16),
              secondaryFirst: true,
              spacing: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationHowItWorksContent extends StatefulWidget {
  const _IronwoodMigrationHowItWorksContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  State<_IronwoodMigrationHowItWorksContent> createState() =>
      _IronwoodMigrationHowItWorksContentState();
}

class _IronwoodMigrationHowItWorksContentState
    extends State<_IronwoodMigrationHowItWorksContent> {
  static const _carouselWidth = 700.0;
  static const _carouselHeight = 320.0;
  static const _cardWidth = 396.0;
  static const _cardHeight = 280.0;
  static const _pageExtent = 412.0;
  static const _pageInset = (_pageExtent - _cardWidth) / 2;
  static const _viewportFraction = _pageExtent / _carouselWidth;
  static const _inactiveOpacity = 0.3;

  static const _steps = [
    (
      title: 'Orchard (legacy shielded) balance is frozen',
      body:
          'A one-time migration to Ironwood is required to spend your existing '
          'shielded balance.',
    ),
    (
      title: 'Pre-migration preparations',
      body:
          'Vizor splits your total balance into many smaller notes '
          '(e.g. 0.1 ZEC / 1 ZEC / 5 ZEC) before migrating.',
    ),
    (
      title: 'Delayed and randomized migrations',
      body:
          'Vizor slowly sends parts at staggered intervals across multiple '
          'batches to reduce traceability.',
    ),
  ];

  late final PageController _pageController;
  var _page = 0;
  var _pointerDown = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _steps.length - 1) {
      _animateToPage(_page + 1);
      return;
    }
    context.go('/migration/what-to-expect');
  }

  void _animateToPage(int page) {
    if (page == _page || !_pageController.hasClients) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _setPointerDown(bool pointerDown) {
    if (_pointerDown == pointerDown) return;
    setState(() => _pointerDown = pointerDown);
  }

  double _opacityFor(int index) {
    final position = _pageController.hasClients
        ? _pageController.page ?? _page.toDouble()
        : _page.toDouble();
    return (1 - (position - index).abs() * (1 - _inactiveOpacity))
        .clamp(_inactiveOpacity, 1)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: _carouselWidth,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 152,
            top: 78,
            width: 396,
            child: Text(
              'How the Migration Works',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 144,
            width: _carouselWidth,
            height: _carouselHeight,
            child: MouseRegion(
              key: const ValueKey(
                'ironwood_migration_how_carousel_drag_region',
              ),
              cursor: _pointerDown
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: Listener(
                onPointerDown: (_) => _setPointerDown(true),
                onPointerUp: (_) => _setPointerDown(false),
                onPointerCancel: (_) => _setPointerDown(false),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0xFFFFFFFF),
                      Color(0xFFFFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0, 0.15, 0.85, 1],
                  ).createShader(bounds),
                  child: Align(
                    child: SizedBox(
                      key: const ValueKey(
                        'ironwood_migration_how_carousel_viewport',
                      ),
                      width: _carouselWidth,
                      height: _carouselHeight,
                      child: Align(
                        child: SizedBox(
                          height: _cardHeight,
                          child: ScrollConfiguration(
                            behavior:
                                const _IronwoodMigrationCarouselScrollBehavior(),
                            child: PageView.builder(
                              key: const ValueKey(
                                'ironwood_migration_how_page_view',
                              ),
                              controller: _pageController,
                              itemCount: _steps.length,
                              physics: const PageScrollPhysics(),
                              onPageChanged: (value) =>
                                  setState(() => _page = value),
                              itemBuilder: (context, index) {
                                final step = _steps[index];
                                return AnimatedBuilder(
                                  animation: _pageController,
                                  builder: (context, child) => Opacity(
                                    key: ValueKey(
                                      'ironwood_migration_how_'
                                      'card_opacity_$index',
                                    ),
                                    opacity: _opacityFor(index),
                                    child: child,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: _pageInset,
                                    ),
                                    child: Semantics(
                                      container: true,
                                      button: index != _page,
                                      selected: index == _page,
                                      label: index == _page
                                          ? 'Migration step ${index + 1} of '
                                                '${_steps.length}. '
                                                '${step.title}. ${step.body}'
                                          : 'Show migration step '
                                                '${index + 1} of '
                                                '${_steps.length}',
                                      onTap: index == _page
                                          ? null
                                          : () => _animateToPage(index),
                                      child: ExcludeSemantics(
                                        child: _IronwoodMigrationCarouselAction(
                                          actionKey: ValueKey(
                                            'ironwood_migration_how_'
                                            'card_action_$index',
                                          ),
                                          onActivate: index == _page
                                              ? null
                                              : () => _animateToPage(index),
                                          borderRadius: BorderRadius.circular(
                                            AppRadii.large,
                                          ),
                                          child: MouseRegion(
                                            key: ValueKey(
                                              'ironwood_migration_how_'
                                              'card_cursor_$index',
                                            ),
                                            cursor: _pointerDown
                                                ? MouseCursor.defer
                                                : index == _page
                                                ? MouseCursor.defer
                                                : SystemMouseCursors.click,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: index == _page
                                                  ? null
                                                  : () => _animateToPage(index),
                                              child:
                                                  _IronwoodMigrationHowStepCard(
                                                    key: ValueKey(
                                                      'ironwood_migration_how_'
                                                      'card_$index',
                                                    ),
                                                    index: index,
                                                    title: step.title,
                                                    body: step.body,
                                                  ),
                                            ),
                                          ),
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
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 306,
            top: 482,
            width: 88,
            height: 32,
            child: Row(
              children: [
                for (var index = 0; index < _steps.length; index++) ...[
                  Semantics(
                    button: true,
                    selected: index == _page,
                    label:
                        'Show migration step ${index + 1} of ${_steps.length}',
                    onTap: () => _animateToPage(index),
                    child: _IronwoodMigrationCarouselAction(
                      actionKey: ValueKey(
                        'ironwood_migration_how_indicator_action_$index',
                      ),
                      onActivate: () => _animateToPage(index),
                      borderRadius: BorderRadius.circular(AppRadii.full),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _animateToPage(index),
                          child: AnimatedContainer(
                            key: ValueKey(
                              'ironwood_migration_how_'
                              'indicator_hit_target_$index',
                            ),
                            duration: const Duration(milliseconds: 220),
                            width: index == _page ? 40 : 20,
                            height: 32,
                            child: Center(
                              child: AnimatedContainer(
                                key: ValueKey(
                                  'ironwood_migration_how_indicator_$index',
                                ),
                                duration: const Duration(milliseconds: 220),
                                width: index == _page ? 40 : 20,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: index == _page
                                      ? colors.background.inverse
                                      : colors.background.overlay,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.full,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (index < _steps.length - 1) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
          Positioned(
            left: 235,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey(
                'ironwood_migration_how_it_works_continue_button',
              ),
              onPressed: _next,
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              child: const Text(
                'Next',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationCarouselAction extends StatelessWidget {
  const _IronwoodMigrationCarouselAction({
    required this.actionKey,
    required this.onActivate,
    required this.borderRadius,
    required this.child,
  });

  final Key actionKey;
  final VoidCallback? onActivate;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: onActivate != null,
      onKeyEvent: (_, event) {
        if (onActivate == null || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter &&
            key != LogicalKeyboardKey.space) {
          return KeyEventResult.ignored;
        }
        onActivate!();
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              KeyedSubtree(key: actionKey, child: child),
              if (focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: context.colors.state.focusRing,
                          width: 2,
                        ),
                        borderRadius: borderRadius,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _IronwoodMigrationCarouselScrollBehavior extends ScrollBehavior {
  const _IronwoodMigrationCarouselScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

class _IronwoodMigrationHowStepCard extends StatelessWidget {
  const _IronwoodMigrationHowStepCard({
    required this.index,
    required this.title,
    required this.body,
    super.key,
  });

  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: _IronwoodMigrationHowItWorksContentState._cardWidth,
      height: _IronwoodMigrationHowItWorksContentState._cardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: ColoredBox(
          color: colors.background.ground,
          child: Column(
            children: [
              SizedBox(
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  child: Stack(
                    children: [
                      _IronwoodMigrationHowStepIllustration(index: index),
                      Positioned(
                        left: 19,
                        top: 24,
                        child: Text(
                          'Step ${index + 1}',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 120,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: index == 0 ? 287 : 364,
                          child: Text(
                            body,
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _IronwoodMigrationHowStepIllustration extends StatelessWidget {
  const _IronwoodMigrationHowStepIllustration({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final geometry = switch (index) {
      0 => (
        containerLeft: 226.0,
        containerWidth: 170.0,
        imageLeft: -11.764,
        imageTop: 8.672,
        imageWidth: 199.529,
        imageHeight: 131.728,
      ),
      1 => (
        containerLeft: 226.0,
        containerWidth: 170.0,
        imageLeft: -42.007,
        imageTop: -4.8,
        imageWidth: 254.507,
        imageHeight: 169.664,
      ),
      _ => (
        containerLeft: 174.0,
        containerWidth: 160.0,
        imageLeft: -51.92,
        imageTop: 0.0,
        imageWidth: 264.24,
        imageHeight: 174.0,
      ),
    };

    return Positioned(
      left: geometry.containerLeft,
      top: 0,
      width: geometry.containerWidth,
      height: 160,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: geometry.imageLeft,
              top: geometry.imageTop,
              width: geometry.imageWidth,
              height: geometry.imageHeight,
              child: Image.asset(
                _ironwoodMigrationHowStepAssets[index],
                fit: BoxFit.fill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IronwoodMigrationWhatToExpectContent extends StatelessWidget {
  const _IronwoodMigrationWhatToExpectContent();

  static const _items = [
    (
      title: 'Migrations can take a long time',
      body:
          'Ironwood migrations can take anywhere from several hours up to a '
          'couple days depending on your migration amount.',
    ),
    (
      title: 'You can spend as funds arrive',
      body:
          'Each confirmed Ironwood amount is available to spend while the '
          'rest of the migration continues.',
    ),
    (
      title: 'Use VPN for an extra privacy',
      body:
          'It’s recommended to run the migration behind a trustable '
          'VPN/network privacy layer',
    ),
    (
      title: 'Keep Vizor running',
      body:
          'Your computer needs to be unlocked with Vizor running so we can '
          'send the next migration transaction',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 60,
            width: 396,
            child: Text(
              'What to expect',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 140,
            width: 396,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < _items.length; index++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MigrationExpectationIllustration(
                        index: index,
                        asset: _ironwoodMigrationExpectationAssets[index],
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 320,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _items[index].title,
                              style: AppTypography.bodyMediumStrong.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _items[index].body,
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (index < _items.length - 1) const SizedBox(height: 24),
                ],
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey(
                'ironwood_migration_what_to_expect_continue_button',
              ),
              onPressed: () => context.go('/migration/options'),
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              child: const Text('Next'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationExpectationIllustration extends StatelessWidget {
  const _MigrationExpectationIllustration({
    required this.index,
    required this.asset,
  });

  final int index;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final background = switch (index) {
      0 => const Color(0xFF9667E2),
      1 => const Color(0xFFDBB013),
      2 => const Color(0xFF00A460),
      _ => const Color(0xFFB90A4A),
    };
    final viewportTop = switch (index) {
      1 || 2 => -6.0,
      _ => 0.0,
    };
    final viewportHeight = index == 3 ? 48.0 : 54.0;
    final imageRect = switch (index) {
      0 => const Rect.fromLTWH(-27.12, -8.70, 102.39, 68.70),
      1 => const Rect.fromLTWH(-9.75, -5.43, 69.19, 69.13),
      2 => const Rect.fromLTWH(-18.11, -6.50, 84, 84),
      _ => const Rect.fromLTWH(0, 0, 48, 48),
    };
    final image = Stack(
      children: [
        Positioned.fromRect(
          rect: imageRect,
          child: Image.asset(asset, fit: BoxFit.fill),
        ),
      ],
    );
    final clippedImage = index == 0
        ? ClipRect(child: image)
        : ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: image,
          );

    return SizedBox.square(
      key: ValueKey('ironwood_migration_expectation_tile_$index'),
      dimension: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: viewportTop,
            width: 48,
            height: viewportHeight,
            child: SizedBox(
              key: ValueKey('ironwood_migration_expectation_viewport_$index'),
              child: clippedImage,
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationOptionsContent extends StatefulWidget {
  const _IronwoodMigrationOptionsContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  State<_IronwoodMigrationOptionsContent> createState() =>
      _IronwoodMigrationOptionsContentState();
}

class _IronwoodMigrationOptionsContentState
    extends State<_IronwoodMigrationOptionsContent> {
  var _selected = _MigrationMode.private;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = _selected;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 49,
            top: 68,
            width: 322,
            child: Column(
              children: [
                Text(
                  'Choose how to migrate',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 322,
                  child: Text(
                    'Choose a private preset, migrate immediately, or '
                    'customize how your balance blends in. You can review '
                    'the details before anything moves.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 193,
            width: 396,
            child: Column(
              children: [
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_private_option'),
                  mode: _MigrationMode.private,
                  selected: selected == _MigrationMode.private,
                  title: 'Private',
                  badge: 'Recommended',
                  body:
                      'Splits transactions into multiple parts to minimize '
                      'traceability, but will take longer.',
                  onTap: () =>
                      setState(() => _selected = _MigrationMode.private),
                ),
                const SizedBox(height: 12),
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_fast_option'),
                  mode: _MigrationMode.fast,
                  selected: selected == _MigrationMode.fast,
                  title: 'Immediate',
                  body:
                      'Migrates your entire balance in one batch. Fast but '
                      'less private.',
                  onTap: () => setState(() => _selected = _MigrationMode.fast),
                ),
                const SizedBox(height: 12),
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_custom_option'),
                  mode: _MigrationMode.custom,
                  selected: selected == _MigrationMode.custom,
                  title: 'Custom',
                  body:
                      'Shape the balance like many smaller wallets and '
                      'control how many migration schedules overlap.',
                  onTap: () =>
                      setState(() => _selected = _MigrationMode.custom),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey('ironwood_migration_select_review_button'),
              onPressed: () {
                context.go(switch (_selected) {
                  _MigrationMode.private => '/migration/private/review',
                  _MigrationMode.custom => '/migration/custom',
                  _MigrationMode.fast => '/migration/immediate/review',
                });
              },
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text('Select & review'),
            ),
          ),
        ],
      ),
    );
  }
}
