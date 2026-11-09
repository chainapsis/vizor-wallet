import 'package:flutter/material.dart';

import '../../../core/l10n/app_language.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/locale_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// First-run Welcome control showing the current language in its own script.
/// Opens the language picker; the language icon lets people who cannot read the
/// current language find it.
class WelcomeLanguageButton extends StatefulWidget {
  const WelcomeLanguageButton({
    required this.height,
    required this.background,
    required this.hoverBackground,
    required this.onTap,
    super.key,
  });

  final double height;
  final Color background;
  final Color hoverBackground;
  final VoidCallback onTap;

  @override
  State<WelcomeLanguageButton> createState() => _WelcomeLanguageButtonState();
}

class _WelcomeLanguageButtonState extends State<WelcomeLanguageButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final language =
        AppLanguage.fromTag(Localizations.localeOf(context).languageCode) ??
        AppLanguage.en;
    const foreground = Color(0xffffffff);
    return Semantics(
      button: true,
      label: context.l10n.settingsLanguageLabel,
      value: language.nativeName,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverBackground : widget.background,
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(AppIcons.language, size: 16, color: foreground),
                const SizedBox(width: AppSpacing.xxs + 2),
                Text(
                  language.nativeName,
                  locale: language.locale,
                  style: AppTypography.labelMedium.copyWith(
                    color: foreground,
                    fontFamilyFallback: fontFamilyFallbackFor(language.locale),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const RotatedBox(
                  quarterTurns: 1,
                  child: AppIcon(
                    AppIcons.chevronForward,
                    size: 12,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
