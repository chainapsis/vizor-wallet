import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import 'import_split_view.dart';

class ImportSecretPassphraseScreen extends ConsumerStatefulWidget {
  const ImportSecretPassphraseScreen({super.key});

  @override
  ConsumerState<ImportSecretPassphraseScreen> createState() =>
      _ImportSecretPassphraseScreenState();
}

class _ImportSecretPassphraseScreenState
    extends ConsumerState<ImportSecretPassphraseScreen> {
  static const _wordCount = 24;
  static const _gridWidth = 588.0;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  bool _isSubmitting = false;
  bool _showValidationError = false;
  bool _isApplyingProgrammaticChange = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_wordCount, (_) => TextEditingController());
    _focusNodes = List.generate(_wordCount, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  List<String> get _normalizedWords => _controllers
      .map((controller) => controller.text.trim().toLowerCase())
      .toList();

  String get _mnemonic => _normalizedWords.join(' ');

  bool get _hasAllWords => _normalizedWords.every((word) => word.isNotEmpty);

  bool get _isMnemonicValid =>
      _hasAllWords && rust_wallet.validateMnemonic(mnemonic: _mnemonic);

  bool get _canSubmit => !_isSubmitting && _isMnemonicValid;

  String? get _errorText {
    if (_submitError != null) return _submitError;
    if (_showValidationError && !_isMnemonicValid) {
      return 'Please enter a valid 24-word secret passphrase.';
    }
    return null;
  }

  void _setControllerText(int index, String text) {
    final controller = _controllers[index];
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _focusIndex(int index) {
    if (index < 0 || index >= _focusNodes.length) return;
    _focusNodes[index].requestFocus();
  }

  void _handleWordChanged(int index, String rawValue) {
    if (_isApplyingProgrammaticChange) return;

    final normalized = rawValue.toLowerCase();
    final words = normalized
        .split(RegExp(r'\s+'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.length > 1) {
      _isApplyingProgrammaticChange = true;
      for (var i = 0; i < words.length; i++) {
        final targetIndex = index + i;
        if (targetIndex >= _controllers.length) break;
        _setControllerText(targetIndex, words[i]);
      }
      _isApplyingProgrammaticChange = false;
      final nextIndex = (index + words.length).clamp(
        0,
        _controllers.length - 1,
      );
      if (nextIndex < _controllers.length &&
          _controllers[nextIndex].text.trim().isEmpty) {
        _focusIndex(nextIndex);
      }
    } else {
      final trimmed = normalized.trim();
      if (rawValue != trimmed) {
        _isApplyingProgrammaticChange = true;
        _setControllerText(index, trimmed);
        _isApplyingProgrammaticChange = false;
      }
      if (rawValue.endsWith(' ') &&
          trimmed.isNotEmpty &&
          index < _wordCount - 1) {
        _focusIndex(index + 1);
      }
    }

    if (mounted) {
      setState(() {
        _submitError = null;
        if (_showValidationError && _isMnemonicValid) {
          _showValidationError = false;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      setState(() {
        _showValidationError = true;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _showValidationError = false;
    });

    try {
      // Temporary until the dedicated birthday-height step lands.
      await ref
          .read(accountProvider.notifier)
          .importAccount(mnemonic: _mnemonic);
    } catch (e, st) {
      log('ImportSecretPassphraseScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
      return;
    }

    if (!mounted) return;
    context.go('/home');
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final security = ref.watch(appSecurityProvider);

    return ImportOnboardingShell(
      activeStep: ImportOnboardingStep.secretPassphrase,
      showPasswordStep: !security.isPasswordConfigured,
      child: ImportOnboardingTrailingPane(
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleBack,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          AppIcons.chevronBackward,
                          size: AppIconSize.medium,
                          color: colors.text.accent,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'Back',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s,
                        ),
                        child: SingleChildScrollView(
                          child: SizedBox(
                            width: 640,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Welcome, Adventurer',
                                  style: AppTypography.displaySmall.copyWith(
                                    color: colors.text.accent,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: AppSpacing.s),
                                Text(
                                  'Import your wallet by entering your Secret Passphrase.',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: colors.text.accent,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: AppSpacing.s),
                                const AppDecorativeDivider(width: 256),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: _gridWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.s,
                                    ),
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: AppSpacing.xs,
                                      runSpacing: AppSpacing.xs,
                                      children: List.generate(
                                        _wordCount,
                                        (index) => _MnemonicWordCell(
                                          index: index,
                                          controller: _controllers[index],
                                          focusNode: _focusNodes[index],
                                          destructive:
                                              _showValidationError &&
                                              _controllers[index].text
                                                  .trim()
                                                  .isNotEmpty,
                                          autofocus: index == 0,
                                          onChanged: (value) =>
                                              _handleWordChanged(index, value),
                                          onSubmitted: (_) {
                                            if (index == _wordCount - 1) {
                                              _submit();
                                            } else {
                                              _focusIndex(index + 1);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_errorText != null) ...[
                                  const SizedBox(height: AppSpacing.s),
                                  Text(
                                    _errorText!,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: colors.text.warning,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AppButton(
                    onPressed: _canSubmit ? _submit : null,
                    minWidth: 256,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: Text(_isSubmitting ? 'Importing...' : 'Import'),
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

class _MnemonicWordCell extends StatefulWidget {
  const _MnemonicWordCell({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    this.destructive = false,
    this.autofocus = false,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool destructive;
  final bool autofocus;

  @override
  State<_MnemonicWordCell> createState() => _MnemonicWordCellState();
}

class _MnemonicWordCellState extends State<_MnemonicWordCell> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _MnemonicWordCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isFocused = widget.focusNode.hasFocus;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final borderColor = widget.destructive
        ? colors.border.utilityDestructive
        : isFocused
        ? colors.border.strong
        : colors.border.subtle;
    final focusRingColor = widget.destructive
        ? colors.border.utilityDestructive
        : colors.state.focusRing;

    final numberColor = widget.destructive
        ? colors.text.warning
        : hasText || isFocused
        ? colors.text.accent
        : colors.text.secondary;

    return SizedBox(
      width: 120,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.focusNode.requestFocus,
          child: SizedBox(
            height: 36,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (isFocused)
                  Positioned(
                    left: -2.5,
                    top: -2.5,
                    right: -2.5,
                    bottom: -2.5,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: focusRingColor,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.input,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      border: Border.all(
                        color: borderColor,
                        width: hasText || isFocused || widget.destructive
                            ? 1.5
                            : 1,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: _hovered && !isFocused && !widget.destructive
                        ? 1
                        : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.state.hover,
                        borderRadius: BorderRadius.circular(AppRadii.small),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${widget.index + 1}'.padLeft(2, '0'),
                            style: AppTypography.codeMedium.copyWith(
                              fontSize: 14,
                              height: 21 / 14,
                              color: numberColor,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: Center(
                            child: TextField(
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              autofocus: widget.autofocus,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              enableSuggestions: false,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[A-Za-z\s]'),
                                ),
                              ],
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.accent,
                              ),
                              cursorColor: colors.text.accent,
                              decoration: InputDecoration.collapsed(
                                hintText: 'Word',
                                hintStyle: AppTypography.labelLarge.copyWith(
                                  color: colors.text.muted,
                                ),
                              ),
                              onChanged: widget.onChanged,
                              onSubmitted: widget.onSubmitted,
                            ),
                          ),
                        ),
                      ),
                    ],
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
