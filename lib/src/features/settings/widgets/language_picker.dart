import 'package:flutter/material.dart';

import '../../../core/l10n/app_language.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../accounts/widgets/account_modal_card.dart';
import '../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel;
import 'settings_option_card.dart';

/// Desktop settings and Welcome language modal. Like the theme modal, a
/// choice applies only on Update. There is no "follow the device" option: on
/// a device in a language Vizor lacks it would look like that language.
class DesktopLanguageModal extends StatefulWidget {
  const DesktopLanguageModal({
    required this.current,
    required this.available,
    required this.onCancel,
    required this.onUpdate,
    super.key,
  });

  final AppLanguage current;
  final List<AppLanguage> available;
  final VoidCallback onCancel;
  final Future<void> Function(AppLanguage language) onUpdate;

  @override
  State<DesktopLanguageModal> createState() => _DesktopLanguageModalState();
}

class _DesktopLanguageModalState extends State<DesktopLanguageModal> {
  late AppLanguage _selected = widget.current;
  bool _isSubmitting = false;
  bool _submitFailed = false;

  bool get _canUpdate => !_isSubmitting && _selected != widget.current;

  void _select(AppLanguage language) {
    setState(() {
      _submitFailed = false;
      _selected = language;
    });
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitFailed = false;
    });
    try {
      await widget.onUpdate(_selected);
    } catch (_) {
      if (mounted) setState(() => _submitFailed = true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsLanguageLabel,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (index, option) in widget.available.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            SettingsOptionCard(
              key: ValueKey('language_option_${option.tag}'),
              label: option.nativeName,
              labelLocale: option.locale,
              selected: option == _selected,
              onTap: () => _select(option),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_submitFailed) ...[
            Text(
              l10n.settingsLanguageUpdateFailed,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AccountModalActions(
            onCancel: _isSubmitting ? null : widget.onCancel,
            cancelLabel: l10n.commonCancel,
            actionLabel: _isSubmitting
                ? l10n.commonUpdating
                : l10n.commonUpdate,
            onAction: _canUpdate ? _submit : null,
          ),
        ],
      ),
    );
  }
}

/// Opens the mobile language sheet. Returns `null` when cancelled.
Future<AppLanguage?> showMobileLanguageSheet(
  BuildContext context, {
  required AppLanguage current,
  required List<AppLanguage> available,
}) {
  return showAppMobileSheet<AppLanguage>(
    context: context,
    builder: (_) => MobileLanguageSheet(current: current, available: available),
  );
}

/// Mobile settings and Welcome language sheet, laid out like the theme sheet.
class MobileLanguageSheet extends StatefulWidget {
  const MobileLanguageSheet({
    required this.current,
    required this.available,
    super.key,
  });

  final AppLanguage current;
  final List<AppLanguage> available;

  @override
  State<MobileLanguageSheet> createState() => _MobileLanguageSheetState();
}

class _MobileLanguageSheetState extends State<MobileLanguageSheet> {
  late AppLanguage _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MobileModalScaffold(
      title: l10n.settingsLanguageLabel,
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.md,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in widget.available) ...[
            MobileSettingsOptionCard(
              key: ValueKey('mobile_language_option_${option.tag}'),
              label: option.nativeName,
              labelLocale: option.locale,
              selected: option == _selected,
              onTap: () => setState(() => _selected = option),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('mobile_language_update'),
            expand: true,
            onPressed: () => Navigator.of(context).pop<AppLanguage>(_selected),
            child: Text(l10n.commonUpdate),
          ),
          const SizedBox(height: AppSpacing.xs),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
