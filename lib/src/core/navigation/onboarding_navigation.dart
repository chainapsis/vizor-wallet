import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

bool get usesInteractiveOnboardingNavigation =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

void navigateOnboardingForward(
  BuildContext context,
  String location, {
  Object? extra,
}) {
  if (usesInteractiveOnboardingNavigation) {
    context.push(location, extra: extra);
    return;
  }
  context.go(location, extra: extra);
}

void navigateOnboardingBack(
  BuildContext context,
  String fallbackLocation, {
  Object? extra,
}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(fallbackLocation, extra: extra);
}
