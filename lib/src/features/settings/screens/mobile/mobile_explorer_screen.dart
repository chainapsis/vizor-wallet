import 'package:flutter/material.dart' show Scaffold, TextInputType;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_radio_card.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/zcash_explorer_provider.dart';

/// Mobile explorer settings — ZecBlock by default, or any other
/// explorer URL the user prefers for transaction links.
class MobileExplorerScreen extends ConsumerStatefulWidget {
  const MobileExplorerScreen({super.key});

  @override
  ConsumerState<MobileExplorerScreen> createState() =>
      _MobileExplorerScreenState();
}

class _MobileExplorerScreenState extends ConsumerState<MobileExplorerScreen> {
  final _customController = TextEditingController();
  final _customFocusNode = FocusNode();
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
    _customFocusNode.dispose();
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
      log('MobileExplorerScreen._submit: ERROR: $e\n$st');
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

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: context.l10n.settingsExplorerTitle,
              onBack: _isSubmitting ? null : () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  kMobilePageMargin,
                  AppSpacing.xs,
                  kMobilePageMargin,
                  AppSpacing.lg,
                ),
                children: [
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
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ExplorerOptionCard(
                    key: const ValueKey('mobile_explorer_option_zecblock'),
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
                      key: const ValueKey(
                        'mobile_explorer_option_zecblock_private',
                      ),
                      iconName: AppIcons.eyeClosed,
                      label: kZecBlockPrivateExplorerLabel,
                      subtitle: context.l10n.settingsExplorerPrivateSubtitle,
                      selected: _choice == ZcashExplorerChoice.zecBlockPrivate,
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
                    key: const ValueKey('mobile_explorer_option_custom'),
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
                    MobileTextField(
                      key: const ValueKey('mobile_explorer_custom_field_shell'),
                      fieldKey: const ValueKey('mobile_explorer_custom_field'),
                      hintText:
                          'https://explorer.example/tx/{txid}', // l10n-ignore: URL template
                      controller: _customController,
                      focusNode: _customFocusNode,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _submitError = null),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (customMessage != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        customMessage,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.settingsExplorerTemplateHint(
                        '{txid}', // l10n-ignore: URL placeholder token
                        '{txHash}', // l10n-ignore: URL placeholder token
                      ),
                      style: AppTypography.bodyMedium.copyWith(
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _choice == ZcashExplorerChoice.zecBlockPrivate
                        ? context.l10n.settingsExplorerPrivateCopy
                        : context.l10n.settingsExplorerPrivacyCopy,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
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
                      key: const ValueKey('mobile_explorer_update'),
                      minWidth: 226,
                      onPressed: _canUpdate(current) ? _submit : null,
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
          ],
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
  Widget build(BuildContext context) => MobileRadioCard(
    iconName: iconName,
    title: label,
    details: [subtitle],
    semanticsLabel: '$label, $subtitle', // l10n-ignore: joins two labels
    selected: selected,
    onTap: onTap,
  );
}
