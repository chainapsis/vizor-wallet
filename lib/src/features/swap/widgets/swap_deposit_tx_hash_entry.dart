import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_tappable.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/mobile_text_field.dart';
import '../models/swap_models.dart';
import '../providers/swap_state_provider.dart';

/// The quiet offer under a claimed external deposit NEAR Intents has not
/// seen yet (see [SwapIntent.canAddUserDepositTxHash]).
class SwapDepositTxHashPrompt extends StatelessWidget {
  const SwapDepositTxHashPrompt({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    widthFactor: 1,
    child: IntrinsicWidth(
      child: Semantics(
        button: true,
        child: AppButton(
          key: const ValueKey('swap_deposit_tx_hash_prompt'),
          onPressed: onTap,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.large,
          height: kAppFormFactor == AppFormFactor.mobile
              ? AppButtonSizing.largeHeight
              : 36,
          growWithContent: true,
          constrainContent: true,
          trailing: const AppIcon(
            AppIcons.arrowForwardIos,
            size: AppIconSize.medium,
          ),
          child: Text(context.l10n.swapDepositTxHashPrompt),
        ),
      ),
    ),
  );
}

/// Takes the hash of the deposit the user sent from another wallet: a sheet
/// on mobile, a pane modal on desktop. Only a hash of the deposit's chain is
/// sent, and the swap keeps it apart from deposit evidence.
class SwapDepositTxHashEntry extends ConsumerStatefulWidget {
  const SwapDepositTxHashEntry({required this.intent, this.onClose, super.key});

  final SwapIntent intent;

  /// Closes the entry; by default it pops its sheet.
  final VoidCallback? onClose;

  @override
  ConsumerState<SwapDepositTxHashEntry> createState() =>
      _SwapDepositTxHashEntryState();
}

class _SwapDepositTxHashEntryState
    extends ConsumerState<SwapDepositTxHashEntry> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;
  bool _failed = false;

  bool get _mobile => kAppFormFactor == AppFormFactor.mobile;

  @override
  void initState() {
    super.initState();
    if (_mobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusWhenMobileSheetOpens(context, _focusNode);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _changed() {
    setState(() => _failed = false);
  }

  // Reads the clipboard only when asked.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (pasted.isEmpty || !mounted) return;
    _controller.value = TextEditingValue(
      text: pasted,
      selection: TextSelection.collapsed(offset: pasted.length),
    );
    _changed();
  }

  Future<void> _submit() async {
    if (_submitting || _controller.text.trim().isEmpty) return;
    setState(() {
      _submitting = true;
      _failed = false;
    });
    final result = await ref
        .read(swapStateProvider.notifier)
        .submitUserDepositTxHash(
          intentId: widget.intent.id,
          txHash: _controller.text,
        );
    if (!mounted) return;
    if (result == SwapUserDepositTxHashResult.submitted) {
      _close();
      return;
    }
    setState(() {
      _submitting = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final mobile = _mobile;
    final intent = widget.intent;
    final asset = intent.externalAsset;
    final symbol = asset == null
        ? ''
        : (intent.direction ?? SwapDirection.externalToZec).fromSymbol(asset);
    final hasText = _controller.text.trim().isNotEmpty;
    final error = _failed ? l10n.swapFailureDepositRejected : null;

    final paste = AppTappable(
      key: const ValueKey('swap_deposit_tx_hash_paste'),
      onTap: _submitting ? null : _paste,
      semanticsLabel: l10n.swapDepositTxHashPaste,
      child: SizedBox.square(
        dimension: AppInputSizing.iconSize,
        child: AppIcon(
          AppIcons.paste,
          size: AppInputSizing.iconSize,
          color: _submitting ? colors.icon.muted : colors.icon.accent,
        ),
      ),
    );
    // Hashes are compared character by character, and the keyboard should
    // neither suggest nor learn them.
    final hashStyle =
        (mobile ? AppTypography.codeMedium : AppTypography.codeSmall).copyWith(
          color: colors.text.accent,
        );
    final field = mobile
        ? MobileTextField(
            fieldKey: const ValueKey('swap_deposit_tx_hash_field'),
            controller: _controller,
            focusNode: _focusNode,
            hintText: l10n.swapDepositTxHashHint(symbol),
            enabled: !_submitting,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => _changed(),
            onSubmitted: (_) => _submit(),
            textStyle: hashStyle,
            trailing: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: paste,
            ),
          )
        : AppTextField(
            key: const ValueKey('swap_deposit_tx_hash_field'),
            label: l10n.swapDepositTxHashTitle,
            showLabel: false,
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            hintText: l10n.swapDepositTxHashHint(symbol),
            enabled: !_submitting,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => _changed(),
            onSubmitted: (_) => _submit(),
            textStyle: hashStyle,
            trailing: paste,
          );

    final content = Column(
      key: const ValueKey('swap_deposit_tx_hash_entry'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!mobile) ...[
          Text(
            l10n.swapDepositTxHashTitle,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          l10n.swapDepositTxHashBody(symbol),
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        field,
        if (error != null) ...[
          const SizedBox(height: AppSpacing.s),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              key: const ValueKey('swap_deposit_tx_hash_error'),
              style:
                  (mobile ? AppTypography.labelLarge : AppTypography.bodySmall)
                      .copyWith(color: colors.text.destructive),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('swap_deposit_tx_hash_submit'),
          expand: true,
          size: mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
          height: mobile ? null : kAppModalButtonHeight,
          onPressed: hasText && !_submitting ? _submit : null,
          trailing: _submitting ? const AppIcon(AppIcons.loader) : null,
          child: Text(
            _submitting
                ? l10n.swapDepositChecking
                : l10n.swapDepositTxHashSubmit,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('swap_deposit_tx_hash_cancel'),
          expand: true,
          variant: AppButtonVariant.ghost,
          size: mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
          height: mobile ? null : kAppModalButtonHeight,
          onPressed: _close,
          child: Text(l10n.commonCancel),
        ),
      ],
    );
    return mobile
        ? MobileModalScaffold(
            title: l10n.swapDepositTxHashTitle,
            titleMaxLines: 2,
            onClose: _close,
            child: content,
          )
        : AppModalCard(child: SingleChildScrollView(child: content));
  }
}
