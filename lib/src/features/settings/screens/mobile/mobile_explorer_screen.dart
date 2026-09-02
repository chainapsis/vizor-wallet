import 'package:flutter/material.dart' show Scaffold, TextInputType;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/zcash_explorer_provider.dart';

enum _ExplorerChoice { cipherscan, custom }

/// Mobile explorer settings — CipherScan by default, or a user-owned
/// instance so opening a transaction does not reveal the signer's IP
/// to a public explorer.
class MobileExplorerScreen extends ConsumerStatefulWidget {
  const MobileExplorerScreen({super.key});

  @override
  ConsumerState<MobileExplorerScreen> createState() =>
      _MobileExplorerScreenState();
}

class _MobileExplorerScreenState extends ConsumerState<MobileExplorerScreen> {
  final _customController = TextEditingController();
  final _customFocusNode = FocusNode();
  late _ExplorerChoice _choice;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final current = ref.read(zcashExplorerProvider);
    _choice = current.trim().isEmpty
        ? _ExplorerChoice.cipherscan
        : _ExplorerChoice.custom;
    if (_choice == _ExplorerChoice.custom) {
      _customController.text = current;
    }
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
      _ExplorerChoice.cipherscan => current.trim().isNotEmpty,
      _ExplorerChoice.custom => _customTemplateChanged(current),
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
    if (_choice != _ExplorerChoice.custom) return null;
    if (_customController.text.trim().isEmpty) return null;
    try {
      normalizeExplorerUrlTemplate(_customController.text);
      return null;
    } on FormatException catch (e) {
      return e.message;
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
      if (_choice == _ExplorerChoice.cipherscan) {
        await notifier.resetToDefault();
      } else {
        await notifier.setCustom(_customController.text);
      }
      if (!mounted) return;
      final next = ref.read(zcashExplorerProvider);
      setState(() {
        _customController.text = next;
        _isSubmitting = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('MobileExplorerScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't save that explorer URL.";
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

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Explorer',
              onBack: _isSubmitting ? null : () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                children: [
                  Text(
                    current.trim().isEmpty
                        ? 'Current: ${defaultZcashExplorerHost(networkName)} (default)'
                        : 'Current: ${explorerSettingsLabel(current, networkName: networkName)}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ExplorerOptionCard(
                    key: const ValueKey('mobile_explorer_option_cipherscan'),
                    iconName: AppIcons.globe,
                    label: kDefaultZcashExplorerLabel,
                    subtitle: defaultZcashExplorerHost(networkName),
                    selected: _choice == _ExplorerChoice.cipherscan,
                    onTap: _isSubmitting
                        ? null
                        : () => setState(() {
                            _choice = _ExplorerChoice.cipherscan;
                            _submitError = null;
                          }),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ExplorerOptionCard(
                    key: const ValueKey('mobile_explorer_option_custom'),
                    iconName: AppIcons.edit,
                    label: 'Custom',
                    subtitle: 'Your own instance',
                    selected: _choice == _ExplorerChoice.custom,
                    onTap: _isSubmitting
                        ? null
                        : () => setState(() {
                            _choice = _ExplorerChoice.custom;
                            _submitError = null;
                            if (_customController.text.trim().isEmpty &&
                                current.trim().isNotEmpty) {
                              _customController.text = current;
                            }
                          }),
                  ),
                  if (_choice == _ExplorerChoice.custom) ...[
                    const SizedBox(height: AppSpacing.md),
                    MobileTextField(
                      key: const ValueKey('mobile_explorer_custom_field_shell'),
                      fieldKey: const ValueKey('mobile_explorer_custom_field'),
                      hintText: 'https://explorer.example/tx/{txid}',
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
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      kZcashExplorerTemplateHint,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppIcon(AppIcons.book, size: 20, color: colors.icon.accent),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    kZcashExplorerPrivacyCopy,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _submitError!,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.destructive,
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
                        _isSubmitting ? 'Updating...' : 'Update explorer',
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.subtle,
              width: selected ? 1.5 : 1,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.background.inverse,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.check,
                      size: 14,
                      color: colors.text.inverse,
                    ),
                  ),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.raised,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
