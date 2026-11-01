import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/contact_zns_lookup.dart';

/// The field tone for a contact form's name line. A resolved name takes the
/// success tone, the same check the send field shows.
AppTextFieldTone contactZnsMessageTone(ContactZnsMessageKind kind) =>
    switch (kind) {
      ContactZnsMessageKind.resolved => AppTextFieldTone.success,
      ContactZnsMessageKind.error => AppTextFieldTone.destructive,
      ContactZnsMessageKind.pending ||
      ContactZnsMessageKind.saved => AppTextFieldTone.neutral,
    };

/// An icon that replaces the tone's default, or null to keep the default.
/// Neutral name lines carry a globe so they read as name state.
Widget? contactZnsMessageIcon(ContactZnsMessageKind kind, AppColors colors) =>
    switch (kind) {
      ContactZnsMessageKind.pending || ContactZnsMessageKind.saved => AppIcon(
        AppIcons.globe,
        size: AppIconSize.medium,
        color: colors.icon.muted,
      ),
      ContactZnsMessageKind.resolved || ContactZnsMessageKind.error => null,
    };
