import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../accounts/widgets/mobile/account_edit_sheets.dart'
    show showProfilePictureSheet;
import '../create/account_persona_generator.dart';
import '../create/onboarding_split_view.dart'
    show clearCreateOnboardingSecretState;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_scaffold.dart';

typedef MobileCustomiseAccountFinishCallback =
    Future<void> Function(String accountName, String profilePictureId);

/// Mobile create-account personalisation — Figma light/dark default frames
/// 6125:117635 / 6132:117807 and keyboard/error frames 6125:117233 /
/// 6132:117773.
class MobileCustomiseAccountScreen extends ConsumerStatefulWidget {
  const MobileCustomiseAccountScreen({
    required this.args,
    this.onFinish,
    this.random,
    super.key,
  });

  final CustomiseAccountArgs args;

  /// Preview/test seam. Production routes own account and password mutation.
  final MobileCustomiseAccountFinishCallback? onFinish;

  /// Optional entropy source for deterministic previews and tests.
  final Random? random;

  @override
  ConsumerState<MobileCustomiseAccountScreen> createState() =>
      _MobileCustomiseAccountScreenState();
}

enum _SubmitPhase { idle, stoppingSync, creatingWallet }

class _MobileCustomiseAccountScreenState
    extends ConsumerState<MobileCustomiseAccountScreen> {
  late final TextEditingController _nameController;
  final _nameFocusNode = FocusNode();
  late String _profilePictureId;
  var _submitPhase = _SubmitPhase.idle;
  String? _submitError;

  String get _normalizedName => normalizeAccountName(_nameController.text);
  int get _nameLength => accountNameCharacterLength(_nameController.text);
  bool get _nameValid => isAccountNameLengthValid(_nameController.text);
  bool get _isSubmitting => _submitPhase != _SubmitPhase.idle;
  bool get _canContinue => !_isSubmitting && _nameValid;

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
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _goBack() async {
    if (_isSubmitting) return;
    final args = widget.args;
    final router = GoRouter.maybeOf(context);
    if (args.configuresPassword) {
      if (router != null) {
        router.go(
          '/onboarding/set-passcode',
          extra: SetPasswordScreenArgs.create(mnemonic: args.mnemonic),
        );
      } else {
        await Navigator.of(context).maybePop();
      }
      return;
    }
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted && router != null) {
      router.go(
        '/onboarding/secret-passphrase',
        extra: CreateSecretPassphraseArgs(mnemonic: args.mnemonic),
      );
    }
  }

  void _handleNameChanged(String _) {
    setState(() => _submitError = null);
  }

  Future<void> _pickProfilePicture() async {
    if (_isSubmitting) return;
    _nameFocusNode.unfocus();
    final selected = await showProfilePictureSheet(
      context,
      selectedId: _profilePictureId,
    );
    if (selected != null && mounted) {
      setState(() => _profilePictureId = selected);
    }
  }

  Future<void> _submit() async {
    if (!_canContinue) return;
    _nameFocusNode.unfocus();
    setState(() {
      _submitPhase = _SubmitPhase.creatingWallet;
      _submitError = null;
    });

    try {
      final onFinish = widget.onFinish;
      if (onFinish != null) {
        await onFinish(_normalizedName, _profilePictureId);
        if (mounted) setState(() => _submitPhase = _SubmitPhase.idle);
        return;
      }
      await _finishSetup();
    } catch (e, st) {
      log('MobileCustomiseAccount._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _SubmitPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
    }
  }

  Future<void> _finishSetup() async {
    final args = widget.args;
    final router = GoRouter.of(context);
    final accountNotifier = ref.read(accountProvider.notifier);

    Future<void> createAccount() => runWithSyncPausedForAccountMutation(
      ref,
      () => accountNotifier.createAccountFromMnemonic(
        mnemonic: args.mnemonic,
        name: _normalizedName,
        profilePictureId: _profilePictureId,
      ),
      onStoppingSync: () {
        if (mounted) {
          setState(() => _submitPhase = _SubmitPhase.stoppingSync);
        }
      },
      onSyncPaused: () {
        if (mounted) {
          setState(() => _submitPhase = _SubmitPhase.creatingWallet);
        }
      },
    );

    final pendingPassword = args.pendingPassword;
    if (pendingPassword == null) {
      await createAccount();
      clearCreateOnboardingSecretState(ref.read);
      router.go('/home');
      return;
    }

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var passwordPrepared = false;
    var passwordCommitted = false;
    try {
      await routerRefresh.pauseWhile(() async {
        await securityNotifier.preparePasswordSetup(pendingPassword);
        passwordPrepared = true;
        await createAccount();
        securityNotifier.commitPasswordSetup();
        passwordCommitted = true;
        clearCreateOnboardingSecretState(ref.read);
        router.go('/onboarding/biometrics');
      });
    } catch (_) {
      if (passwordPrepared && !passwordCommitted) {
        try {
          await securityNotifier.rollbackPasswordSetup();
        } catch (rollbackError, rollbackStack) {
          log(
            'MobileCustomiseAccount._finishSetup: password rollback failed: '
            '$rollbackError\n$rollbackStack',
          );
        }
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(8),
      onBack: _isSubmitting ? null : _goBack,
      title: 'Customise Account',
      subtitle:
          'Add personality to your account by setting an account name and '
          'choosing a profile picture.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_customise_account_continue'),
        expand: true,
        constrainContent: true,
        onPressed: _canContinue ? _submit : null,
        trailing: const AppIcon(AppIcons.chevronForward),
        child: Text(switch (_submitPhase) {
          _SubmitPhase.idle => 'Continue',
          _SubmitPhase.stoppingSync => 'Stop syncing...',
          _SubmitPhase.creatingWallet => 'Creating wallet...',
        }),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          _AccountProfileCard(
            nameController: _nameController,
            nameFocusNode: _nameFocusNode,
            profilePictureId: _profilePictureId,
            message: _nameMessage,
            enabled: !_isSubmitting,
            onNameChanged: _handleNameChanged,
            onEditProfilePicture: _pickProfilePicture,
            onSubmitted: _submit,
          ),
        ],
      ),
    );
  }
}

