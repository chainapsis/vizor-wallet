import 'package:flutter/material.dart'
    show
        DropdownButton,
        DropdownButtonHideUnderline,
        DropdownMenuItem,
        Material,
        MaterialType;
import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import 'mobile_ledger_help_navigation.dart';
import 'mobile_ledger_sheet_content.dart';

enum LedgerHelpModel {
  nanoX('Ledger Nano X'), // l10n-ignore: product name
  flex('Ledger Flex'), // l10n-ignore: product name
  stax('Ledger Stax'), // l10n-ignore: product name
  nanoGen5('Ledger Nano Gen5'); // l10n-ignore: product name

  const LedgerHelpModel(this.label);
  final String label;

  static LedgerHelpModel? fromSavedModel(String? value) {
    final normalized = value
        ?.toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]'), '')
        .replaceFirst(RegExp('^ledger'), '');
    return switch (normalized) {
      'nanox' => nanoX,
      'flex' => flex,
      'stax' => stax,
      'nanogen5' || 'nanogeneration5' || 'apex' => nanoGen5,
      _ => null,
    };
  }

  // Ledger support: /article/Ledger-Nano-X-Nano-S-Plus-Navigation-Menu-Map
  // and /article/9774032283293-zd. These are name lookup, not rename steps.
  String nameHelp(AppLocalizations l10n) => this == nanoX
      ? l10n.ledgerHelpNanoXName
      : l10n.ledgerHelpOtherModelName(label.replaceFirst('Ledger ', ''));
}

enum _HelpStep { checks, ledger, phone, search }

/// Shared manual recovery inside the existing onboarding/signing surface.
/// The caller retains the device request and owns scan/settings cancellation.
class MobileLedgerConnectionHelp extends StatefulWidget {
  const MobileLedgerConnectionHelp({
    required this.platform,
    required this.onBack,
    required this.onClose,
    required this.onSearch,
    this.initialModel,
    this.pairingInvalid = false,
    this.busy = false,
    this.onSettings,
    this.error,
    super.key,
  });

  final TargetPlatform platform;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final VoidCallback? onSearch;
  final LedgerHelpModel? initialModel;
  final bool pairingInvalid;
  final bool busy;
  final VoidCallback? onSettings;
  final String? error;

  @override
  State<MobileLedgerConnectionHelp> createState() =>
      _MobileLedgerConnectionHelpState();
}

