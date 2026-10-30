import 'package:flutter/material.dart'
    show
        DropdownButton,
        DropdownButtonHideUnderline,
        DropdownMenuItem,
        Material,
        MaterialType;
import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import 'mobile_ledger_help_navigation.dart';
import 'mobile_ledger_sheet_content.dart';

enum LedgerHelpModel {
  nanoX('Ledger Nano X'),
  flex('Ledger Flex'),
  stax('Ledger Stax'),
  nanoGen5('Ledger Nano Gen5');

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
  String get nameHelp => this == nanoX
      ? 'On your Nano X, hold both buttons for 2 seconds, then find Device Name.'
      : 'On your ${label.replaceFirst('Ledger ', '')}, check Settings > Name.';
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
    final ios = widget.platform == TargetPlatform.iOS;
    final children = <Widget>[
      if (_step != _HelpStep.checks)
        _message(
          'Step ${_step.index} of 3 · ${switch (_step) {
            _HelpStep.ledger => 'On your Ledger',
            _HelpStep.phone => 'On your phone',
            _ => 'Back in Vizor',
          }}',
          small: true,
        ),
    ];
    late final String actionLabel;
    VoidCallback? action;
    switch (_step) {
      case _HelpStep.checks:
        children.addAll([
          _message(
            'Unlock Ledger, turn on Bluetooth, and keep it close to your phone.',
          ),
          _message(
            'Leave Ledger on its home screen. Open the Zcash app when Vizor asks.',
          ),
          _message(
            'Close other wallet apps and disconnect Ledger from other phones or computers.',
          ),
          _message('Still not showing?', strong: true),
          _message(
            'Try restarting Ledger. If it stays missing, removing the saved Bluetooth pairing on both devices may help.',
          ),
        ]);
        actionLabel = 'Search again';
        action = widget.onSearch;
      case _HelpStep.ledger:
        children.addAll([
          _message(
            'Remove the saved pairing on Ledger, then remove it on your phone.',
          ),
          _message('Ledger model', small: true),
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
                  hint: const Text('Choose your model'),
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
            _message(
              'Select your model to see its pairing removal instructions.',
            )
          else if (_model == LedgerHelpModel.nanoX) ...[
            _message(
              'Unlock Ledger. Hold both buttons to open its controls, then choose:',
            ),
            _message('Settings > Security > Reset pairings', strong: true),
            _message('Confirm on Ledger and enter your PIN on the device.'),
          ] else ...[
            _message(
              'Unlock Ledger. From its home screen, tap the settings icon, then choose:',
            ),
            _message('Bluetooth > Remove pairing', strong: true),
          ],
          _message(
            'Use the Bluetooth pairing option, not Reset device. Your wallet and accounts stay unchanged.',
            small: true,
          ),
        ]);
        actionLabel = 'Next: phone settings';
        action = _model == null
            ? null
            : () => setState(() => _step = _HelpStep.phone);
      case _HelpStep.phone:
        children.addAll([
          _message('Find your Ledger in your phone’s Bluetooth settings.'),
          _message(
            'If you haven’t named your Ledger, it may appear as a short ID, such as 01AB. Otherwise, look for the name you set.',
            small: true,
          ),
          if (_model != null) _message(_model!.nameHelp, small: true),
          _message(
            ios
                ? 'Settings > Bluetooth > the info button next to your Ledger > Forget This Device'
                : 'Bluetooth settings > the settings button next to your Ledger > Forget or Unpair',
            strong: true,
          ),
          _message('If Ledger is not listed, skip this step and continue.'),
          if (!ios && widget.onSettings != null)
            _secondary('Open Bluetooth settings', widget.onSettings),
        ]);
        actionLabel = 'Next: search in Vizor';
        action = () => setState(() => _step = _HelpStep.search);
      case _HelpStep.search:
        children.addAll([
          _message(
            'Keep Ledger unlocked with Bluetooth on, and leave it on its home screen.',
          ),
          _message(
            'Search in Vizor and select your Ledger. Open the Zcash app when Vizor asks.',
          ),
          _message(
            'If it still does not appear, restart both devices and check Ledger’s official Bluetooth troubleshooting guide.',
            small: true,
          ),
        ]);
        actionLabel = 'Search again';
        action = widget.onSearch;
    }
    if (widget.error case final error?) children.add(_message(error));
    return MobileLedgerSheetContent(
      key: ValueKey(_step),
      title: _step == _HelpStep.checks || _step == _HelpStep.search
          ? 'Find your Ledger'
          : 'Reset Bluetooth pairing',
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
              'Reset Bluetooth pairing',
              () => setState(() => _step = _HelpStep.ledger),
            ),
        ],
      ),
      children: children,
    );
  }
}
