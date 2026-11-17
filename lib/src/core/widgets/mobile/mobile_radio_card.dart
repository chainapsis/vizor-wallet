import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../feedback/app_haptics.dart';
import '../../l10n/locale_typography.dart';
import '../../theme/app_theme.dart';
import '../app_icon.dart';
import 'mobile_surface_card.dart';

/// One choice in a mobile single-choice list — Figma `Radio Card`
/// (4654:74580). Stack them with [AppSpacing.s] between (Figma `Radi Group`).
///
/// The card is the mobile surface ([MobileSurfaceCard]: ground fill and its
/// soft lift) with no stroke; only the selected card carries a 2px strong
/// stroke, drawn over the card so its content does not move. An optional
/// icon dims to half when the card is not selected, and a round check on the
/// trailing edge shows the choice.
///
/// Screen readers hear one button: [semanticsLabel] (or [title]) with its
/// selected state. [actions] keep their own buttons beside it.
class MobileRadioCard extends StatelessWidget {
  const MobileRadioCard({
    required this.title,
    required this.selected,
    required this.onTap,
    this.details = const [],
    this.description,
    this.iconName,
    this.titleTrailing,
    this.actions = const [],
    this.enabled = true,
    this.titleLocale,
    this.semanticsLabel,
    super.key,
  });

  final String title;

  /// Short facts under the title, such as an address, a latency or a
  /// status. A long one wraps, and the card grows to fit it.
  final List<String> details;

  /// A wrapping paragraph under the title that explains the choice. The
  /// icon and check then align to the top.
  final String? description;
  final bool selected;

  /// Null while the choice can't change; the card then ignores taps.
  final VoidCallback? onTap;

  /// An [AppIcons] name, drawn before the text.
  final String? iconName;

  /// Shown beside the title, such as a "Recommended" badge.
  final Widget? titleTrailing;

  /// Buttons between the text and the check, such as edit and delete. Each
  /// keeps its own tap and semantics.
  final List<Widget> actions;

  /// False for a choice that is unavailable: the card dims to half and
  /// ignores taps.
  final bool enabled;

  /// The language [title] is written in when it differs from the UI's, such
  /// as a language's own name in a picker; its glyphs come first.
  final Locale? titleLocale;

  /// The spoken name. Defaults to [title].
  final String? semanticsLabel;

  static const _minHeight = 64.0;
  static const _strokeWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconName = this.iconName;
    final onTap = this.onTap;
    final titleLocale = this.titleLocale;
    final description = this.description;
    final titleTrailing = this.titleTrailing;
    final topAligned = description != null;
    var titleStyle = AppTypography.labelLarge.copyWith(
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: colors.text.accent,
    );
    if (titleLocale != null) {
      titleStyle = titleStyle.copyWith(
        fontFamilyFallback: fontFamilyFallbackFor(titleLocale),
      );
    }
    final detailStyle = AppTypography.labelLarge.copyWith(
      fontWeight: FontWeight.w400,
      color: selected ? colors.text.accent : colors.text.secondary,
    );
    final select = onTap == null || !enabled
        ? null
        : () {
            if (!selected) unawaited(AppHaptics.selection());
            onTap();
          };

    // The card grows with its text: a long title wraps, unless a trailing
    // widget shares its line.
    final titleText = Text(
      title,
      locale: titleLocale,
      maxLines: titleTrailing == null ? null : 1,
      overflow: titleTrailing == null ? null : TextOverflow.ellipsis,
      style: titleStyle,
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titleTrailing == null)
          titleText
        else
          Row(
            children: [
              // The title keeps its width; the trailing widget takes what is
              // left and ellipsizes in a narrow card.
              titleText,
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: titleTrailing),
            ],
          ),
        for (final detail in details) ...[
          const SizedBox(height: 2),
          Text(detail, style: detailStyle),
        ],
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: enabled ? null : false,
      label: semanticsLabel ?? title,
      onTap: select,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: select,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: selected
                  ? Border.all(
                      color: colors.border.strong,
                      width: _strokeWidth,
                      strokeAlign: BorderSide.strokeAlignInside,
                    )
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minHeight),
              child: MobileSurfaceCard(
                cornerRadius: AppRadii.medium,
                padding: EdgeInsets.only(
                  left: iconName == null ? AppSpacing.sm : AppSpacing.xs,
                  right: AppSpacing.s,
                  top: topAligned ? AppSpacing.s : AppSpacing.xxs,
                  bottom: topAligned ? AppSpacing.s : AppSpacing.xxs,
                ),
                child: Row(
                  crossAxisAlignment: topAligned
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    if (iconName != null) ...[
                      ExcludeSemantics(
                        child: SizedBox.square(
                          dimension: 32,
                          child: Center(
                            child: Opacity(
                              opacity: selected ? 1 : 0.5,
                              child: AppIcon(
                                iconName,
                                size: 20,
                                color: colors.icon.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxs,
                          ),
                          child: text,
                        ),
                      ),
                    ),
                    ...actions,
                    const SizedBox(width: AppSpacing.xs),
                    Padding(
                      // Level with the title of a top-aligned card.
                      padding: EdgeInsets.only(
                        top: topAligned ? AppSpacing.xxs : 0,
                      ),
                      child: _RadioCheck(selected: selected),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing round check: filled with a check when selected, an empty
/// raised circle otherwise.
class _RadioCheck extends StatelessWidget {
  const _RadioCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: selected
              ? colors.background.inverse
              : colors.background.raised,
          shape: BoxShape.circle,
        ),
        child: selected
            ? Center(
                child: AppIcon(
                  AppIcons.check,
                  size: 14,
                  color: colors.text.inverse,
                ),
              )
            : null,
      ),
    );
  }
}
