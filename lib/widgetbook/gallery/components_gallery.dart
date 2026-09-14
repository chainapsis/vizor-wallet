// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/core/theme/app_theme.dart';
import '../../src/core/widgets/app_button.dart';
import '../../src/core/widgets/app_icon.dart';
import '../../src/core/widgets/app_modal_card.dart';
import '../../src/core/widgets/app_profile_picture.dart';
import '../../src/core/widgets/app_text_field.dart';
import '../../src/core/widgets/app_toast.dart';
import '../../src/core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../../src/providers/network_privacy_provider.dart';
import '../../src/providers/sync_keep_awake_provider.dart';
import '../button_use_cases.dart';
import '../carousel_use_cases.dart';
import '../chip_use_cases.dart';
import '../color_use_cases.dart';
import '../context_menu_use_cases.dart';
import '../core_use_cases.dart';
import '../icon_use_cases.dart';
import '../mobile_shell_use_cases.dart';
import '../review_components_use_cases.dart';
import '../support/wb_design_status.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';
import '../text_field_use_cases.dart';
import '../toast_use_cases.dart';
import '../token_use_cases.dart';
import '../typography_use_cases.dart';

/// The shared-component, token and colour galleries: one knob-driven use case
/// per component, each dispatching to the fixtures the tests and
/// figma_compare bind to.
///
/// Component previews sit on the plain grounds their own fixtures paint — no
/// pane or phone frame — and no case carries a Layout knob, because none of
/// these components has a separate desktop and mobile widget class. The
/// mobile-shell kit is mobile-only: run the mobile lane for true metrics.
final List<WidgetbookNode> componentsGalleryNodes = [
  WidgetbookComponent(
    name: 'Button',
    useCases: [
      WidgetbookUseCase(name: 'Playground', builder: buildComponentsButtonCase),
      // The component sheet is its own surface: every cell at once, which no
      // combination of the playground's knobs can show.
      WidgetbookUseCase(name: 'Matrix', builder: buildButtonMatrixUseCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Carousel',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsCarouselCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Chip',
    useCases: [WidgetbookUseCase(name: 'All', builder: buildChipUseCase)],
  ),
  WidgetbookComponent(
    name: 'Context menu',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsContextMenuCase,
      ),
      // Its own surface: the edge self-correction only appears when the menu
      // is pinned near a pane edge, which no menu-content knob can produce.
      WidgetbookUseCase(
        name: 'Anchor positions',
        builder: buildComponentsContextMenuAnchorCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Decorative divider',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsDecorativeDividerCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Linux keyring',
    useCases: [
      WidgetbookUseCase(
        name: 'Gate',
        builder: buildComponentsLinuxKeyringGateCase,
      ),
      WidgetbookUseCase(
        name: 'Startup',
        builder: buildComponentsLinuxKeyringStartupCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Loading icon',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsLoadingIconCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Main sidebar',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsMainSidebarCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile modal',
    useCases: [
      WidgetbookUseCase(
        name: 'Scaffold',
        builder: buildComponentsMobileModalScaffoldCase,
      ),
      WidgetbookUseCase(
        name: 'Card',
        builder: buildComponentsMobileModalCardCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile sheets',
    useCases: [
      WidgetbookUseCase(
        name: 'Tx fee info',
        builder: buildComponentsTxFeeInfoSheetCase,
      ),
      WidgetbookUseCase(
        name: 'Unsupported',
        builder: buildComponentsUnsupportedSheetCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile shell',
    useCases: [
      WidgetbookUseCase(
        name: 'Top nav',
        builder: buildMobileTopNavVariantsUseCase,
      ),
      WidgetbookUseCase(
        name: 'Top nav playground',
        builder: buildComponentsMobileTopNavCase,
      ),
      WidgetbookUseCase(
        name: 'Top nav account',
        builder: buildComponentsMobileTopNavAccountCase,
      ),
      WidgetbookUseCase(name: 'Tab bar', builder: buildMobileTabBarUseCase),
      WidgetbookUseCase(name: 'Shell', builder: buildMobileShellUseCase),
      WidgetbookUseCase(
        name: 'Surface card and rows',
        builder: buildMobileSurfaceCardUseCase,
      ),
      WidgetbookUseCase(name: 'Sheet', builder: buildMobileSheetUseCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Modal card',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsModalCardCase,
      ),
      WidgetbookUseCase(
        name: 'Actions',
        builder: buildComponentsModalActionsCase,
      ),
      WidgetbookUseCase(
        name: 'Pane overlay',
        builder: buildComponentsPaneModalOverlayCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Pane scroll scaffold',
    useCases: [
      WidgetbookUseCase(
        name: 'Slivers',
        builder: buildComponentsPaneScrollScaffoldCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Profile picture',
    useCases: [
      WidgetbookUseCase(
        name: 'Picker modal',
        builder: buildComponentsProfilePicturePickerCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Review components',
    useCases: [
      WidgetbookUseCase(
        name: 'Info rows',
        builder: buildReviewInfoRowGalleryUseCase,
      ),
      WidgetbookUseCase(
        name: 'Wrap card',
        builder: buildComponentsReviewWrapCardCase,
      ),
      WidgetbookUseCase(
        name: 'List rows',
        builder: buildReviewListRowGalleryUseCase,
      ),
      WidgetbookUseCase(
        name: 'Buttons stack',
        builder: buildReviewButtonsStackUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Sync keep-awake',
    useCases: [
      WidgetbookUseCase(
        name: 'Lock screen',
        builder: buildComponentsSyncKeepAwakeLockCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Text field',
    useCases: [
      WidgetbookUseCase(name: 'Gallery', builder: buildTextFieldGalleryUseCase),
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsTextFieldCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Toast',
    useCases: [
      WidgetbookUseCase(name: 'All', builder: buildToastUseCase),
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsToastPlaygroundCase,
      ),
      WidgetbookUseCase(name: 'Host', builder: buildComponentsToastHostCase),
      WidgetbookUseCase(
        name: 'Network fallback',
        builder: buildComponentsNetworkFallbackToastCase,
      ),
      WidgetbookUseCase(
        name: 'Network fallback host',
        builder: buildComponentsNetworkFallbackHostCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Tooltip',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildComponentsTooltipCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Transaction progress',
    useCases: [
      WidgetbookUseCase(
        name: 'Mobile screen',
        builder: buildComponentsTransactionProgressCase,
      ),
      WidgetbookUseCase(
        name: 'Badge',
        builder: buildComponentsTransactionProgressBadgeCase,
      ),
    ],
  ),
];

/// Design status of the token reference galleries: code-only by construction.
final String _tokensGalleryDesignLink = wbNoFigma(
  note: 'Code-only: token reference table generated from the token classes.',
);

/// Reference tables built from the token classes: Figma holds the variable
/// collections, never a frame of these galleries.
final List<WidgetbookNode> tokensGalleryNodes = [
  WidgetbookComponent(
    name: 'Typography',
    useCases: [
      WidgetbookUseCase(
        name: 'All',
        designLink: _tokensGalleryDesignLink,
        builder: buildTypographyAllUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Spacing',
    useCases: [
      WidgetbookUseCase(
        name: 'All',
        designLink: _tokensGalleryDesignLink,
        builder: buildSpacingUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Icons',
    useCases: [
      WidgetbookUseCase(
        name: 'All',
        designLink: _tokensGalleryDesignLink,
        builder: buildIconsAllUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Icon size',
    useCases: [
      WidgetbookUseCase(
        name: 'All',
        designLink: _tokensGalleryDesignLink,
        builder: buildIconSizeUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Radii',
    useCases: [
      WidgetbookUseCase(
        name: 'All',
        designLink: _tokensGalleryDesignLink,
        builder: buildRadiiUseCase,
      ),
    ],
  ),
];

/// The colour sheets: three tables, each with a knob picking the group.
///
/// Left unmarked rather than `wbNoFigma`: `color_use_cases.dart` states each
/// page mirrors a Figma colour sheet, so the frames exist — only their URLs
/// are unknown until the Figma linking pass.
final List<WidgetbookNode> colorsGalleryNodes = [
  WidgetbookComponent(
    name: 'Primitives',
    useCases: [
      WidgetbookUseCase(name: 'Playground', builder: buildColorsPrimitivesCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Semantic',
    useCases: [
      WidgetbookUseCase(name: 'Playground', builder: buildColorsSemanticCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Button',
    useCases: [
      WidgetbookUseCase(name: 'Playground', builder: buildColorsButtonCase),
    ],
  ),
];

// --- Button ----------------------------------------------------------------

/// Interaction state the fixture can force; hover / pressed / focus are live
/// widget states, so they stay out of the knob.
enum ComponentsButtonState { enabled, disabled }

Widget buildComponentsButtonCase(BuildContext context) {
  final variant = wbStateKnob<AppButtonVariant>(
    context,
    label: 'Variant',
    options: AppButtonVariant.values,
    labelBuilder: componentsButtonVariantLabel,
  );
  final size = wbStateKnob<AppButtonSize>(
    context,
    label: 'Size',
    options: AppButtonSize.values,
    labelBuilder: componentsButtonSizeLabel,
  );
  final state = wbStateKnob<ComponentsButtonState>(
    context,
    label: 'State',
    options: ComponentsButtonState.values,
    labelBuilder: componentsButtonStateLabel,
  );
  final leading = wbBoolKnob(context, label: 'Leading icon', initial: true);
  final trailing = wbBoolKnob(context, label: 'Trailing icon', initial: true);
  // Empty keeps `buttonSingleFixture`'s per-size default, so the singles that
  // share this fixture still render their own label.
  final label = context.knobs.string(label: 'Label', initialValue: '');

  return buttonSingleFixture(
    context,
    variant: variant,
    size: size,
    enabled: state == ComponentsButtonState.enabled,
    leadingIcon: leading,
    trailingIcon: trailing,
    label: label.isEmpty ? null : label,
  );
}

String componentsButtonVariantLabel(AppButtonVariant variant) {
  return switch (variant) {
    AppButtonVariant.primary => 'Primary',
    AppButtonVariant.secondary => 'Secondary',
    AppButtonVariant.ghost => 'Ghost',
    AppButtonVariant.destructive => 'Destructive',
  };
}

String componentsButtonSizeLabel(AppButtonSize size) {
  return switch (size) {
    AppButtonSize.large => 'Large',
    AppButtonSize.mediumLarge => 'Medium large',
    AppButtonSize.medium => 'Medium',
    AppButtonSize.small => 'Small',
  };
}

String componentsButtonStateLabel(ComponentsButtonState state) {
  return switch (state) {
    ComponentsButtonState.enabled => 'Default',
    ComponentsButtonState.disabled => 'Disabled',
  };
}

// --- Carousel --------------------------------------------------------------

/// Which card deck the carousel is showing.
enum ComponentsCarouselDeck { preparation, migration }

/// Which card is on screen; 'Autoplay' is the only fixture that advances on
/// its own, and it always starts on card 1.
enum ComponentsCarouselCard { autoplay, one, two, three }

Widget buildComponentsCarouselCase(BuildContext context) {
  final deck = wbStateKnob<ComponentsCarouselDeck>(
    context,
    label: 'Deck',
    options: ComponentsCarouselDeck.values,
    labelBuilder: componentsCarouselDeckLabel,
  );
  final card = wbStateKnob<ComponentsCarouselCard>(
    context,
    label: 'Card',
    options: ComponentsCarouselCard.values,
    labelBuilder: componentsCarouselCardLabel,
  );

  // `AppCarousel` asserts the desktop form factor, so the mobile lane gets the
  // run command instead of an assertion failure.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: _componentsCarousel(context, deck: deck, card: card),
  );
}

Widget _componentsCarousel(
  BuildContext context, {
  required ComponentsCarouselDeck deck,
  required ComponentsCarouselCard card,
}) {
  if (deck == ComponentsCarouselDeck.preparation) {
    return switch (card) {
      ComponentsCarouselCard.autoplay =>
        buildCarouselPreparationInteractiveUseCase(context),
      ComponentsCarouselCard.one => buildCarouselPreparationCardOneUseCase(
        context,
      ),
      ComponentsCarouselCard.two => buildCarouselPreparationCardTwoUseCase(
        context,
      ),
      ComponentsCarouselCard.three => buildCarouselPreparationCardThreeUseCase(
        context,
      ),
    };
  }
  return switch (card) {
    ComponentsCarouselCard.autoplay => buildCarouselMigrationInteractiveUseCase(
      context,
    ),
    ComponentsCarouselCard.one => buildCarouselMigrationCardOneUseCase(context),
    ComponentsCarouselCard.two => buildCarouselMigrationCardTwoUseCase(context),
    ComponentsCarouselCard.three => buildCarouselMigrationCardThreeUseCase(
      context,
    ),
  };
}

String componentsCarouselDeckLabel(ComponentsCarouselDeck deck) {
  return switch (deck) {
    ComponentsCarouselDeck.preparation => 'Preparation',
    ComponentsCarouselDeck.migration => 'Migration',
  };
}

String componentsCarouselCardLabel(ComponentsCarouselCard card) {
  return switch (card) {
    ComponentsCarouselCard.autoplay => 'Autoplay',
    ComponentsCarouselCard.one => 'Card 1',
    ComponentsCarouselCard.two => 'Card 2',
    ComponentsCarouselCard.three => 'Card 3',
  };
}

// --- Context menu ----------------------------------------------------------

/// Which menu the fixture shows; 'All three' is the side-by-side sheet.
enum ComponentsContextMenu { all, contact, account, narrow }

Widget buildComponentsContextMenuCase(BuildContext context) {
  final menu = wbStateKnob<ComponentsContextMenu>(
    context,
    label: 'Menu',
    options: ComponentsContextMenu.values,
    labelBuilder: componentsContextMenuLabel,
  );
  return switch (menu) {
    ComponentsContextMenu.all => buildContextMenuGalleryUseCase(context),
    ComponentsContextMenu.contact => buildContextMenuContactUseCase(context),
    ComponentsContextMenu.account => buildContextMenuAccountUseCase(context),
    ComponentsContextMenu.narrow => buildContextMenuNarrowUseCase(context),
  };
}

String componentsContextMenuLabel(ComponentsContextMenu menu) {
  return switch (menu) {
    ComponentsContextMenu.all => 'All three',
    ComponentsContextMenu.contact => 'Contact actions',
    ComponentsContextMenu.account => 'Account actions',
    ComponentsContextMenu.narrow => 'Narrow width',
  };
}

/// Menu width; the narrow option is the one the account rows use.
enum ComponentsContextMenuWidth { standard, narrow }

Widget buildComponentsContextMenuAnchorCase(BuildContext context) {
  final anchor = wbStateKnob<ContextMenuAnchor>(
    context,
    label: 'Anchor',
    options: ContextMenuAnchor.values,
    labelBuilder: componentsContextMenuAnchorLabel,
  );
  final width = wbStateKnob<ComponentsContextMenuWidth>(
    context,
    label: 'Width',
    options: ComponentsContextMenuWidth.values,
    labelBuilder: componentsContextMenuWidthLabel,
  );

  return contextMenuAnchorFixture(
    context,
    anchor: anchor,
    width: width == ComponentsContextMenuWidth.narrow
        ? kContextMenuNarrowWidth
        : 160,
  );
}

String componentsContextMenuAnchorLabel(ContextMenuAnchor anchor) {
  return switch (anchor) {
    ContextMenuAnchor.topLeft => 'Top left',
    ContextMenuAnchor.topRight => 'Top right (shifts in)',
    ContextMenuAnchor.bottomLeft => 'Bottom left (flips up)',
    ContextMenuAnchor.bottomRight => 'Bottom right (flips and shifts)',
    ContextMenuAnchor.tallClamped => 'Tall menu (clamps to the edge)',
  };
}

String componentsContextMenuWidthLabel(ComponentsContextMenuWidth width) {
  return switch (width) {
    ComponentsContextMenuWidth.standard => 'Default (160)',
    ComponentsContextMenuWidth.narrow => 'Narrow (128)',
  };
}

// --- Modal card -------------------------------------------------------------

/// Card width; the wide option is what the asset pickers ask for.
enum ComponentsModalCardWidth { standard, wide }

/// Bottom inset below the card body.
enum ComponentsModalCardPadding { standard, flush }

/// The shared desktop modal card. Hover and focus live on the buttons inside
/// it, so this case knobs only the card's own props.
Widget buildComponentsModalCardCase(BuildContext context) {
  final highlight = wbBoolKnob(context, label: 'Highlight');
  final width = wbStateKnob<ComponentsModalCardWidth>(
    context,
    label: 'Width',
    options: ComponentsModalCardWidth.values,
    labelBuilder: componentsModalCardWidthLabel,
  );
  final body = wbStateKnob<CoreModalCardBody>(
    context,
    label: 'Body',
    options: CoreModalCardBody.values,
    labelBuilder: componentsModalCardBodyLabel,
  );
  final padding = wbStateKnob<ComponentsModalCardPadding>(
    context,
    label: 'Bottom padding',
    options: ComponentsModalCardPadding.values,
    labelBuilder: componentsModalCardPaddingLabel,
  );

  return appModalCardFixture(
    context,
    highlight: highlight,
    width: width == ComponentsModalCardWidth.wide
        ? kCoreModalCardWideWidth
        : kAppModalCardWidth,
    body: body,
    bottomPadding: padding == ComponentsModalCardPadding.flush
        ? 0
        : AppSpacing.md,
  );
}

/// Variants the action button is actually shown in.
const List<AppButtonVariant> componentsModalActionVariants = [
  AppButtonVariant.primary,
  AppButtonVariant.destructive,
];

Widget buildComponentsModalActionsCase(BuildContext context) {
  final variant = wbStateKnob<AppButtonVariant>(
    context,
    label: 'Action variant',
    options: componentsModalActionVariants,
    labelBuilder: componentsButtonVariantLabel,
  );
  final actionEnabled = wbBoolKnob(
    context,
    label: 'Action enabled',
    initial: true,
  );
  final cancelEnabled = wbBoolKnob(
    context,
    label: 'Cancel enabled',
    initial: true,
  );
  final leadingIcon = wbBoolKnob(context, label: 'Action leading icon');

  return appModalActionsFixture(
    context,
    actionVariant: variant,
    actionEnabled: actionEnabled,
    cancelEnabled: cancelEnabled,
    actionLeadingIcon: leadingIcon,
  );
}

Widget buildComponentsPaneModalOverlayCase(BuildContext context) {
  final alignment = wbStateKnob<CorePaneModalAlignment>(
    context,
    label: 'Alignment',
    options: CorePaneModalAlignment.values,
    labelBuilder: componentsPaneModalAlignmentLabel,
  );
  final customScrim = wbBoolKnob(context, label: 'Custom scrim');
  final largeRadius = wbBoolKnob(context, label: 'Large corner radius');

  return appPaneModalOverlayFixture(
    context,
    alignment: alignment,
    customScrim: customScrim,
    largeRadius: largeRadius,
  );
}

String componentsModalCardWidthLabel(ComponentsModalCardWidth width) {
  return switch (width) {
    ComponentsModalCardWidth.standard => 'Default (312)',
    ComponentsModalCardWidth.wide => 'Wide (420)',
  };
}

String componentsModalCardBodyLabel(CoreModalCardBody body) {
  return switch (body) {
    CoreModalCardBody.short => 'Short',
    CoreModalCardBody.scrolling => 'Scrolling',
  };
}

String componentsModalCardPaddingLabel(ComponentsModalCardPadding padding) {
  return switch (padding) {
    ComponentsModalCardPadding.standard => 'Default (24)',
    ComponentsModalCardPadding.flush => 'Flush (0)',
  };
}

String componentsPaneModalAlignmentLabel(CorePaneModalAlignment alignment) {
  return switch (alignment) {
    CorePaneModalAlignment.center => 'Center',
    CorePaneModalAlignment.top => 'Top',
    CorePaneModalAlignment.bottom => 'Bottom',
  };
}

// --- Profile picture picker -------------------------------------------------

/// Which picture the account already has.
enum ComponentsProfilePicture { current, alternate }

/// Option-avatar sizes the picker is used at.
const List<AppProfilePictureSize> componentsProfilePickerSizes = [
  AppProfilePictureSize.navLarge,
  AppProfilePictureSize.large,
];

/// The shared picker modal. 'Updating…', the inline error and the disabled
/// grid are private `State`: pick a different avatar and press Update to
/// reach them — this knob only decides how that update resolves. The hover
/// and focus rings are live interaction states.
Widget buildComponentsProfilePicturePickerCase(BuildContext context) {
  final outcome = wbStateKnob<CoreProfilePickerOutcome>(
    context,
    label: 'Update outcome',
    options: CoreProfilePickerOutcome.values,
    labelBuilder: componentsProfilePickerOutcomeLabel,
  );
  final current = wbStateKnob<ComponentsProfilePicture>(
    context,
    label: 'Current picture',
    options: ComponentsProfilePicture.values,
    labelBuilder: componentsProfilePictureLabel,
  );
  final size = wbStateKnob<AppProfilePictureSize>(
    context,
    label: 'Option size',
    options: componentsProfilePickerSizes,
    labelBuilder: componentsProfilePickerSizeLabel,
  );

  return appProfilePicturePickerFixture(
    context,
    outcome: outcome,
    alternateCurrentPicture: current == ComponentsProfilePicture.alternate,
    optionSize: size,
  );
}

String componentsProfilePickerOutcomeLabel(CoreProfilePickerOutcome outcome) {
  return switch (outcome) {
    CoreProfilePickerOutcome.succeeds => 'Succeeds',
    CoreProfilePickerOutcome.inFlight => 'Stays in flight',
    CoreProfilePickerOutcome.fails => 'Fails',
  };
}

String componentsProfilePictureLabel(ComponentsProfilePicture picture) {
  return switch (picture) {
    ComponentsProfilePicture.current => 'Default (Knight)',
    ComponentsProfilePicture.alternate => 'Alternate (Seer)',
  };
}

String componentsProfilePickerSizeLabel(AppProfilePictureSize size) {
  return switch (size) {
    AppProfilePictureSize.navLarge => 'Nav large (40)',
    AppProfilePictureSize.large => 'Large (32)',
    AppProfilePictureSize.medium => 'Medium (24)',
    AppProfilePictureSize.xLarge => 'X large (56)',
    AppProfilePictureSize.xxLarge => 'XX large (72)',
  };
}

// --- Mobile modal -----------------------------------------------------------

/// Software-keyboard state the card's bottom gap reacts to.
enum ComponentsKeyboard { closed, open }

/// The two mobile platforms; only Android adds its navigation-bar inset on
/// top of the card's own bottom gap.
enum ComponentsMobilePlatform { ios, android }

/// The shared mobile modal header + padding. Hovering the close button is a
/// live state, so it is not a knob.
Widget buildComponentsMobileModalScaffoldCase(BuildContext context) {
  final title = wbStateKnob<CoreMobileModalTitle>(
    context,
    label: 'Title',
    options: CoreMobileModalTitle.values,
    labelBuilder: componentsMobileModalTitleLabel,
  );
  final showClose = wbBoolKnob(context, label: 'Close button', initial: true);
  final leading = wbStateKnob<CoreMobileModalLeading>(
    context,
    label: 'Leading',
    options: CoreMobileModalLeading.values,
    labelBuilder: componentsMobileModalLeadingLabel,
  );
  final body = wbStateKnob<CoreMobileModalBody>(
    context,
    label: 'Body',
    options: CoreMobileModalBody.values,
    labelBuilder: componentsMobileModalBodyLabel,
  );

  return mobileModalScaffoldFixture(
    context,
    title: title,
    showClose: showClose,
    leading: leading,
    body: body,
  );
}

Widget buildComponentsMobileModalCardCase(BuildContext context) {
  final transparent = wbBoolKnob(context, label: 'Transparent background');
  final keyboard = wbStateKnob<ComponentsKeyboard>(
    context,
    label: 'Keyboard',
    options: ComponentsKeyboard.values,
    labelBuilder: componentsKeyboardLabel,
  );
  final platform = wbStateKnob<ComponentsMobilePlatform>(
    context,
    label: 'Platform',
    options: ComponentsMobilePlatform.values,
    labelBuilder: componentsMobilePlatformLabel,
  );
  final background = wbStateKnob<CoreMobileModalBackground>(
    context,
    label: 'Background',
    options: CoreMobileModalBackground.values,
    labelBuilder: componentsMobileModalBackgroundLabel,
  );

  return mobileModalCardFixture(
    context,
    transparentBackground: transparent,
    keyboardOpen: keyboard == ComponentsKeyboard.open,
    platform: platform == ComponentsMobilePlatform.android
        ? TargetPlatform.android
        : TargetPlatform.iOS,
    background: background,
  );
}

String componentsMobileModalTitleLabel(CoreMobileModalTitle title) {
  return switch (title) {
    CoreMobileModalTitle.shown => 'Shown',
    CoreMobileModalTitle.hidden => 'Hidden',
    CoreMobileModalTitle.longWrapping => 'Long (wraps to two lines)',
  };
}

String componentsMobileModalLeadingLabel(CoreMobileModalLeading leading) {
  return switch (leading) {
    CoreMobileModalLeading.none => 'None',
    CoreMobileModalLeading.icon => 'Icon',
    CoreMobileModalLeading.avatar => 'Avatar',
  };
}

String componentsMobileModalBodyLabel(CoreMobileModalBody body) {
  return switch (body) {
    CoreMobileModalBody.short => 'Short',
    CoreMobileModalBody.long => 'Long (scrolls)',
  };
}

String componentsKeyboardLabel(ComponentsKeyboard keyboard) {
  return switch (keyboard) {
    ComponentsKeyboard.closed => 'Closed',
    ComponentsKeyboard.open => 'Open (300)',
  };
}

String componentsMobilePlatformLabel(ComponentsMobilePlatform platform) {
  return switch (platform) {
    ComponentsMobilePlatform.ios => 'iOS',
    ComponentsMobilePlatform.android => 'Android',
  };
}

String componentsMobileModalBackgroundLabel(CoreMobileModalBackground value) {
  return switch (value) {
    CoreMobileModalBackground.screen => 'Screen',
    CoreMobileModalBackground.blank => 'Blank ground',
  };
}

// --- Decorative divider -----------------------------------------------------

Widget buildComponentsDecorativeDividerCase(BuildContext context) {
  final width = wbStateKnob<CoreDividerWidth>(
    context,
    label: 'Width',
    options: CoreDividerWidth.values,
    labelBuilder: componentsDividerWidthLabel,
  );
  return decorativeDividerFixture(context, width: width);
}

String componentsDividerWidthLabel(CoreDividerWidth width) {
  return switch (width) {
    CoreDividerWidth.calendar => 'Calendar (256)',
    CoreDividerWidth.wide => 'Wide (420)',
  };
}

// --- Pane scroll scaffold ---------------------------------------------------

Widget buildComponentsPaneScrollScaffoldCase(BuildContext context) {
  final content = wbStateKnob<CorePaneScaffoldContent>(
    context,
    label: 'Content',
    options: CorePaneScaffoldContent.values,
    labelBuilder: componentsPaneScaffoldContentLabel,
  );
  return paneSliverScrollScaffoldFixture(context, content: content);
}

String componentsPaneScaffoldContentLabel(CorePaneScaffoldContent content) {
  return switch (content) {
    CorePaneScaffoldContent.fits => 'Fits the pane',
    CorePaneScaffoldContent.scrolls => 'Scrolls',
  };
}

// --- Loading icon ----------------------------------------------------------

/// Whether the loader spins; 'Static' is what reduced motion renders.
enum ComponentsLoadingIconMotion { animated, still }

Widget buildComponentsLoadingIconCase(BuildContext context) {
  final motion = wbStateKnob<ComponentsLoadingIconMotion>(
    context,
    label: 'Motion',
    options: ComponentsLoadingIconMotion.values,
    labelBuilder: componentsLoadingIconMotionLabel,
  );
  return switch (motion) {
    ComponentsLoadingIconMotion.animated => buildLoadingIconAnimatedUseCase(
      context,
    ),
    ComponentsLoadingIconMotion.still => buildLoadingIconStaticUseCase(context),
  };
}

String componentsLoadingIconMotionLabel(ComponentsLoadingIconMotion motion) {
  return switch (motion) {
    ComponentsLoadingIconMotion.animated => 'Animated',
    ComponentsLoadingIconMotion.still => 'Static',
  };
}

// --- Review components -----------------------------------------------------

/// Wrap-card status; 'Failed' is pinned to the dark surface in both themes.
enum ComponentsReviewWrapCardOutcome { completed, failed }

Widget buildComponentsReviewWrapCardCase(BuildContext context) {
  final outcome = wbStateKnob<ComponentsReviewWrapCardOutcome>(
    context,
    label: 'Outcome',
    options: ComponentsReviewWrapCardOutcome.values,
    labelBuilder: componentsReviewWrapCardOutcomeLabel,
  );
  return switch (outcome) {
    ComponentsReviewWrapCardOutcome.completed =>
      buildReviewWrapCardCompletedUseCase(context),
    ComponentsReviewWrapCardOutcome.failed => buildReviewWrapCardFailedUseCase(
      context,
    ),
  };
}

String componentsReviewWrapCardOutcomeLabel(
  ComponentsReviewWrapCardOutcome outcome,
) {
  return switch (outcome) {
    ComponentsReviewWrapCardOutcome.completed => 'Completed',
    ComponentsReviewWrapCardOutcome.failed => 'Failed (fixed dark)',
  };
}

// --- Text field ------------------------------------------------------------

/// Tones the fixture covers; `AppTextFieldTone.success` has no fixture yet.
const List<AppTextFieldTone> componentsTextFieldTones = [
  AppTextFieldTone.neutral,
  AppTextFieldTone.brandCrimson,
  AppTextFieldTone.destructive,
];

Widget buildComponentsTextFieldCase(BuildContext context) {
  final tone = wbStateKnob<AppTextFieldTone>(
    context,
    label: 'Tone',
    options: componentsTextFieldTones,
    labelBuilder: componentsTextFieldToneLabel,
  );
  final multiline = wbBoolKnob(context, label: 'Text area');
  final showLeading = wbBoolKnob(context, label: 'Leading icon', initial: true);
  final showClearButton = wbBoolKnob(
    context,
    label: 'Clear button',
    initial: true,
  );
  // Free text rather than an enum: the message is arbitrary product copy, and
  // an empty string is the no-message state.
  final messageText = context.knobs.string(
    label: 'Message text',
    initialValue: '',
  );

  return textFieldPlaygroundFixture(
    context,
    multiline: multiline,
    tone: tone,
    showLeading: showLeading,
    showClearButton: showClearButton,
    messageText: messageText,
  );
}

String componentsTextFieldToneLabel(AppTextFieldTone tone) {
  return switch (tone) {
    AppTextFieldTone.neutral => 'Neutral',
    AppTextFieldTone.brandCrimson => 'Brand crimson',
    AppTextFieldTone.destructive => 'Destructive',
    AppTextFieldTone.success => 'Success',
  };
}

// --- Colors ----------------------------------------------------------------

/// The five primitive colour ramps.
enum ColorsPrimitiveRamp { neutral, crimson, plum, gold, green }

Widget buildColorsPrimitivesCase(BuildContext context) {
  final ramp = wbStateKnob<ColorsPrimitiveRamp>(
    context,
    label: 'Ramp',
    options: ColorsPrimitiveRamp.values,
    labelBuilder: colorsPrimitiveRampLabel,
  );
  return switch (ramp) {
    ColorsPrimitiveRamp.neutral => buildPrimitivesNeutralUseCase(context),
    ColorsPrimitiveRamp.crimson => buildPrimitivesCrimsonUseCase(context),
    ColorsPrimitiveRamp.plum => buildPrimitivesPlumUseCase(context),
    ColorsPrimitiveRamp.gold => buildPrimitivesGoldUseCase(context),
    ColorsPrimitiveRamp.green => buildPrimitivesGreenUseCase(context),
  };
}

String colorsPrimitiveRampLabel(ColorsPrimitiveRamp ramp) {
  return switch (ramp) {
    ColorsPrimitiveRamp.neutral => 'Neutral',
    ColorsPrimitiveRamp.crimson => 'Crimson',
    ColorsPrimitiveRamp.plum => 'Plum',
    ColorsPrimitiveRamp.gold => 'Gold',
    ColorsPrimitiveRamp.green => 'Green',
  };
}

/// The semantic colour sheets, one page each.
enum ColorsSemanticGroup {
  background,
  surface,
  border,
  text,
  icon,
  state,
  fade,
}

Widget buildColorsSemanticCase(BuildContext context) {
  final group = wbStateKnob<ColorsSemanticGroup>(
    context,
    label: 'Group',
    options: ColorsSemanticGroup.values,
    labelBuilder: colorsSemanticGroupLabel,
  );
  return switch (group) {
    ColorsSemanticGroup.background => buildBackgroundUseCase(context),
    ColorsSemanticGroup.surface => buildSurfaceUseCase(context),
    ColorsSemanticGroup.border => buildBorderUseCase(context),
    ColorsSemanticGroup.text => buildTextUseCase(context),
    ColorsSemanticGroup.icon => buildIconUseCase(context),
    ColorsSemanticGroup.state => buildStateUseCase(context),
    ColorsSemanticGroup.fade => buildFadeUseCase(context),
  };
}

String colorsSemanticGroupLabel(ColorsSemanticGroup group) {
  return switch (group) {
    ColorsSemanticGroup.background => 'Background',
    ColorsSemanticGroup.surface => 'Surface',
    ColorsSemanticGroup.border => 'Border',
    ColorsSemanticGroup.text => 'Text',
    ColorsSemanticGroup.icon => 'Icon',
    ColorsSemanticGroup.state => 'State',
    ColorsSemanticGroup.fade => 'Fade',
  };
}

/// Button colour sheets; ghost and destructive share one page.
enum ColorsButtonSheet { primary, secondary, ghostAndDestructive }

Widget buildColorsButtonCase(BuildContext context) {
  final sheet = wbStateKnob<ColorsButtonSheet>(
    context,
    label: 'Sheet',
    options: ColorsButtonSheet.values,
    labelBuilder: colorsButtonSheetLabel,
  );
  return switch (sheet) {
    ColorsButtonSheet.primary => buildButtonPrimaryUseCase(context),
    ColorsButtonSheet.secondary => buildButtonSecondaryUseCase(context),
    ColorsButtonSheet.ghostAndDestructive => buildButtonGhostDestructiveUseCase(
      context,
    ),
  };
}

String colorsButtonSheetLabel(ColorsButtonSheet sheet) {
  return switch (sheet) {
    ColorsButtonSheet.primary => 'Primary',
    ColorsButtonSheet.secondary => 'Secondary',
    ColorsButtonSheet.ghostAndDestructive => 'Ghost and destructive',
  };
}

// --- Sync keep-awake --------------------------------------------------------

/// Modes the lock screen presents; `hidden` is the not-shown state, so it is
/// not an option here.
const List<SyncKeepAwakePrivacyLockMode> componentsSyncKeepAwakeModes = [
  SyncKeepAwakePrivacyLockMode.syncing,
  SyncKeepAwakePrivacyLockMode.done,
  SyncKeepAwakePrivacyLockMode.interrupted,
];

/// Sample points on the progress ring; only the syncing mode draws it.
enum ComponentsSyncProgress { early, middle, nearlyDone }

/// Screen box: 'Short' is where the screen compacts its Figma gaps.
enum ComponentsScreenHeight { tall, short }

/// The keep-awake privacy lock screen. Tapping 'Unlock Vizor' with the
/// passcode-only option opens the passcode confirm sub-screen — private
/// `State`, so it is interactive rather than a knob, and the preview's
/// security fake always answers "incorrect".
Widget buildComponentsSyncKeepAwakeLockCase(BuildContext context) {
  final mode = wbStateKnob<SyncKeepAwakePrivacyLockMode>(
    context,
    label: 'Mode',
    options: componentsSyncKeepAwakeModes,
    labelBuilder: componentsSyncKeepAwakeModeLabel,
  );
  final biometric = wbStateKnob<CoreBiometricCase>(
    context,
    label: 'Biometric',
    options: CoreBiometricCase.values,
    labelBuilder: componentsBiometricLabel,
  );
  final progress = wbStateKnob<ComponentsSyncProgress>(
    context,
    label: 'Progress',
    options: ComponentsSyncProgress.values,
    labelBuilder: componentsSyncProgressLabel,
  );
  final height = wbStateKnob<ComponentsScreenHeight>(
    context,
    label: 'Screen height',
    options: ComponentsScreenHeight.values,
    labelBuilder: componentsScreenHeightLabel,
  );

  return syncKeepAwakeLockFixture(
    context,
    mode: mode,
    biometric: biometric,
    progress: componentsSyncProgressValue(progress),
    screenHeight: height == ComponentsScreenHeight.tall ? 852 : 667,
  );
}

String componentsSyncKeepAwakeModeLabel(SyncKeepAwakePrivacyLockMode mode) {
  return switch (mode) {
    SyncKeepAwakePrivacyLockMode.syncing => 'Syncing',
    SyncKeepAwakePrivacyLockMode.done => 'Sync complete',
    SyncKeepAwakePrivacyLockMode.interrupted => 'Sync paused',
    SyncKeepAwakePrivacyLockMode.hidden => 'Hidden',
  };
}

String componentsBiometricLabel(CoreBiometricCase biometric) {
  return switch (biometric) {
    CoreBiometricCase.faceId => 'Face ID',
    CoreBiometricCase.touchId => 'Touch ID',
    CoreBiometricCase.fingerprint => 'Fingerprint',
    CoreBiometricCase.passcodeOnly => 'Passcode only',
  };
}

String componentsSyncProgressLabel(ComponentsSyncProgress progress) {
  return switch (progress) {
    ComponentsSyncProgress.early => '12%',
    ComponentsSyncProgress.middle => '68%',
    ComponentsSyncProgress.nearlyDone => '99%',
  };
}

double componentsSyncProgressValue(ComponentsSyncProgress progress) {
  return switch (progress) {
    ComponentsSyncProgress.early => 0.12,
    ComponentsSyncProgress.middle => 0.68,
    ComponentsSyncProgress.nearlyDone => 0.99,
  };
}

String componentsScreenHeightLabel(ComponentsScreenHeight height) {
  return switch (height) {
    ComponentsScreenHeight.tall => 'Tall (852)',
    ComponentsScreenHeight.short => 'Short (667)',
  };
}

// --- Transaction progress ---------------------------------------------------

/// How many action buttons the page offers below its body copy.
enum ComponentsTransactionActions { none, primaryOnly, primaryAndSecondary }

Widget buildComponentsTransactionProgressCase(BuildContext context) {
  final phase = wbStateKnob<MobileTransactionProgressPhase>(
    context,
    label: 'Phase',
    options: MobileTransactionProgressPhase.values,
    labelBuilder: componentsTransactionPhaseLabel,
  );
  final actions = wbStateKnob<ComponentsTransactionActions>(
    context,
    label: 'Actions',
    options: ComponentsTransactionActions.values,
    labelBuilder: componentsTransactionActionsLabel,
    initial: ComponentsTransactionActions.primaryOnly,
  );
  final popBlocked = wbBoolKnob(context, label: 'Back blocked');

  return mobileTransactionProgressFixture(
    context,
    phase: phase,
    actions: switch (actions) {
      ComponentsTransactionActions.none => CoreTransactionProgressActions.none,
      ComponentsTransactionActions.primaryOnly =>
        CoreTransactionProgressActions.primaryOnly,
      ComponentsTransactionActions.primaryAndSecondary =>
        CoreTransactionProgressActions.primaryAndSecondary,
    },
    canPop: !popBlocked,
  );
}

/// Phases the badge draws differently: `pending` paints the same circle and
/// loader glyph as `inProgress`, so it would be a dead option here.
const List<MobileTransactionProgressPhase> componentsTransactionBadgePhases = [
  MobileTransactionProgressPhase.inProgress,
  MobileTransactionProgressPhase.succeeded,
  MobileTransactionProgressPhase.failed,
];

Widget buildComponentsTransactionProgressBadgeCase(BuildContext context) {
  final phase = wbStateKnob<MobileTransactionProgressPhase>(
    context,
    label: 'Phase',
    options: componentsTransactionBadgePhases,
    labelBuilder: componentsTransactionPhaseLabel,
  );
  final terminalAnimation = wbBoolKnob(
    context,
    label: 'Terminal animation',
    initial: true,
  );
  final tinted = wbBoolKnob(context, label: 'Tinted in-progress colours');

  return mobileTransactionProgressBadgeFixture(
    context,
    phase: phase,
    terminalAnimationEnabled: terminalAnimation,
    tintedInProgressColors: tinted,
  );
}

String componentsTransactionPhaseLabel(MobileTransactionProgressPhase phase) {
  return switch (phase) {
    MobileTransactionProgressPhase.inProgress => 'In progress',
    MobileTransactionProgressPhase.pending => 'Pending',
    MobileTransactionProgressPhase.succeeded => 'Succeeded',
    MobileTransactionProgressPhase.failed => 'Failed',
  };
}

String componentsTransactionActionsLabel(ComponentsTransactionActions actions) {
  return switch (actions) {
    ComponentsTransactionActions.none => 'None',
    ComponentsTransactionActions.primaryOnly => 'Primary only',
    ComponentsTransactionActions.primaryAndSecondary => 'Primary and secondary',
  };
}

// --- Linux keyring ----------------------------------------------------------

Widget buildComponentsLinuxKeyringGateCase(BuildContext context) {
  final state = wbStateKnob<CoreLinuxKeyringCase>(
    context,
    label: 'Phase',
    options: CoreLinuxKeyringCase.values,
    labelBuilder: componentsLinuxKeyringLabel,
    initial: CoreLinuxKeyringCase.keyringLocked,
  );
  final canCancel = wbBoolKnob(context, label: 'Cancel available');

  return linuxKeyringGateFixture(context, state: state, canCancel: canCancel);
}

Widget buildComponentsLinuxKeyringStartupCase(BuildContext context) {
  final bootstrap = wbStateKnob<CoreLinuxStartupCase>(
    context,
    label: 'Bootstrap',
    options: CoreLinuxStartupCase.values,
    labelBuilder: componentsLinuxStartupLabel,
  );
  return linuxKeyringStartupFixture(context, bootstrap: bootstrap);
}

String componentsLinuxKeyringLabel(CoreLinuxKeyringCase state) {
  return switch (state) {
    CoreLinuxKeyringCase.retrying => 'Trying secure storage',
    CoreLinuxKeyringCase.keyringLocked => 'Unlock your keyring',
    CoreLinuxKeyringCase.serviceUnavailable => 'Secure storage unavailable',
    CoreLinuxKeyringCase.storageCorrupt => 'Unable to read secure storage',
    CoreLinuxKeyringCase.outcomeUnknown => 'Unable to confirm the save',
  };
}

String componentsLinuxStartupLabel(CoreLinuxStartupCase bootstrap) {
  return switch (bootstrap) {
    CoreLinuxStartupCase.pending => 'Pending',
    CoreLinuxStartupCase.loaded => 'Loaded',
    CoreLinuxStartupCase.failed => 'Failed',
  };
}

// --- Mobile top nav ---------------------------------------------------------

/// Steps-variant progress samples.
enum ComponentsTopNavProgress { empty, partial, full }

Widget buildComponentsMobileTopNavCase(BuildContext context) {
  final variant = wbStateKnob<MobileTopNavVariantCase>(
    context,
    label: 'Variant',
    options: MobileTopNavVariantCase.values,
    labelBuilder: componentsTopNavVariantLabel,
  );
  final sync = wbStateKnob<MobileTopNavSyncCase>(
    context,
    label: 'Sync',
    options: MobileTopNavSyncCase.values,
    labelBuilder: componentsTopNavSyncLabel,
    initial: MobileTopNavSyncCase.synced,
  );
  final backIcon = wbStateKnob<MobileTopNavBackIconCase>(
    context,
    label: 'Back icon',
    options: MobileTopNavBackIconCase.values,
    labelBuilder: componentsTopNavBackIconLabel,
  );
  final progress = wbStateKnob<ComponentsTopNavProgress>(
    context,
    label: 'Progress',
    options: ComponentsTopNavProgress.values,
    labelBuilder: componentsTopNavProgressLabel,
    initial: ComponentsTopNavProgress.partial,
  );
  final reducedMotion = wbBoolKnob(context, label: 'Reduced motion');
  final balanceLabel = wbBoolKnob(context, label: 'Balance label');
  final backAction = wbBoolKnob(context, label: 'Back action', initial: true);
  final trailing = wbBoolKnob(context, label: 'Trailing lockup');

  return mobileTopNavFixture(
    context,
    variant: variant,
    sync: sync,
    reducedMotion: reducedMotion,
    balanceLabel: balanceLabel,
    backIcon: backIcon,
    hasBackAction: backAction,
    trailing: trailing,
    progress: switch (progress) {
      ComponentsTopNavProgress.empty => 0,
      ComponentsTopNavProgress.partial => 0.3,
      ComponentsTopNavProgress.full => 1,
    },
  );
}

Widget buildComponentsMobileTopNavAccountCase(BuildContext context) {
  final account = wbStateKnob<CoreAccountCase>(
    context,
    label: 'Account',
    options: CoreAccountCase.values,
    labelBuilder: componentsAccountLabel,
    initial: CoreAccountCase.software,
  );
  final sync = wbStateKnob<CoreSyncCase>(
    context,
    label: 'Sync',
    options: CoreSyncCase.values,
    labelBuilder: componentsSyncLabel,
  );
  final showSyncStatus = wbBoolKnob(
    context,
    label: 'Show sync status',
    initial: true,
  );

  return mobileTopNavAccountFixture(
    context,
    account: account,
    sync: sync,
    showSyncStatus: showSyncStatus,
  );
}

String componentsTopNavVariantLabel(MobileTopNavVariantCase variant) {
  return switch (variant) {
    MobileTopNavVariantCase.account => 'Account',
    MobileTopNavVariantCase.steps => 'Steps',
    MobileTopNavVariantCase.back => 'Back',
  };
}

String componentsTopNavSyncLabel(MobileTopNavSyncCase sync) {
  return switch (sync) {
    MobileTopNavSyncCase.hidden => 'Hidden',
    MobileTopNavSyncCase.synced => 'Synced',
    MobileTopNavSyncCase.syncing => 'Syncing',
    MobileTopNavSyncCase.failed => 'Failed',
  };
}

String componentsTopNavBackIconLabel(MobileTopNavBackIconCase icon) {
  return switch (icon) {
    MobileTopNavBackIconCase.chevron => 'Chevron',
    MobileTopNavBackIconCase.cross => 'Cross',
  };
}

String componentsTopNavProgressLabel(ComponentsTopNavProgress progress) {
  return switch (progress) {
    ComponentsTopNavProgress.empty => 'Start',
    ComponentsTopNavProgress.partial => 'A third',
    ComponentsTopNavProgress.full => 'Complete',
  };
}

// --- Main sidebar -----------------------------------------------------------

/// Sidebar spacing families: only macOS reserves room for window controls.
enum ComponentsSidebarPlatform { macOs, windowsAndLinux }

/// The sidebar always shows an account, so 'None' is not an option here.
const List<CoreAccountCase> componentsSidebarAccounts = [
  CoreAccountCase.software,
  CoreAccountCase.keystone,
];

/// The desktop main sidebar. The accounts popover and a sign-out in flight
/// are internal `State` reached by tapping, not knobs.
Widget buildComponentsMainSidebarCase(BuildContext context) {
  final account = wbStateKnob<CoreAccountCase>(
    context,
    label: 'Account',
    options: componentsSidebarAccounts,
    labelBuilder: componentsAccountLabel,
  );
  final route = wbStateKnob<CoreSidebarRoute>(
    context,
    label: 'Active route',
    options: CoreSidebarRoute.values,
    labelBuilder: componentsSidebarRouteLabel,
  );
  final sync = wbStateKnob<CoreSyncCase>(
    context,
    label: 'Sync',
    options: CoreSyncCase.values,
    labelBuilder: componentsSyncLabel,
  );
  final migration = wbStateKnob<CoreSidebarMigrationCase>(
    context,
    label: 'Migration section',
    options: CoreSidebarMigrationCase.values,
    labelBuilder: componentsSidebarMigrationLabel,
  );
  final platform = wbStateKnob<ComponentsSidebarPlatform>(
    context,
    label: 'Platform spacing',
    options: ComponentsSidebarPlatform.values,
    labelBuilder: componentsSidebarPlatformLabel,
  );
  final privacyMode = wbBoolKnob(context, label: 'Privacy mode');
  final swapEnabled = wbBoolKnob(context, label: 'Swap enabled', initial: true);

  return mainSidebarFixture(
    context,
    account: account,
    route: route,
    sync: sync,
    privacyMode: privacyMode,
    swapEnabled: swapEnabled,
    migration: migration,
    platform: platform == ComponentsSidebarPlatform.macOs
        ? TargetPlatform.macOS
        : TargetPlatform.windows,
  );
}

String componentsAccountLabel(CoreAccountCase account) {
  return switch (account) {
    CoreAccountCase.none => 'None',
    CoreAccountCase.software => 'Software',
    CoreAccountCase.keystone => 'Keystone',
  };
}

String componentsSyncLabel(CoreSyncCase sync) {
  return switch (sync) {
    CoreSyncCase.synced => 'Synced',
    CoreSyncCase.syncing => 'Syncing',
    CoreSyncCase.failed => 'Failed',
  };
}

String componentsSidebarRouteLabel(CoreSidebarRoute route) {
  return switch (route) {
    CoreSidebarRoute.home => 'Home',
    CoreSidebarRoute.activity => 'Activity',
    CoreSidebarRoute.settings => 'Settings',
  };
}

String componentsSidebarMigrationLabel(CoreSidebarMigrationCase migration) {
  return switch (migration) {
    CoreSidebarMigrationCase.none => 'None',
    CoreSidebarMigrationCase.splitRows => 'Split rows',
    CoreSidebarMigrationCase.needsInput => 'Needs input',
  };
}

String componentsSidebarPlatformLabel(ComponentsSidebarPlatform platform) {
  return switch (platform) {
    ComponentsSidebarPlatform.macOs => 'macOS',
    ComponentsSidebarPlatform.windowsAndLinux => 'Windows and Linux',
  };
}

// --- Toast ------------------------------------------------------------------

/// Glyphs the toast is actually shown with by its call sites.
enum ComponentsToastIcon { checkCircle, warning, copy }

/// Message length; the long one is what wraps to the pill's second line.
enum ComponentsToastMessage { short, wrapping }

/// Whether an [AppToastHost] is mounted; 'Absent' exercises the root-overlay
/// fallback `showAppToast` uses when a modal covers the host.
enum ComponentsToastHostMount { inShell, absent }

/// Window top padding the hosts read for their `max(32, top + 8)` offset.
enum ComponentsToastInset { desktop, phoneNotch }

Widget buildComponentsToastPlaygroundCase(BuildContext context) {
  final tone = wbStateKnob<AppToastTone>(
    context,
    label: 'Tone',
    options: AppToastTone.values,
    labelBuilder: componentsToastToneLabel,
  );
  final icon = wbStateKnob<ComponentsToastIcon>(
    context,
    label: 'Icon',
    options: ComponentsToastIcon.values,
    labelBuilder: componentsToastIconLabel,
  );
  final message = wbStateKnob<ComponentsToastMessage>(
    context,
    label: 'Message',
    options: ComponentsToastMessage.values,
    labelBuilder: componentsToastMessageLabel,
  );

  return appToastPlaygroundFixture(
    context,
    tone: tone,
    iconName: componentsToastIconName(icon),
    message: componentsToastMessageText(message),
  );
}

/// The host. The visible toast is driven by the fixture's 'Show toast'
/// button, which is also what auto-fires once per knob option.
Widget buildComponentsToastHostCase(BuildContext context) {
  final host = wbStateKnob<ComponentsToastHostMount>(
    context,
    label: 'Host',
    options: ComponentsToastHostMount.values,
    labelBuilder: componentsToastHostLabel,
  );
  final inset = wbStateKnob<ComponentsToastInset>(
    context,
    label: 'Inset',
    options: ComponentsToastInset.values,
    labelBuilder: componentsToastInsetLabel,
  );
  final tone = wbStateKnob<AppToastTone>(
    context,
    label: 'Tone',
    options: AppToastTone.values,
    labelBuilder: componentsToastToneLabel,
  );

  return appToastHostFixture(
    context,
    hasHost: host == ComponentsToastHostMount.inShell,
    topPadding: componentsToastInsetValue(inset),
    tone: tone,
    message: tone == AppToastTone.destructive
        ? "Couldn't copy the address"
        : 'Address copied',
  );
}

String componentsToastToneLabel(AppToastTone tone) {
  return switch (tone) {
    AppToastTone.neutral => 'Neutral',
    AppToastTone.destructive => 'Destructive',
  };
}

String componentsToastIconLabel(ComponentsToastIcon icon) {
  return switch (icon) {
    ComponentsToastIcon.checkCircle => 'Check circle',
    ComponentsToastIcon.warning => 'Warning',
    ComponentsToastIcon.copy => 'Copy',
  };
}

String componentsToastIconName(ComponentsToastIcon icon) {
  return switch (icon) {
    ComponentsToastIcon.checkCircle => AppIcons.checkCircle,
    ComponentsToastIcon.warning => AppIcons.warning,
    ComponentsToastIcon.copy => AppIcons.copy,
  };
}

String componentsToastMessageLabel(ComponentsToastMessage message) {
  return switch (message) {
    ComponentsToastMessage.short => 'Short',
    ComponentsToastMessage.wrapping => 'Wrapping two lines',
  };
}

String componentsToastMessageText(ComponentsToastMessage message) {
  return switch (message) {
    ComponentsToastMessage.short => 'Address copied',
    ComponentsToastMessage.wrapping =>
      'Transaction hash copied to your clipboard',
  };
}

String componentsToastHostLabel(ComponentsToastHostMount host) {
  return switch (host) {
    ComponentsToastHostMount.inShell => 'In shell',
    ComponentsToastHostMount.absent => 'Absent (overlay fallback)',
  };
}

String componentsToastInsetLabel(ComponentsToastInset inset) {
  return switch (inset) {
    ComponentsToastInset.desktop => 'Desktop (0)',
    ComponentsToastInset.phoneNotch => 'Phone notch (59)',
  };
}

double componentsToastInsetValue(ComponentsToastInset inset) {
  return switch (inset) {
    ComponentsToastInset.desktop => 0,
    ComponentsToastInset.phoneNotch => 59,
  };
}

// --- Network fallback toast -------------------------------------------------

/// The five production notices that reach this toast: two from RPC endpoint
/// failover, three from the network-privacy startup checks.
enum ComponentsNetworkNotice {
  endpointFailover,
  endpointRecovered,
  torStartupFailed,
  torUpdatesUnavailable,
  updatesUnavailable,
}

/// Box the toast is measured in; the widget's own cap is 560. 'Phone' is the
/// content width a 393px phone leaves after the host's 16px side gutters.
enum ComponentsToastWidth { phone, desktop }

/// Notices the host case fires — one short, one long.
const List<ComponentsNetworkNotice> componentsNetworkHostNotices = [
  ComponentsNetworkNotice.endpointFailover,
  ComponentsNetworkNotice.torStartupFailed,
];

Widget buildComponentsNetworkFallbackToastCase(BuildContext context) {
  final notice = wbStateKnob<ComponentsNetworkNotice>(
    context,
    label: 'Message',
    options: ComponentsNetworkNotice.values,
    labelBuilder: componentsNetworkNoticeLabel,
  );
  final width = wbStateKnob<ComponentsToastWidth>(
    context,
    label: 'Width',
    options: ComponentsToastWidth.values,
    labelBuilder: componentsToastWidthLabel,
  );

  return networkFallbackToastFixture(
    context,
    message: componentsNetworkNoticeText(notice),
    width: width == ComponentsToastWidth.phone ? 361 : 560,
  );
}

Widget buildComponentsNetworkFallbackHostCase(BuildContext context) {
  final shell = wbStateKnob<ComponentsToastShell>(
    context,
    label: 'Shell',
    options: ComponentsToastShell.values,
    labelBuilder: componentsToastShellLabel,
  );
  final inset = wbStateKnob<ComponentsToastInset>(
    context,
    label: 'Top inset',
    options: ComponentsToastInset.values,
    labelBuilder: componentsToastInsetLabel,
  );
  final notice = wbStateKnob<ComponentsNetworkNotice>(
    context,
    label: 'Message',
    options: componentsNetworkHostNotices,
    labelBuilder: componentsNetworkNoticeLabel,
  );

  return networkFallbackToastHostFixture(
    context,
    sidebarInset: shell == ComponentsToastShell.desktopSidebar,
    topPadding: componentsToastInsetValue(inset),
    message: componentsNetworkNoticeText(notice),
  );
}

/// Whether a sidebar shell publishes a content-overlay inset.
enum ComponentsToastShell { none, desktopSidebar }

String componentsToastShellLabel(ComponentsToastShell shell) {
  return switch (shell) {
    ComponentsToastShell.none => 'No shell',
    ComponentsToastShell.desktopSidebar => 'Desktop sidebar inset',
  };
}

String componentsToastWidthLabel(ComponentsToastWidth width) {
  return switch (width) {
    ComponentsToastWidth.phone => 'Phone (361)',
    ComponentsToastWidth.desktop => 'Desktop (560 cap)',
  };
}

String componentsNetworkNoticeLabel(ComponentsNetworkNotice notice) {
  return switch (notice) {
    ComponentsNetworkNotice.endpointFailover => 'Endpoint failover',
    ComponentsNetworkNotice.endpointRecovered => 'Endpoint recovered',
    ComponentsNetworkNotice.torStartupFailed => 'Tor startup failed',
    ComponentsNetworkNotice.torUpdatesUnavailable =>
      'Updates unavailable over Tor',
    ComponentsNetworkNotice.updatesUnavailable => 'Updates unavailable',
  };
}

String componentsNetworkNoticeText(ComponentsNetworkNotice notice) {
  return switch (notice) {
    ComponentsNetworkNotice.endpointFailover => kWbEndpointFailoverNotice,
    ComponentsNetworkNotice.endpointRecovered => kWbEndpointRecoveredNotice,
    ComponentsNetworkNotice.torStartupFailed => kTorStartupFailureNotice,
    ComponentsNetworkNotice.torUpdatesUnavailable =>
      kTorUpdateUnavailableNotice,
    ComponentsNetworkNotice.updatesUnavailable =>
      kSoftwareUpdateUnavailableNotice,
  };
}

// --- Mobile sheets ----------------------------------------------------------

/// The real ZIP-317 fee sheet. It opens itself on the first frame; its own
/// Close button pops the sheet route, never the widgetbook root.
Widget buildComponentsTxFeeInfoSheetCase(BuildContext context) {
  final copy = wbStateKnob<CoreTxFeeSheetCopy>(
    context,
    label: 'Copy',
    options: CoreTxFeeSheetCopy.values,
    labelBuilder: componentsTxFeeSheetCopyLabel,
  );
  return mobileTxFeeInfoSheetFixture(context, copy: copy);
}

Widget buildComponentsUnsupportedSheetCase(BuildContext context) {
  final copy = wbStateKnob<CoreUnsupportedSheetCopy>(
    context,
    label: 'Message',
    options: CoreUnsupportedSheetCopy.values,
    labelBuilder: componentsUnsupportedSheetCopyLabel,
  );
  return unsupportedSheetFixture(context, copy: copy);
}

String componentsTxFeeSheetCopyLabel(CoreTxFeeSheetCopy copy) {
  return switch (copy) {
    CoreTxFeeSheetCopy.zip317 => 'Default ZIP-317',
    CoreTxFeeSheetCopy.custom => 'Custom title and description',
  };
}

String componentsUnsupportedSheetCopyLabel(CoreUnsupportedSheetCopy copy) {
  return switch (copy) {
    CoreUnsupportedSheetCopy.inProgress => 'Default',
    CoreUnsupportedSheetCopy.keystoneConnect => 'Keystone connect',
    CoreUnsupportedSheetCopy.biometricUnlock => 'Biometric unlock',
  };
}

// --- Tooltip ----------------------------------------------------------------

/// `message` and `richMessage` are mutually exclusive in the constructor, so
/// this knob switches which one is passed.
enum ComponentsTooltipContent { plain, rich }

/// Which side of the anchor the bubble prefers.
enum ComponentsTooltipPlacement { above, below }

Widget buildComponentsTooltipCase(BuildContext context) {
  final content = wbStateKnob<ComponentsTooltipContent>(
    context,
    label: 'Content',
    options: ComponentsTooltipContent.values,
    labelBuilder: componentsTooltipContentLabel,
  );
  final placement = wbStateKnob<ComponentsTooltipPlacement>(
    context,
    label: 'Placement',
    options: ComponentsTooltipPlacement.values,
    labelBuilder: componentsTooltipPlacementLabel,
  );
  final trigger = wbStateKnob<CoreTooltipTrigger>(
    context,
    label: 'Trigger',
    options: CoreTooltipTrigger.values,
    labelBuilder: componentsTooltipTriggerLabel,
  );

  return appTooltipFixture(
    context,
    rich: content == ComponentsTooltipContent.rich,
    preferBelow: placement == ComponentsTooltipPlacement.below,
    trigger: trigger,
  );
}

String componentsTooltipContentLabel(ComponentsTooltipContent content) {
  return switch (content) {
    ComponentsTooltipContent.plain => 'Plain message',
    ComponentsTooltipContent.rich => 'Rich span',
  };
}

String componentsTooltipPlacementLabel(ComponentsTooltipPlacement placement) {
  return switch (placement) {
    ComponentsTooltipPlacement.above => 'Above',
    ComponentsTooltipPlacement.below => 'Below',
  };
}

String componentsTooltipTriggerLabel(CoreTooltipTrigger trigger) {
  return switch (trigger) {
    CoreTooltipTrigger.hover => 'Hover (forced visible)',
    CoreTooltipTrigger.tap => 'Tap',
  };
}
