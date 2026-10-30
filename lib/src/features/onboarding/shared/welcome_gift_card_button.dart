import 'package:flutter/widgets.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'welcome_button_tokens.dart';

/// Gift activation uses Welcome's fixed dark surface in both form factors.
class WelcomeGiftCardButton extends StatelessWidget {
  const WelcomeGiftCardButton({
    required this.onPressed,
    this.height,
    super.key,
  });

  final VoidCallback onPressed;
  final double? height;

  @override
  Widget build(BuildContext context) => AppButton(
    expand: true,
    height: height,
    variant: AppButtonVariant.ghost,
    focusRingColor: WelcomeButtonTokens.focusRing,
    enabledBackgroundColor: const Color(0x00000000),
    disabledBackgroundColor: const Color(0x00000000),
    pressedBackgroundColor: WelcomeButtonTokens.secondaryBackground,
    enabledLabelColor: WelcomeButtonTokens.accentLabel,
    pressedLabelColor: WelcomeButtonTokens.accentLabel,
    leading: const AppIcon(AppIcons.giftCard),
    growWithContent: true,
    constrainContent: true,
    onPressed: onPressed,
    child: const Text('Activate gift card', textAlign: TextAlign.center),
  );
}
