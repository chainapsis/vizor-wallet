import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/widgets/app_toast.dart';

void copySwapText(
  BuildContext context, {
  required String text,
  required String toastMessage,
}) {
  unawaited(_copySwapText(context, text: text, toastMessage: toastMessage));
}

Future<void> _copySwapText(
  BuildContext context, {
  required String text,
  required String toastMessage,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  showAppToast(context, toastMessage);
}
