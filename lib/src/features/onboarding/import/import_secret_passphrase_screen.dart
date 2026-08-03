import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Color,
        InputDecoration,
        Scrollbar,
        ScrollbarTheme,
        ScrollbarThemeData,
        TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/onboarding_flow_args.dart';
import 'import_split_view.dart';

const _kBip39PassphraseMaxCharacters = 100;

bool _isValidBip39Passphrase(String value) {
  final length = value.characters.length;
  return length > 0 && length <= _kBip39PassphraseMaxCharacters;
}

class ImportSecretPassphraseScreen extends ConsumerStatefulWidget {
  const ImportSecretPassphraseScreen({
    this.args,
    this.privacyOverlayController,
    this.wordListOverride,
    this.mnemonicValidatorOverride,
    this.initialBip39PassphraseModalOpen = false,
    this.useEnvironmentPrivacySignals = true,
    super.key,
  });

  final ImportSecretPassphraseArgs? args;
  final SensitivePrivacyOverlayController? privacyOverlayController;
  final List<String>? wordListOverride;
  final bool Function(String mnemonic)? mnemonicValidatorOverride;
  final bool initialBip39PassphraseModalOpen;
  final bool useEnvironmentPrivacySignals;

  @override
  ConsumerState<ImportSecretPassphraseScreen> createState() =>
      _ImportSecretPassphraseScreenState();
}