class _MobileLedgerConnectionHelpState
    extends State<MobileLedgerConnectionHelp> {
  late _HelpStep _step = widget.pairingInvalid
      ? _HelpStep.ledger
      : _HelpStep.checks;
  late LedgerHelpModel? _model = widget.initialModel;
  MobileLedgerHelpNavigation? _navigation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = MobileLedgerHelpScope.maybeOf(context);
    if (identical(navigation, _navigation)) return;
    _navigation?.detach(this);
    _navigation = navigation;
    navigation?.attach(this, _previous);
  }

  @override
  void dispose() {
    _navigation?.detach(this);
    super.dispose();
  }

  void _previous() {
    if (widget.busy) return;
    if (_step == _HelpStep.checks ||
        (widget.pairingInvalid && _step == _HelpStep.ledger)) {
      widget.onBack();
    } else {
      setState(() => _step = _HelpStep.values[_step.index - 1]);
    }
  }

  Widget _message(String text, {bool small = false, bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          text,
          style:
              (small
                      ? AppTypography.bodySmall
                      : strong
                      ? AppTypography.bodyMediumStrong
                      : AppTypography.bodyMedium)
                  .copyWith(color: context.colors.text.secondary),
        ),
      );

  Widget _secondary(String label, VoidCallback? action) => AppButton(
    variant: AppButtonVariant.ghost,
    expand: true,
    growWithContent: true,
    constrainContent: true,
    onPressed: widget.busy ? null : action,
    child: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ios = widget.platform == TargetPlatform.iOS;
    final children = <Widget>[
      if (_step != _HelpStep.checks)
        _message(switch (_step) {
          _HelpStep.ledger => l10n.ledgerHelpStepOnLedger('${_step.index}'),
          _HelpStep.phone => l10n.ledgerHelpStepOnPhone('${_step.index}'),
          _ => l10n.ledgerHelpStepBackInVizor('${_step.index}'),
        }, small: true),
    ];
    late final String actionLabel;
    VoidCallback? action;
    switch (_step) {
      case _HelpStep.checks:
        children.addAll([
          _message(l10n.ledgerHelpChecksUnlockClose),
          _message(l10n.ledgerHelpChecksHomeScreen),
          _message(l10n.ledgerHelpChecksCloseOtherApps),
          _message(l10n.ledgerHelpStillNotShowing, strong: true),
          _message(l10n.ledgerHelpTryRestart),
        ]);
        actionLabel = l10n.ledgerSearchAgain;
        action = widget.onSearch;
      case _HelpStep.ledger:
        children.addAll([
          _message(l10n.ledgerHelpRemovePairingOnLedger),
          _message(l10n.ledgerHelpModelLabel, small: true),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.background.neutralSubtleOpacity,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<LedgerHelpModel>(
                  value: _model,
                  isExpanded: true,
                  itemHeight: null,
                  hint: Text(l10n.ledgerHelpChooseModel),
                  dropdownColor: context.colors.background.base,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.accent,
                  ),
                  onChanged: widget.busy
                      ? null
                      : (model) => setState(() => _model = model),
                  items: [
                    for (final model in LedgerHelpModel.values)
                      DropdownMenuItem(
                        value: model,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs,
                          ),
                          child: Text(model.label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_model == null)
            _message(l10n.ledgerHelpSelectModelHint)
          else if (_model == LedgerHelpModel.nanoX) ...[
            _message(l10n.ledgerHelpNanoXControls),
            _message(l10n.ledgerHelpNanoXMenuPath, strong: true),
            _message(l10n.ledgerHelpNanoXConfirm),
          ] else ...[
            _message(l10n.ledgerHelpTouchControls),
            _message(l10n.ledgerHelpTouchMenuPath, strong: true),
          ],
          _message(l10n.ledgerHelpNotResetDevice, small: true),
        ]);
        actionLabel = l10n.ledgerHelpNextPhoneSettings;
        action = _model == null
            ? null
            : () => setState(() => _step = _HelpStep.phone);
      case _HelpStep.phone:
        children.addAll([
          _message(l10n.ledgerHelpFindInPhoneBluetooth),
          _message(l10n.ledgerHelpShortIdName, small: true),
          if (_model != null) _message(_model!.nameHelp(l10n), small: true),
          _message(
            ios ? l10n.ledgerHelpForgetIos : l10n.ledgerHelpForgetAndroid,
            strong: true,
          ),
          _message(l10n.ledgerHelpSkipIfNotListed),
          if (!ios && widget.onSettings != null)
            _secondary(l10n.ledgerHelpOpenBluetoothSettings, widget.onSettings),
        ]);
        actionLabel = l10n.ledgerHelpNextSearchInVizor;
        action = () => setState(() => _step = _HelpStep.search);
      case _HelpStep.search:
        children.addAll([
          _message(l10n.ledgerHelpKeepUnlockedHome),
          _message(l10n.ledgerHelpSearchSelectOpenZcash),
          _message(l10n.ledgerHelpRestartBothGuide, small: true),
        ]);
        actionLabel = l10n.ledgerSearchAgain;
        action = widget.onSearch;
    }
    if (widget.error case final error?) children.add(_message(error));
    return MobileLedgerSheetContent(
      key: ValueKey(_step),
      title: _step == _HelpStep.checks || _step == _HelpStep.search
          ? l10n.ledgerHelpNextSearchTitle
          : l10n.ledgerResetBluetoothPairing,
      onBack: widget.busy ? null : _previous,
      onClose: widget.onClose,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MobileLedgerAction(
            actionLabel,
            onPressed: widget.busy ? null : action,
          ),
          if (_step == _HelpStep.checks)
            _secondary(
              l10n.ledgerResetBluetoothPairing,
              () => setState(() => _step = _HelpStep.ledger),
            ),
        ],
      ),
      children: children,
    );
  }
}