class _AccountProfileCard extends StatelessWidget {
  const _AccountProfileCard({
    required this.nameController,
    required this.nameFocusNode,
    required this.profilePictureId,
    required this.message,
    required this.enabled,
    required this.onNameChanged,
    required this.onEditProfilePicture,
    required this.onSubmitted,
  });

  final TextEditingController nameController;
  final FocusNode nameFocusNode;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('mobile_customise_account_card'),
          height: 123,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(AppRadii.xLarge),
          ),
          child: Row(
            children: [
              _EditableProfilePicture(
                profilePictureId: profilePictureId,
                enabled: enabled,
                onPressed: onEditProfilePicture,
              ),
              const SizedBox(width: AppSpacing.sm),
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
                      height: 30,
                      child: TextField(
                        key: const ValueKey(
                          'mobile_customise_account_name_field',
                        ),
                        controller: nameController,
                        focusNode: nameFocusNode,
                        enabled: enabled,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        style: AppTypography.headlineSmall.copyWith(
                          color: cardTextColor,
                        ),
                        cursorColor: cardTextColor,
                        cursorWidth: 2,
                        cursorHeight: 22,
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
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
      ],
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
      child: GestureDetector(
        key: const ValueKey('mobile_customise_account_avatar_button'),
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
                right: -6,
                bottom: -6,
                child: Container(
                  key: const ValueKey('mobile_customise_account_edit_badge'),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.text.homeCard,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.background.homeCard,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: _CustomiseAccountEditGlyph(
                      color: colors.background.homeCard,
                    ),
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

class _CustomiseAccountEditGlyph extends StatelessWidget {
  const _CustomiseAccountEditGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Keep the dark-variant 20px edit frame, but leave more breathing room
    // around this icon asset because its filled bounds read larger on-device.
    return SizedBox(
      key: const ValueKey('mobile_customise_account_edit_glyph_frame'),
      width: 20,
      height: 20,
      child: Center(
        child: AppIcon(
          key: const ValueKey('mobile_customise_account_edit_glyph'),
          AppIcons.editFilled,
          size: 12,
          color: color,
        ),
      ),
    );
  }
}