class _ImportSecretPassphraseScreenState
    extends ConsumerState<ImportSecretPassphraseScreen> {
  static const _minImportWordCount = 12;
  static const _wordCountStep = 3;
  static const _wordCount = 24;
  static const _contentWidth = 396.0;
  static const _passphraseHeight = 428.0;
  static const _contentToButtonGap = AppSpacing.md;
  static const _titleTop = 17.0;
  static const _passphraseTop = 128.0;
  static const _onPageContentHeight =
      _passphraseTop + _passphraseHeight + _contentToButtonGap;
  static const _buttonHeight = 44.0;
  static const _layoutHeight = _onPageContentHeight + _buttonHeight;
  static const _referenceLayoutSlack = AppSpacing.sm;
  static const _referenceContentHeight = _layoutHeight + _referenceLayoutSlack;
  static const _scrollBottomPadding = AppSpacing.base;
  static const _gridWidth = 396.0;
  static const _subtitleWidth = 226.0;
  static const _buttonWidth = 230.0;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final List<String> _mnemonicWordList;
  late final TextEditingController _bip39PassphraseController;
  late SensitivePrivacyOverlayController _privacyOverlayController;
  late bool _ownsPrivacyOverlayController;
  ScrollController? _bodyScrollController;

  bool _isSubmitting = false;
  bool _showValidationError = false;
  bool _isApplyingProgrammaticChange = false;
  bool _autocompleteSuppressedForPrivacy = false;
  bool _isBip39PassphraseModalOpen = false;
  String _bip39Passphrase = '';
  String? _submitError;

  ScrollController get _effectiveBodyScrollController =>
      _bodyScrollController ??= ScrollController();

  @override
  void initState() {
    super.initState();
    _mnemonicWordList =
        widget.wordListOverride ?? rust_wallet.mnemonicWordList();
    _controllers = List.generate(_wordCount, (_) => TextEditingController());
    _focusNodes = List.generate(_wordCount, (_) => FocusNode());
    _bip39Passphrase = widget.args?.bip39Passphrase ?? '';
    _bip39PassphraseController = TextEditingController(text: _bip39Passphrase);
    _isBip39PassphraseModalOpen = widget.initialBip39PassphraseModalOpen;
    _setPrivacyOverlayController(widget.privacyOverlayController);
    _restoreMnemonic();
  }

  @override
  void didUpdateWidget(covariant ImportSecretPassphraseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.privacyOverlayController != widget.privacyOverlayController) {
      _privacyOverlayController.removeListener(_handlePrivacySafetyChanged);
      if (_ownsPrivacyOverlayController) {
        _privacyOverlayController.dispose();
      }
      _setPrivacyOverlayController(widget.privacyOverlayController);
    }
  }

  @override
  void dispose() {
    _privacyOverlayController.removeListener(_handlePrivacySafetyChanged);
    if (_ownsPrivacyOverlayController) {
      _privacyOverlayController.dispose();
    }
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _bip39PassphraseController.dispose();
    _bodyScrollController?.dispose();
    super.dispose();
  }

  List<String> get _normalizedWords => _controllers
      .map((controller) => controller.text.trim().toLowerCase())
      .toList();

  List<String> get _enteredWordCells {
    final words = _normalizedWords;
    final lastEnteredIndex = words.lastIndexWhere((word) => word.isNotEmpty);
    if (lastEnteredIndex < 0) return const [];
    return words.take(lastEnteredIndex + 1).toList();
  }

  String get _mnemonic => _enteredWordCells.join(' ');

  bool get _hasContiguousMnemonicWords =>
      _enteredWordCells.every((word) => word.isNotEmpty);

  bool get _hasSupportedMnemonicWordCount {
    final count = _enteredWordCells.length;
    return count >= _minImportWordCount &&
        count <= _wordCount &&
        count % _wordCountStep == 0;
  }

  bool get _hasEnteredMnemonicWords =>
      _controllers.any((controller) => controller.text.trim().isNotEmpty);

  bool get _hasSensitiveImportMaterial =>
      _hasEnteredMnemonicWords ||
      _bip39Passphrase.isNotEmpty ||
      (_isBip39PassphraseModalOpen &&
          _bip39PassphraseController.text.isNotEmpty);

  bool get _isMnemonicValid =>
      _hasContiguousMnemonicWords &&
      _hasSupportedMnemonicWordCount &&
      (widget.mnemonicValidatorOverride?.call(_mnemonic) ??
          rust_wallet.validateMnemonic(mnemonic: _mnemonic));

  bool get _canSubmit => !_isSubmitting && _isMnemonicValid;

  bool get _autocompleteEnabled =>
      _privacyOverlayController.isSafe && !_autocompleteSuppressedForPrivacy;

  void _setPrivacyOverlayController(
    SensitivePrivacyOverlayController? controller,
  ) {
    _ownsPrivacyOverlayController = controller == null;
    _privacyOverlayController =
        controller ??
        (widget.useEnvironmentPrivacySignals
            ? SensitivePrivacyEnvironmentController()
            : SensitivePrivacyOverlayController());
    _privacyOverlayController.addListener(_handlePrivacySafetyChanged);
  }

  void _handlePrivacySafetyChanged() {
    if (!_privacyOverlayController.isSafe) {
      _suppressAutocompleteForPrivacy();
      return;
    }
    if (mounted) setState(() {});
  }

  void _suppressAutocompleteForPrivacy() {
    if (!mounted) {
      _autocompleteSuppressedForPrivacy = true;
      return;
    }

    setState(() {
      _autocompleteSuppressedForPrivacy = true;
    });
    for (final controller in _controllers) {
      _refreshAutocompleteOptions(controller);
    }
  }

  void _reactivateAutocomplete(TextEditingController controller) {
    if (!_privacyOverlayController.isSafe ||
        !_autocompleteSuppressedForPrivacy) {
      return;
    }
    setState(() {
      _autocompleteSuppressedForPrivacy = false;
    });
    _refreshAutocompleteOptions(controller);
  }

  void _refreshAutocompleteOptions(TextEditingController controller) {
    final value = controller.value;
    final text = value.text;
    if (text.isEmpty) return;

    // RawAutocomplete only recomputes options when the text value changes.
    controller.value = value.copyWith(
      text: '$text ',
      selection: TextSelection.collapsed(offset: text.length + 1),
      composing: TextRange.empty,
    );
    controller.value = value;
  }

  void _restoreMnemonic() {
    final mnemonic = widget.args?.mnemonic;
    if (mnemonic == null || mnemonic.trim().isEmpty) return;

    final words = mnemonic
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(_wordCount)
        .toList();

    _isApplyingProgrammaticChange = true;
    for (var index = 0; index < _controllers.length; index++) {
      final text = index < words.length ? words[index] : '';
      _setControllerText(index, text);
    }
    _isApplyingProgrammaticChange = false;
  }

  String? get _errorText {
    if (_submitError != null) return _submitError;
    if (_showValidationError && !_isMnemonicValid) {
      // Deliberately diverges from the Figma copy ('Some words are
      // incorrect'): the word-count guidance is more actionable.
      return 'Enter a valid secret passphrase with 12, 15, 18, 21, or 24 words.';
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

  bool _moveToNextWord(int index) {
    if (index >= _wordCount - 1) return false;
    _focusIndex(index + 1);
    return true;
  }

  bool _moveToPreviousWord(int index) {
    if (index <= 0) return false;
    _focusIndex(index - 1);
    return true;
  }

  void _handleSuggestionSelected(int index, String word) {
    _isApplyingProgrammaticChange = true;
    _setControllerText(index, word.toLowerCase());
    _isApplyingProgrammaticChange = false;

    if (mounted) {
      setState(() {
        _submitError = null;
        if (_showValidationError && _isMnemonicValid) {
          _showValidationError = false;
        }
      });
    }

    _moveToNextWord(index);
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

  void _clearImportDraft() {
    _isApplyingProgrammaticChange = true;
    for (var index = 0; index < _controllers.length; index++) {
      _setControllerText(index, '');
    }
    _isApplyingProgrammaticChange = false;
    _bip39PassphraseController.clear();
    setState(() {
      _bip39Passphrase = '';
      _isBip39PassphraseModalOpen = false;
      _showValidationError = false;
      _submitError = null;
    });
    _focusIndex(0);
  }

  void _openBip39PassphraseModal() {
    _bip39PassphraseController.text = _bip39Passphrase;
    _bip39PassphraseController.selection = TextSelection.collapsed(
      offset: _bip39PassphraseController.text.length,
    );
    setState(() => _isBip39PassphraseModalOpen = true);
  }

  void _cancelBip39PassphraseModal() {
    _bip39PassphraseController.text = _bip39Passphrase;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isBip39PassphraseModalOpen = false);
  }

  void _saveBip39Passphrase() {
    final passphrase = _bip39PassphraseController.text;
    if (!_isValidBip39Passphrase(passphrase)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _bip39Passphrase = passphrase;
      _isBip39PassphraseModalOpen = false;
    });
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

    if (!mounted) return;
    context.go(
      '/import/birthday',
      extra: ImportBirthdayArgs(
        mnemonic: _mnemonic,
        bip39Passphrase: _bip39Passphrase,
      ),
    );
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

    return ImportOnboardingTrailingPane(
      backTarget: OnboardingBackTarget.callback(
        label: 'Welcome',
        onTap: _handleBack,
      ),
      overlay: SensitivePrivacyOverlay(
        sensitiveContentVisible: _hasSensitiveImportMaterial,
        controller: _privacyOverlayController,
        borderRadius: BorderRadius.circular(
          AppDesktopSidebarSurface.glassRadius,
        ),
        child: Stack(
          children: [
            if (_isBip39PassphraseModalOpen)
              AppPaneModalOverlay(
                onDismiss: _cancelBip39PassphraseModal,
                child: _Bip39PassphraseModal(
                  controller: _bip39PassphraseController,
                  isEditing: _bip39Passphrase.isNotEmpty,
                  onChanged: (_) => setState(() {}),
                  onCancel: _cancelBip39PassphraseModal,
                  onSave: _saveBip39Passphrase,
                ),
              ),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needsScrolling = constraints.maxHeight < _layoutHeight;
          final contentHeight = needsScrolling
              ? _layoutHeight + _scrollBottomPadding
              : constraints.maxHeight;
          final scrollController = _effectiveBodyScrollController;

          Widget buildContent(double height) {
            final useExpandedLayout =
                !needsScrolling && height > _referenceContentHeight;
            final buttonTop = useExpandedLayout
                ? height - _buttonHeight
                : _onPageContentHeight;
            final mainTop = useExpandedLayout
                ? (buttonTop - _onPageContentHeight) / 2
                : 0.0;

            return SizedBox(
              width: _contentWidth,
              height: height,
              child: Stack(
                children: [
                  Positioned(
                    top: mainTop,
                    left: 0,
                    right: 0,
                    height: _onPageContentHeight,
                    child: Stack(
                      children: [
                        Positioned(
                          top: _titleTop,
                          left: 0,
                          right: 0,
                          child: _ImportSecretTitle(
                            textColor: colors.text.accent,
                          ),
                        ),
                        Positioned(
                          top: _passphraseTop,
                          left: 0,
                          right: 0,
                          child: _ImportSecretPassphraseGrid(
                            controllers: _controllers,
                            focusNodes: _focusNodes,
                            wordList: _mnemonicWordList,
                            autocompleteEnabled: () => _autocompleteEnabled,
                            onAutocompleteReactivationRequested: (index) =>
                                _reactivateAutocomplete(_controllers[index]),
                            onMoveNext: _moveToNextWord,
                            onMovePrevious: _moveToPreviousWord,
                            onSuggestionSelected: _handleSuggestionSelected,
                            onChanged: _handleWordChanged,
                            onSubmitted: (index) {
                              if (index == _wordCount - 1) {
                                _submit();
                              } else {
                                _moveToNextWord(index);
                              }
                            },
                            showClear:
                                _hasEnteredMnemonicWords ||
                                _bip39Passphrase.isNotEmpty,
                            bip39Passphrase: _bip39Passphrase,
                            onClear: _clearImportDraft,
                            onOpenBip39Passphrase: _openBip39PassphraseModal,
                          ),
                        ),
                        if (_errorText != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Text(
                              _errorText!,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.destructive,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: buttonTop,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AppButton(
                        key: const ValueKey('import_secret_submit_button'),
                        onPressed: _canSubmit ? _submit : null,
                        minWidth: _buttonWidth,
                        child: Text(
                          _isSubmitting ? 'Importing...' : 'Continue',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Scrollbar(
            controller: scrollController,
            thumbVisibility: needsScrolling,
            child: SingleChildScrollView(
              controller: scrollController,
              physics: needsScrolling
                  ? null
                  : const NeverScrollableScrollPhysics(),
              child: Align(
                alignment: Alignment.topCenter,
                child: buildContent(contentHeight),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImportSecretTitle extends StatelessWidget {
  const _ImportSecretTitle({required this.textColor});

  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Import a Wallet',
            style: AppTypography.displayLarge.copyWith(color: textColor),
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: _ImportSecretPassphraseScreenState._subtitleWidth,
          child: Text(
            'Accept 12, 15, 18, 21, or 24 words.',
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ImportSecretPassphraseGrid extends StatelessWidget {
  const _ImportSecretPassphraseGrid({
    required this.controllers,
    required this.focusNodes,
    required this.wordList,
    required this.autocompleteEnabled,
    required this.onAutocompleteReactivationRequested,
    required this.onMoveNext,
    required this.onMovePrevious,
    required this.onSuggestionSelected,
    required this.onChanged,
    required this.onSubmitted,
    required this.showClear,
    required this.bip39Passphrase,
    required this.onClear,
    required this.onOpenBip39Passphrase,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final List<String> wordList;
  final bool Function() autocompleteEnabled;
  final ValueChanged<int> onAutocompleteReactivationRequested;
  final bool Function(int index) onMoveNext;
  final bool Function(int index) onMovePrevious;
  final void Function(int index, String word) onSuggestionSelected;
  final void Function(int index, String value) onChanged;
  final ValueChanged<int> onSubmitted;
  final bool showClear;
  final String bip39Passphrase;
  final VoidCallback onClear;
  final VoidCallback onOpenBip39Passphrase;

  @override
  Widget build(BuildContext context) {
    final wordSet = wordList.toSet();

    final colors = context.colors;
    final hasBip39Passphrase = bip39Passphrase.isNotEmpty;

    Widget buildCell(int index) => _MnemonicWordCell(
      index: index,
      controller: controllers[index],
      focusNode: focusNodes[index],
      wordList: wordList,
      wordSet: wordSet,
      autocompleteEnabled: autocompleteEnabled,
      onAutocompleteReactivationRequested: () =>
          onAutocompleteReactivationRequested(index),
      autofocus: index == 0,
      onMoveNext: () => onMoveNext(index),
      onMovePrevious: () => onMovePrevious(index),
      onSuggestionSelected: (word) => onSuggestionSelected(index, word),
      onChanged: (value) => onChanged(index, value),
      onSubmitted: () => onSubmitted(index),
    );

    return SizedBox(
      width: _ImportSecretPassphraseScreenState._gridWidth,
      height: _ImportSecretPassphraseScreenState._passphraseHeight,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 96,
            child: hasBip39Passphrase
                ? _SavedBip39PassphraseFooter(
                    passphrase: bip39Passphrase,
                    onPressed: onOpenBip39Passphrase,
                  )
                : CustomPaint(
                    painter: _DashedPassphraseFooterPainter(
                      color: colors.border.subtle,
                      radius: AppRadii.large,
                    ),
                    child: Semantics(
                      button: true,
                      label: 'Add BIP39 passphrase',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          key: const ValueKey('bip39_passphrase_action'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onOpenBip39Passphrase,
                          child: Align(
                            alignment: const Alignment(0, 0.42),
                            child: Text(
                              'Add BIP39 Passphrase (Optional)',
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 376,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.homeCard,
                borderRadius: BorderRadius.circular(AppRadii.large),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  children: [
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Secret Passphrase',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.headlineSmall.copyWith(
                                color: colors.text.homeCard,
                              ),
                            ),
                          ),
                          if (showClear)
                            _ClearMnemonicButton(onPressed: onClear),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var columnIndex = 0;
                            columnIndex < 3;
                            columnIndex++
                          ) ...[
                            Expanded(
                              child: Column(
                                children: List.generate(8, (rowIndex) {
                                  final index = columnIndex * 8 + rowIndex;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: rowIndex == 7 ? 0 : 4,
                                    ),
                                    child: buildCell(index),
                                  );
                                }),
                              ),
                            ),
                            if (columnIndex < 2) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedBip39PassphraseFooter extends StatelessWidget {
  const _SavedBip39PassphraseFooter({
    required this.passphrase,
    required this.onPressed,
  });

  final String passphrase;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Edit BIP39 passphrase',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('bip39_passphrase_action'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(AppRadii.large),
                bottomRight: Radius.circular(AppRadii.large),
              ),
              boxShadow: appModalShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'BIP39 Passphrase: $passphrase',
                        key: const ValueKey('bip39_passphrase_preview'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppIcon(
                      AppIcons.edit,
                      size: AppIconSize.medium,
                      color: colors.icon.accent,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Edit',
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
      ),
    );
  }
}

class _ClearMnemonicButton extends StatelessWidget {
  const _ClearMnemonicButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppButton(
      key: const ValueKey('import_mnemonic_clear_button'),
      onPressed: onPressed,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.small,
      height: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      iconGap: 4,
      enabledBackgroundColor: colors.text.homeCard.withValues(alpha: 0.12),
      pressedBackgroundColor: colors.text.homeCard.withValues(alpha: 0.18),
      enabledLabelColor: colors.text.homeCard,
      pressedLabelColor: colors.text.homeCard,
      focusRingColor: colors.text.homeCard,
      leading: AppIcon(AppIcons.trash, size: 14, color: colors.text.homeCard),
      child: const Text('Clear'),
    );
  }
}

class _Bip39PassphraseModal extends StatelessWidget {
  const _Bip39PassphraseModal({
    required this.controller,
    required this.isEditing,
    required this.onChanged,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool isEditing;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final canSave = _isValidBip39Passphrase(controller.text);
    return AppModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'BIP39 Passphrase' : 'BIP39 Passphrase (Optional)',
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          if (!isEditing) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add an optional passphrase (“25th word”) to create/import a '
              'separate wallet from the same recovery phrase.',
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          KeyedSubtree(
            key: const ValueKey('bip39_passphrase_field'),
            child: AppTextField(
              label: 'BIP39 passphrase',
              showLabel: false,
              controller: controller,
              hintText: '1–100 characters',
              minLines: 6,
              maxLines: 6,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              autocorrect: false,
              enableSuggestions: false,
              showClearButton: true,
              clearButtonSemanticLabel: 'Clear BIP39 passphrase',
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  _kBip39PassphraseMaxCharacters,
                ),
              ],
              onChanged: onChanged,
              onClear: () => onChanged(''),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppModalActions(
            cancelKey: const ValueKey('bip39_passphrase_cancel_button'),
            actionKey: const ValueKey('bip39_passphrase_save_button'),
            onCancel: onCancel,
            actionLabel: isEditing ? 'Save' : 'Add',
            onAction: canSave ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class _DashedPassphraseFooterPainter extends CustomPainter {
  const _DashedPassphraseFooterPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 5, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPassphraseFooterPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

class _MnemonicWordCell extends StatefulWidget {
  const _MnemonicWordCell({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.wordList,
    required this.wordSet,
    required this.onChanged,
    required this.onSubmitted,
    required this.onMoveNext,
    required this.onMovePrevious,
    required this.onSuggestionSelected,
    required this.autocompleteEnabled,
    required this.onAutocompleteReactivationRequested,
    this.autofocus = false,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> wordList;
  final Set<String> wordSet;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final bool Function() onMoveNext;
  final bool Function() onMovePrevious;
  final ValueChanged<String> onSuggestionSelected;
  final bool Function() autocompleteEnabled;
  final VoidCallback onAutocompleteReactivationRequested;
  final bool autofocus;

  @override
  State<_MnemonicWordCell> createState() => _MnemonicWordCellState();
}

class _MnemonicWordCellState extends State<_MnemonicWordCell> {
  static const _fieldWidth = 116.0;
  static const _fieldHeight = 33.0;
  static const _suggestionWidth = 172.0;
  static const _maxSuggestionCount = 64;

  final GlobalKey _textFieldRegionKey = GlobalKey();
  bool _hovered = false;
  Offset? _pendingShellTapGlobalPosition;

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

  bool _positionIsInsideTextFieldRegion(Offset globalPosition) {
    final context = _textFieldRegionKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final localPosition = renderObject.globalToLocal(globalPosition);
    return (Offset.zero & renderObject.size).contains(localPosition);
  }

  TextSelection _selectionForShellPointer(
    Offset globalPosition,
    TextStyle valueStyle,
  ) {
    final text = widget.controller.text;
    if (text.isEmpty) return const TextSelection.collapsed(offset: 0);

    final regionContext = _textFieldRegionKey.currentContext;
    final renderObject = regionContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return TextSelection.collapsed(offset: text.length);
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    final clampedPosition = Offset(
      localPosition.dx.clamp(0.0, renderObject.size.width),
      localPosition.dy.clamp(0.0, renderObject.size.height),
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: valueStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: renderObject.size.width);

    final position = textPainter.getPositionForOffset(clampedPosition);
    return TextSelection.collapsed(offset: position.offset);
  }

  void _handleShellTapDown(TapDownDetails details) {
    _pendingShellTapGlobalPosition = details.globalPosition;
  }

  void _requestFocusFromShell(TextStyle valueStyle) {
    final globalPosition = _pendingShellTapGlobalPosition;
    _pendingShellTapGlobalPosition = null;
    if (globalPosition == null) return;
    if (_positionIsInsideTextFieldRegion(globalPosition)) {
      widget.onAutocompleteReactivationRequested();
      return;
    }

    final selection = _selectionForShellPointer(globalPosition, valueStyle);
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }
    widget.onAutocompleteReactivationRequested();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      final offset = selection.baseOffset.clamp(
        0,
        widget.controller.text.length,
      );
      widget.controller.selection = TextSelection.collapsed(offset: offset);
    });
  }

  List<String> _optionsForText(String rawValue) {
    if (!widget.autocompleteEnabled()) return const <String>[];

    final prefix = rawValue.trim().toLowerCase();
    if (prefix.isEmpty || prefix.contains(RegExp(r'\s'))) {
      return const <String>[];
    }

    final options = <String>[];
    for (final word in widget.wordList) {
      if (!word.startsWith(prefix)) continue;
      options.add(word);
      if (options.length >= _maxSuggestionCount) break;
    }

    if (options.length == 1 && options.first == prefix) {
      return const <String>[];
    }
    return options;
  }

  Iterable<String> _buildOptions(TextEditingValue value) {
    return _optionsForText(value.text);
  }

  bool get _hasAutocompleteOptions {
    return widget.focusNode.hasFocus &&
        _optionsForText(widget.controller.text).isNotEmpty;
  }

  KeyEventResult _handleFieldKeyEvent(
    FocusNode node,
    KeyEvent event,
    VoidCallback onAutocompleteSubmitted,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _handleTextSubmitted(onAutocompleteSubmitted);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
      if (_hasAutocompleteOptions) {
        final actionContext = node.context;
        if (actionContext == null) return KeyEventResult.handled;
        Actions.invoke(
          actionContext,
          shiftPressed
              ? const AutocompletePreviousOptionIntent()
              : const AutocompleteNextOptionIntent(),
        );
      } else if (shiftPressed) {
        if (!widget.onMovePrevious()) {
          final focusContext = node.context;
          final moved = focusContext == null
              ? widget.focusNode.previousFocus()
              : FocusTraversalGroup.of(focusContext).previous(widget.focusNode);
          if (!moved || widget.focusNode.hasFocus) {
            widget.focusNode.unfocus();
          }
        }
      } else {
        if (!widget.onMoveNext()) {
          final moved = widget.focusNode.nextFocus();
          if (!moved) {
            widget.focusNode.unfocus();
          }
        }
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleTextSubmitted(VoidCallback onAutocompleteSubmitted) {
    if (_hasAutocompleteOptions) {
      onAutocompleteSubmitted();
      return;
    }
    widget.onSubmitted();
  }

  Widget _buildOptionsView(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
    Iterable<String> options,
  ) {
    final highlightedIndex = AutocompleteHighlightedOption.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: _MnemonicSuggestionPopover(
        wordIndex: widget.index,
        options: options.toList(growable: false),
        highlightedIndex: highlightedIndex,
        onSelected: onSelected,
      ),
    );
  }

  Widget _buildFieldShell(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    VoidCallback onAutocompleteSubmitted,
  ) {
    final colors = context.colors;
    final isFocused = focusNode.hasFocus;
    final enteredWord = controller.text.trim().toLowerCase();
    final hasText = enteredWord.isNotEmpty;
    final isKnownMnemonicWord = hasText && widget.wordSet.contains(enteredWord);
    final isInvalidUnfocused = hasText && !isFocused && !isKnownMnemonicWord;
    final valueStyle = AppTypography.labelLarge.copyWith(
      color: isInvalidUnfocused
          ? colors.text.destructive
          : colors.text.homeCard,
    );
    final hintStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.homeCard.withValues(alpha: 0.2),
    );
    final borderColor = isInvalidUnfocused
        ? colors.text.destructive
        : isFocused
        ? colors.text.homeCard
        : _hovered
        ? colors.text.homeCard.withValues(alpha: 0.45)
        : colors.text.homeCard.withValues(alpha: 0.22);

    final numberColor = isInvalidUnfocused
        ? colors.text.destructive
        : hasText || isFocused
        ? colors.text.homeCard.withValues(alpha: 0.72)
        : colors.text.homeCard.withValues(alpha: 0.4);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) =>
          _handleFieldKeyEvent(node, event, onAutocompleteSubmitted),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: _handleShellTapDown,
          onTap: () => _requestFocusFromShell(valueStyle),
          child: SizedBox(
            height: _fieldHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: isFocused || isInvalidUnfocused ? 1.5 : 1,
                      color: borderColor,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${widget.index + 1}'.padLeft(2, '0'),
                            maxLines: 1,
                            softWrap: false,
                            style: AppTypography.labelMedium.copyWith(
                              color: numberColor,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Center(
                          child: KeyedSubtree(
                            key: widget.index == 0
                                ? const ValueKey(
                                    'import_mnemonic_first_word_field',
                                  )
                                : null,
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (_) =>
                                  widget.onAutocompleteReactivationRequested(),
                              child: TextField(
                                key: _textFieldRegionKey,
                                controller: controller,
                                focusNode: focusNode,
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
                                style: valueStyle,
                                cursorColor: colors.text.homeCard,
                                selectAllOnFocus: false,
                                decoration: InputDecoration.collapsed(
                                  hintText: 'Seed word',
                                  hintStyle: hintStyle,
                                ),
                                onChanged: (value) {
                                  widget.onAutocompleteReactivationRequested();
                                  widget.onChanged(value);
                                },
                                onSubmitted: (_) => _handleTextSubmitted(
                                  onAutocompleteSubmitted,
                                ),
                              ),
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _fieldWidth,
      height: _fieldHeight,
      child: OverflowBox(
        minWidth: _suggestionWidth,
        maxWidth: _suggestionWidth,
        minHeight: _fieldHeight,
        maxHeight: _fieldHeight,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: _suggestionWidth,
          height: _fieldHeight,
          child: RawAutocomplete<String>(
            textEditingController: widget.controller,
            focusNode: widget.focusNode,
            displayStringForOption: (word) => word,
            optionsBuilder: _buildOptions,
            optionsViewOpenDirection: OptionsViewOpenDirection.down,
            optionsViewBuilder: _buildOptionsView,
            onSelected: widget.onSuggestionSelected,
            fieldViewBuilder:
                (context, controller, focusNode, onAutocompleteSubmitted) {
                  return Center(
                    child: SizedBox(
                      width: _fieldWidth,
                      height: _fieldHeight,
                      child: _buildFieldShell(
                        context,
                        controller,
                        focusNode,
                        onAutocompleteSubmitted,
                      ),
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }
}

class _MnemonicSuggestionPopover extends StatefulWidget {
  const _MnemonicSuggestionPopover({
    required this.wordIndex,
    required this.options,
    required this.highlightedIndex,
    required this.onSelected,
  });

  final int wordIndex;
  final List<String> options;
  final int highlightedIndex;
  final ValueChanged<String> onSelected;

  @override
  State<_MnemonicSuggestionPopover> createState() =>
      _MnemonicSuggestionPopoverState();
}

class _MnemonicSuggestionPopoverState
    extends State<_MnemonicSuggestionPopover> {
  static const _rowHeight = 32.0;
  static const _rowGap = 4.0;
  static const _visibleRows = 4;
  static const _listPadding = 4.0;
  static const _scrollbarTrackWidth = 12.0;
  static const _outerVerticalPadding = 8.0;

  final ScrollController _scrollController = ScrollController();
  bool _canScroll = false;

  @override
  void didUpdateWidget(covariant _MnemonicSuggestionPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedIndex != widget.highlightedIndex ||
        oldWidget.options.length != widget.options.length) {
      _scheduleCanScrollUpdate();
      _scheduleHighlightedOptionScroll();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleCanScrollUpdate();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCanScrollUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final nextCanScroll = _scrollController.position.maxScrollExtent > 0;
      if (_canScroll == nextCanScroll) return;
      setState(() {
        _canScroll = nextCanScroll;
      });
    });
  }

  void _scheduleHighlightedOptionScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (widget.options.isEmpty) return;
      final index = widget.highlightedIndex
          .clamp(0, widget.options.length - 1)
          .toInt();
      if (index < 0) return;

      final rowTop = _listPadding + index * (_rowHeight + _rowGap);
      final rowBottom = rowTop + _rowHeight;
      final viewportTop = _scrollController.offset;
      final viewportHeight = _scrollController.position.viewportDimension;
      final viewportBottom = viewportTop + viewportHeight;

      double? nextOffset;
      if (rowTop < viewportTop) {
        nextOffset = rowTop;
      } else if (rowBottom > viewportBottom) {
        nextOffset = rowBottom - viewportHeight;
      }

      if (nextOffset == null) return;
      _scrollController.jumpTo(
        nextOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final optionCount = widget.options.length;
    if (optionCount == 0) return const SizedBox.shrink();

    final visibleCount = optionCount < _visibleRows
        ? optionCount
        : _visibleRows;
    final gapCount = visibleCount > 0 ? visibleCount - 1 : 0;
    final listHeight =
        _listPadding * 2 + visibleCount * _rowHeight + gapCount * _rowGap;
    final popoverHeight = listHeight + _outerVerticalPadding * 2;

    return SizedBox(
      width: _MnemonicWordCellState._suggestionWidth,
      height: popoverHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: colors.border.subtle,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0F000000),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            const BoxShadow(
              color: Color(0x08000000),
              blurRadius: 12,
              offset: Offset(0, -6),
            ),
            const BoxShadow(
              color: Color(0x14000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: WidgetStatePropertyAll(
                colors.text.muted.withValues(alpha: 0.55),
              ),
              radius: const Radius.circular(AppRadii.full),
              thickness: const WidgetStatePropertyAll(6),
              mainAxisMargin: 3,
              crossAxisMargin: 3,
            ),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: _canScroll,
              child: Row(
                children: [
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(_listPadding),
                        itemCount: optionCount,
                        itemBuilder: (context, index) {
                          final option = widget.options[index];
                          final highlighted = index == widget.highlightedIndex;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == optionCount - 1 ? 0 : _rowGap,
                            ),
                            child: _MnemonicSuggestionRow(
                              wordIndex: widget.wordIndex,
                              word: option,
                              highlighted: highlighted,
                              onTap: () => widget.onSelected(option),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_canScroll) const SizedBox(width: _scrollbarTrackWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MnemonicSuggestionRow extends StatelessWidget {
  const _MnemonicSuggestionRow({
    required this.wordIndex,
    required this.word,
    required this.highlighted,
    required this.onTap,
  });

  final int wordIndex;
  final String word;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedBackgroundColor = colors.background.base;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: _MnemonicSuggestionPopoverState._rowHeight,
          decoration: BoxDecoration(
            color: highlighted ? selectedBackgroundColor : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${wordIndex + 1}'.padLeft(2, '0'),
                    style: AppTypography.codeMedium.copyWith(
                      fontSize: 14,
                      height: 21 / 14,
                      color: colors.text.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  word,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
