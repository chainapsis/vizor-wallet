import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/zcash_explorer.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tappable.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/zcash_explorer_provider.dart';

class SettingsExplorerScreen extends ConsumerStatefulWidget {
  const SettingsExplorerScreen({super.key});

  @override
  ConsumerState<SettingsExplorerScreen> createState() =>
      _SettingsExplorerScreenState();
}

class _SettingsExplorerScreenState
    extends ConsumerState<SettingsExplorerScreen> {
  final _customController = TextEditingController();
  late ZcashExplorerChoice _choice;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final current = ref.read(zcashExplorerProvider);
    _choice = _savedChoice(current);
    if (_choice == ZcashExplorerChoice.custom) {
      _customController.text = current;
    }
  }

  ZcashExplorerChoice _savedChoice(String current) {
    return zcashExplorerChoice(
      current,
      networkName: ref.read(rpcEndpointProvider).networkName,
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  bool _canUpdate(String current) {
    if (_isSubmitting) return false;
    return switch (_choice) {
      ZcashExplorerChoice.custom => _customTemplateChanged(current),
      _ => _choice != _savedChoice(current),
    };
  }

  bool _customTemplateChanged(String current) {
    try {
      final normalized = normalizeExplorerUrlTemplate(_customController.text);
      return normalized != current.trim();
    } on FormatException {
      return _customController.text.trim().isNotEmpty;
    }
  }

  String? _customMessageText() {
    if (_choice != ZcashExplorerChoice.custom) return null;
    if (_customController.text.trim().isEmpty) return null;
    try {
      normalizeExplorerUrlTemplate(_customController.text);
      return null;
    } on FormatException catch (e) {
      return explorerUrlErrorText(context.l10n, e);
    }
  }

  Future<void> _submit() async {
    final current = ref.read(zcashExplorerProvider);
    if (!_canUpdate(current)) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final notifier = ref.read(zcashExplorerProvider.notifier);
      switch (_choice) {
        case ZcashExplorerChoice.zecBlock:
          await notifier.resetToDefault();
        case ZcashExplorerChoice.zecBlockPrivate:
          await notifier.setZecBlockPrivate();
        case ZcashExplorerChoice.custom:
          await notifier.setCustom(_customController.text);
      }
      if (!mounted) return;
      final next = ref.read(zcashExplorerProvider);
      setState(() {
        _customController.text = _choice == ZcashExplorerChoice.custom
            ? next
            : '';
        _isSubmitting = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = explorerUrlErrorText(context.l10n, e);
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('SettingsExplorerScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitError = context.l10n.settingsExplorerSaveFailed;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(zcashExplorerProvider);
    final networkName = ref.watch(rpcEndpointProvider).networkName;
    final colors = context.colors;
    final customMessage = _customMessageText();
    final savedChoice = _savedChoice(current);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneScrollScaffold(
          toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.settingsExplorerTitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      savedChoice == ZcashExplorerChoice.zecBlock
                          ? context.l10n.settingsExplorerCurrentDefault(
                              defaultZcashExplorerHost(networkName),
                            )
                          : context.l10n.settingsExplorerCurrent(
                              explorerSettingsLabel(
                                context.l10n,
                                current,
                                networkName: networkName,
                              ),
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _ExplorerOptionCard(
                      key: const ValueKey('explorer_option_zecblock'),
                      iconName: AppIcons.globe,
                      label: kDefaultZcashExplorerLabel,
                      subtitle: defaultZcashExplorerHost(networkName),
                      selected: _choice == ZcashExplorerChoice.zecBlock,
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() {
                              _choice = ZcashExplorerChoice.zecBlock;
                              _submitError = null;
                            }),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (zecBlockPrivateExplorerAvailable(networkName)) ...[
                      _ExplorerOptionCard(
                        key: const ValueKey('explorer_option_zecblock_private'),
                        iconName: AppIcons.eyeClosed,
                        label: kZecBlockPrivateExplorerLabel,
                        subtitle: context.l10n.settingsExplorerPrivateSubtitle,
                        selected:
                            _choice == ZcashExplorerChoice.zecBlockPrivate,
                        onTap: _isSubmitting
                            ? null
                            : () => setState(() {
                                _choice = ZcashExplorerChoice.zecBlockPrivate;
                                _submitError = null;
                              }),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    _ExplorerOptionCard(
                      key: const ValueKey('explorer_option_custom'),
                      iconName: AppIcons.edit,
                      label: context.l10n.settingsExplorerCustom,
                      subtitle: context.l10n.settingsExplorerCustomSubtitle,
                      selected: _choice == ZcashExplorerChoice.custom,
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() {
                              _choice = ZcashExplorerChoice.custom;
                              _submitError = null;
                              if (_customController.text.trim().isEmpty &&
                                  savedChoice == ZcashExplorerChoice.custom) {
                                _customController.text = current;
                              }
                            }),
                    ),
                    if (_choice == ZcashExplorerChoice.custom) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        key: const ValueKey('explorer_custom_field'),
                        label: context.l10n.settingsExplorerUrlLabel,
                        hintText:
                            'https://explorer.example/tx/{txid}', // l10n-ignore: URL template
                        controller: _customController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        messageText: customMessage,
                        tone: customMessage == null
                            ? AppTextFieldTone.neutral
                            : AppTextFieldTone.destructive,
                        onChanged: (_) => setState(() => _submitError = null),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.l10n.settingsExplorerTemplateHint(
                          '{txid}', // l10n-ignore: URL placeholder token
                          '{txHash}', // l10n-ignore: URL placeholder token
                        ),
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppIcon(
                        AppIcons.book,
                        size: 20,
                        color: colors.icon.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _choice == ZcashExplorerChoice.zecBlockPrivate
                          ? context.l10n.settingsExplorerPrivateCopy
                          : context.l10n.settingsExplorerPrivacyCopy,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    if (_submitError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _submitError!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.destructive,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: AppButton(
                        key: const ValueKey('explorer_update'),
                        onPressed: _canUpdate(current) ? _submit : null,
                        minWidth: 196,
                        child: Text(
                          _isSubmitting
                              ? context.l10n.commonUpdating
                              : context.l10n.settingsExplorerUpdate,
                        ),
                      ),
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

class _ExplorerOptionCard extends StatelessWidget {
  const _ExplorerOptionCard({
    required this.iconName,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadii.medium);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $subtitle', // l10n-ignore: joins two labels
      // excludeSemantics drops the detector's tap action, so restate it.
      onTap: onTap,
      excludeSemantics: true,
      child: AppTappable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: radius,
          ),
          // Drawn over the card so a thicker selected border moves nothing.
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.subtle,
              width: selected ? 1.5 : 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            children: [
              Opacity(
                opacity: selected ? 1 : 0.5,
                child: AppIcon(iconName, size: 20, color: colors.icon.accent),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.background.inverse
                      : colors.background.neutralSubtleOpacity,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? Center(
                        child: AppIcon(
                          AppIcons.check,
                          size: 12,
                          color: colors.background.ground,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
