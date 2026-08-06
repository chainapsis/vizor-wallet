import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_profile_picture_picker_modal.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../import/import_split_view.dart';
import '../keystone/keystone_onboarding_flow.dart';
import '../shared/customise_account_mutation.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'account_persona_generator.dart';
import 'onboarding_split_view.dart';

typedef CustomiseAccountFinishCallback =
    Future<void> Function(String accountName, String profilePictureId);

class CustomiseAccountScreen extends ConsumerStatefulWidget {
  const CustomiseAccountScreen({
    required this.args,
    this.onFinish,
    this.random,
    super.key,
  });

  final CustomiseAccountArgs args;

  /// Optional preview/test seam. Production routes leave this null and use the
  /// account + password transaction owned by this screen.
  final CustomiseAccountFinishCallback? onFinish;

  /// Optional entropy source for deterministic previews and tests.
  final Random? random;

  @override
  ConsumerState<CustomiseAccountScreen> createState() =>
      _CustomiseAccountScreenState();
}

enum _FinishPhase { idle, stoppingSync, creatingWallet }

class _CustomiseAccountScreenState
    extends ConsumerState<CustomiseAccountScreen> {
  late final TextEditingController _nameController;
  late String _profilePictureId;
  var _finishPhase = _FinishPhase.idle;
  String? _submitError;
  var _showProfilePicturePicker = false;

  String get _normalizedName => normalizeAccountName(_nameController.text);
  int get _nameLength => accountNameCharacterLength(_nameController.text);
  bool get _nameValid => isAccountNameLengthValid(_nameController.text);
  bool get _isSubmitting => _finishPhase != _FinishPhase.idle;
  bool get _canFinish => !_isSubmitting && _nameValid;

  String? get _nameMessage {
    if (_submitError != null) return _submitError;
    return _nameLength > kAccountNameMaxCharacters
        ? kAccountNameLengthMessage
        : null;
  }

  @override
  void initState() {
    super.initState();
    final suggestion = generateAccountPersona(random: widget.random);
    _nameController = TextEditingController(text: suggestion.name);
    _profilePictureId = suggestion.profilePictureId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canFinish) return;
    setState(() {
      _finishPhase = _FinishPhase.creatingWallet;
      _submitError = null;
    });

    try {
      final onFinish = widget.onFinish;
      if (onFinish != null) {
        await onFinish(_normalizedName, _profilePictureId);
        if (!mounted) return;
        setState(() => _finishPhase = _FinishPhase.idle);
        return;
      }
      await _finishSetup();
    } catch (e, st) {
      log('CustomiseAccountScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _finishPhase = _FinishPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
    }
  }

  Future<void> _finishSetup() async {
    final args = widget.args;
    final router = GoRouter.of(context);
    final pendingPassword = args.pendingPassword;

    Future<void> createAccount() => runCustomisedAccountMutation(
      ref,
      setupArgs: args.setupArgs,
      accountName: _normalizedName,
      profilePictureId: _profilePictureId,
      deriveFromAccountUuid: args.deriveFromAccountUuid,
      onStoppingSync: () {
        if (!mounted) return;
        setState(() => _finishPhase = _FinishPhase.stoppingSync);
      },
      onSyncPaused: () {
        if (!mounted) return;
        setState(() => _finishPhase = _FinishPhase.creatingWallet);
      },
    );

    final routerRefresh = ref.read(routerRefreshProvider);
    if (pendingPassword == null) {
      // Account creation notifies router dependencies before the explicit
      // home navigation below. Preserve this extra-backed route until both
      // operations complete, including the derive-account path.
      await routerRefresh.pauseWhile(() async {
        await createAccount();
        if (!args.isDeriveFlow) {
          clearCustomisedAccountDraft(ref, args.flow);
        }
        router.go('/home');
      });
      return;
    }

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    var passwordPrepared = false;
    var passwordCommitted = false;
    try {
      await routerRefresh.pauseWhile(() async {
        await securityNotifier.preparePasswordSetup(pendingPassword);
        passwordPrepared = true;
        await createAccount();
        securityNotifier.commitPasswordSetup();
        passwordCommitted = true;
        clearCustomisedAccountDraft(ref, args.flow);
        router.go('/home');
      });
    } catch (_) {
      if (passwordPrepared && !passwordCommitted) {
        try {
          await securityNotifier.rollbackPasswordSetup();
        } catch (rollbackError, rollbackStack) {
          log(
            'CustomiseAccountScreen._finishSetup: '
            'password rollback failed: $rollbackError\n$rollbackStack',
          );
        }
      }
      rethrow;
    }
  }

  void _handleNameChanged(String _) {
    setState(() => _submitError = null);
  }

  void _openProfilePicturePicker() {
    if (_isSubmitting) return;
    setState(() => _showProfilePicturePicker = true);
  }

  void _closeProfilePicturePicker() {
    setState(() => _showProfilePicturePicker = false);
  }

  Future<void> _selectProfilePicture(String profilePictureId) async {
    setState(() {
      _profilePictureId = profilePictureId;
      _showProfilePicturePicker = false;
    });
  }

  OnboardingBackTarget? get _backTarget {
    final args = widget.args;
    if (args.isDeriveFlow) return null;
    if (args.configuresPassword) {
      return OnboardingBackTarget.route(
        label: 'Set Password',
        routePath: switch (args.flow) {
          SetPasswordFlow.create => OnboardingStep.setPassword.routePath,
          SetPasswordFlow.importWallet => '/import/set-password',
          SetPasswordFlow.importKeystone =>
            KeystoneOnboardingStep.setPassword.routePath,
          SetPasswordFlow.importWalletLink => throw StateError(
            'Wallet Link does not use account customisation.',
          ),
        },
        routeExtra: args.setupArgs,
      );
    }
    return OnboardingBackTarget.route(
      label: switch (args.flow) {
        SetPasswordFlow.create => OnboardingStep.secretPassphrase.label,
        SetPasswordFlow.importWallet =>
          ImportOnboardingStep.walletBirthdayHeight.label,
        SetPasswordFlow.importKeystone =>
          KeystoneOnboardingStep.walletBirthdayHeight.label,
        SetPasswordFlow.importWalletLink => throw StateError(
          'Wallet Link does not use account customisation.',
        ),
      },
      routePath: args.setupArgs.backRoutePath,
      routeExtra: args.setupArgs.backRouteExtra,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profilePictureOverlay = _showProfilePicturePicker
        ? AppPaneModalOverlay(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            onDismiss: _closeProfilePicturePicker,
            child: AppProfilePicturePickerModal(
              title: 'Select profile picture',
              currentProfilePictureId: _profilePictureId,
              optionKeyPrefix: 'customise_account_pfp_option_',
              cancelKey: const ValueKey('customise_account_pfp_cancel'),
              actionKey: const ValueKey('customise_account_pfp_update'),
              onCancel: _closeProfilePicturePicker,
              onUpdate: _selectProfilePicture,
            ),
          )
        : null;

    final pane = switch (widget.args.flow) {
      SetPasswordFlow.create => OnboardingTrailingPane(
        backTarget: _isSubmitting ? null : _backTarget,
        overlay: profilePictureOverlay,
        child: _buildContent(),
      ),
      SetPasswordFlow.importWallet => ImportOnboardingTrailingPane(
        backTarget: _isSubmitting ? null : _backTarget,
        overlay: profilePictureOverlay,
        child: _buildContent(),
      ),
      SetPasswordFlow.importKeystone => KeystoneOnboardingTrailingPane(
        backTarget: _isSubmitting ? null : _backTarget,
        overlay: profilePictureOverlay,
        child: _buildContent(),
      ),
      SetPasswordFlow.importWalletLink => throw StateError(
        'Wallet Link does not use account customisation.',
      ),
    };
    return pane;
  }

  Widget _buildContent() => _CustomiseAccountContent(
    nameController: _nameController,
    profilePictureId: _profilePictureId,
    nameMessage: _nameMessage,
    finishPhase: _finishPhase,
    canFinish: _canFinish,
    onNameChanged: _handleNameChanged,
    onEditProfilePicture: _openProfilePicturePicker,
    onFinish: _submit,
  );
}

class _CustomiseAccountContent extends StatelessWidget {
  const _CustomiseAccountContent({
    required this.nameController,
    required this.profilePictureId,
    required this.nameMessage,
    required this.finishPhase,
    required this.canFinish,
    required this.onNameChanged,
    required this.onEditProfilePicture,
    required this.onFinish,
  });

  final TextEditingController nameController;
  final String profilePictureId;
  final String? nameMessage;
  final _FinishPhase finishPhase;
  final bool canFinish;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onEditProfilePicture;
  final Future<void> Function() onFinish;

  static const _contentWidth = 396.0;
  static const _sectionGap = 32.0;
  static const _buttonMinWidth = 196.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: _contentWidth,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _CustomiseAccountTitle(),
                    const SizedBox(height: _sectionGap),
                    _AccountProfileCard(
                      nameController: nameController,
                      profilePictureId: profilePictureId,
                      message: nameMessage,
                      enabled: finishPhase == _FinishPhase.idle,
                      onNameChanged: onNameChanged,
                      onEditProfilePicture: onEditProfilePicture,
                      onSubmitted: onFinish,
                    ),
                  ],
                ),
              ),
            ),
            AppButton(
              key: const ValueKey('customise_account_finish_button'),
              onPressed: canFinish ? onFinish : null,
              minWidth: _buttonMinWidth,
              trailing: const AppIcon(AppIcons.chevronForward),
              child: Text(switch (finishPhase) {
                _FinishPhase.idle => 'Finish setup',
                _FinishPhase.stoppingSync => 'Stop syncing...',
                _FinishPhase.creatingWallet => 'Creating wallet...',
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomiseAccountTitle extends StatelessWidget {
  const _CustomiseAccountTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Customise Account',
            textAlign: TextAlign.center,
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 308,
          child: Text(
            'Add personality to your account by setting an account name and '
            'choosing a profile picture.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountProfileCard extends StatelessWidget {
  const _AccountProfileCard({
    required this.nameController,
    required this.profilePictureId,
    required this.message,
    required this.enabled,
    required this.onNameChanged,
    required this.onEditProfilePicture,
    required this.onSubmitted,
  });

  final TextEditingController nameController;
  final String profilePictureId;
  final String? message;
  final bool enabled;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onEditProfilePicture;
  final Future<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    return SizedBox(
      height: 140,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: const ValueKey('customise_account_card'),
            width: 396,
            height: 140,
            padding: const EdgeInsets.symmetric(horizontal: 27),
            decoration: BoxDecoration(
              color: colors.background.homeCard,
              borderRadius: BorderRadius.circular(AppRadii.large),
            ),
            child: Row(
              children: [
                _EditableProfilePicture(
                  profilePictureId: profilePictureId,
                  enabled: enabled,
                  onPressed: onEditProfilePicture,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account name',
                        style: AppTypography.labelLarge.copyWith(
                          color: cardTextColor.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 40,
                        child: TextField(
                          key: const ValueKey('customise_account_name_field'),
                          controller: nameController,
                          enabled: enabled,
                          maxLines: 1,
                          textInputAction: TextInputAction.done,
                          style: AppTypography.headlineMedium.copyWith(
                            color: cardTextColor,
                          ),
                          cursorColor: cardTextColor,
                          cursorWidth: 2,
                          cursorHeight: 28,
                          cursorRadius: const Radius.circular(AppRadii.full),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onChanged: onNameChanged,
                          onSubmitted: (_) => onSubmitted(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (message != null)
            Positioned(
              top: 164,
              left: 0,
              right: 0,
              child: Text(
                message!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditableProfilePicture extends StatelessWidget {
  const _EditableProfilePicture({
    required this.profilePictureId,
    required this.enabled,
    required this.onPressed,
  });

  final String profilePictureId;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Change profile picture',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          key: const ValueKey('customise_account_avatar_button'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AppProfilePicture(
                  profilePictureId: profilePictureId,
                  size: AppProfilePictureSize.xLarge,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colors.text.homeCard,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.background.homeCard,
                        width: 3,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.edit,
                        size: 16,
                        color: colors.background.homeCard,
                      ),
                    ),
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
